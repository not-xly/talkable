#!/bin/bash
# Regenerates every app icon from assets/icon-source.jpeg:
#   assets/AppIcon.icns                    (macOS, rounded artwork + margins)
#   desktop/src-tauri/icons/*              (Windows/Linux, rounded corners)
set -euo pipefail
cd "$(dirname "$0")/.."   # repo root

python3 scripts/make_icon.py

# macOS .icns from the 1024 icon (iconutil expects this exact layout)
ASSETS="assets"
rm -rf "$ASSETS/AppIcon.iconset"
mkdir "$ASSETS/AppIcon.iconset"
for s in 16 32 64 128 256 512; do
    sips -z $s $s "$ASSETS/icon-1024.png" --out "$ASSETS/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
done
cp "$ASSETS/icon-1024.png" "$ASSETS/AppIcon.iconset/icon_512x512@2x.png"
cp "$ASSETS/AppIcon.iconset/icon_256x256.png" "$ASSETS/AppIcon.iconset/icon_128x128@2x.png"
cp "$ASSETS/AppIcon.iconset/icon_32x32.png" "$ASSETS/AppIcon.iconset/icon_16x16@2x.png"

iconutil -c icns "$ASSETS/AppIcon.iconset" -o "$ASSETS/AppIcon.icns"
rm -rf "$ASSETS/AppIcon.iconset"
echo "OK: $ASSETS/AppIcon.icns"
