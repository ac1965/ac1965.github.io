# No Good Father

> [Hugo](https://gohugo.io/) + [Blowfish](https://blowfish.page/) テーマで構築された個人ブログ
> Emacs の [Org-mode](https://orgmode.org/) と [ox-hugo](https://ox-hugo.scripter.co/) により記事を作成


## 目次

- [Requirements](#requirements)
- [Installation](#installation)
- [Writing Workflow](#writing-workflow)
- [Local Development](#local-development)
- [Submodule 管理](#submodule-管理)
- [Configuration](#configuration)
- [Deploy](#deploy)


## Requirements

| ツール | バージョン | 備考 |
|--|||
| [Hugo](https://gohugo.io/installation/) | ≥ 0.141.0 extended | `brew install hugo` |
| [Git](https://git-scm.com/) | 任意 | submodule 管理用 |
| [Emacs](https://www.gnu.org/software/emacs/) | ≥ 29 | 記事執筆用 |
| [ox-hugo](https://ox-hugo.scripter.co/) | 最新 | Org → Hugo Markdown |
| [mmdc](https://github.com/mermaid-js/mermaid-cli) | 任意 | Mermaid 図の生成 |


## Installation

### 1. Hugo サイトの作成

```bash
hugo new site mysite
cd mysite
git init
````

### 2. Blowfish テーマを submodule として追加

```bash
git submodule add -b main https://github.com/nunocoracao/blowfish.git themes/blowfish
```

### 3. テーマ設定ファイルのコピー

```bash
cp themes/blowfish/config/_default/* config/_default/
```

### 4. Emacs パッケージのインストール

`straight.el` を利用（`orgx/orgx-export.el` で設定済み）

```
M-x straight-pull-all
```

ox-hugo がロードされていることを確認

```
M-: (featurep 'ox-hugo)  ; => t
```


## Writing Workflow

すべての記事は **Org-mode** で作成し、ox-hugo により Markdown へ変換されます。

### ディレクトリ構成

```
content-org/
├── about.org
└── posts/
    └── my-post.org       ← ここに執筆

content/                  ← ox-hugo により生成（手動編集しない）
├── about/
│   └── index.md
└── post/
    └── my-post/
        └── index.md
```

### Org ファイル Front Matter 例

```org
#+TITLE: My Post Title
#+DATE: <2026-03-15>
#+HUGO_BASE_DIR: <HUGO_BASE_DIR>
#+HUGO_SECTION: post
#+HUGO_TAGS: hugo emacs
#+HUGO_CATEGORIES: tech
```

### Export コマンド

| 操作           | キーバインド        | 説明                  |
|  | - | - |
| 新規投稿作成       | `C-c c b`     | org-capture で投稿作成   |
| サブツリー export | `C-c C-e H H` | 現在 subtree を export |
| 全体 export    | `C-c C-e H A` | Org ファイル全体 export   |


## Local Development

### 開発サーバ起動（draft 含む）

```bash
hugo server --buildDrafts --disableFastRender
```

Open: [http://localhost:1313](http://localhost:1313)

### Blowfish テーマ更新

```bash
git submodule update --remote --merge themes/blowfish
git add themes/blowfish
git commit -m "chore: update blowfish theme"
```

### よく使う Hugo コマンド

```bash
# 本番ビルド
hugo

# リンクチェック
hugo --gc --minify

# バージョン確認
hugo version
```


## Submodule 管理

Blowfish テーマは Git submodule として管理されています。
リポジトリを clone した直後や、テーマ更新時は以下を実行します。

### 初回 clone 時（submodule を含める）

```bash
git clone --recursive https://github.com/<your-repo>.git
cd <your-repo>
```

すでに clone 済みの場合：

```bash
git submodule update --init --recursive
```

### Submodule を最新に更新

Blowfish テーマを upstream の最新に更新する場合：

```bash
git submodule update --remote --merge themes/blowfish
```

更新後は必ずコミットします：

```bash
git add themes/blowfish
git commit -m "chore: update blowfish theme"
```

### すべての submodule を更新

```bash
git submodule update --remote --recursive
```

### Submodule 状態確認

```bash
git submodule status
```

### Submodule を強制的に同期

リモートURL変更などがあった場合：

```bash
git submodule sync --recursive
git submodule update --init --recursive
```

### よくあるトラブル対処

submodule が壊れた場合：

```bash
git submodule deinit -f themes/blowfish
rm -rf .git/modules/themes/blowfish
git submodule update --init --recursive
```


## Configuration

設定ファイルは `config/_default/` に配置

| ファイル                | 用途                          |
| - |  |
| `hugo.toml`         | サイト全体設定                     |
| `params.toml`       | Blowfish テーマ設定              |
| `languages.en.toml` | 言語・著者情報                     |
| `menus.en.toml`     | ナビゲーション                     |
| `markup.toml`       | Markdown / syntax highlight |
| `module.toml`       | Hugo module                 |


## Deploy

### GitHub Actions

```yaml
# .github/workflows/deploy.yml
- uses: actions/checkout@v4
  with:
    submodules: true
    fetch-depth: 0

- name: Setup Hugo
  uses: peaceiris/actions-hugo@v3
  with:
    hugo-version: '0.157.0'
    extended: true

- name: Build
  run: hugo --minify
```

### 手動ビルド

```bash
hugo --minify
# 出力先: ./public/
```


## License

Content © YAMASHITA, Takao. All rights reserved.
Theme: [Blowfish](https://github.com/nunocoracao/blowfish) — MIT License.
