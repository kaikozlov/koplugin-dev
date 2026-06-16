set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

[private]
_repo_dir := source_directory()

_default:
    @just --list

docker-build:
    @version="$(awk -F= '/^ARG KOREADER_VERSION=/{print $2; exit}' '{{ _repo_dir }}/Dockerfile')" && \
    image="koplugin-dev:$version" && \
    docker build -t "$image" '{{ _repo_dir }}'

docker-rebuild:
    @version="$(awk -F= '/^ARG KOREADER_VERSION=/{print $2; exit}' '{{ _repo_dir }}/Dockerfile')" && \
    image="koplugin-dev:$version" && \
    docker build --no-cache -t "$image" '{{ _repo_dir }}'

shell: docker-build
    @version="$(awk -F= '/^ARG KOREADER_VERSION=/{print $2; exit}' '{{ _repo_dir }}/Dockerfile')" && \
    image="koplugin-dev:$version" && \
    docker run --rm -it "$image" /bin/bash

test: docker-build
    @version="$(awk -F= '/^ARG KOREADER_VERSION=/{print $2; exit}' '{{ _repo_dir }}/Dockerfile')" && \
    image="koplugin-dev:$version" && \
    echo "Testing image $image..." && \
    docker run --rm "$image" sh -c '\
        echo "KOReader: $(cat /opt/lib/koreader/git-rev 2>/dev/null || echo unknown)" && \
        echo "Go: $(go version)" && \
        echo "golangci-lint: $(golangci-lint --version | head -1)" && \
        echo "busted: $(busted-koreader --version)" && \
        echo "luacheck: $(luacheck --version)" && \
        echo "stylua: $(stylua --version)" && \
        echo "lua-language-server: $(lua-language-server --version)" && \
        echo "" && \
        echo "✓ All tools present"'

clean:
    @version="$(awk -F= '/^ARG KOREADER_VERSION=/{print $2; exit}' '{{ _repo_dir }}/Dockerfile')" && \
    image="koplugin-dev:$version" && \
    docker rmi "$image" 2>/dev/null || true
