#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

VERSION="${1:-$(git describe --tags --always 2>/dev/null || echo '1.0.0')}"
VERSION="${VERSION#v}"

echo "=== Packaging VieLotusIM DMG v${VERSION} ==="

# 1. Ensure PKG is built
if [ ! -f ".build/dist/VieLotusIM.pkg" ]; then
    ./scripts/build_pkg.sh "$VERSION"
fi

PKG=".build/dist/VieLotusIM.pkg"
DMG_WORK=".build/dmg-work"
OUT=".build/dist/VieLotusIM.dmg"

rm -rf "$DMG_WORK" "$OUT"
mkdir -p "$DMG_WORK"

cp "$PKG" "$DMG_WORK/Cài đặt Sen Việt.pkg"

# Apply volume icon to mounted DMG
if [ -f "Sources/VieLotusIM/Resources/AppIcon.icns" ]; then
    cp "Sources/VieLotusIM/Resources/AppIcon.icns" "$DMG_WORK/.VolumeIcon.icns"
    SetFile -c icnC "$DMG_WORK/.VolumeIcon.icns" 2>/dev/null || true
    SetFile -a C "$DMG_WORK" 2>/dev/null || true
fi

# Clean AppleDouble metadata
find "$DMG_WORK" -name "._*" -delete 2>/dev/null || true

# Create compressed read-only DMG image
hdiutil create -volname "Sen Việt (VieLotusIM)" \
        -srcfolder "$DMG_WORK" \
        -ov -format UDZO \
        "$OUT"

rm -rf "$DMG_WORK"

# Apply custom icon to DMG file in Finder
if [ -f "Sources/VieLotusIM/Resources/AppIcon.icns" ]; then
    swift -e '
    import AppKit
    let icon = NSImage(contentsOfFile: "Sources/VieLotusIM/Resources/AppIcon.icns")
    let out = CommandLine.arguments[1]
    _ = NSWorkspace.shared.setIcon(icon, forFile: out, options: [])
    ' "$OUT" 2>/dev/null || true
fi

# 2. Codesign the DMG if Developer ID is available
if [ -z "$DEVELOPER_ID_APP" ]; then
    DEVELOPER_ID_APP="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/"Developer ID Application:/ { print $2; exit }')"
fi

if [ -n "$DEVELOPER_ID_APP" ]; then
    echo "=== Signing VieLotusIM.dmg with ($DEVELOPER_ID_APP) ==="
    codesign --force --sign "$DEVELOPER_ID_APP" --timestamp "$OUT"
fi

# 3. Notarize and Staple DMG if requested
if [ "${NOTARIZE:-0}" = "1" ]; then
    bash "$SCRIPT_DIR/scripts/notarize_artifact.sh" "$OUT"
fi

echo "✅ Disk image ready at: $OUT (v${VERSION})"
