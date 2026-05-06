# koplugin-dev: Full development environment for KOReader plugins
#
# Includes:
#   - KOReader Linux release (real runtime for testing)
#   - Go toolchain + golangci-lint
#   - Lua tooling: busted, luacheck, stylua, lua-language-server
#   - Build essentials (gcc, make)
#   - CLI tools (rg, fd, jq, gh)
#
# Usage:
#   docker build --build-arg KOREADER_VERSION=v2026.03 -t koplugin-dev:v2026.03 .
#
# Plugin repos extend this with a thin Dockerfile or use directly via devcontainer.

ARG KOREADER_VERSION=v2026.03
ARG GO_VERSION=1.24.2

FROM ubuntu:24.04

ARG KOREADER_VERSION
ARG GO_VERSION

ENV DEBIAN_FRONTEND=noninteractive

# =============================================================================
# System packages
# =============================================================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Build essentials
    build-essential \
    gcc \
    make \
    pkg-config \
    # KOReader dependencies
    ca-certificates \
    curl \
    xz-utils \
    libc6-dev \
    libssl3t64 \
    # Lua testing (busted + all deps)
    lua-busted \
    lua-check \
    # CLI tools
    ripgrep \
    fd-find \
    jq \
    git \
    unzip \
    # Editor support
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
RUN curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh \
      | sh -s -- -b /usr/local/bin v1.64.5

# =============================================================================
# Lua tooling (not in apt)
# =============================================================================

# stylua (Lua formatter)
COPY --from=johnnymorganz/stylua:2.4.1 /stylua /usr/local/bin/stylua
RUN stylua --version

# lua-language-server
RUN LLS_ARCH=$(dpkg --print-architecture | sed 's/amd64/x64/') && \
    curl -fsSL "https://github.com/LuaLS/lua-language-server/releases/download/3.13.5/lua-language-server-3.13.5-linux-${LLS_ARCH}.tar.gz" \
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
COPY shared.mk /opt/koplugin-dev/shared.mk

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
    echo "lua-language-server: $(lua-language-server --version)"

CMD ["/bin/bash"]
