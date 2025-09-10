#!/bin/bash
set -e

echo "==================================="
echo "Running aks common tests"
echo "=================================="

# Flutter should be available via Homebrew in PATH

# Get dependencies first
echo "Getting dependencies..."
flutter pub get

# Analyze code for issues
echo "Running Flutter analyze..."
flutter analyze --no-fatal-infos --no-fatal-warnings || {
    echo "Warning: Flutter analyze found issues (continuing anyway)"
}

# Format check (optional - can be strict)
echo "Checking code formatting..."
dart format --set-exit-if-changed --output=none . || {
    echo "Warning: Code formatting issues found"
    echo "Run 'dart format .' to fix formatting"
    # Uncomment the next line to make formatting checks strict
    # exit 1
}

# Run common tests (exclude platform-specific tests)
echo "Running common tests..."
if [ -d "test" ] && [ "$(ls -A test/*.dart 2>/dev/null)" ]; then
    # Run tests in test/ directory but exclude test/linux/
    flutter test --coverage --no-pub test/ --exclude "test/linux/**"
    
    # If you want to check coverage threshold (requires lcov)
    if command -v lcov &> /dev/null && [ -f "coverage/lcov.info" ]; then
        echo "Generating coverage report..."
        lcov --summary coverage/lcov.info
    fi
else
    echo "No tests found in test/ directory"
fi

echo "==================================="
echo "Common tests completed!"
echo "===================================="