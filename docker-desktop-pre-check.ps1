# Docker Desktop Pre-Installation Diagnostic Script
# Run as Administrator in PowerShell
# Provides comprehensive system readiness assessment

Write-Host "=== Docker Desktop Pre-Installation Diagnostic ===" -ForegroundColor Cyan
Write-Host "System: $env:COMPUTERNAME" -ForegroundColor Green
Write-Host "User: $env:USERNAME" -ForegroundColor Green
Write-Host "Date: $(Get-Date)" -ForegroundColor Green
Write-Host ""

# Check if running as admin
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
if (-not $isAdmin) {
    Write-Host "❌ ERROR: This script must be run as Administrator" -ForegroundColor Red
    exit 1
}

Write-Host "✅ Running as Administrator" -ForegroundColor Green
Write-Host ""

# 1. Current Docker Status
Write-Host "=== Current Docker Installation ===" -ForegroundColor Yellow
try {
    $dockerVersion = & docker --version 2>$null
    Write-Host "✅ Docker found: $dockerVersion" -ForegroundColor Green
    
    $dockerInfo = & docker info 2>$null
    if ($dockerInfo -match "OSType:\s*windows") {
        Write-Host "✅ Docker configured for Windows containers" -ForegroundColor Green
    }
    
    # Check Docker service
    $dockerService = Get-Service -Name "docker" -ErrorAction SilentlyContinue
    if ($dockerService) {
        Write-Host "✅ Docker service status: $($dockerService.Status)" -ForegroundColor Green
    }
} catch {
    Write-Host "❌ Docker not found or not functional" -ForegroundColor Red
}
Write-Host ""

# 2. System Requirements Check
Write-Host "=== System Requirements ===" -ForegroundColor Yellow

# OS Version
$osInfo = Get-WmiObject -Class Win32_OperatingSystem
Write-Host "OS: $($osInfo.Caption) (Build $($osInfo.BuildNumber))" -ForegroundColor White

# Check Windows 10/11 Pro/Enterprise/Education
if ($osInfo.Caption -match "(Pro|Enterprise|Education)" -and $osInfo.BuildNumber -ge 19041) {
    Write-Host "✅ OS supports Docker Desktop with Hyper-V" -ForegroundColor Green
} else {
    Write-Host "❌ OS may not support Docker Desktop with Hyper-V" -ForegroundColor Red
}

# Memory check
$memory = [math]::Round((Get-WmiObject -Class Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
Write-Host "RAM: ${memory} GB" -ForegroundColor White
if ($memory -ge 4) {
    Write-Host "✅ Sufficient RAM for Docker Desktop" -ForegroundColor Green
} else {
    Write-Host "⚠️  Low RAM - Docker Desktop may struggle" -ForegroundColor Yellow
}
Write-Host ""

# 3. Hyper-V Status Check
Write-Host "=== Hyper-V Configuration ===" -ForegroundColor Yellow

# Check Hyper-V feature
$hypervFeature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -ErrorAction SilentlyContinue
if ($hypervFeature -and $hypervFeature.State -eq "Enabled") {
    Write-Host "✅ Hyper-V feature is enabled" -ForegroundColor Green
} else {
    Write-Host "❌ Hyper-V feature is not enabled" -ForegroundColor Red
}

# Check Hyper-V services
$hypervServices = @("vmms", "vmcompute")
foreach ($service in $hypervServices) {
    $svc = Get-Service -Name $service -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq "Running") {
        Write-Host "✅ $service service is running" -ForegroundColor Green
    } else {
        Write-Host "❌ $service service is not running" -ForegroundColor Red
    }
}

# Check virtualization support
try {
    $cpu = Get-WmiObject -Class Win32_Processor | Select-Object -First 1
    $virtSupport = $cpu.VirtualizationFirmwareEnabled
    if ($virtSupport) {
        Write-Host "✅ CPU virtualization is enabled in BIOS/UEFI" -ForegroundColor Green
    } else {
        Write-Host "❌ CPU virtualization is not enabled in BIOS/UEFI" -ForegroundColor Red
    }
} catch {
    Write-Host "⚠️  Could not check virtualization support" -ForegroundColor Yellow
}
Write-Host ""

# 4. Container Features Check
Write-Host "=== Windows Container Features ===" -ForegroundColor Yellow
$containerFeature = Get-WindowsOptionalFeature -Online -FeatureName Containers -ErrorAction SilentlyContinue
if ($containerFeature -and $containerFeature.State -eq "Enabled") {
    Write-Host "✅ Windows Containers feature is enabled" -ForegroundColor Green
} else {
    Write-Host "❌ Windows Containers feature is not enabled" -ForegroundColor Red
}
Write-Host ""

# 5. Conflicting Software Check
Write-Host "=== Potential Conflicts ===" -ForegroundColor Yellow

# Check for VirtualBox
$vboxService = Get-Service -Name "VBoxSVC" -ErrorAction SilentlyContinue
if ($vboxService) {
    Write-Host "⚠️  VirtualBox detected - may conflict with Hyper-V" -ForegroundColor Yellow
} else {
    Write-Host "✅ No VirtualBox conflict detected" -ForegroundColor Green
}

# Check for VMware
$vmwareServices = Get-Service -Name "VMware*" -ErrorAction SilentlyContinue
if ($vmwareServices) {
    Write-Host "⚠️  VMware services detected - may conflict with Hyper-V" -ForegroundColor Yellow
} else {
    Write-Host "✅ No VMware conflict detected" -ForegroundColor Green
}
Write-Host ""

# 6. Recommendations
Write-Host "=== RECOMMENDATIONS ===" -ForegroundColor Magenta

$needsDockerDesktop = $true
$needsHypervEnable = $false
$needsContainerEnable = $false

if (-not $hypervFeature -or $hypervFeature.State -ne "Enabled") {
    $needsHypervEnable = $true
    Write-Host "❗ REQUIRED: Enable Hyper-V feature" -ForegroundColor Red
}

if (-not $containerFeature -or $containerFeature.State -ne "Enabled") {
    $needsContainerEnable = $true
    Write-Host "❗ REQUIRED: Enable Windows Containers feature" -ForegroundColor Red
}

if ($needsDockerDesktop) {
    Write-Host "❗ REQUIRED: Install Docker Desktop" -ForegroundColor Red
    Write-Host "   - Download from: https://desktop.docker.com/win/main/amd64/Docker%20Desktop%20Installer.exe" -ForegroundColor White
    Write-Host "   - CRITICAL: Choose Hyper-V backend (NOT WSL2)" -ForegroundColor White
}

Write-Host ""
Write-Host "=== NEXT STEPS ===" -ForegroundColor Cyan
if ($needsHypervEnable -or $needsContainerEnable) {
    Write-Host "1. Enable required Windows features (will require restart)" -ForegroundColor White
    if ($needsHypervEnable) {
        Write-Host "   Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All" -ForegroundColor Gray
    }
    if ($needsContainerEnable) {
        Write-Host "   Enable-WindowsOptionalFeature -Online -FeatureName Containers" -ForegroundColor Gray
    }
    Write-Host "2. Restart computer" -ForegroundColor White
    Write-Host "3. Install Docker Desktop with Hyper-V backend" -ForegroundColor White
} else {
    Write-Host "1. Install Docker Desktop with Hyper-V backend" -ForegroundColor White
    Write-Host "2. Configure for Windows containers" -ForegroundColor White
}

Write-Host ""
Write-Host "=== Diagnostic Complete ===" -ForegroundColor Cyan