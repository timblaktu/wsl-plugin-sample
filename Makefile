# WSL Plugin Development Makefile
# Single source of truth for build, test, and development processes

.PHONY: help plugin install test clean
.DEFAULT_GOAL := plugin

# Configuration
PLUGIN_NAME = plugin.dll
PLUGIN_SOURCE = plugin.cpp
PACKAGES_DIR = packages
TEMP_DIR = temp_include

# MinGW Compiler Configuration
CXX = x86_64-w64-mingw32-g++
CXXFLAGS = -std=c++14 -shared
INCLUDES = -I$(TEMP_DIR) -I$(PACKAGES_DIR)/Microsoft.WSL.PluginApi.2.1.3/build/native/include
LIBS = -lws2_32 -lkernel32 -luser32 -lole32 -loleaut32 -lwbemuuid

help: ## Show this help message
	@echo "🔧 WSL Plugin Development Makefile"
	@echo "=================================="
	@echo ""
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-10s %s\n", $$1, $$2}'
	@echo ""
	@echo "Development workflow:"
	@echo "  1. make           # Build the WSL plugin (default)"
	@echo "  2. make test      # Run automated tests"
	@echo "  3. make install   # Install and register plugin"
	@echo "  4. make clean     # Clean build artifacts"
	@echo ""
	@echo "✅ MinGW cross-compilation environment active"
	@echo "📁 Output: $(PLUGIN_NAME)"

plugin: $(PLUGIN_NAME) ## Build the WSL plugin DLL

$(PLUGIN_NAME): $(PLUGIN_SOURCE) $(PACKAGES_DIR)/.restored
	@echo "🔨 Building WSL Plugin with MinGW..."
	@mkdir -p $(TEMP_DIR)
	@echo '#include <windows.h>' > $(TEMP_DIR)/Windows.h
	$(CXX) $(CXXFLAGS) $(INCLUDES) -o $(PLUGIN_NAME) $(PLUGIN_SOURCE) $(LIBS)
	@rm -rf $(TEMP_DIR)
	@echo "✅ Plugin built successfully: $(PLUGIN_NAME)"
	@echo "📊 Size: $$(stat -c%s $(PLUGIN_NAME)) bytes"
	@echo "🔍 Verifying custom strings..."
	@strings $(PLUGIN_NAME) | grep -i "custom" | head -3 || echo "⚠️  No custom strings found"

$(PACKAGES_DIR)/.restored: packages.config ## Restore NuGet packages
	@echo "📦 Restoring NuGet packages..."
	nuget restore packages.config -PackagesDirectory ./$(PACKAGES_DIR)
	@touch $(PACKAGES_DIR)/.restored
	@echo "✅ NuGet packages restored"

install: $(PLUGIN_NAME) ## Install and register WSL plugin
	@echo "🚀 Installing WSL Plugin..."
	@echo "📋 Plugin info:"
	@echo "  File: $(PLUGIN_NAME)"
	@echo "  Size: $$(stat -c%s $(PLUGIN_NAME)) bytes"
	@echo "  Type: $$(file $(PLUGIN_NAME))"
	@echo ""
	@echo "🔐 Running PowerShell installation script..."
	powershell.exe -ExecutionPolicy Bypass -File "./install-wsl-plugin.ps1" -PluginPath "$$(pwd)/$(PLUGIN_NAME)"
	@echo ""
	@echo "📝 Plugin log output will be in: C:\\wsl-plugin-demo.txt"

test: $(PLUGIN_NAME) ## Run automated tests
	@echo "🧪 Running WSL Plugin Tests..."
	@if [ ! -f $(PLUGIN_NAME) ]; then echo "❌ Plugin not found. Run 'make plugin' first."; exit 1; fi
	@echo "✅ Plugin file exists: $(PLUGIN_NAME)"
	@echo "🔍 Running NixOS test framework..."
	@if ! nix-build simple-plugin-test.nix --max-jobs 1; then \
		echo "❌ Test failed! Check output above for details."; \
		exit 1; \
	fi
	@echo "✅ All tests completed successfully"

clean: ## Clean build artifacts
	@echo "🧹 Cleaning build artifacts..."
	rm -f $(PLUGIN_NAME)
	rm -rf $(TEMP_DIR)
	rm -f $(PACKAGES_DIR)/.restored
	rm -f result*
	@echo "✅ Clean completed"
