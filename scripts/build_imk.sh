#!/bin/bash
set -e

export COPYFILE_DISABLE=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

VERSION="${1:-$(git describe --tags --always 2>/dev/null || echo '1.0.0')}"
VERSION="${VERSION#v}" # Strip leading 'v' if present
BUILD_NUMBER="${2:-1}"

echo "=== Building VieLotusIM v${VERSION} (Sen Việt - Apple InputMethodKit Native) ==="

APP_NAME="VieLotusIM.app"
DIST_DIR=".build/dist"
APP_DIR="$DIST_DIR/$APP_NAME"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

echo "-> Compiling arm64 target..."
swift build --configuration release --product VieLotusIM --triple arm64-apple-macosx --scratch-path .build/scratch-arm64

echo "-> Compiling x86_64 target..."
swift build --configuration release --product VieLotusIM --triple x86_64-apple-macosx --scratch-path .build/scratch-x86_64

echo "-> Combining architectures into Universal Binary..."
ARM64_BIN="$(find .build/scratch-arm64 -name "VieLotusIM" -type f ! -path "*.dSYM*" | head -n 1)"
X86_BIN="$(find .build/scratch-x86_64 -name "VieLotusIM" -type f ! -path "*.dSYM*" | head -n 1)"
lipo -create -output "$APP_DIR/Contents/MacOS/VieLotusIM" "$ARM64_BIN" "$X86_BIN"

cp "Sources/VieLotusIM/Info.plist" "$APP_DIR/Contents/Info.plist"

# Inject dynamic version and build number
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_DIR/Contents/Info.plist" 2>/dev/null || \
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $VERSION" "$APP_DIR/Contents/Info.plist"

/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_DIR/Contents/Info.plist" 2>/dev/null || \
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $BUILD_NUMBER" "$APP_DIR/Contents/Info.plist"

if [ -f "Sources/VieLotusIM/Resources/AppIcon.icns" ]; then
    cp "Sources/VieLotusIM/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
elif [ -f "AppIcon.icns" ]; then
    cp "AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

# Clean any extended attribute metadata files
find "$APP_DIR" -name "._*" -delete 2>/dev/null || true

if [ -n "$DEVELOPER_ID_APP" ]; then
    echo "=== Signing with Apple Developer ID Application ($DEVELOPER_ID_APP) + Hardened Runtime ==="
    codesign --force --deep --options runtime \
             --entitlements "scripts/VieLotusIM.entitlements" \
             --timestamp \
             --sign "$DEVELOPER_ID_APP" "$APP_DIR"
    codesign --verify --deep --strict --verbose=2 "$APP_DIR"
else
    echo "=== Ad-hoc code signing (DEVELOPER_ID_APP not set, suitable for local dev) ==="
    codesign --force --deep --sign - "$APP_DIR"
fi

echo "=== Build complete: $APP_DIR (v${VERSION}) ==="
echo ""
echo "To install to ~/Library/Input Methods/:"
echo "  cp -R \"$APP_DIR\" ~/Library/Input\\ Methods/"
echo "  killall -9 VieLotusIM 2>/dev/null || true"
