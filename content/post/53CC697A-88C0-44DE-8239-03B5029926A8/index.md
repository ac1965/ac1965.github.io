+++
title = "py2appバンドルの署名が壊れる不具合を追いかけた顛末"
author = ["YAMASHITA Takao"]
date = 2026-08-23T10:29:00+09:00
lastmod = 2026-09-25T19:59:32+09:00
tags = ["macOS", "py2app", "codesign", "Python"]
categories = ["Tech"]
draft = false
cover = ""
+++

なろう小説をEPUB化する自作ツール narou_dl に、py2app で macOS 用の
`.app` バンドルを作る仕組みを足していた。 `make install-app` を叩けば
ビルドして `/Applications` に放り込むだけ、のはずだったのだが、ある日
そのビルドが署名エラーで丸ごと落ちるようになった。原因を追ったら一日仕
事の潜り込みになったので、記録しておく。

リポジトリはこちら: <https://github.com/ac1965/narou_dl/>


## 事件発生 {#事件発生}

`make install-app` の途中、 `codesign` が `liblzma.5.dylib` というファ
イルに対して次のようなエラーを吐いて止まった。

```text
liblzma.5.dylib: main executable failed strict
validation
```

このファイル自体は narou_dl のコードには出てこない。心当たりがないまま
まずは事実確認から始めた。


## 原因調査 {#原因調査}

たどっていくと、犯人は narou_dl 本体ではなく依存先だった。PDF出力機能
で使っている `reportlab` が `Pillow` を引っ張ってきており、その
`Pillow` が自前の `liblzma.5.dylib` を同梱している。py2app がこのファ
イルをバンドル内にコピーする際、 `macholib` が install name を書き換え
るのだが、このとき対象がすでに署名済みのバイナリだと、Mach-O の
`LC_CODE_SIGNATURE` が壊れる、というのが実体だった。

厄介なのは、壊れ方が「その場で直せない」方向だったこと。 `codesign
--sign -` で再署名しようとしても失敗するし、それなら署名を剥がしてから
付け直せばいいだろうと `codesign --remove-signature` を試しても、今度
は次のエラーで弾かれる。

```text
internal error in Code Signing subsystem
```

つまり壊れた後のファイルは、署名の追加も削除もできない、正真正銘の壊れ
たバイナリになっていた。


## 迷走 {#迷走}

「直せないなら消してしまえばいい」と考えて `liblzma.5.dylib` をバンド
ルから削除してみたが、これは別の壊れ方を引き起こした。=PIL._imaging=
の依存チェーンをたどると `libtiff.6.dylib` が=liblzma.5.dylib= を必要
としており、消してしまうと今度は=from PIL import Image= 自体が読み込め
なくなる。結果として=reportlab= も道連れでインポート不能になり、PDF出
力機能が丸ごと死ぬ。削除は解決策になっていなかった。


## 突破口 {#突破口}

切り分けのために、壊れる条件そのものを手元で再現する実験をした。すでに
署名済みのファイルに対して `install_name_tool -id` でinstall name を書
き換えてから署名すると、確かに壊れる。ところが、順番を変えて「先に
`codesign --remove-signature` で署名を剥がしてから `install_name_tool
-id` で書き換え、その後で署名し直す」と、これは問題なく通った。

つまり壊れる原因は「すでに署名されているファイルの install name を書き
換える」という操作そのものにあり、署名前の状態から組み立て直せば何の問
題もない、ということがここで確定した。


## 対処 {#対処}

とはいえ、py2app 自身がこの書き換えを内部で行っているため、ビルドスク
リプト側でその手順に割り込むのは現実的ではない。そこで発想を変え、「壊
れたファイルを直す」のではなく「バンドル内のどこかに残っている壊れてい
ない同名ファイルで上書きする」方式にした。

`scripts/trim_macos_bundle.py` に `fix_corrupted_dylibs()` を追加し、
バンドル内の `.dylib` / `.so` をファイル名単位で総当たりして、署名に失
敗するファイルがあれば、同じ名前で署名が通る「健全な」コピーをバンドル
内の別の場所から探し、そのバイト列で壊れたファイルを上書きするようにし
た。ただし install name(`-id`)はコピー先ごとに異なるので、上書き前に
`otool -D` で壊れていた方の元の `-id` を控えておき、上書き後に付け直し
てから署名する。


## 副産物: Qtプラグインの消失 {#副産物-qtプラグインの消失}

この調査の途中で、無関係に見えるもう一つの不具合も見つかった。
`trim_macos_bundle.py` は不要な Qt のサブディレクトリを削除する処理を
持っており、その削除対象リストに `plugins` が丸ごと入っていた。これは
通常、py2app が `Contents/Resources/qt_plugins` にプラグインの複製を別
途作ってくれるため安全だったのだが、ビルドによっては py2app がその複製
を作らず、 `PySide6/Qt/plugins/platforms/=の中にしか =libqcocoa.dylib`
が存在しないケースがあった。この場合、一律削除によって唯一のコピーごと
消えてしまい、起動時に「Could not find the Qt platform plugin cocoa」
で落ちる。

削除対象リストから `plugins` を外し、代わりに本当に不要なサブディレク
トリだけを個別に指定するリストに切り替えた。あわせて、
`libqcocoa.dylib` の場所をハードコードせず、バンドル内を探索して動的に
見つけるようにもした。


## 結果 {#結果}

修正後、クリーンな状態からの `make install-app` が最初から最後まで通る
ことを確認した。署名の検証も通り、 `/Applications` に入ったアプリが起
動し、PDF出力機能(`reportlab` 経由)も問題なく動作した。

原因は一言でまとめると「すでに署名済みのファイルの install name を書き
換えると、その場で修復不能な形でMach-Oの署名が壊れる」という、
py2app(というよりmacholibのMach-O書き換え処理)の落とし穴だった。ピンポ
イントで直すのではなく、壊れていない同名ファイルで上書きする、という一
段回り道した対処に落ち着いたのが今回の顛末。

{{<figure src="screenshot_narou-dl.png" width="50%" height="50%">}}
