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
echo "Ready to build with: msbuild wsl-plugin-sample.sln /p:Configuration=Release /p:Platform=x64"
        '';

        # Simple build instructions script  
        buildHelper = pkgs.writeShellScriptBin "build-plugin" ''
echo "🔧 WSL Plugin Build Helper"
echo "========================="
echo ""
echo "⚠️  NOTE: Mono MSBuild lacks Visual C++ support for .vcxproj files"
echo ""
echo "Build options:"
echo ""
echo "1. First, restore NuGet packages:"
echo "   nuget-restore"
echo ""
echo "2a. Try Mono MSBuild (limited C++ support):"
echo "    msbuild wsl-plugin-sample.sln /p:Configuration=Release /p:Platform=x64"
echo ""
echo "2b. Use Wine with Visual Studio Build Tools:"
echo "    nix develop .#wine"
echo "    msbuild-wine wsl-plugin-sample.sln /p:Configuration=Release /p:Platform=x64"
echo ""
echo "2c. Use MinGW cross-compilation:"
echo "    nix develop .#mingw"
echo "    # Manual build with x86_64-w64-mingw32-gcc"
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
            echo "  build-plugin    - Show build instructions"
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
            echo "Run 'build-plugin' to get started!"
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
            echo "Install Visual Studio Build Tools in Wine for MSBuild support"
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