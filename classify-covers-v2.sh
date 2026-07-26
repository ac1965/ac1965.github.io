#!/usr/bin/env zsh
# classify-covers-v2.sh — resources/_gen のHugoキャッシュには頼らず、
# content/post/*/cover.* の実ファイルを直接 SHA-256 で比較して分類する。
# 拡張子は問わない（.jpg / .png 等すべて拾う）。
# 未レンダリングのページも取りこぼさないための、classify-covers.sh の穴を
# 塞ぐ改訂版。
#
# 実行場所: mysite/ (HUGO_DIR) の直下想定
# 出力: ./cover-classification-v2.tsv （slug, ext, sha256, kind, shared_with_count, path）
set -euo pipefail
setopt nullglob extended_glob

readonly CONTENT_DIR="content/post"
readonly OUT_TSV="cover-classification-v2.tsv"

[[ -d "${CONTENT_DIR}" ]] || { echo "ERROR: ${CONTENT_DIR} が見つかりません" >&2; exit 1; }

typeset -A hash_count      # hash -> 出現記事数
typeset -A slug_hash       # slug -> hash
typeset -A slug_path       # slug -> 実ファイルパス
typeset -A slug_ext        # slug -> 拡張子

local dir slug f hash ext
for dir in "${CONTENT_DIR}"/*/(N/); do
	slug="${dir:t}"
	f=("${dir}"cover.*(N))
	(( ${#f[@]} == 0 )) && continue
	if (( ${#f[@]} > 1 )); then
		echo "警告: ${slug} に cover.* が複数存在します: ${f[@]}" >&2
	fi
	f="${f[1]}"
	# 0バイトファイルは除外（壊れたファイルとして別途報告のみ）
	if [[ ! -s "${f}" ]]; then
		echo "警告: ${slug}: ${f} は0バイトです。スキップします（要手動確認）" >&2
		continue
	fi
	ext="${f:e}"
	hash="$(shasum -a 256 "${f}" | awk '{print $1}')"

	slug_hash[${slug}]="${hash}"
	slug_path[${slug}]="${f}"
	slug_ext[${slug}]="${ext}"
	hash_count[${hash}]=$(( ${hash_count[${hash}]:-0} + 1 ))
done

echo -e "slug\text\tsha256\tkind\tshared_with_count\tpath" > "${OUT_TSV}"

local kind cnt
for slug in "${(k)slug_hash[@]}"; do
	hash="${slug_hash[${slug}]}"
	cnt="${hash_count[${hash}]}"
	if (( cnt >= 2 )); then
		kind="shared(seasonal_or_default?)"
	else
		kind="custom(unique)"
	fi
	echo -e "${slug}\t${slug_ext[${slug}]}\t${hash}\t${kind}\t${cnt}\t${slug_path[${slug}]}" >> "${OUT_TSV}"
done

{
	head -1 "${OUT_TSV}"
	tail -n +2 "${OUT_TSV}" | sort -t$'\t' -k4,4 -k3,3 -k1,1
} > "${OUT_TSV}.sorted" && mv "${OUT_TSV}.sorted" "${OUT_TSV}"

echo ""
echo "=== 拡張子別カウント ==="
local -A ext_count
for slug in "${(k)slug_ext[@]}"; do
	ext_count[${slug_ext[${slug}]}]=$(( ${ext_count[${slug_ext[${slug}]}]:-0} + 1 ))
done
for ext in "${(k)ext_count[@]}"; do
	echo "  .${ext}: ${ext_count[${ext}]} 件"
done

echo ""
echo "出力: ${OUT_TSV}（${#slug_hash[@]} 件を分類）"
echo "前回の cover-classification.tsv（46件、.jpgのみ・resources/_genベース）と比較して、"
echo "新たに custom(unique) 判定された記事や、件数の食い違いが無いか確認してください。"
