# Makefile for <PLUGIN_NAME>.koplugin
#
# This Makefile uses shared targets from koplugin-dev.
# Build the base image first: cd /path/to/koplugin-dev && make docker-build

PLUGIN_NAME := <PLUGIN_NAME>

# Path to koplugin-dev (for building the Docker image)
# Set this to wherever you cloned koplugin-dev
KOPLUGIN_DEV_DIR ?= $(HOME)/dev/projects/koplugin-dev

# Include shared targets
include /opt/koplugin-dev/shared.mk

# =============================================================================
# Plugin-specific targets (add your own below)
# =============================================================================

.PHONY: build
build: ## Build the plugin zip
	./build.sh
