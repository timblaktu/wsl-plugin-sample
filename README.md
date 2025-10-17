# WSL Plugin Sample for NixOS Development

A streamlined development environment for building and testing Windows Subsystem for Linux (WSL) plugins using NixOS, with a focus on contributing to NixOS-WSL.

## 🎯 Project Goals

This repository demonstrates a complete development-to-test pipeline for WSL plugins, specifically designed for:

1. **Custom WSL Plugin Development** - Modify and extend WSL functionality
2. **NixOS-WSL Contribution Testing** - Validate changes before submitting to NixOS-WSL  
3. **Automated Testing Infrastructure** - Ensure plugin compatibility and functionality
4. **Reproducible Development Environment** - Consistent builds across different systems

## 🚀 Quick Start

```bash
# Clone the repository
git clone <repository-url>
cd wsl-plugin-sample

# Enter the development environment  
nix develop

# Show all available targets
make help

# Build the plugin
make plugin

# Run tests
make test
```

## 🔧 Development Environment

### Single Optimized Environment

```bash
nix develop    # Default MinGW cross-compilation environment
```

**Features:**
- ✅ **Proven working solution** with WSL Plugin API
- ✅ **Pure Nix cross-compilation** (no Wine required)
- ✅ **Fast builds** (~5-10 seconds)
- ✅ **Embedded Makefile** for all build processes
- ✅ **Fully reproducible** across systems

**Note:** Wine-based development (`nix develop '.#wine'`) is deprecated due to VS 2022 compatibility issues.

## 🛠️ Makefile Targets

All development tasks are managed through the embedded Makefile:

```bash
make help      # Show all available targets
make plugin    # Build the WSL plugin DLL
make install   # Prepare for deployment
make test      # Run automated tests
make clean     # Clean build artifacts
```

### Example Workflow

```bash
# 1. Enter development environment
nix develop

# 2. Build the plugin
make plugin

# 3. Run tests
make test

# 4. Prepare for installation
make install
```

## 📁 Project Structure

- `plugin.cpp` - Main plugin implementation with custom modifications
- `packages.config` - NuGet package dependencies (WSL Plugin API)
- `flake.nix` - Nix development environment and embedded Makefile
- `Makefile` - Auto-generated build automation (single source of truth)
- `simple-plugin-test.nix` - NixOS test framework
- `WSL-PLUGIN-DEVELOPMENT-WORKFLOW.md` - Complete development guide

## 🧪 Custom Plugin Features

This sample includes custom modifications demonstrating:

- **Enhanced VM Startup**: Custom hostname detection and logging
- **Distribution Recognition**: Special handling for NixOS-WSL, Ubuntu, etc.
- **Improved Logging**: Clear custom markers in plugin output
- **Error Handling**: Robust socket communication and cleanup

## 🚀 Plugin Installation

Use the Makefile for deployment preparation:

```bash
make install    # Shows deployment instructions and plugin info
```

Output includes:
- Plugin file path and size
- Installation instructions for WSL
- Log file location (`C:\wsl-plugin-demo.txt`)

## 🔧 Troubleshooting

### Build Issues
```bash
make clean     # Clean all artifacts
make plugin    # Rebuild and verify
make test      # Run tests to validate
```

### Common Problems
- **Missing plugin.dll**: Run `make plugin` first
- **Test failures**: Ensure NixOS test framework is available
- **Wine environment**: Use default environment instead (`nix develop`)

## 🏗️ Architecture

### Key Features
- **Embedded Makefile**: Single source of truth for all build processes
- **MinGW Cross-Compilation**: Pure Nix solution, no Wine required
- **Automated Testing**: NixOS test framework validates functionality
- **Reproducible Builds**: Consistent results across systems

### Wine Environment (Deprecated)
The Wine-based environment (`nix develop '.#wine'`) is preserved for reference but deprecated due to:
- Wine 10.0 incompatibility with VS 2022 Build Tools
- Missing Windows API implementations
- Consistent installation failures

Use the default MinGW environment for reliable development.

## Contributing

This project welcomes contributions and suggestions.  Most contributions require you to agree to a
Contributor License Agreement (CLA) declaring that you have the right to, and actually do, grant us
the rights to use your contribution. For details, visit https://cla.opensource.microsoft.com.

When you submit a pull request, a CLA bot will automatically determine whether you need to provide
a CLA and decorate the PR appropriately (e.g., status check, comment). Simply follow the instructions
provided by the bot. You will only need to do this once across all repos using our CLA.

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).
For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or
contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.

## Trademarks

This project may contain trademarks or logos for projects, products, or services. Authorized use of Microsoft 
trademarks or logos is subject to and must follow 
[Microsoft's Trademark & Brand Guidelines](https://www.microsoft.com/en-us/legal/intellectualproperty/trademarks/usage/general).
Use of Microsoft trademarks or logos in modified versions of this project must not cause confusion or imply Microsoft sponsorship.
Any use of third-party trademarks or logos are subject to those third-party's policies.
