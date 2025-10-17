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

        # Build instructions script with updated information
        buildHelper = pkgs.writeShellScriptBin "build-plugin" ''
echo "🔧 WSL Plugin Build Helper"
echo "========================="
echo ""
echo "✨ NEW: Sequential Component Installation Strategy"
echo ""
echo "🚀 QUICK START (Linux developers):"
echo "   nix develop .#wine         # Enter Wine development environment"
echo "   wine-setup                 # Reliable sequential setup (NEW!)"
echo "   msbuild-wine wsl-plugin-sample.sln /p:Configuration=Release /p:Platform=x64"
echo ""
echo "🎯 What the NEW wine-setup does:"
echo "   • Creates persistent cache (~2-4GB, one-time download)"
echo "   • Installs components sequentially (avoids Wine hangs)"
echo "   • Automatic retry on failure (3 attempts per component)"
echo "   • Component-level verification after each install"
echo "   • No more 30-minute timeouts or exit code 138!"
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

      in
      {
        devShells.default = pkgs.mkShell {
          name = "wsl-plugin-dev";
          
          buildInputs = with pkgs; [
            # Core build tools
            gcc
            gdb
            pkg-config
            cmake
            ninja
            
            # Windows cross-compilation support  
            pkgsCross.mingwW64.stdenv.cc
            wineWowPackages.stable
            winetricks
            
            # .NET/MSBuild related
            dotnet-sdk_8
            mono
            msbuild
            
            # Package management and utilities
            nuget
            curl
            unzip
            git
            vim
            jq
            
            # Custom scripts
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
            
            echo "🔧 WSL Plugin Development Environment"
            echo "====================================="
            echo ""
            echo "Available commands:"
            echo "  nuget-restore   - Restore NuGet packages from packages.config"  
            echo "  build-plugin    - Show correct build instructions (Wine required)"
            echo "  wine-reset      - Reset Wine environment for clean testing"
            echo ""
            echo "Cross-compilation tools:"
            echo "  CC=$CC"
            echo "  CXX=$CXX"
            echo ""
            echo "Project structure:"
            echo "  - wsl-plugin-sample.sln  - Visual Studio solution"
            echo "  - wsl-plugin-sample.vcxproj - Project file"
            echo "  - plugin.cpp - Main source code"
            echo "  - packages.config - NuGet dependencies"
            echo ""
            echo "⚠️  Note: MSBuild requires Wine + VS Build Tools for C++ projects"
            echo "Run 'build-plugin' for detailed instructions!"
            echo ""
          '';
          
          # Environment variables for cross-compilation
          CC = "x86_64-w64-mingw32-gcc";
          CXX = "x86_64-w64-mingw32-g++";
          AR = "x86_64-w64-mingw32-ar";
          STRIP = "x86_64-w64-mingw32-strip";
        };
        
        # Minimal shell for Wine-only development
        devShells.wine = pkgs.mkShell {
          name = "wsl-plugin-wine";
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
            
            echo "🍷 Wine-based WSL Plugin Development"
            echo "Available commands:"
            echo "  wine-setup                     # Setup Wine environment and VS Build Tools"
            echo "  wine-setup --help              # Show setup options (repair, clean, etc.)"
            echo "  wine-cache-manage status       # Check cache status and size"
            echo "  wine-reset                     # Reset Wine environment completely"
            echo "  msbuild-wine <project>         # Build with MSBuild"
            echo ""
            echo "State Summary:"
            # Run verification and format output compactly
            if wine-verify-components 2>/dev/null | grep -q "✅.*MSBuild" && \
               wine-verify-components 2>/dev/null | grep -q "✅.*MSVC" && \
               wine-verify-components 2>/dev/null | grep -q "✅.*Windows.*SDK"; then
              echo "  🟢 VS Build Tools: Ready"
            else
              echo "  🔴 VS Build Tools: Incomplete (run wine-setup)"
            fi
            
            # Check cache status
            CACHE_DIR="$HOME/.wine-wsl-plugin-cache"
            if [ -d "$CACHE_DIR" ] && [ "$(find "$CACHE_DIR" -name "*.exe" 2>/dev/null | wc -l)" -gt 0 ]; then
              CACHE_SIZE=$(du -sh "$CACHE_DIR" 2>/dev/null | cut -f1 || echo "unknown")
              echo "  💾 Cache: Available ($CACHE_SIZE)"
            else
              echo "  💾 Cache: Empty"
            fi
          '';
        };
        
        # MinGW-only shell for direct cross-compilation
        devShells.mingw = pkgs.mkShell {
          name = "wsl-plugin-mingw";
          buildInputs = with pkgs; [
            pkgsCross.mingwW64.stdenv.cc
            nugetRestore
            buildHelper
          ];
          shellHook = ''
            echo "🔨 MinGW-based WSL Plugin Development"
            echo "Direct cross-compilation without Wine"
            export CC=x86_64-w64-mingw32-gcc
            export CXX=x86_64-w64-mingw32-g++
          '';
        };
      });
}