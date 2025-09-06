#!/bin/bash

# Build script for macOS native libraries
# This script builds libraw_processor.dylib and prepares it for bundling

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Building macOS native libraries with bundled dependencies...${NC}"

# Determine libraw location
LIBRAW_DYLIB=""
LIBRAW_INCLUDE=""
LIBRAW_LIB=""

if [ -d "/opt/homebrew" ]; then
    # Apple Silicon Mac
    LIBRAW_INCLUDE="/opt/homebrew/include"
    LIBRAW_LIB="/opt/homebrew/lib"
    LIBRAW_DYLIB="/opt/homebrew/lib/libraw.dylib"
elif [ -d "/usr/local" ]; then
    # Intel Mac
    LIBRAW_INCLUDE="/usr/local/include"
    LIBRAW_LIB="/usr/local/lib"
    LIBRAW_DYLIB="/usr/local/lib/libraw.dylib"
fi

# Check if libraw is installed
if [ ! -f "$LIBRAW_DYLIB" ]; then
    echo -e "${RED}Error: libraw not found. Please install it:${NC}"
    echo -e "${YELLOW}  brew install libraw${NC}"
    exit 1
fi

echo -e "${YELLOW}Found libraw at: $LIBRAW_DYLIB${NC}"

# Build libraw_processor.dylib
echo -e "${GREEN}Building libraw_processor.dylib...${NC}"

clang -shared -fPIC -o libraw_processor.dylib \
    raw_processor/raw_processor.c \
    -I"$LIBRAW_INCLUDE" -L"$LIBRAW_LIB" -lraw -lm \
    -Wl,-rpath,@loader_path

if [ -f "libraw_processor.dylib" ]; then
    echo -e "${GREEN}✓ libraw_processor.dylib built successfully${NC}"
    
    # Copy libraw to local directory for bundling
    echo -e "${GREEN}Copying libraw for bundling...${NC}"
    cp "$LIBRAW_DYLIB" ./libraw.23.dylib 2>/dev/null || cp "$LIBRAW_DYLIB" ./libraw.dylib
    
    # Update the library path to use @loader_path for bundled libraw
    echo -e "${GREEN}Updating library paths for bundling...${NC}"
    
    # Get the actual libraw library name from otool output
    LIBRAW_NAME=$(otool -L libraw_processor.dylib | grep libraw | awk '{print $1}')
    echo -e "${YELLOW}Current libraw path in binary: $LIBRAW_NAME${NC}"
    
    # Change the libraw dependency to use @loader_path
    install_name_tool -change "$LIBRAW_NAME" "@loader_path/libraw.dylib" libraw_processor.dylib
    
    # Set the install name of our library
    install_name_tool -id "@loader_path/libraw_processor.dylib" libraw_processor.dylib
    
    # If we copied libraw, update its install name too
    if [ -f "./libraw.dylib" ] || [ -f "./libraw.23.dylib" ]; then
        LIBRAW_LOCAL=$(ls libraw*.dylib | head -1)
        install_name_tool -id "@loader_path/libraw.dylib" "$LIBRAW_LOCAL"
        if [ "$LIBRAW_LOCAL" != "libraw.dylib" ]; then
            mv "$LIBRAW_LOCAL" libraw.dylib
        fi
        echo -e "${GREEN}✓ libraw.dylib prepared for bundling${NC}"
    fi
    
    # Verify the changes
    echo -e "${YELLOW}Verifying library paths after modification:${NC}"
    otool -L libraw_processor.dylib | grep -E "libraw|@loader_path"
    
    # Set proper permissions
    chmod 755 *.dylib
    
    # Show library info
    echo -e "${YELLOW}Library dependencies after bundling setup:${NC}"
    otool -L libraw_processor.dylib
    
else
    echo -e "${RED}✗ Failed to build libraw_processor.dylib${NC}"
    exit 1
fi

echo -e "\n${GREEN}Build complete!${NC}"
echo -e "Libraries built in: $(pwd)/"
echo -e "  - libraw_processor.dylib (our FFI wrapper)"
echo -e "  - libraw.dylib (bundled dependency)"

# For development with flutter run, copy to app bundle Frameworks
APP_BUNDLE_DEBUG="../build/macos/Build/Products/Debug/aks.app/Contents/Frameworks"
APP_BUNDLE_RELEASE="../build/macos/Build/Products/Release/aks.app/Contents/Frameworks"

echo -e "\n${GREEN}Copying libraries for Flutter development...${NC}"

# Create Frameworks directories if they don't exist
if [ ! -d "$APP_BUNDLE_DEBUG" ]; then
    mkdir -p "$APP_BUNDLE_DEBUG"
fi
if [ ! -d "$APP_BUNDLE_RELEASE" ]; then
    mkdir -p "$APP_BUNDLE_RELEASE"
fi

# Copy both libraries to the app bundle Frameworks directory
cp libraw_processor.dylib "$APP_BUNDLE_DEBUG/" 2>/dev/null || true
cp libraw.dylib "$APP_BUNDLE_DEBUG/" 2>/dev/null || true
cp libraw_processor.dylib "$APP_BUNDLE_RELEASE/" 2>/dev/null || true
cp libraw.dylib "$APP_BUNDLE_RELEASE/" 2>/dev/null || true

# Verify the libraries in the app bundle have correct paths
if [ -f "$APP_BUNDLE_DEBUG/libraw_processor.dylib" ]; then
    echo -e "\n${YELLOW}Verifying Debug bundle library paths:${NC}"
    otool -L "$APP_BUNDLE_DEBUG/libraw_processor.dylib" | head -5
    
    # Check if it's still pointing to Homebrew path
    if otool -L "$APP_BUNDLE_DEBUG/libraw_processor.dylib" | grep -q "/opt/homebrew\|/usr/local"; then
        echo -e "${RED}WARNING: Library still has Homebrew dependencies!${NC}"
        echo -e "${YELLOW}Re-run this script to fix the paths.${NC}"
    else
        echo -e "${GREEN}✓ Library paths look correct${NC}"
    fi
fi

echo -e "${GREEN}✓ Libraries copied to app bundle Frameworks${NC}"
echo -e "  Debug: $APP_BUNDLE_DEBUG"
echo -e "  Release: $APP_BUNDLE_RELEASE"
echo -e "\n${YELLOW}You can now run: flutter run -d macos${NC}"