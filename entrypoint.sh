#!/bin/sh
# entrypoint.sh — set up plugin symlink and exec the user's command
#
# Reads PLUGIN_NAME (default: derived from directory name of mounted source)
# and creates the correct symlink in KOReader's plugins directory.
#
# Usage:
#   docker run -e PLUGIN_NAME=acsm -v ./acsm.koplugin:/opt/plugin koplugin-dev busted-koreader ...

set -e

PLUGIN_PATH="${PLUGIN_PATH:-/opt/plugin}"

# Derive plugin name from the mounted directory if not set
if [ -z "$PLUGIN_NAME" ]; then
    # Try reading _meta.lua
    if [ -f "$PLUGIN_PATH/_meta.lua" ]; then
        PLUGIN_NAME=$(grep -o 'name\s*=\s*"[^"]*"' "$PLUGIN_PATH/_meta.lua" | head -1 | sed 's/.*"\(.*\)"/\1/')
    fi
    # Fallback: use the directory basename
    if [ -z "$PLUGIN_NAME" ]; then
        PLUGIN_NAME=$(basename "$PLUGIN_PATH" | sed 's/\.koplugin$//')
    fi
fi

# Create the correctly-named symlink in KOReader's plugins dir
LINK_NAME="${KOREADER_DIR}/plugins/${PLUGIN_NAME}.koplugin"
ln -sf "$PLUGIN_PATH" "$LINK_NAME"

exec "$@"
