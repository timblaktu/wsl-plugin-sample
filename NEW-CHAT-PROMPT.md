# WSL Plugin-Shim Integration Architecture Design Discussion

## Context & Background

I'm working on integrating the `wsl-plugin-sample` project with `NixOS-WSL` to enable declarative Windows-side disk management through NixOS configuration. The integration uses VSOCK communication between a Windows WSL plugin and the NixOS-WSL systemd-shim to ensure Windows requirements are met before distribution boot.

**Current Implementation Status:**
- ✅ Windows Plugin: Complete with VSOCK client, WMI VM discovery, disk validation  
- ✅ NixOS-WSL systemd-shim: VSOCK server, INI parsing, plugin communication
- ✅ NixOS Module: Declarative configuration (`wsl.plugin.disks.bare`, `wsl.plugin.disks.vhdx`)
- ✅ Build Environment: Windows containers + Docker CLI setup documented
- ✅ Working end-to-end prototype

## Strategic Decision Point

**Current Assumption:** Include `wsl-plugin-sample` as submodule/subtree in `NixOS-WSL`

**New Consideration:** Keep plugin repository separate and generalize for any WSL distribution

## Key Technical Architecture

The plugin-shim integration pattern works by:

1. **WSL Plugin (Windows-side)**: Hooks into WSL lifecycle via `OnDistributionStarted` callback
2. **Distribution Shim (Linux-side)**: Custom init process that tells WSL "this is my init" 
3. **VSOCK Communication**: Plugin connects to shim before allowing distribution boot
4. **Declarative Requirements**: Configuration drives Windows-side disk/VHDX management
5. **Selective Activation**: Plugin only processes distributions implementing the protocol

## Research Findings: Other Declarative WSL Distributions

Based on my analysis, distributions that could benefit from this pattern:

### High Potential
- **NixOS-WSL** ⭐⭐⭐ (our current target)
  - Fully declarative configuration  
  - Custom systemd-shim init process
  - Package management supports complex dependency graphs
  - Strong reproducible builds focus

- **GNU Guix System** ⭐⭐⭐ (theoretical)
  - Purely functional package management
  - Declarative system configuration in Scheme
  - Strong reproducible builds emphasis
  - Could use custom shim process
  - **Gap**: No known WSL2 implementation yet

### Medium Potential  
- **Alpine Linux** ⭐⭐ (limited)
  - Lightweight, container-focused
  - APK package management
  - **Limitation**: No declarative configuration, drops package versions
  - Could benefit from persistent disk requirements

### Lower Potential
- **Standard Ubuntu/Debian/Arch WSL** ⭐ (minimal)
  - Use standard systemd (harder to intercept boot)
  - Imperative package management
  - Limited declarative configuration capabilities
  - Would require significant modifications

## Discussion Topics

1. **Repository Architecture:**
   - Separate plugin repo vs. NixOS-WSL subproject?
   - How to handle versioning/compatibility between plugin and distributions?
   - Distribution-agnostic plugin design patterns?

2. **Generalization Strategy:**
   - What abstraction layer needed for multiple distribution support?
   - How to handle different init systems and boot processes?
   - Configuration format standardization across distributions?

3. **Community & Upstream:**
   - Value proposition for other WSL distributions?
   - Maintenance burden vs. adoption potential?
   - Microsoft WSL team interest in standardizing this pattern?

4. **Technical Implementation:**
   - Plugin discovery mechanism for compatible distributions?
   - Protocol versioning and backward compatibility?
   - Error handling for unsupported distributions?

## Specific Questions for Analysis

1. **Market Research**: Are there other declarative/functional package management WSL distributions in development?

2. **Technical Feasibility**: What modifications would Alpine/Guix need to implement the shim pattern?

3. **Plugin Design**: How to make the Windows plugin completely distribution-agnostic while maintaining NixOS-specific optimizations?

4. **Ecosystem Impact**: Would a generalized solution provide enough value to justify the additional complexity?

## Current Working Environment

- **NixOS-WSL repo**: `/home/tim/src/NixOS-WSL` (Linux-side implementation)
- **Plugin repo**: `/home/tim/src/wsl-plugin-sample` (Windows-side implementation)  
- **Docker CLI setup**: Documented in `docs/DOCKER-CLI-SETUP.md`
- **Architecture docs**: Comprehensive design documentation exists in both repos

## Goal

Determine the optimal integration architecture that balances:
- **Immediate**: Get NixOS-WSL integration working and upstreamed
- **Future**: Enable broader WSL ecosystem adoption
- **Maintenance**: Keep complexity manageable
- **Innovation**: Pioneer declarative Windows-Linux integration patterns

Should we proceed with NixOS-WSL-specific integration or invest in a more generalized approach?