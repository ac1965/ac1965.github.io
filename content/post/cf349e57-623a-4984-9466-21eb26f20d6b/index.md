+++
title = "Hdeploy.sh から push-and-watch.sh までの公開手順を読み解く"
author = ["YAMASHITA Takao"]
date = 2026-10-11T18:23:00+09:00
lastmod = 2026-10-12T08:31:50+09:00
tags = ["Hugo", "Git", "Deploy"]
categories = ["Tech"]
draft = false
cover = ""
+++

記事を公開するときに、次の 1 行を実行している。

```bash
./deploy.sh && g add . && gen-commit-msg.sh --commit && ./push-and-watch.sh
```

この 1 行が何をしているのか、整理してみた。


## 全体の流れ {#全体の流れ}

4 つのコマンドを `&&` でつないだ一連の流れで、内容は次のとおり。

1.  公開用ファイルの整形とビルド確認
2.  全部ステージ
3.  AI にコミットメッセージを書かせてコミット
4.  push して公開を見届ける

どれか 1 つでも失敗すると、そこで止まって次には進まない。

{{< mermaid >}}
flowchart LR
    A["./deploy.sh<br/>整形とビルド確認"] --> B["g add .<br/>全変更をステージ"]
    B --> C["gen-commit-msg.sh --commit<br/>AI がメッセージを書いてコミット"]
    C --> D["./push-and-watch.sh<br/>push して Actions を監視"]
    D --> E["https://www.ty07.net/ 更新"]
{{< /mermaid >}}


## ./deploy.sh {#dot-deploy-dot-sh}

`deploy.sh` は、公開前の準備とビルド確認だけを行う。コミットも push もしない(ファイル冒頭のコメントに明記してある)。

1.  `prepare-content.sh` を呼ぶ。実行内容は次の 3 つ。
    -   `content/post/` の存在確認と、iCloud の同期競合コピー( `index 2.md` のような名前)の検出
    -   記事ごとの画像の同期
    -   カバー画像の自動配置
2.  `hugo --minify` を一時ディレクトリに出力して、ビルドが通るか確認する。ショートコードの閉じ忘れなどを、push の前に見つけるためである。
3.  最後に、手動で行う手順を表示して終わる。


## g add . {#g-add-dot}

`g` は `git` のエイリアスである。カレントディレクトリ以下の変更を、すべてステージする。


## gen-commit-msg.sh --commit {#gen-commit-msg-dot-sh-commit}

`~/.local/bin/gen-commit-msg.sh` は、ステージ済みの diff( `git diff --cached` )を `claude -p` に渡し、Conventional Commits 形式のメッセージを作る。 `--commit` を付けているので、そのままコミットまで行う。

-   モデルは既定で `haiku` である。
-   生成結果の 1 行目が `type(scope): 要約` の形式でなければ、 `--commit` を付けていてもコミットせずエラーで止まる。


## ./push-and-watch.sh {#dot-push-and-watch-dot-sh}

`push-and-watch.sh` は、 `git push` の後に GitHub Actions のデプロイを最後まで見届ける。

1.  `git push` を実行する。
2.  出力に "Everything up-to-date" があれば、push するものが無かったとして終了する。
3.  `HEAD` の SHA に一致する `pages.yml` の実行を最大 60 秒(2 秒おきに 30 回)探す。
4.  見つかったら `gh run watch --exit-status` で完了まで監視する。
5.  成功すれば「サイトが更新されているはず」と表示し、失敗すれば `gh run view ... --log-failed` の案内を出して異常終了する。

    `git push` が成功しても、Actions 側のビルドが失敗して、サイトが更新されなかったことがあった。それを防ぐためのスクリプトである。


## 注意点 {#注意点}

-   `all-posts.org` を直しただけでは、サイトは変わらない。 `deploy.sh` は `content/post/` が生成済みであることを前提にしている( `prepare-content.sh` の冒頭コメント)。先に Emacs で ox-hugo のエクスポートを行い、 `content/post/` を更新しておく。更新していなければ、Actions が古い `content/` をビルドするだけである。
-   `g add .` は広く拾う。 `deploy.sh` が案内する手順は `git add content` で、範囲が狭くなっている。作業中の無関係なファイルが混ざっていないか、 `git status` で確認してからのほうが安全である。
-   diff が外部の API に送られる。 `gen-commit-msg.sh` は、ステージした diff を Anthropic API に送る(スクリプトのコメントにも記載がある)。ブログの記事が中心なので問題は小さいが、機密ファイルをステージしていないか注意する。 `ANTHROPIC_API_KEY` が設定されている必要もある。

途中で失敗した場合は、次のようになる。

| 失敗した場所      | 状態                                      |
|-------------|-----------------------------------------|
| deploy.sh         | ビルドエラーで、何も変更されていない      |
| gen-commit-msg.sh | ステージだけが済んだ状態で止まっている    |
| push-and-watch.sh | すでにコミットされている。push 済みか Actions の失敗かは表示で分かる |


## 読んでいない部分 {#読んでいない部分}

`gen-commit-msg.sh` は 271 行ある。この記事では、ロックファイルによる排他などの後半部分は読んでいない。
