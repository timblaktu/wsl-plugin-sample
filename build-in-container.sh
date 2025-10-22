#!/usr/bin/env bash
# Wrapper script to build WSL plugin in Windows container
set -e
CONTAINER_IMAGE="wsl-plugin-build:latest"
# WINDOWS_PROJECT_PATH=$(wslpath -w .)
WINDOWS_PROJECT_PATH="\\\\wsl\$\\NixOS$(pwd | sed 's|^|\\|g; s|/|\\|g')"
LOGFILE="container-build.log"

if ! docker.exe images --format "table {{.Repository}}:{{.Tag}}" | grep -q "$CONTAINER_IMAGE"; then
    echo "Building container image..."
    docker.exe --debug build -t "$CONTAINER_IMAGE" . 2>&1 | tee "$LOGFILE"
    if [ ${PIPESTATUS[0]} -ne 0 ]; then
        echo "Container build failed! Check $LOGFILE for details."
        exit 1
    fi
fi

echo "Building WSL plugin in Windows container..."
echo "Mapping: $(pwd) -> C:\\work"
docker.exe --debug run --rm --isolation=process \
    -v "$WINDOWS_PROJECT_PATH:C:\\work" \
    "$CONTAINER_IMAGE" \
    msbuild C:\\work\\wsl-plugin-sample.sln /p:Configuration=Release /p:Platform=x64

echo "Build complete! Check for output files in the current directory."
