# shared.mk — Common Makefile targets for KOReader plugins
#
# Include this in your plugin's Makefile:
#
#   PLUGIN_NAME := myplugin
#   include /opt/koplugin-dev/shared.mk
#
# Or if running outside the container, set KOPLUGIN_DEV_DIR:
#
#   KOPLUGIN_DEV_DIR := /path/to/koplugin-dev
#   include $(KOPLUGIN_DEV_DIR)/shared.mk

# =============================================================================
# Configuration (override in your Makefile before including this file)
# =============================================================================

# Plugin name (required) — e.g., "acsm", "localsend", "kindle"
PLUGIN_NAME ?= plugin

# KOReader version for the dev container
KOREADER_VERSION ?= v2026.03

# Docker image name
IMAGE_NAME ?= koplugin-dev:$(KOREADER_VERSION)

# Architecture: arm64 on Apple Silicon, x86_64 elsewhere
DOCKER_ARCH ?= $(shell uname -m | sed 's/arm64/aarch64/' | grep -q aarch64 && echo arm64 || echo x86_64)

# Plugin source directory (current directory by default)
PLUGIN_DIR ?= $(shell pwd)

# Spec directory layout (override if different)
SPEC_DIR ?= spec

# Tags to exclude from normal test runs (e.g., e2e tests that need network)
EXCLUDE_TAGS ?= e2e

# Path to commonrequire.lua (in container)
COMMONREQUIRE ?= /opt/koplugin-dev/commonrequire.lua

# =============================================================================
# Docker run command (shared)
# =============================================================================

DOCKER_RUN = docker run --rm \
	-v "$(PLUGIN_DIR)":/opt/plugin \
	-e PLUGIN_PATH=/opt/plugin \
	$(IMAGE_NAME)

DOCKER_RUN_IT = docker run --rm -it \
	-v "$(PLUGIN_DIR)":/opt/plugin \
	-e PLUGIN_PATH=/opt/plugin \
	$(IMAGE_NAME)

# =============================================================================
# Help
# =============================================================================

.PHONY: help
help: ## Show this help
	@echo "koplugin-dev targets for $(PLUGIN_NAME):"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

# =============================================================================
# Docker image
# =============================================================================

.PHONY: docker-build
docker-build: ## Build the koplugin-dev Docker image
	@if [ -z "$$(docker images -q $(IMAGE_NAME) 2>/dev/null)" ]; then \
		echo "Building $(IMAGE_NAME)..."; \
		docker build \
			--build-arg KOREADER_VERSION=$(KOREADER_VERSION) \
			--build-arg ARCH=$(DOCKER_ARCH) \
			-t $(IMAGE_NAME) \
			$${KOPLUGIN_DEV_DIR:-/opt/koplugin-dev}; \
	else \
		echo "$(IMAGE_NAME) already exists"; \
	fi

.PHONY: docker-rebuild
docker-rebuild: ## Force rebuild the Docker image
	docker build \
		--build-arg KOREADER_VERSION=$(KOREADER_VERSION) \
		--build-arg ARCH=$(DOCKER_ARCH) \
		-t $(IMAGE_NAME) \
		$${KOPLUGIN_DEV_DIR:-/opt/koplugin-dev}

# =============================================================================
# Testing (Lua via busted-koreader)
# =============================================================================

.PHONY: test
test: docker-build ## Run Lua tests (excludes e2e)
	$(DOCKER_RUN) busted-koreader --verbose \
		--helper=$(COMMONREQUIRE) \
		--exclude-tags=$(EXCLUDE_TAGS) \
		/opt/plugin/$(SPEC_DIR)/

.PHONY: test-all
test-all: docker-build ## Run all Lua tests including e2e
	$(DOCKER_RUN) busted-koreader --verbose \
		--helper=$(COMMONREQUIRE) \
		/opt/plugin/$(SPEC_DIR)/

.PHONY: test-e2e
test-e2e: docker-build ## Run only e2e tests
	$(DOCKER_RUN) busted-koreader --verbose \
		--helper=$(COMMONREQUIRE) \
		--filter=e2e \
		/opt/plugin/$(SPEC_DIR)/

.PHONY: test-filter
test-filter: docker-build ## Run tests matching FILTER pattern (pass FILTER="...")
	$(DOCKER_RUN) busted-koreader --verbose \
		--helper=$(COMMONREQUIRE) \
		--filter="$(FILTER)" \
		/opt/plugin/$(SPEC_DIR)/

# =============================================================================
# Testing (Go)
# =============================================================================

.PHONY: test-go
test-go: docker-build ## Run Go tests
	$(DOCKER_RUN) sh -c 'cd /opt/plugin && go test ./... -v'

.PHONY: test-go-race
test-go-race: docker-build ## Run Go tests with race detector
	$(DOCKER_RUN) sh -c 'cd /opt/plugin && go test ./... -race -v'

# =============================================================================
# Linting
# =============================================================================

.PHONY: lint
lint: lint-lua lint-go ## Run all linters

.PHONY: lint-lua
lint-lua: docker-build ## Run luacheck
	$(DOCKER_RUN) luacheck /opt/plugin

.PHONY: lint-go
lint-go: docker-build ## Run golangci-lint
	$(DOCKER_RUN) sh -c 'cd /opt/plugin && golangci-lint run'

# =============================================================================
# Formatting
# =============================================================================

.PHONY: fmt
fmt: fmt-lua fmt-go ## Format all code

.PHONY: fmt-lua
fmt-lua: docker-build ## Format Lua with stylua
	$(DOCKER_RUN) stylua /opt/plugin

.PHONY: fmt-go
fmt-go: docker-build ## Format Go code
	$(DOCKER_RUN) sh -c 'cd /opt/plugin && go fmt ./...'

.PHONY: fmt-check
fmt-check: docker-build ## Check formatting without modifying
	$(DOCKER_RUN) stylua --check /opt/plugin
	$(DOCKER_RUN) sh -c 'cd /opt/plugin && test -z "$$(gofmt -l .)"'

# =============================================================================
# Building
# =============================================================================

.PHONY: build-go
build-go: docker-build ## Build Go binary (native)
	$(DOCKER_RUN) sh -c 'cd /opt/plugin && go build -o $(PLUGIN_NAME) ./cmd/...'

.PHONY: build-go-arm
build-go-arm: docker-build ## Cross-compile Go for ARM (Kindle/Kobo)
	$(DOCKER_RUN) sh -c 'cd /opt/plugin && \
		GOOS=linux GOARCH=arm GOARM=7 CGO_ENABLED=0 \
		go build -ldflags="-s -w" -o $(PLUGIN_NAME)-armv7 ./cmd/... && \
		GOOS=linux GOARCH=arm64 CGO_ENABLED=0 \
		go build -ldflags="-s -w" -o $(PLUGIN_NAME)-arm64 ./cmd/...'

# =============================================================================
# Interactive
# =============================================================================

.PHONY: shell
shell: docker-build ## Drop into a shell in the dev container
	$(DOCKER_RUN_IT) /bin/bash

.PHONY: lua
lua: docker-build ## Start KOReader's LuaJIT REPL
	$(DOCKER_RUN_IT) /opt/lib/koreader/luajit

# =============================================================================
# Cleanup
# =============================================================================

.PHONY: clean
clean: ## Remove build artifacts
	rm -rf build/ *.zip $(PLUGIN_NAME) $(PLUGIN_NAME)-arm*

.PHONY: docker-clean
docker-clean: ## Remove Docker image
	docker rmi $(IMAGE_NAME) 2>/dev/null || true
