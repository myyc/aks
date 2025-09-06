#!/bin/bash
set -e

echo "Building Flatpak for aks photo editor..."

# First, build the Flutter app locally
echo "Building Flutter app (release mode)..."
flutter build linux --release --tree-shake-icons

if [ ! -f "build/linux/x64/release/bundle/aks" ]; then
    echo "Error: Flutter build failed"
    exit 1
fi

echo "Flutter build complete!"

# Install the runtime and SDK if not already installed
echo "Installing Flatpak runtime and SDK..."
flatpak install --user -y flathub org.freedesktop.Platform//24.08
flatpak install --user -y flathub org.freedesktop.Sdk//24.08

# Build the Flatpak (just packages the pre-built binaries)
echo "Packaging Flatpak..."
flatpak-builder --force-clean build-dir dev.myyc.aks.yaml

# Create a repository and export the Flatpak
echo "Exporting Flatpak..."
flatpak-builder --repo=repo --force-clean build-dir dev.myyc.aks.yaml

# Build a single-file bundle
echo "Creating Flatpak bundle..."
flatpak build-bundle repo aks.flatpak dev.myyc.aks

echo ""
echo "✅ Flatpak build complete!"
echo ""
echo "The Flatpak bundle has been created: aks.flatpak"
echo ""
echo "To install locally:"
echo "  flatpak install --user aks.flatpak"
echo ""
echo "To run:"
echo "  flatpak run dev.myyc.aks"
echo ""
echo "To test without installing:"
echo "  flatpak-builder --run build-dir dev.myyc.aks.yaml aks"