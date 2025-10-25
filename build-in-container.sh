#!/usr/bin/env bash
# Wrapper script to build WSL plugin in Windows container
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
    
    echo "wsl_path=$wsl_path"
    echo "wsl_path_from_win=$wsl_path_from_win"
    echo "win_path=$win_path"
    echo "win_path_from_wsl=$win_path_from_wsl"
    
    local branch=$(git branch --show-current) 

    echo "commmitting local changes before syncing to Windows.."
    ( set -x; git commit -av )

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
    LOGFILE="container-build.log"
    echo "Building container image..."
    docker.exe --debug build -t "$CONTAINER_IMAGE" . 2>&1 | tee "$LOGFILE"
    if [ ${PIPESTATUS[0]} -ne 0 ]; then
        echo "Container build failed! Check $LOGFILE for details."
        exit 1
    fi
fi

echo "Synchronizing project path on Windows host filesystem..."
sync_to_windows

WINDOWS_PROJECT_PATH="$(wsl_to_windows_sync_path .)"
echo "Building WSL plugin in Windows container..."
( set -x; 
  # --isolation=process 
  docker.exe --debug run --rm \
    -v "$WINDOWS_PROJECT_PATH:C:\\work" \
    "$CONTAINER_IMAGE" \
    powershell -Command "& { 
        C:\BuildTools\nuget.exe restore C:\work\packages.config -PackagesDirectory C:\work\packages;
        if (\$LASTEXITCODE -ne 0) { exit \$LASTEXITCODE }
        msbuild 'C:\work\wsl-plugin-sample.sln' /t:Rebuild /p:Configuration=Release /p:Platform=x64 '/p:OutDir=C:\work\build\'
        exit \$LASTEXITCODE
    }"
  )

# Capture the exit code from docker
BUILD_EXIT_CODE=$?

if [ $BUILD_EXIT_CODE -eq 0 ]; then
    echo "Build successful! Output files:"
    tree "$(wslpath "$WINDOWS_PROJECT_PATH"/build)" 2>/dev/null || echo "No output files found"
else
    echo "Build FAILED with exit code: $BUILD_EXIT_CODE"
    echo "Check the compiler output above for errors."
fi

# Exit with the actual build status - DUMMY CHANGE TO FORCE GIT SYNC
exit $BUILD_EXIT_CODE
