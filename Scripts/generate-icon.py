#!/usr/bin/env python3
"""Generate a simple camera-themed app icon as SVG, then convert to PNGs."""

import os, subprocess, json, tempfile

SVG = '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="#3a3a3c"/>
      <stop offset="100%" stop-color="#1c1c1e"/>
    </linearGradient>
  </defs>
  <!-- Background rounded rect -->
  <rect x="50" y="50" width="924" height="924" rx="230" ry="230" fill="url(#bg)"/>
  
  <!-- Camera body -->
  <rect x="256" y="280" width="512" height="380" rx="40" ry="40" fill="#e8e8ed"/>
  <rect x="296" y="280" width="432" height="90" rx="20" ry="20" fill="#d1d1d6"/>
  
  <!-- Flash dot -->
  <circle cx="420" cy="340" r="30" fill="#ffcc00"/>
  
  <!-- Lens outer ring -->
  <circle cx="512" cy="510" r="180" fill="#555558"/>
  <!-- Lens dark -->
  <circle cx="512" cy="510" r="155" fill="#2c2c30"/>
  <!-- Lens inner ring -->
  <circle cx="512" cy="510" r="120" fill="#48484a"/>
  <!-- Aperture -->
  <circle cx="512" cy="510" r="80" fill="#1a1a1e"/>
  
  <!-- Shutter blades -->
  <g stroke="#6e6e72" stroke-width="3" opacity="0.6">
    <line x1="512" y1="430" x2="512" y2="590"/>
    <line x1="432" y1="510" x2="592" y2="510"/>
    <line x1="455" y1="453" x2="569" y2="567"/>
    <line x1="569" y1="453" x2="455" y2="567"/>
  </g>
  
  <!-- Green Safari compass dot -->
  <circle cx="700" cy="700" r="45" fill="#34c759"/>
  <circle cx="700" cy="700" r="18" fill="#1d8c3e"/>
</svg>'''

def main():
    assets_dir = os.path.join(
        os.path.dirname(__file__), '..',
        'Sources', 'SnapshotSafari', 'Resources', 'Assets.xcassets',
        'AppIcon.appiconset'
    )
    os.makedirs(assets_dir, exist_ok=True)

    # Write SVG
    svg_path = os.path.join(assets_dir, 'icon.svg')
    with open(svg_path, 'w') as f:
        f.write(SVG)

    # Use qlmanage or sips to rasterize SVG to PNG
    # qlmanage approach (macOS built-in)
    tmpdir = tempfile.mkdtemp()
    subprocess.run(['qlmanage', '-t', '-s', '1024', '-o', tmpdir, svg_path],
                   check=True, capture_output=True)

    # qlmanage creates 'icon.svg.png' in the output dir
    src_png = os.path.join(tmpdir, 'icon.svg.png')
    dest_png = os.path.join(assets_dir, 'icon_1024x1024.png')
    os.rename(src_png, dest_png)
    print(f'Created {dest_png}')

    # Create 512 version
    subprocess.run(['sips', '-Z', '512', dest_png, '--out',
                    os.path.join(assets_dir, 'icon_512x512.png')],
                   check=True, capture_output=True)
    
    # Create 256 version  
    subprocess.run(['sips', '-Z', '256', dest_png, '--out',
                    os.path.join(assets_dir, 'icon_256x256.png')],
                   check=True, capture_output=True)

    # Create 128 version
    subprocess.run(['sips', '-Z', '128', dest_png, '--out',
                    os.path.join(assets_dir, 'icon_128x128.png')],
                   check=True, capture_output=True)

    # Create 32 version  
    subprocess.run(['sips', '-Z', '32', dest_png, '--out',
                    os.path.join(assets_dir, 'icon_32x32.png')],
                   check=True, capture_output=True)

    # Create 16 version  
    subprocess.run(['sips', '-Z', '16', dest_png, '--out',
                    os.path.join(assets_dir, 'icon_16x16.png')],
                   check=True, capture_output=True)

    # Write Contents.json
    contents = {
        "images": [
            {"idiom": "mac", "scale": "1x", "size": "16x16", "filename": "icon_16x16.png"},
            {"idiom": "mac", "scale": "2x", "size": "16x16", "filename": "icon_32x32.png"},
            {"idiom": "mac", "scale": "1x", "size": "32x32", "filename": "icon_32x32.png"},
            {"idiom": "mac", "scale": "2x", "size": "32x32", "filename": "icon_64x64.png"},
            {"idiom": "mac", "scale": "1x", "size": "128x128", "filename": "icon_128x128.png"},
            {"idiom": "mac", "scale": "2x", "size": "128x128", "filename": "icon_256x256.png"},
            {"idiom": "mac", "scale": "1x", "size": "256x256", "filename": "icon_256x256.png"},
            {"idiom": "mac", "scale": "2x", "size": "256x256", "filename": "icon_512x512.png"},
            {"idiom": "mac", "scale": "1x", "size": "512x512", "filename": "icon_512x512.png"},
            {"idiom": "mac", "scale": "2x", "size": "512x512", "filename": "icon_1024x1024.png"},
        ],
        "info": {"author": "xcode", "version": 1}
    }

    # Create 64x64 version (2x for 32)
    subprocess.run(['sips', '-Z', '64', dest_png, '--out',
                    os.path.join(assets_dir, 'icon_64x64.png')],
                   check=True, capture_output=True)

    contents_path = os.path.join(assets_dir, 'Contents.json')
    with open(contents_path, 'w') as f:
        json.dump(contents, f, indent=2)
    print(f'Created {contents_path}')

    # Build the .icns file from the PNGs using iconutil.
    # Create a temporary .iconset folder with the correctly named files.
    iconset = os.path.join(assets_dir, '..', 'icon.iconset')
    os.makedirs(iconset, exist_ok=True)
    
    # iconutil expects specific filenames: icon_16x16.png, icon_16x16@2x.png, etc.
    # Map our sizes to icns naming
    mapping = {
        ('16x16', '1x'): 'icon_16x16.png',
        ('16x16', '2x'): 'icon_32x32.png',
        ('32x32', '1x'): 'icon_32x32.png',
        ('32x32', '2x'): 'icon_64x64.png',
        ('128x128', '1x'): 'icon_128x128.png',
        ('128x128', '2x'): 'icon_256x256.png',
        ('256x256', '1x'): 'icon_256x256.png',
        ('256x256', '2x'): 'icon_512x512.png',
        ('512x512', '1x'): 'icon_512x512.png',
        ('512x512', '2x'): 'icon_1024x1024.png',
    }
    
    for (size, scale), src_name in mapping.items():
        src = os.path.join(assets_dir, src_name)
        if scale == '1x':
            dst_name = f'icon_{size}.png'
        else:
            dst_name = f'icon_{size}@{scale}.png'
        dst = os.path.join(iconset, dst_name)
        subprocess.run(['cp', src, dst], check=True)
    
    # Run iconutil to create the .icns in the Resources directory
    # (build-app.sh copies from Sources/.../Resources/AppIcon.icns)
    icns_path = os.path.join(assets_dir, '..', '..', 'AppIcon.icns')
    subprocess.run(['iconutil', '-c', 'icns', '-o', icns_path, iconset], check=True)
    print(f'Created {icns_path}')
    
    # Clean up iconset
    import shutil
    shutil.rmtree(iconset)

    print('\nIcon generation complete!')

if __name__ == '__main__':
    main()
