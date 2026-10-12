#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="VieLotusLab.app"
APP_DIR=".build/dist/$APP_NAME"

echo "-> Compiling arm64 target..."
swift build --configuration release --product VieLotusLab --triple arm64-apple-macosx --scratch-path .build/scratch-lab-arm64

echo "-> Compiling x86_64 target..."
swift build --configuration release --product VieLotusLab --triple x86_64-apple-macosx --scratch-path .build/scratch-lab-x86_64

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"

echo "-> Combining architectures into Universal Binary..."
ARM64_BIN="$(find .build/scratch-lab-arm64 -name "VieLotusLab" -type f ! -path "*.dSYM*" | head -n 1)"
X86_BIN="$(find .build/scratch-lab-x86_64 -name "VieLotusLab" -type f ! -path "*.dSYM*" | head -n 1)"
lipo -create -output "$APP_DIR/Contents/MacOS/VieLotusLab" "$ARM64_BIN" "$X86_BIN"

VERSION="${1:-$(git describe --tags --always 2>/dev/null || echo '1.0.0')}"
VERSION="${VERSION#v}"
BUILD_NUMBER="${2:-1}"
GIT_COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
BUILD_TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>VieLotusLab</string>
    <key>CFBundleIdentifier</key><string>org.vielotus.inputmethod.VieLotusLab</string>
    <key>CFBundleName</key><string>VieLotus Lab</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
    <key>GitCommitHash</key><string>$GIT_COMMIT</string>
    <key>BuildTimestamp</key><string>$BUILD_TIMESTAMP</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

mkdir -p "$APP_DIR/Contents/Resources"
find .build/scratch-lab-arm64 -name "*.bundle" -type d -maxdepth 5 -exec cp -R {} "$APP_DIR/Contents/Resources/" \; 2>/dev/null || true

bash "$ROOT/scripts/sign_lab_app.sh" "$APP_DIR"
echo "Built $ROOT/$APP_DIR"
