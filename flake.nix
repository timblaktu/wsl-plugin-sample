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

        # Build instructions script with correct information
        buildHelper = pkgs.writeShellScriptBin "build-plugin" ''
echo "🔧 WSL Plugin Build Helper"
echo "========================="
echo ""
echo "⚠️  IMPORTANT: No version of MSBuild on Linux can build Visual C++ projects!"
echo "   Both Mono MSBuild and .NET SDK MSBuild lack Microsoft.Cpp.Default.props"
echo ""
echo "✅ RECOMMENDED: Wine + Visual Studio Build Tools (CLI after setup)"
echo ""
echo "1. First, restore NuGet packages:"
echo "   nuget-restore"
echo ""
echo "2. Setup Wine environment (one-time):"
echo "   nix develop .#wine"
echo "   winecfg                    # Configure Wine"
echo "   curl -L -o vs_buildtools.exe \"https://aka.ms/vs/17/release/vs_buildtools.exe\""
echo "   wine vs_buildtools.exe     # Install VS Build Tools (GUI)"
echo ""
echo "3. Build with Wine MSBuild (pure CLI):"
echo "   msbuild-wine wsl-plugin-sample.sln /p:Configuration=Release /p:Platform=x64"
echo ""
echo "❌ MinGW alternative (may not work with WSL Plugin API):"
echo "   nix develop .#mingw"
echo "   # Manual build with GCC - different ABI than MSVC++"
echo "   # WSL Plugin API likely expects MSVC++ calling conventions"
echo ""
echo "Output will be in x64/Release/"
        '';

        # Wine MSBuild wrapper
        msbuildWine = pkgs.writeShellScriptBin "msbuild-wine" ''
          export WINEPREFIX="$HOME/.wine-wsl-plugin"
          export WINEARCH=win64
          
          echo "Note: You need to install Visual Studio Build Tools in Wine first."
          echo "Run 'winecfg' to set up Wine, then install Build Tools manually."
          echo ""
          
          if [ ! -d "$WINEPREFIX" ]; then
            echo "Initializing Wine environment..."
            ${pkgs.wineWowPackages.stable}/bin/winecfg
          fi
          
          # Try to find and run MSBuild in Wine
          if [ -f "$WINEPREFIX/drive_c/Program Files (x86)/Microsoft Visual Studio/2019/BuildTools/MSBuild/Current/Bin/MSBuild.exe" ]; then
            exec ${pkgs.wineWowPackages.stable}/bin/wine "$WINEPREFIX/drive_c/Program Files (x86)/Microsoft Visual Studio/2019/BuildTools/MSBuild/Current/Bin/MSBuild.exe" "$@"
          else
            echo "MSBuild not found in Wine. Please install Visual Studio Build Tools."
            exit 1
          fi
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
            msbuildWine
          ];
          
          shellHook = ''
            echo "🔧 WSL Plugin Development Environment"
            echo "====================================="
            echo ""
            echo "Available commands:"
            echo "  nuget-restore   - Restore NuGet packages from packages.config"  
            echo "  build-plugin    - Show correct build instructions (Wine required)"
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
          
          # Wine configuration
          WINEPREFIX = "$HOME/.wine-wsl-plugin";
          WINEARCH = "win64";
        };
        
        # Minimal shell for Wine-only development
        devShells.wine = pkgs.mkShell {
          name = "wsl-plugin-wine";
          buildInputs = with pkgs; [
            wineWowPackages.stable
            nugetRestore
            buildHelper
            msbuildWine
          ];
          shellHook = ''
            echo "🍷 Wine-based WSL Plugin Development"
            echo "======================================"
            echo ""
            echo "SETUP REQUIRED (one-time):"
            echo "1. Configure Wine:           winecfg"
            echo "2. Download Build Tools:     curl -L -o vs_buildtools.exe \"https://aka.ms/vs/17/release/vs_buildtools.exe\""
            echo "3. Install in Wine:          wine vs_buildtools.exe"
            echo "   └─ Select 'C++ build tools' workload"
            echo "   └─ Ensure 'MSVC v143 compiler toolset' is included"
            echo "4. Test installation:        msbuild-wine --version"
            echo ""
            echo "AFTER SETUP:"
            echo "- Build project: msbuild-wine wsl-plugin-sample.sln /p:Configuration=Release /p:Platform=x64"
            echo ""
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