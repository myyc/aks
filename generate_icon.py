#!/usr/bin/env python3
"""
Generate app icons for Linux and macOS from aks SVG logo.
Creates multiple sizes for proper desktop integration.
"""

import subprocess
import sys
import shutil
import json
from pathlib import Path

# Icon sizes for Linux desktop (standard hicolor theme sizes)
LINUX_SIZES = [16, 24, 32, 48, 64, 128, 256, 512]

# macOS icon sizes
MACOS_SIZES = [16, 32, 64, 128, 256, 512, 1024]

def detect_svg_converter():
    """Detect the best available SVG to PNG converter."""
    converters = [
        ('rsvg-convert', ['rsvg-convert', '--version']),
        ('inkscape', ['inkscape', '--version']),
        ('magick', ['magick', '-version']),  # ImageMagick 7
        ('convert', ['convert', '-version'])  # ImageMagick 6
    ]
    
    for name, check_cmd in converters:
        try:
            subprocess.run(check_cmd, capture_output=True, check=True)
            return name
        except:
            continue
    
    return None

def convert_svg_to_png(svg_path, png_path, size, converter=None):
    """Convert SVG to PNG using the best available converter, ensuring square output."""
    if not converter:
        converter = detect_svg_converter()
    
    if not converter:
        print("Error: No SVG converter found. Please install rsvg-convert, inkscape, or imagemagick.")
        sys.exit(1)
    
    # Create parent directory if it doesn't exist
    png_path.parent.mkdir(parents=True, exist_ok=True)
    
    if converter == 'rsvg-convert':
        # rsvg-convert maintains aspect ratio, centers the image
        cmd = [
            'rsvg-convert',
            '-a',  # Keep aspect ratio
            '-w', str(size),
            '-h', str(size),
            str(svg_path),
            '-o', str(png_path)
        ]
    elif converter == 'inkscape':
        cmd = [
            'inkscape',
            str(svg_path),
            '--export-type=png',
            f'--export-filename={png_path}',
            f'--export-width={size}',
            f'--export-height={size}'
        ]
    elif converter == 'magick':
        # ImageMagick 7
        cmd = [
            'magick',
            '-density', '300',
            '-background', 'none',
            str(svg_path),
            '-resize', f'{size}x{size}',
            '-gravity', 'center',
            '-extent', f'{size}x{size}',
            str(png_path)
        ]
    else:  # ImageMagick 6 (convert)
        cmd = [
            'convert',
            '-density', '300',
            '-background', 'none',
            str(svg_path),
            '-resize', f'{size}x{size}',
            '-gravity', 'center',
            '-extent', f'{size}x{size}',
            str(png_path)
        ]
    
    try:
        subprocess.run(cmd, check=True, capture_output=True)
        return True
    except subprocess.CalledProcessError as e:
        print(f"Error converting SVG at size {size}: {e}")
        if e.stderr:
            print(e.stderr.decode())
        return False

def generate_linux_icons(svg_path, project_root, converter):
    """Generate Linux desktop icons."""
    print("\n🐧 Generating Linux icons...")
    
    linux_dir = project_root / "linux"
    icons_dir = linux_dir / "icons"
    
    # Create directories if they don't exist
    linux_dir.mkdir(exist_ok=True)
    icons_dir.mkdir(exist_ok=True)
    
    success_count = 0
    
    # Generate icons at different sizes
    for size in LINUX_SIZES:
        png_path = icons_dir / f"aks-{size}.png"
        print(f"  Creating {size}x{size} icon...", end=" ")
        if convert_svg_to_png(svg_path, png_path, size, converter):
            print("✅")
            success_count += 1
        else:
            print("❌")
    
    # Copy the 256x256 icon as the main icon for the desktop file
    main_icon_src = icons_dir / "aks-256.png"
    main_icon_dst = linux_dir / "aks.png"
    if main_icon_src.exists():
        shutil.copy(main_icon_src, main_icon_dst)
        print(f"\n  Copied main icon to {main_icon_dst}")
    
    # Also copy the SVG for vector support
    svg_dst = icons_dir / "aks.svg"
    shutil.copy(svg_path, svg_dst)
    print(f"  Copied SVG to {svg_dst}")
    
    print(f"  ✅ Linux icons complete! ({success_count}/{len(LINUX_SIZES)})")

def generate_macos_icons(svg_path, project_root, converter):
    """Generate macOS app icons."""
    print("\n🍎 Generating macOS icons...")
    
    macos_assets = project_root / "macos/Runner/Assets.xcassets/AppIcon.appiconset"
    
    # Ensure the directory exists
    macos_assets.mkdir(parents=True, exist_ok=True)
    
    success_count = 0
    icon_entries = []
    
    for size in MACOS_SIZES:
        output_path = macos_assets / f"app_icon_{size}.png"
        print(f"  Creating {size}x{size} icon...", end=" ")
        if convert_svg_to_png(svg_path, output_path, size, converter):
            print("✅")
            success_count += 1
            
            # Add entries for Contents.json
            # Each size needs two entries: 1x and 2x scale
            if size <= 512:
                # 1x scale
                icon_entries.append({
                    "size": f"{size}x{size}",
                    "idiom": "mac",
                    "filename": f"app_icon_{size}.png",
                    "scale": "1x"
                })
                
                # 2x scale (using the double-sized image)
                if size * 2 in MACOS_SIZES:
                    icon_entries.append({
                        "size": f"{size}x{size}",
                        "idiom": "mac",
                        "filename": f"app_icon_{size * 2}.png",
                        "scale": "2x"
                    })
        else:
            print("❌")
    
    # Create Contents.json for macOS
    contents = {
        "images": icon_entries,
        "info": {
            "version": 1,
            "author": "xcode"
        }
    }
    
    contents_path = macos_assets / "Contents.json"
    with open(contents_path, 'w') as f:
        json.dump(contents, f, indent=2)
    
    print(f"  Created Contents.json")
    print(f"  ✅ macOS icons complete! ({success_count}/{len(MACOS_SIZES)})")

def main():
    project_root = Path(__file__).parent
    svg_path = project_root / "assets" / "icons" / "aks.svg"
    
    if not svg_path.exists():
        print(f"Error: SVG file not found: {svg_path}")
        sys.exit(1)
    
    converter = detect_svg_converter()
    if not converter:
        print("Error: No SVG converter found.")
        print("Please install one of: rsvg-convert, inkscape, or imagemagick.")
        sys.exit(1)
    
    print("=" * 50)
    print("🎨 AKS Icon Generator")
    print("=" * 50)
    print(f"Using {converter} to generate icons...")
    print(f"Source: {svg_path}")
    
    # Generate Linux icons
    generate_linux_icons(svg_path, project_root, converter)
    
    # Generate macOS icons
    generate_macos_icons(svg_path, project_root, converter)
    
    print("\n" + "=" * 50)
    print("✅ All icons generated successfully!")
    print("=" * 50)

if __name__ == "__main__":
    main()