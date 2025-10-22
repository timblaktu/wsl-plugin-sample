# Docker CLI Setup (Alternative to Docker Desktop)

This guide covers setting up Docker CLI directly without Docker Desktop, ideal for developers who prefer lightweight installations or need more control over Docker configuration.

## Overview

Unlike Docker Desktop, this approach installs only the Docker CLI and daemon as Windows services, avoiding the overhead of Docker Desktop's GUI and additional components. This setup is particularly useful for:

- Automated/scripted environments
- Servers without GUI requirements
- Developers who prefer command-line tools
- Avoiding Docker Desktop licensing requirements

## Prerequisites

- **Windows 11 Pro, Enterprise, or Education** (Windows 11 Home requires upgrade)
- **Administrator access** for initial setup
- **WSL2** enabled (if using WSL integration)

## Step 1: Upgrade Windows 11 Home to Pro (if needed)

Windows 11 Home does not support Windows Containers or Hyper-V, which are required for this setup.

### Option A: Digital License Upgrade
```powershell
# Run as Administrator
# This upgrades using existing Windows 11 Home license
# No additional purchase required for existing Windows 11 Home users
changepk.exe /productkey VK7JG-NPHTM-C97JM-9MPGT-3V66T
```

### Option B: Settings App Upgrade
1. Open **Settings** → **System** → **Activation**
2. Click **Go to Store** next to "Upgrade your edition of Windows"
3. Purchase and install Windows 11 Pro upgrade

## Step 2: Enable Required Windows Features

Run PowerShell as Administrator:

```powershell
# Enable required features for containers and Hyper-V
dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
dism.exe /online /enable-feature /featurename:Microsoft-Hyper-V-All /all /norestart
dism.exe /online /enable-feature /featurename:Containers /all /norestart

# Restart required
shutdown /r /t 0
```

## Step 3: Install Docker CLI Binaries

### Download Docker Binaries

```powershell
# Create Docker directory
$dockerPath = "C:\Program Files\Docker"
New-Item -ItemType Directory -Force -Path $dockerPath

# Download Docker CLI and daemon
$dockerVersion = "24.0.7"  # Use latest stable version
$baseUrl = "https://download.docker.com/win/static/stable/x86_64"

# Download docker.exe (CLI)
Invoke-WebRequest -Uri "$baseUrl/docker-$dockerVersion.zip" -OutFile "$env:TEMP\docker.zip"

# Extract Docker binaries
Expand-Archive -Path "$env:TEMP\docker.zip" -DestinationPath "$env:TEMP\docker-extract" -Force
Copy-Item "$env:TEMP\docker-extract\docker\*" -Destination $dockerPath -Force

# Cleanup
Remove-Item "$env:TEMP\docker.zip", "$env:TEMP\docker-extract" -Recurse -Force
```

### Add Docker to PATH

```powershell
# Add Docker to system PATH
$currentPath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
if ($currentPath -notlike "*$dockerPath*") {
    [Environment]::SetEnvironmentVariable("PATH", "$currentPath;$dockerPath", "Machine")
}

# Refresh current session PATH
$env:PATH = [Environment]::GetEnvironmentVariable("PATH", "Machine")
```

## Step 4: Configure Docker User Group

This step allows Docker to run without Administrator privileges.

```powershell
# Create docker-users group (if it doesn't exist)
try {
    Get-LocalGroup -Name "docker-users" -ErrorAction Stop
    Write-Host "docker-users group already exists"
} catch {
    New-LocalGroup -Name "docker-users" -Description "Docker Users Group"
    Write-Host "Created docker-users group"
}

# Add current user to docker-users group
$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
Add-LocalGroupMember -Group "docker-users" -Member $currentUser

Write-Host "Added $currentUser to docker-users group"
Write-Host "You must log out and log back in for group membership to take effect"
```

## Step 5: Register Docker Daemon as Windows Service

Create the Docker daemon service with proper group permissions:

```powershell
# Create Docker daemon configuration
$dockerConfig = @{
    "hosts" = @("npipe://", "tcp://0.0.0.0:2375")
    "group" = "docker-users"
    "experimental" = $false
}

$configPath = "C:\ProgramData\docker"
New-Item -ItemType Directory -Force -Path $configPath
$dockerConfig | ConvertTo-Json | Set-Content "$configPath\daemon.json"

# Register Docker service
$serviceName = "docker"
$binaryPath = "`"C:\Program Files\Docker\dockerd.exe`" --run-service -G docker-users"

# Remove existing service if present
if (Get-Service -Name $serviceName -ErrorAction SilentlyContinue) {
    Stop-Service -Name $serviceName -Force
    sc.exe delete $serviceName
}

# Create new service
sc.exe create $serviceName binpath= $binaryPath start= auto
sc.exe description $serviceName "Docker Engine"

Write-Host "Docker service registered successfully"
```

## Step 6: Start and Verify Docker

```powershell
# Start Docker service
Start-Service -Name docker

# Wait for service to initialize
Start-Sleep -Seconds 10

# Verify Docker installation
docker version
docker info

# Test Windows container (requires logout/login for group membership)
Write-Host "Testing Windows container..."
docker run --rm mcr.microsoft.com/windows/nanoserver:ltsc2022 cmd /c echo "Docker CLI setup successful!"
```

## Step 7: Configure for Windows Containers (Default)

Ensure Docker is configured for Windows containers:

```powershell
# Switch to Windows containers (should already be default)
& 'C:\Program Files\Docker\docker.exe' system info | Select-String "OSType"

# If showing "linux", switch to Windows containers manually:
# This requires the Docker Desktop CLI switch command, but for CLI-only installations,
# Windows containers should be the default since no Linux VM is configured
```

## Troubleshooting

### Common Issues

**Error: "Access is denied" when running docker commands**
```powershell
# Ensure you've logged out and back in after adding user to docker-users group
# Verify group membership:
whoami /groups | findstr docker-users

# If not shown, log out and log back in
```

**Error: "Docker daemon not running"**
```powershell
# Check service status
Get-Service docker

# Start service if stopped
Start-Service docker

# Check service logs
Get-EventLog -LogName Application -Source "docker" -Newest 20
```

**Error: "The system cannot find the file specified" when starting service**
```powershell
# Verify Docker binaries are in correct location
Test-Path "C:\Program Files\Docker\dockerd.exe"

# Re-register service with correct path
sc.exe delete docker
sc.exe create docker binpath= "`"C:\Program Files\Docker\dockerd.exe`" --run-service -G docker-users" start= auto
```

**Permission denied for Windows containers**
```powershell
# Ensure Hyper-V and Containers features are enabled
Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V
Get-WindowsOptionalFeature -Online -FeatureName Containers

# If not enabled, run the DISM commands from Step 2 again
```

### Service Management

```powershell
# Stop Docker service
Stop-Service docker

# Start Docker service
Start-Service docker

# Restart Docker service
Restart-Service docker

# Check service status
Get-Service docker

# View service configuration
sc.exe qc docker
```

### Configuration Changes

Docker daemon configuration is stored in `C:\ProgramData\docker\daemon.json`. After making changes:

```powershell
# Restart Docker service to apply changes
Restart-Service docker
```

## Comparison with Docker Desktop

| Feature | Docker CLI Setup | Docker Desktop |
|---------|------------------|----------------|
| **Installation Size** | ~50 MB | ~500+ MB |
| **System Resources** | Minimal | Higher (GUI, additional services) |
| **Windows Containers** | ✅ Native | ✅ Supported |
| **Linux Containers** | ❌ (requires WSL2 integration) | ✅ Built-in |
| **GUI Management** | ❌ CLI only | ✅ Full GUI |
| **Licensing** | Free | May require license for enterprise |
| **Auto-updates** | Manual | Automatic |
| **Integration** | Manual configuration | Seamless |

## Integration with WSL2

For WSL2 integration with this CLI-only setup:

```powershell
# Configure Docker to expose daemon on TCP (optional, for WSL access)
# Edit C:\ProgramData\docker\daemon.json to include:
# {
#   "hosts": ["npipe://", "tcp://0.0.0.0:2375"],
#   "group": "docker-users"
# }

# From WSL2, you can then use:
# export DOCKER_HOST=tcp://localhost:2375
```

**Security Note:** Exposing Docker daemon on TCP is for development only. For production, use named pipes or TLS-secured connections.

## Next Steps

With Docker CLI configured, you can now:

1. **Build Windows containers**: Use the provided `Dockerfile` to build WSL plugin environments
2. **Run build scripts**: Execute `build-in-container.ps1` or `build-in-container.sh` 
3. **Integrate with CI/CD**: Use this setup in automated environments
4. **Develop WSL plugins**: Use containerized build environments for consistent results

This CLI-only setup provides a lightweight, scriptable Docker environment perfect for WSL plugin development without the overhead of Docker Desktop.


# INSTRUCTIONS FROM COPILOT

Here’s a comprehensive guide that consolidates everything you need to **install, configure, register, and monitor the Docker daemon (`dockerd`) as a Windows service** — tailored for your manual binary setup on Windows 11 Pro.

---

## 🐳 Docker Daemon Setup & Management on Windows (Manual Install)

### 📦 1. Install Docker Binaries

Place the following files in a permanent directory, e.g.:
```
C:\Docker\
```
- `dockerd.exe`
- `docker.exe`

Add this folder to your system `PATH`:
```powershell
[Environment]::SetEnvironmentVariable("Path", $env:Path + ";C:\Docker", "Machine")
```

---

### ⚙️ 2. Create a Configuration File (Optional but Recommended)

Create:
```
C:\Docker\daemon.json
```

Example contents:
```json
{
  "hosts": ["npipe://"],
  "experimental": false,
  "debug": true
}
```

---

### 🛠️ 3. Register `dockerd` as a Windows Service

Use `sc.exe` to register the service:
```powershell
sc.exe create Docker binPath= "C:\Docker\dockerd.exe --config-file=C:\Docker\daemon.json" start= auto
```

> ⚠️ Note: There must be a space after `binPath=` and `start=` — this is required by `sc.exe`.

---

### 🔄 4. Start and Enable the Service

Start the service:
```powershell
Start-Service Docker
```

Set it to start automatically on boot:
```powershell
Set-Service Docker -StartupType Automatic
```

---

### 🔍 5. Check Docker Service Status (Windows Equivalent of `systemctl`)

Use PowerShell to inspect the service:

```powershell
Get-Service Docker
```

Output fields:
- `Status`: `Running`, `Stopped`, etc.
- `StartType`: `Automatic`, `Manual`, `Disabled`
- `DisplayName`: Should be `Docker Engine`

To get detailed info:
```powershell
Get-WmiObject -Class Win32_Service -Filter "Name='Docker'" | Select-Object *
```

---

### 🧹 6. Remove or Reconfigure the Service

To delete the service:
```powershell
sc.exe delete Docker
```

To change the startup type:
```powershell
Set-Service Docker -StartupType Manual
```

---

### 🧪 7. Test Docker Functionality

Verify Docker CLI is working:
```bash
docker version
```

Try pulling a small image:
```bash
docker pull mcr.microsoft.com/windows/nanoserver:ltsc2022
```

---

### 🧯 8. Troubleshooting Extraction Hangs

If `docker pull` hangs during extraction:

1. **Kill stuck `dockerd` processes**:
   ```powershell
   Get-Process dockerd | ForEach-Object { Stop-Process -Id $_.Id -Force }
   ```

2. **Clean Docker temp state**:
   Delete contents of:
   ```
   C:\ProgramData\Docker\windowsfilter
   C:\ProgramData\Docker\image\windows
   C:\ProgramData\Docker\containers
   C:\ProgramData\Docker\tmp
   ```

3. **Restart the service**:
   ```powershell
   Start-Service Docker
   ```

---

# Docker Build Troubleshooting

## Step-by-step instructions for diagnosing a stuck Windows container build

You can inspect the running container even during a stuck build. Here's how to diagnose it:

Step 1: Find the Running Container
bashdocker.exe ps -a
Look for a container with status "Up" or the one being built. Note its CONTAINER ID.
Step 2: Execute Commands Inside the Stuck Container
bash# Replace <container-id> with the ID from step 1

# See all running processes
docker.exe exec <container-id> powershell -Command "Get-Process | Select-Object Name, Id, Path, StartTime | Sort-Object StartTime | Format-Table -AutoSize"

# Look specifically for VS-related processes
docker.exe exec <container-id> powershell -Command "Get-Process | Where-Object {$_.Name -like '*vs*' -or $_.Name -like '*VSInstaller*' -or $_.Name -like '*VBCSCompiler*' -or $_.Name -like '*MSBuild*'} | Format-Table Name, Id, Path -AutoSize"

# Check for any processes with open file handles in BuildTools
docker.exe exec <container-id> powershell -Command "Get-Process | Where-Object {$_.Path -like 'C:\BuildTools*'} | Format-Table Name, Id, Path -AutoSize"
Step 3: Check for Specific Culprits
Common processes that hang VS installations:
bash# Check for telemetry and feedback processes
docker.exe exec <container-id> powershell -Command "Get-Process | Where-Object {$_.Name -match 'PerfWatson|vstelemetry|feedback|ServiceHub'} | Format-Table Name, Id -AutoSize"

# Check for background installer processes
docker.exe exec <container-id> powershell -Command "Get-Process | Where-Object {$_.Name -match 'setup|installer'} | Format-Table Name, Id -AutoSize"
Step 4: View Container Logs
bash# See what Docker sees from the container
docker.exe logs <container-id>
Step 5: Interactive Debugging (Optional)
If you want to poke around more:
bash# Open an interactive PowerShell session
docker.exe exec -it <container-id> powershell
Then inside that session you can run:
powershellGet-Process | Format-Table
Get-ChildItem C:\BuildTools
Get-EventLog -LogName Application -Newest 20
What to Look For
The diagnostic output will likely show:

ServiceHub processes (telemetry)
PerfWatson (crash reporting)
vctip.exe (Customer Experience Improvement)
feedback.exe or similar

Any of these will prevent Docker from committing the layer.




## Fixing it
The VS Build Tools installation completed successfully, but Docker appears to be hanging before committing the layer and moving to Step 4/6. This is a common issue with VS Build Tools in Windows containers.

### The Problem
The VS installer often spawns background processes (telemetry, feedback collectors, etc.) that don't terminate even though the main installer exits. Docker waits for all processes in the container to exit before committing the layer, causing it to hang indefinitely.
### Immediate Solutions
#### Option 1: Add Process Cleanup (Recommended)
Modify your RUN command to explicitly kill lingering processes:
```dockerfile
RUN Write-Host 'Downloading VS Build Tools installer (~2MB)...' ; \
    Invoke-WebRequest -Uri 'https://aka.ms/vs/17/release/vs_buildtools.exe' -OutFile 'vs_buildtools.exe' ; \
    Write-Host 'Installing VS Build Tools and Windows SDK (~2GB)...' ; \
    Write-Host 'This will take 10-20 minutes...' ; \
    Start-Process -FilePath '.\vs_buildtools.exe' -ArgumentList @( \
        '--quiet', '--wait', '--norestart', '--nocache', \
        '--installPath', 'C:\BuildTools', \
        '--add', 'Microsoft.VisualStudio.Workload.VCTools', \
        '--add', 'Microsoft.VisualStudio.Workload.MSBuildTools', \
        '--add', 'Microsoft.VisualStudio.Component.Windows10SDK.19041', \
        '--add', 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64', \
        '--add', 'Microsoft.VisualStudio.Component.VC.CMake.Project' \
    ) -NoNewWindow -Wait ; \
    Write-Host 'VS Build Tools installation complete!' ; \
    Remove-Item '.\vs_buildtools.exe' ; \
    Write-Host 'Cleaning up background processes...' ; \
    Get-Process | Where-Object {$_.Name -like '*vs*' -or $_.Name -like '*VSInstaller*'} | Stop-Process -Force -ErrorAction SilentlyContinue ; \
    Start-Sleep -Seconds 5
```

### Option 2: Kill Current Stuck Build
Right now, you need to stop the hung build:
```bash
# Find and kill the stuck docker build
docker.exe ps -a  # Find the container ID
docker.exe kill <container-id>
docker.exe rm <container-id>

# Or force kill all docker processes
taskkill /F /IM dockerd.exe
taskkill /F /IM docker.exe
```

### Additional Improvements
Fix Your ENTRYPOINT Issue
Your current ENTRYPOINT has a problem - VsDevCmd.bat with && won't work as expected:
```dockerfile
# Replace this problematic ENTRYPOINT:
ENTRYPOINT ["C:\\BuildTools\\Common7\\Tools\\VsDevCmd.bat", "&&"]

# With this PowerShell wrapper:
ENTRYPOINT ["powershell", "-Command"]
CMD ["& 'C:\\BuildTools\\Common7\\Tools\\Launch-VsDevShell.ps1'; msbuild /?"]
```

Or better yet, create a wrapper script in your image:

```dockerfile
# Add before ENTRYPOINT
RUN Set-Content -Path C:\entrypoint.ps1 -Value @' \
& 'C:\BuildTools\Common7\Tools\Launch-VsDevShell.ps1' -Arch amd64 -HostArch amd64 \
if ($args.Count -gt 0) { \
    & $args[0] $args[1..($args.Count-1)] \
} \
'@

ENTRYPOINT ["powershell", "-File", "C:\\entrypoint.ps1"]
CMD ["msbuild", "/?"]
```

### Diagnostic Steps (For Next Time)
Add this to see what's running:
```dockerfile
RUN Write-Host 'Checking running processes...' ; \
    Get-Process | Select-Object Name, Id, CPU | Format-Table
`
```
