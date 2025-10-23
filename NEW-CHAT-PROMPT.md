# WSL Plugin Development - Next Phase

## Context
I'm developing a WSL plugin for declarative Windows disk management. **Container infrastructure issue has been completely resolved** - Docker Desktop with Windows containers is now working perfectly (builds complete in ~7s instead of timing out).

## Current Status
- **Repository**: `/home/tim/src/wsl-plugin-sample` (working directory)
- **Working Document**: `/home/tim/src/wsl-plugin-sample/CONTAINER-DEBUGGING.md` (read this first)
- **Branch**: `nixdev` (development branch)
- **Container Infrastructure**: ✅ **WORKING** - Docker Desktop with Hyper-V backend functional
- **Build Status**: Container builds successfully, but **compilation fails** with missing headers

## Current Problem
The Windows container build process works perfectly, but compilation fails with these specific errors:

1. **Missing WSL Plugin API headers**: `error C1083: Cannot open include file: 'WslPluginApi.h': No such file or directory`
2. **Windows SDK header conflicts**: Multiple GUID redefinitions between `winioctl.h` and `ntddstor.h` 

## Build Environment 
- **Container**: Windows Server Core with VS Build Tools 2022
- **Build Command**: `msbuild C:\work\wsl-plugin-sample.sln /p:Configuration=Release /p:Platform=x64`
- **Volume Mount**: WSL filesystem successfully accessible in container
- **Build Time**: ~7 seconds (infrastructure working correctly)

## Next Tasks
1. **Obtain WSL Plugin API headers** - Find and include `WslPluginApi.h` from Microsoft WSL SDK
2. **Fix Windows SDK header conflicts** - Resolve GUID redefinition errors
3. **Complete plugin compilation** - Get clean build
4. **Test plugin functionality** - Verify with actual WSL distributions

## Project Architecture
- **Windows Plugin**: C++ DLL with VSOCK communication to WSL distributions
- **Linux Side**: systemd-shim integration in NixOS-WSL (separate repo)
- **Configuration**: INI-based disk management (bare disks, VHDX creation)
- **Target**: Declarative disk management through WSL plugin API

## Important Notes
- Container debugging phase is **complete** - do not revisit Docker setup
- Focus on **compilation errors only** - the build infrastructure works
- All diagnostic scripts and validation tools are already available
- Working document contains full resolution history and current configuration

**Primary Goal**: Fix the missing headers and compilation errors to get a working plugin build.