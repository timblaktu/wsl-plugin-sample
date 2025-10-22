# Windows container for building WSL plugin with MS Build Tools
FROM mcr.microsoft.com/windows/servercore:ltsc2022

# Set PowerShell as default shell
SHELL ["powershell", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]

# Download and install VS Build Tools 2022 with progress indication
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
    Remove-Item '.\vs_buildtools.exe';

# Intent is to safely cleanup any hung processes in this order:
#     1. Kill processes (Stop-Process -Force)
#     2. Wait for termination (Start-Sleep)
#     3. Let Docker commit the layer
# (Probably unnecessary process cleanup code added when troubleshooting a hung docker build)
# 
# RUN Write-Host 'Cleaning up background processes...' ; \
#     Get-Process | Where-Object {$_.Name -like '*ServiceHub*' -or $_.Name -like '*PerfWatson*'} | Stop-Process -Force -ErrorAction SilentlyContinue ; \
#     Start-Sleep -Seconds 3

WORKDIR "C:\work"
COPY entrypoint.ps1 "C:\entrypoint.ps1"


# Create entrypoint script that always sets up VS dev environment on entry
# RUN $script = (@('& ''C:\BuildTools\Common7\Tools\Launch-VsDevShell.ps1'' -Arch amd64 -HostArch amd64', 'if ($args.Count -gt 0) {', '    & $args[0] $args[1..($args.Count-1)]', '    exit $LASTEXITCODE', '} else {', '    msbuild /?', '}') -join "`r`n") ; Set-Content -Path C:\entrypoint.ps1 -Value $script -Encoding ASCII

# RUN $script = @'
# & 'C:\BuildTools\Common7\Tools\Launch-VsDevShell.ps1' -Arch amd64 -HostArch amd64
# if ($args.Count -gt 0) {
#     & $args[0] $args[1..($args.Count-1)]
#     exit $LASTEXITCODE
# } else {
#     msbuild /?
# }
# '@ ; Set-Content -Path C:\entrypoint.ps1 -Value $script -Encoding ASCII

# RUN @( \
#     "& 'C:\BuildTools\Common7\Tools\Launch-VsDevShell.ps1' -Arch amd64 -HostArch amd64", \
#     "if (`$args.Count -gt 0) {", \
#     "    & `$args[0] `$args[1..(`$args.Count-1)]", \
#     "    exit `$LASTEXITCODE", \
#     "} else {", \
#     "    msbuild /?", \
#     "}" \
#     ) | Out-File -FilePath C:\entrypoint.ps1 -Encoding ASCII

# RUN "& 'C:\BuildTools\Common7\Tools\Launch-VsDevShell.ps1' -Arch amd64 -HostArch amd64", \
#     "if (`$args.Count -gt 0) {", \
#     "    & `$args[0] `$args[1..(`$args.Count-1)]", \
#     "    exit `$LASTEXITCODE", \
#     "} else {", \
#     "    msbuild /?", \
#     "}" | Out-File -FilePath C:\entrypoint.ps1 -Encoding ASCII

# RUN Set-Content -Path C:\entrypoint.ps1 -Value "& 'C:\BuildTools\Common7\Tools\Launch-VsDevShell.ps1' -Arch amd64 -HostArch amd64`nif (`$args.Count -gt 0) { & `$args[0] `$args[1..(`$args.Count-1)]; exit `$LASTEXITCODE } else { msbuild /? }" -Encoding ASCII

# RUN $content = "& 'C:\BuildTools\Common7\Tools\Launch-VsDevShell.ps1' -Arch amd64 -HostArch amd64`nif (`$args.Count -gt 0) {`n    & `$args[0] `$args[1..(`$args.Count-1)]`n    exit `$LASTEXITCODE`n} else {`n    msbuild /?`n}"; \
#     Set-Content -Path C:\entrypoint.ps1 -Value $content -Encoding ASCII

# RUN @' \
# & 'C:\BuildTools\Common7\Tools\Launch-VsDevShell.ps1' -Arch amd64 -HostArch amd64 \
# if ($args.Count -gt 0) { \
#     & $args[0] $args[1..($args.Count-1)] \
#     exit $LASTEXITCODE \
# } else { \
#     msbuild /? \
# } \
# '@ | Out-File -FilePath C:\entrypoint.ps1 -Encoding ASCII

# RUN $script = @(); \
#     $script += "& 'C:\BuildTools\Common7\Tools\Launch-VsDevShell.ps1' -Arch amd64 -HostArch amd64"; \
#     $script += "if (`$args.Count -gt 0) {"; \
#     $script += "    & `$args[0] `$args[1..(`$args.Count-1)]"; \
#     $script += "    exit `$LASTEXITCODE"; \
#     $script += "} else {"; \
#     $script += "    msbuild /?"; \
#     $script += "}"; \
#     $script | Out-File -FilePath C:\entrypoint.ps1 -Encoding ASCII;

ENTRYPOINT ["powershell", "-File", "C:\\entrypoint.ps1"]
CMD []
