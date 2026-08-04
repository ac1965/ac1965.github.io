# Makefile — org2hugo.py によるエクスポートと deploy.sh の実行をまとめる。
#
# 前提: org2hugo.py, deploy.sh, all-posts.org と同じディレクトリ（mysite/）
# に置く。deploy.sh は zsh スクリプトで、以下をこの順で行う:
#   preflight_checks → sync_post_assets → place_covers → build_site(hugo --minify)
#   → [--dry-run で無ければ] sync_deploy_dir → commit_and_push
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
	@echo "  make deploy-check    - org2hugo実行後、deploy.sh --dry-run を実行"
	@echo "                         （hugoビルドまで行うが push はしない）"
	@echo "  make deploy          - org2hugo実行後、deploy.sh を実行して公開する"
	@echo "  make check           - org2hugo-check + deploy.shの構文チェックのみ"
	@echo "                         （hugoビルドは行わない、最速の確認）"
	@echo "  make clean-content   - $(OUTDIR) を削除する（ビルド成果物なので再生成可能）"
	@echo ""
	@echo "deploy.sh へフラグを渡す場合: make deploy DEPLOY_FLAGS=--skip-cover"

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

# 実際に $(OUTDIR) へ書き出す（content/post は .gitignore 対象のビルド
# 成果物なので、書き込み自体に副作用はない）。
org2hugo:
	$(PYTHON) org2hugo.py $(ORG_FILE) \
		--outdir $(OUTDIR) \
		--asset-dir $(ASSET_DIR) \
		--tz $(TZ_OFFSET)

## --- deploy.sh -----------------------------------------------------------

# org2hugoで実ファイルを生成したうえで、deploy.sh --dry-run を実行する。
# deploy.sh側の --dry-run は preflight/sync_post_assets/place_covers/
# hugo --minify まで実際に行い、rsyncとgit pushだけをスキップする
# （＝ここまで通れば本番実行してもまず失敗しない、という強い確認になる）。
deploy-check: org2hugo
	./deploy.sh --dry-run $(DEPLOY_FLAGS)

# 本番実行。
deploy: org2hugo
	./deploy.sh $(DEPLOY_FLAGS)

## --- 軽量チェック（hugoビルドは行わない） --------------------------------

# org2hugoのdry-run + deploy.shの構文チェック（zsh -n）だけを行う、
# 一番速い確認。CIやコミット前のさっと確認用。
check: org2hugo-check
	@zsh -n deploy.sh && echo "deploy.sh: 構文OK" || echo "deploy.sh: 構文エラーあり（上記参照）"

## --- 掃除 ------------------------------------------------------------

clean-content:
	rm -rf $(OUTDIR)
