+++
title = "pushは成功したのにサイトが更新されない、を追いかけたら二重の教訓が出てきた"
author = ["YAMASHITA Takao"]
date = 2026-09-21T17:10:00+09:00
lastmod = 2026-09-21T16:58:00+09:00
tags = ["Hugo", "GitHubActions", "Ox-Hugo", "Deploy"]
categories = ["Tech"]
draft = false
cover = ""
+++

前回、[GitHub Actions移行とDNS設定ミスの記事](https://www.ty07.net/post/github-actions-pages-migration-and-dns-fix/)を書いてpushしたところ、実はそのpush自体が「サイトが更新されない」という新しい問題を持ち込んでいた。


## 「deploy &amp;&amp; git pushまで終わっているのに、サイトが変わっていない」 {#deploy-and-and-git-pushまで終わっているのに-サイトが変わっていない}

前回の記事をpushしたあと、サイトを確認しても内容が変わっていなかった。 `git push` 自体はエラーもなく完了していたので、最初は何が起きているのか分からなかった。

`gh run list` で確認すると、直近2回の `Deploy to GitHub Pages` ワークフローが、どちらも数十秒で `failure` に終わっていた。


## 　ログを見ると、原因は自分が書いた記事そのものだった {#ログを見ると-原因は自分が書いた記事そのものだった}

`gh run view --log-failed` でログを確認すると、Hugoのビルド自体が失敗していた。

```text
ERROR error building site: assemble: failed to create page from pageMetaSource /post/github-actions-pages-migration-and-dns-fix: failed to extract shortcode: shortcode "details" must be closed or self-closed
```

原因は、直前に書いた記事の本文中にあった。Blowfishの `\{\{<details>\}\}` ショートコードの閉じタグが、中括弧1つ分だけ足りなかった。

実際の誤りは次のとおりだった。

```diff
-{</details>}}
+{{</*/details*/>}}
```

正しくは `\{\{</details>}}` だが、 `\{</details>}}` になっていた。1文字抜けているだけなので見た目にはほとんど気づけないが、Hugoのショートコードパーサーにとっては致命的だった。


## 生成物だけ直しても意味がない、というox-hugo特有の落とし穴 {#生成物だけ直しても意味がない-というox-hugo特有の落とし穴}

最初、 `content/post/github-actions-pages-migration-and-dns-fix/index.md` 側の閉じタグを直してビルドが通ることを確認し、それで解決したつもりになった。

ところがこのブログはox-hugo運用で、 `content/post/*/index.md` はorg-modeのソースファイル（ `all-posts.org` ）からの生成物にすぎない。生成物側だけを直しても、次にox-hugoで再エクスポートすれば、 `all-posts.org` に残ったままの誤りがそのまま `index.md` に上書きされて復活してしまう。

実際に `all-posts.org` 側の該当箇所（今回追加した記事の `pages.yml` 引用部分）を確認すると、まったく同じ `\{</details>}}` の誤りが残っていた。おそらく最初にorg側で打ち間違え、それがエクスポートによってMarkdown側にも伝播したのだと思う。ソース（org）と生成物（md）の両方を直して、ようやく直った。


## なぜ「pushは成功したのに」が起きたのか {#なぜ-pushは成功したのに-が起きたのか}

これまでの `deploy.sh` 運用では、pushが成功することと、公開されることはほぼ同じ意味だった。手元でHugoビルドしてrsyncしてpushする、という一直線の処理だったからだ。

ところが今はビルドと公開をGitHub Actions側に委譲している。 `git push` はGitへの転送が成功したかどうかしか保証しておらず、その後のHugoビルドとGitHub Pagesへのデプロイは、pushとは別のジョブとして走る。今回はそのビルドジョブの方が、記事本文の記法ミスで落ちていた。pushという「入口」の成功と、サイトの更新という「出口」の成功が切り離されたことで、「pushは終わっているのに何も変わっていない」という、以前の運用では起こり得なかった状態が起きた。


## 再発防止1: pushする前に、ローカルでも同じビルドを走らせる {#再発防止1-pushする前に-ローカルでも同じビルドを走らせる}

`deploy.sh` は、画像同期とカバー画像配置を行う `prepare-content.sh` を呼ぶだけの薄いラッパーになっていた。ここに、pushの案内を出す前に `hugo --minify` をローカルで実行してビルドが通ることを確認するステップを追加した。ビルドに失敗した場合は、そこでスクリプトを中断し、commit・pushの案内は出さないようにした。

{{<details "deploy.shに追加したビルド確認部分">}}
```sh
step "Hugoビルド確認 (hugo --minify)"
readonly BUILD_TMPDIR="$(mktemp -d)"
trap 'rm -rf "${BUILD_TMPDIR}"' EXIT

if ! (cd "${SCRIPT_DIR}" && hugo --minify --destination "${BUILD_TMPDIR}"); then
	abort "hugo --minify が失敗しました。push前にcontent/post/配下の記事(ショートコードの閉じ忘れ等)を確認してください。GitHub Actions側も同じ理由で失敗します。"
fi
info "ローカルビルド成功。GitHub Actionsでも同様にビルドできる見込みです。"
```
{{</details>}}

ビルド出力は `mktemp -d` で作った一時ディレクトリに書き出し、 `trap` で必ず削除するようにしたので、リポジトリを汚すことはない。GitHub Actions側と同じ `hugo --minify` を手元で先に走らせるだけで、今回のような記法ミスの大半はpush前に潰せるはずだ。


## 再発防止2: push後もActionsの結果まで見届ける {#再発防止2-push後もactionsの結果まで見届ける}

ただし、これだけでは足りない。Pagesの設定や権限、DNS、CI環境の差異のように、ローカルのビルドでは再現できない種類の失敗もある。 `push` 自体の成功と、Actions側のビルド・デプロイの成功は、今回はっきり別物だと分かったので、pushしたら最後まで見届ける仕組みも作ることにした。

`push-and-watch.sh` という新しいスクリプトを追加した。 `git push` を実行し、そのコミットのSHAを使って対応する `pages.yml` のワークフロー実行を特定し、 `gh run watch --exit-status` で完走するまで監視する。

{{<details "push-and-watch.sh">}}
```sh
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
```
{{</details>}}

pushが「転送」の成功でしかなく、その先のビルドとデプロイが別ジョブとして動いている以上、push後に何が起きるかまで見届ける仕組みを用意しておいた方が安心だと思う。実際にこのスクリプト自身を使って、今回の一連の修正コミットをpush・監視し、buildとdeployの両方が成功することを確認した。


## 振り返って {#振り返って}

同じ `\{</details>}}` という中括弧の抜けが、記事本文（生成物）とorgソースの両方に別々に存在していた点が今回は一番の学びだった。ox-hugoのような「ソースから生成物を作る」パイプラインでは、目の前のエラーが出ている場所（生成物）を直しただけで満足せず、そのソースまで遡って直したかを確認しないと、同じ不具合が何度でも復活する。

もうひとつは、pushの成功とデプロイの成功が別レイヤーの話だという当たり前のことを、CIを挟む構成に変えた直後は忘れがちだという点だ。ローカルで一度も試さずpushする以上、ビルドが壊れているかどうかはCIが教えてくれるまで分からない。手元でCIと同じビルドコマンドを先に走らせておくのと、push後にその結果まで見届けておくのと、両方を仕組みにしておくくらいがちょうどいいのだと思う。
