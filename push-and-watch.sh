#!/usr/bin/env zsh
# push-and-watch.sh — git push した直後に、それが起こす GitHub Actions の
# デプロイ(.github/workflows/pages.yml)を最後まで見届けるスクリプト。
#
# 背景: git push はリモートへの転送が成功したかどうかしか保証しない。
# 実際に「pushは成功したのにサイトが更新されない」事故が起きたことが
# あり(記事のショートコード閉じ忘れでbuildジョブが失敗していた)、
# 気づくまで手動でgh run listを叩く必要があった。
# deploy.sh側のローカルhugo --minifyチェックで記法ミスは防げるが、
# Pages設定・権限・DNS・CI環境差異など、ローカルでは再現できない
# 種類の失敗はpush後にActions側の結果を見るまで気づけない。
#
# Usage: ./push-and-watch.sh
set -euo pipefail

trap 'echo -e "\033[1;31m> UNEXPECTED ERROR\033[0m at line ${LINENO} (exit ${?})" >&2' ERR

info() { echo -e "\033[1;30m>\033[0;36m>\033[1;36m> \033[0m${*}"; }
warn() { echo -e "\033[1;30m>\033[0;33m>\033[1;33m> \033[0m${*}"; }
abort() {
	echo -e "\033[1;30m>\033[0;31m>\033[1;31m> ERROR:\033[0m ${*}\n" >&2
	exit 1
}
step() { echo -e "\n\033[1;35m==> \033[0m${*}"; }

require_cmd() {
	command -v "$1" >/dev/null 2>&1 || abort "${1} コマンドが見つかりません。"
}
require_cmd git
require_cmd gh

readonly SCRIPT_DIR="${0:A:h}"
readonly WORKFLOW_FILE="pages.yml"
readonly SITE_URL="https://www.ty07.net/"
cd "${SCRIPT_DIR}"

readonly BRANCH="$(git rev-parse --abbrev-ref HEAD)"

step "git push (${BRANCH})"
PUSH_OUTPUT="$(git push 2>&1)" || { print -r -- "${PUSH_OUTPUT}" >&2; abort "git push に失敗しました。"; }
print -r -- "${PUSH_OUTPUT}"

if [[ "${PUSH_OUTPUT}" == *"Everything up-to-date"* ]]; then
	info "pushする変更がありませんでした。監視をスキップします。"
	exit 0
fi

readonly SHA="$(git rev-parse HEAD)"

step "対応するGitHub Actionsの実行を待機"
run_id=""
for _ in {1..30}; do
	run_id="$(gh run list --workflow="${WORKFLOW_FILE}" --branch="${BRANCH}" \
		--json databaseId,headSha --jq ".[] | select(.headSha==\"${SHA}\") | .databaseId" | head -n1)"
	[[ -n "${run_id}" ]] && break
	sleep 2
done

if [[ -z "${run_id}" ]]; then
	abort "対応するワークフロー実行が見つかりませんでした(60秒待機)。'gh run list' で手動確認してください。"
fi

step "実行を監視 (run ${run_id})"
if gh run watch "${run_id}" --exit-status; then
	step "デプロイ成功"
	info "${SITE_URL} が更新されているはずです。"
else
	warn "デプロイに失敗しました。ログ確認: gh run view ${run_id} --log-failed"
	abort "GitHub Actions run ${run_id} が失敗しました。"
fi
