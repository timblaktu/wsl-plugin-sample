import <nixpkgs/nixos/tests/make-test-python.nix> ({ pkgs, ... }: {
  name = "wsl-plugin-test";

  nodes.machine = { config, pkgs, lib, ... }: {
    # Basic NixOS configuration for testing
    system.stateVersion = "24.05";
    
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
      binutils  # provides strings
    ];
    
    # Copy our test plugin.dll for inspection
    environment.etc."wsl-plugin-test/plugin.dll" = {
      source = ./plugin.dll;
      mode = "0644";
    };
    
    # Create a test script that simulates WSL plugin operations
    environment.etc."wsl-plugin-test/test-plugin-functionality.sh" = {
      text = lib.replaceStrings ["\r\n" "\r"] ["\n" "\n"] ''
        #!${pkgs.bash}/bin/bash
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

# Validate line endings in test script
print("Validating line endings in test script...")
machine.succeed("file /etc/wsl-plugin-test/test-plugin-functionality.sh | grep -v CRLF")

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
})