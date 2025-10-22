# Windows Build Environments: Containers, VMs, and GitHub Actions for VS Build Tools

Your quest for a reproducible Windows VS Build Tools environment reveals a fundamental architectural mismatch: **GitHub Actions uses Azure VMs, not containers**. This means true local/CI parity using "the same method" isn't possible. However, you can achieve excellent reproducibility through parallel approaches optimized for each environment.

## Windows 11 Pro: Required for containers, but not for contributors

**The verdict:** Windows 11 Pro or Enterprise is **absolutely required** for running Windows containers. The "Containers" Windows feature and Hyper-V capabilities are deliberately excluded from Home edition SKUs with no legitimate workarounds. This is Microsoft product segmentation, not a technical limitation.

**Critical distinction:** WSL2 works perfectly on Windows 11 Home. It uses the "Virtual Machine Platform" feature (a subset of Hyper-V) that's available on all Desktop editions. Contributors to your NixOS-WSL plugin project do **not** need Pro licenses - they only need Home with WSL2 enabled.

**Cost implications:** Upgrading Home to Pro costs $99-199, which would create an unreasonable barrier for open-source contributors when WSL2 (your core use case) works identically on both editions.

## Podman cannot replace Docker for Windows containers

**Major finding:** Podman does **not** support native Windows containers as of 2025, with no roadmap for implementation. Podman maintainers explicitly stated they have "no interest in Windows containers" and focus solely on Linux containers via WSL2.

**CLI-only Docker options:** Docker Desktop is **not required** for Windows containers. You can install standalone Docker binaries (`dockerd.exe` and `docker.exe`) from the static builds at `download.docker.com/win/static/stable/x86_64/`, register the daemon as a Windows service, and use CLI-only workflows. Docker Desktop's licensing restrictions only apply to the GUI application, not the CLI binaries (Apache 2.0 licensed).

**Recommended setup for Windows containers:**
```powershell
# Enable Windows features (requires Pro)
Enable-WindowsOptionalFeature -Online -FeatureName containers -All
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All

# Download and install Docker CLI binaries
curl.exe -o docker.zip -LO https://download.docker.com/win/static/stable/x86_64/docker-27.3.1.zip
Expand-Archive docker.zip -DestinationPath C:\
[Environment]::SetEnvironmentVariable("Path", "$($env:path);C:\docker", [System.EnvironmentVariableTarget]::Machine)

# Register and start Docker service
dockerd --register-service
Start-Service docker
```

## Architecture: WSL2 and Windows containers coexist harmoniously

WSL2 and Windows containers share the Windows Hypervisor Platform infrastructure without conflicts. Both can run simultaneously on Windows 11 Pro because they use different aspects of the same underlying virtualization stack.

**Key architectural components:**
- **WSL2**: Uses Virtual Machine Platform (lightweight Hyper-V subset) to run a Utility VM with Linux kernel
- **Windows containers**: Support two isolation modes:
  - **Process isolation**: Shares host kernel, minimal overhead (200MB-2GB per container), default on Server
  - **Hyper-V isolation**: Each container in its own VM, better security (1-2GB per container), default on Windows 10/11 Pro

**Required Windows features for coexistence:**
1. Windows Subsystem for Linux
2. Virtual Machine Platform
3. Containers (Pro edition only)
4. Hyper-V (optional, for Hyper-V container isolation)

**Integration via Docker Desktop:** When Docker Desktop is installed with WSL2 backend, the `docker` CLI works seamlessly from WSL2 terminals. You can call Windows containers from Linux/WSL2 using the same Docker commands, with automatic path translation for volume mounts like `-v /mnt/c/code:/code`.

## Windows containers dominate VMs and Sandbox for your use case

For a reproducible VS Build Tools environment callable from WSL2, Windows containers are the clear winner over Hyper-V VMs and Windows Sandbox.

### Performance comparison

| Metric | Windows Containers | Hyper-V VMs | Windows Sandbox |
|--------|-------------------|-------------|-----------------|
| **Startup time** | 1-2 seconds | 30-60+ seconds | 10-20 seconds |
| **Memory footprint** | 200MB-2GB | 4-16GB | 4GB (configurable) |
| **Disk space** | 10-20GB (layered) | 40-100GB | Dynamic (minimal) |
| **WSL2 integration** | ★★★★★ (native Docker) | ★★☆☆☆ (PowerShell) | ★☆☆☆☆ (none) |
| **Reproducibility** | ★★★★★ (immutable images) | ★★★★☆ (templates) | ★★☆☆☆ (config only) |
| **CI/CD support** | ★★★★★ (native) | ★★★★☆ (traditional) | ★☆☆☆☆ (unsuitable) |

### Windows Sandbox limitations

**Windows Sandbox is not suitable for repeated build workflows.** While it offers clean, isolated environments, it has critical drawbacks:

- **Non-persistent**: Everything is discarded on close, requiring VS Build Tools reinstallation each launch (~10 minutes)
- **Automation**: Limited to `.wsb` XML configuration files; CLI tools only available in Windows 11 24H2+ (October 2024)
- **Not designed for CI/CD**: Single-machine, single-user focus with no orchestration support
- **WSL2 integration**: Essentially none - must call via `powershell.exe` wrapper

### Windows containers: The optimal choice

**Strengths for VS Build Tools environments:**

1. **Immutable infrastructure**: Dockerfile defines exact environment in version control
2. **Fast iteration**: 1-2 second startup enables rapid build-test cycles
3. **Excellent automation**: Docker CLI is industry standard with comprehensive tooling
4. **Native WSL2 integration**: Docker Desktop's WSL2 backend makes containers accessible from Linux terminals
5. **High density**: Run many parallel builds on the same host (important for CI)
6. **Portability**: Push images to registry, pull anywhere

**Example Dockerfile for VS Build Tools 2022:**
```dockerfile
FROM mcr.microsoft.com/dotnet/framework/sdk:4.8-windowsservercore-ltsc2022

# Download and install VS Build Tools 2022
RUN curl -SL --output vs_buildtools.exe https://aka.ms/vs/17/release/vs_buildtools.exe && \
    start /w vs_buildtools.exe --quiet --wait --norestart --nocache \
    --installPath "C:\BuildTools" \
    --add Microsoft.VisualStudio.Workload.VCTools \
    --add Microsoft.VisualStudio.Workload.MSBuildTools \
    --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 \
    || IF "%ERRORLEVEL%"=="3010" EXIT 0 && \
    del /q vs_buildtools.exe

# Set up build environment
ENTRYPOINT ["C:\\BuildTools\\Common7\\Tools\\VsDevCmd.bat", "&&", "powershell.exe", "-NoLogo", "-ExecutionPolicy", "Bypass"]
```

**Usage from WSL2:**
```bash
docker run --rm \
  -v /mnt/c/projects/myapp:/source:ro \
  -v /mnt/c/build-output:/output \
  buildtools:2022 \
  cmd /c "msbuild C:\source\MyApp.sln /p:Configuration=Release /p:OutDir=C:\output"
```

**Critical configuration requirements:**
- **Container storage**: 127GB recommended (VS Build Tools needs ~10-15GB)
- **Build memory**: Minimum 2GB with `-m 2GB` flag
- **OS version matching**: Container base image OS must match host OS version for process isolation

## GitHub Actions: VMs, not containers - requiring different strategy

**The critical finding:** GitHub Actions Windows runners use **Azure Virtual Machines**, not containers. This fundamentally differs from Linux workflows where containers are first-class citizens.

### Backend architecture

- **Virtualization**: Ephemeral Azure VMs (previously Dadsv5-series)
- **Specs**: 4 vCPU, 16GB RAM for public repos; 2 vCPU, 8GB RAM for private repos
- **OS options**: `windows-2025`, `windows-2022`, `windows-2019` (deprecated)
- **Storage**: C: drive (slower managed disks), D: drive (fast local SSD for temp files)
- **Runner software**: Fork of Azure Pipelines Agent

**Windows containers are NOT supported in GitHub Actions.** The `container:` keyword only works with Linux runners. This is a platform limitation, not a technical Windows constraint.

### Pre-installed software on Windows runners

GitHub provides comprehensive pre-installed software on Windows Server 2022/2025 images:

- **Visual Studio 2022 Enterprise** (full installation)
- **MSBuild** (all versions)
- **Visual C++ build tools** (latest version)
- **Windows SDKs** (multiple versions)
- **.NET SDK** (6.0, 8.0, 9.0 series) and .NET Framework (3.5-4.8.x)
- **PowerShell 7.x** + Windows PowerShell 5.1
- **Development tools**: Node.js, Python, Ruby, Go, Rust, Java
- **Build systems**: CMake, Gradle, Maven, Ninja, Bazel
- **Container tools**: Docker Desktop (Linux containers by default)
- **WSL**: v1 on 2022, v2 on 2025

Full software manifests available at `github.com/actions/runner-images/blob/main/images/windows/Windows2022-Readme.md`

### Local replication strategies

**Perfect replication is impractical** because GitHub's ephemeral Azure VM infrastructure can't be exactly duplicated locally. However, three approaches provide different trade-offs:

**Option 1: Self-hosted runners (best parity)**
- Install GitHub Actions runner application on your own Windows machine
- Exact environment control - you manage all software versions
- Can target with `runs-on: self-hosted` in workflows
- **Best for:** Teams with dedicated infrastructure, compliance requirements

**Option 2: Manual environment matching**
- Install Visual Studio 2022 Enterprise/Community locally
- Match .NET SDK versions from runner manifest
- Use same PowerShell commands as workflows
- **Best for:** Individual developers with existing Windows development setup

**Option 3: Parallel environments with functional parity**
- Use Docker containers locally for fast iteration
- Use GitHub Actions VMs for authoritative CI testing
- Ensure both environments use same Build Tools versions
- **Best for:** Your use case - NixOS-WSL plugin development

### Best practices for development/CI parity

**1. Version pinning in workflows:**
```yaml
- uses: microsoft/setup-msbuild@v2
  with:
    vs-version: '17.0'  # Pin specific VS version

- uses: actions/setup-node@v4
  with:
    node-version: '20.19.5'  # Pin exact version
```

**2. Use actions for environment setup:**
```yaml
- uses: ilammy/msvc-dev-cmd@v1  # Setup MSVC environment
  with:
    arch: x64
    
- uses: microsoft/setup-msbuild@v2  # Add MSBuild to PATH
```

**3. Performance optimization for Windows builds:**
```yaml
- name: Build with Optimized Paths
  run: |
    msbuild MySolution.sln `
      /p:Configuration=Release `
      /p:IntermediateOutputPath=D:\obj\ `
      /p:OutDir=D:\bin\
  env:
    TMP: D:\temp
    TEMP: D:\temp
    NUGET_PACKAGES: D:\nuget-packages
```

**4. Document environment in repository:**
Create `ENVIRONMENT.md` with required VS version, workloads, .NET SDKs, and environment variables.

**5. Minimize GitHub-specific dependencies:**
Keep CI-specific logic in workflow files, not build scripts. Use parameters instead of `GITHUB_*` environment variables in build scripts.

## Open-source contributor requirements: Don't mandate Pro licenses

**Requiring Windows 11 Pro from contributors is unreasonable and unnecessary** for your NixOS-WSL plugin project. This contradicts open-source best practices of minimizing contributor friction.

### Why Pro requirements are inappropriate

1. **WSL2 works on Home**: Your core use case (WSL2 development) requires only Windows Home with Virtual Machine Platform enabled
2. **Cost barrier**: $99-199 upgrade cost discourages volunteer contributions
3. **Against open-source principles**: Successful projects minimize "time to first commit" by removing barriers
4. **Uncommon pattern**: Major projects like Node.js, WSL itself, and NixOS-WSL don't require specific OS licenses

### Recommended contributor model

**Adopt a CI-first approach** that eliminates local Windows testing requirements:

**Tier 1 - Preferred setup (zero barriers):**
1. Implement GitHub Actions with Windows runners for automated testing
2. Provide `devcontainer.json` for GitHub Codespaces (free 60 hours/month)
3. Document that contributors can submit PRs without local Windows testing
4. CI validates all changes on actual Windows environments

**Tier 2 - Local development (optional):**
5. Document that Windows 10/11 Home with WSL2 is sufficient for local testing
6. Provide Nix flake or setup script for WSL2 development environment
7. Contributors can test within WSL2 on Home edition

**Tier 3 - Advanced setup (maintainers only):**
8. Document any Windows-specific features requiring Pro (if truly needed)
9. Make this tier optional for casual contributors

**Documentation strategy:**
Your `CONTRIBUTING.md` should prominently state: *"You don't need Windows Pro to contribute. Basic contributions can be made with any OS, and Windows-specific testing happens automatically in CI."*

### Examples from similar projects

- **NixOS-WSL project**: No Windows Pro requirement documented; uses GitHub for hosting (implying CI-based testing)
- **Microsoft's WSL** (now open source): No Pro license requirement mentioned
- **Node.js**: Converted 50% of monthly contributors as first-timers by minimizing barriers
- **Best practice pattern**: Design for casual contributors, not just core maintainers

## Recommended architecture for your use case

Your specific scenario - reproducible VS Build Tools for a NixOS-WSL plugin project - calls for a **hybrid approach** that leverages strengths of both containers and VMs:

### Architecture design

**Local development (Windows 11 Pro with Docker):**
```
┌─────────────────────────────────────────┐
│  Windows 11 Pro Host                    │
│  ┌───────────────────────────────────┐  │
│  │  WSL2 (NixOS via NixOS-WSL)       │  │
│  │  - Your development environment   │  │
│  │  - Docker CLI installed           │  │
│  │  - Build scripts                  │  │
│  └───────────────────────────────────┘  │
│               │                          │
│               ▼                          │
│  ┌───────────────────────────────────┐  │
│  │  Docker Desktop (Windows backend) │  │
│  │  - Manages Windows containers     │  │
│  │  - Accessible from WSL2 CLI       │  │
│  └───────────────────────────────────┘  │
│               │                          │
│               ▼                          │
│  ┌───────────────────────────────────┐  │
│  │  Windows Container                │  │
│  │  - VS Build Tools 2022            │  │
│  │  - Reproducible environment       │  │
│  │  - 1-2s startup time              │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
```

**CI pipeline (GitHub Actions VMs):**
```
┌─────────────────────────────────────────┐
│  GitHub Actions (Azure VM)              │
│  - runs-on: windows-2022                │
│  - Pre-installed VS 2022 Enterprise     │
│  - MSBuild, .NET SDK, Windows SDK       │
│  - Ephemeral, pristine environment      │
│  - Authoritative test results           │
└─────────────────────────────────────────┘
```

### Implementation workflow

**1. Create Dockerfile for local development:**
```dockerfile
FROM mcr.microsoft.com/dotnet/framework/sdk:4.8-windowsservercore-ltsc2022

# Install VS Build Tools matching GitHub Actions
RUN curl -SL --output vs_buildtools.exe https://aka.ms/vs/17/release/vs_buildtools.exe && \
    start /w vs_buildtools.exe --quiet --wait --norestart --nocache \
    --installPath "C:\BuildTools" \
    --add Microsoft.VisualStudio.Workload.VCTools \
    --add Microsoft.VisualStudio.Workload.MSBuildTools \
    || IF "%ERRORLEVEL%"=="3010" EXIT 0 && \
    del /q vs_buildtools.exe

ENTRYPOINT ["C:\\BuildTools\\Common7\\Tools\\VsDevCmd.bat", "&&", "cmd.exe"]
```

**2. Build once, use repeatedly:**
```bash
# From WSL2 terminal
docker build -t nixos-wsl-buildtools:2022 -m 2GB .
```

**3. Create wrapper script in your project:**
```bash
#!/usr/bin/env bash
# scripts/build-windows.sh
docker run --rm \
  -v "$(pwd):/workspace" \
  -w /workspace \
  nixos-wsl-buildtools:2022 \
  msbuild MyProject.sln /p:Configuration=Release "$@"
```

**4. GitHub Actions workflow:**
```yaml
name: Build and Test

on: [push, pull_request]

jobs:
  build-windows:
    runs-on: windows-2022
    steps:
      - uses: actions/checkout@v4
      
      - uses: ilammy/msvc-dev-cmd@v1
        with:
          arch: x64
      
      - name: Build
        run: msbuild MyProject.sln /p:Configuration=Release
        
      - name: Test
        run: ./test-windows.ps1
```

**5. Maintain parity:**
- Pin VS Build Tools version in both Dockerfile and workflow
- Document exact versions in `ENVIRONMENT.md`
- Test locally with containers before pushing
- Trust GitHub Actions as authoritative for PRs
- Update both environments together when upgrading tools

### Key benefits of this approach

1. **Fast local iteration**: Containers start in 1-2 seconds for rapid testing
2. **Reproducibility**: Dockerfile in version control defines exact environment
3. **CI integration**: GitHub Actions provides authoritative testing on VM infrastructure
4. **Contributor accessibility**: Contributors can use GitHub Actions for testing without Windows
5. **Cost efficiency**: Only you (maintainer) needs Windows 11 Pro; contributors use CI
6. **Best of both worlds**: Containers for speed, VMs for comprehensive testing

## Critical considerations and caveats

### Licensing requirements

**Windows Server containers:**
- Standard edition: Allows 2 Hyper-V isolated containers
- Datacenter edition: Unlimited Hyper-V isolated containers
- Process isolation: No additional licensing beyond host OS

**Docker Desktop:**
- CLI binaries: Free (Apache 2.0 license)
- Docker Desktop GUI: Requires paid subscription for commercial use (250+ employees or $10M+ revenue)

### Technical limitations

**OS version matching:**
- Container base image OS must match host OS for process isolation
- Windows Server 2022 container → Windows Server 2022 host
- Hyper-V isolation more flexible but still constrained
- Solution: Use Hyper-V isolation mode: `docker run --isolation=hyperv`

**Windows containers not available in GitHub Actions:**
- Cannot use `container:` keyword with Windows images in workflows
- Must use pre-installed software on runner VMs
- This architectural difference means truly identical environments aren't possible

**Storage and memory requirements:**
- Container storage: 127GB recommended for VS Build Tools
- Build memory: Minimum 2GB (configure with `-m 2GB`)
- Default 20GB storage insufficient

### Performance optimization

**Use D: drive in GitHub Actions:**
D: drive uses local SSD storage (30x faster IOPS than C: drive) for build artifacts and temporary files.

**Enable parallel builds:**
```bash
msbuild MySolution.sln /m /p:Configuration=Release
```

**Cache dependencies:**
```yaml
- uses: actions/cache@v4
  with:
    path: ~/.nuget/packages
    key: ${{ runner.os }}-nuget-${{ hashFiles('**/*.csproj') }}
```

## Final recommendations

### For you (project maintainer)

1. **Upgrade to Windows 11 Pro** to enable Windows containers for local development
2. **Install Docker CLI** (standalone binaries, not Docker Desktop if licensing is a concern)
3. **Create Dockerfile** matching GitHub Actions VS Build Tools version
4. **Use containers locally** for fast iteration (1-2s startup)
5. **Trust GitHub Actions** as authoritative CI environment

### For contributors

1. **Do NOT require Windows 11 Pro** - WSL2 works on Home
2. **Implement GitHub Actions** with Windows runners for automated testing
3. **Provide dev container configuration** for GitHub Codespaces
4. **Document clearly**: "You can contribute without local Windows testing - CI validates all changes"
5. **Welcome first-time contributors** with low-barrier entry points

### For the project architecture

1. **Hybrid approach**: Containers for local dev, VMs for CI
2. **Functional parity over identical environments**: Pin versions, document requirements
3. **CI-first validation**: Make GitHub Actions the source of truth for PRs
4. **Version control everything**: Dockerfiles, workflow configs, environment documentation
5. **Monitor runner-images releases**: Subscribe to `github.com/actions/runner-images/releases` for updates

The fundamental mismatch between GitHub Actions VMs and local container options means perfect replication isn't achievable. However, this hybrid approach - optimized containers locally, comprehensive VMs in CI - provides excellent reproducibility while maintaining contributor accessibility and development velocity.

Your focus should be on **functional parity through careful version management** rather than architectural identity. The CI pipeline becomes your contract for "this works," while local containers provide rapid feedback loops for development.