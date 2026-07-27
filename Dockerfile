# koplugin-dev: Full development environment for KOReader plugins
#
# Includes:
#   - KOReader Linux release (real runtime for testing)
#   - Go toolchain + golangci-lint
#   - Lua tooling: busted, luacheck, stylua, lua-language-server
#   - Build essentials (gcc, make)
#   - CLI tools (rg, fd, jq, gh, qemu-arm)
#
# Usage:
#   just docker-build
#
# Plugin repos extend this with a thin Dockerfile or use directly via devcontainer.

ARG KOREADER_VERSION=v2026.07
ARG GO_VERSION=1.26.5
ARG GOLANGCI_LINT_VERSION=2.12.2
ARG STYLUA_VERSION=2.5.2
ARG LLS_VERSION=3.18.2
ARG UBUNTU_VERSION=26.04

# stylua image used as a binary source (stages support ARG expansion; --from does not)
FROM johnnymorganz/stylua:${STYLUA_VERSION} AS stylua-bin

FROM ubuntu:${UBUNTU_VERSION}

ARG KOREADER_VERSION
ARG GO_VERSION
ARG GOLANGCI_LINT_VERSION
ARG STYLUA_VERSION
ARG LLS_VERSION
ARG UBUNTU_VERSION

ENV DEBIAN_FRONTEND=noninteractive

# =============================================================================
# System packages
# =============================================================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Build essentials
    build-essential \
    pkg-config \
    just \
    # KOReader dependencies
    ca-certificates \
    curl \
    xz-utils \
    libssl3t64 \
    # Translations (provides msgfmt + xgettext)
    gettext \
    # Lua testing (busted + all deps)
    lua-busted \
    lua-check \
    # CLI tools
    ripgrep \
    fd-find \
    jq \
    git \
    qemu-user \
    unzip \
    zip \
    && rm -rf /var/lib/apt/lists/*

# =============================================================================
# GitHub CLI
# =============================================================================
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      -o /usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list && \
    apt-get update && apt-get install -y gh && \
    rm -rf /var/lib/apt/lists/*

# =============================================================================
# Go toolchain
# =============================================================================
RUN GOARCH=$(dpkg --print-architecture) && \
    curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${GOARCH}.tar.gz" \
      | tar -C /usr/local -xzf - && \
    /usr/local/go/bin/go version

ENV PATH="/usr/local/go/bin:/root/go/bin:${PATH}"
ENV GOPATH="/root/go"

# golangci-lint
# NOTE: use golangci-lint.run, NOT the abandoned `master` branch script.
# The old script greps checksums.txt without an end-anchor, so it also matches the
# *.sbom.json line and checksum verification fails on every modern release.
RUN curl -sSfL https://golangci-lint.run/install.sh \
      | sh -s -- -b /usr/local/bin "v${GOLANGCI_LINT_VERSION}"

# =============================================================================
# Lua tooling (not in apt)
# =============================================================================

# stylua (Lua formatter)
COPY --from=stylua-bin /stylua /usr/local/bin/stylua
RUN stylua --version

# lua-language-server
RUN LLS_ARCH=$(dpkg --print-architecture | sed 's/amd64/x64/') && \
    curl -fsSL "https://github.com/LuaLS/lua-language-server/releases/download/${LLS_VERSION}/lua-language-server-${LLS_VERSION}-linux-${LLS_ARCH}.tar.gz" \
      -o /tmp/lls.tar.gz && \
    mkdir -p /opt/lua-language-server && \
    tar -xzf /tmp/lls.tar.gz -C /opt/lua-language-server && \
    rm /tmp/lls.tar.gz && \
    ln -s /opt/lua-language-server/bin/lua-language-server /usr/local/bin/lua-language-server

# =============================================================================
# KOReader Linux release
# =============================================================================
RUN mkdir -p /opt && \
    KOREADER_ARCH=$(dpkg --print-architecture | sed 's/amd64/x86_64/') && \
    curl -fsSL -o /tmp/koreader.tar.xz \
      "https://github.com/koreader/koreader/releases/download/${KOREADER_VERSION}/koreader-linux-${KOREADER_ARCH}-${KOREADER_VERSION}.tar.xz" && \
    tar xf /tmp/koreader.tar.xz -C /opt/ && \
    rm /tmp/koreader.tar.xz && \
    /opt/lib/koreader/luajit -v

ENV KOREADER_DIR=/opt/lib/koreader

# SDL dummy driver for headless device/UIManager support
ENV SDL_VIDEODRIVER=dummy

# Lua paths: busted (apt) + KOReader modules
ENV LUA_PATH="/usr/share/lua/5.1/?.lua;/usr/share/lua/5.1/?/init.lua;${KOREADER_DIR}/common/?.lua;${KOREADER_DIR}/frontend/?.lua;${KOREADER_DIR}/?.lua;;"
ENV LUA_CPATH="/usr/lib/aarch64-linux-gnu/lua/5.1/?.so;/usr/lib/x86_64-linux-gnu/lua/5.1/?.so;${KOREADER_DIR}/common/?.so;;"

# busted-koreader: runs busted under KOReader's LuaJIT
RUN printf '#!/bin/sh\nexec %s /usr/bin/busted "$@"\n' "${KOREADER_DIR}/luajit" \
      > /usr/local/bin/busted-koreader && \
    chmod +x /usr/local/bin/busted-koreader && \
    cd "${KOREADER_DIR}" && /usr/local/bin/busted-koreader --version

# =============================================================================
# Shared koplugin-dev infrastructure
# =============================================================================
COPY commonrequire.lua /opt/koplugin-dev/commonrequire.lua
COPY shared.just /opt/koplugin-dev/shared.just

# Plugin mount point — plugins bind-mount their source here
RUN mkdir -p /opt/plugin
COPY entrypoint.sh /opt/koplugin-dev/entrypoint.sh
ENTRYPOINT ["/opt/koplugin-dev/entrypoint.sh"]

# =============================================================================
# Default working directory
# =============================================================================
WORKDIR /opt/lib/koreader

# Sanity check: print versions
RUN echo "=== koplugin-dev ===" && \
    echo "KOReader: ${KOREADER_VERSION}" && \
    echo "Go: $(go version)" && \
    echo "golangci-lint: $(golangci-lint --version | head -1)" && \
    echo "busted: $(/usr/local/bin/busted-koreader --version)" && \
    echo "luacheck: $(luacheck --version)" && \
    echo "stylua: $(stylua --version)" && \
    echo "lua-language-server: $(lua-language-server --version)" && \
    echo "qemu-arm: $(qemu-arm --version | head -1)"

CMD ["/bin/bash"]
