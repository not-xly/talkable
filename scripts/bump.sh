#!/bin/bash
# Bumps the version everywhere: Cargo.toml, tauri.conf.json, macOS Info.plist, README files.
# Usage: ./scripts/bump.sh 0.4.0
set -euo pipefail
cd "$(dirname "$0")/.."
if [ $# -ne 1 ]; then
  echo "Usage: $0 <version>" >&2
  exit 1
fi
VER="$1"
if ! [[ "$VER" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Version must look like 0.4.0" >&2
  exit 1
fi
sed -i.bak -E "s/^version = \"[0-9]+\.[0-9]+\.[0-9]+\"/version = \"$VER\"/" desktop/src-tauri/Cargo.toml && rm desktop/src-tauri/Cargo.toml.bak
sed -i.bak -E "s/\"version\": \"[0-9]+\.[0-9]+\.[0-9]+\"/\"version\": \"$VER\"/" desktop/src-tauri/tauri.conf.json && rm desktop/src-tauri/tauri.conf.json.bak
sed -i.bak -E "s/<string>[0-9]+\.[0-9]+\.[0-9]+<\/string>/<string>$VER<\/string>/g" macos/scripts/make_app.sh && rm macos/scripts/make_app.sh.bak
sed -i.bak -E "s/Talkable_[0-9]+\.[0-9]+\.[0-9]+_/Talkable_${VER}_/g" README.md README.es.md && rm README.md.bak README.es.md.bak
echo "OK: bumped to $VER (run cargo check to refresh Cargo.lock)"
