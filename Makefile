# WSL Plugin Development Makefile
# Single source of truth for build, test, and development processes

.PHONY: help plugin test clean container deprecated-mingw deprecated-wine
.DEFAULT_GOAL := help

# Configuration
PLUGIN_NAME = wsl-plugin-sample.dll
PLUGIN_SOURCE = plugin.cpp
CONTAINER_IMAGE = wsl-plugin-build:latest

# Import shared container utilities
SHELL := /bin/bash
export BASH_LIB := $(PWD)/lib/container-utils.sh

help: ## Show this help message
	@echo "🔧 WSL Plugin Development Makefile"
	@echo "=================================="
	@echo ""
	@echo "🚀 PRODUCTION TARGETS (Windows Container):"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | grep -v 'deprecated' | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-12s %s\n", $$1, $$2}'
	@echo ""
	@echo "🗑️  DEPRECATED TARGETS (for reference only):"
	@grep -E '^deprecated-[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-12s %s\n", $$1, $$2}'
	@echo ""
	@echo "🔄 DEVELOPMENT WORKFLOW:"
	@echo "  1. make container  # Build Windows container image (one-time setup)"
	@echo "  2. make plugin     # Build the WSL plugin DLL"
	@echo "  3. make test       # Run unit tests"
	@echo "  4. make clean      # Clean build artifacts"
	@echo ""
	@echo "📁 Output: $(PLUGIN_NAME)"
	@echo "🐳 Container: $(CONTAINER_IMAGE)"

container: ## Build Windows container image with MSVC build tools
	@echo "🐳 Building Windows container with MSVC build environment..."
	@./build-in-container.sh -CreateImage
	@echo "✅ Container image '$(CONTAINER_IMAGE)' ready"

plugin: ## Build WSL plugin DLL using Windows container
	@echo "🔨 Building WSL plugin using Windows container..."
	@[ -f "$(BASH_LIB)" ] || (echo "❌ Missing container utilities. Run 'git pull' to get latest version." && exit 1)
	@source "$(BASH_LIB)" && build_plugin_in_container
	@echo "✅ Plugin built: $(PLUGIN_NAME)"
	@[ -f "$(PLUGIN_NAME)" ] && echo "📊 Size: $$(stat -c%s $(PLUGIN_NAME)) bytes" || echo "⚠️  Plugin file not found in working directory"

test: ## Run unit tests using Windows container
	@echo "🧪 Running unit tests using Windows container..."
	@[ -f "$(BASH_LIB)" ] || (echo "❌ Missing container utilities. Run 'git pull' to get latest version." && exit 1)
	@source "$(BASH_LIB)" && build_and_run_tests_in_container

integration-test: plugin ## Run integration tests (NixOS framework) 
	@echo "🔬 Running integration tests using NixOS framework..."
	@[ -f "$(PLUGIN_NAME)" ] || (echo "❌ Plugin not found. Run 'make plugin' first." && exit 1)
	@echo "🔍 Running NixOS test framework..."
	nix-build simple-plugin-test.nix --max-jobs 1 | tail -10
	@echo "✅ Integration tests completed"

clean: ## Clean all build artifacts
	@echo "🧹 Cleaning build artifacts..."
	rm -f $(PLUGIN_NAME) *.dll *.exe *.lib *.exp *.pdb
	rm -rf build/ test-build/ temp_include/
	rm -f packages/.restored
	rm -f result*
	@echo "✅ Clean completed"

deep-clean: clean ## Clean everything including container sync
	@echo "🧹 Deep cleaning including Windows sync directory..."
	@source "$(BASH_LIB)" 2>/dev/null && { \
		WIN_PATH=$$(wsl_to_windows_sync_path .); \
		WIN_PATH_WSL=$$(wslpath "$$WIN_PATH"); \
		if [ -d "$$WIN_PATH_WSL" ]; then \
			echo "🗑️  Removing Windows sync directory: $$WIN_PATH_WSL"; \
			rm -rf "$$WIN_PATH_WSL"; \
		fi; \
	} || echo "ℹ️  Skipping Windows sync cleanup (utilities not available)"
	@echo "✅ Deep clean completed"

install: plugin ## Show installation instructions
	@echo "📋 WSL Plugin Installation Guide"
	@echo "==============================="
	@echo ""
	@[ -f "$(PLUGIN_NAME)" ] || (echo "❌ Plugin not found. Run 'make plugin' first." && exit 1)
	@echo "✅ Plugin ready: $(PLUGIN_NAME)"
	@echo "📊 Size: $$(stat -c%s $(PLUGIN_NAME)) bytes"
	@echo "🔍 Type: $$(file $(PLUGIN_NAME))"
	@echo ""
	@echo "🚀 Installation steps:"
	@echo "  1. Copy $(PLUGIN_NAME) to Windows WSL plugin directory"
	@echo "  2. Register plugin with WSL service (requires admin privileges)"
	@echo "  3. Create plugin configuration file"
	@echo "  4. Restart WSL to load plugin"
	@echo ""
	@echo "📝 Plugin will log to: C:\\wsl-plugin-nixos.txt"
	@echo "📖 See integration test files for configuration examples"

# ==============================================================================
# DEPRECATED TARGETS - Kept for historical reference
# These approaches have been thoroughly tested and are not viable for production
# ==============================================================================

deprecated-mingw: ## 🗑️ DEPRECATED: MinGW cross-compilation (missing essential APIs)
	@echo "⚠️  WARNING: This target is DEPRECATED and not suitable for production"
	@echo "    Missing APIs: AF_HYPERV sockets, WMI interfaces, VirtDisk API"
	@echo "    Use 'make plugin' for production builds"
	@echo ""
	@echo "🔨 Building with MinGW (limited functionality)..."
	@command -v x86_64-w64-mingw32-g++ >/dev/null || (echo "❌ MinGW not found. Use 'nix develop \".#mingw\"'" && exit 1)
	@mkdir -p temp_include
	@echo '#include <windows.h>' > temp_include/Windows.h
	x86_64-w64-mingw32-g++ -std=c++14 -shared \
	  -Itemp_include \
	  -Ipackages/Microsoft.WSL.PluginApi.2.1.3/build/native/include \
	  -o $(PLUGIN_NAME) $(PLUGIN_SOURCE) \
	  -lws2_32 -lkernel32 -luser32
	@rm -rf temp_include
	@echo "⚠️  Plugin built with MinGW (DEPRECATED - limited functionality)"
	@echo "📊 Size: $$(stat -c%s $(PLUGIN_NAME)) bytes"

deprecated-wine: ## 🗑️ DEPRECATED: Wine + VS Build Tools (incompatible)
	@echo "⚠️  WARNING: This target is DEPRECATED and does not work"
	@echo "    Wine 10.0 is incompatible with Visual Studio Build Tools 2022"
	@echo "    Missing Windows NT APIs cause consistent installer failures"
	@echo "    Use 'make plugin' for production builds"
	@echo ""
	@echo "❌ Wine approach is not implemented (architectural impossibility)"
	@echo "📖 See WINE_VS_COMPAT.md for detailed analysis of why this fails"

# Legacy targets for backwards compatibility
build: plugin ## Alias for 'plugin' target
test-old: integration-test ## Alias for 'integration-test' target