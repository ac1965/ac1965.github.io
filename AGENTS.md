# AGENTS.md

このファイルは、このリポジトリで作業する AI コーディングエージェント向けの
ガイドです。詳細な運用手順は [README.org](README.org) を正とするため、
矛盾があれば README.org を優先してください。

## プロジェクト概要

[Hugo](https://gohugo.io/) + [Blowfish](https://blowfish.page/) テーマで
構築された個人ブログ（ty07.net）。記事は Emacs の Org-mode で執筆し、
[ox-hugo](https://ox-hugo.scripter.co/) により Markdown へ変換して Hugo で
ビルド・公開する。

**移行中の注意(2026-09-21〜)**: 公開方式をローカル手動デプロイ
（`deploy.sh` がビルドから `deploy` ブランチへの push まで一括で行う方式）
から GitHub Actions（`.github/workflows/pages.yml`）によるビルド・公開へ
移行する作業に着手した。本ファイルの記述は新方式を前提に更新済みだが、
まだ本番切り替えは完了していない: `content/post/` の初回コミット・push、
およびリポジトリの Settings > Pages > Source を「GitHub Actions」へ
切り替える作業が残っている。それまでは現行の `deploy` ブランチが
実際の公開経路のまま。

## リポジトリ構成

- `all-posts.org` — 記事の Org ソース。1 ファイルに全記事を subtree として格納
- `content/` — **ox-hugo（Emacs）または `org2hugo.py` により生成される**。
  手動編集しない。2026-09-21 以降 **Git 管理下**（`.gitignore` の除外を解除
  済み）。生成物であることに変わりはないので、`all-posts.org` 側を直さず
  ここを直接編集してコミットしないこと
- `config/_default/` — Hugo / Blowfish の設定ファイル一式（管理方針は下記
  「Config 管理方針」参照）
- `themes/blowfish/` — Blowfish テーマ（Git submodule、`branch = main` を追跡）
- `prepare-content.sh` — `content/post/` 生成後の後処理スクリプト（zsh）。
  画像同期（`sync_post_assets`）とカバー画像の自動配置（`place_covers`）を
  行う。ビルドや git 操作は行わない
- `deploy.sh` — `prepare-content.sh` を呼ぶだけの薄いラッパー。旧版はここで
  Hugo ビルド・`deploy` ブランチへの同期・commit & push まで一括で
  行っていたが、その役割は GitHub Actions（`.github/workflows/pages.yml`）
  へ移した。`content/` の commit・push は自動化せず、意図的に手動のまま
- `.github/workflows/pages.yml` — push (`main`) をトリガーに Hugo でビルドし
  GitHub Pages へデプロイする GitHub Actions ワークフロー。動作させるには
  リポジトリの Pages Source を「GitHub Actions」に切り替える必要がある
  （まだ未実施、上記「移行中の注意」参照）
- `public/` — Hugo のビルド出力（Git 管理対象外）
- `org2hugo.py` / `Makefile` — `all-posts.org` から `content/post/` を
  Python スクリプトで生成するツール。**README.org には記載がなく、正規の
  執筆ワークフロー（下記）とは別系統**。ox-hugo の出力と完全に一致する
  保証はないため、使う場合は `make org2hugo-check`（dry-run）で差分を
  確認してから使うこと

## 執筆ワークフロー(README.org 準拠)

記事は Org-mode（`all-posts.org`）で作成し、Emacs 上で ox-hugo により
`content/` へ変換するのが正規の経路。

- 保存時に `org-hugo-export-wim-to-md` が自動実行される設定であれば手動 export は不要
- 手動 export: サブツリーのみ `C-c C-e H H` / ファイル全体 `C-c C-e H A`
- 新規投稿は org-capture のテンプレート `b` から作成

AI エージェントは通常 Emacs を操作できないため、`content/` の再生成が
必要な場合は上記 `org2hugo.py`（未検証の代替経路である点に注意）を使うか、
既に生成済みの `content/` をユーザーに確認してもらうこと。

`content/` を生成・更新したら、commit する前に必ず `./prepare-content.sh`
（画像同期・カバー配置）を実行すること。

## Config 管理方針(config/_default/)

`config/_default/` は Blowfish テーマの初回セットアップ時に
`themes/blowfish/config/_default/` から**コピーして自サイト用にカスタマイズ
したもの**であり、テーマ更新のたびに上書きされる派生物ではない。
各ファイルの役割は以下の通り。

| ファイル              | 用途                              |
|-----------------------|-----------------------------------|
| `hugo.toml`           | サイト全体設定                    |
| `params.toml`         | Blowfish テーマ設定                |
| `languages.en.toml`   | 言語・著者情報                     |
| `menus.en.toml`       | ナビゲーション                     |
| `markup.toml`         | Markdown / syntax highlight        |

**テーマ(`themes/blowfish`)が更新されても、このディレクトリの「方向性」
（サイト固有のカスタマイズ）を失わないための鉄則:**

1. **`themes/blowfish/config/_default/*` を `config/_default/` へ丸ごと
   上書きコピーしてはいけない。** ローカルのカスタマイズが失われる。
   丸ごとコピーが許されるのは初回セットアップ時のみ。
2. テーマ更新後は必ず両者を diff し、増えたキー・変更されたデフォルト値
   だけを手動でマージする。

   ```bash
   diff -ru config/_default/ themes/blowfish/config/_default/
   ```
3. Hugo の min/max バージョン要件は `config/_default/module.toml` ではなく
   `themes/blowfish/config.toml` の `[module.hugoVersion]` で管理されている
   （旧 `config/_default/module.toml` は v3 以降空ファイルで未使用）。
   テーマ更新時は必ずここを確認し、ローカルの Hugo バージョンと CI
   （`.github/workflows/pages.yml` の `HUGO_VERSION`）の両方を範囲内に
   追随させる。
4. 新しい Blowfish の機能（追加ショートコード・新規 params 項目など）を
   使いたい場合は、`themes/blowfish/exampleSite/` 配下のサンプル設定を
   参照して該当キーを `params.toml` 等に追記する。

つまり「テーマの設定が正、自サイトの設定はその都度追随させる」のではなく、
**「自サイトの `config/_default/` が正、テーマ更新時は差分だけを選んで
取り込む」**という向きで運用する。エージェントがテーマ更新やトラブル対応で
`config/_default/` を触る際は、この向きを逆転させないこと（詳細は
README.org の「Submodule 管理」参照）。

## よく使うコマンド

```bash
hugo server --buildDrafts --disableFastRender   # ローカル開発サーバ (http://localhost:1313)
hugo --minify                                    # ローカルでのビルド確認(出力先 ./public/、Git対象外)
./deploy.sh                                      # 実体は ./prepare-content.sh(画像同期・カバー配置のみ)
git add content && git commit -m "..." && git push  # 手動。push後にGitHub Actionsが起動
```

`deploy.sh`（= `prepare-content.sh`）は `content/post` が既に生成済みで
あることを前提とするため、実行前に `all-posts.org` の変更が `content/` に
反映済みか確認すること(反映方法は上記「執筆ワークフロー」参照)。
`--dry-run` オプションは廃止した(ビルド・pushをスクリプト側で行わなくなり、
スキップする対象が無くなったため)。

Hugo ビルドと GitHub Pages への公開は、`content/` を含む push をトリガーに
GitHub Actions が行う(Pages の Source を「GitHub Actions」に切り替え済みの
場合に限る。上記「移行中の注意」参照)。`Makefile` の `make deploy` 等は
README.org 非記載の別経路であり、正規手順ではない点に注意。

## 変更時の注意事項

- **`content/` を直接編集しない**。編集元は必ず `all-posts.org` 側で行う。
  `content/` はビルド成果物であり再生成される。
- **`resources/_gen/` と `public/` を Git 管理下に置かない**。`.gitignore`
  で除外済みだが、誤ってコミットしないよう注意。
- 記事本体は2026-07-30の移行以降 `content/post/<slug>/index.md` という
  **真のPage Bundle**として出力される（それ以前の「flat file」という記述は
  古い情報なので参照しないこと）。カバー画像は `prepare-content.sh` が
  front matter の日付等を基に機械的に配置している（詳細は README.org の
  Writing Workflow / Deploy 参照）。
- 画像ファイルは拡張子と実データ形式を一致させること。不一致があると
  Hugo の `.Resize` 処理がビルド全体を失敗させる。
- Blowfish テーマ更新時は `themes/blowfish/config.toml` の
  `[module.hugoVersion]`（min/max）を確認し、ローカルの Hugo バージョンと
  CI（`.github/workflows/pages.yml` の `HUGO_VERSION`）の両方を追随させる。
- リポジトリは **iCloud Drive 同期対象外**（`$HOME/Projects` 配下など）に
  置くこと。過去に iCloud の同期競合コピー生成が原因で記事画像が広範囲に
  破損した事故がある（README.org の Known Issues 参照）。
- 記事を大きく編集した後は、Hugo のビルド成功だけでは画像参照切れを
  検出できないため、実際に公開ページを目視で確認すること。
- **カスタムドメインのDNS設定（2026-09-21修正済み、詳細はREADME.orgの
  Known Issues参照）**: `www.ty07.net` は `ac1965.github.io` へのCNAME、
  apex（`ty07.net`）は GitHub Pages公式の4つのA レコード
  （`185.199.108/109/110/111.153`）で構成されており、どちらもCloudflareの
  プロキシは**意図的に無効（DNS only）**にしてある。これは以前
  「Cloudflareのプロキシが古いGitHub IPを覆い隠していた」という不具合を
  修正した結果なので、プロキシを有効化する提案・変更は行わないこと。
  また `ty07.net` ゾーンには `ac1965@ty07.net` のiCloudカスタムメール
  ドメイン（MX/SPF/DKIM/`apple-domain`確認用TXT）が生きているため、
  ネームサーバーの委任先やこれらメール関連レコードは絶対に変更しないこと。

## コミットメッセージ

既存のコミット履歴に合わせ、`fix:` / `feat:` / `docs:` / `chore:` などの
Conventional Commits 形式・日本語の説明文で記述する。
