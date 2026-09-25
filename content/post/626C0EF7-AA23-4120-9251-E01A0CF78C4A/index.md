+++
title = ".emacs.d を Literate Configuration で管理する"
author = ["YAMASHITA Takao"]
date = 2026-03-20T19:19:00+09:00
lastmod = 2026-09-25T16:30:45+09:00
tags = ["Emacs", "Org-Mode", "Literate-Programming", "Ox-Hugo", "Claude-APIs"]
categories = ["Tech"]
draft = false
+++

`README.org` を久しぶりに大きく更新したので、設計の話も含めて記録として書き残しておく。


## そもそもなぜこんな構成にしたのか {#そもそもなぜこんな構成にしたのか}

Emacs の設定は、放っておくと本当にカオスになってしまう。 `init.el` に `setq` がだらだらと並んで、どれが何のためにあるのか誰にもわからなくなる（かくいう自分も含めて）。

そこで数年前に、思い切って全部作り直した。コンセプトはシンプルで、

-   設定をきちんとエンジニアリングの成果物として扱うこと
-   どのモジュールを消しても他が壊れないこと
-   どの環境で起動しても同じ結果になること

この3つを最初から保証できる構成にしている。


## Literate Configuration {#literate-configuration}

`README.org` が唯一の真実の源泉になっている。Emacs Lisp のコードはすべて `README.org` 内の `src` ブロックに書いておき、 `org-babel-tangle` で `lisp/<layer>/<module>.el` に書き出す仕組みだ。

保存時に自動でタングルされるようにしてあるので、実際の作業フローはほぼ「 `README.org` を編集して保存するだけ」になっている。

ドキュメントとコードが同じファイルにあるので、「コードはあるけど意図がわからない」という状況が生まれない。これがいちばんの利点だと思っている。


## 階層アーキテクチャ {#階層アーキテクチャ}

設定は10層に分かれていて、依存関係は必ず下から上への一方向のみ。

```text
early-init → core → ui → auth → completion → orgx → vcs → dev → utils → personal
```

`core` が UI に依存してはいけないし、 `vcs` が `dev` に依存してもいけない。この制約を守ることで、モジュールを消したり差し替えたりしても他が壊れないようにしている。

起動時のオーケストレーションは `modules.el` が担っていて、モジュールごとにエラートラップをかけながらロードしていく。 `my:modules-verbose` を有効にすると、モジュールごとの起動時間も表示されるので、何が遅いのかも一目でわかる。


## 最近の更新（2026-03） {#最近の更新-2026-03}

今月は、わりと大きめの追加が4つあった。


### Claude API クライアントを `utils` 層に追加（Fix AL） {#claude-api-クライアントを-utils-層に追加-fix-al}

`utils/utils-claude.el` として、低レベルの HTTP クライアントを作った。公開しているAPIは3つの関数だけ。

| 関数                        | 役割                       |
|---------------------------|--------------------------|
| `utils-claude-get-api-key`  | `auth-source` から API キーを取得 |
| `utils-claude-request-sync` | 同期 POST                  |
| `utils-claude-request`      | 非同期バリアント（コールバック） |

`utils` 層に置いたのは、UI にも Org にも依存しない純粋なトランスポート層だから。built-in の `url` ・ `json` ・ `auth-source` しか使っていないので、どの上位層からでも `require` できる。

`dev` 層にある `aidermacs` や `gptel` とはあくまで別物という整理で、あちらは「開発ツール」、こちらは「HTTP 配管」という位置づけにしている。

エラーは `utils-claude-error` という専用シンボルで定義していて、HTTP 非200・JSON パース失敗・API キー未設定という3パターンを `condition-case` でキャッチできるようにしてある。


### Org Babel から Claude を呼ぶ（Fix AM） {#org-babel-から-claude-を呼ぶ-fix-am}

`utils-claude` の上に、個人ワークフロー用のモジュールを `personal` 層に追加した。

いちばん面白いのは、Org Babel の言語として登録したところで、

```org
#+begin_src claude :system "You are a code reviewer."
このコードのリファクタリング案を教えてください。
...
#+end_src
```

これを `C-c C-c` で評価すると、そのままアシスタントの応答が結果として入る。 `:system` ・ `:model` ・ `:tokens` といったヘッダ引数もサポートしている。

インタラクティブなコマンドも3つ追加した。

| コマンド                          | 動作                             |
|-------------------------------|--------------------------------|
| `my/claude-refactor-defun`        | カーソル位置の `defun` をリファクタリング依頼 |
| `my/claude-complete-docstring`    | `defun` の docstring を生成      |
| `my/claude-analyze-require-graph` | バッファの `require` グラフを分析して上向き依存を検出 |

`personal` 層に置いたのは、これが完全に個人的なワークフローの選択だから。共有モジュールのロード順に影響を与えてはいけない、という原則も理由のひとつになっている。


### ブログ記事キャプチャテンプレート（Fix AN） {#ブログ記事キャプチャテンプレート-fix-an}

`C-c c b` で新しい記事のスケルトンを作れるようにした。

ox-hugo のサブツリーエクスポートは `* blog` 直下にエントリがないと動かないので、テンプレートのターゲットは `(file+olp my:f:capture-blog-file "blog")` にしてある。

プロパティドロワーは自動で埋まるようになっている。

| プロパティ               | 値                     |
|---------------------|-----------------------|
| `EXPORT_FILE_NAME`       | UUID（=org-id-new=）   |
| `EXPORT_DATE`            | 現在時刻               |
| `EXPORT_HUGO_TAGS`       | インタラクティブ入力   |
| `EXPORT_HUGO_CATEGORIES` | インタラクティブ入力   |
| `EXPORT_HUGO_LASTMOD`    | 空（ox-hugo がエクスポート時に補完） |

デフォルトの `blog.org` は実際には存在しないので、 `personal/ac1965.el` で `my:f:capture-blog-file` を `all-posts.org` にオーバーライドしている。これをやっておかないと、キャプチャ時に `org-find-olp: Heading not found` というエラーが出てしまう。


### 保存時に自動で ox-hugo エクスポート（Fix AO） {#保存時に自動で-ox-hugo-エクスポート-fix-ao}

`orgx/orgx-auto-hugo.el` を追加して、 `all-posts.org` を保存したら `org-hugo-export-wim-to-md :all-subtrees` が自動で走るようにした。

`orgx-auto-tangle.el` と同じパターンで実装している。

-   **適格性述語** `orgx-auto-hugo--eligible-p` ： `file-truename` でシンボリックリンクも解決する
-   **ガードフラグ** `defvar-local orgx-auto-hugo--in-progress` ：ox-hugo が内部でバッファ保存を再トリガーして無限ループになるのを防ぐ
-   **ワーカー** `orgx-auto-hugo--maybe` ： `condition-case` 内で実行する
-   **フック登録** `orgx-auto-hugo--install-hook` ： `org-mode-hook` からバッファローカルに `after-save-hook` を設置する

これで「 `C-c c b` でスケルトン作成 → 書く → 保存」だけで Hugo へのエクスポートまで完結するようになった。この記事自体も、そのフローで書いている。

{{< alert >}}
訂正点：
orgx/orgx-auto-hugo.el を追加して、all-posts.org への org-capture が確定したら org-hugo-export-wim-to-md :all-subtrees が自動で走るようにした。
orgx-auto-tangle.el と同じパターンを基礎としているが、トリガーは after-save-hook ではなく org-capture-after-finalize-hook に登録している。保存のたびに走ると、未完成のエントリが部分的にエクスポートされてしまうためだ。
{{< /alert >}}

{{< alert >}}
実装の要素：
orgx-auto-hugo--blog-capture-p: org-capture-last-stored-marker が指すバッファのファイル名を file-truename で解決し、my:f:capture-blog-file と一致するか確認する。シンボリックリンクも正しく処理され、無関係なキャプチャ（Todo・Note・Journal など）では発火しない。
ガードフラグ defvar orgx-auto-hugo--in-progress: ox-hugo が内部でバッファ保存を再トリガーして無限ループになるのを防ぐ。
ワーカー orgx-auto-hugo--on-capture-finalize: org-capture-after-finalize-hook に登録。中断（C-c C-k）時は org-note-abort を見てスキップし、確定（C-c C-c）時のみ condition-case 内でエクスポートを実行する。

org-capture でブログ用テンプレート（キー b）を選択してスケルトン作成 → 書く → C-c C-c で確定するだけで Hugo へのエクスポートまで完結するようになった。この記事もそのフローで書いている。
「C-c c b でスケルトン作成」→「org-capture でテンプレート b を選択してスケルトン作成」。C-c c というキーシーケンスは設定されておらず、org-capture は ui-leader-o-map 経由で起動する。
{{< /alert >}}


## まとめ {#まとめ}

今月の更新で、Emacs の中で Claude を使う基盤（ `utils-claude` ）、それを使った個人ワークフロー（ `personal-ai` ）、そしてブログ執筆をゼロフリクションにするフロー（キャプチャ＋自動エクスポート）がひととおり揃った。

Literate Configuration ＋ 階層アーキテクチャは、最初に組み上げるコストは高いけれど、長く使い続けるならやってよかったと思っている。「Emacs の設定が育てにくい」と感じている人の参考になれば嬉しい。
