#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

VERSION="${1:-1.0.0}"
echo "=== Packaging VieLotusLab DMG v${VERSION} ==="

killall -9 VieLotusLab 2>/dev/null || true

# 1. Ensure Universal VieLotusLab.app is built and signed
./scripts/build_lab.sh "$VERSION"

APP=".build/dist/VieLotusLab.app"
TMP_WORK="/tmp/vielotus-lab-work-$$"
TMP_OUT="/tmp/VieLotusLab-$$.dmg"
OUT=".build/dist/VieLotusLab.dmg"

rm -rf "$TMP_WORK" "$TMP_OUT" "$OUT"
mkdir -p "$TMP_WORK"

# Use ditto for clean HFS/APFS metadata copy
ditto "$APP" "$TMP_WORK/VieLotusLab.app"
ln -s /Applications "$TMP_WORK/Applications"

# Clean AppleDouble metadata
find "$TMP_WORK" -name "._*" -delete 2>/dev/null || true

# Create compressed read-only DMG image
hdiutil create -volname "VieLotus Lab" \
        -srcfolder "$TMP_WORK" \
        -ov -format UDZO \
        "$TMP_OUT"

rm -rf "$TMP_WORK"
cp "$TMP_OUT" "$OUT"
rm -f "$TMP_OUT"

# 2. Codesign the DMG with Developer ID Application if available
IDENTITY="${DEVELOPER_ID_APP:-}"
if [[ -z "$IDENTITY" ]]; then
    IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/"Developer ID Application:/ { print $2; exit }')"
fi

if [[ -n "$IDENTITY" ]]; then
    echo "=== Signing VieLotusLab.dmg with ($IDENTITY) ==="
    codesign --force --sign "$IDENTITY" --timestamp "$OUT"
    codesign --verify --verbose=2 "$OUT"
fi

# 3. Notarize and Staple DMG if requested
if [ "${NOTARIZE:-0}" = "1" ]; then
    bash "$SCRIPT_DIR/scripts/notarize_artifact.sh" "$OUT"
fi

echo "✅ VieLotusLab DMG ready at: $OUT (v${VERSION})"
