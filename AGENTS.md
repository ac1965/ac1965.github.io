# AGENTS.md

このファイルは、このリポジトリで作業する AI コーディングエージェント向けの
ガイドです。詳細な運用手順は [README.org](README.org) を正とするため、
矛盾があれば README.org を優先してください。

## プロジェクト概要

[Hugo](https://gohugo.io/) + [Blowfish](https://blowfish.page/) テーマで
構築された個人ブログ（ty07.net）。記事は Emacs の Org-mode で執筆し、
[ox-hugo](https://ox-hugo.scripter.co/) により Markdown へ変換して Hugo で
ビルド・公開する。

## リポジトリ構成

- `all-posts.org` — 記事の Org ソース。1 ファイルに全記事を subtree として格納
- `content/` — **ox-hugo（Emacs）により生成される**。手動編集しない
- `config/_default/` — Hugo / Blowfish の設定ファイル一式
- `themes/blowfish/` — Blowfish テーマ（Git submodule、`branch = main` を追跡）
- `deploy.sh` — ローカルからの手動デプロイスクリプト（zsh）。`content/post`
  が既に生成済みであることを前提に、カバー画像配置 → ビルド → 公開ディレクトリ
  への同期 → commit & push を行う
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

## よく使うコマンド

```bash
hugo server --buildDrafts --disableFastRender   # ローカル開発サーバ (http://localhost:1313)
hugo --minify                                    # 本番ビルド(出力先 ./public/)
./deploy.sh --dry-run                            # デプロイ前確認(rsync・git pushはスキップ)
./deploy.sh                                      # 本番デプロイ(cd mysite/ で実行)
```

`deploy.sh` は `content/post` が既に生成済みであることを前提とするため、
実行前に `all-posts.org` の変更が `content/` に反映済みか確認すること
(反映方法は上記「執筆ワークフロー」参照)。`Makefile` の `make deploy` 等は
README.org 非記載の別経路であり、正規手順ではない点に注意。

## 変更時の注意事項

- **`content/` を直接編集しない**。編集元は必ず `all-posts.org` 側で行う。
  `content/` はビルド成果物であり再生成される。
- **`resources/_gen/` と `public/` を Git 管理下に置かない**。`.gitignore`
  で除外済みだが、誤ってコミットしないよう注意。
- 記事本体（`content/post/<slug>.md`）は Page Bundle ではなく **flat file**
  として出力される既知の設計負債がある。カバー画像・記事内画像は
  `<slug>/` ディレクトリ配下に手動配置し、`deploy.sh` が front matter の
  日付を基にカバー画像を機械的に配置している（詳細は README.org の
  Writing Workflow / Deploy 参照）。
- 画像ファイルは拡張子と実データ形式を一致させること。不一致があると
  Hugo の `.Resize` 処理がビルド全体を失敗させる。
- Blowfish テーマ更新時は `themes/blowfish/config.toml` の
  `[module.hugoVersion]`（min/max）を確認し、ローカルの Hugo バージョンと
  CI（`.github/workflows/deploy.yml` の `hugo-version`）の両方を追随させる。
- リポジトリ（および `deploy.sh` の `PROJECTS_ROOT`）は **iCloud Drive
  同期対象外**（`$HOME/Projects` 配下など）に置くこと。過去に iCloud の
  同期競合コピー生成が原因で記事画像が広範囲に破損した事故がある
  （README.org の Known Issues 参照）。
- 記事を大きく編集した後は、Hugo のビルド成功だけでは画像参照切れを
  検出できないため、実際に公開ページを目視で確認すること。

## コミットメッセージ

既存のコミット履歴に合わせ、`fix:` / `feat:` / `docs:` / `chore:` などの
Conventional Commits 形式・日本語の説明文で記述する。
