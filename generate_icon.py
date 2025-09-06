#!/usr/bin/env python3
"""
Generate Linux PNG icons from aks SVG logo.
Creates multiple sizes for proper desktop integration.
"""

import subprocess
import sys
import shutil
from pathlib import Path

# Icon sizes for Linux desktop (standard hicolor theme sizes)
ICON_SIZES = [16, 24, 32, 48, 64, 128, 256, 512]

def detect_svg_converter():
    """Detect the best available SVG to PNG converter."""
    converters = [
        ('rsvg-convert', ['rsvg-convert', '--version']),
        ('inkscape', ['inkscape', '--version']),
        ('convert', ['convert', '-version'])  # ImageMagick
    ]
    
    for name, check_cmd in converters:
        try:
            subprocess.run(check_cmd, capture_output=True, check=True)
            return name
        except:
            continue
    
    return None

def convert_svg_to_png(svg_path, png_path, size):
    """Convert SVG to PNG using the best available converter."""
    converter = detect_svg_converter()
    
    if not converter:
        print("Error: No SVG converter found. Please install rsvg-convert, inkscape, or imagemagick.")
        sys.exit(1)
    
    if converter == 'rsvg-convert':
        cmd = [
            'rsvg-convert',
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
    else:  # ImageMagick convert
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

def main():
    project_root = Path(__file__).parent
    svg_path = project_root / "assets" / "icons" / "aks.svg"
    linux_dir = project_root / "linux"
    icons_dir = linux_dir / "icons"
    
    if not svg_path.exists():
        print(f"Error: SVG file not found: {svg_path}")
        sys.exit(1)
    
    # Create directories if they don't exist
    linux_dir.mkdir(exist_ok=True)
    icons_dir.mkdir(exist_ok=True)
    
    converter = detect_svg_converter()
    if not converter:
        print("Error: No SVG converter found. Please install rsvg-convert, inkscape, or imagemagick.")
        sys.exit(1)
    
    print(f"Using {converter} to generate icons...")
    print(f"Generating {len(ICON_SIZES)} icon sizes...\n")
    
    success_count = 0
    
    # Generate icons at different sizes
    for size in ICON_SIZES:
        png_path = icons_dir / f"aks-{size}.png"
        print(f"  Creating {size}x{size} icon...", end=" ")
        if convert_svg_to_png(svg_path, png_path, size):
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
    
    print(f"\n✅ Icon generation complete!")
    print(f"Generated {success_count}/{len(ICON_SIZES)} PNG icons in {icons_dir}")
    print(f"Main icon (256x256) copied to {main_icon_dst}")

if __name__ == "__main__":
    main()