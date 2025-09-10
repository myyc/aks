#!/bin/bash
set -e

echo "==================================="
echo "Running aks Linux-specific tests"
echo "=================================="

# Add Flutter to PATH if not already there
export PATH="$PATH:$HOME/flutter/bin"

# Get dependencies first
echo "Getting dependencies..."
flutter pub get

# Build native Linux libraries for tests
echo "Building Linux native libraries..."
if [ -f "scripts/build_test_libs.sh" ]; then
    bash scripts/build_test_libs.sh
else
    echo "Warning: build_test_libs.sh not found, skipping native library build"
fi

# Run Linux-specific tests
echo "Running Linux-specific tests..."
if [ -d "test/processors" ] && [ "$(ls -A test/processors/*.dart 2>/dev/null)" ]; then
    # Run tests with linux tag only
    flutter test --tags=linux --no-pub test/processors/
    
    echo "Linux-specific tests completed!"
else
    echo "No Linux-specific tests found"
fi

echo "==================================="
echo "Linux tests completed!"
echo "===================================="