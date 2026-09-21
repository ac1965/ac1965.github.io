# Makefile — org2hugo.py によるエクスポートと prepare-content.sh の実行をまとめる。
#
# 前提: org2hugo.py, deploy.sh, prepare-content.sh, all-posts.org と
# 同じディレクトリ（mysite/）に置く。
#
# 公開の仕組みが変わった点に注意:
#   旧: deploy.sh が preflight → sync_post_assets → place_covers →
#       build_site(hugo --minify) → sync_deploy_dir → commit_and_push まで
#       一括で行い、deploy ブランチへの push が公開そのものだった。
#   新: content/post/ は .gitignore 対象から外れ、Git 管理下に置く。
#       ローカルでは prepare-content.sh（sync_post_assets → place_covers）
#       までしか行わず、Hugo ビルドと GitHub Pages への公開は push を
#       トリガーに GitHub Actions（.github/workflows/pages.yml）が行う。
#       deploy.sh は prepare-content.sh を呼ぶだけの薄いラッパーになり、
#       --dry-run オプションは廃止した（build/push を分岐する対象が
#       もう無いため）。
# deploy.sh 自体は org2hugo.py を呼ばない（content/post が既に存在している
# 前提で動く）ため、Makefile 側で必ず org2hugo を先に実行する。

ORG_FILE     ?= all-posts.org
OUTDIR       ?= content/post
ASSET_DIR    ?= assets/img/post-assets
TZ_OFFSET    ?= +09:00
PYTHON       ?= python3
DEPLOY_FLAGS ?=

.PHONY: help deps org2hugo-check org2hugo deploy-check deploy check clean-content

.DEFAULT_GOAL := help

help:
	@echo "利用可能なターゲット:"
	@echo "  make deps            - hugo/git/rsync/zsh/pandoc の有無を確認する"
	@echo "  make org2hugo-check  - org2hugo.py を --dry-run で実行（書き込みなし）"
	@echo "  make org2hugo        - org2hugo.py を実行して $(OUTDIR) を生成"
	@echo "  make deploy-check    - org2hugo実行後、prepare-content.sh を実行し、"
	@echo "                         さらにローカルで hugo --minify を試し、"
	@echo "                         push後にGitHub Actionsのビルドが通るかを事前確認する"
	@echo "  make deploy          - org2hugo実行後、deploy.sh(=prepare-content.sh)を実行する"
	@echo "                         （commit・pushは行わない。手動で行うこと）"
	@echo "  make check           - org2hugo-check + deploy.sh/prepare-content.shの構文チェックのみ"
	@echo "                         （hugoビルドは行わない、最速の確認）"
	@echo "  make clean-content   - $(OUTDIR) を削除する（要再生成。Git管理下のため誤って"
	@echo "                         commit・pushしないよう git status で確認してから使うこと）"
	@echo ""
	@echo "deploy.sh/prepare-content.sh へフラグを渡す場合: make deploy DEPLOY_FLAGS=--skip-cover"
	@echo ""
	@echo "公開は make deploy の後、git add content && git commit && git push で行う。"
	@echo "push後の実際のビルド・公開は GitHub Actions が行う(要: Pages Source切替)。"

## --- 依存ツールの確認 -------------------------------------------------
# hugo/git/rsync は deploy.sh の require_cmd でも見ているが、
# 失敗してからではなく事前に気づけるようここでも確認する。

deps:
	@command -v pandoc >/dev/null 2>&1 \
		&& echo "pandoc: OK ($$(pandoc --version | head -1))" \
		|| echo "pandoc: NOT FOUND"
	@command -v hugo >/dev/null 2>&1 \
		&& echo "hugo:   OK ($$(hugo version))" \
		|| echo "hugo: NOT FOUND"
	@command -v git >/dev/null 2>&1 \
		&& echo "git:    OK" \
		|| echo "git: NOT FOUND"
	@command -v rsync >/dev/null 2>&1 \
		&& echo "rsync:  OK" \
		|| echo "rsync: NOT FOUND"
	@command -v zsh >/dev/null 2>&1 \
		&& echo "zsh:    OK ($$(zsh --version))" \
		|| echo "zsh: NOT FOUND（deploy.shはzshスクリプトのため必須）"

## --- org2hugo.py -------------------------------------------------------

# 書き込みを一切せず、警告だけを見る。
org2hugo-check:
	$(PYTHON) org2hugo.py $(ORG_FILE) \
		--outdir $(OUTDIR) \
		--asset-dir $(ASSET_DIR) \
		--tz $(TZ_OFFSET) \
		--dry-run --verbose

# 実際に $(OUTDIR) へ書き出す（content/post は Git 管理下に置くようになった
# ため、書き込みは実際のリポジトリの変更になる点に注意。git status で
# 差分を確認してから add・commit すること）。
org2hugo:
	$(PYTHON) org2hugo.py $(ORG_FILE) \
		--outdir $(OUTDIR) \
		--asset-dir $(ASSET_DIR) \
		--tz $(TZ_OFFSET)

## --- deploy.sh / prepare-content.sh --------------------------------------

# org2hugoで実ファイルを生成したうえで prepare-content.sh を実行し、
# さらにローカルで hugo --minify を試す。ここまで通れば、push後に
# GitHub Actions側のビルドもまず失敗しない、という事前確認になる
# （public/ は .gitignore 対象のままなのでコミットされない）。
deploy-check: org2hugo
	./prepare-content.sh $(DEPLOY_FLAGS)
	hugo --minify

# ローカルでの準備（org2hugo + prepare-content.sh）まで。
# commit・push は行わない（意図的に手動 — レビューを挟むため）。
# push後の実際のビルド・公開は GitHub Actions が行う。
deploy: org2hugo
	./deploy.sh $(DEPLOY_FLAGS)

## --- 軽量チェック（hugoビルドは行わない） --------------------------------

# org2hugoのdry-run + deploy.sh/prepare-content.shの構文チェック（zsh -n）
# だけを行う、一番速い確認。CIやコミット前のさっと確認用。
check: org2hugo-check
	@zsh -n deploy.sh && echo "deploy.sh: 構文OK" || echo "deploy.sh: 構文エラーあり（上記参照）"
	@zsh -n prepare-content.sh && echo "prepare-content.sh: 構文OK" || echo "prepare-content.sh: 構文エラーあり（上記参照）"

## --- 掃除 ------------------------------------------------------------

# content/post は Git 管理下にあるため、削除後は org2hugo/ox-hugoで
# 再生成しないと git 上は「削除」として差分に乗ってしまう点に注意。
clean-content:
	rm -rf $(OUTDIR)
