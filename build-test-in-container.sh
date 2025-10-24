#!/bin/bash
set -euo pipefail

echo "🧪 Building WSL Plugin Test Program..."

# Sync to Windows filesystem
./build-in-container.sh -SkipBuild

echo "📦 Building test program in Windows container..."

# Use winget installed MSVC in container
docker run --rm \
    -v "C:/wsl-sync/NixOS/home/tim/src/wsl-plugin-sample:C:/work" \
    -w "C:/work" \
    mcr.microsoft.com/windows/servercore:ltsc2022 \
    cmd /c '
        echo "Setting up MSVC environment..."
        call "C:\BuildTools\VC\Auxiliary\Build\vcvars64.bat" > nul
        
        echo "Compiling test program..."
        cl.exe /EHsc /std:c++17 test-plugin-functions.cpp /Fe:test-plugin-functions.exe
        
        echo "Running test program..."
        test-plugin-functions.exe
    '

echo "✅ Test program execution completed!"