+++
title = "Blowfish（Hugoテーマ）のショートコード使い方まとめ"
author = ["YAMASHITA Takao"]
date = 2026-07-27T21:57:00+09:00
lastmod = 2026-09-25T19:59:32+09:00
tags = ["Hugo", "Blowfish", "Ox-Hugo", "Shortcode"]
categories = ["Tech"]
draft = false
+++

参照元は [nunocoracao/blowfish](https://github.com/nunocoracao/blowfish) の exampleSite ドキュメントと [公式サイトのshortcodesページ](https://blowfish.page/docs/shortcodes/)（2026年7月確認）。

ox-hugoでタングル/エクスポートする前提なので、ショートコードを書く部分は全部 `#+begin_export hugo` 〜 `#+end_export` で囲んである。org地の文（説明・表）はそのままMarkdownとして出力されるので、export ブロックは不要。

org-mode的には「構文そのものを文字として見せたいexportブロック」と「実際にHugoに変換させて機能させるexportブロック」は区別が必要である。 `#+begin_export hugo` はox-hugoに素通しされて実際にレンダリングされてしまうので、構文自体を文字として見せたい場合は `#+begin_example=（または =#+begin_src org=）で一段リテラル化してから、その直後に本物の =#+begin_export hugo` ブロックを続ける、という2段構成にしている。

ただし `#+begin_example` で囲んだだけでは不十分だった。Hugoのショートコード展開は、囲んでいるのがMarkdownのコードフェンスかどうかを見ずに、ファイル全体のテキストから波括弧2つのショートコード記法を機械的に探して実行してしまうため、コードブロックの中に書いた例文もそのまま実行されてビルドエラーや取得失敗の原因になる。これを防ぐには、Hugo公式のショートコードのエスケープ記法を使う必要がある。開き括弧の直後と閉じ括弧の直前に「/\* 」「 \*/」を挟むと、実行されずに文字通りの文字列としてそのまま出力される。以下すべての節の「書き方はこう」の例では、この記法で統一した。


## Alert（警告・注意喚起ボックス） {#alert-警告-注意喚起ボックス}

記事内に目立つメッセージボックスを表示する。中身は Markdown 記法。

書き方はこうなる。

```text
#+begin_export hugo
{{</* alert */>}}
**Warning!** This action is destructive!
{{</* /alert */>}}
#+end_export
```

実際にレンダリングすると、こう表示される。

{{< alert >}}
**Warning!** This action is destructive!
{{< /alert >}}

アイコン付き・色指定もできる。

```text
#+begin_export hugo
{{</* alert icon="fire" cardColor="#e63946" iconColor="#1d3557" textColor="#f1faee" */>}}
This is an error!
{{</* /alert */>}}
#+end_export
```

{{< alert icon="fire" cardColor="#e63946" iconColor="#1d3557" textColor="#f1faee" >}}
This is an error!
{{< /alert >}}

| パラメータ | 説明                                   |
|-------|--------------------------------------|
| icon      | 任意。左側アイコン名。デフォルト: triangle-exclamation |
| iconColor | 任意。アイコン色（hex or カラー名）    |
| cardColor | 任意。カード背景色                     |
| textColor | 任意。テキスト色                       |


## Admonition（GitHub/Obsidian 風コールアウト） {#admonition-github-obsidian-風コールアウト}

これはショートコードではなく Hugo の render hook 経由のMarkdown拡張構文。 `#+begin_export hugo` で囲む必要はなく、そのままorg内でblockquote記法として書ける（ただしox-hugo側でblockquoteへの変換確認が必要。確実に反映したい場合はexportブロック推奨）。

書き方はこう。

```text
#+begin_export hugo
> [!TIP]
> A Tip type admonition.

> [!TIP]+ Custom Title + Custom Icon
> A collapsible admonition with custom title.
{icon="twitter"}
#+end_export
```

実際にレンダリングすると、こう表示される。

> [!TIP]
> A Tip type admonition.

> [!TIP]+ Custom Title + Custom Icon
> A collapsible admonition with custom title.
{icon="twitter"}

対応タイプはGitHub系（NOTE / TIP / IMPORTANT / WARNING / CAUTION）とObsidian系（note / abstract / info / todo / tip / success / question / warning / failure / danger / bug / example / quote）。=+= / `-` で折りたたみ制御もできる（Obsidian互換）。


## Accordion（アコーディオン／折りたたみパネル） {#accordion-アコーディオン-折りたたみパネル}

書き方はこう。

```text
#+begin_export hugo
{{</* accordion mode="open" separated=true */>}}
  {{</* accordionItem title="Markdown example" icon="code" open=true */>}}
  本文（Markdown）
  {{</* /accordionItem */>}}

  {{</* accordionItem title="Shortcode example" md=false */>}}
  {{</* alert */>}}インラインアラート{{</* /alert */>}}
  {{</* /accordionItem */>}}
{{</* /accordion */>}}
#+end_export
```

実際にレンダリングすると、こう表示される。

{{< accordion mode="open" separated=true >}}
  {{< accordionItem title="Markdown example" icon="code" open=true >}}
  本文（Markdown）
  {{< /accordionItem >}}

  {{< accordionItem title="Shortcode example" md=false >}}
  {{< alert >}}インラインアラート{{< /alert >}}
  {{< /accordionItem >}}
{{< /accordion >}}

| パラメータ | 説明                                      |
|-------|-----------------------------------------|
| mode      | collapse（単一展開）/ open（複数展開）。デフォルト collapse |
| separated | true で各項目を独立カード表示             |
| title     | 必須。ヘッダタイトル                      |
| open      | デフォルトで開いた状態にする              |
| icon      | タイトル前のアイコン                      |
| align     | left / center / right                     |


## Ansible Galaxy Card {#ansible-galaxy-card}

書き方はこう。

```text
#+begin_export hugo
{{</* ansible role="geerlingguy.docker" */>}}
{{</* ansible collection="community.general" */>}}
#+end_export
```

実際にレンダリングすると、こう表示される。

{{< ansible role="geerlingguy.docker" >}}
{{< ansible collection="community.general" >}}

`role` または `collection` のどちらか一方を指定する（ビルド時に `resources.GetRemote` で取得、ブラウザ側では更新されない）。


## Article（記事埋め込み） {#article-記事埋め込み}

書き方はこう。

```text
#+begin_export hugo
{{</* article link="/docs/welcome/" showSummary=true compactSummary=true */>}}
#+end_export
```

実際にレンダリングすると、こう表示される。

{{< article link="/docs/welcome/" showSummary=true compactSummary=true >}}

| パラメータ     | 説明                    |
|-----------|-----------------------|
| link           | 必須。埋め込み先の .RelPermalink |
| showSummary    | 任意。サマリー表示可否  |
| compactSummary | 任意。コンパクト表示    |

サブフォルダ運用時はパスを含めて指定する必要がある。


## Badge {#badge}

書き方はこう。

```text
#+begin_export hugo
{{</* badge */>}}
New article!
{{</* /badge */>}}
#+end_export
```

実際にレンダリングすると、こう表示される。

{{< badge >}}
New article!
{{< /badge >}}


## Button {#button}

書き方はこう。 `pageRef` は存在する内部ページのパスを指定する必要があるので、ここでは記法例として `docs/getting-started` を挙げているが、実際に使う際はサイト内の実在パスに置き換えること（存在しないパスを `pageRef` に渡すとビルド時に `REF_NOT_FOUND` エラーになりビルド自体が止まる）。

```text
#+begin_export hugo
{{</* button href="#button" target="_self" */>}}
Call to action
{{</* /button */>}}

{{</* button pageRef="docs/getting-started" */>}}
Get started
{{</* /button */>}}
#+end_export
```

`href` 版（任意URL/アンカー）はそのままレンダリングできる。

{{< button href="#button" target="_self" >}}
Call to action
{{< /button >}}

`pageRef` （内部ページ参照）と `href` （任意URL）が併用時は `pageRef` 優先。 `target` / `rel` も指定できる。


## Carousel（画像カルーセル） {#carousel-画像カルーセル}

書き方はこう。 `captions` の中の `*formatting*` もMarkdown記法（斜体）である点に注意。

```text
#+begin_export hugo
{{</* carousel images="gallery/*" aspectRatio="21-9" interval="2500" */>}}

{{</* carousel images="gallery/*" captions="{01.jpg:First image with *formatting*,02.jpg:Second image}" */>}}
#+end_export
```

実際にレンダリングすると、こう表示される。

{{< carousel images="gallery/*" aspectRatio="21-9" interval="2500" >}}

{{< carousel images="gallery/*" captions="{01.jpg:First image with *formatting*,02.jpg:Second image}" >}}

| パラメータ  | 説明                            |
|--------|-------------------------------|
| images      | 必須。画像名/URLにマッチする正規表現 |
| captions    | 任意。key:caption 形式リスト（Markdown可） |
| aspectRatio | 任意。デフォルト 16-9           |
| interval    | 任意。自動スクロール間隔(ms)。デフォルト 2000 |


## Chart（Chart.js グラフ） {#chart-chart-dot-js-グラフ}

書き方はこう。

```text
#+begin_export hugo
{{</* chart */>}}
type: 'bar',
data: {
  labels: ['Tomato', 'Blueberry', 'Banana'],
  datasets: [{ label: '# of votes', data: [12, 19, 3] }]
}
{{</* /chart */>}}
#+end_export
```

実際にレンダリングすると、こう表示される。

{{< chart >}}
type: 'bar',
data: {
  labels: ['Tomato', 'Blueberry', 'Banana'],
  datasets: [{ label: '# of votes', data: [12, 19, 3] }]
}
{{< /chart >}}

Chart.jsの設定をそのまま記述する。


## Code Importer（外部コード取り込み） {#code-importer-外部コード取り込み}

書き方はこう。=url= は実在するファイルのraw URLを指定する必要があり、ここでのURLは記法説明用のプレースホルダーなので実レンダリングはしていない（プレースホルダーのままビルドすると `unable to fetch` の警告が出る）。

```text
#+begin_export hugo
{{</* codeimporter url="https://raw.githubusercontent.com/.../mdimporter.html" type="go" startLine="11" endLine="18" */>}}
#+end_export
```

| パラメータ          | 説明            |
|----------------|---------------|
| url                 | 必須。外部コードファイルURL |
| type                | シンタックスハイライト言語 |
| startLine / endLine | 任意。取り込み範囲 |


## Codeberg / Forgejo / Gitea / GitHub / GitLab Card（外部リポジトリカード） {#codeberg-forgejo-gitea-github-gitlab-card-外部リポジトリカード}

書き方はこう。

```text
#+begin_export hugo
{{</* codeberg repo="forgejo/forgejo" */>}}
{{</* forgejo server="https://v11.next.forgejo.org" repo="a/mastodon" */>}}
{{</* gitea server="https://git.fsfe.org" repo="FSFE/fsfe-website" */>}}
{{</* github repo="nunocoracao/blowfish" showThumbnail=true */>}}
{{</* gitlab projectID="278964" */>}}
#+end_export
```

実際にレンダリングすると、こう表示される。

{{< codeberg repo="forgejo/forgejo" >}}
{{< forgejo server="https://v11.next.forgejo.org" repo="a/mastodon" >}}
{{< gitea server="https://git.fsfe.org" repo="FSFE/fsfe-website" >}}
{{< github repo="nunocoracao/blowfish" showThumbnail=true >}}
{{< gitlab projectID="278964" >}}

各サービスAPIからスター数・フォーク数等をリアルタイム取得表示する。 `github` のみ `showThumbnail` がある。 `gitlab` は `baseURL` でセルフホスト対応。


## Email（難読化メールリンク） {#email-難読化メールリンク}

書き方はこう。

```text
#+begin_export hugo
{{</* email email="mailto:hello@test.com" text="text" subject="Reply to awesome article" */>}}
#+end_export
```

実際にレンダリングすると、こう表示される。

{{< email email="mailto:hello@test.com" text="text" subject="Reply to awesome article" >}}


## Figure（画像・図表） {#figure-画像-図表}

書き方はこう。

```text
#+begin_export hugo
{{</* figure
    src="abstract.jpg"
    alt="Abstract purple artwork"
    caption="Photo by [Jr Korpa](https://unsplash.com/@jrkorpa)"
*/>}}
#+end_export
```

実際にレンダリングすると、こう表示される。

{{< figure
    src="abstract.jpg"
    alt="Abstract purple artwork"
    caption="Photo by [Jr Korpa](https://unsplash.com/@jrkorpa)"
>}}

標準Markdown画像記法でも自動変換されるので、org中では通常の `[[file:image.jpg]]` リンクをox-hugoが変換する形でも良い。細かい制御（caption/class/nozoom等）が必要な場合だけexportブロックで明示する。

| パラメータ  | 説明                             |
|--------|--------------------------------|
| src         | 必須。ページリソース→assets/→static/の順で探索 |
| alt         | 代替テキスト                     |
| caption     | キャプション(Markdown可)         |
| class       | &lt;img&gt;への追加CSSクラス     |
| figureClass | &lt;figure&gt;への追加CSSクラス（ギャラリー用） |
| href/target | リンク先URL・target              |
| nozoom      | true でズーム機能無効化          |
| default     | true で標準Hugo figure挙動に戻す |


## Gallery（画像ギャラリー） {#gallery-画像ギャラリー}

書き方はこう。

```text
#+begin_export hugo
{{</* gallery */>}}
  <img src="gallery/01.jpg" class="grid-w33" />
  <img src="gallery/02.jpg" class="grid-w50 md:grid-w33 xl:grid-w25" />
{{</* /gallery */>}}
#+end_export
```

実際にレンダリングすると、こう表示される。

{{< gallery >}}
  <img src="gallery/01.jpg" class="grid-w33" />
  <img src="gallery/02.jpg" class="grid-w50 md:grid-w33 xl:grid-w25" />
{{< /gallery >}}

`class` `"grid-wXX"` （10%〜100%、5%刻み。33%/66%も可）でカラム幅を指定する。


## Gist（GitHub Gist埋め込み） {#gist-github-gist埋め込み}

書き方はこう。

```text
#+begin_export hugo
{{</* gist "octocat" "6cad326836d38bd3a7ae" */>}}
{{</* gist "rauchg" "2052694" "README.md" */>}}
#+end_export
```

実際にレンダリングすると、こう表示される。

{{< gist "octocat" "6cad326836d38bd3a7ae" >}}
{{< gist "rauchg" "2052694" "README.md" >}}

引数は [0] GitHubユーザー名 / [1] Gist ID / [2] 任意、Gist内の特定ファイル名。


## Hugging Face Card {#hugging-face-card}

書き方はこう。

```text
#+begin_export hugo
{{</* huggingface model="google-bert/bert-base-uncased" */>}}
{{</* huggingface dataset="stanfordnlp/imdb" */>}}
#+end_export
```

実際にレンダリングすると、こう表示される。

{{< huggingface model="google-bert/bert-base-uncased" >}}
{{< huggingface dataset="stanfordnlp/imdb" >}}

`model` か `dataset` のどちらか一方を指定する。


## Icon（SVGアイコン） {#icon-svgアイコン}

書き方はこう。

```text
#+begin_export hugo
{{</* icon "github" */>}}
#+end_export
```

実際にレンダリングすると、こう表示される。

{{< icon "github" >}}

独自アイコンは `assets/icons/` にSVG配置し、拡張子なしファイル名で参照できる。


## KaTeX（数式） {#katex-数式}

書き方はこう。

```text
#+begin_export hugo
{{</* katex */>}}
\(f(a,b,c) = (a^2+b^2+c^2)^3\)
#+end_export
```

実際にレンダリングすると、こう表示される。

{{< katex >}}
\(f(a,b,c) = (a^2+b^2+c^2)^3\)

記事内に1回だけ配置すればページ内の数式が自動レンダリングされる。org自体のLaTeX記法（=\\( \\)=）と併用する場合はexportブロック内でエスケープが崩れないか要確認。


## Keyword / KeywordList（キーワード強調） {#keyword-keywordlist-キーワード強調}

書き方はこう。

```text
#+begin_export hugo
{{</* keyword */>}} *Super* skill {{</* /keyword */>}}

{{</* keywordList */>}}
{{</* keyword icon="github" */>}} Lorem ipsum dolor. {{</* /keyword */>}}
{{</* keyword icon="code" */>}} **Important** skill {{</* /keyword */>}}
{{</* /keywordList */>}}
#+end_export
```

実際にレンダリングすると、こう表示される。 `*Super*` （斜体1個）と `**Important**` （太字2個）が使い分けられている点に注目。

{{< keyword >}} *Super* skill {{< /keyword >}}

{{< keywordList >}}
{{< keyword icon="github" >}} Lorem ipsum dolor. {{< /keyword >}}
{{< keyword icon="code" >}} **Important** skill {{< /keyword >}}
{{< /keywordList >}}


## Lead（リード文強調） {#lead-リード文強調}

書き方はこう。

```text
#+begin_export hugo
{{</* lead */>}}
When life gives you lemons, make lemonade.
{{</* /lead */>}}
#+end_export
```

実際にレンダリングすると、こう表示される。

{{< lead >}}
When life gives you lemons, make lemonade.
{{< /lead >}}


## List（記事一覧表示） {#list-記事一覧表示}

書き方はこう。

```text
#+begin_export hugo
{{</* list limit=2 */>}}
{{</* list title="Samples" cardView=true limit=6 where="Type" value="sample" */>}}
#+end_export
```

実際にレンダリングすると、こう表示される。

{{< list limit=2 >}}
{{< list title="Samples" cardView=true limit=6 where="Type" value="sample" >}}

| パラメータ  | 説明                            |
|--------|-------------------------------|
| limit       | 必須。表示件数                  |
| title       | 任意。デフォルト Recent         |
| cardView    | 任意。カード表示                |
| where/value | 任意。記事フィルタ条件（Hugoの where クエリに準拠） |


## LTR/RTL {#ltr-rtl}

書き方はこう。

```text
#+begin_export hugo
- This is a markdown list.
{{%/* rtl */%}}
- هذه القائمة باللغة العربية
{{%/* /rtl */%}}
#+end_export
```

実際にレンダリングすると、こう表示される。

- This is a markdown list.
{{% rtl %}}
- هذه القائمة باللغة العربية
{{% /rtl %}}


## Markdown Importer（外部Markdown取り込み） {#markdown-importer-外部markdown取り込み}

書き方はこう。こちらも `url` は記法説明用のプレースホルダーなので、実在するraw URLに置き換えるまでは実レンダリングしない。

```text
#+begin_export hugo
{{</* mdimporter url="https://raw.githubusercontent.com/.../README.md" */>}}
#+end_export
```


## Mermaid（図表・ダイアグラム） {#mermaid-図表-ダイアグラム}

書き方はこう。

```text
#+begin_export hugo
{{</* mermaid */>}}
graph LR;
A[Lemons]-->B[Lemonade];
B-->C[Profit]
{{</* /mermaid */>}}
#+end_export
```

実際にレンダリングすると、こう表示される。

{{< mermaid >}}
graph LR;
A[Lemons]-->B[Lemonade];
B-->C[Profit]
{{< /mermaid >}}

org標準の `#+begin_src mermaid` ブロックとは別物である点に注意（Hugo側でレンダリングさせたい場合はexport hugoブロックを使う）。


## Swatches（カラーパレット表示） {#swatches-カラーパレット表示}

書き方はこう。

```text
#+begin_export hugo
{{</* swatches "#64748b" "#3b82f6" "#06b6d4" */>}}
#+end_export
```

実際にレンダリングすると、こう表示される。

{{< swatches "#64748b" "#3b82f6" "#06b6d4" >}}


## Tabs（タブ切り替え） {#tabs-タブ切り替え}

書き方はこう。

````text
#+begin_export hugo
{{</* tabs group="lang" default="Python" */>}}
    {{</* tab label="JavaScript" icon="code" */>}}
    ```javascript
    console.log("Hello");
    ```
    {{</* /tab */>}}
    {{</* tab label="Python" icon="sun" */>}}
    ```python
    print("Hello")
    ```
    {{</* /tab */>}}
{{</* /tabs */>}}
#+end_export
````

実際にレンダリングすると、こう表示される。

{{< tabs group="lang" default="Python" >}}
    {{< tab label="JavaScript" icon="code" >}}
    ```javascript
    console.log("Hello");
    ```
    {{< /tab >}}
    {{< tab label="Python" icon="sun" >}}
    ```python
    print("Hello")
    ```
    {{< /tab >}}
{{< /tabs >}}

| パラメータ | 説明                            |
|-------|-------------------------------|
| group   | 任意。同一グループ名のタブは連動切替 |
| default | 任意。デフォルトアクティブタブのラベル |
| label   | 必須（tab側）。タブラベル       |
| icon    | 任意（tab側）。ラベル前アイコン |
| md      | 任意（tab側）。false でネストしたショートコード使用可 |


## Timeline（タイムライン） {#timeline-タイムライン}

書き方はこう。

````text
#+begin_export hugo
{{</* timeline */>}}
{{</* timelineItem icon="github" header="header" badge="badge test" subheader="subheader" */>}}
本文
{{</* /timelineItem */>}}
{{</* /timeline */>}}
#+end_export
````

実際にレンダリングすると、こう表示される。

{{< timeline >}}
{{< timelineItem icon="github" header="header" badge="badge test" subheader="subheader" >}}
本文
{{< /timelineItem >}}
{{< /timeline >}}

| パラメータ(timelineItem) | 説明                 |
|---------------------|--------------------|
| md                  | Markdownとしてレンダリングするか |
| icon                | タイムラインビジュアルに使うアイコン |
| header              | 見出し               |
| badge               | 右上バッジテキスト   |
| subheader           | サブ見出し           |


## TypeIt（タイプライター演出） {#typeit-タイプライター演出}

書き方はこう。

````text
#+begin_export hugo
{{</* typeit
  tag=h3
  speed=50
  breakLines=false
  loop=true
*/>}}
"Frankly, my dear, I don't give a damn."
{{</* /typeit */>}}
#+end_export
````

実際にレンダリングすると、こう表示される。

{{< typeit
  tag=h3
  speed=50
  breakLines=false
  loop=true
>}}
"Frankly, my dear, I don't give a damn."
{{< /typeit >}}

| パラメータ       | 説明                      |
|-------------|-------------------------|
| tag              | 描画するHTMLタグ          |
| classList        | CSSクラスリスト           |
| initialString    | 初期表示文字列            |
| speed            | タイピング速度(ms)        |
| lifeLike         | 人間らしい不規則タイピング |
| startDelay       | 開始までの遅延            |
| breakLines       | 複数文字列を改行表示するか |
| waitUntilVisible | ビューポート内表示時に開始（デフォルト true） |
| loop             | ループ再生                |


## Video（動画埋め込み） {#video-動画埋め込み}

書き方はこう。=caption= の中の `**説明文**` もMarkdown記法（太字）である点に注意。

````text
#+begin_export hugo
{{</* video
    src="https://example.com/video.webm"
    poster="https://example.com/poster.jpg"
    caption="**説明文**"
    loop=true
    muted=true
*/>}}
#+end_export
````

実際にレンダリングすると、こう表示される。

{{< video
    src="https://example.com/video.webm"
    poster="https://example.com/poster.jpg"
    caption="**説明文**"
    loop=true
    muted=true
>}}

| パラメータ                               | 説明               |
|-------------------------------------|------------------|
| src                                      | 必須。ローカル/URL |
| poster                                   | 任意。サムネイル画像 |
| caption                                  | 任意。Markdownキャプション |
| autoplay/loop/muted/controls/playsinline | 各種再生制御（真偽値） |
| preload                                  | metadata/none/auto |
| start/end                                | 再生開始・終了秒数 |
| ratio                                    | アスペクト比（16/9等） |
| fit                                      | contain/cover/fill |


## Youtube Lite（YouTube軽量埋め込み） {#youtube-lite-youtube軽量埋め込み}

書き方はこう。

````text
#+begin_export hugo
{{</* youtubeLite id="SgXhGb-7QbU" label="Blowfish-tools demo" params="start=130&end=10&controls=0" */>}}
#+end_export
````

実際にレンダリングすると、こう表示される。

{{< youtubeLite id="SgXhGb-7QbU" label="Blowfish-tools demo" params="start=130&end=10&controls=0" >}}

| パラメータ | 説明                                        |
|-------|-------------------------------------------|
| id     | 必須。YouTube動画ID                         |
| label  | 任意。ラベル                                |
| params | 任意。YouTube Player Parameters（&amp;区切りで複数指定） |


## 補足（org運用時の注意点） {#補足-org運用時の注意点}

`#+begin_export hugo ... #+end_export` の中身は ox-hugo によって **無変換のまま素通し** される。org内の `*bold*` や `/italic/` のようなorg記法は効かないので、ショートコード内で強調したい場合はMarkdownの `**bold**` / `*italic*` をそのまま書く（この記事もその方針で統一している）。

`all-posts.org` のようにファイル内に複数記事が `* 見出し` で区切られている場合、ox-hugoの `#+hugo_base_dir` や各見出しの `:EXPORT_FILE_NAME:` プロパティ設定が別途必要になる。

既存記事に貼り付ける際は、export blockの直前直後に空行を入れないとorg側のパース崩れが起きるケースがあるので注意する。

Admonitionだけはショートコードではなく `render-blockquote.html` によるMarkdown render hook実装である。

「構文そのものを文字として見せたい」場合は、=#+begin_export hugo= をそのまま書くのではなく `#+begin_example` （または `#+begin_src org` ）で一段リテラル化してから、その直後に本物の `#+begin_export hugo` ブロックを続けて実際のレンダリング結果も見せる、という2段構成にしておくと分かりやすい。

ただし `#+begin_example` で囲むだけでは足りない。Hugoのショートコード展開はMarkdownのコードフェンスの中かどうかを見ずに、ファイル全体から波括弧2つのショートコード記法を探して実行してしまうため、例文として書いたつもりの `pageRef` や外部URL指定がそのまま実行されて `REF_NOT_FOUND` やfetch失敗の原因になることがある。=#+begin_example= の中に書くショートコード例は、開き括弧の直後と閉じ括弧の直前に「/\* 」「 \*/」を挟むエスケープ記法（Hugo公式）で書いておく必要がある。
