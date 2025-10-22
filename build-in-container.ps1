# PowerShell wrapper script to build WSL plugin in Windows container
# For use when running directly from Windows PowerShell

param(
    [string]$Configuration = "Release",
    [string]$Platform = "x64"
)

$ContainerImage = "wsl-plugin-build:latest"
$ProjectPath = $PWD.Path

Write-Host "Building WSL plugin in Windows container..."
Write-Host "Mapping: $ProjectPath -> C:\work"

# Build the container image if it doesn't exist
$imageExists = docker images --format "table {{.Repository}}:{{.Tag}}" | Select-String $ContainerImage
if (-not $imageExists) {
    Write-Host "Container image not found. Building..."
    docker build -t $ContainerImage .
}

# Run the build command
Write-Host "Running MSBuild in container..."
docker run --rm --isolation=process `
    -v "${ProjectPath}:C:\work" `
    $ContainerImage `
    msbuild C:\work\wsl-plugin-sample.sln /p:Configuration=$Configuration /p:Platform=$Platform

Write-Host "Build complete! Check for output files in the current directory."