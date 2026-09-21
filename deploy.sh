#!/usr/bin/env zsh
# deploy.sh — 後方互換のための薄いラッパー。
#
# 旧: 画像同期・カバー配置 → hugo --minify → deploy/ ディレクトリへの同期
#     → commit・push まで一括で行っていたが、ビルドと GitHub Pages への
#     公開は GitHub Actions(.github/workflows/pages.yml) に委譲する運用へ
#     移行したため、ローカルで行う処理は画像同期・カバー配置
#     （prepare-content.sh に分離済み）だけになった。
#
# 注意: content/post/ を main ブランチへ commit・push する操作は、
#       このスクリプトは行わない（レビューを挟むため意図的に手動）。
#       push すると GitHub Actions が起動し、ビルドと公開が走る。
#
# Usage: ./deploy.sh [--skip-cover] [--force]
set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
"${SCRIPT_DIR}/prepare-content.sh" "$@"

echo -e "\n\033[1;35m==> \033[0m次の手順(手動):"
echo "  git add content"
echo "  git commit -m \"content: ...\""
echo "  git push"
echo ""
echo "push後、GitHub Actions が自動でビルド・公開します。"
