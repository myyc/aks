#!/bin/bash

# Build script for test libraries
# This ensures all native libraries are built and in the right place for tests

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Building test libraries...${NC}"

# Change to project root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"
cd "$PROJECT_ROOT"

# Check dependencies
echo -e "${YELLOW}Checking dependencies...${NC}"

if ! command -v gcc &> /dev/null; then
    echo -e "${RED}Error: gcc not found. Please install build-essential.${NC}"
    exit 1
fi

if ! pkg-config --exists libraw; then
    echo -e "${RED}Error: libraw not found. Please install libraw-dev.${NC}"
    exit 1
fi

if ! pkg-config --exists vulkan; then
    echo -e "${RED}Error: vulkan not found. Please install libvulkan-dev.${NC}"
    exit 1
fi

if ! command -v glslc &> /dev/null; then
    echo -e "${YELLOW}Warning: glslc not found. Shaders will not be compiled.${NC}"
    echo -e "${YELLOW}Install vulkan-tools or vulkan-sdk to compile shaders.${NC}"
    SKIP_SHADERS=1
fi

# Create linux directory if it doesn't exist
mkdir -p linux

# Build libraw_processor.so
echo -e "${GREEN}Building libraw_processor.so...${NC}"
gcc -shared -fPIC -o linux/libraw_processor.so \
    linux/raw_processor/raw_processor.c \
    $(pkg-config --cflags --libs libraw) \
    -lm

if [ -f "linux/libraw_processor.so" ]; then
    echo -e "${GREEN}✓ libraw_processor.so built successfully${NC}"
else
    echo -e "${RED}✗ Failed to build libraw_processor.so${NC}"
    exit 1
fi

# Build libvulkan_processor.so
echo -e "${GREEN}Building libvulkan_processor.so...${NC}"
gcc -shared -fPIC -o linux/libvulkan_processor.so \
    linux/vulkan_processor/vulkan_processor.c \
    -lvulkan -lm

if [ -f "linux/libvulkan_processor.so" ]; then
    echo -e "${GREEN}✓ libvulkan_processor.so built successfully${NC}"
else
    echo -e "${RED}✗ Failed to build libvulkan_processor.so${NC}"
    exit 1
fi

# Compile shaders if glslc is available
if [ -z "$SKIP_SHADERS" ]; then
    echo -e "${GREEN}Compiling shaders...${NC}"
    
    # Create shader output directory
    mkdir -p linux/vulkan_processor/shaders
    
    # Find all compute shaders
    for shader in linux/vulkan_processor/shaders/*.comp; do
        if [ -f "$shader" ]; then
            shader_name=$(basename "$shader" .comp)
            echo -e "  Compiling ${shader_name}..."
            glslc -fshader-stage=comp "$shader" \
                -o "linux/vulkan_processor/shaders/${shader_name}.spv"
            
            if [ -f "linux/vulkan_processor/shaders/${shader_name}.spv" ]; then
                echo -e "${GREEN}  ✓ ${shader_name}.spv${NC}"
            else
                echo -e "${RED}  ✗ Failed to compile ${shader_name}${NC}"
            fi
        fi
    done
    
    # Also copy to build directory for runtime
    mkdir -p linux/build/shaders
    cp linux/vulkan_processor/shaders/*.spv linux/build/shaders/ 2>/dev/null || true
else
    echo -e "${YELLOW}Skipping shader compilation (glslc not found)${NC}"
fi

# Create symlinks for alternative paths
echo -e "${GREEN}Creating library symlinks...${NC}"

# Create lib directory and symlinks for common search paths
mkdir -p lib
ln -sf ../linux/libraw_processor.so lib/libraw_processor.so 2>/dev/null || true
ln -sf ../linux/libvulkan_processor.so lib/libvulkan_processor.so 2>/dev/null || true

# Summary
echo -e "\n${GREEN}Build complete!${NC}"
echo -e "Libraries built in: ${PROJECT_ROOT}/linux/"
echo -e "To run tests: flutter test"