+++
title = "EmacsでLLM"
author = ["YAMASHITA Takao"]
date = 2024-11-10T22:33:00+09:00
lastmod = 2026-09-13T13:38:58+09:00
tags = ["Emacs", "Ollama", "Ellama", "LLM"]
categories = ["Tech"]
draft = false
pin = false
+++

昨日、久しぶりに本屋に立ち寄って立ち読みしていたら、MacのOllamaでLLMをローカルで動かして遊ぶという記事を見かけた。普段はあまり技術書コーナーで長居しないんだけど、最近あちこちで「LLMがローカルで動く」という話を耳にしていたので、つい足が止まった。

思わず食指が動いて、さっそくバイナリを落として動かしてみた。手元のマシンでもそれなりにサクサク動いて、これはなかなか遊べそうだったので、年末年始にじっくり勉強することにした。

[Ollamaで利用可能なモデル](https://ollama.com/library)も豊富で、コミュニティが精力的にアップし続けてくれてるみたいだった。これだけ盛り上がっているなら、Emacsで動くパッケージもきっとあるだろうと思って、最近お気に入りの[Perplexity](https://www.perplexity.ai)で調べてみた。[Google](https://www.google.com)でもよかったんだけど、Perplexityのほうがサッと調べてくれるので、最近はこっちに頼りがちだ。

以下、Perplexityの回答をそのまま引用する。

{{<details "LLMの目的、目標と課題">}}
大規模言語モデル（LLM）は、ざっくり言うと「膨大なデータと計算力を使って訓練された、言葉を扱うのが得意なAI」だ。文章を書いたり、質問に答えたり、翻訳したり、要約したり、チャットボットとして会話したりと、言語まわりのタスクなら一通りこなせる。有名どころだとOpenAIのGPTシリーズやMetaのLlamaシリーズがあって、パラメータ数は数十億〜数千億というとんでもない規模のネットワークを積んでいる。

### 何のために作られているのか

LLMがやりたいことは、要するに言語処理の精度と柔軟性を上げること。具体的には次のあたりが軸になる。

1. **自然な会話**: 人間っぽいやり取りができるので、カスタマーサポートや情報提供の窓口として使われる。チャットボットや音声アシスタントの「自然な受け答え」は、だいたいLLMのおかげだ。

2. **情報検索・要約**: 論文やニュースをサクッと要約してくれるので、必要な情報にすぐたどり着ける。長い文書の整理にも重宝する。

3. **翻訳・言語変換**: リアルタイム翻訳や言語変換もこなせるので、言葉の壁を越えたコミュニケーションを支えてくれる。

### 何がうれしいのか

パラメータが多いぶん、こんな効果が期待できる。

1. **応答の精度**: 大量のデータで訓練されているので、自然で的確な返事が返ってくる。使っていて気持ちいい。

2. **適応力**: 一度訓練したモデルでも、ファインチューニングすれば新しいタスクやテーマにすぐ対応できる。

3. **スケーラビリティ**: クラウドでもローカルでも動くので、個人から企業まで規模を問わず使える。医療・教育・金融など、応用範囲も広い。

### 目標と課題

もちろん良いことばかりではなく、いくつか気になる課題もある。

- **倫理面**: 偏ったデータで訓練すると、モデルの回答も偏ってしまうリスクがある。公平さや倫理的な使い方が求められる。
- **計算資源**: とにかく大量のデータと計算パワーを食うので、環境負荷やコストが無視できない。
- **プライバシー**: 特にセンシティブな情報を扱う分野では、データの管理とセキュリティがそのまま信頼に直結する。

これから先は、もっと軽くて効率的なモデルの開発や、倫理・社会的責任をきちんと果たすためのガイドライン整備が課題になっていきそうだ。
{{</details>}}

{{<details "Ollamaって？">}}
Ollamaは、ローカル環境で大規模言語モデル（LLM）を動かして管理するためのソフトだ。自分のPCで直接AIモデルを動かせるので、クラウドに頼らずに済むし、プライバシーやデータの扱いも自分でコントロールできる。LlamaやCode Llamaといった人気モデルに対応していて、文章生成からコーディング支援まで幅広くこなせる。

「Modelfile」という設定ファイルを使えば、温度設定やサンプリング手法といったパラメータを細かくいじれるので、目的に合わせたカスタマイズも自由自在。LangChainとの連携もできるので、チャットボットや対話型AIを組みたいときにも便利そうだ。

ローカルで完結するぶん、データが外に漏れる心配が少なく、ネットがなくても使えるのがうれしいところ。ただし大きいモデルを動かすにはそこそこのGPUとストレージが要るので、セットアップにはちょっとした技術力とリソースが必要になる。
{{</details>}}

{{<details "Ollamaで扱うAIモデルの構造">}}
Ollamaで扱われるモデルの中身は、基本的に大規模言語モデル（LLM）そのものだ。多層のニューラルネットワークで構成されていて、特に「トランスフォーマー」というアーキテクチャを採用しているのがポイント。2017年にGoogleが発表したこの仕組みは、テキストを並列処理できるので処理効率が高く、LLMの土台としてすっかり定番になっている。

### トランスフォーマーの中身をざっくり

トランスフォーマーは、本来エンコーダーとデコーダーの2パートで構成されるけど、GPTやLlamaのような大規模言語モデルでは、どちらか片方だけを使うことが多い。各層には「自己注意機構（Self-Attention）」という仕組みがあって、単語同士の関係性を見ながら文脈を保ったまま処理を進めていく。

- **自己注意機構**: 文章中の各単語が、他の単語とどう関係しているかを見ながら処理する仕組み。これのおかげで、長い文脈でも前後のつながりを保ったまま学習できて、長文生成や複雑な文章構造の理解が得意になる。

- **マルチヘッド注意**: 1つの層の中に複数の「ヘッド」があって、それぞれ違う視点でデータを見る。おかげで多角的に意味を捉えられて、単語の曖昧さも解消しやすくなる。

### Ollamaでのモデル管理

Ollamaでは「Modelfile」を作ることで、モデルのサイズや特性に合わせて自由に設定を変えられる。応答の多様性を左右する「温度」パラメータを調整したり、ハードウェアアクセラレーションを有効にしてパフォーマンスを上げたりもできる。こういうカスタマイズ性のおかげで、幅広い用途に対応できるわけだ。

### GPTとLlama、それぞれの特徴

Ollamaでよく使われるLlamaやGPTには、こんな特徴がある。

- **パラメータの多さ**: GPT-4やLlamaは数十億〜数千億パラメータという規模で、膨大な知識を蓄えている。トレーニングデータの量とあいまって、幅広いタスクに対応できる。
- **データと学習**: Webテキストや書籍など多様なデータで学習しているので、文脈理解や推論もこなせる。用途に合わせてファインチューニングもできるので、ビジネスや専門分野に特化させやすい。

こうしたモデル構造をうまく活かしつつ、ローカルで効率的にAIを動かそうというのがOllamaの狙いだ。データのプライバシーを守りつつオフラインでも使えるので、いろんな業界で活用が進んでいる。

**Llama**と**GPT**は、どちらもLLMの代表格で、NLPのさまざまなタスクに使われているAIモデルだけど、設計思想や用途には違いがある。

### Llama（Large Language Model Meta AI）

LlamaはMeta（旧Facebook）が開発したオープンソースのLLM。効率性とプライバシーを重視した設計で、GPTに比べると軽量で、ローカル環境でも動かしやすいのが特徴だ。

- **設計の特徴**: トランスフォーマーを採用しつつ、計算効率とモデルサイズの削減に力を入れている。Llama 2は数十億〜数千億パラメータのモデルが公開されていて、エッジデバイスやローカル環境でも動く。プライバシーを重視する企業や開発者にとっては、自分のインフラ内でAIを使えるのが大きなメリットになる。
- **用途**: 生成AI、要約、チャットボット、質問応答など幅広く使われていて、研究機関や企業での試験導入も進んでいる。

### GPT（Generative Pre-trained Transformer）

GPT（特にGPT-3やGPT-4）はOpenAIが開発したLLMで、この分野を大きく前進させた立役者。膨大なテキストで事前学習されていて、自然なテキスト生成や対話が得意だ。

- **設計の特徴**: GPT-4では数千億パラメータ以上という巨大な規模で、必要な計算資源も膨大。基本的にはクラウド環境や高性能ハードウェア上で動かす。自己回帰型のテキスト生成が得意で、プロンプトから次の単語を予測しながら文章を組み立てていく。
- **用途**: 対話アシスタント、文章生成、コンテンツ制作、コード補助など、商業・学術問わず幅広く使われている。精度と流暢さが高く、即座に応答してほしい用途に向いている。

### 結局どう違うのか

- **オープンソース性と使う環境**: Llamaはオープンソースで、条件さえ満たせば無料で使える。GPTはOpenAIのAPIやクラウド経由が中心で、基本的に利用料がかかる。
- **パフォーマンスとリソース**: GPTは精度が高い分、計算リソースをかなり食う。Llamaは効率化されているので、一般的なマシンでも扱いやすい。

どちらも高度な自然言語処理を可能にしていて、選ぶ基準は使う環境やコスト、プライバシーをどれだけ重視するか次第、という感じだ。
{{</details>}}

{{<details "Ollamaのインストールとellamaの設定">}}
OllamaをmacOSに入れて、EmacsからEllamaを使えるようにするまでの手順をざっとまとめておく。

#### Ollamaのインストール[fn:Ollama]

1. **Homebrewを使ってインストール**:
   ターミナルを開いて、以下を実行する。
```bash
   brew install ollama
```

2. **動作確認**:
   インストールできたか、バージョンを見て確かめる。
```bash
   ollama --version
```

3. **モデルのダウンロードと実行**:
   例えば `gemma2:9b` を使いたいときは、こう打つ。
```bash
   ollama run gemma2:9b
```

4. **対話の終了**:
```bash
   Ctrl + d または /bye
```

#### EmacsでEllamaの設定

1. **必要なパッケージをインストール**:
   `use-package` でEllamaを設定する。Emacsの設定ファイル（通常は `~/.emacs.d/init.el`）に以下を追加する。
```elisp
   (use-package ellama
     :init
     (setq ellama-keymap-prefix "C-c e")  ;; キーバインディングの設定
     (setq ellama-language "Japanese")      ;; 言語設定
     (require 'llm-ollama)
     (setq ellama-provider (make-llm-ollama
       :host "localhost"                     ;; Ollamaが動作しているホスト名
       :chat-model "gemma2:9b"               ;; 使用するチャットモデル名
       :embedding-model "gemma2:9b")))       ;; 使用する埋め込みモデル名
```

2. **EmacsからEllamaを使う**:
   Emacs内でこんなコマンドが使える。
   - テーブル作成: `M-x ellama-make-table`
   - YAMLフォーマット変換: `M-x ellama-make-format RET yaml RET`
   - 概要作成: `M-x ellama-summarize`
   - 翻訳: `M-x ellama-translate`
{{</details>}}

私は[ leaf ](https://github.com/conao3/leaf.el)を使っているので、それに合わせて書き換えたものを貼っておく。

```emacs-lisp
(leaf ellama
  :after llm-ollama
  :ensure t
  :init
  (setopt ellama-language "Japanese")
  (setopt ellama-sessions-directory (concat no-littering-var-directory "ellama-sessions"))
  (setopt ellama-naming-scheme 'ellama-generate-name-by-llm)
  (setopt ellama-provider
          (make-llm-ollama
           ;; this model should be pulled to use it
           ;; value should be the same as you print in terminal during pull
           :chat-model "llama3:8b-instruct-q8_0"
           :embedding-model "nomic-embed-text"
           :default-chat-non-standard-params '(("num_ctx" . 8192))))
  (setopt ellama-summarization-provider
          (make-llm-ollama
           :chat-model "qwen2.5:3b"
           :embedding-model "nomic-embed-text"
           :default-chat-non-standard-params '(("num_ctx" . 32768))))
  ;; llm providers for interactive switching.
  (setopt ellama-providers
          '(("zephyr" . (make-llm-ollama
                             :chat-model "zephyr:7b-beta-q6_K"
                             :embedding-model "zephyr:7b-beta-q6_K"))
            ("mistral" . (make-llm-ollama
                              :chat-model "mistral:7b-instruct-v0.2-q6_K"
                              :embedding-model "mistral:7b-instruct-v0.2-q6_K"))
            ("mixtral" . (make-llm-ollama
                              :chat-model "mixtral:8x7b-instruct-v0.1-q3_K_M-4k"
                              :embedding-model "mixtral:8x7b-instruct-v0.1-q3_K_M-4k"))
            ("codestral" . (make-llm-ollama
                            :chat-model "codestral:22b-v0.1-q4_K_S"
                            :embedding-model "codestral:22b-v0.1-q4_K_S"))
            ("gemma2" . (make-llm-ollama
                         :chat-model "gemma2:27b-instruct-q4_K_S"
                         :embedding-model "gemma2:27b-instruct-q4_K_S"))
            ("command-r" . (make-llm-ollama
                            :chat-model "command-r:35b"
                            :embedding-model "command-r:35b"))
            ("llama3.1" . (make-llm-ollama
                           :chat-model "llama3.1:8b"
                           :embedding-model "llama3.1:8b"))))
  ;; Naming new sessions with llm
  (setopt ellama-naming-provider
          (make-llm-ollama
           :chat-model "llama3:8b-instruct-q8_0"
           :embedding-model "nomic-embed-text"
           :default-chat-non-standard-params '(("stop" . ("\n")))))
  ;; Translation llm provider
  (setopt ellama-translation-provider
          (make-llm-ollama
           :chat-model "qwen2.5:3b"
           :embedding-model "nomic-embed-text"
           :default-chat-non-standard-params
           '(("num_ctx" . 32768)))))
```


## 設定ファイル（Modelfile）の作成 {#設定ファイル-modelfile-の作成}

> Ollamaでは、カスタムモデルの設定ファイルとして <span class="underline">Modelfile</span> が必要です。以下はその例です。
>
> 1.  **Modelfileの作成**:
>     モデルと同じディレクトリに `Modelfile` という名前のファイルを作成し、以下の内容を記述します。
>
> <!--listend-->
>
> ```shell
> from /ollama/gemma2-9b-chat-gguf
> ```


## Ellamaで遊んだ {#ellamaで遊んだ}

`M-x ellama-chat` で試しに遊んでみたら、思っていたよりずっとちゃんとしていて驚いた🤣

せっかくなので、Emacsの設定ファイルについて聞いてみた。返ってきたコードはあちこち構文が壊れているんだけど、それっぽいコードをそれっぽく組み立ててくる時点で、素直におもしろい。

{{<details "Ellamaとの会話ログ">}}
**User:** emacs29以上で動作する設定ファイル

**Ellama:** Emacs29から上手く動作する設定ファイルを記述します。
```elisp
;;; config.el - Emacs config file

;; Emacsバージョンのチェック
(unless (>= emacs-major-version 29)
  (error "Emacs 29以上をインストールしてください"))

;; 基本設定
(setq default-frame-alist '((top . 0) (left . 0) (width . 1400) (height . 800)))
(setq mouse-wheel-movement 2) ; マウスホイールの回転量
(setq tab-width 2) ; Tabキーのタブ幅
(setq indent-tabs-mode nil) ; タブを空白で置換する
(setq show-paren-mode t) ; 括弧の表示
(setq show-trailing-whitespace t) ; 不要なスペースの表示
(setq enable-pop-up-menu t) ; Pop-up menuの有効化
(setq scroll-step-1 120) ; Scrollバーのスクロール量
(setq column-number-mode t) ; 行数と列数を表示する

;; キーバイング
(global-set-key [C-left] 'previous-line) ; Ctrl + Left Arrow
(global-set-key [C-right] 'next-line') ; Ctrl + Right Arrow
(global-set-key [C-x C-k] 'kill-region') ; Ctrl + X + K
(global-set-key [C-x C-c] 'copy-region') ; Ctrl + X + C
(global-set-key [C-x C-y] 'yank') ; Ctrl + X + Y
(global-set-key [C-x C-w] 'cut-region') ; Ctrl + X + W
(global-set-key [C-c C-f] 'find-file') ; Ctrl + C + F
(global-set-key [C-c C-s] 'save-some-buffers') ; Ctrl + C + S
(global-set-key [C-c C-q] 'write-region') ; Ctrl + C + Q
(global-set-key [C-c C-j] 'next-error') ; Ctrl + C + J
(global-set-key [C-c C-i] 'previous-error') ; Ctrl + C + I
(global-set-key [C-c C-k] 'kill-some-buffers') ; Ctrl + C + K
(global-set-key [M-.] 'undo') ; Option + .
(global-set-key [M-;] 'revert') ; Option + ;
(global-set-key [C-x o] 'other-frame') ; Ctrl + X + O
(global-set-key [C-x 5] 'minibuffer-scroll-down') ; Ctrl + X + 5 (下スクロール)
(global-set-key [C-x 6] 'minibuffer-scroll-up') ; Ctrl + X + 6 (上スクロール)

;; パッケージのインストールと有効化
(package-initialize) ; Emacs Package Manager (EPM)の初期化
(add-to-list 'load-path "/path/to/package/directory") ; パッケージの探索先の追加
(require 'company) ; Company-modeパッケージの有効化
(company-setup) ; Company-modeの設定

;; テーマの選択
(set-face-attribute 'default' nil :background "black") ; 背景の色を白にする場合
(load-theme 'gruvbox-dark' t) ; テーマの有効化

;; ライブラリの有効化
(require 'org) ; Org-modeパッケージの有効化
(setq org-mode '(text . plain) (html . html)) ; Org-modeの出力形式
(add-to-list 'auto-mode-alist '("\\.org" . org-mode)) ;  ".org" で Org-mode を有効化

;; プロジェクトの管理
(require 'projectile) ; Projectileパッケージの有効化
(projectile-global-mode 1) ; Projectile をグローバルに有効化
(setq projectile-find-by-name t) ; Projectile で名前でプロジェクト検索を有効化
```

この設定ファイルでは、Emacs29から上手く動作する設定を記述しています。特に、エディタの基本設定、キーバインド、パッケージのインストールと有効化、テーマの選択、ライブラリの有効化などが含まれています。これを使用すると、開発者や学習者などにとって役立つ設定が提供されます。
{{</details>}}

教科書的な説明を淡々と返してくるだけかと思いきや、ちゃんと動く（つもりの）コードまで組み立ててくるのは、正直ちょっと感動した。エラーが残っている部分はご愛嬌として、年末年始はこのあたりをもう少し触って、実用に耐えるくらいまで設定を詰めていきたい。
