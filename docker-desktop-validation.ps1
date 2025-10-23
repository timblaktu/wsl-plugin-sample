# Docker Desktop with Hyper-V Validation Script
# Run as Administrator in PowerShell

Write-Host "=== Docker Desktop Installation Validation ===" -ForegroundColor Green
Write-Host "Date: $(Get-Date)" -ForegroundColor Yellow
Write-Host ""

# 1. Check Docker Services
Write-Host "1. Docker Services Status:" -ForegroundColor Cyan
try {
    Get-Service -Name "com.docker.service" -ErrorAction Stop | Format-Table -AutoSize
    Get-Service -Name "docker" -ErrorAction SilentlyContinue | Format-Table -AutoSize
} catch {
    Write-Host "Error checking services: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# 2. Check Docker Version and Info
Write-Host "2. Docker Version and Configuration:" -ForegroundColor Cyan
try {
    & docker version
    Write-Host ""
    & docker info
} catch {
    Write-Host "Error running docker commands: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# 3. Check Windows Features (Hyper-V related)
Write-Host "3. Windows Virtualization Features:" -ForegroundColor Cyan
$features = @(
    "Microsoft-Hyper-V-All",
    "Microsoft-Hyper-V-Management-PowerShell",
    "Microsoft-Hyper-V-Services",
    "Microsoft-Hyper-V-Hypervisor",
    "VirtualMachinePlatform",
    "Microsoft-Windows-Subsystem-Linux"
)

foreach ($feature in $features) {
    $status = Get-WindowsOptionalFeature -Online -FeatureName $feature -ErrorAction SilentlyContinue
    if ($status) {
        Write-Host "$feature`: $($status.State)" -ForegroundColor $(if($status.State -eq "Enabled") {"Green"} else {"Yellow"})
    } else {
        Write-Host "$feature`: Not Found" -ForegroundColor Red
    }
}
Write-Host ""

# 4. Test Basic Windows Container
Write-Host "4. Testing Basic Windows Container:" -ForegroundColor Cyan
try {
    Write-Host "Pulling Windows Server Core image..." -ForegroundColor Yellow
    & docker pull mcr.microsoft.com/windows/servercore:ltsc2022
    
    Write-Host "Testing container execution..." -ForegroundColor Yellow
    $result = & docker run --rm mcr.microsoft.com/windows/servercore:ltsc2022 cmd /c "echo SUCCESS && ver"
    Write-Host "Container test result: $result" -ForegroundColor Green
} catch {
    Write-Host "Container test failed: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# 5. Test Volume Mount
Write-Host "5. Testing Volume Mount:" -ForegroundColor Cyan
try {
    $testDir = "C:\temp\docker-test"
    if (!(Test-Path $testDir)) {
        New-Item -ItemType Directory -Path $testDir -Force | Out-Null
    }
    
    "Test content from host" | Out-File -FilePath "$testDir\test.txt" -Encoding ASCII
    
    Write-Host "Testing volume mount..." -ForegroundColor Yellow
    $mountResult = & docker run --rm -v "$testDir`:C:\work" mcr.microsoft.com/windows/servercore:ltsc2022 cmd /c "type C:\work\test.txt"
    Write-Host "Volume mount result: $mountResult" -ForegroundColor Green
    
    # Cleanup
    Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
} catch {
    Write-Host "Volume mount test failed: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# 6. Check Docker Desktop Backend
Write-Host "6. Docker Desktop Backend Configuration:" -ForegroundColor Cyan
try {
    $dockerDesktopSettings = Get-Content "$env:APPDATA\Docker\settings.json" -ErrorAction SilentlyContinue | ConvertFrom-Json
    if ($dockerDesktopSettings) {
        Write-Host "Docker Desktop Backend: $($dockerDesktopSettings.wslEngineEnabled)" -ForegroundColor $(if($dockerDesktopSettings.wslEngineEnabled -eq $false) {"Green"} else {"Red"})
        Write-Host "Hyper-V Backend: $($dockerDesktopSettings.hypervEnabled)" -ForegroundColor $(if($dockerDesktopSettings.hypervEnabled -eq $true) {"Green"} else {"Red"})
    } else {
        Write-Host "Could not read Docker Desktop settings" -ForegroundColor Yellow
    }
} catch {
    Write-Host "Error checking Docker Desktop settings: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

Write-Host "=== Validation Complete ===" -ForegroundColor Green
Write-Host "Please copy all output above and provide to Claude for analysis." -ForegroundColor Yellow