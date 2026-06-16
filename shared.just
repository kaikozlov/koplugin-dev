# shared.just — Common just recipes for KOReader plugins
#
# Import this from a plugin justfile:
#
#   plugin_name := "myplugin"
#   import "../koplugin-dev/shared.just"
#
# The default image tag is derived from the Dockerfile next to this file.
# Override with environment variables when needed:
#   IMAGE_NAME=koplugin-dev:v2026.03 just test
#   SPEC_DIR=tests just test

set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

[private]
_koplugin_dev_dir := source_directory()
[private]
_spec_dir := env_var_or_default("SPEC_DIR", "spec")
[private]
_exclude_tags := env_var_or_default("EXCLUDE_TAGS", "e2e")
[private]
_commonrequire := env_var_or_default("COMMONREQUIRE", "/opt/koplugin-dev/commonrequire.lua")

_default:
    @just --list

# Build the koplugin-dev Docker image if it does not already exist
docker-build:
    @version="$(awk -F= '/^ARG KOREADER_VERSION=/{print $2; exit}' '{{ _koplugin_dev_dir }}/Dockerfile')" && \
    image="${IMAGE_NAME:-koplugin-dev:$version}" && \
    if [ -z "$(docker images -q "$image" 2>/dev/null)" ]; then \
        echo "Building $image..."; \
        docker build -t "$image" '{{ _koplugin_dev_dir }}'; \
    else \
        echo "$image already exists"; \
    fi

# Force rebuild the koplugin-dev Docker image
docker-rebuild:
    @version="$(awk -F= '/^ARG KOREADER_VERSION=/{print $2; exit}' '{{ _koplugin_dev_dir }}/Dockerfile')" && \
    image="${IMAGE_NAME:-koplugin-dev:$version}" && \
    docker build --no-cache -t "$image" '{{ _koplugin_dev_dir }}'

# Run Lua tests, excluding e2e by default
test: docker-build
    @version="$(awk -F= '/^ARG KOREADER_VERSION=/{print $2; exit}' '{{ _koplugin_dev_dir }}/Dockerfile')" && \
    image="${IMAGE_NAME:-koplugin-dev:$version}" && \
    plugin_dir="${PLUGIN_DIR:-$PWD}" && \
    docker run --rm \
        -v "$plugin_dir":/opt/plugin \
        -e PLUGIN_PATH=/opt/plugin \
        -e PLUGIN_NAME={{ plugin_name }} \
        "$image" busted-koreader --verbose \
        --helper={{ _commonrequire }} \
        --exclude-tags={{ _exclude_tags }} \
        /opt/plugin/{{ _spec_dir }}/

# Run all Lua tests, including e2e, with host networking
test-all: docker-build
    @version="$(awk -F= '/^ARG KOREADER_VERSION=/{print $2; exit}' '{{ _koplugin_dev_dir }}/Dockerfile')" && \
    image="${IMAGE_NAME:-koplugin-dev:$version}" && \
    plugin_dir="${PLUGIN_DIR:-$PWD}" && \
    docker run --rm --network=host \
        -v "$plugin_dir":/opt/plugin \
        -e PLUGIN_PATH=/opt/plugin \
        -e PLUGIN_NAME={{ plugin_name }} \
        "$image" busted-koreader --verbose \
        --helper={{ _commonrequire }} \
        /opt/plugin/{{ _spec_dir }}/

# Run only e2e tests, with host networking
test-e2e: docker-build
    @version="$(awk -F= '/^ARG KOREADER_VERSION=/{print $2; exit}' '{{ _koplugin_dev_dir }}/Dockerfile')" && \
    image="${IMAGE_NAME:-koplugin-dev:$version}" && \
    plugin_dir="${PLUGIN_DIR:-$PWD}" && \
    docker run --rm --network=host \
        -v "$plugin_dir":/opt/plugin \
        -e PLUGIN_PATH=/opt/plugin \
        -e PLUGIN_NAME={{ plugin_name }} \
        "$image" busted-koreader --verbose \
        --helper={{ _commonrequire }} \
        --filter=e2e \
        /opt/plugin/{{ _spec_dir }}/

# Run tests matching a busted filter pattern
test-filter filter: docker-build
    @version="$(awk -F= '/^ARG KOREADER_VERSION=/{print $2; exit}' '{{ _koplugin_dev_dir }}/Dockerfile')" && \
    image="${IMAGE_NAME:-koplugin-dev:$version}" && \
    plugin_dir="${PLUGIN_DIR:-$PWD}" && \
    docker run --rm \
        -v "$plugin_dir":/opt/plugin \
        -e PLUGIN_PATH=/opt/plugin \
        -e PLUGIN_NAME={{ plugin_name }} \
        "$image" busted-koreader --verbose \
        --helper={{ _commonrequire }} \
        --filter='{{ filter }}' \
        /opt/plugin/{{ _spec_dir }}/

# Run Go tests
test-go: docker-build
    @version="$(awk -F= '/^ARG KOREADER_VERSION=/{print $2; exit}' '{{ _koplugin_dev_dir }}/Dockerfile')" && \
    image="${IMAGE_NAME:-koplugin-dev:$version}" && \
    plugin_dir="${PLUGIN_DIR:-$PWD}" && \
    docker run --rm -v "$plugin_dir":/opt/plugin -e PLUGIN_PATH=/opt/plugin -e PLUGIN_NAME={{ plugin_name }} \
        "$image" sh -c 'cd /opt/plugin && go test ./... -v'

# Run Go tests with the race detector
test-go-race: docker-build
    @version="$(awk -F= '/^ARG KOREADER_VERSION=/{print $2; exit}' '{{ _koplugin_dev_dir }}/Dockerfile')" && \
    image="${IMAGE_NAME:-koplugin-dev:$version}" && \
    plugin_dir="${PLUGIN_DIR:-$PWD}" && \
    docker run --rm -v "$plugin_dir":/opt/plugin -e PLUGIN_PATH=/opt/plugin -e PLUGIN_NAME={{ plugin_name }} \
        "$image" sh -c 'cd /opt/plugin && go test ./... -race -v'

# Run all linters
lint: lint-lua lint-go

# Run luacheck
lint-lua: docker-build
    @version="$(awk -F= '/^ARG KOREADER_VERSION=/{print $2; exit}' '{{ _koplugin_dev_dir }}/Dockerfile')" && \
    image="${IMAGE_NAME:-koplugin-dev:$version}" && \
    plugin_dir="${PLUGIN_DIR:-$PWD}" && \
    docker run --rm -v "$plugin_dir":/opt/plugin -e PLUGIN_PATH=/opt/plugin -e PLUGIN_NAME={{ plugin_name }} \
        "$image" luacheck /opt/plugin

# Run golangci-lint
lint-go: docker-build
    @version="$(awk -F= '/^ARG KOREADER_VERSION=/{print $2; exit}' '{{ _koplugin_dev_dir }}/Dockerfile')" && \
    image="${IMAGE_NAME:-koplugin-dev:$version}" && \
    plugin_dir="${PLUGIN_DIR:-$PWD}" && \
    docker run --rm -v "$plugin_dir":/opt/plugin -e PLUGIN_PATH=/opt/plugin -e PLUGIN_NAME={{ plugin_name }} \
        "$image" sh -c 'cd /opt/plugin && golangci-lint run'

# Format Lua and Go code
fmt: fmt-lua fmt-go

# Format Lua with stylua
fmt-lua: docker-build
    @version="$(awk -F= '/^ARG KOREADER_VERSION=/{print $2; exit}' '{{ _koplugin_dev_dir }}/Dockerfile')" && \
    image="${IMAGE_NAME:-koplugin-dev:$version}" && \
    plugin_dir="${PLUGIN_DIR:-$PWD}" && \
    docker run --rm -v "$plugin_dir":/opt/plugin -e PLUGIN_PATH=/opt/plugin -e PLUGIN_NAME={{ plugin_name }} \
        "$image" stylua /opt/plugin

# Format Go code
fmt-go: docker-build
    @version="$(awk -F= '/^ARG KOREADER_VERSION=/{print $2; exit}' '{{ _koplugin_dev_dir }}/Dockerfile')" && \
    image="${IMAGE_NAME:-koplugin-dev:$version}" && \
    plugin_dir="${PLUGIN_DIR:-$PWD}" && \
    docker run --rm -v "$plugin_dir":/opt/plugin -e PLUGIN_PATH=/opt/plugin -e PLUGIN_NAME={{ plugin_name }} \
        "$image" sh -c 'cd /opt/plugin && go fmt ./...'

# Check formatting without modifying files
fmt-check: docker-build
    @version="$(awk -F= '/^ARG KOREADER_VERSION=/{print $2; exit}' '{{ _koplugin_dev_dir }}/Dockerfile')" && \
    image="${IMAGE_NAME:-koplugin-dev:$version}" && \
    plugin_dir="${PLUGIN_DIR:-$PWD}" && \
    docker run --rm -v "$plugin_dir":/opt/plugin -e PLUGIN_PATH=/opt/plugin -e PLUGIN_NAME={{ plugin_name }} \
        "$image" stylua --check /opt/plugin && \
    docker run --rm -v "$plugin_dir":/opt/plugin -e PLUGIN_PATH=/opt/plugin -e PLUGIN_NAME={{ plugin_name }} \
        "$image" sh -c 'cd /opt/plugin && test -z "$(gofmt -l .)"'

# Build Go binary for the native architecture
build-go: docker-build
    @version="$(awk -F= '/^ARG KOREADER_VERSION=/{print $2; exit}' '{{ _koplugin_dev_dir }}/Dockerfile')" && \
    image="${IMAGE_NAME:-koplugin-dev:$version}" && \
    plugin_dir="${PLUGIN_DIR:-$PWD}" && \
    docker run --rm -v "$plugin_dir":/opt/plugin -e PLUGIN_PATH=/opt/plugin -e PLUGIN_NAME={{ plugin_name }} \
        "$image" sh -c 'cd /opt/plugin && go build -o {{ plugin_name }} ./cmd/...'

# Cross-compile Go binaries for Kindle/Kobo ARM targets
build-go-arm: docker-build
    @version="$(awk -F= '/^ARG KOREADER_VERSION=/{print $2; exit}' '{{ _koplugin_dev_dir }}/Dockerfile')" && \
    image="${IMAGE_NAME:-koplugin-dev:$version}" && \
    plugin_dir="${PLUGIN_DIR:-$PWD}" && \
    docker run --rm -v "$plugin_dir":/opt/plugin -e PLUGIN_PATH=/opt/plugin -e PLUGIN_NAME={{ plugin_name }} \
        "$image" sh -c 'cd /opt/plugin && \
            GOOS=linux GOARCH=arm GOARM=7 CGO_ENABLED=0 \
            go build -ldflags="-s -w" -o {{ plugin_name }}-armv7 ./cmd/... && \
            GOOS=linux GOARCH=arm64 CGO_ENABLED=0 \
            go build -ldflags="-s -w" -o {{ plugin_name }}-arm64 ./cmd/...'

# Drop into a shell in the dev container
shell: docker-build
    @version="$(awk -F= '/^ARG KOREADER_VERSION=/{print $2; exit}' '{{ _koplugin_dev_dir }}/Dockerfile')" && \
    image="${IMAGE_NAME:-koplugin-dev:$version}" && \
    plugin_dir="${PLUGIN_DIR:-$PWD}" && \
    docker run --rm -it -v "$plugin_dir":/opt/plugin -e PLUGIN_PATH=/opt/plugin -e PLUGIN_NAME={{ plugin_name }} \
        "$image" /bin/bash

# Start KOReader's LuaJIT REPL
lua: docker-build
    @version="$(awk -F= '/^ARG KOREADER_VERSION=/{print $2; exit}' '{{ _koplugin_dev_dir }}/Dockerfile')" && \
    image="${IMAGE_NAME:-koplugin-dev:$version}" && \
    plugin_dir="${PLUGIN_DIR:-$PWD}" && \
    docker run --rm -it -v "$plugin_dir":/opt/plugin -e PLUGIN_PATH=/opt/plugin -e PLUGIN_NAME={{ plugin_name }} \
        "$image" /opt/lib/koreader/luajit

# Remove build artifacts
clean:
    rm -rf build/ *.zip {{ plugin_name }} {{ plugin_name }}-arm*

# Remove Docker image
docker-clean:
    @version="$(awk -F= '/^ARG KOREADER_VERSION=/{print $2; exit}' '{{ _koplugin_dev_dir }}/Dockerfile')" && \
    image="${IMAGE_NAME:-koplugin-dev:$version}" && \
    docker rmi "$image" 2>/dev/null || true
