# koplugin-dev

Development environment for KOReader plugins. One Docker image with everything you need:

- **KOReader Linux release** — real runtime for testing (not mocks)
- **Go toolchain** — build, test, lint, format
- **Lua toolchain** — busted, luacheck, stylua, lua-language-server
- **Build essentials** — compiler/toolchain support for native deps
- **CLI tools** — rg, fd, jq, gh, qemu-arm, just, gettext

## Quick Start

Plugins **vendor** `shared.just` into the repo under `just/shared.just`
(committed) and pin a published GHCR image. Contributors only need Docker +
`just` — no sibling clone of this repo. Use `just/` rather than `vendor/` so
Go does not treat it as a module vendor tree.

```bash
cd myplugin.koplugin
just setup     # install git hooks + pull the image
just test      # quiet by default; V=1 for full output
just check     # format (mutating) + lint + test
just shell
```

## Using in Your Plugin

### 1. Create a justfile and vendor shared recipes

```bash
mkdir -p just
curl -fsSL https://raw.githubusercontent.com/kaikozlov/koplugin-dev/main/shared.just \
  -o just/shared.just
```

```just
# justfile
plugin_name := "myplugin"
koplugin_dev_version := "v2026.07_1"
koplugin_dev_ref := env("KOPLUGIN_DEV_REF", "main")
plugin_path := "/opt/plugin"       # nested Lua plugins: "/opt/plugin/lua"
spec_dir := "spec"                 # nested: "lua/spec"
lua_paths := "."                   # stylua/luacheck paths under /opt/plugin
has_go := "0"                      # "1" for Go+Lua plugins
go_integration_packages := ""      # package patterns and optional selection flags
exclude_tags := "e2e"

import "./just/shared.just"

# Refresh recipes from upstream (then commit just/shared.just):
sync-shared:
    #!/usr/bin/env bash
    set -euo pipefail
    ref="{{ koplugin_dev_ref }}"
    mkdir -p just
    tmp="$(mktemp)"
    curl -fsSL "https://raw.githubusercontent.com/kaikozlov/koplugin-dev/${ref}/shared.just" -o "$tmp"
    {
        echo "# Vendored from https://github.com/kaikozlov/koplugin-dev"
        echo "# Ref: ${ref}"
        echo "# Refresh with: just sync-shared"
        echo
        cat "$tmp"
    } > just/shared.just
    rm -f "$tmp"

# Product-specific recipes (packaging, etc.) go below.
```

Or copy `templates/justfile` and run `just sync-shared` once.

The shared recipes give you:

| Recipe | What it does |
|--------|-------------|
| `setup` | Install `.githooks` + `docker pull` GHCR image |
| `pull-image` | Pull the pinned image without changing Git configuration |
| `test` | Lua tests (excludes e2e); Go `-race` when `has_go=1` |
| `test-filter` | Filtered Lua tests |
| `test-e2e` / `test-all` | Network tests (`--network=host`) |
| `test-go` / `test-go-race` / `test-go-integration` | Go tests |
| `lint` / `fmt` / `fmt-check` | One-container aggregates |
| `check` | Mutating fmt + lint + test pass |
| `build-go` / `build-go-arm` | Go builds |
| `shell` / `lua` | Interactive container |

Quiet by default. Use `V=1 just test` for full busted/go output.

### One-container aggregate recipes

Every top-level shared recipe launches one fresh container. A plugin can compose
several recipes into a larger aggregate without nesting additional containers by
re-entering its justfile through the private `_reenter` command:

```just
# One host `docker run`; verify-static and test execute inside it.
verify:
    {{ _run }} {{ _reenter }} _verify

[private]
_verify: verify-static test
```

`_reenter` sets the internal `KOPLUGIN_DEV_IN_CONTAINER=1` marker and preserves
the image's `/opt/lib/koreader` working directory for native-library discovery.
While that marker is present, `_run`, `_run_network`, and `_run_it` become empty
prefixes, so the normal Just dependency graph and failure behavior are preserved
inside the existing container. Use a separate top-level invocation for recipes that
need different Docker settings, such as host networking or an interactive TTY.

Optional image override (local build instead of GHCR):

```bash
# Requires a local koplugin-dev checkout (or KOPLUGIN_DEV_DIR):
just docker-build
IMAGE_NAME=koplugin-dev:v2026.07 just test
```

### 2. Keeping `just/shared.just` up to date

`shared.just` lives in this repo. Plugins commit a copy under `just/`.

When recipes change here:

1. Merge/push to `koplugin-dev`
2. In each plugin: `just sync-shared` (optional: `KOPLUGIN_DEV_REF=<sha> just sync-shared`)
3. Commit the updated `just/shared.just`

Image pin (`koplugin_dev_version`) and recipe sync (`koplugin_dev_ref`) are
independent — bump the image when GHCR publishes a new `_N` tag; sync recipes
whenever `shared.just` changes.

### 3. CI

Normal single-repo checkout is enough (vendored file is in the tree):

```yaml
steps:
  - uses: actions/checkout@v7
  - run: # install just
  - run: just pull-image
  - run: just fmt-check
  - run: just lint
  - run: just test
```

### 4. Git hooks

Keep pre-commit fast and read-only (`just fmt-check`, then `just lint`), and run
`just test` from `.githooks/pre-push`. This preserves the full local safety net
without auto-formatting unrelated or partially staged work. `just setup` makes
all checked-in files under `.githooks/` executable and points `core.hooksPath`
at that directory.

### 5. Devcontainer / .luarc.json (optional)

```bash
mkdir -p .devcontainer
cp /path/to/koplugin-dev/templates/devcontainer.json .devcontainer/
cp /path/to/koplugin-dev/templates/.luarc.json .
```

## Writing Tests

Tests run via `busted-koreader` which uses KOReader's bundled LuaJIT. The `commonrequire.lua` helper sets up the headless environment.

```lua
-- spec/myfeature_spec.lua
describe("My feature", function()
    it("does something", function()
        local UIManager = require("ui/uimanager")
        assert.is.truthy(UIManager)
    end)

    it("loads the plugin", function()
        disable_plugins()
        load_plugin("myplugin")
    end)
end)
```

### Available test helpers

From `commonrequire.lua`:

| Function | Purpose |
|----------|---------|
| `load_plugin(name)` | Load a plugin via PluginLoader |
| `disable_plugins()` | Clear all plugins before selective loading |
| `fastforward_ui_events()` | Run scheduled UI tasks immediately |
| `get_test_data_dir()` | Path to isolated temp directory |
| `get_plugin_path()` | Path to plugin under test |

### Test isolation

- Settings are isolated to `/tmp/koreader-test-data`
- Each test run gets fresh `G_reader_settings` and `G_defaults`
- Screen and input are headless (no SDL window)

## Image Versioning

Published images use `v{KOREADER_VERSION}_{N}` tags on GHCR, e.g.
`ghcr.io/kaikozlov/koplugin-dev:v2026.07_1`. Bump `koplugin_dev_version` in
each plugin justfile when the image updates.

Local builds (optional) derive the tag from `ARG KOREADER_VERSION` in the
Dockerfile (no `_N` suffix):

```bash
cd koplugin-dev
just docker-build   # builds koplugin-dev:v2026.07
IMAGE_NAME=koplugin-dev:v2026.07 just test
```

## What's Inside

| Tool | Version | Purpose |
|------|---------|---------|
| Ubuntu | 26.04 | Base OS |
| KOReader | v2026.07 | Real runtime for testing |
| Go | 1.26.5 | Build Go-based plugins |
| golangci-lint | 2.12.2 | Go linting |
| busted | apt | Lua testing |
| luacheck | apt | Lua linting |
| stylua | 2.5.2 | Lua formatting |
| lua-language-server | 3.18.2 | Editor support |
| QEMU user mode | apt | Legacy ARM compatibility testing |

## Architecture

```
koplugin-dev/
├── Dockerfile           # The one image
├── justfile             # Recipes for this repo
├── commonrequire.lua    # Shared busted bootstrap
├── shared.just          # Shared plugin recipes (vendored by consumers)
├── templates/
│   ├── devcontainer.json
│   ├── justfile
│   └── .luarc.json
└── README.md
```

In the container:

```
/opt/
├── lib/koreader/        # KOReader installation
├── koplugin-dev/        # Shared infrastructure
│   ├── commonrequire.lua
│   └── shared.just
├── plugin/              # Your plugin (bind-mounted)
└── lua-language-server/ # LSP server
```

## Tested With

- `acsm.koplugin` — pure Lua plugin
- `localsend.koplugin` — Go + Lua
- `kindle.koplugin` — Go + Lua

All three use the same base image with no custom extensions.
