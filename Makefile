# WSL Plugin Development Makefile
# Single source of truth for build, test, and development processes

.PHONY: help plugin install test clean plugin-windows plugin-mingw
.DEFAULT_GOAL := help

# Configuration
PLUGIN_NAME = plugin.dll
PLUGIN_SOURCE = plugin.cpp

# Detect environment and set default build method
ifeq ($(shell command -v build-windows-plugin 2>/dev/null),)
    # MinGW environment
    BUILD_METHOD := mingw
    ENVIRONMENT := MinGW cross-compilation
else
    # Windows container environment  
    BUILD_METHOD := windows
    ENVIRONMENT := Windows Container (full SDK)
endif

help: ## Show this help message
	@echo "🔧 WSL Plugin Development Makefile"
	@echo "=================================="
	@echo ""
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-10s %s\n", $$1, $$2}'
	@echo ""
	@echo "Development workflow:"
	@echo "  1. make plugin    # Build the WSL plugin (auto-detect method)"
	@echo "  2. make test      # Run automated tests"
	@echo "  3. make install   # Prepare for deployment"
	@echo "  4. make clean     # Clean build artifacts"
	@echo ""
	@echo "Build methods:"
	@echo "  plugin-windows    # Build with Windows Container (full SDK APIs)"
	@echo "  plugin-mingw      # Build with MinGW (limited APIs)"
	@echo ""
	@echo "Active environment: $(ENVIRONMENT)"
	@echo "Default build method: $(BUILD_METHOD)"
	@echo "📁 Output: $(PLUGIN_NAME)"

plugin: ## Build the WSL plugin DLL (auto-detect method)
ifeq ($(BUILD_METHOD),windows)
	@$(MAKE) plugin-windows
else
	@$(MAKE) plugin-mingw
endif

plugin-windows: ## Build with Windows Container (full Windows SDK APIs)
	@echo "🐳 Building WSL Plugin with Windows Container (full SDK APIs)..."
	@command -v build-windows-plugin >/dev/null || (echo "❌ build-windows-plugin not found. Use 'nix develop' (default shell)" && exit 1)
	build-windows-plugin
	@echo "✅ Plugin built with full Windows SDK support"

plugin-mingw: packages/.restored ## Build with MinGW (limited APIs - testing only)
	@echo "🔨 Building WSL Plugin with MinGW (limited APIs)..."
	@echo "⚠️  WARNING: This build has limited functionality"
	@echo "    Missing: AF_HYPERV sockets, WMI interfaces, VirtDisk API"
	@echo "    For production use: make plugin-windows"
	@echo ""
	@command -v x86_64-w64-mingw32-g++ >/dev/null || (echo "❌ MinGW not found. Use 'nix develop \".#mingw\"'" && exit 1)
	@mkdir -p temp_include
	@echo '#include <windows.h>' > temp_include/Windows.h
	x86_64-w64-mingw32-g++ -std=c++14 -shared \
	  -Itemp_include \
	  -Ipackages/Microsoft.WSL.PluginApi.2.1.3/build/native/include \
	  -o $(PLUGIN_NAME) $(PLUGIN_SOURCE) \
	  -lws2_32 -lkernel32 -luser32
	@rm -rf temp_include
	@echo "✅ Plugin built (MinGW - limited functionality)"
	@echo "📊 Size: $$(stat -c%s $(PLUGIN_NAME)) bytes"

packages/.restored: packages.config ## Restore NuGet packages
	@echo "📦 Restoring NuGet packages..."
	nuget restore packages.config -PackagesDirectory ./packages
	@touch packages/.restored
	@echo "✅ NuGet packages restored"

install: $(PLUGIN_NAME) ## Prepare plugin for installation
	@echo "📋 Plugin ready for installation:"
	@echo "  File: $(PLUGIN_NAME)"
	@echo "  Size: $$(stat -c%s $(PLUGIN_NAME)) bytes"
	@echo "  Type: $$(file $(PLUGIN_NAME))"
	@echo ""
	@echo "🚀 To install in WSL:"
	@echo "  1. Copy $(PLUGIN_NAME) to Windows WSL plugin directory"
	@echo "  2. Register plugin with WSL service"
	@echo "  3. Restart WSL to load plugin"
	@echo ""
	@echo "📝 Plugin log output will be in: C:\\wsl-plugin-demo.txt"

test: $(PLUGIN_NAME) ## Run automated tests
	@echo "🧪 Running WSL Plugin Tests..."
	@if [ ! -f $(PLUGIN_NAME) ]; then echo "❌ Plugin not found. Run 'make plugin' first."; exit 1; fi
	@echo "✅ Plugin file exists: $(PLUGIN_NAME)"
	@echo "🔍 Running NixOS test framework..."
	nix-build simple-plugin-test.nix --max-jobs 1 | tail -10
	@echo "✅ All tests completed"

clean: ## Clean build artifacts
	@echo "🧹 Cleaning build artifacts..."
	rm -f $(PLUGIN_NAME)
	rm -rf temp_include
	rm -f packages/.restored
	rm -f result*
	@echo "✅ Clean completed"
