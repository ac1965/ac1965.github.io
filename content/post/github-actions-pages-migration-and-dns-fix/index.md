+++
title = "ブログの公開をGitHub Actionsに移したら、10年前のDNSの古傷が出てきた話"
author = ["YAMASHITA Takao"]
date = 2026-09-21T14:27:00+09:00
lastmod = 2026-09-21T15:24:01+09:00
tags = ["Hugo", "GitHubPages", "Cloudflare", "DNS", "Ox-Hugo", "Deploy"]
categories = ["Tech"]
draft = false
cover = ""
+++

ty07.netのビルド・公開は、ずっと自分のマシンから `deploy.sh` を手で叩くだけの運用にしていた。Hugoでビルドして、公開用ディレクトリに `rsync` して、そのまま `git push` する。素朴だけど、自分しか触らない前提なら十分だと思っていた。

これをGitHub Actions側に寄せる作業をした日、思わぬところで10年近く前の古傷を見つけることになった。


## まず、公開の仕組みだけをGitHub Actionsに任せることにした {#まず-公開の仕組みだけをgithub-actionsに任せることにした}

記事の変換（org-modeからHugo用Markdownへの変換）は、これまでどおりEmacsの ox-hugo に任せることに決めた。実は `org2hugo.py` というPythonだけで変換を再現するスクリプトも用意してあって、これを使えばCI側だけで完結できなくもない。ただ、このスクリプト自身のコメントに「ox-hugoの出力と完全一致する保証はない」と書いてあるとおり、まだ検証しきれていない代替経路だ。個人ブログとはいえ、いきなり本番公開の唯一の入口に据えるのはリスクに見合わないと判断して、変換はox-hugoのまま残すことにした。

代わりに変えたのは「公開」の部分だけ。具体的には、

-   これまで `.gitignore` に入れて無視していた `content/post/` を、Git管理下に置くようにした
-   `deploy.sh` からHugoビルド以降の処理（ビルド・rsync・push）を全部剥がして、画像同期とカバー画像の自動配置だけを行う `prepare-content.sh` という薄いスクリプトに分離した
-   `.github/workflows/pages.yml` を新規作成し、pushをトリガーに `hugo --minify` でビルドして `actions/deploy-pages` でGitHub Pagesに公開する、という流れをGitHub Actions側に持たせた

{{<details "pages.ymlの中身(抜粋)">}}
```yaml
name: Deploy to GitHub Pages

on:
  push:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read
  pages: write
  id-token: write

env:
  HUGO_VERSION: "0.165.0"

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive
      - uses: peaceiris/actions-hugo@v3
        with:
          hugo-version: ${{ env.HUGO_VERSION }}
          extended: true
      - run: hugo --minify
      - uses: actions/upload-pages-artifact@v3
        with:
          path: ./public

  deploy:
    needs: build
    runs-on: ubuntu-latest
    steps:
      - uses: actions/deploy-pages@v4
{{</details>}}

Hugoのバージョンは、Blowfishテーマが要求する範囲（0.162.0〜0.165.0）に収まるよう `0.165.0` に固定した。ローカルの `hugo version` を見たら `v0.166.0` で、実はテーマの上限を超えていた。ローカルでは動いていたので気づいていなかった。


## 切り替えたら、想定より早く終わっていた {#切り替えたら-想定より早く終わっていた}

手順としては「①contentをpush→②buildジョブの成功だけ確認→③Pages SourceをGitHub Actionsに切り替え→④再実行してdeployまで通す」という、慎重に段階を踏むつもりだった。Sourceを先に切り替えると、まだ一度もActionsからのデプロイが無い状態でサイトが404になりかねないからだ。

ところが実際にpushしてみたら、buildジョブだけでなくdeployジョブまで一発で成功していた。Settings画面を見ると、Sourceの表示はまだ「Deploy from a branch」のままなのに、「Your site was last deployed to the github-pages environment by the Deploy to GitHub Pages workflow」という一文があり、実体はもうActions側に切り替わっていた。表示と実態がねじれた中途半端な状態だったので、あらためてSourceを明示的に「GitHub Actions」に切り替えて、表示と実態を一致させた。

後片付けとして、使わなくなった `deploy` ブランチと、ローカルの別クローン（ `~/Projects/blog/deploy` ）を削除した。もう一つ、pushしたコミットのメッセージが「以下は、提供された変更内容に基づく解説と確認ポイントです。」という、AIの応答の前置き文がそのまま件名になってしまっていたのも見つけて、 `commit --amend` と `push --force-with-lease` で直した。


## 本題：Enforce HTTPSがどうしても有効化できない {#本題-enforce-httpsがどうしても有効化できない}

一通り片付いたところで、GitHub PagesのSettingsに気になる表示が残っていた。「Enforce HTTPS」がグレーアウトしていて、理由は「your domain is not properly configured to support HTTPS」。サイト自体は `https://www.ty07.net/` で普通に開けるので、最初は気にしていなかった。

調べてみると、原因はCloudflareだった。 `www.ty07.net` のDNSがCloudflareの「プロキシ有効（オレンジクラウド）」になっていて、GitHubが直接ドメインの所有権を検証できずにいた。実際に証明書を確認すると、訪問者が見ているのはCloudflareが発行した証明書（発行者 Google Trust Services、CN=ty07.net）で、GitHub自身の証明書ではなかった。

ここで「じゃあプロキシを切ればいい」という単純な話では済まなかった。 `www.ty07.net` のAレコードを見ると2本あり、指しているIPが `192.30.252.153` と `192.30.252.154` 。この2つに直接アクセスして証明書を確認したら、返ってきたのは `.github.io` ではなく `.github.com` の証明書だった。何年も前に廃止されたGitHub Pagesの旧IPアドレスが、そのまま放置されていたということだ。今サイトが正常に見えていたのは、Cloudflareのプロキシがこの壊れたIPへの直接アクセスを覆い隠し、正しいGitHub Pagesへ橋渡ししてくれていたからにすぎない。もしプロキシのチェックを外すだけの対応をしていたら、その瞬間にサイトが表示されなくなっていたはずだ。


## Cloudflareを丸ごと切る、という選択肢は取らなかった {#cloudflareを丸ごと切る-という選択肢は取らなかった}

この際Cloudflareのサービス自体（ネームサーバー）をやめてしまう手も考えたが、調べてみると `ty07.net` のDNSゾーンには、メールアドレス `ac1965@ty07.net` の実体（iCloudのカスタムメールドメイン機能によるMX・SPF・DKIMのレコード）が生きていた。ネームサーバーの委任先を変えるということは、このドメイン全体に関わる大掛かりな変更になり、しかも一つでも移行漏れがあればメールが届かなくなる。ブログのHTTPS証明書の見た目を整えるために背負うリスクとしては見合わないと判断し、あくまで `www` の1レコードだけをピンポイントで直す方針にした。


## flarectlで、必要最小限の権限のトークンを作って直す {#flarectlで-必要最小限の権限のトークンを作って直す}

Cloudflareの公式CLIである `flarectl` を導入し、権限を「 `ty07.net` のDNS編集のみ」に絞った一時APIトークンを発行した。最初にテンプレートから作ろうとしたら「すべてのゾーン」向けの権限や、WAF・Bot Management・Page Rulesまで含む広すぎる権限がまとまって付いてくる場面が何度かあり、「最初から作成」でDNSの権限グループだけを選び直す、というやり取りを何往復かした。

最終的に、廃止済みのAレコード2本を削除して、GitHub公式が推奨する構成——www → CNAME → `ac1965.github.io` （プロキシなし）——に張り替えた。

{{<details "実行したflarectlコマンド">}}

flarectl dns delete --zone=ty07.net --id=6a3fa95634d332428d447e4b10e66a1f
flarectl dns delete --zone=ty07.net --id=fdc46e1d79ad38890153b81dc4109635
flarectl dns create --zone=ty07.net --name=www --type=CNAME --content=ac1965.github.io --ttl=1
{{</details>}}

張り替えた直後は、GitHubがまだ `www.ty07.net` 専用の証明書を発行し終えておらず、HTTPSでアクセスすると証明書エラーが出る一時的な状態になった。数分待ってから確認すると、GitHub自身が発行したLet's Encrypt証明書（CN=www.ty07.net）に切り替わっており、Enforce HTTPSも有効化できた。


## ついでに、裸のドメインにも同じ問題が隠れていた {#ついでに-裸のドメインにも同じ問題が隠れていた}

これで解決したと思っていたら、Settings画面に別の警告が出ていることに気づいた。「ty07.net is improperly configured — Domain does not resolve to the GitHub Pages server (NotServedByPagesError)」。 `www` を外した裸のドメイン `ty07.net` の方だ。

調べると、こちらは今回の一連の変更が原因ではなく、そもそも `ty07.net` にはAレコードもAAAAレコードも一切存在しなかった。GitHub Pagesは、 `www` をカスタムドメインに設定すると、裸のドメインからも `www` へリダイレクトできるかを合わせてチェックする仕様らしい。サイトの主機能には影響しない話だが、ついでに直しておくことにして、GitHub公式の4つのAレコード（185.199.108〜111.153）を `ty07.net` に追加した。これでSettings画面の表示も「DNS check successful」に変わり、裸のドメインでアクセスしてもきちんと `https://www.ty07.net/` にリダイレクトされるようになった。


## 振り返って {#振り返って}

実はこの話には前史がある。[以前書いた「このサイトのデプロイについて」という記事](https://www.ty07.net/post/2024-036f-d136/)を読み返すと、2024年の時点で一度、自動デプロイを試みてCNAMEの設定がうまく処理されず、結局Hugoの成果物を `rsync` して `git push` するだけの手動スクリプトに倒した、という記録が残っていた。当時は「とにかく動く形」に落ち着けることを優先して、CNAMEがなぜうまく処理されなかったのかまでは詰めなかったのだと思う。今回見つかった「廃止済みのGitHub旧IPが何年も放置されていた」問題は、まさにあの時に先送りした宿題が、2年半ほど経ってようやく回ってきた形だった。

一番印象に残ったのは、Cloudflareのプロキシが表面上の問題を何年も覆い隠していたという点だ。サイトは実際に正常に見えていたし、誰も困っていなかった。けれどその裏では、GitHub Pages側の設定が静かに腐っていた。プロキシやCDNを経由した構成のトラブルを追いかけるときは、見えている結果だけで判断せず、オリジン側に直接アクセスして実体を確認する、という手間を惜しんではいけないと思った。

作業に使った一時的なAPIトークンは、当然だけど用が済んだらすぐに失効させておいた。
