#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

./scripts/build_lab.sh
SOURCE_APP=".build/dist/VieLotusLab.app"
DEST_ROOT=".build/dist/VieLotusLabClients"
BIN="$SOURCE_APP/Contents/MacOS/VieLotusLab"

while IFS='|' read -r name bundle_id; do
    [[ -z "$name" ]] && continue
    app="$DEST_ROOT/$name.app"
    rm -rf "$app"
    mkdir -p "$app/Contents/MacOS"
    cp "$BIN" "$app/Contents/MacOS/VieLotusLab"
    cp "$SOURCE_APP/Contents/Info.plist" "$app/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $bundle_id" "$app/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleName $name" "$app/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $name" "$app/Contents/Info.plist" 2>/dev/null || \
        /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string $name" "$app/Contents/Info.plist"
    bash "$ROOT/scripts/sign_lab_app.sh" "$app"
    printf 'Built %s (%s)\n' "$ROOT/$app" "$bundle_id"
done <<'PROFILES'
Lab Host - AppKit|org.vielotus.inputmethod.vielotuslab.appkit
Lab Host - Chromium|org.vielotus.inputmethod.vielotuslab.chromium
Lab Host - Office|org.vielotus.inputmethod.vielotuslab.com.microsoft.word
Lab Host - Terminal|org.vielotus.inputmethod.vielotuslab.terminal
Lab Host - Overlay|org.vielotus.inputmethod.vielotuslab.raycast
PROFILES
