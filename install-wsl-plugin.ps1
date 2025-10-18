#Requires -RunAsAdministrator

[cmdletbinding(PositionalBinding = $false)]
param (
    [Parameter(Mandatory = $true, HelpMessage = "Path to the plugin DLL file")]
    [string]$PluginPath,
    [string]$PluginName = "demo-plugin",
    [string]$CertPath = "$PSScriptRoot\cert.pfx",
    [string]$CertSubject = "CN=WSL Plugin Development, O=Local Development, L=Local, S=Local, C=US",
    [string]$CertName = "WSL Plugin Development Certificate",
    [switch]$SkipTestSigning = $false,
    [switch]$Verbose = $false
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Function to check if running as administrator
function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Function to restart script with admin privileges
function Restart-AsAdministrator {
    $arguments = ""
    foreach ($key in $PSBoundParameters.Keys) {
        $value = $PSBoundParameters[$key]
        if ($value -is [switch]) {
            if ($value) {
                $arguments += " -$key"
            }
        } else {
            $arguments += " -$key `"$value`""
        }
    }
    
    Write-Host "🔒 Restarting with administrator privileges..." -ForegroundColor Yellow
    Start-Process PowerShell -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`"$arguments" -Verb RunAs
    exit
}

# Function to enable test signing mode
function Enable-TestSigning {
    Write-Host "🔧 Checking test signing mode..." -ForegroundColor Cyan
    
    $testSigningStatus = bcdedit /enum | Select-String "testsigning"
    if ($testSigningStatus -match "Yes") {
        Write-Host "✅ Test signing mode already enabled" -ForegroundColor Green
        return $false
    } else {
        Write-Host "⚙️  Enabling test signing mode..." -ForegroundColor Yellow
        bcdedit /set testsigning on
        Write-Host "✅ Test signing mode enabled" -ForegroundColor Green
        return $true
    }
}

# Function to sign the plugin
function Sign-Plugin {
    param($DllPath, $CertificatePath)
    
    Write-Host "🔐 Signing plugin: $DllPath" -ForegroundColor Cyan
    
    # Check if certificate exists, create if not
    if (!(Test-Path $CertificatePath)) {
        Write-Host "📜 Certificate not found. Creating self-signed certificate..." -ForegroundColor Yellow
        
        $certificate = New-SelfSignedCertificate `
            -KeyExportPolicy Exportable `
            -Type Custom `
            -Subject $CertSubject `
            -KeyUsage DigitalSignature `
            -FriendlyName $CertName `
            -CertStoreLocation "Cert:\CurrentUser\My" `
            -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.3", "2.5.29.19={text}") `
            -HashAlgorithm "SHA256" `
            -NotAfter (Get-Date).AddYears(10)
        
        # Export certificate to PFX
        $certbase64 = [System.Convert]::ToBase64String($certificate.RawData, [System.Base64FormattingOptions]::InsertLineBreaks)
        $key = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($certificate)
        $keyBytes = $key.Key.Export([System.Security.Cryptography.CngKeyBlobFormat]::Pkcs8PrivateBlob)
        $keyBase64 = [System.Convert]::ToBase64String($KeyBytes, [System.Base64FormattingOptions]::InsertLineBreaks)

        $pemContent = @"
-----BEGIN PRIVATE KEY-----
$keyBase64
-----END PRIVATE KEY-----
-----BEGIN CERTIFICATE-----
$certbase64
-----END CERTIFICATE-----
"@
        
        $pemContent | openssl pkcs12 -export -nodes -out "$CertificatePath" -passout pass:
        Write-Host "✅ Certificate created: $CertificatePath" -ForegroundColor Green
    }
    
    # Trust the certificate
    Write-Host "🛡️  Installing certificate to Trusted Root..." -ForegroundColor Yellow
    Import-PfxCertificate -FilePath $CertificatePath -CertStoreLocation Cert:\LocalMachine\Root | Out-Null
    Write-Host "✅ Certificate trusted" -ForegroundColor Green
    
    # Sign the plugin
    Write-Host "✍️  Signing plugin with SignTool..." -ForegroundColor Yellow
    $signResult = & SignTool.exe sign /a /v /fd SHA256 /f $CertificatePath $DllPath
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Plugin signed successfully" -ForegroundColor Green
    } else {
        throw "Failed to sign plugin. SignTool exit code: $LASTEXITCODE"
    }
}

# Function to register plugin in WSL
function Register-WSLPlugin {
    param($DllPath, $Name)
    
    Write-Host "📝 Registering WSL plugin..." -ForegroundColor Cyan
    
    $registryPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Lxss\Plugins"
    
    # Convert WSL path to Windows path if needed
    if ($DllPath -match "^/mnt/([a-z])/(.*)") {
        $drive = $matches[1].ToUpper()
        $path = $matches[2] -replace "/", "\"
        $windowsPath = "${drive}:\$path"
        Write-Host "🔄 Converted WSL path: $DllPath -> $windowsPath" -ForegroundColor Yellow
    } else {
        $windowsPath = $DllPath
    }
    
    # Get absolute path
    $absolutePath = (Resolve-Path $windowsPath).Path
    
    # Create registry path if it doesn't exist
    if (!(Test-Path $registryPath)) {
        New-Item -Path $registryPath -Force | Out-Null
        Write-Host "📁 Created registry path: $registryPath" -ForegroundColor Yellow
    }
    
    # Register the plugin
    Set-ItemProperty -Path $registryPath -Name $Name -Value $absolutePath -Force
    Write-Host "✅ Plugin registered: $Name -> $absolutePath" -ForegroundColor Green
    
    # Verify registration
    $registeredPath = Get-ItemProperty -Path $registryPath -Name $Name -ErrorAction SilentlyContinue
    if ($registeredPath.$Name -eq $absolutePath) {
        Write-Host "✅ Registration verified" -ForegroundColor Green
    } else {
        throw "Failed to verify plugin registration"
    }
}

# Function to restart WSL service
function Restart-WSLService {
    Write-Host "🔄 Restarting WSL service..." -ForegroundColor Cyan
    
    # Shutdown all WSL instances
    Write-Host "⏹️  Shutting down WSL..." -ForegroundColor Yellow
    wsl --shutdown
    Start-Sleep -Seconds 2
    
    # Restart LxssManager service
    Write-Host "🔄 Restarting LxssManager service..." -ForegroundColor Yellow
    Restart-Service -Name "LxssManager" -Force
    Start-Sleep -Seconds 3
    
    Write-Host "✅ WSL service restarted" -ForegroundColor Green
}

# Main execution
try {
    Write-Host "🚀 WSL Plugin Installation Script" -ForegroundColor Magenta
    Write-Host "=================================" -ForegroundColor Magenta
    
    # Check if running as administrator
    if (-not (Test-Administrator)) {
        Restart-AsAdministrator
        return
    }
    
    # Validate plugin file exists
    if (!(Test-Path $PluginPath)) {
        throw "Plugin file not found: $PluginPath"
    }
    
    $pluginInfo = Get-Item $PluginPath
    Write-Host "📄 Plugin: $($pluginInfo.Name) ($($pluginInfo.Length) bytes)" -ForegroundColor White
    
    # Step 1: Enable test signing mode (if not skipped)
    $rebootRequired = $false
    if (-not $SkipTestSigning) {
        $rebootRequired = Enable-TestSigning
    }
    
    # Step 2: Sign the plugin
    Sign-Plugin -DllPath $PluginPath -CertificatePath $CertPath
    
    # Step 3: Register plugin in WSL registry
    Register-WSLPlugin -DllPath $PluginPath -Name $PluginName
    
    # Step 4: Restart WSL service
    Restart-WSLService
    
    Write-Host ""
    Write-Host "🎉 Plugin installation completed successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "📋 Summary:" -ForegroundColor Cyan
    Write-Host "  Plugin: $PluginPath" -ForegroundColor White
    Write-Host "  Registry: HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Lxss\Plugins\$PluginName" -ForegroundColor White
    Write-Host "  Certificate: $CertPath" -ForegroundColor White
    Write-Host ""
    Write-Host "🔍 Next steps:" -ForegroundColor Cyan
    Write-Host "  1. Start your WSL distro: wsl -d <distro-name>" -ForegroundColor White
    Write-Host "  2. Check plugin log: C:\wsl-plugin-demo.txt" -ForegroundColor White
    Write-Host "  3. Monitor Windows Event Viewer for WSL service errors" -ForegroundColor White
    
    if ($rebootRequired) {
        Write-Host ""
        Write-Host "⚠️  REBOOT REQUIRED: Test signing mode was enabled" -ForegroundColor Red
        Write-Host "    Please reboot Windows for test signing to take effect" -ForegroundColor Red
    }
    
} catch {
    Write-Host ""
    Write-Host "❌ Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "💡 Troubleshooting tips:" -ForegroundColor Yellow
    Write-Host "  - Ensure you're running as Administrator" -ForegroundColor White
    Write-Host "  - Check that SignTool.exe is available in PATH" -ForegroundColor White
    Write-Host "  - Verify the plugin file exists and is not corrupted" -ForegroundColor White
    Write-Host "  - Check Windows Event Viewer for detailed error messages" -ForegroundColor White
    exit 1
}