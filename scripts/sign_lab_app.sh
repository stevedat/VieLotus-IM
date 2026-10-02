#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_PATH="${1:?Usage: sign_lab_app.sh APP_PATH}"
ENTITLEMENTS="$SCRIPT_DIR/VieLotusLab.entitlements"

# 1. Priority 1: Explicit Developer ID Application (for release / notarization)
IDENTITY="${DEVELOPER_ID_APP:-${VIELOTUS_LAB_CODESIGN_IDENTITY:-}}"

# 2. Priority 2: Auto-detect Developer ID Application if present
if [[ -z "$IDENTITY" ]]; then
    IDENTITY="$(security find-identity -v -p codesigning | awk '/"Developer ID Application:/ { print $2; exit }')"
fi

# 3. Priority 3: Fallback to local Apple Development (for development machine)
if [[ -z "$IDENTITY" ]]; then
    IDENTITY="$(security find-identity -v -p codesigning | awk '/"Apple Development:/ { print $2; exit }')"
fi

if [[ -n "$IDENTITY" ]]; then
    echo "=== Signing $APP_PATH with $IDENTITY + Hardened Runtime ==="
    codesign --force --deep --options runtime \
             --entitlements "$ENTITLEMENTS" \
             --timestamp \
             --sign "$IDENTITY" "$APP_PATH"
    codesign --verify --deep --strict --verbose=2 "$APP_PATH"
    printf 'Signed %s successfully\n' "$APP_PATH"
else
    echo "=== Ad-hoc code signing (no identity found) ==="
    codesign --force --deep --sign - "$APP_PATH"
    printf 'WARNING: no codesign identity found; Accessibility trust may reset after rebuilds\n' >&2
fi
