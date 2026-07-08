# koplugin-dev

Development environment for KOReader plugins. One Docker image with everything you need:

- **KOReader Linux release** — real runtime for testing (not mocks)
- **Go toolchain** — build, test, lint, format
- **Lua toolchain** — busted, luacheck, stylua, lua-language-server
- **Build essentials** — compiler/toolchain support for native deps
- **CLI tools** — rg, fd, jq, gh, just

## Quick Start

```bash
# Build the base image
cd koplugin-dev
just docker-build

# Use it in your plugin
cd ../myplugin.koplugin
just test      # runs busted against real KOReader
just lint      # luacheck + golangci-lint
just shell     # drop into the container
```

## Using in Your Plugin

### 1. Create a justfile

```just
# justfile
plugin_name := "myplugin"

# Update this import path if your plugin repo is not next to koplugin-dev.
import "../koplugin-dev/shared.just"
```

The shared recipes give you:

| Recipe | What it does |
|--------|-------------|
| `test` | Run Lua tests (excludes e2e) |
| `test-all` | Run all Lua tests |
| `test-go` | Run Go tests |
| `lint` | Run luacheck + golangci-lint |
| `fmt` | Format Lua + Go |
| `build-go-arm` | Cross-compile for Kindle/Kobo |
| `shell` | Interactive bash in container |

Optional environment overrides:

```bash
IMAGE_NAME=koplugin-dev:v2026.03 just test
SPEC_DIR=tests just test
EXCLUDE_TAGS='e2e,slow' just test
```

### 2. Set up devcontainer (optional)

Copy `templates/devcontainer.json` to `.devcontainer/devcontainer.json` in your plugin:

```bash
mkdir -p .devcontainer
cp /path/to/koplugin-dev/templates/devcontainer.json .devcontainer/
```

Then open in VS Code/Cursor and select "Reopen in Container".

### 3. Add .luarc.json (optional)

For Lua language server support:

```bash
cp /path/to/koplugin-dev/templates/.luarc.json .
```

## Writing Tests

Tests run via `busted-koreader` which uses KOReader's bundled LuaJIT. The `commonrequire.lua` helper sets up the headless environment.

```lua
-- spec/myfeature_spec.lua
describe("My feature", function()
    it("does something", function()
        -- Real KOReader modules available
        local UIManager = require("ui/uimanager")
        assert.is.truthy(UIManager)
    end)

    it("loads the plugin", function()
        disable_plugins()
        load_plugin("myplugin")
        -- Plugin is now loaded into real PluginLoader
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

The Dockerfile is the source of truth for pinned versions. Update the `ARG` constants at the top of `Dockerfile`, then rebuild:

```bash
just docker-rebuild
```

The default local image tag is derived from `ARG KOREADER_VERSION`:

```bash
# ARG KOREADER_VERSION=v2026.03
just docker-build
# builds: koplugin-dev:v2026.03
```

## What's Inside

| Tool | Version | Purpose |
|------|---------|---------|
| Ubuntu | 26.04 | Base OS |
| KOReader | v2026.03 | Real runtime for testing |
| Go | 1.26.5 | Build Go-based plugins |
| golangci-lint | 2.12.2 | Go linting |
| busted | apt | Lua testing |
| luacheck | apt | Lua linting |
| stylua | 2.5.2 | Lua formatting |
| lua-language-server | 3.18.2 | Editor support |

## Architecture

```
koplugin-dev/
├── Dockerfile           # The one image
├── justfile             # Recipes for this repo
├── commonrequire.lua    # Shared busted bootstrap
├── shared.just          # Shared plugin recipes
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
