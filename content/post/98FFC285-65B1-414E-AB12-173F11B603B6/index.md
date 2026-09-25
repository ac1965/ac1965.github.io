+++
title = "画像消失を直しに行ったら、直すべき場所が4つあった話"
author = ["YAMASHITA Takao"]
date = 2026-07-30T01:39:00+09:00
lastmod = 2026-09-25T19:59:32+09:00
tags = ["Hugo", "Ox-Hugo", "PageBundle", "Deploy", "夏"]
categories = ["Tech"]
draft = false
cover = ""
+++

前回、3ヶ月半前から全記事の画像が消えていたことに気づいた話を書いた。
原因は分かったので「あとは直すだけ」のつもりだったのだが、実際に手を
付けてみると、直すべき場所は1箇所どころか4箇所あった。しかも直している
最中に、また別の画像を消すというオチまで付いた。備忘として一通り
記録しておく。


## そもそもの根本原因：flatファイルとPage Bundleの取り違え {#そもそもの根本原因-flatファイルとpage-bundleの取り違え}

うちのHugoサイトは、ox-hugoが記事を `content/post/<slug>.md` という
flatなファイルとして書き出す構成になっていた。カバー画像は
`content/post/<slug>/cover.jpg` という、記事ファイルと同名の別
ディレクトリに `deploy.sh` が機械的に配置する、という運用でずっと
やってきた。

これがそもそもの間違いだった。Hugoの世界では `<slug>.md` と `<slug>/`
は同名でも無関係な存在で、後者はPage Resourceとして認識されない。
Blowfishテーマのカバー画像自動検出（ `.Resources.ByType "image"` ）は
Page Bundle（ `<slug>/index.md` の形）でしか機能しないので、うちの
構成では最初から蚊帳の外だった。 `deploy.sh` が季節画像をローテー
ションで機械的に置き続けていたのは、いわばこの構造的な欠陥を隠す
ための対症療法だったわけだ。


## 直した場所その1：all-posts.org を一括変換 {#直した場所その1-all-posts-dot-org-を一括変換}

ox-hugoには `:EXPORT_HUGO_BUNDLE:` という、まさにこのためのプロパティ
がある。全49記事の `:EXPORT_FILE_NAME: <slug>` を

```org
:EXPORT_HUGO_BUNDLE: <slug>
:EXPORT_FILE_NAME: index
```

に機械的に変換した。Hugoは `<slug>.md` でも `<slug>/index.md` でも
同じ `/post/<slug>/` に解決するので、パーマリンクへの影響はゼロ。
これは気楽に一括変換していい変更だった。


## 直した場所その2： `deploy.sh` のカバー画像配置ロジック {#直した場所その2-deploy-dot-sh-のカバー画像配置ロジック}

ここで最初の見落としに気づいた。カバー画像を置く `place_covers()`
関数は `content/post/*.md` を直接グロブしていたので、記事が
`<slug>/index.md` に変わった瞬間、対象ファイルを1件も見つけられなく
なって沈黙する。グロブを `*/index.md` に変え、post_dirの導出も
文字列結合からindex.mdの親ディレクトリ参照に直した。


## 直した場所その3と4：新規記事が古い形式に戻ってしまう2つの入り口 {#直した場所その3と4-新規記事が古い形式に戻ってしまう2つの入り口}

ここまでで「よし直った」と思っていたのだが、もう2箇所あることに
気づいた。新規記事は `C-c c b` のorg-captureテンプレートから作る
のだが、Emacs設定（ `orgx-core.el` のベース版と、それを上書きする
`personal/ac1965.el` の2箇所）の両方とも `:EXPORT_FILE_NAME:
%(org-id-new)` のままだった。これでは次に書く記事から、また
flat構造に逆戻りしてしまう。

さらにもう1つ。 `all-posts.org` の冒頭には、ネタをAIに投げて記事の
下書きを生成させるためのプロンプトテンプレートを仕込んであるの
だが、その中のPROPERTIESドロワーの見本も `EXPORT_FILE_NAME: <slug>`
のままだった。ソースコードだけ直して、その生成元になるテンプレート
文章を見落とすところだった。地味だが、これを見落とすと「なぜか
たまに古い形式の記事が紛れ込む」という原因不明のバグを将来の自分に
仕込むところだった。


## そして、また画像を消した {#そして-また画像を消した}

一通り直したので、動作確認のつもりで一度 `content/post` を
`rm -rf` してから再exportしてみた。 `content/post` はビルド成果物
なので.gitignore対象、消しても再生成されるだけのはずだった。

ところが、記事本文で使っていたBlowfishのfigure/carouselショートコード
（ `src`"frieren.jpg"= や `images`"inuyama-fest/\*"= のように画像を
直接指定するタイプ）が参照していた画像だけは戻ってこなかった。

理由は単純で、これらはPage Resourceとして `content/post/<slug>/`
直下に **手で置いていただけ** のファイルだった。カバー画像は
`deploy.sh` が毎回決定的に再生成するし、Orgの `[[file:...]]` リンク
はox-hugoが自動でコピーし直してくれる。しかしshortcode内の
`src`"..."= はox-hugoにとってただの文字列で、どの自動生成の仕組みにも
紐づいていなかった。一番安全なはずの「ビルド成果物だから消していい」
という前提が、実はこの種の画像には最初から成り立っていなかった、
というわけだ。


## deployブランチという名の保険 {#deployブランチという名の保険}

さすがに焦ったが、幸い逃げ道が残っていた。うちの `deploy.sh` は
ビルド後の `public/` を、sourceとは別の `deploy` ブランチにpushして
いる。つまり、公開されているHTML・画像そのものが独立したGit履歴を
持っているということだ。

GitHubのTrees APIで `deploy` ブランチの履歴を遡り、3月21日の大量
削除が起きる直前、最後に正常だったdeployコミットを特定した。そこから
Hugoのリサイズキャッシュ（ `*_hu_<hash>.*` ）を除いた **オリジナル
ファイルだけ** を掘り出したところ、10記事・37ファイル、 `frieren.jpg`
も `inuyama-fest/` の写真11枚も無事に発見できた。全ファイル、コミット
時点のGit blobサイズと突き合わせて一致を確認済みで、EXIF情報から
撮影日時まで読み取れる、正真正銘のオリジナルだった。

これを機に、 `assets/img/post-assets/<slug>/` という「正本置き場」を
新設し、 `deploy.sh` に `sync_post_assets()` を追加した。build毎に
ここから `content/post/<slug>/` へ同期するので、以後は `rm -rf
content/post` してもこの種の画像はもう消えない。


## しめに {#しめに}

「カバー画像のローテーションがおかしい」から始まった話が、Page
Bundleへの構造変更、Emacs側の2つの入り口、AIプロンプトテンプレート、
そして本文画像そのものの消失発覚と、芋づる式に広がっていった。

一番の教訓は、「ビルド成果物だから消していい」という前提は、何に
よってどう再生成されるかを1つずつ確認しない限り信用してはいけない、
ということだった。cover.jpgとインライン画像は見た目には
同じ「content/post配下のファイル」だが、裏の仕組みはまったく別物
だった。今回はたまたまdeployブランチという保険が効いたからよかった
ものの、無ければ本当に取り返しがつかなかった。

直すべき場所を1つ見つけるたびに、もう1つ見つかる。地味に骨の折れる
作業だったが、これで少なくとも同じ事故は起きなくなったはずだ。


## 参考：Page Bundleとは {#参考-page-bundleとは}

なぜflatファイルとPage Bundleを取り違えるとこんなことになるのか、
ここで改めて整理しておく。

{{< accordion mode="collapse" >}}

{{< accordionItem title="Leaf Bundle と Branch Bundle" >}}
Hugoでは通常、1つのコンテンツファイル（`.md`）が1ページに対応する。
**Page Bundle**は、そのファイルと関連リソース（画像など）を同じ
ディレクトリにまとめる仕組みで、2種類ある。

- **Leaf Bundle**：`index.md`を含み、子ページを持たないバンドル
  （例: `content/post/my-post/index.md`）
- **Branch Bundle**：`_index.md`を含み、子ページを持てるバンドル
  （セクションのトップページなど）

今回の記事群は`<slug>.md`という素の`.md`ファイルだった。同名の
`<slug>/`ディレクトリを隣に置いても、Hugoから見ればこの2つは無関係な
存在で、後者はPage Resourceとして認識されない。
{{< /accordionItem >}}

{{< accordionItem title="なぜこの構造がいいのか" >}}
「1記事＝1つのまとまり」という単位で、コンテンツと素材を同じ場所に
置けるのが本質。バンドル内のファイルは`.Resources`経由でテンプレート
から直接参照でき、リサイズ・フォーマット変換・fingerprintなどの画像
処理をパス指定なしで書けるようになる。
{{< /accordionItem >}}

{{< accordionItem title="メリット" >}}
- 記事の削除・移動がディレクトリ単位で完結し、画像の消し忘れが起きにくい
- 相対パスで画像参照を書ける（`![](cover.jpg)`）
- `.Resources.GetMatch`などのPage Resources APIが使える
- `headless: true`で「素材だけ共有する」バンドルも作れる
{{< /accordionItem >}}

{{< accordionItem title="デメリット" >}}
- 記事数だけディレクトリが増え、一覧性が下がる
- Branch Bundle配下の非indexページはPage Resourceになれない、という制約
- ox-hugo側の対応（`EXPORT_HUGO_BUNDLE`＋`EXPORT_FILE_NAME: index`）が
  必須で、既存記事は一括変換が要る
- ビルド・デプロイスクリプト側も`<slug>.md`から`<slug>/index.md`への
  パス変更に追従できていないと、今回のように静かに壊れる
{{< /accordionItem >}}

{{< /accordion >}}
