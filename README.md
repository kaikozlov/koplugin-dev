# koplugin-dev

Development environment for KOReader plugins. One Docker image with everything you need:

- **KOReader Linux release** — real runtime for testing (not mocks)
- **Go toolchain** — build, test, lint, format
- **Lua toolchain** — busted, luacheck, stylua, lua-language-server
- **Build essentials** — gcc, make
- **CLI tools** — rg, fd, jq, gh

## Quick Start

```bash
# Build the base image (once per KOReader version)
cd koplugin-dev
make docker-build

# Use it in your plugin
cd ../myplugin.koplugin
make test      # runs busted against real KOReader
make lint      # luacheck + golangci-lint
make shell     # drop into the container
```

## Using in Your Plugin

### 1. Create a Makefile

```makefile
# Makefile
PLUGIN_NAME := myplugin
KOPLUGIN_DEV_DIR := $(HOME)/dev/projects/koplugin-dev
include /opt/koplugin-dev/shared.mk
```

The shared targets give you:

| Target | What it does |
|--------|-------------|
| `test` | Run Lua tests (excludes e2e) |
| `test-all` | Run all Lua tests |
| `test-go` | Run Go tests |
| `lint` | Run luacheck + golangci-lint |
| `fmt` | Format Lua + Go |
| `build-go-arm` | Cross-compile for Kindle/Kobo |
| `shell` | Interactive bash in container |

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

The image is tagged by KOReader version:

```bash
# Build for specific version
make docker-build KOREADER_VERSION=v2026.03

# Results in: koplugin-dev:v2026.03
```

When KOReader releases a new version:

1. Update `KOREADER_VERSION` in this repo's Makefile
2. Run `make docker-rebuild`
3. Update plugin Makefiles to use the new version

## What's Inside

| Tool | Version | Purpose |
|------|---------|---------|
| Ubuntu | 24.04 | Base OS |
| KOReader | v2026.03 | Real runtime for testing |
| Go | 1.24.2 | Build Go-based plugins |
| golangci-lint | 1.64.5 | Go linting |
| busted | apt | Lua testing |
| luacheck | apt | Lua linting |
| stylua | 2.0.2 | Lua formatting |
| lua-language-server | 3.13.5 | Editor support |

## Architecture

```
koplugin-dev/
├── Dockerfile           # The one image
├── commonrequire.lua    # Shared busted bootstrap
├── shared.mk            # Shared Makefile targets
├── templates/
│   ├── devcontainer.json
│   ├── Makefile
│   └── .luarc.json
└── README.md
```

In the container:

```
/opt/
├── lib/koreader/        # KOReader installation
├── koplugin-dev/        # Shared infrastructure
│   ├── commonrequire.lua
│   └── shared.mk
├── plugin/              # Your plugin (bind-mounted)
└── lua-language-server/ # LSP server
```

## Tested With

- `acsm.koplugin` — pure Lua plugin
- `localsend.koplugin` — Go + Lua
- `kindle.koplugin` — Go + Lua

All three use the same base image with no custom extensions.
