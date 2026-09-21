+++
title = "Makefile が自分自身を tangle する設定で、実機でしかハマらないバグを4連発踏んだ話"
author = ["YAMASHITA Takao"]
date = 2026-08-01T20:24:00+09:00
lastmod = 2026-09-21T15:24:01+09:00
tags = ["Emacs", "Org-Mode", "Makefile", "Graphviz", "Mermaid", "デバッグ"]
categories = ["Tech"]
draft = false
cover = ""
+++

前回、 `README.org` の Makefile ブロックでタブが壊れる話を書いたけど、あの後も
続きがあった。実際に手元で `make reload` や `make diagrams` を叩くたびに、
サンドボックス環境の検証だけでは踏めない類のバグが次々出てきて、結局4段階の
実機デバッグになった。せっかくなので記録として残しておく。

**最初の直しが別のバグを生んだ**

タブが `org-babel-tangle` に飲み込まれる問題、最初は `.RECIPEPREFIX :` &gt;= で
recipe行の先頭マーカーをタブ以外の文字に変える案で直したつもりだった。だがこれは
GNU Make 3.82以降の機能で、macOS標準の `/usr/bin/make` はGPLv3回避のため3.81に
凍結されている。案の定、手元で試してもらったら:

```text
Makefile:87: *** missing separator.  Stop.
```

同じエラーが別の行で再発した。バージョン依存の機能に頼ったのが失敗で、結局
本物のタブ文字に戻し、 `org-src-preserve-indentation` を `t` にして tangle時の
インデント除去処理自体を無効化する方式に変更した。

**その修正がまた別のファイルを壊した**

ところがこの `org-src-preserve-indentation` を `(setq ...)` で **グローバルに**
設定したのが次の落とし穴だった。README.org は1回のEmacsセッションで全ブロックを
tangleするので、Makefileだけでなく `early-init.el` や `lisp/*.el` 全部に
この設定が波及してしまい、org側の見た目そろえ用スペースが `early-init.el` の
1行目（ `lexical-binding` cookie）にまで残ってしまった。結果、Emacs起動時に
こんな警告が出た。

> Warning (files): Missing 'lexical-binding' cookie in "~/.emacs.d-stable/early-init.el".

直し方は2段階tangleにすること。1段階目は普通に（indentation preserveなし）
全ブロックをtangleして `early-init.el` 等を正しく生成し、2段階目で
`org-babel-tangle-file` の言語フィルタ引数に `\"makefile\"` だけを渡して、
Makefileブロックだけを preserve-indentation=t で再tangleする。これで両方
正しくなった。

**leafマクロが理由不明のまま原因不特定になった件**

Makefile周りが片付いたところで、今度は実際の起動ログから `ui-which-key`
モジュールが読み込み失敗しているのが見つかった。

```text
[modules] Failed to load ui-which-key: Symbol's value as variable is void: which-key
```

該当箇所は `leaf which-key` を `:straight` と `:if` の組み合わせで
Emacs 30以降／未満に条件分岐させていた部分。手元にEmacs 30系が無かったので、
straight・leaf・leaf-keywordsを実際にブートストラップして単体評価まで試したが、
正直なところ `leaf-keywords.el` の `:straight` 拡張内部の正確な原因までは
特定しきれなかった。原因究明より実利を取って、 `leaf` マクロを経由せず
素の `(when (< emacs-major-version 30) (straight-use-package 'which-key))`
に書き換えることで問題自体を回避した。

**Puppeteerのバージョン固定にも足をすくわれた**

図版のMermaidレンダリング（ `mmdc` ）でも似たようなことが起きた。エラーメッセージは
素直に「Chromeが見つからない」と言っていて、Puppeteer公式の案内通り
`npx puppeteer browsers install chrome-headless-shell` を勧めたのだが、これが
外れだった。 `mmdc` が同梱する `puppeteer-core` は特定バージョンのChromeに
ピン留めされているため、システムに最新版を入れても一致せず、同じエラーが
再発し続けた。

{{< details summary="実機で確認した回避策" >}}
**確実な直し方**は `PUPPETEER_CONFIG` に `executablePath` を明示すること。
バージョンが一致していなくても、実行ファイルのパスさえ指定すれば
puppeteer側のバージョンチェック自体を素通りしてくれる。普段使いのGoogle Chromeを
そのまま指定すれば、新規ダウンロードも不要だった。
{{< /details >}}

**結局16枚全部揃った**

最終的に `dot-tangle` / `dot-svg` / `mmd-tangle` / `mmd-svg` を1つにまとめた
`make diagrams` で、design_spec.org側13枚 ＋ README.org側3枚の計16枚が
問題なくレンダリングされるところまで確認できた。

サンドボックスでの検証だけでは絶対に踏めないバグ（Makeのバージョン差、
tangleの副作用範囲、leafマクロの内部実装、puppeteerのバージョン固定）が
4段階連続で出てきて、そのたびに「サンドボックスでは動いたのに」という
展開になった。実機で試してもらうまで確信が持てない類の不具合が、こんなに
積み重なるとは思っていなかった
