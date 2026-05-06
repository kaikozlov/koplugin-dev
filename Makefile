# Makefile for koplugin-dev base image

KOREADER_VERSION ?= v2026.03
GO_VERSION ?= 1.24.2
IMAGE_NAME ?= koplugin-dev:$(KOREADER_VERSION)

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

.PHONY: docker-build
docker-build: ## Build the koplugin-dev Docker image
	docker build \
		--build-arg KOREADER_VERSION=$(KOREADER_VERSION) \
		--build-arg GO_VERSION=$(GO_VERSION) \
		-t $(IMAGE_NAME) .

.PHONY: docker-rebuild
docker-rebuild: ## Force rebuild (no cache)
	docker build --no-cache \
		--build-arg KOREADER_VERSION=$(KOREADER_VERSION) \
		--build-arg GO_VERSION=$(GO_VERSION) \
		-t $(IMAGE_NAME) .

.PHONY: shell
shell: docker-build ## Drop into the container
	docker run --rm -it $(IMAGE_NAME) /bin/bash

.PHONY: test
test: docker-build ## Sanity check the image
	@echo "Testing image $(IMAGE_NAME)..."
	docker run --rm $(IMAGE_NAME) sh -c '\
		echo "KOReader: $$(cat /opt/lib/koreader/git-rev 2>/dev/null || echo unknown)" && \
		echo "Go: $$(go version)" && \
		echo "golangci-lint: $$(golangci-lint --version | head -1)" && \
		echo "busted: $$(busted-koreader --version)" && \
		echo "luacheck: $$(luacheck --version)" && \
		echo "stylua: $$(stylua --version)" && \
		echo "lua-language-server: $$(lua-language-server --version)" && \
		echo "" && \
		echo "✓ All tools present"'

.PHONY: clean
clean: ## Remove the Docker image
	docker rmi $(IMAGE_NAME) 2>/dev/null || true
