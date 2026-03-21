#!/usr/bin/env bash
# deploy.sh — Build Hugo site and push public/ to GitHub
# Usage: ./deploy.sh [--dry-run] [--skip-cover]
set -euo pipefail
IFS=$'\n\t'

# ─────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────
ICLOUD_USE="${ICLOUD_USE:-${HOME}/Projects}"
HUGO_DIR="${ICLOUD_USE}/mysite"
PUBLIC_DIR="${ICLOUD_USE}/deploy"
COVER_SRC_DIR="${HUGO_DIR}/assets/img/cover"
CONTENT_POST_DIR="${HUGO_DIR}/content/post"

DRY_RUN=false
SKIP_COVER=false

# ─────────────────────────────────────────
# Argument parsing
# ─────────────────────────────────────────
for arg in "$@"; do
	case "${arg}" in
	--dry-run) DRY_RUN=true ;;
	--skip-cover) SKIP_COVER=true ;;
	--help | -h)
		echo "Usage: $(basename "$0") [--dry-run] [--skip-cover]"
		echo "  --dry-run     Run hugo build but skip git push"
		echo "  --skip-cover  Skip cover image placement"
		exit 0
		;;
	*)
		abort "Unknown option: ${arg}"
		;;
	esac
done

# ─────────────────────────────────────────
# Logging helpers
# ─────────────────────────────────────────
abort() {
	echo -e "\033[1;30m>\033[0;31m>\033[1;31m> ERROR:\033[0m ${*}\n" >&2
	exit 1
}
info() { echo -e "\033[1;30m>\033[0;36m>\033[1;36m> \033[0m${*}"; }
warn() { echo -e "\033[1;30m>\033[0;33m>\033[1;33m> \033[0m${*}"; }
step() { echo -e "\n\033[1;35m==> \033[0m${*}"; }

# ─────────────────────────────────────────
# Utilities
# ─────────────────────────────────────────

# Map month number to seasonal cover group
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

# ─────────────────────────────────────────
# Pre-flight checks
# ─────────────────────────────────────────
step "Pre-flight checks"
require_cmd hugo
require_cmd git
require_cmd rsync

[[ -d "${HUGO_DIR}" ]] || abort "Hugo site directory not found: ${HUGO_DIR}"
[[ -d "${PUBLIC_DIR}" ]] || abort "Deploy directory not found: ${PUBLIC_DIR}"

# ─────────────────────────────────────────
# Place cover images
# ─────────────────────────────────────────
if [[ "${SKIP_COVER}" == false ]]; then
	step "Placing cover images"

	current_month="$(date +%m)"
	cover_group="$(cover_month "${current_month}")"
	cover_file="${COVER_SRC_DIR}/${cover_group}.jpg"

	[[ -f "${cover_file}" ]] || abort "Cover source not found: ${cover_file}"
	info "Using cover: ${cover_file}"

	while IFS= read -r -d '' md_file; do
		post_name="$(basename "${md_file}" .md)"
		post_dir="${CONTENT_POST_DIR}/${post_name}"

		# Ensure post directory exists
		[[ -d "${post_dir}" ]] || mkdir -p "${post_dir}"

		# Copy cover only if none exists (any extension)
		if ! compgen -G "${post_dir}/cover.*" &>/dev/null; then
			cp "${cover_file}" "${post_dir}/cover.jpg"
			info "  Added cover → ${post_dir}/cover.jpg"
		fi
	done < <(find "${CONTENT_POST_DIR}" -maxdepth 1 -name "*.md" -print0)
fi

# ─────────────────────────────────────────
# Hugo build
# ─────────────────────────────────────────
step "Building site with Hugo"
cd "${HUGO_DIR}"

# Clean previous build
rm -rf public

hugo --minify || abort "Hugo build failed."
info "Build complete: $(find public -type f | wc -l | tr -d ' ') files generated."

# ─────────────────────────────────────────
# Deploy
# ─────────────────────────────────────────
if [[ "${DRY_RUN}" == true ]]; then
	warn "Dry-run mode: skipping rsync and git push."
	exit 0
fi

step "Syncing to deploy directory"
rsync -a --delete --checksum --exclude=".git" "${HUGO_DIR}/public/" "${PUBLIC_DIR}/"

step "Committing and pushing to GitHub"
cd "${PUBLIC_DIR}"

git add --all

if git diff --cached --quiet; then
	warn "Nothing to commit — deploy directory is up to date."
	exit 0
fi

commit_msg="deploy: $(LC_ALL=C date '+%Y-%m-%dT%H:%M:%S%z')"
git commit -m "${commit_msg}"
git push

info "✓ Deployed successfully: ${commit_msg}"
