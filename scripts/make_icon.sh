#!/bin/bash
# Regenerates assets/AppIcon.icns from assets/icon-source.jpeg
set -euo pipefail
cd "$(dirname "$0")/.."   # repo root

ASSETS="assets"
SRC="$ASSETS/icon-source.jpeg"
[ -f "$SRC" ] || { echo "Falta $SRC"; exit 1; }

# Center crop so the artwork fills the canvas (the source has margins)
sips -c 1150 1150 "$SRC" --out "$ASSETS/crop.jpg" >/dev/null
sips -s format png "$ASSETS/crop.jpg" --out "$ASSETS/icon-1024.png" >/dev/null
rm "$ASSETS/crop.jpg"

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
