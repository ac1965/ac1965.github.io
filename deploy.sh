#!/usr/bin/env zsh
# deploy.sh — Build Hugo site and push public/ to GitHub
# Usage: ./deploy.sh [--dry-run] [--skip-cover] [--force]
set -euo pipefail
setopt nullglob        # マッチしないグロブは空文字列に展開（bashのnullglob相当）
setopt extended_glob    # (N)修飾子等を使うため

# ─────────────────────────────────────────
# Logging helpers
# ─────────────────────────────────────────
# NOTE: これらは他の全ての関数・処理より前に定義すること。
# zshも関数呼び出しは実行時解決のため、定義前に呼ぶと失敗する。
abort() {
	echo -e "\033[1;30m>\033[0;31m>\033[1;31m> ERROR:\033[0m ${*}\n" >&2
	exit 1
}
info() { echo -e "\033[1;30m>\033[0;36m>\033[1;36m> \033[0m${*}"; }
warn() { echo -e "\033[1;30m>\033[0;33m>\033[1;33m> \033[0m${*}"; }
step() { echo -e "\n\033[1;35m==> \033[0m${*}"; }

# 想定外のエラーで即座に中断し、行番号を出す（デバッグ容易化）
trap 'echo -e "\033[1;31m> UNEXPECTED ERROR\033[0m at line ${LINENO} (exit ${?})" >&2' ERR

# zshの関数内では $0 が「関数名」に置き換わり、スクリプト名を取れなくなる
# （bashとの挙動差）。そのためトップレベルのうちに退避しておく。
readonly SCRIPT_NAME="${0:t}"

# ─────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────
# PROJECTS_ROOT: サイトルート（mysite/, deploy/ の親ディレクトリ）
#   重要: iCloud Drive（デスクトップと書類フォルダの同期）配下は避けること。
#   同期競合により "cover 2.jpg" のような幽霊ファイルが生成され、
#   カバー画像の誤配置バグの温床になることが判明している。
#
#   プロジェクトごとに値が変わるため、環境変数のexportには頼らず、
#   このスクリプト自身の設置場所（${HUGO_DIR}/deploy.sh 想定）から
#   自動算出する。PROJECTS_ROOT を明示的にexportした場合はそちらを優先する
#   （CI環境や一時的な上書きのための逃げ道として残す）。
#
#   ${0:A}   … このスクリプトの絶対パス
#   ${0:A:h} … その1つ上（= mysite/ ディレクトリ）
#   ${0:A:h:h} … さらに1つ上（= PROJECTS_ROOT。例: ~/Projects/blog）
readonly PROJECTS_ROOT="${PROJECTS_ROOT:-${0:A:h:h}}"
readonly HUGO_DIR="${PROJECTS_ROOT}/mysite"
readonly PUBLIC_DIR="${PROJECTS_ROOT}/deploy"
readonly CONTENT_POST_DIR="${HUGO_DIR}/content/post"
readonly COVER_EXT="jpg"

# カバー画像の優先順位付きフォールバックチェーン（高→低）
#   Tier 0: post_dir に cover.* が既に存在する場合はスキップ（既存の冪等性ガード、下記ループ内）
#   Tier 1: front matterの cover: 明示指定 → COVER_SRC_DIR 基準の相対パス、または絶対パス
#   Tier 2: COVER_TAG_DIR/<tag>/*.${COVER_EXT} からハッシュで決定的に1枚選択
#   Tier 3: COVER_SEASONAL_DIR/<group>.${COVER_EXT}（旧構成 COVER_SRC_DIR/<group>.${COVER_EXT} も後方互換で参照）
#   Tier 4: COVER_DEFAULT。ここまで来て解決しない場合の最終フォールバック（原則ここには来ない想定）
readonly COVER_SRC_DIR="${HUGO_DIR}/assets/img/cover"
readonly COVER_TAG_DIR="${COVER_SRC_DIR}/tags"
readonly COVER_SEASONAL_DIR="${COVER_SRC_DIR}/seasonal"
readonly COVER_DEFAULT="${COVER_SRC_DIR}/default.${COVER_EXT}"

DRY_RUN=false
SKIP_COVER=false
FORCE=false

# ─────────────────────────────────────────
# Utilities
# ─────────────────────────────────────────

# 月番号を季節カバーグループへ変換（4ヶ月周期で3グループを循環）
# 01,05,09月 → group 01 / 02,06,10月 → group 02 / ...
cover_month() {
	local month="${1}"
	case "${month}" in
	01 | 02 | 03) echo "01" ;;
	04 | 05 | 06) echo "02" ;;
	07 | 08 | 09) echo "03" ;;
	10 | 11 | 12) echo "04" ;;
	*) abort "Invalid month: ${month}" ;;
	esac
}

# 記事のfront matterから公開月（MM）を取得する。
# YAML (`date: 2026-01-05T...`) / TOML (`date = 2026-01-05T...`) の
# どちらの記法にも対応。date/publishDateどちらのキーも許容。
# パース不能な場合は空文字を返す（呼び出し側で「スキップ」判断させる。
# 実行時月へのフォールバックは行わない — 全記事が同一カバーになる
# バグの再発防止のため、安全側に倒して「処理しない」を選ぶ）。
post_month() {
	local md_file="${1}"
	local date_line month

	date_line="$(grep -m1 -E '^(date|publishDate)[[:space:]]*[:=]' "${md_file}" 2>/dev/null || true)"

	if [[ -n "${date_line}" ]]; then
		month="$(echo "${date_line}" | grep -oE '[0-9]{4}-[0-9]{2}' | head -1 | cut -d'-' -f2)"
	fi

	echo "${month:-}"
}

# Tier 1: front matterの cover: (YAML) / cover = (TOML) 明示指定を取得する。
# 指定が無ければ空文字を返す。パスの実在チェックは呼び出し側で行う
# （存在しない指定は「警告して次のTierへフォールスルー」させる設計のため、
#  ここでは abort しない）。
post_front_matter_cover() {
	local md_file="${1}"
	# 注意: zshでは "path" は $PATH に紐付けられた特殊パラメータ。
	# ここで "local path" を宣言すると関数内で $PATH が空になり、
	# grep/sed 等の外部コマンド呼び出しが軒並み無言で失敗する
	# （"2>/dev/null || true" で握りつぶされるため気付きにくい）。
	# そのため変数名は cover_path とし、path という名前は避ける。
	local line cover_path

	line="$(grep -m1 -E '^cover[[:space:]]*[:=]' "${md_file}" 2>/dev/null || true)"
	[[ -z "${line}" ]] && { echo ""; return; }

	# "cover:" / "cover =" の右辺だけを取り出し、前後の引用符を除去
	cover_path="$(echo "${line}" | sed -E 's/^cover[[:space:]]*[:=][[:space:]]*//; s/^["'\'']//; s/["'\'']$//')"
	[[ -z "${cover_path}" ]] && { echo ""; return; }

	# 絶対パス指定はそのまま、相対パスは COVER_SRC_DIR 基準で解決する
	if [[ "${cover_path}" == /* ]]; then
		echo "${cover_path}"
	else
		echo "${COVER_SRC_DIR}/${cover_path}"
	fi
}

# front matterの tags: (YAML配列 or ブロックリスト) / TOML配列からタグ一覧を
# 空白区切りの文字列として返す。前後の引用符・空白は簡易的に除去する。
# ox-hugoが出す代表的な2形式（インライン配列 / ブロックリスト）のみ対応。
# それ以外の記法（複雑なYAML）は非対応 — 検出できなければ単に空を返し、
# 呼び出し側（select_tag_cover）はTier2をスキップして次のTierへ進む。
post_tags() {
	local md_file="${1}"
	local -a tags
	local line

	# インライン配列: tags: ["a", "b"]  /  tags = ["a", "b"]
	line="$(grep -m1 -E '^tags[[:space:]]*[:=][[:space:]]*\[' "${md_file}" 2>/dev/null || true)"
	if [[ -n "${line}" ]]; then
		local inner
		inner="${line#*\[}"
		inner="${inner%%\]*}"
		tags=("${(@s/,/)inner}")
		tags=("${(@)tags// /}")
		tags=("${(@)tags//[\"\']/}")
	else
		# ブロックリスト形式:
		#   tags:
		#     - a
		#     - b
		local in_block=false v
		while IFS= read -r line; do
			if [[ "${in_block}" == true ]]; then
				if [[ "${line}" =~ ^[[:space:]]*-[[:space:]]*(.+)$ ]]; then
					v="${match[1]}"
					v="${v//[\"\']/}"
					tags+=("${v}")
					continue
				fi
				# インデントされた行が続かなくなったらブロック終了
				[[ "${line}" =~ ^[[:space:]] ]] && continue
				break
			elif [[ "${line}" =~ ^tags:[[:space:]]*$ ]]; then
				in_block=true
			fi
		done < "${md_file}"
	fi

	echo "${tags[@]}"
}

# Tier 2: post_tags() が返すタグを front matter に書かれた順で走査し、
# COVER_TAG_DIR/<tag>/ の中身が空でない「最初に一致したタグ」だけを
# 候補プールとして採用する（複数タグの画像を混ぜない）。
# プール内の選択はハッシュ（記事名の cksum）を候補数で割った余りで決める
# 完全ステートレスな方式 — 使用履歴ファイルは持たない。
# 同じ記事名なら常に同じ画像になる（rebuild-safe）。
select_tag_cover() {
	local md_file="${1}" post_name="${2}"
	local -a tags pool
	tags=(${(z)"$(post_tags "${md_file}")"})

	local tag dir
	for tag in "${tags[@]}"; do
		[[ -z "${tag}" ]] && continue
		dir="${COVER_TAG_DIR}/${tag}"
		[[ -d "${dir}" ]] || continue
		pool=("${dir}"/*.${COVER_EXT}(N))
		(( ${#pool[@]} > 0 )) && break
	done

	(( ${#pool[@]} == 0 )) && { echo ""; return; }

	# ディレクトリのinode順に依存させないよう、名前の昇順に確定ソート
	pool=("${(@o)pool}")

	local hash_num idx
	hash_num="$(print -n -- "${post_name}" | cksum | awk '{print $1}')"
	idx=$(( hash_num % ${#pool[@]} + 1 ))   # zshの配列は1始まり
	echo "${pool[${idx}]}"
}

require_cmd() {
	command -v "${1}" &>/dev/null || abort "'${1}' is not installed or not in PATH."
}

usage() {
	echo "Usage: ${SCRIPT_NAME} [--dry-run] [--skip-cover] [--force]"
	echo "  --dry-run     Run hugo build but skip git push"
	echo "  --skip-cover  Skip cover image placement"
	echo "  --force       Proceed even if sync-conflict-like files are detected"
}

# ─────────────────────────────────────────
# Argument parsing
# ─────────────────────────────────────────
parse_args() {
	local arg
	for arg in "$@"; do
		case "${arg}" in
		--dry-run) DRY_RUN=true ;;
		--skip-cover) SKIP_COVER=true ;;
		--force) FORCE=true ;;
		--help | -h)
			usage
			exit 0
			;;
		*)
			abort "Unknown option: ${arg} (see --help)"
			;;
		esac
	done
}

# ─────────────────────────────────────────
# Pre-flight checks
# ─────────────────────────────────────────
preflight_checks() {
	step "Pre-flight checks"
	info "PROJECTS_ROOT = ${PROJECTS_ROOT}"
	require_cmd hugo
	require_cmd git
	require_cmd rsync

	[[ -d "${HUGO_DIR}" ]] || abort "Hugo site directory not found: ${HUGO_DIR}"
	[[ -d "${PUBLIC_DIR}" ]] || abort "Deploy directory not found: ${PUBLIC_DIR}"

	# iCloud等の同期デーモンが作る典型的な競合コピー名を検出する。
	# 例: "cover 2.jpg" / "index 2.md" / "foo 3.png"
	# これに気づかず処理を続けると、カバー検出ロジックが誤判定し、
	# 季節画像の二重配置・意図しない上書きにつながる。
	local -a suspects
	suspects=("${CONTENT_POST_DIR}"/**/*[[:space:]][0-9].*(N))

	if (( ${#suspects[@]} > 0 )); then
		warn "同期競合コピーの可能性があるファイルを検出しました:"
		local s
		for s in "${suspects[@]}"; do
			warn "  ${s}"
		done
		if [[ "${FORCE}" == false ]]; then
			abort "上記を確認・削除してから再実行するか、--force で強制続行してください。"
		else
			warn "--force が指定されているため、検出のみ行い処理を続行します。"
		fi
	fi
}

# ─────────────────────────────────────────
# Place cover images
# ─────────────────────────────────────────
place_covers() {
	if [[ "${SKIP_COVER}" == true ]]; then
		return 0
	fi

	step "Placing cover images"

	# Tier 4（デフォルト）は必ず解決できる必要があるため、無ければここで
	# 即中断する（ループの途中で発覚させない。require_cmd等と同じ思想）。
	[[ -f "${COVER_DEFAULT}" ]] || abort "Default cover not found: ${COVER_DEFAULT}"

	# Tier 3（季節グループ）用キャッシュ（同じグループを何度もディスク
	# チェックしないための連想配列。zshネイティブ）
	local -A seasonal_cache

	# zshネイティブのグロブでmdファイルを配列取得（bashのfind+read -d''をglob修飾子に置換）
	local -a md_files
	md_files=("${CONTENT_POST_DIR}"/*.md(N))

	local md_file post_name post_dir month cover_group cover_file seasonal_file tier
	local -a existing_covers
	for md_file in "${md_files[@]}"; do
		post_name="${md_file:t:r}"   # basename、拡張子除去（zsh modifier）
		post_dir="${CONTENT_POST_DIR}/${post_name}"

		# Ensure post directory exists
		[[ -d "${post_dir}" ]] || mkdir -p "${post_dir}"

		# Tier 0: 既存カバーの検出。"cover.jpg" のような正規のパターンに加え、
		# "cover 2.jpg" / "cover-2.jpg" のような亜種も「既存扱い」にして、
		# 画像の二重コピーを防ぐ（対策Bをすり抜けた場合の保険）。
		# ここで確定済みとみなし、以降のTierは一切評価しない（冪等性優先）。
		existing_covers=("${post_dir}"/cover.*(N) "${post_dir}"/cover[-_\ ]*(N))
		if (( ${#existing_covers[@]} > 0 )); then
			continue
		fi

		cover_file=""
		tier=""

		# Tier 1: front matter明示指定
		cover_file="$(post_front_matter_cover "${md_file}")"
		if [[ -n "${cover_file}" ]]; then
			if [[ -f "${cover_file}" ]]; then
				tier="明示指定"
			else
				warn "  ${post_name}: front matterのcover指定が見つかりません: ${cover_file} → 次のTierへ"
				cover_file=""
			fi
		fi

		# Tier 2: タグ別ライブラリから決定的に選択
		if [[ -z "${cover_file}" ]]; then
			cover_file="$(select_tag_cover "${md_file}" "${post_name}")"
			[[ -n "${cover_file}" ]] && tier="タグ一致"
		fi

		# Tier 3: 季節グループ（記事自身の公開月から決定。deploy実行月ではない）
		if [[ -z "${cover_file}" ]]; then
			month="$(post_month "${md_file}")"
			if [[ -n "${month}" ]]; then
				cover_group="$(cover_month "${month}")"
				if [[ -z "${seasonal_cache[${cover_group}]:-}" ]]; then
					if [[ -f "${COVER_SEASONAL_DIR}/${cover_group}.${COVER_EXT}" ]]; then
						seasonal_file="${COVER_SEASONAL_DIR}/${cover_group}.${COVER_EXT}"
					else
						# 旧構成（seasonal/未移行）との後方互換
						seasonal_file="${COVER_SRC_DIR}/${cover_group}.${COVER_EXT}"
					fi
					[[ -f "${seasonal_file}" ]] || abort "Seasonal cover not found: ${seasonal_file}"
					seasonal_cache[${cover_group}]="${seasonal_file}"
				fi
				cover_file="${seasonal_cache[${cover_group}]}"
				tier="季節(${month}月→group${cover_group})"
			fi
		fi

		# Tier 4: デフォルト（ここまで来て解決しない場合の最終フォールバック）
		if [[ -z "${cover_file}" ]]; then
			cover_file="${COVER_DEFAULT}"
			tier="デフォルト"
		fi

		cp "${cover_file}" "${post_dir}/cover.${COVER_EXT}"
		info "  ${post_name} → [${tier}] ${cover_file:t}"
	done
}

# ─────────────────────────────────────────
# Hugo build
# ─────────────────────────────────────────
build_site() {
	step "Building site with Hugo"
	cd "${HUGO_DIR}"

	# Clean previous build
	rm -rf public

	hugo --minify || abort "Hugo build failed."
	info "Build complete: $(find public -type f | wc -l | tr -d ' ') files generated."
}

# ─────────────────────────────────────────
# Deploy
# ─────────────────────────────────────────
sync_deploy_dir() {
	step "Syncing to deploy directory"
	rsync -a --delete --checksum --exclude=".git" "${HUGO_DIR}/public/" "${PUBLIC_DIR}/"
}

commit_and_push() {
	step "Committing and pushing to GitHub"
	cd "${PUBLIC_DIR}"

	git add --all

	if git diff --cached --quiet; then
		warn "Nothing to commit — deploy directory is up to date."
		return 0
	fi

	local commit_msg
	commit_msg="deploy: $(LC_ALL=C date '+%Y-%m-%dT%H:%M:%S%z')"
	git commit -m "${commit_msg}"
	git push

	info "✓ Deployed successfully: ${commit_msg}"
}

# ─────────────────────────────────────────
# Main
# ─────────────────────────────────────────
main() {
	parse_args "$@"
	preflight_checks
	place_covers
	build_site

	if [[ "${DRY_RUN}" == true ]]; then
		warn "Dry-run mode: skipping rsync and git push."
		exit 0
	fi

	sync_deploy_dir
	commit_and_push
}

main "$@"
