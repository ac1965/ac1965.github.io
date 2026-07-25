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
readonly COVER_SRC_DIR="${HUGO_DIR}/assets/img/cover"
readonly CONTENT_POST_DIR="${HUGO_DIR}/content/post"
readonly COVER_EXT="jpg"

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
	01 | 05 | 09) echo "01" ;;
	02 | 06 | 10) echo "02" ;;
	03 | 07 | 11) echo "03" ;;
	04 | 08 | 12) echo "04" ;;
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

	# グループごとのカバーファイルパスをキャッシュ（同じグループを何度も
	# ディスクチェックしないための連想配列。zshネイティブ）
	local -A cover_cache

	# zshネイティブのグロブでmdファイルを配列取得（bashのfind+read -d''をglob修飾子に置換）
	local -a md_files
	md_files=("${CONTENT_POST_DIR}"/*.md(N))

	local md_file post_name post_dir month cover_group cover_file
	local -a existing_covers skipped_posts
	for md_file in "${md_files[@]}"; do
		post_name="${md_file:t:r}"   # basename、拡張子除去（zsh modifier）
		post_dir="${CONTENT_POST_DIR}/${post_name}"

		# Ensure post directory exists
		[[ -d "${post_dir}" ]] || mkdir -p "${post_dir}"

		# 既存カバーの検出。"cover.jpg" のような正規のパターンに加え、
		# "cover 2.jpg" / "cover-2.jpg" のような亜種も「既存扱い」にして、
		# 季節画像の二重コピーを防ぐ（対策Bをすり抜けた場合の保険）。
		existing_covers=("${post_dir}"/cover.*(N) "${post_dir}"/cover[-_\ ]*(N))
		if (( ${#existing_covers[@]} > 0 )); then
			continue
		fi

		# 記事自身の公開月からカバーグループを決定（deploy実行月ではない）。
		# 取得できない場合は「実行時月へのフォールバック」をせず、
		# このカバー配置を丸ごとスキップして最後にまとめて警告する。
		month="$(post_month "${md_file}")"
		if [[ -z "${month}" ]]; then
			skipped_posts+=("${post_name}")
			continue
		fi
		cover_group="$(cover_month "${month}")"

		if [[ -z "${cover_cache[${cover_group}]:-}" ]]; then
			cover_file="${COVER_SRC_DIR}/${cover_group}.${COVER_EXT}"
			[[ -f "${cover_file}" ]] || abort "Cover source not found: ${cover_file}"
			cover_cache[${cover_group}]="${cover_file}"
		fi
		cover_file="${cover_cache[${cover_group}]}"

		cp "${cover_file}" "${post_dir}/cover.${COVER_EXT}"
		info "  ${post_name} (${month}月) → cover group ${cover_group} 適用"
	done

	if (( ${#skipped_posts[@]} > 0 )); then
		warn "front matterの日付が解析できず、カバー配置をスキップした記事:"
		local sp
		for sp in "${skipped_posts[@]}"; do
			warn "  ${sp}"
		done
		warn "手動でカバーを確認するか、front matter の date/publishDate 形式を確認してください。"
	fi
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
