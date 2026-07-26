#!/usr/bin/env zsh
# finalize-custom-covers.sh
#
# 1. content/post/2020-64ac-ab0e/cover.png（PNG）を sips でJPEGに変換し、
#    assets/img/cover/custom/2020-64ac-ab0e.jpg として配置する
#    （deploy.sh の Tier1 コピー先は cover.${COVER_EXT} = cover.jpg 固定のため、
#     拡張子を揃えておかないと "cover.jpg" という名のPNGが再び生成されてしまう）
# 2. 元の content/post/2020-64ac-ab0e/cover.png はバックアップの上で削除
# 3. custom(全12記事）の content/post/<slug>/cover.jpg を、直近の
#    `deploy.sh --dry-run` 2回によって季節画像で上書きされてしまった分も含めて
#    もう一度クリアする（ox-hugo再エクスポート後、次のdeployでTier1が
#    確実に効くようにするための最終処置。Tier0の「既存カバーは即スキップ」を
#    外すのが目的）
#
# 前提: ox-hugoでの再エクスポート（README.org からの C-c C-e H A）は
#       このスクリプト実行の前でも後でもどちらでも良いが、
#       「deploy.sh 実行」は必ずこのスクリプトの後、かつ再エクスポート後に行うこと。
#
# 実行場所: mysite/ (HUGO_DIR) の直下想定
set -euo pipefail
setopt nullglob

readonly CONTENT_DIR="content/post"
readonly CUSTOM_DIR="assets/img/cover/custom"
readonly BACKUP_DIR="finalize-custom-backup-$(date +%Y%m%d-%H%M%S)"

# custom判定 全12記事（前回11件 + 今回発見の2020-64ac-ab0e）
readonly -a CUSTOM_SLUGS=(
	2024-b55f-0ad0
	2024-8776-0378
	2010-4ca5-ca76
	2020-4b4f-83fe
	2016-fbf9-cc8d
	2010-ae11-dbbf
	2024-25cb-9aad
	2024-3ec3-22af
	2024-cf97-098e
	2021-4317-c611
	2021-b683-9118
	2020-64ac-ab0e
)

mkdir -p "${CUSTOM_DIR}" "${BACKUP_DIR}"

echo "=== Step 1: 2020-64ac-ab0e の cover.png → custom/2020-64ac-ab0e.jpg (JPEG変換) ==="
local src="${CONTENT_DIR}/2020-64ac-ab0e/cover.png"
local dst="${CUSTOM_DIR}/2020-64ac-ab0e.jpg"

if [[ -f "${src}" ]]; then
	if [[ -f "${dst}" ]]; then
		echo "  既に ${dst} が存在するため変換をスキップします"
	elif command -v sips &>/dev/null; then
		sips -s format jpeg "${src}" --out "${dst}" >/dev/null
		echo "  変換完了: ${src} → ${dst}"
	elif command -v magick &>/dev/null; then
		magick "${src}" "${dst}"
		echo "  変換完了(ImageMagick): ${src} → ${dst}"
	else
		echo "  ERROR: sips も magick も見つかりません。手動で変換してください。" >&2
		exit 1
	fi

	mkdir -p "${BACKUP_DIR}/2020-64ac-ab0e"
	cp "${src}" "${BACKUP_DIR}/2020-64ac-ab0e/cover.png"
	rm "${src}"
	echo "  元ファイル削除済み（バックアップ: ${BACKUP_DIR}/2020-64ac-ab0e/cover.png）"
else
	echo "  skip: ${src} が見つかりません（既に処理済みの可能性）"
fi

echo ""
echo "=== Step 2: custom全12記事の content/post/<slug>/cover.* を最終クリア ==="
local slug dir found f
for slug in "${CUSTOM_SLUGS[@]}"; do
	dir="${CONTENT_DIR}/${slug}"
	[[ -d "${dir}" ]] || { echo "  skip (dir not found): ${slug}"; continue; }

	found=("${dir}"/cover.*(N))
	if (( ${#found[@]} == 0 )); then
		echo "  clean: ${slug}（cover.*なし）"
		continue
	fi
	for f in "${found[@]}"; do
		mkdir -p "${BACKUP_DIR}/${slug}"
		cp "${f}" "${BACKUP_DIR}/${slug}/"
		rm "${f}"
		echo "  cleared: ${f}"
	done
done

echo ""
echo "バックアップ先: ${BACKUP_DIR}/"
echo ""
echo "残タスク:"
echo "  1. README.org / all-posts.org からox-hugoで再エクスポート（C-c C-e H A）"
echo "     ※ まだの場合。既に済んでいれば不要。"
echo "  2. grep -l '^cover:' content/post/*.md | wc -l   # 12件になっているか確認"
echo "  3. zsh deploy.sh --dry-run で custom全12記事に [明示指定] custom/<slug>.jpg が出るか確認"
echo "  4. hugo server --buildDrafts --disableFastRender で全カテゴリが正常ビルドされるか確認"
echo "  5. 問題なければ zsh deploy.sh で本番デプロイ"
