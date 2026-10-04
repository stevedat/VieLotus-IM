#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

echo "=== VieLotusIM Local Deployment (Sen Việt) ==="

# 1. Build universal release if needed
if [ ! -d ".build/dist/VieLotusIM.app" ]; then
    ./scripts/build_imk.sh
fi

APP_SRC=".build/dist/VieLotusIM.app"
USER_TARGET="$HOME/Library/Input Methods/VieLotusIM.app"
SYS_TARGET="/Library/Input Methods/VieLotusIM.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

# Determine target: prefer /Library/Input Methods if it exists, otherwise ~/Library/Input Methods
if [ -d "$SYS_TARGET" ]; then
    TARGET="$SYS_TARGET"
    # Ensure no conflicting copy exists in user directory
    if [ -d "$USER_TARGET" ]; then
        echo "→ Removing conflicting user duplicate: $USER_TARGET"
        rm -rf "$USER_TARGET"
        "$LSREGISTER" -u "$USER_TARGET" 2>/dev/null || true
    fi
    NEED_SUDO=1
else
    TARGET="$USER_TARGET"
    NEED_SUDO=0
fi

echo "→ Stopping running instances of VieLotusIM..."
pkill -9 VieLotusIM 2>/dev/null || true

echo "→ Deploying new bundle to: $TARGET"
if [ "$NEED_SUDO" -eq 1 ]; then
    if sudo -n true 2>/dev/null; then
        sudo rm -rf "$TARGET"
        sudo ditto "$APP_SRC" "$TARGET"
    else
        osascript -e "do shell script \"rm -rf '$TARGET' && ditto '$APP_SRC' '$TARGET'\" with administrator privileges"
    fi
else
    rm -rf "$TARGET"
    ditto "$APP_SRC" "$TARGET"
fi

echo "→ Updating LaunchServices registration..."
"$LSREGISTER" -f "$TARGET" 2>/dev/null || true

# Register TIS input source cleanly (deduplicating)
echo "→ Registering Input Source with TIS..."
swiftc -O "scripts/pkg-resources/register-source.swift" -framework Carbon -target arm64-apple-macos13 -o /tmp/vielotus-reg-helper
/tmp/vielotus-reg-helper "$TARGET"
rm -f /tmp/vielotus-reg-helper

# Refresh TextInputMenuAgent to update the macOS input menu bar immediately
killall -9 TextInputMenuAgent 2>/dev/null || true

# Launch the newly installed input method
open "$TARGET" 2>/dev/null || true

echo "✅ Nạp và khởi động thành công VieLotusIM tại: $TARGET"
