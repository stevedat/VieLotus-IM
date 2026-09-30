#!/bin/bash
set -e

export COPYFILE_DISABLE=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

VERSION="${1:-$(git describe --tags --always 2>/dev/null || echo '1.0.0')}"
VERSION="${VERSION#v}" # Strip leading 'v'

echo "=== Packaging VieLotusIM v${VERSION} ==="

# 1. Build universal VieLotusIM.app
./scripts/build_imk.sh "$VERSION"

APP=".build/dist/VieLotusIM.app"
RES="scripts/pkg-resources"
WORK=".build/pkg-work"
OUT=".build/dist/VieLotusIM.pkg"

rm -rf "$WORK"
mkdir -p "$WORK/payload" "$WORK/scripts"
/usr/bin/ditto "$APP" "$WORK/payload/VieLotusIM.app"

echo "→ Compiling register helper (Universal arm64 + x86_64)"
swiftc -O "$RES/register-source.swift" -framework Carbon \
       -target arm64-apple-macos13 -o "$WORK/scripts/register-source-arm64"
swiftc -O "$RES/register-source.swift" -framework Carbon \
       -target x86_64-apple-macos13 -o "$WORK/scripts/register-source-x86_64"
lipo -create "$WORK/scripts/register-source-arm64" "$WORK/scripts/register-source-x86_64" \
     -output "$WORK/scripts/register-source"
rm "$WORK/scripts/register-source-arm64" "$WORK/scripts/register-source-x86_64"

cp "$RES/postinstall" "$WORK/scripts/postinstall"
chmod +x "$WORK/scripts/postinstall"
chmod +x "$WORK/scripts/register-source"

if [ -n "$DEVELOPER_ID_APP" ]; then
    echo "=== Signing register-source helper with Apple Developer ID Application ($DEVELOPER_ID_APP) ==="
    codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_APP" "$WORK/scripts/register-source"
fi

# Clean any AppleDouble metadata files and normalize payload permissions
find "$WORK" -name "._*" -delete 2>/dev/null || true
chmod -R u+rwX,go+rX "$WORK/payload"

echo "→ Building PKG package (v${VERSION})"
pkgbuild --root "$WORK/payload" \
         --install-location "/Library/Input Methods" \
         --scripts "$WORK/scripts" \
         --identifier "org.vielotus.inputmethod.VieLotusIM.pkg" \
         --version "$VERSION" \
         "$WORK/component.pkg"

echo "→ Synthesizing Installer Distribution to suppress logout requirement"
productbuild --synthesize --package "$WORK/component.pkg" "$WORK/distribution.xml"

if [ -n "$DEVELOPER_ID_INSTALLER" ]; then
    echo "=== Wrapping and Signing PKG with Apple Developer ID Installer ($DEVELOPER_ID_INSTALLER) ==="
    productbuild --distribution "$WORK/distribution.xml" \
                 --package-path "$WORK" \
                 --sign "$DEVELOPER_ID_INSTALLER" \
                 --timestamp \
                 "$OUT"
else
    echo "=== Building unsigned PKG (DEVELOPER_ID_INSTALLER not set) ==="
    productbuild --distribution "$WORK/distribution.xml" \
                 --package-path "$WORK" \
                 "$OUT"
fi

# Apply custom AppIcon to the PKG file in Finder
if [ -f "Sources/VieLotusIM/Resources/AppIcon.icns" ]; then
    swift -e '
    import AppKit
    let icon = NSImage(contentsOfFile: "Sources/VieLotusIM/Resources/AppIcon.icns")
    let out = CommandLine.arguments[1]
    _ = NSWorkspace.shared.setIcon(icon, forFile: out, options: [])
    ' "$OUT" >/dev/null 2>&1 || true
fi

# Optional Notarization step if requested
if [ "$NOTARIZE" = "1" ]; then
    PROFILE="${NOTARY_KEYCHAIN_PROFILE:-notarytool-profile}"
    echo "=== Notarizing package via xcrun notarytool (profile: $PROFILE) ==="
    xcrun notarytool submit "$OUT" --keychain-profile "$PROFILE" --wait

    echo "=== Stapling ticket to PKG ==="
    xcrun stapler staple "$OUT"
    echo "✅ Successfully notarized and stapled $OUT"
fi

echo "✅ Installer package ready at: $OUT (v${VERSION})"
