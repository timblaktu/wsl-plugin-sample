# Nix Development Environment Quick Reference

## Quick Start

```bash
# Enter Wine development environment
nix develop '.#wine'

# Automated setup (one command does everything)
wine-setup

# Build the plugin  
msbuild-wine wsl-plugin-sample.sln /p:Configuration=Release /p:Platform=x64
```

## Available Commands

### Setup Commands
- **`wine-setup`** - Quick headless setup with VS 2022
- **`wine-setup-advanced`** - Advanced setup with options:
  - `--vs2019` - Use Visual Studio Build Tools 2019
  - `--interactive` - Show installer GUI (requires X11/Wayland)
  - `--clean` - Remove existing Wine prefix first
  - `--help` - Show all options

### Build Commands
- **`msbuild-wine <args>`** - Run MSBuild through Wine
- **`nuget-restore`** - Restore NuGet packages
- **`build-plugin`** - Show comprehensive build help

### Development Shells
- **`nix develop`** - Default shell with multiple toolchains
- **`nix develop '.#wine'`** - Wine + MSVC environment
- **`nix develop '.#mingw'`** - MinGW cross-compilation

## Environment Details

### Wine Configuration
- **Wine Prefix**: `$HOME/.wine-wsl-plugin`
- **Architecture**: 64-bit Windows (win64)
- **Windows Version**: Windows 10 (set automatically)
- **Debug Output**: Disabled (`WINEDEBUG=-all`)

### Pre-downloaded Installers
Both installers are downloaded at nix build time with verified SHA256 hashes:

- **VS Build Tools 2022**: `vs_buildtools.exe` (default)
- **VS Build Tools 2019**: Available via `--vs2019` option

### MSBuild Detection
The `msbuild-wine` command automatically detects MSBuild in these locations:
1. VS 2022 BuildTools (x86)
2. VS 2019 BuildTools (x86)  
3. VS 2022 BuildTools (x64)

## Troubleshooting

### Common Issues

**"MSBuild not found"**
```bash
wine-setup-advanced --clean  # Clean reinstall
```

**".NET Framework installation issues"**
```bash
# Check winetricks cache and network
rm -rf ~/.cache/winetricks
wine-setup-advanced --clean  # Reinstall everything
```

**Wine prefix issues**
```bash
rm -rf ~/.wine-wsl-plugin     # Remove prefix
wine-setup                    # Recreate
```

**Display/GUI errors**
```bash
wine-setup-advanced --interactive  # Use GUI for debugging
```

**Network/hash issues**
```bash
nix flake check              # Validate flake
nix develop --rebuild        # Rebuild environment
```

### Verification Commands

**Check Wine prefix**
```bash
ls ~/.wine-wsl-plugin/drive_c/Program\ Files\ \(x86\)/Microsoft\ Visual\ Studio/
```

**Test MSBuild directly**
```bash
wine ~/.wine-wsl-plugin/drive_c/Program\ Files\ \(x86\)/Microsoft\ Visual\ Studio/2022/BuildTools/MSBuild/Current/Bin/MSBuild.exe -version
```

**Check available commands in shell**
```bash
type wine-setup msbuild-wine nuget-restore build-plugin
```

## Advanced Usage

### Custom Wine Configuration
If you need additional Wine configuration:

```bash
export WINEPREFIX="$HOME/.wine-wsl-plugin"
export WINEARCH=win64

# Add registry keys
wine reg add "HKEY_CURRENT_USER\\Software\\Wine\\DirectInput" /v MouseWarpOverride /d force /f

# Install additional components
wine-setup-advanced --interactive  # Use GUI for complex setups
```

### CI/CD Integration
For automated builds in CI/CD:

```bash
# Non-interactive setup
nix develop '.#wine' --command bash -c "wine-setup && msbuild-wine wsl-plugin-sample.sln /p:Configuration=Release /p:Platform=x64"
```

### Custom Build Scripts
You can wrap the commands in your own scripts:

```bash
#!/usr/bin/env bash
set -e

echo "Setting up build environment..."
nix develop '.#wine' --command wine-setup

echo "Building plugin..."
nix develop '.#wine' --command msbuild-wine wsl-plugin-sample.sln /p:Configuration=Release /p:Platform=x64

echo "Build complete: x64/Release/sample-wsl-plugin.dll"
```

## Why This Approach?

### Benefits over Manual Setup
- **Reproducible**: Same environment on every machine
- **Declarative**: Configuration is code, not manual steps
- **Reliable**: Pre-downloaded installers with verified hashes
- **Fast**: No manual GUI interaction required
- **Automated**: One command sets up everything
- **Version-controlled**: Flake.nix tracks exact tool versions

### Comparison with Traditional Methods

| Method | Setup Time | Reproducibility | Linux Support | Automation |
|--------|------------|-----------------|---------------|------------|
| Visual Studio GUI | 30+ min | Manual | ❌ | ❌ |
| Manual Wine Setup | 45+ min | Manual | ⚠️ | ❌ |
| This Nix Setup | 5-10 min | 100% | ✅ | ✅ |

This approach is particularly valuable for:
- Linux-based development teams
- CI/CD pipelines  
- Cross-platform development workflows
- Teams that value reproducible environments