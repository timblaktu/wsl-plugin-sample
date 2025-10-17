{
  description = "NixOS test for WSL plugin functionality";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        
        # NixOS test for WSL plugin functionality
        wsl-plugin-test = pkgs.nixosTest {
          name = "wsl-plugin-test";
          
          nodes.machine = { config, pkgs, lib, ... }: {
            # Basic NixOS configuration for testing
            imports = [ ];
            
            system.stateVersion = "24.05";
            
            # Minimal configuration
            boot.kernelParams = [ "console=ttyS0" ];
            
            # User for testing
            users.users.test = {
              isNormalUser = true;
              extraGroups = [ "wheel" ];
              password = "test";
            };
            
            # Enable sudo without password
            security.sudo.wheelNeedsPassword = false;
            
            # Install packages that our WSL plugin will interact with
            environment.systemPackages = with pkgs; [
              hostname
              procps  # provides ps, pgrep, etc.
              coreutils  # provides cat, etc.
              util-linux  # provides various system utilities
              file
            ];
            
            # Copy our test plugin.dll for inspection
            environment.etc."wsl-plugin-test/plugin.dll" = {
              source = ./plugin.dll;
              mode = "0644";
            };
            
            # Create a test script that simulates WSL plugin operations
            environment.etc."wsl-plugin-test/test-plugin-functionality.sh" = {
              text = ''
                #!/bin/bash
                set -e
                
                echo "=== WSL Plugin Functionality Test ==="
                echo ""
                
                echo "1. Testing hostname command (used by plugin):"
                hostname
                echo ""
                
                echo "2. Testing /proc/version access (used by plugin):"
                cat /proc/version
                echo ""
                
                echo "3. Testing plugin DLL presence:"
                if [ -f /etc/wsl-plugin-test/plugin.dll ]; then
                  echo "✅ plugin.dll found"
                  file /etc/wsl-plugin-test/plugin.dll
                  echo "Size: $(stat -c%s /etc/wsl-plugin-test/plugin.dll) bytes"
                else
                  echo "❌ plugin.dll not found"
                fi
                echo ""
                
                echo "4. Testing custom strings in plugin:"
                if strings /etc/wsl-plugin-test/plugin.dll | grep -q "CUSTOM WSL PLUGIN"; then
                  echo "✅ Custom plugin strings found:"
                  strings /etc/wsl-plugin-test/plugin.dll | grep "CUSTOM" | head -5
                else
                  echo "❌ Custom strings not found in plugin"
                fi
                echo ""
                
                echo "5. Testing system readiness for WSL plugin:"
                # Check if system has required commands that plugin uses
                REQUIRED_COMMANDS="hostname cat"
                for cmd in $REQUIRED_COMMANDS; do
                  if command -v "$cmd" >/dev/null 2>&1; then
                    echo "✅ $cmd: $(which $cmd)"
                  else
                    echo "❌ $cmd: not found"
                  fi
                done
                echo ""
                
                echo "=== Test Complete ==="
              '';
              mode = "0755";
            };
          };

          testScript = ''
            machine.start()
            machine.wait_for_unit("multi-user.target")
            
            # Test basic system functionality
            print("Testing basic system commands...")
            machine.succeed("hostname")
            machine.succeed("cat /proc/version")
            
            # Test plugin file presence
            print("Testing plugin file...")
            machine.succeed("test -f /etc/wsl-plugin-test/plugin.dll")
            
            # Run our comprehensive test script
            print("Running WSL plugin functionality tests...")
            result = machine.succeed("/etc/wsl-plugin-test/test-plugin-functionality.sh")
            print("Test output:")
            print(result)
            
            # Verify custom strings are present in plugin
            print("Verifying custom modifications...")
            machine.succeed("strings /etc/wsl-plugin-test/plugin.dll | grep 'CUSTOM WSL PLUGIN'")
            machine.succeed("strings /etc/wsl-plugin-test/plugin.dll | grep 'NixOS-WSL'")
            
            print("All tests passed!")
          '';
        };
      in
      {
        # NixOS test for WSL plugin functionality
        checks.wsl-plugin-test = wsl-plugin-test;

        # Development environment for running tests
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            nixos-test-driver  # For running nixosTest
            qemu_kvm
            virt-viewer
          ];
          shellHook = ''
            echo "🧪 WSL Plugin Test Environment"
            echo "=============================="
            echo ""
            echo "Available commands:"
            echo "  nix build .#checks.wsl-plugin-test        # Build and run plugin test"
            echo "  nix flake check                           # Run all checks"
            echo ""
            echo "This test validates:"
            echo "  • Plugin compilation and custom modifications"
            echo "  • System commands used by plugin (hostname, cat /proc/version)"
            echo "  • Plugin DLL structure and custom strings"
            echo "  • NixOS environment compatibility"
          '';
        };

        # Helper to run the test interactively
        packages.test-plugin = pkgs.writeShellScriptBin "test-wsl-plugin" ''
          echo "🧪 Running WSL Plugin Test"
          echo "========================="
          echo ""
          
          if [ ! -f plugin.dll ]; then
            echo "❌ plugin.dll not found. Build it first with:"
            echo "   nix develop .#mingw --command bash -c 'nuget-restore && build-plugin-mingw'"
            exit 1
          fi
          
          echo "✅ Found plugin.dll, running NixOS test..."
          nix build .#checks.wsl-plugin-test -L
        '';

        packages.default = self.packages.${system}.test-plugin;
      });
}