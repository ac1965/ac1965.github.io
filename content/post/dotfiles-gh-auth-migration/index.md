+++
title = "dotfilesのGitHub操作スクリプトを gh 認証に寄せた"
author = ["YAMASHITA Takao"]
date = 2026-09-13T11:25:00+09:00
lastmod = 2026-09-25T19:59:32+09:00
tags = ["GitHub-CLI", "zsh", "dotfiles", "認証", "セキュリティ"]
categories = ["Tech"]
draft = false
cover = ""
+++

## きっかけ {#きっかけ}

手元の dotfiles には、指定した GitHub URL を clone/pull する [`hub-clone.sh`](https://github.com/ac1965/dotfiles/blob/d1a3f9e/.local/bin/hub-clone.sh) と、指定したユーザーのリポジトリ一覧を JSON で取得する [`hub-repos.sh`](https://github.com/ac1965/dotfiles/blob/d1a3f9e/.local/bin/hub-repos.sh) という2本のシェルスクリプトがある。長らく `GITHUB_TOKEN` という環境変数で GitHub Personal Access Token を渡す方式で動いていたが、これをやめて `gh auth login` で macOS の安全な認証情報ストア(Keychain)を使う形にリファクタリングできないか、と思い立った。

きっかけになったのは、実際に手を動かしたときに出た次のエラーだった。

```text
❯ hub-clone.sh https://github.com/d12frosted/environment/tree/master
fatal: repository 'https://github.com/d12frosted/environment/tree/master/' not found
❯ hub-repos.sh https://github.com/d12frosted/environment/tree/master
❌ API呼び出しに失敗しました(HTTP 404)。ユーザー名またはトークンを確認してください。
```


## GITHUB_TOKEN を捨てて gh CLI に寄せる {#github-token-を捨てて-gh-cli-に寄せる}

`hub-repos.sh` は元々 `curl` と `GITHUB_TOKEN` で GitHub の [REST API(List repositories for a user)](https://docs.github.com/en/rest/repos/repos#list-repositories-for-a-user) を直接叩いていた。ここを [`gh api --paginate`](https://cli.github.com/manual/gh_api) に置き換え、認証チェックも `gh auth status` で行うようにした。 `hub-clone.sh` 側も GITHUB_TOKEN の有無を見ていた箇所を削除し、同じく `gh auth status` で判定するようにしている。

面白かったのは、 [`gh auth login`](https://cli.github.com/manual/gh_auth_login) が実はすでに macOS のキーリングに認証情報を保存する仕組みを持っていたこと。 `gh auth status` で確認すると、環境変数の `GITHUB_TOKEN` が優先されて表に出ていなかっただけで、キーリング認証はアクティブになっていない状態のまま存在していた。環境変数を外すだけで、後ろに隠れていた安全な認証方式がそのまま使えるようになったわけだ。


## gh api の -f オプションが黙って POST になる {#gh-api-の-f-オプションが黙って-post-になる}

移行作業の中で一番ハマったのがこれだった。

```shell
gh api --paginate "users/USER/repos" -f per_page=100 -f type=owner
```

これが理由もなく 404 を返してきた。エンドポイント自体は合っているし、認証も通っている。調べていくと、 `gh api` は `-f` や `-F` でパラメータを渡すと、既定の HTTP メソッドが `GET` から `POST` に暗黙で切り替わる仕様だとわかった([マニュアル](https://cli.github.com/manual/gh_api)にもその旨の記載がある)。GET 専用のエンドポイントに POST してしまっていたので 404 になっていた、というオチだった。 `--method GET` を明示的に指定することで解決した。


## ついでに見つかった tree URL のバグ {#ついでに見つかった-tree-url-のバグ}

最初に貼ったエラーログにあった `https://github.com/d12frosted/environment/tree/master` という URL は、ブラウザでリポジトリのファイル一覧を見ているときにアドレスバーからそのままコピーしたものだった。owner/repo 名の抽出自体はもともと正しく動いていて、 `environment` というリポジトリ名はちゃんと認識できていた。問題は、clone を実行する段になって、抽出した情報を使わずに元の URL をそのまま `git clone` に渡していたことだった。 `/tree/master` が付いたままの URL は Git のリモートとしては存在しないので、当然 fail するしかない。

ここは [`build_clone_url()`](https://github.com/ac1965/dotfiles/blob/d1a3f9e/.local/bin/hub-clone.sh#L134) という関数を新しく用意して、抽出済みの host/owner/repo から `https://host/owner/repo.git` のような正規の clone 用 URL を組み立て直すようにした。これでブラウザからコピーした tree 付きの URL でも問題なく clone できるようになった。


## hub-repos.sh は何のためにあるのか {#hub-repos-dot-sh-は何のためにあるのか}

一通りリファクタリングが終わったところで、素朴な疑問が湧いた。「 `hub-repos.sh` って結局何の役に立っているんだろう」。

調べてみると、 `hub-repos.sh` を呼んでいるのは `hub-clone.sh` の中の副次処理だけだった。clone するたびに、その owner が持っている全リポジトリの一覧を `repos-<owner>.json` としてクローン先のディレクトリに書き出す、という処理。ところが、この出力を後で読んでいる箇所がどこにもない。書き出されたきり誰にも参照されない、完全な出しっぱなし状態になっていた。

手元にはもう1本、 [`clone-favorite-repos.sh`](https://github.com/ac1965/dotfiles/blob/d1a3f9e/.local/bin/clone-favorite-repos.sh) というスクリプトもある。こちらはお気に入りのリポジトリをカテゴリ分けして管理し、 [`favorite-repos.json`](https://github.com/ac1965/dotfiles/blob/d1a3f9e/.local/share/favorite-repos.json) を見ながら一括で clone/pull するためのものだ。 `hub-repos.sh` とは完全に別系統で、これまで繋がったことがなかった。


## hub-repos.sh の出力を favorite-repos.json の資産に変える {#hub-repos-dot-sh-の出力を-favorite-repos-dot-json-の資産に変える}

そこで、 `hub-repos.sh` の出力を `favorite-repos.json` の形式に寄せて、 `clone-favorite-repos.sh` を拡張することにした。

まず [`hub-repos.sh` の中核部分](https://github.com/ac1965/dotfiles/blob/d1a3f9e/.local/bin/hub-repos.sh#L110)の出力スキーマを、GitHub API の生データ( `name`, `full_name`, `html_url`, `private`, `fork` )から、 `favorite-repos.json` の要素と同じ `{owner, repo, url}` 形式に変更した。ついでに、 `INCLUDE_FORKS=1` を明示しない限り fork リポジトリはデフォルトで除外するようにもした。試しにあるユーザーで実行してみたら、79件あったリポジトリが fork 除外後は 52件になった。

次に `clone-favorite-repos.sh` に `--import-owner OWNER [-c category]` と `--import-json PATH [-c category]` という新しいモードを追加した([この時点の実装](https://github.com/ac1965/dotfiles/blob/d1a3f9e/.local/bin/clone-favorite-repos.sh#L125))。指定した owner のリポジトリ一覧を取得して、 `favorite-repos.json` の指定カテゴリにマージする。カテゴリを省略すると、owner 名がそのままカテゴリ名になる。 `url` をキーに重複排除しているので、同じデータを何度 import しても件数が増えたりしない。実際に2回連続で実行して、エントリ数が変わらないことも確認した。 `-n` (dry-run)を付ければ、実際に書き換える前に取り込み内容を一覧表示できる。

これで「気になる GitHub ユーザーのリポジトリ一覧をざっと眺めて、良さそうなものを favorite に取り込む」という導線ができた。 `hub-repos.sh` は出しっぱなしのデータ生成器から、favorite リストを育てるための入り口に変わったことになる。


## dedup は url だけでは足りなかった {#dedup-は-url-だけでは足りなかった}

下書きを見せたところ、「エントリ数が変わらない、とは owner のリポジトリ一覧をチェックして重複排除しているのだろうか。それだと owner 側のリポジトリの追加・削除が反映されないのでは」という指摘をもらった。

まさにその通りだった。上記の実装は、既存エントリと新規取得エントリを url の和集合として [`unique_by(.url)`](https://jqlang.org/manual/v1.7/#unique-unique_by) で重複排除しているだけで、確認していたのは「同じデータを2回連続で import しても件数が増えない」ことだけだった。GitHub 側でリポジトリが削除されたりリネームされたりして url が消えたケースは、一度も試していなかった。

実際に再現させてみると、案の定だった。

```text
1回目 import: repo-a, repo-b, repo-c を取り込む → 3件
(GitHub 側で repo-b が削除された想定)
2回目 import: repo-a, repo-c だけを取得 → マージ後も repo-a, repo-b, repo-c の3件のまま
```

repo-b は GitHub 上から消えているのに、 `favorite-repos.json` には亡霊のように残り続ける。url の和集合を取るだけの実装では、増える方向にしか動かないのは当然だった。

対策として、マージ処理を「和集合」から「該当 owner 分だけの置き換え」に変更した。 `favorite-repos.json` のカテゴリには複数 owner のエントリが混在することがある(例えば `emacs` カテゴリには複数の作者のリポジトリが並んでいる)ので、カテゴリ全体を丸ごと置き換えるわけにはいかない。今回 import した owner に属するエントリだけを最新の取得結果で置き換え、他の owner のエントリには一切触れないようにした。


## jq の . が別の配列にすり替わる罠 {#jq-の-dot-が別の配列にすり替わる罠}

この修正の途中で、もう一つ別の罠を踏んだ。次のような [`index()`](https://jqlang.org/manual/v1.7/#index-rindex) を使った jq 式を書いたところ、意味もなく `Cannot index array with string "url"` というエラーが出た。

```jq
$existingUrls | index(.url)
```

一見、 `$existingUrls` という配列の中から現在の要素の `url` を探しているつもりだった。ところが `A | f(B)` という形では、引数 `B` の中の `.` は `A` の入力ではなく `A` が出力した値、つまりパイプで渡された後の `$existingUrls` (配列そのもの)を指してしまう。配列に対して `.url` でアクセスしようとするのでエラーになる、という理屈だった。

```shell
echo '{"url":"abc"}' | jq '(["x","abc","y"] | index(.url))'
# jq: error: Cannot index array with string "url"

echo '{"url":"abc"}' | jq '. as $item | (["x","abc","y"] | index($item.url))'
# 1
```

対処は単純で、パイプで `.` が入れ替わる前に `. as $item` で値を変数に退避しておき、以降は `.url` の代わりに `$item.url` を使うようにした。地味だが、jq を書くときに何度も踏み抜きがちな罠だと思う。


## 直して、テストし直す {#直して-テストし直す}

修正後は、追加・削除・冪等性・他 owner への非干渉を[`select()`](https://jqlang.org/manual/v1.7/#select)の条件を書き直しながら一通りテストし直した。

-   新しいリポジトリが増えていれば追加候補として検出される
-   GitHub 側で消えたリポジトリは削除候補として検出され、実行すると `favorite-repos.json` からも消える
-   同じデータをもう一度 import しても、追加・削除ともに0件のまま変化しない
-   `emacs` のように複数 owner が混在するカテゴリに、新しい owner を import しても既存の他 owner のエントリは無傷

`-n` (dry-run) を付けると、実際に書き換える前に「+追加予定」「-削除予定」の一覧が見られるようにもしたので、いきなり `favorite-repos.json` が書き換わって困る、ということもなくなったはずだ。

「エントリ数が変わらない」というテストだけで安心してしまっていたのは、典型的な確認不足だったと思う。次からは、増える方向だけでなく減る方向のケースも忘れずに試すようにしたい。


## dotfiles.zsh deploy を忘れると古い挙動のまま {#dotfiles-dot-zsh-deploy-を忘れると古い挙動のまま}

最後にひとつ、運用面での学びを書いておく。手元の dotfiles は `~/.local/bin/` にシンボリックリンクを張る運用ではなく、 `dotfiles.zsh deploy` というコマンドでリポジトリから `$HOME` へファイルを同期する運用になっている。そのため、リポジトリ側のスクリプトを直しただけでは `$HOME` 上の実行ファイルには反映されない。

最初のテストで「あれ、直したはずなのに GITHUB_TOKEN のエラーがまだ出る」と一瞬混乱した。原因は単純で、 `~/.local/bin/hub-repos.sh` が更新前の内容のまま残っていただけだった。 `./dotfiles.zsh deploy -n` でドライラン確認してから実際に deploy する、という手順を徹底することで解決した。地味だが、実行ファイルの実体がどこにあるかを見失うと、直したはずのバグがいつまでも直らないように見えてしまう、という良い教訓になった。
