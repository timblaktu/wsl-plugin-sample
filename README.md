# WSL Plugin Sample

A sample project demonstrating how to create WSL (Windows Subsystem for Linux) plugins using C++. This project supports development on both Windows and Linux environments.

## Development Environments

### 🍷 Linux Development with Nix (Recommended)

For Linux developers who want to build Windows WSL plugins without leaving their Linux environment:

#### Quick Start
```bash
# Enter the Wine-based development environment
nix develop '.#wine'

# One-command setup (downloads, installs, configures everything)
wine-setup

# Build the plugin
msbuild-wine wsl-plugin-sample.sln /p:Configuration=Release /p:Platform=x64
```

#### Features
- **Headless Setup**: No GUI interaction required
- **Pre-downloaded Installers**: Visual Studio Build Tools downloaded at nix build time with verified SHA256 hashes
- **Automated Configuration**: Wine prefix, Windows compatibility, .NET Framework, and MSVC toolchain configured automatically
- **Multiple VS Versions**: Support for Visual Studio Build Tools 2019 and 2022
- **Zero Manual Steps**: Complete automation from clean system to working build environment

#### Advanced Options
```bash
# Show all setup options
wine-setup-advanced --help

# Use VS 2019 instead of 2022
wine-setup-advanced --vs2019

# Interactive installer (requires X11/Wayland)
wine-setup-advanced --interactive

# Clean install (removes existing Wine prefix)
wine-setup-advanced --clean
```

#### Alternative Development Shells
```bash
# Default shell with multiple toolchains
nix develop

# MinGW cross-compilation (experimental)
nix develop '.#mingw'
```

### 🪟 Windows Development (Traditional)

* Build the plugin dll via Visual Studio or msbuild
* Open a visual studio developer command prompt as administrator and sign the plugin via:
`cd path\to\sample-wsl-plugin && powershell .\sign-plugin.ps1 -PluginPath .\x64\Debug\sample-wsl-plugin.dll -Trust`

## Plugin Installation and Testing

* Register the plugin with WSL via:
` reg.exe add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Lxss\Plugins" /v sample-plugin /d path\to\sample-wsl-plugin\x64\Release\sample-wsl-plugin.dll  /t reg_sz

* Restart wslservice to load the plugin:
`sc.exe stop wslservice`

* Once loaded, open `C:\wsl-plugin-demo.txt` to see the plugin output

## Troubleshooting

### Linux/Nix Environment

**Wine Setup Issues:**
- **Permission errors**: Ensure you have write access to `$HOME/.wine-wsl-plugin`
- **Wine installation fails**: Check Wine output for specific errors, try `wine-setup-advanced --clean`
- **.NET Framework installation fails**: Winetricks downloads components automatically; check network connection
- **MSBuild not found**: Run `wine-setup` again to reinstall Visual Studio Build Tools
- **Display errors**: The setup runs headless by default; use `wine-setup-advanced --interactive` for GUI debugging

**Build Issues:**
- **Missing dependencies**: Ensure you're in the correct nix shell: `nix develop '.#wine'`
- **MSVC compiler not found**: Verify VS Build Tools installation with `wine-setup-advanced --clean`
- **Path issues**: Check Wine prefix: `ls ~/.wine-wsl-plugin/drive_c/Program\ Files\ \(x86\)/Microsoft\ Visual\ Studio/`

**General Nix Issues:**
- **Flake errors**: Run `nix flake check` to validate the flake
- **Build cache**: Use `nix develop --rebuild` to rebuild the environment
- **Hash mismatches**: Pre-downloaded installers use fixed hashes; this indicates a network/security issue

### Windows Environment

Common error codes:
* `Wsl/Service/CreateInstance/CreateVm/Plugin/ERROR_MOD_NOT_FOUND` -> The plugin DLL could not be loaded. Check that the plugin registration path is correct
* `Wsl/Service/CreateInstance/CreateVm/Plugin/*` -> The plugin DLL returned an error in WSLPLUGINAPI_ENTRYPOINTV1 or OnVmStarted()
* `Wsl/Service/CreateInstance/CreateVm/Plugin/TRUST_E_NOSIGNATURE` -> The plugin DLL is not signed, or its signature is not trusted by the computer. Validate that you ran `sign-plugin.ps1`
* `Wsl/Service/CreateInstance/Plugin/*` -> The plugin DLL returned an error in OnDistributionStarted()

## Technical Implementation

### Nix Flake Architecture

This project uses a sophisticated Nix flake setup that demonstrates several advanced concepts:

#### Pre-downloaded Build Tools
```nix
vsBuildTools2022 = pkgs.fetchurl {
  url = "https://aka.ms/vs/17/release/vs_buildtools.exe";
  sha256 = "027y1cmhxqhsnnd028kfbd7vcp8gl6mcjz5916sxmvrbg24fy3nr";
};
```
- **Fixed-hash derivations** ensure reproducible builds
- **Build-time downloads** eliminate runtime dependency on Microsoft servers
- **SHA256 verification** guarantees installer integrity

#### Headless Wine Configuration
The setup scripts demonstrate programmatic Wine configuration:
- **Registry modification** via `wine reg add` for Windows version setting
- **Environment variables** (`WINEDEBUG=-all`, `DISPLAY=""`) for headless operation
- **Silent installation** using VS Build Tools command-line parameters

#### Nix Writers Pattern
Scripts are generated using `pkgs.writeShellScriptBin`:
- **Build-time validation** ensures script correctness
- **Dependency injection** of Nix store paths for Wine, tools, and installers
- **Parameterized generation** allows multiple script variants from single source

### Development Shell Features

#### Multiple Environments
- **`.#wine`**: Wine + MSVC for Windows-compatible builds
- **`.#mingw`**: Cross-compilation toolchain (experimental)
- **`.#default`**: Full development environment with multiple toolchains

#### Script Integration
All helper scripts are available as commands in the development shells:
- `wine-setup` / `wine-setup-advanced`: Automated setup
- `msbuild-wine`: Wine-wrapped MSBuild with path detection
- `nuget-restore`: NuGet package management
- `build-plugin`: Comprehensive build instructions

This architecture serves as a reference implementation for:
- **Cross-platform development** setups in Nix
- **Wine integration** for Windows-specific toolchains
- **Automated environment provisioning** for complex build requirements

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
