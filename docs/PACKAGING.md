# Packaging NixOS-WSL with WSL Plugin Distribution

This document outlines 5 comprehensive approaches for packaging the NixOS-WSL tarball alongside WSL plugin DLL and installation scripts, based on research of the NixOS-WSL build system and Nix packaging patterns.

## Background: NixOS-WSL Build Process

NixOS-WSL uses `make-system-tarball.nix` to create distribution tarballs. Key points:

- **Build Time**: `extraCommands` execute during tarball creation on the build machine
- **Import Time**: `wsl --import` extracts tarball contents to WSL root filesystem  
- **First Boot**: WSL starts, systemd runs, `/mnt/c` becomes available for Windows filesystem access

The `.wsl` file is essentially a renamed tarball that contains a complete NixOS system with WSL-specific adaptations.

## 1. Extended System Tarball Approach (Recommended)

**Pattern:** Extend `make-system-tarball.nix` with plugin assets integrated directly into the .wsl file

### Timeline and Execution

**Build Time (extraCommands execution):**
- `extraCommands` run during Nix build on the build machine
- Create systemd services and setup scripts
- Embed files at Linux filesystem paths in the tarball
- Windows filesystem (`/mnt/c`) is NOT available during build

**Import Time (`wsl --import`):**
- WSL extracts tarball contents to distribution root filesystem
- Plugin files now exist at Linux paths (e.g., `/opt/nixos-wsl-plugin/`)
- WSL distribution is imported but not yet running

**First Boot (post-import):**
- WSL starts, systemd initializes
- `/mnt/c` mount becomes available (Windows C: drive)
- First-boot systemd service copies plugin files to Windows filesystem
- Plugin installation can be triggered automatically

### Implementation

```nix
# In your NixOS-WSL build configuration
system.build.tarball = pkgs.callPackage <nixpkgs/nixos/lib/make-system-tarball.nix> {
  contents = [
    # Standard NixOS-WSL contents
    { source = config.system.build.toplevel; target = "/"; }
    
    # Embed WSL Plugin files in Linux filesystem
    { source = wslPluginPackage; target = "/opt/nixos-wsl-plugin/plugin.dll"; }
    { source = installScript; target = "/opt/nixos-wsl-plugin/install-wsl-plugin.ps1"; }
    { source = pluginDocs; target = "/opt/nixos-wsl-plugin/README.md"; }
  ];
  
  extraCommands = ''
    # Create first-boot systemd service (runs during build)
    mkdir -p $out/etc/systemd/system
    cat > $out/etc/systemd/system/nixos-wsl-plugin-setup.service << 'EOF'
[Unit]
Description=NixOS-WSL Plugin Setup
After=multi-user.target
ConditionPathExists=!/var/lib/nixos-wsl-plugin-installed

[Service]
Type=oneshot
ExecStart=/opt/nixos-wsl-plugin/setup-plugin.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    # Create the setup script (runs during build)
    mkdir -p $out/opt/nixos-wsl-plugin
    cat > $out/opt/nixos-wsl-plugin/setup-plugin.sh << 'EOF'
#!/bin/bash
echo "🔄 Setting up NixOS-WSL Plugin..."

# Copy plugin files to Windows filesystem (runs on first boot)
mkdir -p /mnt/c/NixOS-WSL-Plugin
cp /opt/nixos-wsl-plugin/* /mnt/c/NixOS-WSL-Plugin/

echo "✅ Plugin files copied to C:\\NixOS-WSL-Plugin\\"

# Mark as installed to prevent re-running
touch /var/lib/nixos-wsl-plugin-installed

# Optionally auto-install the plugin
echo "🔐 Installing WSL plugin..."
powershell.exe -ExecutionPolicy Bypass \
  -File "/mnt/c/NixOS-WSL-Plugin/install-wsl-plugin.ps1" \
  -PluginPath "C:\\NixOS-WSL-Plugin\\plugin.dll"

echo "✅ WSL plugin installation complete"
EOF
    chmod +x $out/opt/nixos-wsl-plugin/setup-plugin.sh
    
    # Enable the service
    mkdir -p $out/etc/systemd/system/multi-user.target.wants
    ln -sf ../nixos-wsl-plugin-setup.service $out/etc/systemd/system/multi-user.target.wants/
  '';
};
```

### Execution Flow

1. **Build**: Files embedded in tarball, systemd service created
2. **Import**: `wsl --import NixOS-Custom $HOME/WSL/NixOS nixos-wsl-custom.tar.gz`
3. **First Boot**: 
   - User runs `wsl -d NixOS-Custom`
   - systemd starts `nixos-wsl-plugin-setup.service`
   - Plugin files copied to `C:\NixOS-WSL-Plugin\`
   - Plugin automatically registered with WSL

### Advantages
- Single .wsl file distribution
- Plugin automatically available and installed after import
- Leverages existing NixOS-WSL infrastructure
- Standard WSL installation workflow
- No manual plugin installation steps required

### Disadvantages
- Slightly larger .wsl file (~130KB for plugin)
- Requires PowerShell execution during first boot
- One-time setup delay on first boot

---

## 2. Multi-Archive Distribution with Wrapper Script

**Pattern:** Companion archive containing plugin + wrapper installation script

### Implementation

```nix
# Main NixOS-WSL tarball (unchanged)
nixos-wsl-tarball = /* standard build */;

# Plugin companion package
wsl-plugin-distribution = pkgs.runCommand "nixos-wsl-plugin-dist" {} ''
  mkdir -p $out
  
  # Create plugin archive
  tar -czf $out/nixos-wsl-plugin.tar.gz \
    --transform 's|.*|plugin/|' ${wslPlugin}/plugin.dll \
    --transform 's|.*|plugin/|' ${installScript}/install-wsl-plugin.ps1 \
    --transform 's|.*|plugin/|' ${pluginDocs}/README.md
  
  # Create unified installer script
  cat > $out/install-nixos-wsl-complete.ps1 << 'EOF'
# NixOS-WSL Complete Installation Script
param(
    [string]$DistroName = "NixOS-Custom",
    [string]$InstallPath = "$env:USERPROFILE\WSL\$DistroName"
)

Write-Host "🚀 Installing NixOS-WSL with Plugin Support" -ForegroundColor Magenta

# Import WSL distribution
Write-Host "📦 Importing NixOS-WSL distribution..." -ForegroundColor Cyan
wsl --import $DistroName $InstallPath nixos-wsl.tar.gz

# Extract and install plugin
Write-Host "🔧 Setting up WSL plugin..." -ForegroundColor Cyan
tar -xzf nixos-wsl-plugin.tar.gz
.\plugin\install-wsl-plugin.ps1 -PluginPath "$(Get-Location)\plugin\plugin.dll"

Write-Host "✅ Installation complete!" -ForegroundColor Green
Write-Host "Start with: wsl -d $DistroName" -ForegroundColor White
EOF
'';
```

### Distribution Files
- `nixos-wsl.tar.gz` (main system)
- `nixos-wsl-plugin.tar.gz` (plugin assets) 
- `install-nixos-wsl-complete.ps1` (unified installer)

### Usage
```powershell
# Download all three files, then run:
.\install-nixos-wsl-complete.ps1 -DistroName "MyNixOS" -InstallPath "C:\WSL\MyNixOS"
```

### Advantages
- Modular distribution - users can skip plugin if desired
- Clear separation of concerns
- Standard archive formats
- User choice in installation process

### Disadvantages  
- Multiple files to distribute
- More complex installation process
- Requires manual coordination of files

---

## 3. Self-Extracting Windows Installer

**Pattern:** Windows-native .exe that extracts both WSL tarball and plugin

### Implementation

```nix
# Use mingw cross-compilation for Windows executable
wsl-installer = pkgs.pkgsCross.mingwW64.stdenv.mkDerivation {
  name = "nixos-wsl-installer";
  src = ./installer-src;
  
  nativeBuildInputs = with pkgs.pkgsCross.mingwW64; [
    stdenv.cc
    windows.pthreads
  ];
  
  postInstall = ''
    # Embed WSL tarball and plugin as resources in executable
    ${pkgs.pkgsCross.mingwW64.binutils}/bin/x86_64-w64-mingw32-objcopy \
      --add-section .wsl_tarball=${nixos-wsl-tarball}/nixos-wsl.tar.gz \
      --add-section .wsl_plugin=${wslPlugin}/plugin.dll \
      --add-section .install_script=${installScript}/install-wsl-plugin.ps1 \
      $out/bin/installer.exe $out/bin/nixos-wsl-installer.exe
      
    # Sign the executable for Windows trust
    ${signTool} $out/bin/nixos-wsl-installer.exe
  '';
};
```

### Installer C++ Logic
```cpp
// Extract embedded resources
ExtractResource("wsl_tarball", "nixos-wsl.tar.gz");
ExtractResource("wsl_plugin", "plugin.dll"); 
ExtractResource("install_script", "install-wsl-plugin.ps1");

// Run WSL import
system("wsl --import NixOS-Custom %USERPROFILE%\\WSL\\NixOS nixos-wsl.tar.gz");

// Install plugin
system("powershell -ExecutionPolicy Bypass -File install-wsl-plugin.ps1 -PluginPath plugin.dll");

// Cleanup temp files
DeleteFiles();
```

### Advantages
- Single file distribution (.exe)
- Familiar Windows installer experience  
- Automatic WSL + plugin installation
- Can include GUI progress indicator
- Professional distribution format

### Disadvantages
- Most complex build process
- Requires code signing for Windows trust
- Larger file size (embedded archives)
- Need to maintain C++ installer code

---

## 4. Nix Package with Post-Install Hooks

**Pattern:** WSL plugin as separate Nix package with deployment tooling

### Implementation

```nix
# WSL Plugin package
wsl-plugin = pkgs.stdenv.mkDerivation {
  name = "nixos-wsl-plugin";
  src = ./plugin-src;
  
  nativeBuildInputs = [ pkgs.pkgsCross.mingwW64.stdenv.cc ];
  
  buildPhase = ''
    x86_64-w64-mingw32-g++ -std=c++14 -shared \
      -I${wslPluginApi}/include \
      -o plugin.dll plugin.cpp \
      -lws2_32 -lkernel32 -luser32
  '';
  
  installPhase = ''
    mkdir -p $out/{bin,share/wsl-plugin}
    cp plugin.dll $out/share/wsl-plugin/
    cp install-wsl-plugin.ps1 $out/share/wsl-plugin/
    
    # Create deployment script  
    cat > $out/bin/deploy-wsl-plugin << 'EOF'
#!/bin/bash
set -euo pipefail

PLUGIN_PATH="$out/share/wsl-plugin"
echo "🔐 Deploying WSL plugin from $PLUGIN_PATH"

# Copy to Windows filesystem
mkdir -p /mnt/c/NixOS-WSL-Plugin
cp "$PLUGIN_PATH"/* /mnt/c/NixOS-WSL-Plugin/

# Install plugin
powershell.exe -ExecutionPolicy Bypass \
  -File "$PLUGIN_PATH/install-wsl-plugin.ps1" \
  -PluginPath "C:\\NixOS-WSL-Plugin\\plugin.dll"

echo "✅ WSL plugin deployed successfully"
EOF
    chmod +x $out/bin/deploy-wsl-plugin
  '';
};

# Include in NixOS-WSL system packages
environment.systemPackages = [ wsl-plugin ];

# Optional: Auto-deploy on system activation
system.activationScripts.wsl-plugin = ''
  # Run plugin deployment if conditions are met
  if [[ -d /mnt/c ]] && command -v powershell.exe >/dev/null 2>&1; then
    ${wsl-plugin}/bin/deploy-wsl-plugin || echo "⚠️ WSL plugin deployment failed"
  fi
'';
```

### Usage Workflow

```bash
# After WSL import and first boot
sudo nixos-rebuild switch  # Installs plugin package + auto-deploys

# Or manual deployment  
deploy-wsl-plugin

# Future updates
sudo nixos-rebuild switch  # Auto-updates and redeploys plugin
```

### Advantages
- Leverages Nix package management
- Plugin updates via standard `nixos-rebuild`
- Clean integration with NixOS configuration
- Reproducible deployments
- Version tracking and rollbacks

### Disadvantages
- Requires NixOS knowledge to configure
- Plugin deployment happens after WSL is running
- May need manual first-time setup

---

## 5. Hybrid: Enhanced Tarball + Standalone Plugin Package

**Pattern:** Best of both worlds - plugin in tarball + standalone package for updates

### Implementation

```nix
# Enhanced NixOS-WSL with embedded plugin (read-only reference)
system.build.tarball = pkgs.callPackage <nixpkgs/nixos/lib/make-system-tarball.nix> {
  contents = [
    { source = config.system.build.toplevel; target = "/"; }
    # Embed plugin as system resource
    { source = wslPlugin; target = "/usr/share/nixos-wsl/plugin.dll"; }
    { source = installScript; target = "/usr/share/nixos-wsl/install-wsl-plugin.ps1"; }
  ];
};

# Standalone updatable plugin package
wsl-plugin-manager = pkgs.writeShellScriptBin "nixos-wsl-plugin" ''
  set -euo pipefail
  
  PLUGIN_DIR="/usr/share/nixos-wsl"
  WINDOWS_DIR="/mnt/c/NixOS-WSL-Plugin"
  
  cmd_install() {
    echo "🔄 Installing NixOS-WSL plugin..."
    
    if [[ ! -f "$PLUGIN_DIR/plugin.dll" ]]; then
      echo "❌ Plugin not found. Please rebuild NixOS-WSL with plugin support."
      exit 1
    fi
    
    # Copy to Windows filesystem
    mkdir -p "$WINDOWS_DIR"
    cp "$PLUGIN_DIR"/* "$WINDOWS_DIR"/
    
    # Install plugin
    powershell.exe -ExecutionPolicy Bypass \
      -File "$PLUGIN_DIR/install-wsl-plugin.ps1" \
      -PluginPath "C:\\NixOS-WSL-Plugin\\plugin.dll"
      
    echo "✅ Plugin installed successfully"
  }
  
  cmd_status() {
    if reg.exe query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Lxss\Plugins" /v "demo-plugin" >/dev/null 2>&1; then
      echo "✅ WSL plugin is registered"
    else  
      echo "❌ WSL plugin is not registered"
    fi
  }
  
  cmd_uninstall() {
    echo "🗑️ Uninstalling WSL plugin..."
    reg.exe delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Lxss\Plugins" /v "demo-plugin" /f || true
    rm -rf "$WINDOWS_DIR"
    echo "✅ Plugin uninstalled"
  }
  
  case "''${1:-install}" in
    install) cmd_install ;;
    status) cmd_status ;; 
    uninstall) cmd_uninstall ;;
    *) echo "Usage: nixos-wsl-plugin {install|status|uninstall}" ;;
  esac
'';

# Include manager in system
environment.systemPackages = [ wsl-plugin-manager ];

# Optional: Auto-install on first boot
system.activationScripts.wsl-plugin-check = ''
  # Auto-install plugin if not already registered
  if [[ -d /mnt/c ]] && ! ${wsl-plugin-manager}/bin/nixos-wsl-plugin status >/dev/null 2>&1; then
    echo "🔄 Auto-installing WSL plugin on first boot..."
    ${wsl-plugin-manager}/bin/nixos-wsl-plugin install || echo "⚠️ Auto-install failed"
  fi
'';
```

### Usage Workflow

```bash
# One-time setup after WSL import  
nixos-wsl-plugin install

# Check status
nixos-wsl-plugin status

# Future updates (automatic with system updates)
sudo nixos-rebuild switch  # Updates plugin + auto-reinstalls

# Manual reinstall if needed
nixos-wsl-plugin install

# Remove plugin
nixos-wsl-plugin uninstall
```

### Advantages
- Plugin always available in distribution
- Simple management interface
- No external dependencies for initial install  
- Backward compatible with standard NixOS-WSL
- Graceful handling of updates and reinstalls

### Disadvantages
- Plugin embedded in every tarball (slight size increase)
- Requires command-line interaction for management

---

## Recommendation Summary

**For immediate development and testing:** Start with **Approach #1 (Extended System Tarball)** - it provides seamless integration with automatic setup.

**For production deployment:** Consider **Approach #5 (Hybrid)** - it offers the best user experience with automatic availability and flexible management.

**For maximum user choice:** **Approach #2 (Multi-Archive)** offers the most flexibility for users who may not want the plugin.

**For professional distribution:** **Approach #3 (Self-Extracting Installer)** provides the most polished end-user experience.

Each approach leverages different aspects of the Nix ecosystem while addressing the unique challenges of distributing Windows binaries alongside Linux distributions. The key insight is that `make-system-tarball.nix` provides powerful extension mechanisms through the `contents` and `extraCommands` parameters, enabling sophisticated plugin distribution strategies.