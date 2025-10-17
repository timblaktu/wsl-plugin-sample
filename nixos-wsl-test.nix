{
  description = "Lightweight NixOS-WSL test instance for WSL plugin development";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-wsl.url = "github:nix-community/NixOS-WSL";
    nixos-wsl.inputs.nixpkgs.follows = "nixpkgs";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, nixos-wsl, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system: {
      packages.default = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          nixos-wsl.nixosModules.wsl
          {
            system.stateVersion = "24.05";
            
            # WSL configuration
            wsl = {
              enable = true;
              automountPath = "/mnt";
              defaultUser = "nixos";
              startMenuLaunchers = true;
              wslConf.automount.root = "/mnt";
              wslConf.interop.appendWindowsPath = false;
              wslConf.network.generateHosts = false;
            };

            # Minimal system configuration for testing
            users.users.nixos = {
              isNormalUser = true;
              extraGroups = [ "wheel" "networkmanager" ];
              # Allow sudo without password for testing
              extraGroups = [ "wheel" ];
            };

            # Enable sudo without password for testing
            security.sudo.wheelNeedsPassword = false;

            # Minimal package set
            environment.systemPackages = with nixpkgs.legacyPackages.${system}; [
              vim
              git
              curl
              htop
              file
              hostname
              # For testing our custom WSL plugin functionality
              procps  # provides hostname, ps, etc.
            ];

            # Network configuration
            networking = {
              hostName = "nixos-wsl-test";
              dhcpcd.enable = false;
              dhcp.enable = false;
              useNetworkd = true;
            };

            # Systemd configuration
            systemd.services.systemd-resolved.enable = false;

            # Disable unnecessary services for lighter footprint
            services = {
              resolved.enable = false;
              timesyncd.enable = false;
            };

            # Enable basic services needed for testing
            services.openssh.enable = true;
            services.openssh.settings.PasswordAuthentication = true;
            services.openssh.settings.PermitRootLogin = "yes";
          }
        ];
      };

      # Build script to create WSL tarball
      packages.build-wsl-tarball = nixpkgs.legacyPackages.${system}.writeShellScriptBin "build-nixos-wsl-test" ''
        echo "🔨 Building NixOS-WSL Test Instance"
        echo "=================================="
        echo ""
        echo "Building lightweight NixOS-WSL system..."
        
        # Build the NixOS system
        nix build .#default.config.system.build.tarball --out-link result-wsl-tarball
        
        if [ -L result-wsl-tarball ]; then
          TARBALL_PATH=$(readlink -f result-wsl-tarball)
          TARBALL_FILE=$(find "$TARBALL_PATH" -name "*.tar.gz" | head -1)
          
          if [ -f "$TARBALL_FILE" ]; then
            # Copy to more convenient location
            cp "$TARBALL_FILE" nixos-wsl-test.tar.gz
            echo ""
            echo "✅ NixOS-WSL test instance built successfully!"
            echo "📁 Tarball: $(pwd)/nixos-wsl-test.tar.gz"
            echo "📊 Size: $(du -h nixos-wsl-test.tar.gz | cut -f1)"
            echo ""
            echo "🚀 To import into WSL:"
            echo "   wsl --import nixos-wsl-test C:\\path\\to\\install nixos-wsl-test.tar.gz"
            echo ""
            echo "🧪 To test with our WSL plugin:"
            echo "   1. Copy plugin.dll to appropriate WSL plugin directory"
            echo "   2. Start the NixOS-WSL instance"
            echo "   3. Check C:\\wsl-plugin-demo.txt for plugin output"
          else
            echo "❌ Could not find built tarball in $TARBALL_PATH"
            exit 1
          fi
        else
          echo "❌ Build failed - result symlink not created"
          exit 1
        fi
      '';

      # Development shell with necessary tools
      devShells.default = nixpkgs.legacyPackages.${system}.mkShell {
        buildInputs = with nixpkgs.legacyPackages.${system}; [
          git
          nix
          # For WSL management
          qemu
        ];
        shellHook = ''
          echo "🔧 NixOS-WSL Test Environment"
          echo "============================="
          echo ""
          echo "Available commands:"
          echo "  nix build .#default.config.system.build.tarball  # Build WSL tarball"
          echo "  nix run .#build-wsl-tarball                      # Build with convenience script"
          echo ""
          echo "This will create a minimal NixOS-WSL instance suitable for testing"
          echo "the custom WSL plugin functionality."
        '';
      };
    });
}