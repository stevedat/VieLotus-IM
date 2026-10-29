#!/bin/bash
set -e

export COPYFILE_DISABLE=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

VERSION="${1:-$(git describe --tags --always 2>/dev/null || echo '2.0.0')}"
VERSION="${VERSION#v}" # Strip leading 'v' if present
if [ -z "$1" ] && [ -n "$(git status --porcelain 2>/dev/null)" ] && [[ "$VERSION" != *"-dev"* ]]; then
    VERSION="${VERSION}-dev"
fi
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
strip -x "$APP_DIR/Contents/MacOS/VieLotusIM"

cp "Sources/VieLotusIM/Info.plist" "$APP_DIR/Contents/Info.plist"

# Inject dynamic version and build number
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_DIR/Contents/Info.plist" 2>/dev/null || \
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $VERSION" "$APP_DIR/Contents/Info.plist"

/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_DIR/Contents/Info.plist" 2>/dev/null || \
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $BUILD_NUMBER" "$APP_DIR/Contents/Info.plist"

GIT_COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
    GIT_COMMIT="${GIT_COMMIT}-dev"
fi
BUILD_TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

/usr/libexec/PlistBuddy -c "Set :GitCommitHash $GIT_COMMIT" "$APP_DIR/Contents/Info.plist" 2>/dev/null || \
/usr/libexec/PlistBuddy -c "Add :GitCommitHash string $GIT_COMMIT" "$APP_DIR/Contents/Info.plist"

/usr/libexec/PlistBuddy -c "Set :BuildTimestamp $BUILD_TIMESTAMP" "$APP_DIR/Contents/Info.plist" 2>/dev/null || \
/usr/libexec/PlistBuddy -c "Add :BuildTimestamp string $BUILD_TIMESTAMP" "$APP_DIR/Contents/Info.plist"

if [ -f "Sources/VieLotusIM/Resources/AppIcon.icns" ]; then
    cp "Sources/VieLotusIM/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
elif [ -f "AppIcon.icns" ]; then
    cp "AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

for icon_file in MenuBarTemplate.tiff MenuBarTemplate.png MenuBarTemplate@2x.png vietqr.png; do
    if [ -f "Sources/VieLotusIM/Resources/$icon_file" ]; then
        cp "Sources/VieLotusIM/Resources/$icon_file" "$APP_DIR/Contents/Resources/$icon_file"
    fi
done

# Copy SPM module resource bundles (only VieLotusCore typing-modes.yml)
find .build/scratch-arm64 -name "*VieLotusCore.bundle" -type d -maxdepth 5 -exec cp -R {} "$APP_DIR/Contents/Resources/" \; 2>/dev/null || true
find .build/out/Products/Release -name "*VieLotusCore.bundle" -type d -maxdepth 2 -exec cp -R {} "$APP_DIR/Contents/Resources/" \; 2>/dev/null || true
if [ -d "Frameworks/VieLotusCore.xcframework" ]; then
    find Frameworks/VieLotusCore.xcframework -name "*VieLotusCore.bundle" -type d -maxdepth 6 -exec cp -R {} "$APP_DIR/Contents/Resources/" \; 2>/dev/null || true
fi

# Ship the per-app presentation rules at a stable, user-inspectable top-level path.
# It also exists inside VietLotusIM_VieLotusCore.bundle; PresentationRulesLoader prefers
# this copy so the documented location is the one that is actually read.
if [ -f "Sources/VieLotusCore/Resources/typing-modes.yml" ]; then
    mkdir -p "$APP_DIR/Contents/Resources"
    cp "Sources/VieLotusCore/Resources/typing-modes.yml" "$APP_DIR/Contents/Resources/typing-modes.yml"
elif [ -f "Resources/typing-modes.yml" ]; then
    mkdir -p "$APP_DIR/Contents/Resources"
    cp "Resources/typing-modes.yml" "$APP_DIR/Contents/Resources/typing-modes.yml"
fi

# Clean any extended attribute metadata files
find "$APP_DIR" -name "._*" -delete 2>/dev/null || true

# Auto-detect Developer ID Application from keychain if not set
if [ -z "$DEVELOPER_ID_APP" ]; then
    DEVELOPER_ID_APP="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/"Developer ID Application:/ { print $2; exit }')"
fi

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
echo "To deploy locally and restart IME cleanly:"
echo "  ./scripts/deploy_local.sh"

