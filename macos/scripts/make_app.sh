#!/bin/bash
# Builds Talkable and bundles Talkable.app (ad-hoc signed).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP="build/Talkable.app"
BIN="$APP/Contents/MacOS"
RES="$APP/Contents/Resources"
rm -rf "$APP"
mkdir -p "$BIN" "$RES"
cp .build/release/Talkable "$BIN/Talkable"

# Icon (generated with the repo's scripts/make_icon.sh)
if [ -f "../assets/AppIcon.icns" ]; then
    cp ../assets/AppIcon.icns "$RES/AppIcon.icns"
fi

# Legal notices (the MIT license requires them to ship with the app)
cp ../LICENSE "$RES/LICENSE.txt"
cp ../THIRD_PARTY_LICENSES.md "$RES/THIRD_PARTY_LICENSES.md"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Talkable</string>
    <key>CFBundleDisplayName</key><string>Talkable</string>
    <key>CFBundleIdentifier</key><string>local.talkable.app</string>
    <key>CFBundleVersion</key><string>0.3.0</string>
    <key>CFBundleShortVersionString</key><string>0.3.0</string>
    <key>CFBundleExecutable</key><string>Talkable</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Talkable uses the microphone to turn your voice into text.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>Talkable processes your voice to transcribe it into text.</string>
</dict>
</plist>
PLIST

codesign --force -s - "$APP"
echo "OK: $APP"
