.PHONY: help build up down exec clean compile watch pdf stop logs

# TeXファイルのリストを取得
TEX_FILES := $(wildcard src/*.tex)
PDF_FILES := $(patsubst src/%.tex,pdf/%.pdf,$(TEX_FILES))

# 実行環境の判定
IN_DEVCONTAINER := $(shell test -f /.dockerenv && test -f /workspace/.devcontainer/devcontainer.json && echo 1 || echo 0)

# 環境に応じたコマンドの定義
ifeq ($(IN_DEVCONTAINER),1)
    # Dev Container 内での実行コマンド
    DOCKER_PREFIX =
    CD_PREFIX = cd /workspace &&
else
    # Docker Compose 経由での実行コマンド
    DOCKER_PREFIX = docker compose exec -T latex
    CD_PREFIX = bash -c cd /workspace &&
endif

# 共通のコマンドを定義
LATEX_CMD = $(DOCKER_PREFIX) $(CD_PREFIX) TEXINPUTS=./src//: latexmk -pdfdvi
LATEX_CLEAN = $(DOCKER_PREFIX) $(CD_PREFIX) latexmk -c
LATEX_CLEAN_ALL = $(DOCKER_PREFIX) $(CD_PREFIX) latexmk -C
CP_CMD = $(DOCKER_PREFIX) $(CD_PREFIX) cp
RM_CMD = $(DOCKER_PREFIX) $(CD_PREFIX) rm -rf
WATCH_CMD = $(DOCKER_PREFIX) bash -c 'cd /workspace && \
    while true; do \
        inotifywait -r -e modify,create,delete src/*.tex; \
        echo "Changes detected, recompiling..."; \
        for tex in src/*.tex; do \
            if [ -f "$$tex" ]; then \
                echo "Compiling: $$tex"; \
                TEXINPUTS=./src//: latexmk -pdfdvi "$$tex" && \
                mkdir -p pdf && \
                cp build/$$(basename "$$tex" .tex).pdf pdf/ || echo "Failed to copy PDF for $$tex"; \
            fi \
        done; \
    done'
LATEX_SINGLE = $(LATEX_CMD)

# デフォルトターゲット
all: $(PDF_FILES) ## すべての TeX ファイルを PDF に変換
	@if [ -n "$(TEX_FILES)" ]; then \
		echo "コンパイル完了。ファイルの変更監視を開始します..."; \
		make watch; \
	else \
		echo "[WARNING] src/ ディレクトリに .tex ファイルが見つかりません。"; \
		exit 1; \
	fi

help: ## ヘルプを表示
	@echo "利用可能なコマンド:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

# ファイル別の PDF ビルドルール
pdf/%.pdf: src/%.tex
	@mkdir -p pdf build
	$(LATEX_SINGLE) $<
	$(CP_CMD) build/$(notdir $(basename $<)).pdf $@

# LaTeX 関連コマンド
compile: ## src 下の .tex ファイルをコンパイル
	@mkdir -p pdf build
	@for tex in $(TEX_FILES); do \
		echo "コンパイル: $$tex"; \
		$(LATEX_CMD) $$tex; \
		$(CP_CMD) build/$$(basename $${tex%.tex}).pdf pdf/; \
	done
	@echo "コンパイル完了"

watch: ## ファイル変更を監視してコンパイル
	@mkdir -p pdf build
	@echo "watching: src/*.tex"
	$(WATCH_CMD)

copy: ## 最新の .tex ファイルをコピーして日付を更新
	@FILE_NAME="src/$$(TZ=Asia/Tokyo date '+%Y-%m-%d').tex"; \
	FILE_BASENAME="$$(TZ=Asia/Tokyo date '+%Y-%m-%d').tex"; \
	if [ ! -e "$${FILE_NAME}" ]; then \
		latest_tex=$$(ls -t src/*.tex | head -n 1); \
		if [ -z "$$latest_tex" ]; then \
			echo "[ERROR] No tex files found in src/"; \
			exit 1; \
		fi; \
		cat "$$latest_tex" | sed -e "s/^\\\date{.*}/\\\date{$$(LANG=C LC_ALL=C TZ=Asia/Tokyo date '+%Y-%m-%d %a')}/g" > "$${FILE_NAME}"; \
		echo "CREATED: $${FILE_NAME}"; \
		$(LATEX_SINGLE) src/$${FILE_BASENAME} && \
		$(CP_CMD) build/$$(basename $${FILE_BASENAME} .tex).pdf pdf/; \
		code "$${FILE_NAME}"; \
		make watch "$${FILE_BASENAME}" & \
	else \
		echo "[ERROR] ALREADY EXISTS: $${FILE_NAME}"; \
	fi

clean: ## LaTeX 中間ファイルを削除
	@for tex in $(TEX_FILES); do \
		echo "中間ファイル削除中: $$tex"; \
		$(LATEX_CLEAN) $$tex; \
	done
	$(RM_CMD) pdf/*

clean-all: ## すべての LaTeX 生成ファイルを削除
	@for tex in $(TEX_FILES); do \
		echo "生成ファイル完全削除中: $$tex"; \
		$(LATEX_CLEAN_ALL) $$tex; \
	done
	$(RM_CMD) pdf/* build/*

# Docker 関連コマンド実行時の実行環境チェック
# devcontainer 下で docker コマンドを実行できないので、その場合は警告文を表示して終了する
check_docker_cmd = @if [ "$(IN_DEVCONTAINER)" = "1" ]; then \
	echo "[ERROR] Dev Container 環境では Docker 関連コマンドは使用できません"; \
	exit 1; \
fi

# Docker 関連コマンド
build: ## Docker イメージをビルド
	$(check_docker_cmd)
	docker compose build

up: ## コンテナを起動（バックグラウンド）
	$(check_docker_cmd)
	docker compose up -d

down: ## コンテナを停止・削除
	$(check_docker_cmd)
	docker compose down

exec: ## コンテナに接続
	$(check_docker_cmd)
	docker compose exec latex bash

stop: ## コンテナを停止
	$(check_docker_cmd)
	docker compose stop

logs: ## コンテナのログを表示
	$(check_docker_cmd)
	docker compose logs -f latex

# 開発用コマンド
setup: ## 初回セットアップ (ビルド + 起動)
	@if [ "$(IN_DEVCONTAINER)" = "1" ]; then \
		echo "[INFO] Dev Container 環境では make setup による初回セットアップは不要です。"; \
		echo "以下のコマンドでコンパイルできます:"; \
		echo "  make compile  # src 下の .tex ファイルをコンパイル"; \
		echo "  make watch   # ファイルの変更を監視してコンパイル"; \
	else \
		make build up; \
		echo "環境構築を完了しました。以下のコマンドでコンパイルできます:"; \
		echo "  make compile  # src 下の .tex ファイルをコンパイル"; \
		echo "  make watch   # ファイルの変更を監視してコンパイル"; \
	fi

dev: ## 開発モード (起動 + 監視コンパイル)
	@if [ "$(IN_DEVCONTAINER)" = "1" ]; then \
		echo "[WARNING] Dev Container 環境では make up は不要です。make watch を実行します"; \
		make watch; \
	else \
		make up watch; \
	fi

restart: ## コンテナを再起動
	$(check_docker_cmd)
	@make down up

rebuild: ## 完全に再ビルド
	$(check_docker_cmd)
	@make down build up

# ファイル操作
open-pdf: ## 生成されたPDFを開く（Mac用）
	@if [ -f build/sample.pdf ]; then \
		open build/sample.pdf; \
	else \
		echo "PDFファイルが見つかりません。先に make compile を実行してください。"; \
	fi
