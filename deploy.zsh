#!/usr/bin/env zsh
# deploy.sh — Build Hugo site and push public/ to GitHub
# Usage: ./deploy.sh [--dry-run] [--skip-cover]
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
# ICLOUD_USE: サイトルート（mysite/, deploy/ の親ディレクトリ）
#   デフォルト: ${HOME}/Projects
#   カレントディレクトリを使う場合の例:
#     ICLOUD_USE="$(pwd)" ./deploy.zsh.sh
#     または実行前に export ICLOUD_USE="${PWD}"
readonly ICLOUD_USE="${ICLOUD_USE:-${HOME}/Projects}"
readonly HUGO_DIR="${ICLOUD_USE}/mysite"
readonly PUBLIC_DIR="${ICLOUD_USE}/deploy"
readonly COVER_SRC_DIR="${HUGO_DIR}/assets/img/cover"
readonly CONTENT_POST_DIR="${HUGO_DIR}/content/post"
readonly COVER_EXT="jpg"

DRY_RUN=false
SKIP_COVER=false

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

require_cmd() {
	command -v "${1}" &>/dev/null || abort "'${1}' is not installed or not in PATH."
}

usage() {
	echo "Usage: ${SCRIPT_NAME} [--dry-run] [--skip-cover]"
	echo "  --dry-run     Run hugo build but skip git push"
	echo "  --skip-cover  Skip cover image placement"
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
	require_cmd hugo
	require_cmd git
	require_cmd rsync

	[[ -d "${HUGO_DIR}" ]] || abort "Hugo site directory not found: ${HUGO_DIR}"
	[[ -d "${PUBLIC_DIR}" ]] || abort "Deploy directory not found: ${PUBLIC_DIR}"
}

# ─────────────────────────────────────────
# Place cover images
# ─────────────────────────────────────────
place_covers() {
	if [[ "${SKIP_COVER}" == true ]]; then
		return 0
	fi

	step "Placing cover images"

	local current_month cover_group cover_file
	current_month="$(date +%m)"
	cover_group="$(cover_month "${current_month}")"
	cover_file="${COVER_SRC_DIR}/${cover_group}.${COVER_EXT}"

	[[ -f "${cover_file}" ]] || abort "Cover source not found: ${cover_file}"
	info "Using cover: ${cover_file}"

	# zshネイティブのグロブでmdファイルを配列取得（bashのfind+read -d''をglob修飾子に置換）
	local -a md_files
	md_files=("${CONTENT_POST_DIR}"/*.md(N))

	local md_file post_name post_dir
	local -a existing_covers
	for md_file in "${md_files[@]}"; do
		post_name="${md_file:t:r}"   # basename、拡張子除去（zsh modifier）
		post_dir="${CONTENT_POST_DIR}/${post_name}"

		# Ensure post directory exists
		[[ -d "${post_dir}" ]] || mkdir -p "${post_dir}"

		# Copy cover only if none exists (any extension)
		# nullglob設定済みなので、マッチなしなら空配列になる
		existing_covers=("${post_dir}"/cover.*(N))
		if (( ${#existing_covers[@]} == 0 )); then
			cp "${cover_file}" "${post_dir}/cover.${COVER_EXT}"
			info "  Added cover → ${post_dir}/cover.${COVER_EXT}"
		fi
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
