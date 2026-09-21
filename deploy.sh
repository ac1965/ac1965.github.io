#!/usr/bin/env zsh
# deploy.sh — 後方互換のための薄いラッパー。
#
# 旧: 画像同期・カバー配置 → hugo --minify → deploy/ ディレクトリへの同期
#     → commit・push まで一括で行っていたが、ビルドと GitHub Pages への
#     公開は GitHub Actions(.github/workflows/pages.yml) に委譲する運用へ
#     移行したため、ローカルで行う処理は画像同期・カバー配置
#     （prepare-content.sh に分離済み）と、push前の hugo --minify による
#     ビルド確認だけになった。
#
# ビルド確認をここでやる理由: ショートコードの閉じ忘れ等の記法ミスは
# push後のGitHub Actions側で初めて失敗が判明すると気づきにくい
# （push自体は成功するため）。同じ hugo --minify をpush前にローカルで
# 走らせ、ビルドが壊れている記事をここで検出する。
#
# 注意: content/post/ を main ブランチへ commit・push する操作は、
#       このスクリプトは行わない（レビューを挟むため意図的に手動）。
#       push すると GitHub Actions が起動し、ビルドと公開が走る。
#
# Usage: ./deploy.sh [--skip-cover] [--force]
set -euo pipefail

info() { echo -e "\033[1;30m>\033[0;36m>\033[1;36m> \033[0m${*}"; }
abort() {
	echo -e "\033[1;30m>\033[0;31m>\033[1;31m> ERROR:\033[0m ${*}\n" >&2
	exit 1
}
step() { echo -e "\n\033[1;35m==> \033[0m${*}"; }

readonly SCRIPT_DIR="${0:A:h}"
"${SCRIPT_DIR}/prepare-content.sh" "$@"

step "Hugoビルド確認 (hugo --minify)"
readonly BUILD_TMPDIR="$(mktemp -d)"
trap 'rm -rf "${BUILD_TMPDIR}"' EXIT

if ! (cd "${SCRIPT_DIR}" && hugo --minify --destination "${BUILD_TMPDIR}"); then
	abort "hugo --minify が失敗しました。push前にcontent/post/配下の記事(ショートコードの閉じ忘れ等)を確認してください。GitHub Actions側も同じ理由で失敗します。"
fi
info "ローカルビルド成功。GitHub Actionsでも同様にビルドできる見込みです。"

step "次の手順(手動)"
echo "  git add content"
echo "  git commit -m \"content: ...\""
echo "  git push"
echo ""
echo "push後、GitHub Actions が自動でビルド・公開します。"
