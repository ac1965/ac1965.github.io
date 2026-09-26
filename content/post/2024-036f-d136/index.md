+++
title = "このサイトのデプロイについて"
author = ["YAMASHITA Takao"]
date = 2024-03-30T14:52:00+09:00
lastmod = 2026-09-26T22:31:33+09:00
tags = ["Hugo", "GitHubPages", "Deploy"]
categories = ["Tech"]
draft = false
pin = true
+++

世の中にはたくさんのブログサービスがあって、そのお手軽さもそれはそれで魅力的だけど、静的サイトジェネレータには静的サイトジェネレータならではの良さがある。動的サイトのようにレンダリング処理が要らないぶん、表示が速いのもポイント。メモ帳程度の文章をつらつら書くだけなので、あまり凝る必要もない。そんな理由から静的サイトジェネレータを選んでいる。

ドメインは自分で取得したものだけど、サイト自体はあちこち渡り歩いてきた。いまは GitHub Pages を使っている。これまでは作ったコンテンツをローカルの[GitHub Pages](https://github.com/ac1965/ac1965.github.io)のリポジトリに `rsync` してから `git push` していたのだけど、それすら面倒に感じるくらいのオッさんになってきたので、Post を作って `git push` したら自動でデプロイされる方向に切り替えたいと思い始めた。

以下、git アカウントの作成や Hugo サイトの構築、git まわりの設定はすでに済んでいる前提で進める。


## GitHub Pagesでデプロイ {#github-pagesでデプロイ}

-   [GitHub Pages について](https://docs.github.com/ja/pages/getting-started-with-github-pages/about-github-pages)
-   [GitHub Pages](https://pages.github.com)
-   [deploy-page](https://github.com/actions/deploy-pages)

これによると、 **GitHub Pages** には2つのタイプがあるらしい。

-   User or Organization Site
    `https://<username or organization>.github.io/` のURLで公開されるタイプ
-   Project Site
    `https://<username>.github.io/repository/` のURLで公開されるタイプ

リポジトリ名が `username.github.io` 以外の場合は後者になるということがわかった。たぶん、その理解で合っていると思う。

つまり <https://gohugo.io/hosting-and-deployment/hosting-on-github/> のやり方をそのままやると、<https://www.ty07.net/hugo-mysite/> のようなURLで公開されてしまう。期待どおり <https://www.ty07.net> のURLで公開しようとすると、結局 [GitHub Pages](https://github.com/ac1965/ac1965.github.io) のリポジトリに `rsync` してから `git push` する方法しかないのだろうか😓


## すこしたった後に思ったこと。 {#すこしたった後に思ったこと}

[actions-hugo](https://github.com/peaceiris/actions-hugo) を先に読んでいれば、もう少し理解が早かったかもしれない。要するに `https://<username>.github.io/` 側に Hugo の環境を入れて、GitHub Pages にデプロイすればいいということがわかった。

{{< figure src="githubpages-setting.png" >}}

{{< figure src="gitubpages-deplogy.png" >}}

ただ、CNAME がうまく処理されなかったので、結局は以前とほぼ同じデプロイ方法に落ち着いた。

{{<details "deploy.sh">}}
```sh
  #!/bin/bash

  hugo=~/Documents/devel/repos/ac1965.github.io
  public=~/Documents/devel/repos/deploy

  abort ()
  {
      echo -e "\033[1;30m>\033[0;31m>\033[1;31m> ERROR:\033[0m${@}\n" && exit
  }

  info ()
  {
      echo -e "\033[1;30m>\033[0;36m>\033[1;36m> \033[0m${@}\n"
  }

  warn ()
  {
      echo -e "\033[1;30m>\033[0;33m>\033[1;33m> \033[0m${@}\n"
  }

  test -d ${hugo} && cd ${hugo} || abort "${hogo} directory not found."
  # clean public
  rm -fr public

  info "Deploying updates to GitHub..."

  # Build the project.
  hugo # if using a theme, replace with `hugo -t <YOURTHEME>`

  # Go To Public folder
  test -d ${public} && cd ${public} || abort "${public} not found."
  info "rsync.."
  rsync -at --delete --exclude=".git" ${hugo}/public/. .

  # Add changes to git.
  git add .
  git commit -avm "update:$(env LANG=C date)" && git push
```
{{</details>}}
