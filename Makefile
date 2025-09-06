# Makefile for AKS RAW Photo Editor

.PHONY: all build test test-libs clean run help

# Default target
all: build

# Build the Flutter application
build:
	@echo "Building Flutter application..."
	flutter build linux

# Build native libraries for testing
test-libs:
	@echo "Building test libraries..."
	@bash scripts/build_test_libs.sh

# Run tests (builds libraries first if needed)
test: test-libs
	@echo "Running tests..."
	flutter test

# Run specific test file
test-processors: test-libs
	@echo "Running processor tests..."
	flutter test test/processors/processor_comparison_test.dart

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	flutter clean
	rm -f linux/*.so
	rm -f linux/vulkan_processor/shaders/*.spv
	rm -rf linux/build
	rm -rf build
	rm -f lib/*.so

# Run the application in debug mode
run:
	@echo "Running application..."
	flutter run

# Run with verbose Vulkan logging
run-verbose:
	@echo "Running with verbose Vulkan logging..."
	VULKAN_VERBOSE=1 flutter run

# Build and run
build-run: build
	./build/linux/x64/release/bundle/aks

# Help target
help:
	@echo "AKS RAW Photo Editor - Makefile targets:"
	@echo ""
	@echo "  make build         - Build the Flutter application"
	@echo "  make test-libs     - Build native libraries for testing"
	@echo "  make test          - Run all tests (builds libs first)"
	@echo "  make test-processors - Run processor comparison tests"
	@echo "  make clean         - Clean all build artifacts"
	@echo "  make run           - Run the application in debug mode"
	@echo "  make run-verbose   - Run with verbose Vulkan logging"
	@echo "  make build-run     - Build and run release version"
	@echo "  make help          - Show this help message"
	@echo ""
	@echo "Environment variables:"
	@echo "  VULKAN_VERBOSE=1   - Enable verbose Vulkan logging"