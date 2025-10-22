# Docker Manual Installation Complete Removal Script
# Run as Administrator in PowerShell
# PURPOSE: Completely remove manual Docker installation before Docker Desktop

Write-Host "=== DOCKER MANUAL INSTALLATION REMOVAL ===" -ForegroundColor Yellow
Write-Host "This script will completely remove manual Docker installation" -ForegroundColor Yellow
Write-Host "Run as Administrator only!" -ForegroundColor Red
Write-Host ""

# Check if running as Administrator
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "❌ ERROR: This script must be run as Administrator" -ForegroundColor Red
    Write-Host "Right-click PowerShell and select 'Run as Administrator'" -ForegroundColor Red
    exit 1
}

Write-Host "✅ Running as Administrator" -ForegroundColor Green
Write-Host ""

# Step 1: Stop Docker Service
Write-Host "🔄 Step 1: Stopping Docker Service..." -ForegroundColor Cyan
try {
    $dockerService = Get-Service -Name "docker" -ErrorAction SilentlyContinue
    if ($dockerService) {
        if ($dockerService.Status -eq "Running") {
            Write-Host "   Stopping docker service..." -ForegroundColor Yellow
            Stop-Service -Name "docker" -Force
            Write-Host "   ✅ Docker service stopped" -ForegroundColor Green
        } else {
            Write-Host "   ℹ️ Docker service already stopped" -ForegroundColor Blue
        }
    } else {
        Write-Host "   ℹ️ Docker service not found" -ForegroundColor Blue
    }
} catch {
    Write-Host "   ⚠️ Error stopping service: $($_.Exception.Message)" -ForegroundColor Yellow
}

# Step 2: Remove Windows Service
Write-Host ""
Write-Host "🔄 Step 2: Removing Docker Windows Service..." -ForegroundColor Cyan
try {
    $result = sc.exe delete docker 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "   ✅ Docker service deleted successfully" -ForegroundColor Green
    } else {
        Write-Host "   ℹ️ Docker service deletion result: $result" -ForegroundColor Blue
    }
} catch {
    Write-Host "   ⚠️ Error deleting service: $($_.Exception.Message)" -ForegroundColor Yellow
}

# Step 3: Find and Remove Docker Binaries
Write-Host ""
Write-Host "🔄 Step 3: Locating Docker Binary Installation..." -ForegroundColor Cyan

# Common Docker installation locations
$dockerPaths = @(
    "C:\Program Files\Docker",
    "C:\Program Files (x86)\Docker", 
    "C:\docker",
    "C:\tools\docker"
)

# Check where docker.exe is in PATH
$dockerInPath = Get-Command docker.exe -ErrorAction SilentlyContinue
if ($dockerInPath) {
    $dockerBinaryPath = Split-Path -Parent $dockerInPath.Source
    Write-Host "   Found docker.exe in PATH: $dockerBinaryPath" -ForegroundColor Yellow
    $dockerPaths += $dockerBinaryPath
}

foreach ($path in $dockerPaths) {
    if (Test-Path $path) {
        Write-Host "   Found Docker installation: $path" -ForegroundColor Yellow
        try {
            Remove-Item -Path $path -Recurse -Force
            Write-Host "   ✅ Removed: $path" -ForegroundColor Green
        } catch {
            Write-Host "   ❌ Failed to remove: $path - $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

# Step 4: Remove Docker Data Directory
Write-Host ""
Write-Host "🔄 Step 4: Removing Docker Data..." -ForegroundColor Cyan
$dockerDataPath = "C:\ProgramData\docker"
if (Test-Path $dockerDataPath) {
    Write-Host "   Found Docker data directory: $dockerDataPath" -ForegroundColor Yellow
    try {
        Remove-Item -Path $dockerDataPath -Recurse -Force
        Write-Host "   ✅ Removed Docker data directory" -ForegroundColor Green
    } catch {
        Write-Host "   ❌ Failed to remove Docker data: $($_.Exception.Message)" -ForegroundColor Red
    }
} else {
    Write-Host "   ℹ️ Docker data directory not found" -ForegroundColor Blue
}

# Step 5: Clean System PATH
Write-Host ""
Write-Host "🔄 Step 5: Cleaning Docker from System PATH..." -ForegroundColor Cyan
$systemPath = [System.Environment]::GetEnvironmentVariable("PATH", "Machine")
$pathEntries = $systemPath -split ";"
$dockerPathEntries = $pathEntries | Where-Object { $_ -like "*docker*" }

if ($dockerPathEntries) {
    Write-Host "   Found Docker entries in PATH:" -ForegroundColor Yellow
    $dockerPathEntries | ForEach-Object { Write-Host "     $_" -ForegroundColor Yellow }
    
    $cleanedPath = ($pathEntries | Where-Object { $_ -notlike "*docker*" }) -join ";"
    [System.Environment]::SetEnvironmentVariable("PATH", $cleanedPath, "Machine")
    Write-Host "   ✅ Removed Docker entries from PATH" -ForegroundColor Green
} else {
    Write-Host "   ℹ️ No Docker entries found in PATH" -ForegroundColor Blue
}

# Step 6: Registry Cleanup
Write-Host ""
Write-Host "🔄 Step 6: Registry Cleanup..." -ForegroundColor Cyan
$registryPaths = @(
    "HKLM:\SYSTEM\CurrentControlSet\Services\docker",
    "HKLM:\SOFTWARE\Docker Inc."
)

foreach ($regPath in $registryPaths) {
    if (Test-Path $regPath) {
        Write-Host "   Found registry entry: $regPath" -ForegroundColor Yellow
        try {
            Remove-Item -Path $regPath -Recurse -Force
            Write-Host "   ✅ Removed registry entry: $regPath" -ForegroundColor Green
        } catch {
            Write-Host "   ⚠️ Could not remove registry entry: $regPath" -ForegroundColor Yellow
        }
    } else {
        Write-Host "   ℹ️ Registry entry not found: $regPath" -ForegroundColor Blue
    }
}

# Step 7: Verification
Write-Host ""
Write-Host "🔄 Step 7: Verifying Complete Removal..." -ForegroundColor Cyan

# Check for remaining processes
$dockerProcesses = Get-Process | Where-Object { $_.ProcessName -like "*docker*" }
if ($dockerProcesses) {
    Write-Host "   ⚠️ Found remaining Docker processes:" -ForegroundColor Yellow
    $dockerProcesses | ForEach-Object { Write-Host "     $($_.ProcessName) (PID: $($_.Id))" -ForegroundColor Yellow }
} else {
    Write-Host "   ✅ No Docker processes found" -ForegroundColor Green
}

# Check for remaining services
$dockerServices = Get-Service | Where-Object { $_.Name -like "*docker*" }
if ($dockerServices) {
    Write-Host "   ⚠️ Found remaining Docker services:" -ForegroundColor Yellow
    $dockerServices | ForEach-Object { Write-Host "     $($_.Name) - $($_.Status)" -ForegroundColor Yellow }
} else {
    Write-Host "   ✅ No Docker services found" -ForegroundColor Green
}

# Test docker command
Write-Host ""
Write-Host "🔄 Testing docker command availability..." -ForegroundColor Cyan
try {
    $dockerTest = Get-Command docker.exe -ErrorAction SilentlyContinue
    if ($dockerTest) {
        Write-Host "   ⚠️ docker.exe still available at: $($dockerTest.Source)" -ForegroundColor Yellow
    } else {
        Write-Host "   ✅ docker.exe no longer available in PATH" -ForegroundColor Green
    }
} catch {
    Write-Host "   ✅ docker.exe no longer available" -ForegroundColor Green
}

Write-Host ""
Write-Host "=== DOCKER REMOVAL COMPLETE ===" -ForegroundColor Green
Write-Host "System is ready for Docker Desktop installation" -ForegroundColor Green
Write-Host ""
Write-Host "📝 NEXT STEPS:" -ForegroundColor Cyan
Write-Host "1. Restart Windows (recommended)" -ForegroundColor White
Write-Host "2. Install Docker Desktop with Hyper-V backend" -ForegroundColor White
Write-Host "3. Ensure Hyper-V backend is selected (NOT WSL2)" -ForegroundColor White
Write-Host ""
Write-Host "Press any key to exit..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")