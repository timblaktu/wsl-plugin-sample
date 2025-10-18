# WSL Plugin Development & Testing Workflow

## Overview

This document describes the complete development-to-test pipeline for WSL plugins using NixOS, specifically focused on developing custom functionality and testing it in isolation before contributing to NixOS-WSL.

## Development Environment Setup

### Prerequisites

- NixOS or Nix package manager
- This repository cloned locally
- Access to Windows system for final WSL testing (optional for development)

### Quick Start

```bash
cd ~/src/wsl-plugin-sample
nix develop    # Enter development environment
make help      # Show all available targets
make plugin    # Build your first plugin
```

## 🔧 Development Workflow

### 1. Environment Setup

The project uses a single, optimized development environment:

```bash
# Default MinGW cross-compilation environment
nix develop
```

**Note**: Wine-based development is deprecated due to VS 2022 compatibility issues. Use `nix develop '.#wine'` only for reference.

### 2. Plugin Development

#### Source Code Structure

- `plugin.cpp` - Main plugin implementation
- `packages.config` - NuGet package dependencies (WSL Plugin API)
- `flake.nix` - Nix development environment and embedded Makefile
- `Makefile` - Single source of truth for all build processes (auto-generated)

#### Making Changes

1. **Enter development environment**: `nix develop`
2. **Edit the plugin source** (`plugin.cpp`)
3. **Build the plugin**: `make plugin`

#### Example Custom Modifications

The current codebase includes example customizations:

- **VM Start Events**: Custom hostname detection and logging
- **Distribution Detection**: Special handling for NixOS-WSL, Ubuntu, etc.
- **Enhanced Logging**: Clear markers for custom functionality

### 3. Build Process (via Makefile)

All build processes are managed by the embedded Makefile. **Use the Makefile as the single source of truth**:

```bash
make help      # Show all available targets
make plugin    # Build the WSL plugin DLL
make install   # Prepare for deployment
make test      # Run automated tests
make clean     # Clean build artifacts
```

The Makefile automatically handles:
- ✅ NuGet package restoration
- ✅ MinGW cross-compilation setup
- ✅ Windows header generation
- ✅ Plugin verification and validation

### 4. Testing Infrastructure

#### Automated Testing via Makefile

All testing is managed through the Makefile:

```bash
make test    # Run comprehensive plugin tests
```

#### Test Coverage

The automated tests verify:

- ✅ Plugin compilation and structure
- ✅ Custom modifications present in binary
- ✅ System commands used by plugin (hostname, /proc/version)
- ✅ NixOS environment compatibility
- ✅ Plugin file format and dependencies

### 5. Integration Testing (Manual)

For complete end-to-end testing:

1. **Build plugin**: `make plugin`
2. **Prepare for installation**: `make install` (shows deployment instructions)
3. **Deploy to Windows WSL** (follow instructions from `make install`)
4. **Verify functionality** (check `C:\wsl-plugin-demo.txt` for plugin output)

## 🏗️ Architecture Decisions

### Why MinGW Cross-Compilation?

1. **Pure Nix Solution**: No Wine dependency, faster builds
2. **ABI Compatibility**: Proven compatible with WSL Plugin API
3. **Reproducible**: Works consistently across systems
4. **Fast**: No emulation overhead

### Why NixOS Tests?

1. **Automated Verification**: Catches regressions early
2. **Isolated Environment**: Clean testing without system pollution
3. **CI/CD Ready**: Can be integrated into automated pipelines
4. **Comprehensive**: Tests both code and system compatibility

### Development vs Production

- **Development**: Pure MinGW cross-compilation for rapid iteration
- **Testing**: NixOS tests for automated verification
- **Production**: Final testing in actual WSL environment

## 🚀 Contributing to NixOS-WSL

### Preparation Steps

1. **Develop custom functionality** using this workflow
2. **Verify with automated tests** (`nix-build simple-plugin-test.nix`)
3. **Test in isolated NixOS-WSL instance** (optional)
4. **Document changes and test results**

### Integration Workflow

1. **Fork NixOS-WSL repository**
2. **Apply lessons learned** from this development environment
3. **Submit PR with test evidence** from this workflow
4. **Reference this development setup** for reviewer testing

## 📊 Performance & Metrics

### Build Times

- **MinGW Build**: ~5-10 seconds
- **NixOS Test**: ~2-5 minutes (includes VM setup)
- **Full Integration Test**: ~10-20 minutes

### File Sizes

- **plugin.dll**: ~130KB (custom version)
- **NixOS-WSL test instance**: ~200-500MB (minimal)

## 🔍 Troubleshooting

### Common Issues

1. **Missing NuGet packages**: Run `nuget-restore`
2. **Build failures**: Check MinGW environment setup
3. **Test failures**: Verify plugin.dll exists before running tests
4. **Wine issues**: Use MinGW instead (recommended approach)

### Debug Commands

All debugging is handled through the Makefile workflow:

```bash
make clean     # Clean all artifacts
make plugin    # Rebuild and verify plugin
make test      # Run comprehensive tests
```

## 📚 Key Files Reference

### Development Files

- `plugin.cpp` - Plugin source code
- `flake.nix` - Development environment definitions
- `packages.config` - NuGet dependencies

### Testing Files

- `simple-plugin-test.nix` - NixOS test definition
- `wsl-plugin-test.nix` - Alternative flake-based test
- `nixos-wsl-test.nix` - Full NixOS-WSL instance builder

### Documentation

- `README.md` - Project overview
- `WSL-PLUGIN-DEVELOPMENT-WORKFLOW.md` - This document
- `WINE_VS_COMPAT.md` - Wine compatibility research

## 🎯 Success Criteria

A successful development workflow should achieve:

- ✅ **Fast iteration**: Build and test cycles under 30 seconds
- ✅ **Automated verification**: Tests catch issues before manual testing
- ✅ **Isolated testing**: No impact on development system
- ✅ **Reproducible results**: Same results across different systems
- ✅ **Clear documentation**: Easy for other contributors to follow

## 📋 Complete Workflow Checklist

### Development Phase
- [ ] Clone repository and enter development environment: `nix develop`
- [ ] Make plugin modifications in `plugin.cpp`
- [ ] Build plugin: `make plugin`
- [ ] Verify build success and custom functionality

### Testing Phase
- [ ] Run automated tests: `make test`
- [ ] Verify all test components pass
- [ ] Check plugin functionality in isolated environment
- [ ] Document any issues or improvements

### Integration Phase
- [ ] Prepare for deployment: `make install`
- [ ] Follow deployment instructions from install target
- [ ] Submit to NixOS-WSL with test evidence
- [ ] Provide this workflow for reviewer verification

---

**Result**: A complete, tested, and documented WSL plugin development workflow suitable for contributing to NixOS-WSL and other WSL-related projects.