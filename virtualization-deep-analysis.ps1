# Deep Virtualization Architecture Analysis - Fixed Version
# Investigates WSL2, Hyper-V, and CPU virtualization relationships
# Run as Administrator in PowerShell

Write-Host "=== Deep Virtualization Architecture Analysis ===" -ForegroundColor Cyan
Write-Host "Investigating WSL2 vs Hyper-V vs CPU Virtualization" -ForegroundColor White
Write-Host "System: $env:COMPUTERNAME | Date: $(Get-Date)" -ForegroundColor Green
Write-Host ""

# Check if running as admin
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
if (-not $isAdmin) {
    Write-Host "ERROR: This script must be run as Administrator" -ForegroundColor Red
    exit 1
}

# 1. CPU Virtualization Deep Check
Write-Host "=== 1. CPU VIRTUALIZATION ANALYSIS ===" -ForegroundColor Yellow

# Method 1: systeminfo.exe (most reliable)
Write-Host "Method 1: systeminfo.exe" -ForegroundColor White
try {
    $systemInfo = & systeminfo.exe
    $hypervLines = $systemInfo | Where-Object { $_ -match "Hyper-V|Virtualization" }
    if ($hypervLines) {
        $hypervLines | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
    } else {
        Write-Host "  No Hyper-V/Virtualization info in systeminfo" -ForegroundColor Yellow
    }
} catch {
    Write-Host "  systeminfo failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Method 2: WMI Win32_Processor
Write-Host "`nMethod 2: WMI Win32_Processor" -ForegroundColor White
try {
    $cpu = Get-WmiObject -Class Win32_Processor | Select-Object -First 1
    Write-Host "  CPU: $($cpu.Name)" -ForegroundColor Gray
    Write-Host "  VirtualizationFirmwareEnabled: $($cpu.VirtualizationFirmwareEnabled)" -ForegroundColor Gray
} catch {
    Write-Host "  WMI query failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""

# 2. Windows Features Analysis
Write-Host "=== 2. WINDOWS FEATURES ARCHITECTURE ===" -ForegroundColor Yellow

# Check Virtual Machine Platform (WSL2 requirement)
Write-Host "Virtual Machine Platform (WSL2 requirement):" -ForegroundColor White
$vmpFeature = Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -ErrorAction SilentlyContinue
if ($vmpFeature) {
    $vmpColor = if ($vmpFeature.State -eq "Enabled") { "Green" } else { "Red" }
    Write-Host "  Status: $($vmpFeature.State)" -ForegroundColor $vmpColor
} else {
    Write-Host "  Feature not found" -ForegroundColor Red
}

# Check Windows Subsystem for Linux
Write-Host "`nWindows Subsystem for Linux:" -ForegroundColor White
$wslFeature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -ErrorAction SilentlyContinue
if ($wslFeature) {
    $wslColor = if ($wslFeature.State -eq "Enabled") { "Green" } else { "Red" }
    Write-Host "  Status: $($wslFeature.State)" -ForegroundColor $wslColor
} else {
    Write-Host "  Feature not found" -ForegroundColor Red
}

# Check Windows Hypervisor Platform (WSL2 uses this)
Write-Host "`nWindows Hypervisor Platform (WSL2 uses this):" -ForegroundColor White
$hvpFeature = Get-WindowsOptionalFeature -Online -FeatureName HypervisorPlatform -ErrorAction SilentlyContinue
if ($hvpFeature) {
    $hvpColor = if ($hvpFeature.State -eq "Enabled") { "Green" } else { "Red" }
    Write-Host "  Status: $($hvpFeature.State)" -ForegroundColor $hvpColor
} else {
    Write-Host "  Feature not found" -ForegroundColor Red
}

# Check Hyper-V Platform (Full Hyper-V)
Write-Host "`nHyper-V Platform (Full Hyper-V for Windows containers):" -ForegroundColor White
$hypervPlatform = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -ErrorAction SilentlyContinue
if ($hypervPlatform) {
    $hypervColor = if ($hypervPlatform.State -eq "Enabled") { "Green" } else { "Red" }
    Write-Host "  Status: $($hypervPlatform.State)" -ForegroundColor $hypervColor
} else {
    Write-Host "  Feature not found" -ForegroundColor Red
}

Write-Host ""

# 3. WSL2 Status Analysis
Write-Host "=== 3. WSL2 ANALYSIS ===" -ForegroundColor Yellow

# Check WSL version and distributions
Write-Host "WSL Version and Distributions:" -ForegroundColor White
try {
    $wslStatus = & wsl --status 2>$null
    if ($wslStatus) {
        $wslStatus | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
    }
    
    Write-Host "`nWSL Distributions:" -ForegroundColor White
    $wslList = & wsl --list --verbose 2>$null
    if ($wslList) {
        $wslList | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
    }
} catch {
    Write-Host "  WSL commands failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""

# 4. Hypervisor Detection
Write-Host "=== 4. HYPERVISOR DETECTION ===" -ForegroundColor Yellow

# Check if hypervisor is detected
Write-Host "Hypervisor Detection Methods:" -ForegroundColor White

# Registry check
try {
    $hvStatus = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "HypervisorLaunchType" -ErrorAction SilentlyContinue
    if ($hvStatus) {
        Write-Host "  Registry HypervisorLaunchType: $($hvStatus.HypervisorLaunchType)" -ForegroundColor Gray
        Write-Host "    (0=Off, 1=Auto/On, 2=Manual)" -ForegroundColor Gray
    }
} catch {
    Write-Host "  Registry check failed" -ForegroundColor Yellow
}

Write-Host ""

# 5. Architecture Summary
Write-Host "=== 5. ARCHITECTURE ANALYSIS SUMMARY ===" -ForegroundColor Magenta

Write-Host "`nWSL2 vs Hyper-V Architecture:" -ForegroundColor White
Write-Host "  WSL2 Requirements:" -ForegroundColor Gray
Write-Host "    - Virtual Machine Platform (VirtualMachinePlatform)" -ForegroundColor Gray
Write-Host "    - Windows Hypervisor Platform (HypervisorPlatform)" -ForegroundColor Gray
Write-Host "    - Does NOT require full Hyper-V role" -ForegroundColor Gray
Write-Host ""
Write-Host "  Windows Containers Requirements:" -ForegroundColor Gray
Write-Host "    - Full Hyper-V role (Microsoft-Hyper-V)" -ForegroundColor Gray
Write-Host "    - Can coexist with WSL2 but may conflict" -ForegroundColor Gray
Write-Host ""

# 6. Analysis Conclusions
Write-Host "ANALYSIS CONCLUSIONS:" -ForegroundColor Cyan

$vmpEnabled = $vmpFeature -and $vmpFeature.State -eq "Enabled"
$hvpEnabled = $hvpFeature -and $hvpFeature.State -eq "Enabled"
$hypervEnabled = $hypervPlatform -and $hypervPlatform.State -eq "Enabled"

if ($vmpEnabled -and $hvpEnabled -and -not $hypervEnabled) {
    Write-Host "PERFECT WSL2 SETUP DETECTED:" -ForegroundColor Green
    Write-Host "  - Virtual Machine Platform: Enabled (WSL2 requirement)" -ForegroundColor Green
    Write-Host "  - Windows Hypervisor Platform: Enabled (WSL2 requirement)" -ForegroundColor Green
    Write-Host "  - Full Hyper-V: Disabled (as expected for WSL2-only)" -ForegroundColor Green
    Write-Host ""
    Write-Host "IMPORTANT FINDING:" -ForegroundColor Red
    Write-Host "  Your system is optimized for WSL2, not full Hyper-V!" -ForegroundColor Red
    Write-Host "  This explains why CPU virtualization appears disabled" -ForegroundColor Yellow
    Write-Host "  - WSL2 uses lightweight hypervisor platform" -ForegroundColor Yellow
    Write-Host "  - Full Hyper-V uses different virtualization layer" -ForegroundColor Yellow
} elseif ($hypervEnabled) {
    Write-Host "FULL HYPER-V DETECTED:" -ForegroundColor Green
    Write-Host "  Ready for Windows containers with Hyper-V backend" -ForegroundColor Green
} else {
    Write-Host "MIXED OR INCOMPLETE CONFIGURATION" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== Analysis Complete ===" -ForegroundColor Cyan