--- commonrequire.lua
-- Shared bootstrap for running busted tests inside a real KOReader environment.
--
-- Ported from KOReader's spec/unit/commonrequire.lua. This file is loaded
-- by busted via `--helper` and sets up the headless KOReader environment:
--   - Real KOReader modules (no mocks)
--   - einkfb.dummy = true → framebuffer skips SDL window
--   - Input.dummy = true → no input device polling
--   - Isolated G_reader_settings and G_defaults in temp files
--
-- This runs INSIDE KOReader's bundled LuaJIT, so all native FFI libs
-- (OpenSSL, zstd, sqlite, etc.) are available for real.
--
-- Environment variables:
--   PLUGIN_PATH  — path to the plugin under test (default: /opt/plugin)
--   TEST_DATA_DIR — temp directory for test data (default: /tmp/koreader-test-data)

-- =============================================================================
-- Package paths for KOReader modules
-- =============================================================================
package.path =
    "common/?.lua;frontend/?.lua;" ..
    package.path
package.cpath =
    "common/?.so;common/?.dll;/usr/lib/lua/?.so;" ..
    package.cpath

-- Set up ffi.load override for native library discovery
require("ffi/loadlib")

-- =============================================================================
-- Quiet the logs
-- =============================================================================
require("dbg"):turnOff()
local logger = require("logger")
logger:setLevel(logger.levels.warn)

-- =============================================================================
-- Isolated test data directory
-- =============================================================================
local test_data_dir = os.getenv("TEST_DATA_DIR") or "/tmp/koreader-test-data"
os.execute("mkdir -p " .. test_data_dir)

-- Override os.getenv to redirect KO_HOME to our test directory
os.getenv = (function()
    local orig = os.getenv
    local overrides = {
        KO_HOME = test_data_dir,
    }
    return function(key)
        if overrides[key] ~= nil then
            return overrides[key]
        end
        return orig(key)
    end
end)()

-- Re-init datastorage after setting KO_HOME
package.loaded["datastorage"] = nil
local DataStorage = require("datastorage")

-- =============================================================================
-- Isolated settings files
-- =============================================================================
local data_dir = DataStorage:getDataDir()

-- Global defaults (isolated)
os.remove(data_dir .. "/defaults.tests.lua")
os.remove(data_dir .. "/defaults.tests.lua.old")
G_defaults = require("luadefaults"):open(data_dir .. "/defaults.tests.lua")

-- Global reader settings (isolated)
os.remove(data_dir .. "/settings.tests.lua")
os.remove(data_dir .. "/settings.tests.lua.old")
G_reader_settings = require("luasettings"):open(data_dir .. "/settings.tests.lua")

-- =============================================================================
-- Headless device setup
-- =============================================================================

-- Headless framebuffer — no SDL window creation
einkfb = require("ffi/framebuffer") -- luacheck: ignore
einkfb.dummy = true                 -- luacheck: ignore

local Device = require("device")

-- Init output device (dummy screen)
local Screen = Device.screen
Screen:init()

local CanvasContext = require("document/canvascontext")
CanvasContext:init(Device)

-- Init input device (headless)
local Input = Device.input
Input.dummy = true

-- =============================================================================
-- Module helpers (from KOReader's commonrequire)
-- =============================================================================

--- Unload a module from package.loaded and _G
-- @param module Module name string
-- @return true if unloaded, false otherwise
function package.unload(module) -- luacheck: ignore
    if type(module) ~= "string" then return false end
    package.loaded[module] = nil
    _G[module] = nil
    return true
end

--- Replace a module in package.loaded
-- @param name Module name
-- @param module The module table to install
-- @return true if replaced
function package.replace(name, module) -- luacheck: ignore
    if type(name) ~= "string" then return false end
    assert(package.unload(name))
    package.loaded[name] = module
    return true
end

--- Reload a module (unload + require)
-- @param name Module name
-- @return The reloaded module
function package.reload(name) -- luacheck: ignore
    if type(name) ~= "string" then return false end
    assert(package.unload(name))
    return require(name)
end

-- =============================================================================
-- Plugin testing helpers
-- =============================================================================

--- Load a specific KOReader plugin by name.
-- Useful for testing plugin interaction with real KOReader infrastructure.
-- @param name Plugin name, with or without .koplugin suffix
function load_plugin(name) -- luacheck: ignore
    local PluginLoader = require("pluginloader")
    local t = PluginLoader:_discover()
    -- Normalize: ensure .koplugin suffix for comparison
    local full_name = name:find("%.koplugin$") and name or (name .. ".koplugin")
    local short_name = name:gsub("%.koplugin$", "")
    for _, v in ipairs(t) do
        if v.name == full_name or v.name == short_name then
            PluginLoader:_load({ v })
            return
        end
    end
    error("Plugin not found: " .. name)
end

--- Fast-forward all scheduled UI tasks and run the input loop once.
-- Essential for testing async/UI code without blocking.
function fastforward_ui_events() -- luacheck: ignore
    local UIManager = require("ui/uimanager")
    UIManager:shiftScheduledTasksBy(-1e9)
    UIManager:setInputTimeout(0)
    UIManager:handleInput()
end

--- Disable all plugins for isolated testing.
-- Call this before load_plugin() to ensure only your plugin is loaded.
function disable_plugins() -- luacheck: ignore
    local PluginLoader = require("pluginloader")
    PluginLoader.enabled_plugins = {}
    PluginLoader.disabled_plugins = {}
    PluginLoader.loaded_plugins = {}
end

--- Get the test data directory path
-- @return string Path to isolated test data directory
function get_test_data_dir() -- luacheck: ignore
    return test_data_dir
end

--- Get the plugin path
-- @return string Path to the plugin under test
function get_plugin_path() -- luacheck: ignore
    return os.getenv("PLUGIN_PATH") or "/opt/plugin"
end

-- =============================================================================
-- Plugin package path setup
-- =============================================================================
local plugin_path = get_plugin_path()

-- Add plugin source to package.path
-- Plugins can have their own dependencies/ subdirectory
package.path = plugin_path .. "/?.lua;" ..
               plugin_path .. "/dependencies/?.lua;" ..
               plugin_path .. "/src/?.lua;" ..
               plugin_path .. "/lua/?.lua;" ..
               package.path

-- Export for specs
_G.TEST_DATA_DIR = test_data_dir -- luacheck: ignore
_G.PLUGIN_PATH = plugin_path     -- luacheck: ignore

-- =============================================================================
-- Startup banner
-- =============================================================================
print(string.format("[koplugin-dev] KOReader %s (headless)  Device: %s  Screen: %dx%d",
    require("version"):getCurrentRevision(),
    tostring(Device.model),
    Screen:getWidth(), Screen:getHeight()))
print(string.format("[koplugin-dev] Data dir: %s", data_dir))
print(string.format("[koplugin-dev] Plugin path: %s", plugin_path))
