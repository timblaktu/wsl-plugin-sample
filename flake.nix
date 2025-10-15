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

# Create packages directory if it doesn't exist
mkdir -p packages

# Download Microsoft.WSL.PluginApi directly from NuGet
PACKAGE_VERSION="2.1.3"
PACKAGE_NAME="Microsoft.WSL.PluginApi"
PACKAGE_DIR="packages/$PACKAGE_NAME.$PACKAGE_VERSION"

if [ ! -d "$PACKAGE_DIR" ]
then
  echo "Downloading $PACKAGE_NAME $PACKAGE_VERSION..."
  
  # Create temp directory for download
  TEMP_DIR=$(mktemp -d)
  cd "$TEMP_DIR"
  
  # Download the nupkg file
  ${pkgs.curl}/bin/curl -L "https://www.nuget.org/api/v2/package/$PACKAGE_NAME/$PACKAGE_VERSION" -o "$PACKAGE_NAME.$PACKAGE_VERSION.nupkg"
  
  # Extract the package (nupkg is just a zip file)
  ${pkgs.unzip}/bin/unzip -q "$PACKAGE_NAME.$PACKAGE_VERSION.nupkg"
  
  # Move to packages directory
  cd "$OLDPWD"
  mv "$TEMP_DIR" "$PACKAGE_DIR"
  
  echo "Package restored to $PACKAGE_DIR"
else
  echo "Package $PACKAGE_NAME $PACKAGE_VERSION already exists"
fi
        '';

        # Simple build instructions script
        buildHelper = pkgs.writeShellScriptBin "build-plugin" ''
          echo "🔧 WSL Plugin Build Helper"
          echo "========================="
          echo ""
          echo "1. First, restore NuGet packages:"
          echo "   nuget-restore"
          echo ""
          echo "2. Then build with one of these methods:"
          echo ""
          echo "🪟 Windows/WSL (recommended):"
          echo "   msbuild.exe wsl-plugin-sample.sln /p:Configuration=Release /p:Platform=x64"
          echo ""
          echo "🍷 Wine MSBuild:"
          echo "   msbuild-wine wsl-plugin-sample.sln /p:Configuration=Release /p:Platform=x64"
          echo ""
          echo "🔨 MinGW direct compilation:"
          echo "   x86_64-w64-mingw32-gcc -shared -o sample-wsl-plugin.dll plugin.cpp \\"
          echo "     -I./packages/Microsoft.WSL.PluginApi.2.1.3/build/native/include \\"
          echo "     -lws2_32"
          echo ""
          echo "Output will be in x64/Release/ (MSBuild) or current directory (MinGW)"
          echo ""
          echo "Use the nuget command to restore packages manually if needed."
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
            
            # Package management and utilities
            nuget
            curl
            unzip
            git
            vim
            jq
            
            # Custom scripts
            buildHelper
          ];
          
          shellHook = ''
            echo "🔧 WSL Plugin Development Environment"
            echo "====================================="
            echo ""
            echo "Available commands:"
            echo "  build-plugin    - Show build instructions and restore packages"
            echo "  nuget-restore   - Download Microsoft.WSL.PluginApi NuGet package"
            echo "  msbuild-wine    - MSBuild wrapper using Wine (requires setup)"
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