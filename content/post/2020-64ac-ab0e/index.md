+++
title = "Hugo"
author = ["YAMASHITA Takao"]
date = 2020-10-27T22:46:00+09:00
lastmod = 2026-09-26T22:31:33+09:00
tags = ["Hugo"]
categories = ["Tech"]
draft = false
cover = "custom/2020-64ac-ab0e.jpg"
+++

## Hexo から Hugo {#hexo-から-hugo}

サイトジェネレータを [Hugo](https://gohugo.io) に変えてみた。インストールといっても homebrew を使うので簡単 :grin:

[EMOJI-CHEAT-SHEET](https://www.webfx.com/tools/emoji-cheat-sheet/)


## インストール {#インストール}

[Homebrew](https://brew.sh/index_ja) はインストール済みという前提で進める。

```sh
$ brew update
$ brew install hugo
```

テーマは [conao3さん](https://conao3.com) の [anatole-ext](https://github.com/conao3/anatole-ext) にすることにした。

```sh
$ hugo new site hoge
$ cd hoge
$ git clone https://github.com/conao3/anatole-ext themes/anatole-ext
$ hugo new posts/first-article.md
```

これで hoge ディレクトリーが作成され、その配下に雛形が作成される。


## 自分用のメモ {#自分用のメモ}


### 展開 {#展開}

```sh
$ git clone git@github.com:ac1965/hugo.git ./hugo-blog
$ cd hugo-blog
$ git clone git@github.com:ac1965/anatole-ext themes/anatole-ext
$ hugo
```

hugo コマンドを実行すると、public ディレクトリの下にコンテンツが生成される。


### \`deploy.sh' {#deploy-dot-sh}

hexo と大きく違うのは、デプロイの仕組みが利用者まかせになっているところ。

私の環境では本体用と公開用でリポジトリを分けていて、本体は hugo-blog、公開用は ac1965.github.com として管理している。

{{<details "deploy.sh">}}
```sh
  #! /bin/bash

  hugo=~/devel/repos/hugo-blog
  public=~/devel/repos/ac1965.github.io

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
  test -d ${public} && cd ${public} || exit
  info "rsync.."
  rsync -at --delete --exclude=".git" ${hugo}/public/. .

  # Add changes to git.
  git add .
  git commit -avm "update:$(env LANG=C date)" && git push
```
{{</details>}}
