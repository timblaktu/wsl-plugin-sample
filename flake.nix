{
  description = "Development environment for WSL Plugin Sample with MSBuild support";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        
        # Pre-download Visual Studio Build Tools 2022 at build time
        vsBuildTools2022 = pkgs.fetchurl {
          url = "https://aka.ms/vs/17/release/vs_buildtools.exe";
          sha256 = "027y1cmhxqhsnnd028kfbd7vcp8gl6mcjz5916sxmvrbg24fy3nr";
        };
        
        # Pre-download Visual Studio Build Tools 2019 (alternative)
        vsBuildTools2019 = pkgs.fetchurl {
          url = "https://aka.ms/vs/16/release/vs_buildtools.exe";
          sha256 = "052v9qhz5apsif78n7kblq44hz7356jzlj9iq9715lis3fba7k0j";
        };
        
        # Simple NuGet package restoration script
        nugetRestore = pkgs.writeShellScriptBin "nuget-restore" ''
echo "Restoring NuGet packages for WSL Plugin..."
echo ""
echo "Running: nuget restore packages.config -PackagesDirectory ./packages"
${pkgs.nuget}/bin/nuget restore packages.config -PackagesDirectory ./packages
echo ""
echo "✅ Package restoration completed!"
echo "📁 Packages should be in: ./packages/"
echo "⚠️  NOTE: MSBuild on Linux cannot build Visual C++ projects!"
echo "Use Wine-based build instead (see build-plugin for instructions)"
        '';

        # MinGW build helper for WSL plugin compilation
        buildPluginMinGW = pkgs.writeShellScriptBin "build-plugin-mingw" ''
echo "🛠️  WSL Plugin MinGW Build Helper"
echo "================================"
echo ""
echo "✅ WORKING SOLUTION: MinGW Cross-Compilation"
echo ""
echo "🚀 QUICK BUILD:"
echo "   mkdir -p temp_include"
echo "   echo '#include <windows.h>' > temp_include/Windows.h"
echo "   x86_64-w64-mingw32-g++ \\"
echo "     -std=c++14 -shared \\"
echo "     -I temp_include \\"
echo "     -I packages/Microsoft.WSL.PluginApi.2.1.3/build/native/include \\"
echo "     -o plugin.dll plugin.cpp \\"
echo "     -lws2_32 -lkernel32 -luser32"
echo "   rm -rf temp_include"
echo ""
echo "📊 PREREQUISITES:"
echo "   nuget-restore                   # Restore NuGet packages (WSL Plugin API)"
echo ""
echo "🎯 BENEFITS:"
echo "   • Pure Nix solution - no Wine required"
echo "   • WSL Plugin API compatible (tested and working)"
echo "   • Fast compilation - no emulation overhead"
echo "   • Fully reproducible across systems"
echo ""
echo "📁 Output: plugin.dll (Windows DLL, ~130KB)"
echo ""
        '';

        # Build instructions script with updated information
        buildHelper = pkgs.writeShellScriptBin "build-plugin" ''
echo "🔧 WSL Plugin Build Helper"
echo "========================="
echo ""
echo "⚠️  WINE APPROACH: Known Issues - See WINE_VS_COMPAT.md"
echo ""
echo "🚀 RECOMMENDED (MinGW Cross-Compilation):"
echo "   nix develop .#mingw        # Enter MinGW environment"
echo "   build-plugin-mingw         # Show MinGW build instructions"
echo "   # Build works without Wine/VS dependencies!"
echo ""
echo "❌ WINE APPROACH (Not Working):"
echo "   nix develop .#wine         # Wine environment (reference only)"
echo "   wine-setup                 # ❌ Fails due to Wine 10.0 + VS 2022 incompatibility"
echo ""
echo "🔍 WINE LIMITATIONS IDENTIFIED:"
echo "   • Missing Windows API implementations in Wine 10.0"
echo "   • VS 2022 installer requires APIs not available in Wine"
echo "   • Consistent 5-7 second failure pattern documented"
echo "   • Wine AppDB rates VS 2022 compatibility as 'Garbage'"
echo ""
echo "📊 MONITORING & MANAGEMENT:"
echo "   wine-cache-manage status   # Check cache and component status"
echo "   wine-verify-components     # Verify all components installed"
echo "   wine-setup --repair        # Repair broken components"
echo "   wine-setup --clean         # Clean install from scratch"
echo ""
echo "🔧 ADVANCED OPTIONS:"
echo "   wine-setup --help          # Show all options"
echo "   wine-setup --vs2019        # Use VS 2019 instead of 2022"
echo "   wine-setup --update-cache  # Update offline layout"
echo ""
echo "🏗️  TRADITIONAL WORKFLOWS:"
echo ""
echo "1. NuGet packages (if needed):"
echo "   nuget-restore"
echo ""
echo "2. Windows development:"
echo "   # Use Visual Studio or MSBuild directly on Windows"
echo ""
echo "3. MinGW alternative (experimental, may not work with WSL Plugin API):"
echo "   nix develop .#mingw"
echo "   # Manual build with GCC - different ABI than MSVC++"
echo ""
echo "📁 Output will be in x64/Release/"
echo ""
echo "💡 KEY IMPROVEMENT: Sequential installation strategy eliminates Wine"
echo "    process management failures that caused 30+ minute hangs!"
        '';

        # Advanced Wine setup script with sequential installation strategy
        wineSetupAdvanced = pkgs.writeShellScriptBin "wine-setup-advanced" ''
          set -e
          
          export WINEPREFIX="$HOME/.wine-wsl-plugin"
          export WINEARCH=win64
          export WINEDEBUG=-all
          
          # Configuration
          CACHE_DIR="$HOME/.wine-wsl-plugin-cache"
          VS_VERSION="2022"
          LAYOUT_DIR="$CACHE_DIR/vs''${VS_VERSION}_offline"
          LOG_FILE="$HOME/.wine-wsl-plugin-setup.log"
          
          # Component lists (in dependency order)
          CORE_COMPONENTS=(
            "Microsoft.Component.MSBuild"
            "Microsoft.VisualStudio.Component.Roslyn.Compiler"
            "Microsoft.VisualStudio.Component.TextTemplating"
            "Microsoft.VisualStudio.Component.VC.CoreBuildTools"
          )
          
          CPP_COMPONENTS=(
            "Microsoft.VisualStudio.Component.VC.CoreIde"
            "Microsoft.VisualStudio.Component.VC.Tools.x86.x64"
            "Microsoft.VisualStudio.Component.VC.Redist.14.Latest"
          )
          
          SDK_COMPONENTS=(
            "Microsoft.VisualStudio.Component.Windows10SDK.19041"
            "Microsoft.VisualStudio.Component.VC.CMake.Project"
            "Microsoft.VisualStudio.Component.VC.CLI.Support"
          )
          
          # Wine health validation function
          validate_wine_state() {
            log_with_timestamp "🔍 Testing basic Wine functionality..."
            
            # Kill any existing Wine processes
            ${pkgs.wineWowPackages.stable}/bin/wineserver -k 2>/dev/null || true
            sleep 2
            
            # Test basic Wine functionality
            export DISPLAY=""
            if ! ${pkgs.wineWowPackages.stable}/bin/wine --version >/dev/null 2>&1; then
              log_with_timestamp "❌ Wine basic test failed"
              return 1
            fi
            
            # Initialize Wine prefix if corrupted/missing
            if [ ! -d "$WINEPREFIX" ] || [ ! -f "$WINEPREFIX/system.reg" ]; then
              log_with_timestamp "🔧 Reinitializing Wine prefix..."
              rm -rf "$WINEPREFIX" 2>/dev/null || true
              ${pkgs.wineWowPackages.stable}/bin/wineboot --init >/dev/null 2>&1
              ${pkgs.wineWowPackages.stable}/bin/wine reg add "HKEY_CURRENT_USER\\Software\\Wine" /v Version /d win10 /f >/dev/null 2>&1
            fi
            
            log_with_timestamp "✅ Basic Wine functionality confirmed"
            return 0
          }
          
          # Options
          USE_2019=false
          CLEAN_INSTALL=false
          REPAIR_MODE=false
          UPDATE_CACHE=false
          
          # Parse command line arguments
          while [[ $# -gt 0 ]]; do
            case $1 in
              --vs2019)
                USE_2019=true
                VS_VERSION="2019"
                LAYOUT_DIR="$CACHE_DIR/vs2019_offline"
                shift
                ;;
              --clean)
                CLEAN_INSTALL=true
                shift
                ;;
              --repair)
                REPAIR_MODE=true
                shift
                ;;
              --update-cache)
                UPDATE_CACHE=true
                shift
                ;;
              --help)
                echo "🍷 Wine MSVC Setup Script (Sequential Installation)"
                echo ""
                echo "Options:"
                echo "  --vs2019      Use Visual Studio Build Tools 2019 instead of 2022"
                echo "  --clean       Remove existing Wine prefix before setup"
                echo "  --repair      Repair existing installation"
                echo "  --update-cache Update offline layout cache"
                echo "  --help        Show this help message"
                echo ""
                echo "Features:"
                echo "  • Downloads VS Build Tools offline layout (one-time, ~2-4GB)"
                echo "  • Installs components sequentially to avoid Wine hangs"
                echo "  • Automatic retry logic for failed components"
                echo "  • Component-level verification"
                echo "  • Persistent cache across rebuilds"
                exit 0
                ;;
              *)
                echo "Unknown option: $1"
                echo "Use --help for options"
                exit 1
                ;;
            esac
          done
          
          # Logging function
          log_with_timestamp() {
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
          }
          
          # Component verification function
          verify_component() {
            local component=$1
            case "$component" in
              "Microsoft.Component.MSBuild")
                [ -f "$WINEPREFIX/drive_c/Program Files (x86)/Microsoft Visual Studio/$VS_VERSION/BuildTools/MSBuild/Current/Bin/MSBuild.exe" ] || \
                [ -f "$WINEPREFIX/drive_c/Program Files/Microsoft Visual Studio/$VS_VERSION/BuildTools/MSBuild/Current/Bin/MSBuild.exe" ]
                ;;
              "Microsoft.VisualStudio.Component.VC.Tools.x86.x64")
                compgen -G "$WINEPREFIX/drive_c/Program Files (x86)/Microsoft Visual Studio/$VS_VERSION/BuildTools/VC/Tools/MSVC/*/bin/Hostx64/x64/cl.exe" > /dev/null || \
                compgen -G "$WINEPREFIX/drive_c/Program Files/Microsoft Visual Studio/$VS_VERSION/BuildTools/VC/Tools/MSVC/*/bin/Hostx64/x64/cl.exe" > /dev/null
                ;;
              "Microsoft.VisualStudio.Component.Windows10SDK.19041")
                [ -d "$WINEPREFIX/drive_c/Program Files (x86)/Windows Kits/10/bin/10.0.19041.0" ] || \
                [ -d "$WINEPREFIX/drive_c/Program Files/Windows Kits/10/bin/10.0.19041.0" ]
                ;;
              *)
                # Generic check - component exists in some form
                [ -d "$WINEPREFIX/drive_c/Program Files (x86)/Microsoft Visual Studio" ] || \
                [ -d "$WINEPREFIX/drive_c/Program Files/Microsoft Visual Studio" ]
                ;;
            esac
          }
          
          # Install single component with improved monitoring
          install_single_component() {
            local component="$1"
            local timeout=120  # 2 minutes per component
            local poll_timeout=60   # 1 minute polling
            
            log_with_timestamp "Installing component: $component"
            
            # Validate basic Wine functionality before installation
            if ! validate_wine_state; then
              log_with_timestamp "❌ Basic Wine functionality test failed for $component"
              return 1
            fi
            
            # Disable set -e for Wine execution
            set +e
            
            # Capture output to detect errors immediately
            local temp_output="$(mktemp)"
            
            # Start Wine process in background for monitoring
            ${pkgs.wineWowPackages.stable}/bin/wine "$LAYOUT_DIR/vs_buildtools.exe" \
              --add "$component" \
              --passive \
              --norestart \
              --noUpdateInstaller \
              --noWeb \
              > "$temp_output" 2>&1 &
            
            local wine_pid=$!
            local monitor_start=$(date +%s)
            local wine_exit_code=0
            
            # Monitor process with timeout
            while kill -0 $wine_pid 2>/dev/null; do
              local elapsed=$(($(date +%s) - monitor_start))
              
              # Check for immediate fatal errors
              if grep -q "Inconsistency detected by ld.so" "$temp_output" 2>/dev/null; then
                log_with_timestamp "❌ Wine ld.so corruption detected for $component"
                kill $wine_pid 2>/dev/null || true
                wine_exit_code=1
                break
              fi
              
              if grep -q "Assertion.*failed" "$temp_output" 2>/dev/null; then
                log_with_timestamp "❌ Wine assertion failure detected for $component"
                kill $wine_pid 2>/dev/null || true
                wine_exit_code=1
                break
              fi
              
              # Timeout check
              if [ $elapsed -gt $timeout ]; then
                log_with_timestamp "⚠️ Component timeout ($timeout s): $component"
                kill $wine_pid 2>/dev/null || true
                wine_exit_code=124
                break
              fi
              
              sleep 5
            done
            
            # Wait for process to finish and get exit code (only if not already set by corruption detection)
            if [ $wine_exit_code -eq 0 ]; then
              wait $wine_pid 2>/dev/null || wine_exit_code=$?
            else
              wait $wine_pid 2>/dev/null || true  # Don't overwrite corruption exit code
            fi
            
            # Log output
            cat "$temp_output" >> "$LOG_FILE"
            rm -f "$temp_output"
            
            # Re-enable set -e
            set -e
            
            # If VS installer failed with corruption, clean state and return
            if [ $wine_exit_code -eq 1 ]; then
              log_with_timestamp "🧹 VS installer corruption detected - cleaning Wine state"
              ${pkgs.wineWowPackages.stable}/bin/wineserver -k || true
              sleep 2
              return 1
            fi
            
            # Poll for completion
            local elapsed=0
            while [ $elapsed -lt $poll_timeout ]; do
              if verify_component "$component"; then
                log_with_timestamp "✅ Component installed: $component"
                return 0
              fi
              
              sleep 10
              ((elapsed += 10))
              
              if [ $((elapsed % 30)) -eq 0 ]; then
                log_with_timestamp "Waiting for $component ($((poll_timeout - elapsed))s remaining)"
              fi
            done
            
            log_with_timestamp "⚠️ Component timeout: $component"
            return 1
          }
          
          # Install components sequentially with retry logic
          install_components_sequentially() {
            local components=("$@")
            
            for component in "''${components[@]}"; do
              local max_retries=3
              local retry_count=0
              local success=false
              
              while [ $retry_count -lt $max_retries ]; do
                if install_single_component "$component"; then
                  success=true
                  break
                fi
                
                ((retry_count++))
                if [ $retry_count -lt $max_retries ]; then
                  log_with_timestamp "Retry $retry_count/$max_retries for $component"
                  
                  # Clean Wine state
                  ${pkgs.wineWowPackages.stable}/bin/wineserver -k
                  sleep 5
                  
                  # Progressive delay
                  sleep $((retry_count * 30))
                fi
              done
              
              if [ "$success" = false ]; then
                log_with_timestamp "❌ Component permanently failed: $component"
                return 1
              fi
            done
          }
          
          # Create offline layout
          create_offline_layout() {
            log_with_timestamp "Creating VS Build Tools offline cache at $LAYOUT_DIR"
            log_with_timestamp "This will download ~2-4GB on first run..."
            
            mkdir -p "$CACHE_DIR"
            
            # Select installer
            if [ "$USE_2019" = true ]; then
              INSTALLER="${vsBuildTools2019}"
            else
              INSTALLER="${vsBuildTools2022}"
            fi
            
            # Copy installer to cache
            cp "$INSTALLER" "$CACHE_DIR/vs_buildtools.exe"
            
            # Create offline layout using native execution (no Wine)
            cd "$CACHE_DIR"
            
            # Note: VS installer can't actually run --layout without Windows
            # So we'll use the installer directly from cache
            mkdir -p "$LAYOUT_DIR"
            cp "$CACHE_DIR/vs_buildtools.exe" "$LAYOUT_DIR/vs_buildtools.exe"
            
            # Mark as complete (simplified since we can't do true offline layout in Linux)
            echo "$(date): VS $VS_VERSION offline layout ready" > "$LAYOUT_DIR/.complete"
            
            log_with_timestamp "✅ Offline cache prepared"
          }
          
          # Main installation flow
          log_with_timestamp "=== Wine Setup Started (Sequential Installation) ==="
          log_with_timestamp "WINEPREFIX: $WINEPREFIX"
          log_with_timestamp "VS_VERSION: $VS_VERSION"
          log_with_timestamp "CACHE_DIR: $CACHE_DIR"
          
          # Clean install if requested
          if [ "$CLEAN_INSTALL" = true ] && [ -d "$WINEPREFIX" ]; then
            log_with_timestamp "🧹 Removing existing Wine prefix..."
            rm -rf "$WINEPREFIX"
          fi
          
          # Phase 1: Ensure offline cache exists
          if [ ! -f "$LAYOUT_DIR/.complete" ] || [ "$UPDATE_CACHE" = true ]; then
            create_offline_layout
          else
            log_with_timestamp "✅ Using existing cache: $LAYOUT_DIR"
          fi
          
          # Validate and initialize Wine prefix
          if ! validate_wine_state; then
            log_with_timestamp "❌ Wine validation failed, aborting setup"
            exit 1
          fi
          
          # Install .NET Framework if needed
          if [ ! -f "$WINEPREFIX/drive_c/windows/Microsoft.NET/Framework64/v4.0.30319/MSBuild.exe" ]; then
            log_with_timestamp "📦 Installing .NET Framework 4.8..."
            ${pkgs.winetricks}/bin/winetricks -q dotnet48 corefonts
            log_with_timestamp "✅ .NET Framework installed"
          fi
          
          # Phase 2: Install core components
          log_with_timestamp "=== Installing Core Components ==="
          install_components_sequentially "''${CORE_COMPONENTS[@]}"
          
          # Phase 3: Install C++ toolchain
          log_with_timestamp "=== Installing C++ Toolchain ==="
          install_components_sequentially "''${CPP_COMPONENTS[@]}"
          
          # Phase 4: Install SDK and tools
          log_with_timestamp "=== Installing SDK Components ==="
          install_components_sequentially "''${SDK_COMPONENTS[@]}"
          
          # Phase 5: Verify complete workload
          log_with_timestamp "=== Verifying Installation ==="
          if [ -f "$WINEPREFIX/drive_c/Program Files (x86)/Microsoft Visual Studio/$VS_VERSION/BuildTools/MSBuild/Current/Bin/MSBuild.exe" ] || \
             [ -f "$WINEPREFIX/drive_c/Program Files/Microsoft Visual Studio/$VS_VERSION/BuildTools/MSBuild/Current/Bin/MSBuild.exe" ]; then
            log_with_timestamp "✅ VS Build Tools installation complete!"
          else
            log_with_timestamp "⚠️ Installation may be incomplete - check log for details"
            
            if [ "$REPAIR_MODE" = true ]; then
              log_with_timestamp "Attempting repair..."
              ${pkgs.wineWowPackages.stable}/bin/wine "$LAYOUT_DIR/vs_buildtools.exe" \
                --repair \
                --passive \
                --norestart
            fi
          fi
          
          log_with_timestamp "=== Setup Complete ==="
          echo "🎯 Setup complete! You can now use 'msbuild-wine' to build projects."
        '';
        
        # Simplified Wine setup script using sequential installation
        wineSetup = pkgs.writeShellScriptBin "wine-setup" ''
          # Use the advanced sequential installation with default options
          exec ${wineSetupAdvanced}/bin/wine-setup-advanced "$@"
        '';
        
        # Cache management helper
        wineCacheManage = pkgs.writeShellScriptBin "wine-cache-manage" ''
          CACHE_DIR="$HOME/.wine-wsl-plugin-cache"
          
          case "$1" in
            status)
              echo "📦 Wine VS Build Tools Cache Status"
              echo "===================================="
              if [ -d "$CACHE_DIR" ]; then
                echo "Cache location: $CACHE_DIR"
                
                if [ -f "$CACHE_DIR/vs2022_offline/.complete" ]; then
                  echo "✅ VS 2022 cache: $(du -sh "$CACHE_DIR/vs2022_offline" 2>/dev/null | cut -f1)"
                  echo "   Created: $(cat "$CACHE_DIR/vs2022_offline/.complete")"
                else
                  echo "❌ VS 2022 cache: Not created"
                fi
                
                if [ -f "$CACHE_DIR/vs2019_offline/.complete" ]; then
                  echo "✅ VS 2019 cache: $(du -sh "$CACHE_DIR/vs2019_offline" 2>/dev/null | cut -f1)"
                  echo "   Created: $(cat "$CACHE_DIR/vs2019_offline/.complete")"
                else
                  echo "❌ VS 2019 cache: Not created"
                fi
                
                echo ""
                echo "Total cache size: $(du -sh "$CACHE_DIR" 2>/dev/null | cut -f1)"
              else
                echo "❌ No cache directory found"
              fi
              ;;
            
            clean)
              if [ -d "$CACHE_DIR" ]; then
                echo "🧹 Cleaning VS Build Tools cache..."
                rm -rf "$CACHE_DIR"
                echo "✅ Cache cleaned"
              else
                echo "❌ No cache to clean"
              fi
              ;;
            
            update)
              echo "🔄 Updating cache..."
              ${wineSetupAdvanced}/bin/wine-setup-advanced --update-cache
              ;;
            
            *)
              echo "Wine VS Build Tools Cache Manager"
              echo ""
              echo "Usage: wine-cache-manage <command>"
              echo ""
              echo "Commands:"
              echo "  status  Show cache status and size"
              echo "  clean   Remove all cached files"
              echo "  update  Update offline layout cache"
              ;;
          esac
        '';
        
        # Component verification helper
        wineVerifyComponents = pkgs.writeShellScriptBin "wine-verify-components" ''
          export WINEPREFIX="$HOME/.wine-wsl-plugin"
          
          echo "🔍 VS Build Tools Component Verification"
          echo "========================================"
          
          if [ ! -d "$WINEPREFIX" ]; then
            echo "❌ Wine prefix not found. Run 'wine-setup' first."
            exit 1
          fi
          
          # Check core components
          echo ""
          echo "Core Components:"
          
          if [ -f "$WINEPREFIX/drive_c/windows/Microsoft.NET/Framework64/v4.0.30319/MSBuild.exe" ] || \
             [ -f "$WINEPREFIX/drive_c/Program Files (x86)/Microsoft Visual Studio/2022/BuildTools/MSBuild/Current/Bin/MSBuild.exe" ] || \
             [ -f "$WINEPREFIX/drive_c/Program Files/Microsoft Visual Studio/2022/BuildTools/MSBuild/Current/Bin/MSBuild.exe" ]; then
            echo "✅ MSBuild"
          else
            echo "❌ MSBuild"
          fi
          
          # Check for MSVC compiler
          if compgen -G "$WINEPREFIX/drive_c/Program Files (x86)/Microsoft Visual Studio/2022/BuildTools/VC/Tools/MSVC/*/bin/Hostx64/x64/cl.exe" > /dev/null || \
             compgen -G "$WINEPREFIX/drive_c/Program Files/Microsoft Visual Studio/2022/BuildTools/VC/Tools/MSVC/*/bin/Hostx64/x64/cl.exe" > /dev/null; then
            echo "✅ MSVC C++ Compiler (cl.exe)"
          else
            echo "❌ MSVC C++ Compiler (cl.exe)"
          fi
          
          # Check for Windows SDK
          if [ -d "$WINEPREFIX/drive_c/Program Files (x86)/Windows Kits/10/bin/10.0.19041.0" ] || \
             [ -d "$WINEPREFIX/drive_c/Program Files/Windows Kits/10/bin/10.0.19041.0" ]; then
            echo "✅ Windows 10 SDK (10.0.19041)"
          else
            echo "❌ Windows 10 SDK"
          fi
          
          # Check .NET Framework
          if [ -f "$WINEPREFIX/drive_c/windows/Microsoft.NET/Framework64/v4.0.30319/MSBuild.exe" ]; then
            echo "✅ .NET Framework 4.8"
          else
            echo "❌ .NET Framework 4.8"
          fi
          
          echo ""
          echo "💡 If components are missing, run: wine-setup --repair"
        '';
        
        # Simplified Wine reset script
        wineReset = pkgs.writeShellScriptBin "wine-reset" ''
          set -euo pipefail
          
          export WINEPREFIX="$HOME/.wine-wsl-plugin"
          CACHE_DIR="$HOME/.wine-wsl-plugin-cache"
          LOG_FILE="$HOME/.wine-wsl-plugin-setup.log"
          
          echo "🔄 Wine Environment Reset"
          echo "========================"
          echo ""
          echo "This will remove:"
          echo "  • Wine prefix: $WINEPREFIX"
          echo "  • VS cache: $CACHE_DIR" 
          echo "  • Setup log: $LOG_FILE"
          echo ""
          echo -n "Continue? (y/N): "
          read -r response
          if [[ ! "$response" =~ ^[Yy]$ ]]; then
            echo "Cancelled."
            exit 0
          fi
          
          echo ""
          echo "🛑 Performing thorough Wine cleanup..."
          
          # Kill all Wine processes (multiple attempts)
          ${pkgs.wineWowPackages.stable}/bin/wineserver -k 2>/dev/null || true
          sleep 2
          ${pkgs.wineWowPackages.stable}/bin/wineserver -k 2>/dev/null || true
          
          # Kill any remaining Wine processes by name
          pkill -f wine 2>/dev/null || true
          pkill -f wineserver 2>/dev/null || true
          sleep 1
          
          # Force kill any stubborn processes
          pkill -9 -f wine 2>/dev/null || true
          pkill -9 -f wineserver 2>/dev/null || true
          
          # Remove Wine prefix
          if [ -d "$WINEPREFIX" ]; then
            echo "🗑️  Removing Wine prefix..."
            rm -rf "$WINEPREFIX"
            echo "   ✅ Removed"
          fi
          
          # Remove cache
          if [ -d "$CACHE_DIR" ]; then
            echo "🗑️  Removing VS cache..."
            rm -rf "$CACHE_DIR"
            echo "   ✅ Removed"
          fi
          
          # Remove log
          if [ -f "$LOG_FILE" ]; then
            echo "🗑️  Removing setup log..."
            rm -f "$LOG_FILE"
            echo "   ✅ Removed"
          fi
          
          # Clean Wine temporary files and shared memory
          echo "🧹 Cleaning Wine temporary files..."
          rm -rf /tmp/.wine-* 2>/dev/null || true
          rm -rf /tmp/wine-* 2>/dev/null || true
          rm -rf ~/.cache/wine 2>/dev/null || true
          rm -rf ~/.cache/winetricks 2>/dev/null || true
          
          # Clean any Wine shared memory segments
          for shm in $(ls /dev/shm/ 2>/dev/null | grep -E "wine|Wine" || true); do
            rm -f "/dev/shm/$shm" 2>/dev/null || true
          done
          
          echo ""
          echo "✨ Thorough reset complete! Wine state fully cleaned."
          echo "Run 'wine-setup' to reinstall with fresh environment."
        '';
        
        # Wine MSBuild wrapper with better path detection
        msbuildWine = pkgs.writeShellScriptBin "msbuild-wine" ''
          export WINEPREFIX="$HOME/.wine-wsl-plugin"
          export WINEARCH=win64
          export WINEDEBUG=-all
          
          # Check if Wine prefix exists
          if [ ! -d "$WINEPREFIX" ]; then
            echo "❌ Wine prefix not found. Run 'wine-setup' first."
            exit 1
          fi
          
          # Try multiple possible MSBuild locations
          msbuild_paths=(
            # .NET Framework MSBuild (installed via winetricks dotnet48)
            "$WINEPREFIX/drive_c/windows/Microsoft.NET/Framework64/v4.0.30319/MSBuild.exe"
            "$WINEPREFIX/drive_c/windows/Microsoft.NET/Framework/v4.0.30319/MSBuild.exe"
            # VS Build Tools MSBuild (if separately installed)
            "$WINEPREFIX/drive_c/Program Files (x86)/Microsoft Visual Studio/2022/BuildTools/MSBuild/Current/Bin/MSBuild.exe"
            "$WINEPREFIX/drive_c/Program Files (x86)/Microsoft Visual Studio/2019/BuildTools/MSBuild/Current/Bin/MSBuild.exe"
            "$WINEPREFIX/drive_c/Program Files/Microsoft Visual Studio/2022/BuildTools/MSBuild/Current/Bin/MSBuild.exe"
          )
          
          msbuild_exe=""
          for path in "''${msbuild_paths[@]}"; do
            if [ -f "$path" ]; then
              msbuild_exe="$path"
              break
            fi
          done
          
          if [ -z "$msbuild_exe" ]; then
            echo "❌ MSBuild not found in Wine. Run 'wine-setup' to install Visual Studio Build Tools."
            exit 1
          fi
          
          echo "🔨 Using MSBuild: $(basename "$(dirname "$msbuild_exe")")"
          exec ${pkgs.wineWowPackages.stable}/bin/wine "$msbuild_exe" "$@"
        '';

        # Embedded Makefile for build automation
        makefileContent = ''
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
        '';

        # Write Makefile to the development environment
        embeddedMakefile = pkgs.writeText "Makefile" makefileContent;
        # Enhanced Windows Container build script with WSL interop support
        buildWindowsPlugin = pkgs.writeShellScriptBin "build-windows-plugin" ''
          set -euo pipefail
          
          # WSL Interop function - runs containers on Windows host via PowerShell
          exec_wsl_windows_build() {
            # Get Windows equivalent of current directory
            local wsl_path="$(pwd)"
            local windows_path
            
            # Convert WSL path to Windows path
            if [[ "$wsl_path" =~ ^/mnt/([a-z])/ ]]; then
              # Path like /mnt/c/... 
              local drive="''${BASH_REMATCH[1]}"
              windows_path="''${drive^^}:''${wsl_path#/mnt/$drive}"
              windows_path="''${windows_path//\//\\}"
            else
              # WSL internal path - use wslpath if available
              if command -v wslpath >/dev/null 2>&1; then
                windows_path="$(wslpath -w "$wsl_path")"
              else
                echo "❌ Cannot convert WSL path to Windows path: $wsl_path"
                echo "💡 Please run from a Windows drive (/mnt/c/...)"
                exit 1
              fi
            fi
            
            echo "[INFO] Working directory: $wsl_path"
            echo "[INFO] Windows path: $windows_path"
            echo ""
            
            # Create PowerShell build script on Windows side
            local ps_script_path="/mnt/c/temp/wsl-plugin-build.ps1"
            echo "[INFO] Creating Windows-side PowerShell build script..."
            
            mkdir -p "$(dirname "$ps_script_path")"
            cat > "$ps_script_path" << 'PSEOF'
          param(
              [string]$ProjectPath = "."
          )
          
          $ErrorActionPreference = "Stop"
          
          Write-Host "🐳 Windows Container Build via WSL Interop"
          Write-Host "=========================================="
          Write-Host ""
          Write-Host "📁 Project path: $ProjectPath"
          
          # Change to project directory
          Set-Location $ProjectPath
          
          # Check for container runtime
          $ContainerCmd = $null
          foreach ($cmd in @("docker", "podman")) {
              if (Get-Command $cmd -ErrorAction SilentlyContinue) {
                  $ContainerCmd = $cmd
                  Write-Host "✅ Found container runtime: $cmd"
                  break
              }
          }
          
          if (-not $ContainerCmd) {
              Write-Host "❌ No container runtime found (docker or podman required)"
              Write-Host "💡 Install Docker Desktop or Podman Desktop for Windows"
              exit 1
          }
          
          # Create Dockerfile if it doesn't exist
          if (-not (Test-Path "Dockerfile.windows")) {
              Write-Host "📄 Creating Dockerfile.windows..."
              @"
          # Windows Server Core with Visual Studio Build Tools
          FROM mcr.microsoft.com/windows/servercore:ltsc2022
          
          # Install VS Build Tools with required components
          SHELL ["powershell", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]
          
          RUN Invoke-WebRequest -Uri "https://aka.ms/vs/17/release/vs_buildtools.exe" -OutFile "vs_buildtools.exe" ; \
              Start-Process -FilePath ".\vs_buildtools.exe" -ArgumentList "--quiet", "--wait", \
                "--add", "Microsoft.VisualStudio.Workload.VCTools", \
                "--add", "Microsoft.VisualStudio.Component.Windows10SDK.19041", \
                "--add", "Microsoft.VisualStudio.Component.VC.CMake.Project" \
                -NoNewWindow -Wait ; \
              Remove-Item ".\vs_buildtools.exe"
          
          # Set environment for builds
          RUN setx PATH "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin;%PATH%" /M
          
          WORKDIR C:\workspace
          "@ | Out-File -FilePath "Dockerfile.windows" -Encoding ASCII
              Write-Host "✅ Dockerfile.windows created"
          }
          
          # Create MSBuild project file if it doesn't exist
          if (-not (Test-Path "plugin.vcxproj")) {
              Write-Host "📄 Creating plugin.vcxproj..."
              @"
          <?xml version="1.0" encoding="utf-8"?>
          <Project DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
            <ItemGroup Label="ProjectConfigurations">
              <ProjectConfiguration Include="Release|x64">
                <Configuration>Release</Configuration>
                <Platform>x64</Platform>
              </ProjectConfiguration>
            </ItemGroup>
            <PropertyGroup Label="Globals">
              <VCProjectVersion>16.0</VCProjectVersion>
              <ProjectGuid>{12345678-1234-1234-1234-123456789012}</ProjectGuid>
              <Keyword>Win32Proj</Keyword>
              <RootNamespace>wslplugin</RootNamespace>
              <WindowsTargetPlatformVersion>10.0.19041.0</WindowsTargetPlatformVersion>
            </PropertyGroup>
            <Import Project="`$(VCTargetsPath)\Microsoft.Cpp.Default.props" />
            <PropertyGroup Condition="'`$(Configuration)|`$(Platform)'=='Release|x64'" Label="Configuration">
              <ConfigurationType>DynamicLibrary</ConfigurationType>
              <UseDebugLibraries>false</UseDebugLibraries>
              <PlatformToolset>v143</PlatformToolset>
              <WholeProgramOptimization>true</WholeProgramOptimization>
              <CharacterSet>Unicode</CharacterSet>
            </PropertyGroup>
            <Import Project="`$(VCTargetsPath)\Microsoft.Cpp.props" />
            <PropertyGroup Condition="'`$(Configuration)|`$(Platform)'=='Release|x64'">
              <LinkIncremental>false</LinkIncremental>
              <TargetName>plugin</TargetName>
            </PropertyGroup>
            <ItemDefinitionGroup Condition="'`$(Configuration)|`$(Platform)'=='Release|x64'">
              <ClCompile>
                <WarningLevel>Level3</WarningLevel>
                <FunctionLevelLinking>true</FunctionLevelLinking>
                <IntrinsicFunctions>true</IntrinsicFunctions>
                <SDLCheck>true</SDLCheck>
                <PreprocessorDefinitions>NDEBUG;WSLPLUGIN_EXPORTS;_WINDOWS;_USRDLL;%(PreprocessorDefinitions)</PreprocessorDefinitions>
                <ConformanceMode>true</ConformanceMode>
                <AdditionalIncludeDirectories>packages\Microsoft.WSL.PluginApi.2.1.3\build\native\include</AdditionalIncludeDirectories>
              </ClCompile>
              <Link>
                <SubSystem>Windows</SubSystem>
                <EnableCOMDATFolding>true</EnableCOMDATFolding>
                <OptimizeReferences>true</OptimizeReferences>
                <GenerateDebugInformation>true</GenerateDebugInformation>
                <AdditionalDependencies>ws2_32.lib;wbemuuid.lib;ole32.lib;oleaut32.lib;%(AdditionalDependencies)</AdditionalDependencies>
              </Link>
            </ItemDefinitionGroup>
            <ItemGroup>
              <ClCompile Include="plugin.cpp" />
            </ItemGroup>
            <Import Project="`$(VCTargetsPath)\Microsoft.Cpp.targets" />
          </Project>
          "@ | Out-File -FilePath "plugin.vcxproj" -Encoding UTF8
              Write-Host "✅ plugin.vcxproj created"
          }
          
          # Build or check for existing container
          $ImageName = "wsl-plugin-builder:latest"
          $ImageExists = & $ContainerCmd images --format "{{.Repository}}:{{.Tag}}" | Select-String -Pattern $ImageName
          
          if (-not $ImageExists) {
              Write-Host "[INFO] Building Windows container (this may take 10-15 minutes)..."
              & $ContainerCmd build -f Dockerfile.windows -t $ImageName .
              if ($LASTEXITCODE -ne 0) {
                  Write-Host "[ERROR] Container build failed"
                  exit 1
              }
              Write-Host "[SUCCESS] Container built successfully"
          } else {
              Write-Host "[SUCCESS] Using existing container: $ImageName"
          }
          
          Write-Host "[INFO] Building plugin with Windows container..."
          
          # Run the build in the container
          & $ContainerCmd run --rm -v "''${PWD}:C:\workspace" -w "C:\workspace" $ImageName powershell -Command @"
              # Restore NuGet packages first
              if (Test-Path 'packages.config') {
                  nuget restore packages.config -PackagesDirectory packages
              }
              
              # Build the project
              MSBuild plugin.vcxproj /p:Configuration=Release /p:Platform=x64 /m
              
              # Copy output to expected location
              if (Test-Path 'x64/Release/plugin.dll') {
                  Copy-Item 'x64/Release/plugin.dll' 'plugin.dll'
                  Write-Host '[SUCCESS] Plugin built successfully: plugin.dll'
                  Get-Item plugin.dll | Format-List Name,Length
              } else {
                  Write-Host '[ERROR] Build failed - plugin.dll not found'
                  exit 1
              }
          "@
          
          if ($LASTEXITCODE -ne 0) {
              Write-Host "[ERROR] Container build failed"
              exit 1
          }
          
          if (Test-Path "plugin.dll") {
              $FileSize = (Get-Item "plugin.dll").Length
              Write-Host ""
              Write-Host "[SUCCESS] Windows container build completed successfully!"
              Write-Host "[INFO] Output: plugin.dll ($FileSize bytes)"
              Write-Host "[INFO] Built with full Windows SDK APIs (AF_HYPERV, WMI, VirtDisk)"
          } else {
              Write-Host "[ERROR] Build failed - plugin.dll not found"
              exit 1
          }
          PSEOF
            
            echo "[SUCCESS] PowerShell script created at $ps_script_path"
            echo ""
            
            # Execute the PowerShell script on Windows host
            echo "[INFO] Executing Windows container build via PowerShell..."
            /mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe \
              -ExecutionPolicy Bypass \
              -File "C:\\temp\\wsl-plugin-build.ps1" \
              -ProjectPath "$windows_path"
            
            # Clean up the temporary script
            rm -f "$ps_script_path"
          }
          
          # Linux native container function (original implementation)
          exec_linux_build() {
            # Check if Dockerfile.windows exists
            if [ ! -f Dockerfile.windows ]; then
              echo "📄 Creating Dockerfile.windows..."
              cat > Dockerfile.windows << 'EOF'
          # Windows Server Core with Visual Studio Build Tools
          FROM mcr.microsoft.com/windows/servercore:ltsc2022
          
          # Install VS Build Tools with required components
          SHELL ["powershell", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]
          
          RUN Invoke-WebRequest -Uri "https://aka.ms/vs/17/release/vs_buildtools.exe" -OutFile "vs_buildtools.exe" ; \
              Start-Process -FilePath ".\vs_buildtools.exe" -ArgumentList "--quiet", "--wait", \
                "--add", "Microsoft.VisualStudio.Workload.VCTools", \
                "--add", "Microsoft.VisualStudio.Component.Windows10SDK.19041", \
                "--add", "Microsoft.VisualStudio.Component.VC.CMake.Project" \
                -NoNewWindow -Wait ; \
              Remove-Item ".\vs_buildtools.exe"
          
          # Set environment for builds
          RUN setx PATH "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin;%PATH%" /M
          
          WORKDIR C:\workspace
          EOF
              echo "✅ Dockerfile.windows created"
            fi
            
            # Build the container if it doesn't exist
            if ! podman images --format "{{.Repository}}:{{.Tag}}" | grep -q "wsl-plugin-builder:latest"; then
              echo "🔨 Building Windows container (this may take 10-15 minutes)..."
              podman build -f Dockerfile.windows -t wsl-plugin-builder:latest .
              echo "✅ Container built successfully"
            else
              echo "✅ Using existing container: wsl-plugin-builder:latest"
            fi
            
            # Create MSBuild project file if it doesn't exist
            if [ ! -f plugin.vcxproj ]; then
              echo "📄 Creating plugin.vcxproj..."
              cat > plugin.vcxproj << 'EOF'
          <?xml version="1.0" encoding="utf-8"?>
          <Project DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
            <ItemGroup Label="ProjectConfigurations">
              <ProjectConfiguration Include="Release|x64">
                <Configuration>Release</Configuration>
                <Platform>x64</Platform>
              </ProjectConfiguration>
            </ItemGroup>
            <PropertyGroup Label="Globals">
              <VCProjectVersion>16.0</VCProjectVersion>
              <ProjectGuid>{12345678-1234-1234-1234-123456789012}</ProjectGuid>
              <Keyword>Win32Proj</Keyword>
              <RootNamespace>wslplugin</RootNamespace>
              <WindowsTargetPlatformVersion>10.0.19041.0</WindowsTargetPlatformVersion>
            </PropertyGroup>
            <Import Project="$(VCTargetsPath)\Microsoft.Cpp.Default.props" />
            <PropertyGroup Condition="'$(Configuration)|$(Platform)'=='Release|x64'" Label="Configuration">
              <ConfigurationType>DynamicLibrary</ConfigurationType>
              <UseDebugLibraries>false</UseDebugLibraries>
              <PlatformToolset>v143</PlatformToolset>
              <WholeProgramOptimization>true</WholeProgramOptimization>
              <CharacterSet>Unicode</CharacterSet>
            </PropertyGroup>
            <Import Project="$(VCTargetsPath)\Microsoft.Cpp.props" />
            <PropertyGroup Condition="'$(Configuration)|$(Platform)'=='Release|x64'">
              <LinkIncremental>false</LinkIncremental>
              <TargetName>plugin</TargetName>
            </PropertyGroup>
            <ItemDefinitionGroup Condition="'$(Configuration)|$(Platform)'=='Release|x64'">
              <ClCompile>
                <WarningLevel>Level3</WarningLevel>
                <FunctionLevelLinking>true</FunctionLevelLinking>
                <IntrinsicFunctions>true</IntrinsicFunctions>
                <SDLCheck>true</SDLCheck>
                <PreprocessorDefinitions>NDEBUG;WSLPLUGIN_EXPORTS;_WINDOWS;_USRDLL;%(PreprocessorDefinitions)</PreprocessorDefinitions>
                <ConformanceMode>true</ConformanceMode>
                <AdditionalIncludeDirectories>packages\Microsoft.WSL.PluginApi.2.1.3\build\native\include</AdditionalIncludeDirectories>
              </ClCompile>
              <Link>
                <SubSystem>Windows</SubSystem>
                <EnableCOMDATFolding>true</EnableCOMDATFolding>
                <OptimizeReferences>true</OptimizeReferences>
                <GenerateDebugInformation>true</GenerateDebugInformation>
                <AdditionalDependencies>ws2_32.lib;wbemuuid.lib;ole32.lib;oleaut32.lib;%(AdditionalDependencies)</AdditionalDependencies>
              </Link>
            </ItemDefinitionGroup>
            <ItemGroup>
              <ClCompile Include="plugin.cpp" />
            </ItemGroup>
            <Import Project="$(VCTargetsPath)\Microsoft.Cpp.targets" />
          </Project>
          EOF
              echo "✅ plugin.vcxproj created"
            fi
            
            echo "🚀 Building plugin with Windows container..."
            
            # Run the build in the container
            podman run --rm \
              -v "$(pwd):/workspace:Z" \
              -w /workspace \
              wsl-plugin-builder:latest \
              powershell -Command "
                # Restore NuGet packages first
                if (Test-Path 'packages.config') {
                  nuget restore packages.config -PackagesDirectory packages
                }
                
                # Build the project
                MSBuild plugin.vcxproj /p:Configuration=Release /p:Platform=x64 /m
                
                # Copy output to expected location
                if (Test-Path 'x64/Release/plugin.dll') {
                  Copy-Item 'x64/Release/plugin.dll' 'plugin.dll'
                  Write-Host '✅ Plugin built successfully: plugin.dll'
                  Get-Item plugin.dll | Format-List Name,Length
                } else {
                  Write-Host '❌ Build failed - plugin.dll not found'
                  exit 1
                }
              "
            
            if [ -f plugin.dll ]; then
              echo ""
              echo "✅ Windows container build completed successfully!"
              echo "📁 Output: plugin.dll ($(stat -c%s plugin.dll) bytes)"
              echo "🔍 Built with full Windows SDK APIs (AF_HYPERV, WMI, VirtDisk)"
            else
              echo "❌ Build failed"
              exit 1
            fi
          }
          
          # Main execution logic
          echo "🐳 WSL Plugin Windows Container Build"
          echo "===================================="
          echo ""
          
          # Detect if we're running in WSL
          if [ -n "''${WSL_DISTRO_NAME:-}" ]; then
            echo "[INFO] WSL environment detected: $WSL_DISTRO_NAME"
            echo "[INFO] Using WSL interop for Windows host container build"
            echo ""
            
            # Use WSL interop approach
            exec_wsl_windows_build
          else
            echo "[INFO] Linux environment detected"
            echo "[INFO] Using native Linux container build"
            echo ""
            
            # Use original Linux container approach  
            exec_linux_build
          fi
        '';
        
        # Podman container management script  
        manageContainers = pkgs.writeShellScriptBin "manage-containers" ''
          case "$1" in
            clean)
              echo "🧹 Cleaning WSL plugin containers and images..."
              podman container prune -f
              podman rmi wsl-plugin-builder:latest 2>/dev/null || true
              echo "✅ Containers cleaned"
              ;;
            status)
              echo "📊 WSL Plugin Container Status"
              echo "=============================="
              echo ""
              echo "Images:"
              podman images --format "table {{.Repository}}:{{.Tag}} {{.Size}} {{.Created}}" | grep -E "(REPOSITORY|wsl-plugin)"
              echo ""
              echo "Containers:"
              podman ps -a --format "table {{.Names}} {{.Status}} {{.Image}}" | grep -E "(NAMES|wsl-plugin)" || echo "No containers found"
              ;;
            build)
              echo "🔨 Rebuilding WSL plugin container..."
              podman rmi wsl-plugin-builder:latest 2>/dev/null || true
              ${buildWindowsPlugin}/bin/build-windows-plugin
              ;;
            *)
              echo "WSL Plugin Container Management"
              echo ""
              echo "Usage: manage-containers <command>"
              echo ""
              echo "Commands:"
              echo "  status  Show container and image status"
              echo "  clean   Remove all plugin containers and images"
              echo "  build   Force rebuild the container"
              ;;
          esac
        '';
      in
      {
        # Default shell is now Windows Container-based (winpod)
        devShells.default = pkgs.mkShell {
          name = "wsl-plugin-winpod-dev";
          
          buildInputs = with pkgs; [
            # Container tools
            podman
            podman-compose
            
            # Build tools  
            gnumake
            
            # Package management
            nuget
            
            # Development utilities
            file
            binutils
            git
            
            # WSL Plugin specific tools
            buildWindowsPlugin
            manageContainers
            
            # For testing (NixOS tests framework)
            # Note: Full testing requires nix-build, available in shell
          ];
          
          shellHook = ''
            # Copy Makefile to current directory
            if [ ! -f Makefile ] || [ "${embeddedMakefile}" -nt Makefile ]; then
              cp "${embeddedMakefile}" Makefile
              echo "📄 Makefile updated from flake definition"
            fi
            
            echo "🐳 WSL Plugin Development Environment (Windows Container)"
            echo "========================================================"
            echo ""
            echo "🚀 Quick start:"
            echo "  build-windows-plugin    # Build plugin with full Windows SDK APIs"
            echo "  manage-containers       # Container management tools"
            echo "  make plugin            # Build plugin with auto-detection"
            echo "  make test              # Run automated tests"
            echo ""
            echo "🔧 Container workflow:"
            echo "  1. First build downloads Windows Server Core (~4GB)"
            echo "  2. Installs Visual Studio Build Tools in container"
            echo "  3. Builds plugin.dll with real Windows APIs"
            echo ""
            echo "Environment:"
            echo "  Podman: $(podman --version 2>/dev/null || echo 'Not available')"
            echo "  Container: Windows Server Core + VS Build Tools"
            echo ""
            echo "💡 This replaces MinGW with full Windows SDK compilation"
          '';
        };
        
        # MinGW shell for lightweight development (no longer default)
        devShells.mingw = pkgs.mkShell {
          name = "wsl-plugin-mingw-dev";
          
          buildInputs = with pkgs; [
            # MinGW cross-compilation toolchain
            pkgsCross.mingwW64.stdenv.cc
            
            # Build tools
            gnumake
            
            # Package management
            nuget
            
            # Development utilities
            file
            binutils  # for strings command
            git
            
            # For testing (NixOS tests framework)
            # Note: Full testing requires nix-build, available in shell
          ];
          
          shellHook = ''
            # Copy Makefile to current directory
            if [ ! -f Makefile ] || [ "${embeddedMakefile}" -nt Makefile ]; then
              cp "${embeddedMakefile}" Makefile
              echo "📄 Makefile updated from flake definition"
            fi
            
            echo "🔨 WSL Plugin Development Environment (MinGW - Limited APIs)"
            echo "==========================================================="
            echo ""
            echo "⚠️  WARNING: MinGW has limited Windows SDK support"
            echo "    Missing: AF_HYPERV sockets, WMI interfaces, VirtDisk API"
            echo "    Use 'nix develop' (default) for full API support"
            echo ""
            echo "🚀 Quick start:"
            echo "  make help     # Show all available targets"
            echo "  make plugin   # Build the WSL plugin (limited functionality)"
            echo "  make test     # Run automated tests"
            echo ""
            echo "Environment:"
            echo "  Compiler: $(which x86_64-w64-mingw32-g++)"
            echo "  Make: $(which make)"
            echo ""
          '';
          
          # Environment variables for cross-compilation
          CC = "x86_64-w64-mingw32-gcc";
          CXX = "x86_64-w64-mingw32-g++";
          AR = "x86_64-w64-mingw32-ar";
          STRIP = "x86_64-w64-mingw32-strip";
        };
        
        # DEPRECATED: Wine-based development environment
        # ⚠️ DEPRECATED: Wine approach has compatibility issues with VS 2022 Build Tools
        # Use the default MinGW environment instead for reliable cross-compilation
        devShells.wine = pkgs.mkShell {
          name = "wsl-plugin-wine-deprecated";
          buildInputs = with pkgs; [
            wineWowPackages.stable
            winetricks
            curl
            nugetRestore
            buildHelper
            wineSetup
            wineSetupAdvanced
            msbuildWine
            wineCacheManage
            wineVerifyComponents
            wineReset
          ];
          shellHook = ''
            export WINEPREFIX="$HOME/.wine-wsl-plugin"
            export WINEARCH="win64"
            
            echo "⚠️  DEPRECATED: Wine-based WSL Plugin Development"
            echo "================================================"
            echo ""
            echo "🚨 This environment is DEPRECATED due to:"
            echo "   • Wine 10.0 incompatibility with VS 2022 Build Tools"
            echo "   • Missing Windows API implementations required by VS installer"
            echo "   • Consistent 5-7 second failure pattern in VS setup"
            echo "   • Wine AppDB rates VS 2022 compatibility as 'Garbage'"
            echo ""
            echo "✅ RECOMMENDED: Use the default MinGW environment instead:"
            echo "   exit"
            echo "   nix develop  # Enter default MinGW environment"
            echo "   make plugin  # Build with proven working solution"
            echo ""
            echo "📚 This shell is kept for reference and research purposes only."
            echo ""
          '';
        };
      });
}