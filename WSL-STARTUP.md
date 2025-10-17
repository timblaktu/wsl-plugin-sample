# WSL2 Initialization Sequence & NixOS-WSL Plugin Architecture

## Executive Summary

This document provides a comprehensive technical analysis of the Windows Subsystem for Linux 2 (WSL2) initialization sequence, covering both Windows host-side operations and Linux guest-side boot processes. It details the synchronization points available through WSL plugins and examines the NixOS-WSL implementation as a case study in manipulating the Linux boot sequence.

**New in this revision:** This document introduces an architectural vision for extending NixOS-WSL's declarative configuration paradigm to the Windows host through WSL plugins, enabling seamless management of Windows-side dependencies (VHDXs, services, network shares) through NixOS configuration files. This represents a fundamental shift toward truly unified system configuration across the Windows/Linux boundary.

## Table of Contents

1. [WSL2 Architecture Overview](#wsl2-architecture-overview)
2. [Windows-Side Initialization](#windows-side-initialization)
3. [Linux-Side Initialization](#linux-side-initialization)
4. [WSL Plugin System](#wsl-plugin-system)
5. [NixOS-WSL Boot Shim Analysis](#nixos-wsl-boot-shim-analysis)
6. [NixOS-WSL Plugin Architecture Vision](#nixos-wsl-plugin-architecture-vision)
7. [Practical Applications](#practical-applications)
8. [Implementation Roadmap](#implementation-roadmap)

---

## WSL2 Architecture Overview

### Fundamental Components

WSL2 operates as a lightweight virtual machine running on Microsoft's Type 1 hypervisor (Hyper-V). Unlike WSL1 (which used syscall translation), WSL2 runs a real Linux kernel:

- **Host**: Windows 10/11 (build 19041+)
- **Hypervisor**: Hyper-V (lightweight VM infrastructure)
- **VM**: Hyper-V Utility VM running custom Microsoft Linux kernel
- **Guest**: Linux distribution root filesystem

### Key Architectural Differences from Traditional VMs

```
Traditional VM:                WSL2:
┌──────────────┐              ┌──────────────┐
│   Guest OS   │              │  Windows 10+ │
├──────────────┤              ├──────────────┤
│  Hypervisor  │              │ WSL Service  │ ← Windows service
├──────────────┤              │  (wslservice)│
│   Host OS    │              ├──────────────┤
└──────────────┘              │  Hyper-V VM  │ ← Lightweight VM
                              │ (wslhost.exe)│
                              ├──────────────┤
                              │ Linux Kernel │ ← Microsoft kernel
                              ├──────────────┤
                              │ Distribution │ ← Ubuntu, NixOS, etc.
                              │   Rootfs     │
                              └──────────────┘
```

### Process Hierarchy

When a user runs `wsl.exe` or `wsl.exe -d Ubuntu`:

1. **wsl.exe** (client) → communicates with **wslservice** (Windows service)
2. **wslservice** → manages **wslhost.exe** (VM process)
3. **wslhost.exe** → hosts the Hyper-V lightweight VM
4. **Linux kernel** boots inside VM
5. **Init process** (PID 1) starts in distribution

---

## Windows-Side Initialization

### Phase 1: WSL Service Startup

The WSL service (`wslservice`) runs as a Windows service and manages the lifecycle of all WSL instances.

**Key Responsibilities:**
- Managing plugin registration and lifecycle
- VM creation and lifecycle management
- Inter-process communication between Windows and Linux
- Resource allocation and networking

**Registry Location:**
```
HKLM\SYSTEM\CurrentControlSet\Services\wslservice
```

### Phase 2: Plugin Loading

**Registry Location:**
```
HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Lxss\Plugins
```

Plugins are registered as registry values:
```
Name:  plugin-name (REG_SZ)
Value: C:\Path\To\Plugin.dll
```

**Plugin Requirements:**
1. **Digital signature required** - unsigned DLLs will be rejected with `TRUST_E_NOSIGNATURE`
2. **Entry point**: `WSLPLUGINAPI_ENTRYPOINTV1(const WSLPluginAPIV1* Api, WSLPluginHooksV1* Hooks)`
3. **Runs in wslservice address space** - crashes will crash entire WSL service

### Phase 3: VM Creation Request

When `wsl.exe` is executed:

```
User Command: wsl.exe -d Ubuntu
     ↓
wsl.exe client process
     ↓
IPC to wslservice
     ↓
Plugin: WSLPLUGINAPI_ENTRYPOINTV1() ← Plugin DLL loaded
     ↓
wslservice creates VM request
     ↓
wslhost.exe process spawned
     ↓
Hyper-V VM allocated
```

### Phase 4: VM Initialization

**Timeline:**

```
T+0ms:   wslhost.exe process created
T+50ms:  Hyper-V VM allocated (memory, CPU)
T+100ms: Custom Linux kernel loaded into VM memory
T+150ms: Kernel boot parameters set
T+200ms: VM execution begins
T+250ms: Linux kernel decompresses and starts
T+300ms: Initramfs extracted
T+350ms: Early kernel initialization
T+400ms: Plugin: OnVMStarted() hook called ← SYNCHRONIZATION POINT #1
```

**Critical**: At this point:
- ✅ VM process exists and is running
- ✅ Linux kernel is loaded and executing
- ✅ Initramfs is mounted as root
- ❌ No distribution has started yet
- ❌ No PID 1 init process yet

---

## Linux-Side Initialization

### Phase 1: Kernel Boot

The Microsoft-built Linux kernel boots inside the VM:

```bash
# Kernel command line (typical)
initrd=/initrd.img panic=-1 pty.legacy_count=0 nr_cpus=8
```

**Boot Stages:**
1. **Kernel decompression** (`decompress_kernel`)
2. **Early init** (`start_kernel`)
3. **Memory management setup** (`mm_init`)
4. **Scheduler initialization** (`sched_init`)
5. **Initramfs extraction** (embedded in kernel)
6. **Root filesystem setup**

### Phase 2: Initramfs Environment

The initramfs provides a minimal Linux environment:

```
/initramfs (tmpfs)
├── bin/
│   ├── sh
│   ├── mount
│   └── ...
├── sbin/
│   └── init → /init
├── dev/
├── proc/
├── sys/
└── init (main init script)
```

**Purpose:**
- Mount necessary filesystems (`/proc`, `/sys`, `/dev`)
- Set up device nodes
- Mount the actual distribution root filesystem
- Execute the distribution's init system

### Phase 3: Root Namespace vs Distribution Namespace

WSL2 maintains multiple namespaces:

#### Root Namespace (VM-level)
```bash
# Access via: wsl --debug-shell
$ wsl --debug-shell
/ # ls /
bin   dev  home  init  lib    lost+found  mnt  proc  run   srv  tmp  var
```

This is the "root namespace" where:
- Linux kernel is running
- WSL utilities live (`/sbin/init`)
- **Plugin-spawned processes execute here** (via `ExecuteBinary()`)
- Minimal Mariner Linux-based root filesystem
- **Writable tmpfs** (changes lost on VM shutdown)

#### Distribution Namespace(s)
Each WSL distribution runs in its own PID and mount namespace:
```
Root Namespace (PID namespace)
  ↓
  ├── Distribution 1 Namespace (Ubuntu)
  │   └── PID 1: /sbin/init or systemd
  │
  └── Distribution 2 Namespace (NixOS)
      └── PID 1: /nix/store/.../systemd-shim
```

### Phase 4: Distribution Init Process

**Standard Distribution Boot:**

```
1. Kernel mounts distribution rootfs from:
   \\wsl.localhost\{DistroName}
   (actually: /mnt/wsl/instances/{GUID}/ext4.vhdx)

2. Kernel executes: /sbin/init (or whatever is in rootfs)

3. This process becomes PID 1 in the distribution namespace

4. WSL Plugin Hook: OnDistributionStarted() ← SYNCHRONIZATION POINT #2

5. Init system (systemd, OpenRC, etc.) takes over
```

**Key Constraint:**
On Linux, **PID 1 is special**:
- Cannot be killed (except SIGKILL from parent)
- If PID 1 exits, kernel panics
- systemd **refuses** to run unless it is PID 1
- This creates problems for non-native init systems (see NixOS case study)

### Phase 5: /etc/wsl.conf Processing

WSL reads `/etc/wsl.conf` from the distribution to configure behavior:

```ini
[boot]
systemd=true          # Use systemd as init (modern WSL)
command=/usr/bin/foo  # Run command on distro start

[automount]
enabled=true
mountFsTab=false

[network]
generateHosts=true
generateResolvConf=true

[interop]
enabled=true
appendWindowsPath=true
```

**Timing**: `/etc/wsl.conf` is read:
- Before distribution init starts
- After VM kernel is running
- Can influence what gets executed as PID 1

---

## WSL Plugin System

### Plugin Architecture

WSL plugins are Win32 DLLs that export a specific entry point and register hook functions for lifecycle events.

### Plugin API Version 1

**Entry Point:**
```cpp
EXTERN_C __declspec(dllexport) 
HRESULT WSLPLUGINAPI_ENTRYPOINTV1(
    const WSLPluginAPIV1* Api,  // API functions WSL provides to plugin
    WSLPluginHooksV1* Hooks     // Hooks plugin provides to WSL
);
```

**API Structure:**
```cpp
typedef struct {
    WSL_VERSION Version;  // WSL version info
    
    // Execute a Linux binary in root namespace
    HRESULT (*ExecuteBinary)(
        DWORD SessionId,
        const char* Path,
        const char* const* Arguments,
        SOCKET* Socket  // For stdout/stderr/stdin
    );
    
    // Other API functions...
} WSLPluginAPIV1;
```

**Hooks Structure:**
```cpp
typedef struct {
    HRESULT (*OnVMStarted)(
        const WSLSessionInformation* Session,
        const WSLVmCreationSettings* Settings
    );
    
    HRESULT (*OnVMStopping)(
        const WSLSessionInformation* Session
    );
    
    HRESULT (*OnDistributionStarted)(
        const WSLSessionInformation* Session,
        const WSLDistributionInformation* Distribution
    );
    
    HRESULT (*OnDistributionStopping)(
        const WSLSessionInformation* Session,
        const WSLDistributionInformation* Distribution
    );
    
    HRESULT (*OnDistributionRegistered)(
        const WSLSessionInformation* Session,
        const WslOfflineDistributionInformation* Distribution
    );
    
    HRESULT (*OnDistributionUnregistered)(
        const WSLSessionInformation* Session,
        const WslOfflineDistributionInformation* Distribution
    );
} WSLPluginHooksV1;
```

### Hook Lifecycle and Guarantees

#### OnVMStarted - VM Creation Hook

**When Called:**
```
Timeline of VM Start:
┌─────────────────────────────────────────────────────────┐
│ wslservice creates VM request                           │
├─────────────────────────────────────────────────────────┤
│ wslhost.exe spawned                                     │
├─────────────────────────────────────────────────────────┤
│ Hyper-V VM allocated                                    │
├─────────────────────────────────────────────────────────┤
│ Linux kernel loaded and started                         │
├─────────────────────────────────────────────────────────┤
│ Initramfs mounted                                       │
├─────────────────────────────────────────────────────────┤
│ Root namespace initialized                              │
├─────────────────────────────────────────────────────────┤
│ ★ OnVMStarted() CALLED HERE ★                          │ ← BLOCKING
│                                                         │
│ [SYNCHRONOUS - WSL SERVICE WAITS]                      │
│                                                         │
│ Plugin can:                                             │
│ - Execute Windows code (CreateProcess, registry, etc.) │
│ - Execute Linux binaries in root namespace             │
│ - Return S_OK to continue                              │
│ - Return error HRESULT to ABORT VM startup             │
├─────────────────────────────────────────────────────────┤
│ OnVMStarted() returns                                   │
├─────────────────────────────────────────────────────────┤
│ Distribution rootfs mounted                             │
├─────────────────────────────────────────────────────────┤
│ Distribution init process spawned (PID 1)               │
└─────────────────────────────────────────────────────────┘
```

**Guarantees:**
- ✅ **Synchronous blocking**: WSL waits for return before proceeding
- ✅ **Error handling**: Returning `FAILED(HRESULT)` terminates VM startup
- ✅ **Windows execution**: Full access to Windows APIs
- ✅ **Linux execution**: Can run binaries in root namespace via `ExecuteBinary()`
- ✅ **Before distributions**: No distribution has started yet
- ⚠️ **VM already running**: The VM kernel is already executing
- ⚠️ **No PID 1 yet**: Distribution init hasn't been spawned

**Example Usage:**
```cpp
HRESULT OnVmStarted(
    const WSLSessionInformation* Session,
    const WSLVmCreationSettings* Settings)
{
    // Check Windows dependencies
    if (!IsServiceRunning("MyRequiredService")) {
        return E_FAIL; // VM startup aborted
    }
    
    // Execute Linux commands in root namespace
    std::vector<const char*> args = {
        "/bin/sh", "-c", "echo VM started > /tmp/log", nullptr
    };
    SOCKET sock;
    g_api->ExecuteBinary(Session->SessionId, args[0], args.data(), &sock);
    closesocket(sock);
    
    // Allow VM startup to continue
    return S_OK;
}
```

#### OnDistributionStarted - Distribution Init Hook

**When Called:**
```
Timeline of Distribution Start:
┌─────────────────────────────────────────────────────────┐
│ (OnVMStarted has already completed)                     │
├─────────────────────────────────────────────────────────┤
│ Distribution rootfs mounted at:                         │
│   /mnt/wslg/distro/{name}                              │
├─────────────────────────────────────────────────────────┤
│ New PID namespace created for distribution              │
├─────────────────────────────────────────────────────────┤
│ Init process spawned in new namespace                   │
│   PID 1 in namespace = /sbin/init (or configured)      │
├─────────────────────────────────────────────────────────┤
│ ★ OnDistributionStarted() CALLED HERE ★                │ ← BLOCKING
│                                                         │
│ [SYNCHRONOUS - WSL SERVICE WAITS]                      │
│                                                         │
│ Plugin receives:                                        │
│ - Distribution name                                     │
│ - Package family name                                   │
│ - PID namespace ID                                      │
│ - Init process PID (in namespace)                       │
│                                                         │
│ Plugin can:                                             │
│ - Execute Windows code                                  │
│ - Return S_OK to allow distribution to run             │
│ - Return error to TERMINATE distribution               │
├─────────────────────────────────────────────────────────┤
│ OnDistributionStarted() returns                         │
├─────────────────────────────────────────────────────────┤
│ Distribution init continues execution                   │
│   (systemd, OpenRC, custom init, etc.)                 │
└─────────────────────────────────────────────────────────┘
```

**Guarantees:**
- ✅ **Synchronous blocking**: WSL waits for return
- ✅ **PID 1 exists**: Distribution init process is running
- ✅ **Error handling**: Returning error terminates distribution
- ✅ **Distribution context**: Access to distribution metadata
- ⚠️ **Init already started**: The PID 1 process exists and is executing
- ⚠️ **Cannot prevent spawn**: The init process was already spawned before hook

**Example Usage:**
```cpp
HRESULT OnDistroStarted(
    const WSLSessionInformation* Session,
    const WSLDistributionInformation* Distribution)
{
    std::wstring_convert<std::codecvt_utf8<wchar_t>, wchar_t> converter;
    std::string name = converter.to_bytes(Distribution->Name);
    
    g_logfile << "Distribution started: " << name 
              << ", PID namespace: " << Distribution->PidNamespace
              << ", Init PID: " << Distribution->InitPid << std::endl;
    
    // Could implement policy enforcement here
    if (name == "untrusted-distro" && !UserHasPermission()) {
        return E_ACCESSDENIED; // Distribution terminated
    }
    
    return S_OK;
}
```

### Critical Plugin Constraints

**Threading Model:**
- Plugins run on wslservice thread
- **Must not block indefinitely** - will hang all WSL operations
- Should complete quickly (< 1 second recommended)

**Error Handling:**
- Any `FAILED(HRESULT)` return is **fatal**
- Error codes appear in event logs:
  - `Wsl/Service/CreateInstance/CreateVm/Plugin/*` - OnVMStarted errors
  - `Wsl/Service/CreateInstance/Plugin/*` - OnDistributionStarted errors

**Safety:**
- Plugins run in wslservice address space
- **Plugin crash = service crash = all WSL VMs terminated**
- Must be extremely robust

**Execution Context:**
- Runs as LOCAL SYSTEM (wslservice account)
- Has SYSTEM privileges on Windows side
- Can execute code with highest privileges

---

## NixOS-WSL Boot Shim Analysis

### The systemd PID 1 Problem

Standard systemd-based distributions face a challenge on WSL:

**The Problem:**
```
WSL Boot Sequence:
1. WSL spawns: /sbin/init (whatever is in rootfs)
2. This becomes PID 1 in distribution namespace
3. For NixOS: /sbin/init → symlink to systemd

BUT:
- NixOS activation scripts need to run BEFORE systemd
- systemd refuses to start unless it is PID 1
- If something else runs first, systemd cannot be started
```

### NixOS-WSL Solution: The Shim

NixOS-WSL solves this with a **systemd-shim** that intercepts the boot process.

**Architecture:**
```
/sbin/init (WSL expects this)
  ↓ (symlink)
/nix/store/...-systemd-shim/bin/systemd-shim
  ↓
[SHIM PROCESS STARTS AS PID 1]
  ↓
1. Run NixOS activation scripts
   /nix/var/nix/profiles/system/activate
  ↓
2. Set up FHS compatibility symlinks
   /bin/sh, /usr/bin/env, etc.
  ↓
3. exec() systemd (replacing PID 1)
   exec /nix/store/...-systemd/lib/systemd/systemd
  ↓
[SYSTEMD NOW RUNNING AS PID 1]
```

**Key Technique: `exec()`**
The shim uses the Unix `exec()` system call:
```rust
// Simplified concept
fn main() {
    // I am PID 1
    run_activation_scripts();
    setup_fhs_symlinks();
    
    // Replace myself with systemd, keeping PID 1
    exec("/path/to/systemd", args);
    
    // This line never executes - process image replaced
}
```

**Why This Works:**
- `exec()` **replaces** the current process's memory and code
- **PID remains the same** - still PID 1
- systemd sees itself as PID 1 ✓
- Activation scripts have already run ✓

### Modern NixOS-WSL Implementation

**From the design documentation:**

> Instead of directly loading systemd, we use a small shim that runs the NixOS activation scripts first. Some additional binaries required by WSL's internal tooling are symlinked to FHS paths on activation.

**Boot Flow:**
```
User: wsl -d NixOS
  ↓
OnVMStarted() hook (if plugin installed)
  ↓
Distribution namespace created
  ↓
WSL executes: /sbin/init
  ↓
/sbin/init → /nix/store/XXX-systemd-shim/bin/systemd-shim
  ↓
systemd-shim (Rust binary, PID 1):
  │
  ├─ Run activation: /nix/var/nix/profiles/system/activate
  │  │
  │  ├─ Set up systemd service links
  │  ├─ Configure users and groups
  │  ├─ Set up /etc files
  │  └─ Create FHS compatibility symlinks:
  │     ├─ /bin/sh → /nix/store/...-bash/bin/sh
  │     ├─ /usr/bin/env → /nix/store/...-coreutils/bin/env
  │     └─ Other WSL-required paths
  │
  ├─ Verify environment is ready
  │
  └─ exec("/nix/store/XXX-systemd/lib/systemd/systemd", ...)
     ↓
     [Process image replaced, PID still 1]
     ↓
  systemd (now PID 1):
    ├─ systemd-journald
    ├─ systemd-logind  
    ├─ dbus
    ├─ User services
    └─ ...
```

**OnDistributionStarted Timing:**
```
Timeline with NixOS-WSL:
┌─────────────────────────────────────────────────────────┐
│ systemd-shim spawned as PID 1                           │
├─────────────────────────────────────────────────────────┤
│ ★ OnDistributionStarted() CALLED ★                     │ ← Hook fires
│   (Plugin sees PID 1 = systemd-shim)                   │
├─────────────────────────────────────────────────────────┤
│ systemd-shim runs activation scripts                    │
├─────────────────────────────────────────────────────────┤
│ systemd-shim exec() to replace itself with systemd     │
├─────────────────────────────────────────────────────────┤
│ systemd takes over (still PID 1)                        │
└─────────────────────────────────────────────────────────┘
```

### Legacy Method (Deprecated, Removed in 24.11)

**Historical Note:**
Older NixOS-WSL versions (pre-WSL systemd support) used a different approach called "syschdemd":

```
/bin/sh (default shell)
  ↓
Shell wrapper intercepts
  ↓
1. Start systemd in separate PID namespace
2. nsenter into systemd's namespace
3. Drop to actual user shell
```

This approach:
- Created a nested PID namespace where systemd could be PID 1
- Required shell wrapper for every shell invocation
- More complex and fragile
- **Removed** when WSL added native systemd support

---

## NixOS-WSL Plugin Architecture Vision

### The Declarative Configuration Gap

**Current State:**
NixOS provides exceptional declarative configuration for the Linux environment:

```nix
{ config, pkgs, ... }:
{
  # Declarative Linux configuration
  users.users.myuser = {
    isNormalUser = true;
    extraGroups = [ "wheel" "docker" ];
  };
  
  services.nginx.enable = true;
  
  environment.systemPackages = with pkgs; [
    vim git htop
  ];
}
```

However, there's a **fundamental asymmetry**: Windows-side dependencies are **not** declaratively managed:

```
Current Manual Process:
1. User manually creates D:\WSL\Data.vhdx
2. User manually mounts it in wsl.conf or fstab
3. User manually ensures Windows services are running
4. User manually configures network shares
5. NixOS configuration assumes all the above exists
```

**The Problem:**
- No single source of truth for the entire system
- Windows setup is error-prone and undocumented
- Cannot version control Windows dependencies
- Cannot reproduce environments reliably
- Breaks the NixOS declarative paradigm

### The Vision: Unified Declarative Configuration

**Goal:** Extend NixOS's declarative configuration to encompass Windows-side requirements through WSL plugins.

**Extended NixOS Configuration Example:**
```nix
{ config, pkgs, lib, ... }:
{
  # Standard NixOS configuration
  users.users.myuser = {
    isNormalUser = true;
    home = "/home/myuser";
  };
  
  # NEW: Declarative Windows-side configuration
  wsl.windows = {
    # Virtual disks on Windows host
    vhdx = {
      # Additional data disk on separate drive
      "/mnt/data" = {
        windowsPath = "D:\\WSL\\NixOS-Data.vhdx";
        sizeGB = 100;
        filesystem = "ext4";
        autoCreate = true;
        autoMount = true;
      };
      
      # Fast NVMe-backed nix store
      "/nix/store-fast" = {
        windowsPath = "E:\\WSL\\NixOS-Store.vhdx";
        sizeGB = 250;
        filesystem = "ext4";
        autoCreate = true;
        autoMount = true;
        mountOptions = [ "noatime" "discard" ];
      };
      
      # Project workspace
      "/home/myuser/projects" = {
        windowsPath = "C:\\Users\\MyUser\\WSL\\Projects.vhdx";
        sizeGB = 50;
        filesystem = "ext4";
        autoCreate = true;
        autoMount = true;
      };
    };
    
    # Required Windows services
    requiredServices = [
      "Docker Desktop Service"
      "WinRM"  # If using for automation
    ];
    
    # Network shares to mount
    networkShares = {
      "/mnt/company-share" = {
        uncPath = "\\\\fileserver.company.com\\share";
        credentials = "/etc/smb-credentials";  # Encrypted in NixOS
        mountOptions = [ "vers=3.0" "uid=1000" "gid=100" ];
      };
    };
    
    # Windows firewall rules for WSL
    firewallRules = [
      {
        name = "WSL-SSH-Inbound";
        port = 22;
        protocol = "TCP";
        direction = "Inbound";
        action = "Allow";
      }
    ];
    
    # Windows registry settings
    registry = {
      "HKLM\\SOFTWARE\\Company\\WSL" = {
        "EnableFeatureX" = { type = "DWORD"; value = 1; };
      };
    };
    
    # Environment variables for Windows side
    environment = {
      "WSL_DISTRO_NAME" = "NixOS";
      "CUSTOM_CONFIG_PATH" = "C:\\ProgramData\\NixOS-WSL";
    };
  };
  
  # The plugin reads this configuration and implements it
}
```

**Result:** A single configuration file describes the **entire system**, both Linux and Windows sides.

### Architecture Components

#### Component 1: NixOS Configuration Module

**Location:** `/etc/nixos/modules/wsl-windows.nix`

```nix
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.wsl.windows;
in
{
  options.wsl.windows = {
    enable = mkEnableOption "Windows-side WSL plugin configuration";
    
    vhdx = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          windowsPath = mkOption {
            type = types.str;
            description = "Windows path to VHDX file";
            example = "D:\\WSL\\Data.vhdx";
          };
          
          sizeGB = mkOption {
            type = types.int;
            description = "Size in GB";
            default = 100;
          };
          
          filesystem = mkOption {
            type = types.enum [ "ext4" "btrfs" "xfs" ];
            description = "Filesystem type";
            default = "ext4";
          };
          
          autoCreate = mkOption {
            type = types.bool;
            description = "Auto-create if doesn't exist";
            default = true;
          };
          
          autoMount = mkOption {
            type = types.bool;
            description = "Auto-mount on boot";
            default = true;
          };
          
          mountOptions = mkOption {
            type = types.listOf types.str;
            description = "Mount options";
            default = [];
          };
        };
      });
      default = {};
      description = "VHDX disks to manage on Windows host";
    };
    
    requiredServices = mkOption {
      type = types.listOf types.str;
      description = "Windows services that must be running";
      default = [];
    };
    
    networkShares = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          uncPath = mkOption {
            type = types.str;
            description = "UNC path to network share";
          };
          
          credentials = mkOption {
            type = types.nullOr types.str;
            description = "Path to credentials file";
            default = null;
          };
          
          mountOptions = mkOption {
            type = types.listOf types.str;
            default = [];
          };
        };
      });
      default = {};
    };
    
    firewallRules = mkOption {
      type = types.listOf (types.submodule {
        options = {
          name = mkOption { type = types.str; };
          port = mkOption { type = types.int; };
          protocol = mkOption { type = types.str; };
          direction = mkOption { type = types.str; };
          action = mkOption { type = types.str; };
        };
      });
      default = [];
    };
  };
  
  config = mkIf cfg.enable {
    # Generate configuration file for Windows plugin
    environment.etc."wsl-windows-config.json" = {
      text = builtins.toJSON {
        inherit (cfg) vhdx requiredServices networkShares firewallRules;
      };
    };
    
    # Ensure mount points exist in Linux
    systemd.tmpfiles.rules = 
      map (mountPoint: "d ${mountPoint} 0755 root root -") 
          (attrNames cfg.vhdx);
    
    # Add fstab entries for VHDXs
    fileSystems = 
      mapAttrs' (mountPoint: vhdxCfg: 
        nameValuePair mountPoint {
          device = "/dev/disk/by-label/${baseNameOf vhdxCfg.windowsPath}";
          fsType = vhdxCfg.filesystem;
          options = vhdxCfg.mountOptions;
        }
      ) cfg.vhdx;
  };
}
```

#### Component 2: Windows Plugin DLL

**Architecture:**
```
NixOS-WSL-Plugin.dll
├── OnVMStarted()
│   ├── Read /mnt/wslg/distro/NixOS/etc/wsl-windows-config.json
│   ├── Create/verify VHDXs
│   ├── Attach VHDXs to WSL
│   ├── Verify Windows services
│   ├── Configure firewall
│   └── Set up registry
│
├── OnDistributionStarted()
│   ├── Verify distribution is NixOS
│   ├── Log successful startup
│   └── Optionally mount network shares
│
└── OnDistributionStopping()
    └── Cleanup (detach VHDXs, etc.)
```

**Key Implementation Functions:**

```cpp
// VhdxManager.cpp
class VhdxManager {
public:
    struct VhdxConfig {
        std::wstring windowsPath;
        uint64_t sizeGB;
        std::string filesystem;
        bool autoCreate;
        bool autoMount;
        std::vector<std::string> mountOptions;
    };
    
    HRESULT EnsureVhdxExists(const VhdxConfig& config) {
        // Check if VHDX exists
        if (!PathFileExists(config.windowsPath.c_str())) {
            if (!config.autoCreate) {
                return E_FAIL;
            }
            
            // Create VHDX using diskpart or Windows Storage API
            return CreateVhdx(config.windowsPath, config.sizeGB);
        }
        
        return S_OK;
    }
    
    HRESULT AttachVhdxToWsl(
        const std::wstring& vhdxPath, 
        const std::string& mountPoint,
        DWORD sessionId) 
    {
        // Use wsl.exe --mount to attach VHDX
        std::wstring cmdLine = L"wsl.exe --mount " + vhdxPath + 
                               L" --partition 1 --name " + 
                               std::wstring(mountPoint.begin(), mountPoint.end());
        
        STARTUPINFO si = {sizeof(si)};
        PROCESS_INFORMATION pi;
        
        if (!CreateProcess(NULL, (LPWSTR)cmdLine.c_str(), 
                          NULL, NULL, FALSE, 0, NULL, NULL, &si, &pi)) {
            return HRESULT_FROM_WIN32(GetLastError());
        }
        
        WaitForSingleObject(pi.hProcess, INFINITE);
        
        DWORD exitCode;
        GetExitCodeProcess(pi.hProcess, &exitCode);
        
        CloseHandle(pi.hProcess);
        CloseHandle(pi.hThread);
        
        return exitCode == 0 ? S_OK : E_FAIL;
    }
    
private:
    HRESULT CreateVhdx(const std::wstring& path, uint64_t sizeGB) {
        // Create diskpart script
        std::wstring script = 
            L"create vdisk file=\"" + path + L"\" "
            L"maximum=" + std::to_wstring(sizeGB * 1024) + L" "
            L"type=expandable\n"
            L"attach vdisk\n"
            L"create partition primary\n"
            L"format fs=ntfs quick\n"
            L"detach vdisk\n";
        
        // Write script to temp file
        wchar_t tempPath[MAX_PATH];
        GetTempPath(MAX_PATH, tempPath);
        std::wstring scriptPath = std::wstring(tempPath) + L"diskpart_script.txt";
        
        std::wofstream scriptFile(scriptPath);
        scriptFile << script;
        scriptFile.close();
        
        // Execute diskpart
        std::wstring cmdLine = L"diskpart /s " + scriptPath;
        
        STARTUPINFO si = {sizeof(si)};
        PROCESS_INFORMATION pi;
        
        if (!CreateProcess(NULL, (LPWSTR)cmdLine.c_str(),
                          NULL, NULL, FALSE, 0, NULL, NULL, &si, &pi)) {
            return HRESULT_FROM_WIN32(GetLastError());
        }
        
        WaitForSingleObject(pi.hProcess, INFINITE);
        
        DWORD exitCode;
        GetExitCodeProcess(pi.hProcess, &exitCode);
        
        CloseHandle(pi.hProcess);
        CloseHandle(pi.hThread);
        DeleteFile(scriptPath.c_str());
        
        return exitCode == 0 ? S_OK : E_FAIL;
    }
};

// ServiceManager.cpp
class ServiceManager {
public:
    HRESULT VerifyServicesRunning(
        const std::vector<std::wstring>& serviceNames) 
    {
        SC_HANDLE scm = OpenSCManager(NULL, NULL, SC_MANAGER_CONNECT);
        if (!scm) return HRESULT_FROM_WIN32(GetLastError());
        
        for (const auto& serviceName : serviceNames) {
            SC_HANDLE service = OpenService(
                scm, serviceName.c_str(), SERVICE_QUERY_STATUS);
            
            if (!service) {
                CloseServiceHandle(scm);
                LogError(L"Service not found: " + serviceName);
                return E_FAIL;
            }
            
            SERVICE_STATUS status;
            if (!QueryServiceStatus(service, &status) ||
                status.dwCurrentState != SERVICE_RUNNING) {
                
                CloseServiceHandle(service);
                CloseServiceHandle(scm);
                LogError(L"Service not running: " + serviceName);
                return E_FAIL;
            }
            
            CloseServiceHandle(service);
        }
        
        CloseServiceHandle(scm);
        return S_OK;
    }
    
    HRESULT StartServiceIfNeeded(const std::wstring& serviceName) {
        SC_HANDLE scm = OpenSCManager(
            NULL, NULL, SC_MANAGER_CONNECT);
        if (!scm) return HRESULT_FROM_WIN32(GetLastError());
        
        SC_HANDLE service = OpenService(
            scm, serviceName.c_str(), 
            SERVICE_START | SERVICE_QUERY_STATUS);
        
        if (!service) {
            CloseServiceHandle(scm);
            return E_FAIL;
        }
        
        SERVICE_STATUS status;
        QueryServiceStatus(service, &status);
        
        if (status.dwCurrentState != SERVICE_RUNNING) {
            if (!StartService(service, 0, NULL)) {
                DWORD error = GetLastError();
                CloseServiceHandle(service);
                CloseServiceHandle(scm);
                return HRESULT_FROM_WIN32(error);
            }
            
            // Wait for service to start
            for (int i = 0; i < 30; i++) {
                Sleep(1000);
                QueryServiceStatus(service, &status);
                if (status.dwCurrentState == SERVICE_RUNNING) break;
            }
        }
        
        CloseServiceHandle(service);
        CloseServiceHandle(scm);
        
        return S_OK;
    }
};

// FirewallManager.cpp
class FirewallManager {
public:
    struct FirewallRule {
        std::wstring name;
        int port;
        std::wstring protocol;
        std::wstring direction;
        std::wstring action;
    };
    
    HRESULT ConfigureFirewallRules(
        const std::vector<FirewallRule>& rules) 
    {
        for (const auto& rule : rules) {
            HRESULT hr = AddFirewallRule(rule);
            if (FAILED(hr)) {
                LogError(L"Failed to add firewall rule: " + rule.name);
                return hr;
            }
        }
        return S_OK;
    }
    
private:
    HRESULT AddFirewallRule(const FirewallRule& rule) {
        // Use Windows Firewall COM API
        INetFwPolicy2* policy = nullptr;
        HRESULT hr = CoCreateInstance(
            __uuidof(NetFwPolicy2),
            NULL,
            CLSCTX_INPROC_SERVER,
            __uuidof(INetFwPolicy2),
            (void**)&policy);
        
        if (FAILED(hr)) return hr;
        
        INetFwRules* rules = nullptr;
        hr = policy->get_Rules(&rules);
        if (FAILED(hr)) {
            policy->Release();
            return hr;
        }
        
        INetFwRule* fwRule = nullptr;
        hr = CoCreateInstance(
            __uuidof(NetFwRule),
            NULL,
            CLSCTX_INPROC_SERVER,
            __uuidof(INetFwRule),
            (void**)&fwRule);
        
        if (SUCCEEDED(hr)) {
            fwRule->put_Name(_bstr_t(rule.name.c_str()));
            fwRule->put_Protocol(
                rule.protocol == L"TCP" ? NET_FW_IP_PROTOCOL_TCP 
                                       : NET_FW_IP_PROTOCOL_UDP);
            fwRule->put_LocalPorts(_bstr_t(std::to_wstring(rule.port).c_str()));
            fwRule->put_Direction(
                rule.direction == L"Inbound" ? NET_FW_RULE_DIR_IN 
                                             : NET_FW_RULE_DIR_OUT);
            fwRule->put_Action(
                rule.action == L"Allow" ? NET_FW_ACTION_ALLOW 
                                       : NET_FW_ACTION_BLOCK);
            fwRule->put_Enabled(VARIANT_TRUE);
            
            hr = rules->Add(fwRule);
            fwRule->Release();
        }
        
        rules->Release();
        policy->Release();
        
        return hr;
    }
};

// Main plugin implementation
class NixOSWslPlugin {
private:
    const WSLPluginAPIV1* m_api;
    VhdxManager m_vhdxManager;
    ServiceManager m_serviceManager;
    FirewallManager m_firewallManager;
    
    struct PluginConfig {
        std::map<std::string, VhdxManager::VhdxConfig> vhdxDisks;
        std::vector<std::wstring> requiredServices;
        std::vector<FirewallManager::FirewallRule> firewallRules;
        // ... other config
    };
    
    HRESULT LoadConfiguration(
        DWORD sessionId, 
        const std::wstring& distroName,
        PluginConfig& config) 
    {
        // Execute command in WSL to read config file
        const char* args[] = {
            "/bin/sh", "-c",
            "cat /etc/wsl-windows-config.json 2>/dev/null || echo '{}'",
            nullptr
        };
        
        SOCKET sock;
        HRESULT hr = m_api->ExecuteBinary(sessionId, args[0], args, &sock);
        if (FAILED(hr)) return hr;
        
        // Read JSON output
        std::vector<char> buffer(65536);
        int bytesRead = recv(sock, buffer.data(), buffer.size(), 0);
        closesocket(sock);
        
        if (bytesRead <= 0) return E_FAIL;
        
        // Parse JSON (use nlohmann::json or similar)
        std::string jsonStr(buffer.data(), bytesRead);
        try {
            auto json = nlohmann::json::parse(jsonStr);
            
            // Parse VHDX config
            if (json.contains("vhdx")) {
                for (auto& [mountPoint, vhdxData] : json["vhdx"].items()) {
                    VhdxManager::VhdxConfig vhdx;
                    vhdx.windowsPath = 
                        std::wstring(vhdxData["windowsPath"].get<std::string>().begin(),
                                   vhdxData["windowsPath"].get<std::string>().end());
                    vhdx.sizeGB = vhdxData["sizeGB"].get<uint64_t>();
                    vhdx.filesystem = vhdxData["filesystem"].get<std::string>();
                    vhdx.autoCreate = vhdxData["autoCreate"].get<bool>();
                    vhdx.autoMount = vhdxData["autoMount"].get<bool>();
                    
                    config.vhdxDisks[mountPoint] = vhdx;
                }
            }
            
            // Parse required services
            if (json.contains("requiredServices")) {
                for (const auto& service : json["requiredServices"]) {
                    std::string svcName = service.get<std::string>();
                    config.requiredServices.push_back(
                        std::wstring(svcName.begin(), svcName.end()));
                }
            }
            
            // Parse firewall rules
            if (json.contains("firewallRules")) {
                for (const auto& rule : json["firewallRules"]) {
                    FirewallManager::FirewallRule fwRule;
                    std::string name = rule["name"].get<std::string>();
                    fwRule.name = std::wstring(name.begin(), name.end());
                    fwRule.port = rule["port"].get<int>();
                    
                    std::string proto = rule["protocol"].get<std::string>();
                    fwRule.protocol = std::wstring(proto.begin(), proto.end());
                    
                    std::string dir = rule["direction"].get<std::string>();
                    fwRule.direction = std::wstring(dir.begin(), dir.end());
                    
                    std::string act = rule["action"].get<std::string>();
                    fwRule.action = std::wstring(act.begin(), act.end());
                    
                    config.firewallRules.push_back(fwRule);
                }
            }
            
        } catch (const std::exception& e) {
            LogError(std::string("JSON parse error: ") + e.what());
            return E_FAIL;
        }
        
        return S_OK;
    }
    
public:
    HRESULT OnVMStarted(
        const WSLSessionInformation* session,
        const WSLVmCreationSettings* settings) 
    {
        Log("OnVMStarted called");
        
        // We don't know which distribution will start yet,
        // so we can't load distribution-specific config.
        // However, we can do VM-level setup here.
        
        return S_OK;
    }
    
    HRESULT OnDistributionStarted(
        const WSLSessionInformation* session,
        const WSLDistributionInformation* distribution) 
    {
        // Convert distribution name
        std::wstring distroName = distribution->Name;
        
        // Only act on NixOS distributions
        if (distroName.find(L"NixOS") == std::wstring::npos) {
            return S_OK;
        }
        
        Log("NixOS distribution starting: " + 
            std::string(distroName.begin(), distroName.end()));
        
        // Load configuration from NixOS
        PluginConfig config;
        HRESULT hr = LoadConfiguration(
            session->SessionId, distroName, config);
        
        if (FAILED(hr)) {
            LogError("Failed to load configuration");
            // Don't fail startup, just log
            return S_OK;
        }
        
        // Verify required Windows services
        hr = m_serviceManager.VerifyServicesRunning(
            config.requiredServices);
        if (FAILED(hr)) {
            LogError("Required services not running");
            return E_FAIL; // Block distribution startup
        }
        
        // Create and attach VHDXs
        for (const auto& [mountPoint, vhdxConfig] : config.vhdxDisks) {
            hr = m_vhdxManager.EnsureVhdxExists(vhdxConfig);
            if (FAILED(hr)) {
                LogError("Failed to create VHDX: " + mountPoint);
                return E_FAIL;
            }
            
            if (vhdxConfig.autoMount) {
                hr = m_vhdxManager.AttachVhdxToWsl(
                    vhdxConfig.windowsPath, 
                    mountPoint,
                    session->SessionId);
                
                if (FAILED(hr)) {
                    LogError("Failed to attach VHDX: " + mountPoint);
                    return E_FAIL;
                }
            }
        }
        
        // Configure firewall
        hr = m_firewallManager.ConfigureFirewallRules(
            config.firewallRules);
        if (FAILED(hr)) {
            LogError("Failed to configure firewall");
            // Don't fail startup for firewall issues
        }
        
        Log("NixOS distribution setup complete");
        return S_OK;
    }
};

// Plugin entry point
EXTERN_C __declspec(dllexport)
HRESULT WSLPLUGINAPI_ENTRYPOINTV1(
    const WSLPluginAPIV1* api,
    WSLPluginHooksV1* hooks)
{
    // Initialize COM for Windows Firewall API
    CoInitializeEx(NULL, COINIT_MULTITHREADED);
    
    // Create plugin instance (stored in global for hook callbacks)
    static NixOSWslPlugin plugin;
    plugin.Initialize(api);
    
    // Register hooks
    hooks->OnVMStarted = [](
        const WSLSessionInformation* session,
        const WSLVmCreationSettings* settings) -> HRESULT 
    {
        return plugin.OnVMStarted(session, settings);
    };
    
    hooks->OnDistributionStarted = [](
        const WSLSessionInformation* session,
        const WSLDistributionInformation* distribution) -> HRESULT 
    {
        return plugin.OnDistributionStarted(session, distribution);
    };
    
    return S_OK;
}
```

#### Component 3: Distribution Package

**Package Structure:**
```
nixos-wsl-installer.exe
├── Embedded Resources:
│   ├── NixOS-WSL.tar.gz (NixOS rootfs)
│   ├── NixOS-WSL-Plugin.dll (signed)
│   └── install-config.json
│
└── Installer Logic:
    1. Check prerequisites (Windows version, WSL installed)
    2. Register plugin in Windows registry
    3. Import NixOS distribution using wsl.exe --import
    4. Configure default settings
    5. Launch initial setup wizard
```

**Installer Implementation (Inno Setup or WiX):**

```nsi
; Example Inno Setup script
[Setup]
AppName=NixOS-WSL
AppVersion=1.0
DefaultDirName={autopf}\NixOS-WSL
DisableProgramGroupPage=yes
OutputBaseFilename=nixos-wsl-setup
Compression=lzma2
SolidCompression=yes
PrivilegesRequired=admin

[Files]
Source: "NixOS-WSL.tar.gz"; DestDir: "{tmp}"; Flags: deleteafterinstall
Source: "NixOS-WSL-Plugin.dll"; DestDir: "{app}"

[Code]
function InitializeSetup(): Boolean;
var
  ResultCode: Integer;
begin
  // Check if WSL is installed
  if not Exec('wsl.exe', '--version', '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
  begin
    MsgBox('WSL is not installed. Please install WSL first.', mbError, MB_OK);
    Result := False;
    Exit;
  end;
  
  Result := True;
end;

procedure RegisterPlugin();
var
  PluginPath: String;
begin
  PluginPath := ExpandConstant('{app}\NixOS-WSL-Plugin.dll');
  
  // Register plugin in registry
  RegWriteStringValue(HKLM, 
    'SOFTWARE\Microsoft\Windows\CurrentVersion\Lxss\Plugins',
    'NixOS-WSL-Plugin',
    PluginPath);
end;

procedure ImportDistribution();
var
  TarPath, InstallPath: String;
  ResultCode: Integer;
begin
  TarPath := ExpandConstant('{tmp}\NixOS-WSL.tar.gz');
  InstallPath := ExpandConstant('{localappdata}\NixOS-WSL');
  
  // Import distribution
  Exec('wsl.exe', 
    '--import NixOS "' + InstallPath + '" "' + TarPath + '"',
    '', SW_SHOW, ewWaitUntilTerminated, ResultCode);
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    RegisterPlugin();
    ImportDistribution();
    
    // Restart WSL service to load plugin
    Exec('net', 'stop wslservice', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    Exec('net', 'start wslservice', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  end;
end;
```

### Configuration Flow

**Complete Lifecycle:**

```
1. Developer writes NixOS configuration:
   ┌────────────────────────────────────┐
   │ /etc/nixos/configuration.nix       │
   │                                    │
   │ wsl.windows = {                    │
   │   vhdx = {                         │
   │     "/mnt/data" = {                │
   │       windowsPath = "D:\\...";     │
   │       sizeGB = 100;                │
   │     };                             │
   │   };                               │
   │ }                                  │
   └────────────────────────────────────┘
                  ↓
2. Run nixos-rebuild:
   ┌────────────────────────────────────┐
   │ $ nixos-rebuild switch             │
   └────────────────────────────────────┘
                  ↓
3. NixOS builds system configuration:
   ┌────────────────────────────────────┐
   │ - Generates /etc/wsl-windows-      │
   │   config.json from Nix options     │
   │ - Creates mount points             │
   │ - Updates systemd units            │
   └────────────────────────────────────┘
                  ↓
4. User runs: wsl -d NixOS
   ┌────────────────────────────────────┐
   │ Windows: wsl.exe                   │
   │    ↓                               │
   │ Windows: wslservice                │
   │    ↓                               │
   │ Plugin: OnVMStarted()              │
   └────────────────────────────────────┘
                  ↓
5. Plugin reads configuration:
   ┌────────────────────────────────────┐
   │ Plugin: ExecuteBinary()            │
   │   "cat /etc/wsl-windows-config"    │
   │    ↓                               │
   │ Plugin parses JSON                 │
   └────────────────────────────────────┘
                  ↓
6. Plugin implements Windows-side:
   ┌────────────────────────────────────┐
   │ - Create D:\WSL\Data.vhdx          │
   │ - wsl.exe --mount (attach VHDX)    │
   │ - Verify Windows services          │
   │ - Configure firewall               │
   └────────────────────────────────────┘
                  ↓
7. Distribution starts:
   ┌────────────────────────────────────┐
   │ Linux: /sbin/init (systemd-shim)   │
   │    ↓                               │
   │ Plugin: OnDistributionStarted()    │
   │    ↓                               │
   │ Linux: systemd-shim activates      │
   │    ↓                               │
   │ Linux: systemd takes over          │
   │    ↓                               │
   │ Linux: /mnt/data is mounted        │
   │        (from fstab generated by    │
   │         NixOS module)              │
   └────────────────────────────────────┘
                  ↓
8. User gets shell with everything ready:
   ┌────────────────────────────────────┐
   │ $ wsl -d NixOS                     │
   │ $ df -h /mnt/data                  │
   │ Filesystem      Size  Used Avail   │
   │ /dev/sdc1       100G   10G   90G   │
   └────────────────────────────────────┘
```

### Benefits of This Architecture

**1. Single Source of Truth**
```nix
# Everything in one file
{ config, ... }: {
  # Linux configuration
  users.users.alice = { ... };
  
  # Windows configuration
  wsl.windows.vhdx."/mnt/data" = { ... };
}
```

**2. Version Control**
```bash
$ git diff
- wsl.windows.vhdx."/mnt/data".sizeGB = 100;
+ wsl.windows.vhdx."/mnt/data".sizeGB = 200;

$ nixos-rebuild switch
# Windows VHDX is automatically resized
```

**3. Reproducibility**
```bash
# Clone configuration to new machine
$ git clone git@github.com:user/nixos-config
$ nixos-rebuild switch

# Plugin automatically:
# - Creates required VHDXs
# - Configures Windows firewall
# - Sets up services
```

**4. Documentation as Code**
```nix
# Configuration is self-documenting
wsl.windows.vhdx."/mnt/projects" = {
  windowsPath = "C:\\Users\\Alice\\WSL\\Projects.vhdx";
  sizeGB = 50;
  # This disk stores active development projects
  # and is backed up nightly by Windows Backup
};
```

**5. Error Prevention**
```nix
# Type checking prevents errors
wsl.windows.vhdx."/mnt/data" = {
  windowsPath = "D:\\WSL\\Data.vhdx";
  sizeGB = "100";  # ← Build error: expecting int
};
```

### Advanced Use Cases

#### Use Case 1: Multi-Disk Development Environment

```nix
{ config, pkgs, ... }:
{
  wsl.windows = {
    vhdx = {
      # Fast NVMe for Nix store
      "/nix/store" = {
        windowsPath = "E:\\WSL\\NixOS-Store.vhdx";
        sizeGB = 500;
        filesystem = "ext4";
        mountOptions = [ "noatime" "discard" ];
      };
      
      # Large HDD for data
      "/home/data" = {
        windowsPath = "D:\\WSL\\UserData.vhdx";
        sizeGB = 2000;
        filesystem = "btrfs";
        mountOptions = [ "compress=zstd" ];
      };
      
      # RAM disk for builds
      "/tmp/build" = {
        windowsPath = "R:\\WSL\\BuildCache.vhdx";
        sizeGB = 20;
        filesystem = "ext4";
        mountOptions = [ "noatime" ];
      };
    };
    
    # Required for development
    requiredServices = [
      "Docker Desktop Service"
      "ssh-agent"  # For Git authentication
    ];
    
    # Allow incoming SSH connections
    firewallRules = [
      {
        name = "WSL-SSH";
        port = 22;
        protocol = "TCP";
        direction = "Inbound";
        action = "Allow";
      }
    ];
  };
  
  # Linux-side configuration leverages the Windows setup
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "no";
  };
  
  # Build cache on fast disk
  nix.settings = {
    build-dir = "/tmp/build";
  };
}
```

**Result:** Developer runs `nixos-rebuild switch`, and the entire environment is automatically configured across Windows and Linux.

#### Use Case 2: Corporate Compliance

```nix
{ config, lib, ... }:

let
  # Enforce corporate policies
  isCorporateNetwork = true;  # Detected by plugin
in
{
  wsl.windows = {
    # Require corporate VPN
    requiredServices = lib.mkIf isCorporateNetwork [
      "CiscoAnyConnectVPNAgent"
    ];
    
    # Block external access when on corporate network
    firewallRules = lib.mkIf isCorporateNetwork [
      {
        name = "Block-WSL-External";
        port = 0;  # All ports
        protocol = "TCP";
        direction = "Outbound";
        action = "Block";
        # Except internal networks (configured in plugin)
      }
    ];
    
    # Mount encrypted corporate share
    networkShares = lib.mkIf isCorporateNetwork {
      "/mnt/corporate" = {
        uncPath = "\\\\fileserver.corp.com\\share";
        credentials = "/etc/corporate-smb-creds";
      };
    };
  };
  
  # Enforce Linux-side policies
  security.audit.enable = true;
  
  services.fail2ban.enable = true;
}
```

**Result:** Corporate policies are enforced consistently across all developer machines.

#### Use Case 3: Automated Backup Integration

```nix
{ config, ... }:
{
  wsl.windows = {
    vhdx = {
      "/home/myuser" = {
        windowsPath = "D:\\WSL\\NixOS-Home.vhdx";
        sizeGB = 100;
        
        # Plugin can add VHDX to Windows Backup schedule
        windowsBackup = {
          enable = true;
          schedule = "daily";
          retentionDays = 30;
        };
      };
    };
  };
  
  # Linux-side backup to cloud
  services.borgbackup.jobs.home = {
    paths = [ "/home/myuser" ];
    repo = "borgbase:repo";
    schedule = "hourly";
  };
}
```

**Result:** Both Windows-level (VHDX) and Linux-level (file) backups are configured declaratively.

---

## Practical Applications

### Use Case 1: Windows Dependency Enforcement (Current)

**Scenario**: Ensure specific Windows services are running before WSL starts.

**Implementation**:
```cpp
HRESULT OnVmStarted(
    const WSLSessionInformation* Session,
    const WSLVmCreationSettings* Settings)
{
    // Check required services
    const wchar_t* requiredServices[] = {
        L"MyBackupService",
        L"MyVPNService",
        L"MySecurityService"
    };
    
    SC_HANDLE scm = OpenSCManager(NULL, NULL, SC_MANAGER_CONNECT);
    if (!scm) return E_FAIL;
    
    for (auto& serviceName : requiredServices) {
        SC_HANDLE service = OpenService(scm, serviceName, 
                                       SERVICE_QUERY_STATUS);
        if (!service) {
            CloseServiceHandle(scm);
            return HRESULT_FROM_WIN32(GetLastError());
        }
        
        SERVICE_STATUS status;
        if (!QueryServiceStatus(service, &status) ||
            status.dwCurrentState != SERVICE_RUNNING) {
            
            g_logfile << "Required service not running: " 
                     << serviceName << std::endl;
            
            CloseServiceHandle(service);
            CloseServiceHandle(scm);
            return E_FAIL; // Abort WSL startup
        }
        
        CloseServiceHandle(service);
    }
    
    CloseServiceHandle(scm);
    return S_OK;
}
```

**Result**: User runs `wsl`, services are verified, WSL only starts if all pass.

### Use Case 2: Declarative VHDX Management (Enhanced with NixOS)

**Scenario**: Developer wants additional storage on D: drive for data.

**Current Manual Approach:**
```powershell
# Manual steps (error-prone)
PS> New-VHD -Path D:\WSL\Data.vhdx -SizeBytes 100GB
PS> wsl --mount D:\WSL\Data.vhdx
PS> wsl -d NixOS
$ sudo mkfs.ext4 /dev/sdc
$ sudo mkdir /mnt/data
$ sudo mount /dev/sdc /mnt/data
$ echo "/dev/sdc /mnt/data ext4 defaults 0 0" | sudo tee -a /etc/fstab
```

**New Declarative Approach:**
```nix
# In /etc/nixos/configuration.nix
{
  wsl.windows.vhdx."/mnt/data" = {
    windowsPath = "D:\\WSL\\Data.vhdx";
    sizeGB = 100;
    filesystem = "ext4";
    autoCreate = true;
    autoMount = true;
  };
}
```

```bash
$ nixos-rebuild switch
$ wsl --shutdown
$ wsl -d NixOS
# /mnt/data is automatically available
```

**Result**: Plugin handles all Windows-side operations; NixOS handles Linux-side.

### Use Case 3: Development Environment Bootstrap

**Scenario**: New developer onboarding with complete environment setup.

**Implementation:**
```nix
{ config, pkgs, ... }:
{
  wsl.windows = {
    # Separate disk for node_modules (better performance)
    vhdx."/home/dev/projects/.cache" = {
      windowsPath = "E:\\WSL\\DevCache.vhdx";
      sizeGB = 50;
      filesystem = "ext4";
      mountOptions = [ "noatime" ];
    };
    
    # Required Windows services
    requiredServices = [
      "Docker Desktop Service"
      "ssh-agent"
    ];
    
    # Network share for shared resources
    networkShares."/mnt/company" = {
      uncPath = "\\\\fileserver\\engineering";
      credentials = "/etc/smb-credentials";
    };
    
    # Allow web development
    firewallRules = [
      {
        name = "WSL-Web-Dev";
        port = 3000;
        protocol = "TCP";
        direction = "Inbound";
        action = "Allow";
      }
    ];
  };
  
  # Developer tools
  environment.systemPackages = with pkgs; [
    git nodejs python3 go rustc
    docker-compose kubectl
  ];
  
  # Pre-configure Git
  programs.git = {
    enable = true;
    config = {
      user.name = "New Developer";
      user.email = "dev@company.com";
    };
  };
}
```

**Process:**
```bash
# On new machine:
$ git clone company-repo/nixos-dev-config
$ cd nixos-dev-config
$ nixos-rebuild switch --flake .

# Everything is set up:
# - VHDXs created and mounted
# - Windows services verified
# - Network shares connected
# - Firewall configured
# - Development tools installed
# - Git configured
```

**Result**: Zero-touch developer onboarding.

### Use Case 4: Dynamic Resource Allocation

**Scenario**: Automatically allocate resources based on project requirements.

**Implementation:**
```nix
{ config, lib, ... }:

let
  # Detect active project
  currentProject = builtins.readFile /home/dev/.current-project;
  
  # Project-specific resources
  projectResources = {
    "ml-training" = {
      vhdxSize = 500;  # Large dataset storage
      requiredServices = [ "NVIDIA GPU Service" ];
    };
    
    "web-app" = {
      vhdxSize = 50;
      requiredServices = [ "Docker Desktop Service" ];
    };
    
    "embedded" = {
      vhdxSize = 20;
      requiredServices = [ "USB Serial Driver" ];
    };
  };
  
  resources = projectResources.${currentProject};
in
{
  wsl.windows = {
    vhdx."/home/dev/workspace" = {
      windowsPath = "D:\\WSL\\${currentProject}.vhdx";
      sizeGB = resources.vhdxSize;
      filesystem = "ext4";
      autoCreate = true;
    };
    
    requiredServices = resources.requiredServices;
  };
}
```

**Result**: Resources automatically adjust when switching projects.

---

## Implementation Roadmap

### Phase 1: Proof of Concept (Weeks 1-4)

**Goals:**
- Basic plugin that reads NixOS configuration
- VHDX creation and attachment
- Simple service verification

**Deliverables:**
```
1. Basic plugin DLL with:
   - OnVMStarted() implementation
   - JSON configuration parsing
   - VHDX creation via diskpart
   - Service verification

2. NixOS module with:
   - wsl.windows.vhdx option
   - wsl.windows.requiredServices option
   - JSON generation

3. Test suite:
   - Plugin loading test
   - Configuration parsing test
   - VHDX creation test
```

**Success Criteria:**
- Plugin loads without crashing WSL
- Can create and attach one VHDX
- Can read NixOS configuration

### Phase 2: Core Functionality (Weeks 5-8)

**Goals:**
- Full VHDX management
- Firewall configuration
- Network share mounting
- Error handling and logging

**Deliverables:**
```
1. Enhanced plugin with:
   - Multiple VHDX support
   - Windows Firewall API integration
   - Network share mounting
   - Comprehensive error handling
   - Event log integration

2. Complete NixOS module:
   - All configuration options
   - Type checking
   - Documentation
   - Example configurations

3. Installer package:
   - Signed DLL
   - Registry installation
   - WSL distribution import
```

**Success Criteria:**
- Can manage 3+ VHDXs simultaneously
- Firewall rules apply correctly
- Network shares mount reliably
- Errors are logged to Windows Event Log

### Phase 3: Polish and Distribution (Weeks 9-12)

**Goals:**
- Code signing certificate
- Installer wizard
- Documentation
- Community testing

**Deliverables:**
```
1. Production-ready plugin:
   - Signed with valid certificate
   - Performance optimized (< 500ms startup)
   - Extensive error messages
   - Recovery mechanisms

2. Distribution package:
   - Professional installer (Inno Setup/WiX)
   - Configuration wizard
   - Integration tests

3. Documentation:
   - User guide
   - Administrator guide
   - API documentation
   - Troubleshooting guide

4. Community release:
   - GitHub repository
   - Release announcement
   - Example configurations
   - Video tutorials
```

**Success Criteria:**
- Successfully installs on Windows 10/11
- < 5% support ticket rate
- Positive community feedback
- Working on 100+ test machines

### Phase 4: Advanced Features (Weeks 13+)

**Goals:**
- Dynamic resource management
- Cloud integration
- Monitoring and telemetry
- Advanced policies

**Deliverables:**
```
1. Advanced plugin features:
   - Dynamic VHDX resizing
   - Cloud storage integration (Azure, S3)
   - Performance monitoring
   - Automatic backup integration

2. Enterprise features:
   - Group Policy support
   - Centralized configuration management
   - Compliance reporting
   - Multi-machine orchestration

3. Integration ecosystem:
   - VSCode extension
   - PowerShell module
   - Terraform provider
   - Ansible module
```

---

## Technical Challenges and Solutions

### Challenge 1: Plugin Signing

**Problem**: Windows requires plugins to be digitally signed.

**Solutions:**
- **Development**: Use test signing mode
  ```powershell
  PS> bcdedit /set testsigning on
  ```

- **Production**: Obtain code signing certificate
  - EV (Extended Validation) certificate recommended
  - Options: DigiCert, Sectigo, GlobalSign
  - Cost: $200-600/year

- **Alternative**: Self-signed for organization
  ```powershell
  PS> New-SelfSignedCertificate -Type CodeSigningCert
  PS> Add-Certificate -FilePath cert.cer -CertStoreLocation Cert:\LocalMachine\TrustedPublisher
  ```

### Challenge 2: Configuration Synchronization

**Problem**: How does the Windows plugin know about NixOS changes?

**Solutions:**

**Solution A: Pull on Startup (Implemented Above)**
```
OnDistributionStarted() → Read /etc/wsl-windows-config.json
```
- ✅ Simple
- ✅ Always current
- ❌ Only updates on WSL restart

**Solution B: File Watcher**
```cpp
// Plugin watches Windows directory
HANDLE hDir = CreateFile("C:\\ProgramData\\NixOS-WSL", ...);
ReadDirectoryChangesW(hDir, ...);
```
- ✅ Real-time updates
- ❌ More complex
- ❌ Requires background service

**Solution C: Windows Service Component**
```
NixOS-WSL-Service.exe (Windows service)
  ↓
Watches for config changes
  ↓
Applies changes without WSL restart
```
- ✅ Most flexible
- ✅ Can update without restart
- ❌ More components to maintain

**Recommendation**: Start with Solution A (pull on startup), evolve to C if needed.

### Challenge 3: Error Recovery

**Problem**: What if VHDX creation fails midway through startup?

**Solutions:**

**Rollback Mechanism:**
```cpp
class TransactionManager {
    std::vector<std::function<void()>> rollbacks;
    
public:
    void AddRollback(std::function<void()> rollback) {
        rollbacks.push_back(rollback);
    }
    
    void Commit() {
        rollbacks.clear();
    }
    
    ~TransactionManager() {
        // Rollback on destruction (if not committed)
        for (auto it = rollbacks.rbegin(); it != rollbacks.rend(); ++it) {
            (*it)();
        }
    }
};

HRESULT OnDistributionStarted(...) {
    TransactionManager tx;
    
    // Create VHDX
    hr = CreateVhdx(...);
    if (FAILED(hr)) return hr;
    tx.AddRollback([](){ DeleteVhdx(...); });
    
    // Attach VHDX
    hr = AttachVhdx(...);
    if (FAILED(hr)) return hr;  // Rollback occurs
    tx.AddRollback([](){ DetachVhdx(...); });
    
    // Configure firewall
    hr = ConfigureFirewall(...);
    if (FAILED(hr)) return hr;  // Rollback occurs
    tx.AddRollback([](){ RemoveFirewallRules(...); });
    
    // Success - commit changes
    tx.Commit();
    return S_OK;
}
```

### Challenge 4: Performance

**Problem**: Plugin must complete quickly (< 1 second).

**Solutions:**

**Optimization Strategies:**
```cpp
// 1. Parallel operations
std::vector<std::future<HRESULT>> futures;
for (const auto& vhdx : vhdxConfigs) {
    futures.push_back(std::async(std::launch::async, [&]() {
        return EnsureVhdxExists(vhdx);
    }));
}

// 2. Caching
class VhdxCache {
    std::map<std::wstring, bool> existsCache;
public:
    bool Exists(const std::wstring& path) {
        auto it = existsCache.find(path);
        if (it != existsCache.end()) return it->second;
        
        bool exists = PathFileExists(path.c_str());
        existsCache[path] = exists;
        return exists;
    }
};

// 3. Lazy initialization
if (vhdxConfig.autoCreate && !VhdxExists(path)) {
    // Only create if needed
    CreateVhdx(path, size);
}
```

**Benchmarks:**
```
Target performance:
- Configuration parsing: < 50ms
- Service checks: < 100ms per service
- VHDX attachment: < 200ms per disk
- Firewall config: < 100ms total
Total: < 500ms for typical setup
```

### Challenge 5: Security

**Problem**: Plugin runs as SYSTEM and can do anything.

**Solutions:**

**Defense in Depth:**
```cpp
class SecurityManager {
public:
    // 1. Validate paths
    bool IsPathSafe(const std::wstring& path) {
        // Prevent path traversal
        if (path.find(L"..") != std::wstring::npos) return false;
        
        // Only allow specific drives
        wchar_t drive = path[0];
        if (drive != L'C' && drive != L'D' && drive != L'E') return false;
        
        // Prevent system path modification
        if (path.find(L"Windows") != std::wstring::npos) return false;
        
        return true;
    }
    
    // 2. Validate service names
    bool IsServiceWhitelisted(const std::wstring& name) {
        static const std::set<std::wstring> whitelist = {
            L"Docker Desktop Service",
            L"ssh-agent",
            // ... known safe services
        };
        return whitelist.count(name) > 0;
    }
    
    // 3. Validate disk sizes
    bool IsDiskSizeReasonable(uint64_t sizeGB) {
        return sizeGB > 0 && sizeGB < 5000;  // < 5TB
    }
    
    // 4. Audit logging
    void LogSecurityEvent(const std::string& event) {
        // Log to Windows Security Event Log
        HANDLE hEventLog = RegisterEventSource(NULL, L"NixOS-WSL-Plugin");
        if (hEventLog) {
            ReportEvent(hEventLog, EVENTLOG_INFORMATION_TYPE, 
                       0, 1000, NULL, 1, 0, &event, NULL);
            DeregisterEventSource(hEventLog);
        }
    }
};
```

---

## Summary: Complete Boot Timeline with NixOS Plugin

### Consolidated Timeline with All Synchronization Points

```
TIME | WINDOWS SIDE                    | LINUX SIDE                  | PLUGIN HOOKS
-----|--------------------------------|-----------------------------|-----------------
T+0  | User: wsl.exe -d NixOS        |                            |
     | wsl.exe → wslservice IPC      |                            |
     |                               |                            |
T+1  | Plugin DLL loaded             |                            | ★ ENTRY POINT
     | WSLPLUGINAPI_ENTRYPOINTV1()   |                            |
     |                               |                            |
T+2  | wslhost.exe spawned           |                            |
     | Hyper-V VM allocated          |                            |
     |                               |                            |
T+3  | Kernel loaded into VM memory  | Kernel decompresses        |
     |                               | start_kernel()             |
     |                               |                            |
T+4  |                               | mm_init(), sched_init()    |
     |                               | Initramfs extracted        |
     |                               | Root namespace created     |
     |                               |                            |
T+5  | ★ BLOCKING WAIT ★             |                            | ★ OnVMStarted()
     | [WSL waits for return]        | [VM idle, waiting]         | [Could do VM-level
     |                               |                            |  setup here]
     |                               |                            |
T+6  | OnVMStarted() returned S_OK   |                            |
     | Continue boot process         |                            |
     |                               |                            |
T+7  | Mount distribution rootfs     | Rootfs mounted             |
     | Create distribution namespace | PID namespace created      |
     |                               |                            |
T+8  | Spawn init process            | PID 1: /sbin/init starts   |
     |                               | (systemd-shim)             |
     |                               |                            |
T+9  | ★ BLOCKING WAIT ★             | [Init process running      | ★ OnDistribution-
     | [WSL waits for return]        |  but waiting]              |    Started()
     |                               |                            | [Read NixOS config]
     |                               |                            | [Create VHDXs]
     |                               |                            | [Attach VHDXs]
     |                               |                            | [Verify services]
     |                               |                            | [Configure firewall]
     |                               |                            | [Return S_OK]
     |                               |                            |
T+10 | OnDistributionStarted() OK    |                            |
     | VHDXs now attached to WSL     |                            |
     |                               |                            |
T+11 |                               | systemd-shim activation:   |
     |                               |   1. Run activate scripts  |
     |                               |   2. FHS symlinks          |
     |                               |   3. Mount VHDXs (fstab)   |
     |                               |   4. exec(systemd)         |
     |                               |                            |
T+12 |                               | systemd takes over (PID 1) |
     |                               | systemd-journald           |
     |                               | systemd-logind             |
     |                               | Mount /mnt/data (VHDX)     |
     |                               |                            |
T+13 | User gets shell prompt        | User shell spawned         |
     |                               | All mounts ready           |
     |                               | /mnt/data available        |
```

---

## Conclusion

### The Unified Vision

This architecture represents a fundamental evolution in how we think about WSL distributions. Rather than treating the Windows host and Linux guest as separate entities, we embrace them as a **unified declarative system**.

**Key Insights:**

1. **WSL Plugins are the Missing Link**
   - They provide the synchronization point needed for Windows-side management
   - They run early enough to set up prerequisites
   - They have the privileges needed to configure Windows

2. **NixOS is Uniquely Positioned**
   - Already has declarative configuration
   - Already has activation script infrastructure (systemd-shim)
   - Community values reproducibility and correctness

3. **The Asymmetry Problem is Solved**
   - Before: Linux is declarative, Windows is manual
   - After: Both sides are declarative, managed from one configuration

4. **New Possibilities Emerge**
   - Version control entire development environments
   - Reproduce exact configurations across teams
   - Enforce policies consistently
   - Automate complex setups

### Future Directions

**Community Adoption:**
- Other distributions could adopt similar patterns
- Standard WSL plugin library could emerge
- Cross-distribution plugin sharing

**Enterprise Features:**
- Centralized configuration management
- Fleet-wide policy enforcement
- Audit and compliance reporting
- Integration with existing IT infrastructure

**Developer Experience:**
- VSCode integration for configuration editing
- GUI configuration tool for non-NixOS users
- Pre-built configurations for common setups
- Marketplace for plugin extensions

### Getting Started

For those interested in implementing this vision:

1. **Start Small**: Basic VHDX plugin
2. **Iterate**: Add features incrementally
3. **Collaborate**: Share designs with community
4. **Document**: Help others understand and adopt
5. **Test**: Extensively, on many configurations

The future of WSL is declarative, unified, and powerful. This architecture shows the way forward.

---

## References

### Official Documentation

- [WSL Plugin Documentation](https://learn.microsoft.com/en-us/windows/wsl/wsl-plugins)
- [WSL Configuration (wsl.conf)](https://learn.microsoft.com/en-us/windows/wsl/wsl-config)
- [WSL Advanced Settings (.wslconfig)](https://learn.microsoft.com/en-us/windows/wsl/wsl-config)

### Code Repositories

- [microsoft/wsl-plugin-sample](https://github.com/microsoft/wsl-plugin-sample) - Official plugin sample
- [nix-community/NixOS-WSL](https://github.com/nix-community/NixOS-WSL) - NixOS-WSL project
- [NixOS-WSL Design Documentation](https://nix-community.github.io/NixOS-WSL/design.html)

### Technical Specifications

- WSL Plugin API: `Microsoft.WSL.PluginApi` NuGet package
- Minimum WSL version: 2.0.7.0 for plugin support
- Minimum WSL version: 2.4.4 for .wsl tarball import
- systemd support: WSL 0.67.6+ (native systemd as PID 1)

### Related Projects

- [Distrod](https://github.com/nullpo-head/wsl-distrod) - Alternative systemd approach
- [WSL-DistroLauncher](https://github.com/microsoft/WSL-DistroLauncher) - Custom distribution template

### Windows APIs

- [Windows Firewall API](https://learn.microsoft.com/en-us/windows/win32/api/_ics/)
- [Service Control Manager](https://learn.microsoft.com/en-us/windows/win32/services/service-control-manager)
- [Virtual Hard Disk API](https://learn.microsoft.com/en-us/windows/win32/api/_vhd/)
