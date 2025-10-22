# Windows Containers: Local Development & CI

This document describes how to set up a unified build environment using Windows Containers that works identically in both local development and GitHub Actions CI.

## Overview

The WSL plugin requires Windows development tools to build and test. We use Windows Containers to provide a consistent, declarative build environment across:

- **Local development**: Windows 11 Pro with Docker Desktop
- **GitHub Actions CI**: `windows-2025` runners (have Docker pre-installed)

## Requirements

### Local Development

**Windows 11 Pro (or Windows Server 2022+) is required** for Windows Container support with process isolation.

> **Note**: Windows 11 Home does NOT support Windows Containers. It only supports Linux containers via WSL2. If you have Windows 11 Home, you can either:
> - Upgrade to Windows 11 Pro
> - Use WSL2 for development (different approach, not covered here)
> - Use self-hosted GitHub Actions runners for testing

### GitHub Actions CI

No special requirements - `windows-2025` and `windows-2022` runners have Docker pre-installed and configured for Windows Containers.

## Local Setup

### 1. Enable Windows Features

Run PowerShell as Administrator:

```powershell
# Enable required features
dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
dism.exe /online /enable-feature /featurename:Microsoft-Hyper-V-All /all /norestart
dism.exe /online /enable-feature /featurename:Containers /all /norestart

# Restart required
shutdown /r /t 0
```

### 2. Install Docker Desktop

**Manual Installation:**

1. Download from https://www.docker.com/products/docker-desktop/
2. Run installer
3. During setup, ensure "Use Windows containers" is selected

**Automated Installation (Winget):**

```powershell
winget install Docker.DockerDesktop --silent --accept-package-agreements --accept-source-agreements
```

**Alternative: Direct Download + Silent Install:**

```powershell
# Download installer
$url = "https://desktop.docker.com/win/main/amd64/Docker%20Desktop%20Installer.exe"
$output = "$env:TEMP\DockerDesktopInstaller.exe"
Invoke-WebRequest -Uri $url -OutFile $output

# Install silently
Start-Process -Wait -FilePath $output -ArgumentList @(
    "install",
    "--quiet",
    "--accept-license",
    "--backend=windows"
)

# Cleanup
Remove-Item $output
```

### 3. Configure for Windows Containers

After installation, switch to Windows containers:

```powershell
# Via Docker Desktop system tray
# Right-click Docker icon → "Switch to Windows containers..."

# Or via CLI
& 'C:\Program Files\Docker\Docker\DockerCli.exe' -SwitchWindowsEngine
```

### 4. Verify Installation

```powershell
docker version
docker info

# Test Windows container
docker run --isolation=process mcr.microsoft.com/windows/nanoserver:ltsc2025 cmd /c echo Hello from Windows Container
```

## Container Build Environment

### Dockerfile Structure

The main `Dockerfile` uses winget for installing Visual Studio Build Tools:

```dockerfile
# Windows container for building WSL plugin with MS Build Tools
# Base image: Windows Server Core 2022 with App Installer (winget) support
FROM mcr.microsoft.com/windows/servercore:ltsc2022

# Install App Installer (winget) and its dependencies
SHELL ["powershell", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]

# Install the latest NuGet provider and App Installer
RUN Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force ; \
    Add-AppxPackage -Path https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx ; \
    $releases = Invoke-RestMethod https://api.github.com/repos/microsoft/winget-cli/releases/latest ; \
    $latestRelease = $releases.assets | Where-Object { $_.name -match 'msixbundle' } | Select-Object -First 1 ; \
    Add-AppxPackage -Path $latestRelease.browser_download_url ; \
    Add-AppxPackage -Path https://aka.ms/Microsoft.UI.Xaml.2.8.x64.appx

# Install Visual Studio Build Tools 2022 via winget
RUN winget install Microsoft.VisualStudio.2022.BuildTools --silent --accept-package-agreements --accept-source-agreements \
    --override "--passive --wait \
    --add Microsoft.VisualStudio.Workload.VCTools \
    --add Microsoft.VisualStudio.Workload.MSBuildTools \
    --add Microsoft.VisualStudio.Component.Windows10SDK.19041 \
    --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 \
    --add Microsoft.VisualStudio.Component.VC.CMake.Project"

# Set up environment variables for MSBuild
RUN setx PATH "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin;%PATH%" /M

# Create work directory for the project
WORKDIR C:\work

# Create output directory for build artifacts
RUN mkdir C:\output

# Entry point that sets up the VS development environment and runs commands
ENTRYPOINT ["C:\\Program Files (x86)\\Microsoft Visual Studio\\2022\\BuildTools\\Common7\\Tools\\VsDevCmd.bat", "&&"]

# Default command - can be overridden at runtime
CMD ["msbuild", "/?"]
```

### WSL-Windows Container Workflow Design

#### Architecture Overview

To avoid the 9P filesystem performance penalty when accessing WSL2 files from Windows containers, we implement a dual-repository design with Git synchronization:

1. **WSL2 Repository** (Primary development location)
   - Path: `/home/user/src/wsl-plugin-sample` (current PWD)
   - Used for development, editing, and version control
   - Maintains full git history and branches

2. **Windows Repository** (Build location)
   - Suggested path: `C:\BuildWorkspace\wsl-plugin-sample`
   - Cloned from WSL2 repository via git remote
   - Used exclusively for building inside Windows containers
   - Bind-mounted to `/work` inside the container

#### Filesystem Synchronization Strategy

##### Git Remote Setup

```bash
# In WSL2 - Set up Windows repo as remote
cd /home/user/src/wsl-plugin-sample
git remote add windows-build /mnt/c/BuildWorkspace/wsl-plugin-sample

# Initial clone on Windows side (run once in PowerShell)
cd C:\BuildWorkspace
git clone \\wsl.localhost\<distro>\home\user\src\wsl-plugin-sample

# Configure Windows repo to track WSL2 repo
cd C:\BuildWorkspace\wsl-plugin-sample
git remote add wsl \\wsl.localhost\<distro>\home\user\src\wsl-plugin-sample
```

##### Pre-Build Synchronization

Before building in the container, sync the Windows repository:

```bash
# From WSL2 - Push changes to Windows repo
git push windows-build main

# Or from Windows - Pull changes from WSL2 repo
cd C:\BuildWorkspace\wsl-plugin-sample
git pull wsl main
```

#### Build Output Handling

Since we don't want to commit binaries to git, we use a separate output directory:

1. **Container Output Directory**: `C:\output` (inside container)
2. **Host Output Directory**: `C:\BuildOutput\wsl-plugin-sample` (on Windows host)
3. **WSL2 Access**: `/mnt/c/BuildOutput/wsl-plugin-sample` (from WSL2)

##### Build Command Example

```powershell
# From Windows PowerShell or WSL2 via docker.exe
docker run --rm --isolation=process `
  -v C:\BuildWorkspace\wsl-plugin-sample:C:\work:ro `
  -v C:\BuildOutput\wsl-plugin-sample:C:\output `
  wsl-plugin-build `
  msbuild C:\work\wsl-plugin-sample.sln /p:Configuration=Release /p:OutDir=C:\output
```

##### Accessing Build Output from WSL2

```bash
# From WSL2 - Copy build artifacts
cp /mnt/c/BuildOutput/wsl-plugin-sample/*.dll ./build/

# Or create a symbolic link for continuous access
ln -s /mnt/c/BuildOutput/wsl-plugin-sample ./build-output
```

#### Complete Workflow Script

Create `build-in-windows-container.sh` in WSL2:

```bash
#!/bin/bash
# Build WSL plugin using Windows container from WSL2

PROJECT_DIR="/home/user/src/wsl-plugin-sample"
WINDOWS_REPO="C:\\BuildWorkspace\\wsl-plugin-sample"
OUTPUT_DIR="C:\\BuildOutput\\wsl-plugin-sample"
CONTAINER_IMAGE="wsl-plugin-build:latest"

# Sync code to Windows repository
echo "Syncing code to Windows build repository..."
cd "$PROJECT_DIR"
git push windows-build main --force

# Build in Windows container via docker.exe
echo "Building in Windows container..."
docker.exe run --rm --isolation=process \
  -v "${WINDOWS_REPO}:C:\\work:ro" \
  -v "${OUTPUT_DIR}:C:\\output" \
  "$CONTAINER_IMAGE" \
  msbuild C:\\work\\wsl-plugin-sample.sln /p:Configuration=Release /p:OutDir=C:\\output

# Check build results
if [ $? -eq 0 ]; then
    echo "Build successful! Output available at:"
    echo "  Windows: ${OUTPUT_DIR}"
    echo "  WSL2: /mnt/c/BuildOutput/wsl-plugin-sample"
    ls -la /mnt/c/BuildOutput/wsl-plugin-sample/
else
    echo "Build failed!"
    exit 1
fi
```

#### Alternative: Direct VHDX Mount (Advanced)

For better performance, you can mount a VHDX directly in both WSL2 and Windows:

1. Create a VHDX for build workspace
2. Mount in WSL2 as ext4
3. Mount in Windows container as NTFS
4. Use rsync for synchronization instead of git

This approach requires more setup but provides better I/O performance for large projects.

## Simplified Build Approach (Current Implementation)

For immediate development needs, we've implemented a simplified approach that prioritizes ease of use over optimal performance:

### Single Volume Strategy

Instead of the complex dual-repository design, we use a single read-write volume that maps the WSL2 project directory directly to the container's `C:\work`. This accepts the 9P filesystem performance penalty in favor of simplicity.

**Key Benefits:**
- No complex git synchronization required
- Build output appears directly in the project directory
- Simple volume mapping: `$(pwd)` → `C:\work`
- Works immediately without additional setup

### Build Output Management

**Binary Placement Strategy:**
- Build outputs (`.dll`, `.exe`, `.pdb` files) are placed in the project directory or subdirectories
- These files are excluded from git via `.gitignore` patterns
- No separate output directory synchronization needed

**Git Integration:**
- Source code: Committed to git as normal
- Build artifacts: Excluded via `.gitignore` entries:
  ```gitignore
  # Build outputs
  *.dll
  *.exe
  *.pdb
  *.obj
  *.lib
  x64/
  Debug/
  Release/
  .vs/
  ```

### Automation Scripts

**From WSL2:** Use `build-in-container.sh`
```bash
# Automatically maps current directory to C:\work
./build-in-container.sh
```

**From Windows PowerShell:** Use `build-in-container.ps1`
```powershell
# Builds with default Release/x64 configuration
.\build-in-container.ps1

# Or specify configuration
.\build-in-container.ps1 -Configuration Debug -Platform x86
```

**Manual Docker Command:**
```bash
# From WSL2
docker.exe run --rm --isolation=process \
    -v "$(wslpath -w .):C:\work" \
    wsl-plugin-build:latest \
    msbuild C:\work\wsl-plugin-sample.sln /p:Configuration=Release

# From Windows PowerShell
docker run --rm --isolation=process \
    -v "${PWD}:C:\work" \
    wsl-plugin-build:latest \
    msbuild C:\work\wsl-plugin-sample.sln /p:Configuration=Release
```

### Performance Considerations

**9P Filesystem Impact:**
- File I/O from Windows container → WSL2 filesystem has overhead
- Acceptable for moderate-sized projects and occasional builds
- Build times may be 2-3x slower than native Windows builds
- Can upgrade to dual-repository approach later if needed

**When to Consider Optimization:**
- Large codebase (>100 MB of source files)
- Frequent builds (multiple times per hour)
- Performance-critical CI/CD pipelines
- Large number of small files

### Building the Container

```powershell
# Build image
docker build -f Dockerfile.windows -t wsl-plugin-build-env:latest .

# Tag with version
docker tag wsl-plugin-build-env:latest wsl-plugin-build-env:1.0
```

### Using the Container Locally

```powershell
# Build the container image
docker build -t wsl-plugin-build:latest .

# Run interactive shell in container (for debugging)
docker run -it --isolation=process `
    -v C:\BuildWorkspace\wsl-plugin-sample:C:\work `
    -v C:\BuildOutput\wsl-plugin-sample:C:\output `
    wsl-plugin-build:latest `
    cmd

# Build the project
docker run --rm --isolation=process `
    -v C:\BuildWorkspace\wsl-plugin-sample:C:\work:ro `
    -v C:\BuildOutput\wsl-plugin-sample:C:\output `
    wsl-plugin-build:latest `
    msbuild C:\work\wsl-plugin-sample.sln /p:Configuration=Release /p:OutDir=C:\output

# Build from WSL2 using docker.exe
docker.exe run --rm --isolation=process `
    -v "C:\BuildWorkspace\wsl-plugin-sample:C:\work:ro" `
    -v "C:\BuildOutput\wsl-plugin-sample:C:\output" `
    wsl-plugin-build:latest `
    msbuild C:\work\wsl-plugin-sample.sln /p:Configuration=Release /p:OutDir=C:\output
```

## GitHub Actions Integration

### Basic Workflow

`.github/workflows/build-windows.yml`:

```yaml
name: Windows Build

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  build:
    runs-on: windows-2022  # Windows Server 2022 for container compatibility
    
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
      
      - name: Build container image
        run: docker build -t wsl-plugin-build:latest .
      
      - name: Create output directory
        run: New-Item -ItemType Directory -Force -Path C:\BuildOutput
      
      - name: Build project
        run: |
          docker run --rm --isolation=process `
            -v ${PWD}:C:\work:ro `
            -v C:\BuildOutput:C:\output `
            wsl-plugin-build:latest `
            msbuild C:\work\wsl-plugin-sample.sln /p:Configuration=Release /p:OutDir=C:\output
      
      - name: Upload artifacts
        uses: actions/upload-artifact@v4
        with:
          name: wsl-plugin-dll
          path: C:\BuildOutput\*.dll
```

### Advanced: Matrix Builds

Test against multiple Windows versions:

```yaml
jobs:
  build:
    runs-on: ${{ matrix.os }}
    strategy:
      matrix:
        os: [windows-2022, windows-2025]
        include:
          - os: windows-2022
            base_image: mcr.microsoft.com/windows/servercore:ltsc2022
          - os: windows-2025
            base_image: mcr.microsoft.com/windows/servercore:ltsc2025
    
    steps:
      - uses: actions/checkout@v4
      
      - name: Build with specific base image
        run: |
          docker build -f Dockerfile.windows `
            --build-arg BASE_IMAGE=${{ matrix.base_image }} `
            -t wsl-plugin-build-env:latest .
      
      # ... rest of build steps
```

### Caching Container Layers

Speed up CI by caching Docker layers:

```yaml
      - name: Setup Docker Buildx
        uses: docker/setup-buildx-action@v3
      
      - name: Cache Docker layers
        uses: actions/cache@v4
        with:
          path: C:\ProgramData\docker\windowsfilter
          key: docker-${{ runner.os }}-${{ hashFiles('Dockerfile.windows') }}
          restore-keys: |
            docker-${{ runner.os }}-
```

## Process Isolation vs Hyper-V Isolation

### Process Isolation (Recommended)

- **Pros**: Faster startup, lower memory overhead, better performance
- **Cons**: Requires matching OS version (Windows 11 can run Server 2022/2025 containers)
- **Usage**: `docker run --isolation=process`

### Hyper-V Isolation

- **Pros**: Better security isolation, can run mismatched OS versions
- **Cons**: Slower startup, higher memory usage
- **Usage**: `docker run --isolation=hyperv`

**Default behavior**: Docker automatically selects process isolation when OS versions match.

## Troubleshooting

### "Image operating system mismatch" Error

```powershell
# Check host OS version
[System.Environment]::OSVersion.Version

# Check container image version
docker inspect mcr.microsoft.com/windows/servercore:ltsc2025 | Select-String "os.version"
```

**Solution**: Use `--isolation=hyperv` for mismatched versions, or rebuild container with matching base image.

### Docker Desktop Not Starting

1. Check Hyper-V is enabled: `Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V`
2. Check WSL status: `wsl --status`
3. Restart Docker Desktop service: `Restart-Service docker`

### Build Tools Not Found in Container

Ensure tools are installed during image build. Test interactively:

```powershell
docker run -it --isolation=process wsl-plugin-build-env:latest powershell

# Inside container
Get-Command cmake
Get-Command cl.exe  # MSVC compiler
```

### Volume Mount Issues

Windows paths must use PowerShell syntax in GitHub Actions:

```yaml
# ✅ Correct
run: docker run -v ${PWD}:C:\workspace

# ❌ Incorrect  
run: docker run -v %CD%:C:\workspace  # CMD syntax
```

## Best Practices

1. **Pin base image versions**: Use specific tags like `ltsc2025` instead of `latest`
2. **Layer caching**: Order Dockerfile commands from least to most frequently changing
3. **Minimize image size**: Use `nanoserver` for minimal runtime (no package manager)
4. **Multi-stage builds**: Separate build tools from runtime environment
5. **Clean up**: Remove installer files after installation to reduce image size

## Why Not Podman?

Podman does not support Windows Containers - it only runs Linux containers via WSL2 on Windows. Docker Desktop is currently the only option for native Windows Container support on Windows.

## References

- [Windows Container Documentation](https://learn.microsoft.com/en-us/virtualization/windowscontainers/)
- [Docker Desktop for Windows](https://docs.docker.com/desktop/install/windows-install/)
- [GitHub Actions Windows Runners](https://docs.github.com/en/actions/using-github-hosted-runners/about-github-hosted-runners)
- [Windows Server 2025 Container Improvements](https://learn.microsoft.com/en-us/windows-server/get-started/whats-new-windows-server-2025)
