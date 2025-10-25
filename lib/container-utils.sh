#!/usr/bin/env bash
# WSL Plugin Container Utilities Library
# Shared functions for Windows container operations

set -euo pipefail

# Convert WSL path to corresponding Windows sync path
wsl_to_windows_sync_path() {
    local wsl_path=$(realpath "${1:-.}" 2>/dev/null || echo "${1:-.}")
    local base_windows_path="C:\\wsl-sync"
    
    # Remove leading slash and convert remaining slashes to backslashes
    local sanitized_path="${wsl_path#/}"
    sanitized_path="${sanitized_path//\//\\}"
    
    # Construct and echo full Windows path
    echo "${base_windows_path}\\${WSL_DISTRO_NAME}\\${sanitized_path}"
}

# Sync current directory to Windows filesystem for container access
sync_to_windows() {
    local wsl_path=$(realpath "${1:-.}" 2>/dev/null || echo "${1:-.}")
    local wsl_path_from_win=$(wslpath -w "$wsl_path")
    local win_path=$(wsl_to_windows_sync_path "$wsl_path")
    local win_path_from_wsl=$(wslpath "$win_path")
    
    echo "📁 Syncing project to Windows container filesystem..."
    echo "   WSL path: $wsl_path"
    echo "   Windows path: $win_path"
    
    local branch=$(git branch --show-current) 

    echo "📝 Committing local changes before syncing to Windows..."
    local commit_msg=$(~/src/nixcfg/home/files/bin/claudefuncs.sh 2>/dev/null || echo "Update files for container build")
    ( set -x; git add -A; git commit -m "$commit_msg" || true )

    if [ ! -d "$win_path_from_wsl" ]; then
        mkdir -p "$(dirname "$win_path_from_wsl")"
        echo "🔄 Cloning repository to Windows filesystem..."
        ( set -x; git clone -b $branch "$wsl_path" "$win_path_from_wsl"
          git -C "$win_path_from_wsl" remote add wsl "$wsl_path" )
    else
        echo "🔄 Updating repository on Windows filesystem..."
        ( set -x; git -C "$win_path_from_wsl" pull wsl $branch )
    fi
}

# Check if container image exists
check_container_image() {
    local image="${1:-wsl-plugin-build:latest}"
    if ! docker.exe images --format "table {{.Repository}}:{{.Tag}}" | grep -q "$image"; then
        echo "❌ Container image '$image' not found."
        echo "   Please run 'make container' first to create the base image."
        return 1
    fi
    return 0
}

# Execute command in Windows container with proper setup
run_in_container() {
    local command="$1"
    local windows_project_path="$(wsl_to_windows_sync_path .)"
    local container_image="${2:-wsl-plugin-build:latest}"
    
    ( set -x; 
      docker.exe run --rm \
        -v "$windows_project_path:C:\\work" \
        "$container_image" \
        powershell -Command "& { $command }"
    )
}

# Build plugin in Windows container
build_plugin_in_container() {
    echo "🔨 Building WSL plugin in Windows container..."
    
    check_container_image || return 1
    sync_to_windows
    
    local build_command='Write-Host \"Restoring NuGet packages...\"; C:\\BuildTools\\nuget.exe restore C:\\work\\packages.config -PackagesDirectory C:\\work\\packages; if ($LASTEXITCODE -ne 0) { Write-Host \"NuGet restore failed!\"; exit $LASTEXITCODE }; Write-Host \"Building plugin...\"; msbuild \"C:\\work\\wsl-plugin-sample.vcxproj\" /t:Rebuild /p:Configuration=Release /p:Platform=x64 \"/p:OutDir=C:\\work\\\"; if ($LASTEXITCODE -ne 0) { Write-Host \"Plugin build failed!\"; exit $LASTEXITCODE }; Write-Host \"Plugin built successfully!\";'
    
    run_in_container "$build_command"
    
    # Copy built plugin back to WSL working directory
    local win_path_from_wsl=$(wslpath "$(wsl_to_windows_sync_path .)")
    if [ -f "$win_path_from_wsl/wsl-plugin-sample.dll" ]; then
        cp "$win_path_from_wsl/wsl-plugin-sample.dll" .
        echo "📋 Plugin copied to working directory"
    else
        echo "⚠️  Plugin not found in Windows sync directory"
    fi
}

# Build and run unit tests in Windows container
build_and_run_tests_in_container() {
    echo "🧪 Building and running unit tests in Windows container..."
    
    check_container_image || return 1
    sync_to_windows
    
    local test_command='Write-Host \"Restoring NuGet packages...\"; C:\\BuildTools\\nuget.exe restore C:\\work\\packages.config -PackagesDirectory C:\\work\\packages; if ($LASTEXITCODE -ne 0) { Write-Host \"NuGet restore failed!\"; exit $LASTEXITCODE }; Write-Host \"Building unit tests...\"; msbuild \"C:\\work\\wsl-plugin-tests.vcxproj\" /t:Rebuild /p:Configuration=Release /p:Platform=x64 \"/p:OutDir=C:\\work\\test-build\\\"; if ($LASTEXITCODE -ne 0) { Write-Host \"Test build failed!\"; exit $LASTEXITCODE }; if (Test-Path \"C:\\work\\test-build\\wsl-plugin-tests.exe\") { Write-Host \"Running unit tests...\"; Set-Location \"C:\\work\\test-build\"; .\\wsl-plugin-tests.exe; $testExitCode = $LASTEXITCODE; Write-Host \"Tests completed with exit code: $testExitCode\"; exit $testExitCode; } else { Write-Host \"Test executable not found!\"; Get-ChildItem C:\\work\\test-build -ErrorAction SilentlyContinue; exit 1; }'
    
    run_in_container "$test_command"
}