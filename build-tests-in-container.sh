#!/usr/bin/env bash
# Script to build and run unit tests in Windows container
set -e

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

sync_to_windows() {
    local wsl_path=$(realpath "${1:-.}" 2>/dev/null || echo "${1:-.}")
    local wsl_path_from_win=$(wslpath -w "$wsl_path")
    local win_path=$(wsl_to_windows_sync_path "$wsl_path")
    local win_path_from_wsl=$(wslpath "$win_path")
    
    echo "Syncing project to Windows container filesystem..."
    echo "wsl_path=$wsl_path"
    echo "win_path=$win_path"
    
    local branch=$(git branch --show-current) 

    echo "Committing local changes before syncing to Windows..."
    ( set -x; git add -A; git commit -m "Update test files for container build" || true )

    if [ ! -d "$win_path_from_wsl" ]; then
        mkdir -p "$(dirname "$win_path_from_wsl")"
        # Clone from WSL repo + add remote for future syncing
        ( set -x; git clone -b $branch "$wsl_path" "$win_path_from_wsl"
          git -C "$win_path_from_wsl" remote add wsl "$wsl_path" )
    else
        # Pull from WSL remote
        ( set -x; git -C "$win_path_from_wsl" pull wsl $branch )
    fi
}

CONTAINER_IMAGE="wsl-plugin-build:latest"
if ! docker.exe images --format "table {{.Repository}}:{{.Tag}}" | grep -q "$CONTAINER_IMAGE"; then
    echo "Container image not found. Please run build-in-container.sh first to create the base image."
    exit 1
fi

echo "Synchronizing project with test files to Windows host filesystem..."
sync_to_windows

WINDOWS_PROJECT_PATH="$(wsl_to_windows_sync_path .)"
echo "Building and running unit tests in Windows container..."

# Check what files are available in the container
echo "Checking container file structure..."
( set -x; 
  docker.exe run --rm \
    -v "$WINDOWS_PROJECT_PATH:C:\\work" \
    "$CONTAINER_IMAGE" \
    powershell -Command "& { 
        Write-Host 'Project files:';
        Get-ChildItem C:\work -Recurse | Select-Object Name, FullName | Format-Table -AutoSize;
        Write-Host 'Test files:';
        Get-ChildItem C:\work\tests -Recurse -ErrorAction SilentlyContinue | Select-Object Name, FullName | Format-Table -AutoSize;
    }"
)

echo "Building unit tests..."
( set -x; 
  docker.exe run --rm \
    -v "$WINDOWS_PROJECT_PATH:C:\\work" \
    "$CONTAINER_IMAGE" \
    powershell -Command "& { 
        # First restore NuGet packages
        Write-Host 'Restoring NuGet packages...';
        C:\BuildTools\nuget.exe restore C:\work\packages.config -PackagesDirectory C:\work\packages;
        if (\$LASTEXITCODE -ne 0) { 
            Write-Host 'NuGet restore failed!';
            exit \$LASTEXITCODE 
        }
        
        # Build the test executable
        Write-Host 'Building unit tests...';
        msbuild 'C:\work\wsl-plugin-tests.vcxproj' /t:Rebuild /p:Configuration=Release /p:Platform=x64 '/p:OutDir=C:\work\test-build\';
        if (\$LASTEXITCODE -ne 0) { 
            Write-Host 'Test build failed!';
            exit \$LASTEXITCODE 
        }
        
        # Check if test executable was created
        if (Test-Path 'C:\work\test-build\wsl-plugin-tests.exe') {
            Write-Host 'Test executable created successfully';
            
            # Change to test directory so relative paths work
            Set-Location 'C:\work\test-build';
            
            # Run the tests
            Write-Host 'Running unit tests...';
            .\wsl-plugin-tests.exe;
            \$testExitCode = \$LASTEXITCODE;
            
            Write-Host \"Tests completed with exit code: \$testExitCode\";
            exit \$testExitCode;
        } else {
            Write-Host 'Test executable not found!';
            Get-ChildItem C:\work\test-build -ErrorAction SilentlyContinue;
            exit 1;
        }
    }"
)

# Capture the exit code from docker
TEST_EXIT_CODE=$?

if [ $TEST_EXIT_CODE -eq 0 ]; then
    echo ""
    echo "✅ All unit tests passed!"
    echo "Test output files:"
    tree "$(wslpath "$WINDOWS_PROJECT_PATH"/test-build)" 2>/dev/null || echo "No test output files found"
else
    echo ""
    echo "❌ Unit tests FAILED with exit code: $TEST_EXIT_CODE"
    echo "Check the test output above for details."
fi

# Exit with the actual test status
exit $TEST_EXIT_CODE