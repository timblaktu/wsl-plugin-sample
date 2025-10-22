# Docker Desktop Installation Guide with Hyper-V Backend
# Run as Administrator in PowerShell

Write-Host "=== Docker Desktop Installation Guide ===" -ForegroundColor Cyan
Write-Host "System: $env:COMPUTERNAME" -ForegroundColor Green
Write-Host "Date: $(Get-Date)" -ForegroundColor Green
Write-Host ""

# Step 1: Download Docker Desktop
Write-Host "=== STEP 1: Download Docker Desktop ===" -ForegroundColor Yellow
$downloadUrl = "https://desktop.docker.com/win/main/amd64/Docker%20Desktop%20Installer.exe"
$installerPath = "$env:TEMP\DockerDesktopInstaller.exe"

Write-Host "Downloading Docker Desktop installer..." -ForegroundColor White
Write-Host "URL: $downloadUrl" -ForegroundColor Gray
Write-Host "Destination: $installerPath" -ForegroundColor Gray

try {
    # Check if already downloaded
    if (Test-Path $installerPath) {
        $existingSize = (Get-Item $installerPath).Length
        Write-Host "✅ Installer already exists (Size: $([math]::Round($existingSize/1MB, 1)) MB)" -ForegroundColor Green
        $download = Read-Host "Re-download? (y/N)"
        if ($download -eq "y" -or $download -eq "Y") {
            Remove-Item $installerPath -Force
        }
    }
    
    if (-not (Test-Path $installerPath)) {
        Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath -UseBasicParsing
        $downloadedSize = (Get-Item $installerPath).Length
        Write-Host "✅ Download complete (Size: $([math]::Round($downloadedSize/1MB, 1)) MB)" -ForegroundColor Green
    }
} catch {
    Write-Host "❌ Download failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Please download manually from: $downloadUrl" -ForegroundColor White
    return
}

Write-Host ""

# Step 2: Stop current Docker service
Write-Host "=== STEP 2: Stop Current Docker Service ===" -ForegroundColor Yellow
try {
    $dockerService = Get-Service -Name "docker" -ErrorAction SilentlyContinue
    if ($dockerService -and $dockerService.Status -eq "Running") {
        Write-Host "Stopping current Docker service..." -ForegroundColor White
        Stop-Service -Name "docker" -Force
        Write-Host "✅ Docker service stopped" -ForegroundColor Green
    } else {
        Write-Host "✅ Docker service not running" -ForegroundColor Green
    }
} catch {
    Write-Host "⚠️  Could not stop Docker service: $($_.Exception.Message)" -ForegroundColor Yellow
}

Write-Host ""

# Step 3: Installation instructions
Write-Host "=== STEP 3: Install Docker Desktop ===" -ForegroundColor Yellow
Write-Host "🔥 CRITICAL INSTALLATION SETTINGS:" -ForegroundColor Red
Write-Host ""
Write-Host "1. Run the installer:" -ForegroundColor White
Write-Host "   & '$installerPath'" -ForegroundColor Gray
Write-Host ""
Write-Host "2. ⚠️  INSTALLATION OPTIONS - VERY IMPORTANT:" -ForegroundColor Red
Write-Host "   ✅ CHECK: 'Use Hyper-V instead of WSL 2'" -ForegroundColor Green
Write-Host "   ❌ UNCHECK: 'Use WSL 2 instead of Hyper-V'" -ForegroundColor Red
Write-Host "   ✅ CHECK: 'Add shortcut to desktop'" -ForegroundColor Green
Write-Host ""
Write-Host "3. During installation:" -ForegroundColor White
Write-Host "   - Installation will take 5-10 minutes" -ForegroundColor Gray
Write-Host "   - May require restart" -ForegroundColor Gray
Write-Host "   - Will replace manual Docker installation" -ForegroundColor Gray
Write-Host ""

# Step 4: Post-installation verification script
Write-Host "=== STEP 4: Post-Installation Verification ===" -ForegroundColor Yellow
Write-Host "After installation completes, run this verification:" -ForegroundColor White
Write-Host ""

$verificationScript = @'
# Docker Desktop Post-Installation Verification
Write-Host "=== Docker Desktop Verification ===" -ForegroundColor Cyan

# Wait for Docker Desktop to start
Write-Host "Waiting for Docker Desktop to initialize..." -ForegroundColor White
Start-Sleep -Seconds 10

# Check Docker version
try {
    $version = & docker --version
    Write-Host "✅ Docker version: $version" -ForegroundColor Green
} catch {
    Write-Host "❌ Docker command failed" -ForegroundColor Red
}

# Check Docker info
try {
    $info = & docker info 2>$null
    if ($info -match "OSType:\s*windows") {
        Write-Host "✅ Docker configured for Windows containers" -ForegroundColor Green
    } else {
        Write-Host "❌ Docker not configured for Windows containers" -ForegroundColor Red
    }
    
    if ($info -match "Isolation:\s*hyperv") {
        Write-Host "✅ Using Hyper-V isolation" -ForegroundColor Green
    } else {
        Write-Host "⚠️  Not using Hyper-V isolation" -ForegroundColor Yellow
    }
} catch {
    Write-Host "❌ Docker info failed" -ForegroundColor Red
}

# Test simple Windows container
Write-Host "Testing Windows container..." -ForegroundColor White
try {
    $testResult = & docker run --rm mcr.microsoft.com/windows/nanoserver:ltsc2022 cmd /c "echo SUCCESS"
    if ($testResult -match "SUCCESS") {
        Write-Host "✅ Windows container test PASSED" -ForegroundColor Green
    } else {
        Write-Host "❌ Windows container test FAILED" -ForegroundColor Red
    }
} catch {
    Write-Host "❌ Windows container test ERROR: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "✅ Verification complete" -ForegroundColor Green
'@

$verificationScript | Out-File -FilePath "$env:TEMP\docker-verify.ps1" -Encoding UTF8
Write-Host "Verification script saved to: $env:TEMP\docker-verify.ps1" -ForegroundColor Gray
Write-Host ""

# Step 5: Ready to install
Write-Host "=== READY TO INSTALL ===" -ForegroundColor Magenta
Write-Host "1. Run installer with Hyper-V backend selected" -ForegroundColor White
Write-Host "2. After installation, run verification script" -ForegroundColor White
Write-Host "3. Report results back to continue with container build testing" -ForegroundColor White
Write-Host ""

$proceed = Read-Host "Start Docker Desktop installation now? (Y/n)"
if ($proceed -ne "n" -and $proceed -ne "N") {
    Write-Host "🚀 Starting Docker Desktop installer..." -ForegroundColor Green
    Start-Process -FilePath $installerPath -Wait
    Write-Host ""
    Write-Host "✅ Installation completed!" -ForegroundColor Green
    Write-Host "🔄 If restart is required, please restart and then run verification script" -ForegroundColor Yellow
} else {
    Write-Host "📋 Installation postponed. Run when ready:" -ForegroundColor Yellow
    Write-Host "   & '$installerPath'" -ForegroundColor Gray
}