#!/bin/bash
set -euo pipefail

TEAM_ID="${TEAM_ID:-9QCZ4F58K8}"
PROFILE="${NOTARY_KEYCHAIN_PROFILE:-notarytool-profile}"

staple_with_retry() {
    local target="$1"
    local max_attempts=8
    local delay=15
    local attempt=1

    echo "→ Waiting 10s for Apple CloudKit ticket distribution..."
    sleep 10

    while [ $attempt -le $max_attempts ]; do
        echo "→ Staple attempt $attempt of $max_attempts for: $target"
        if xcrun stapler staple "$target"; then
            echo "✅ Successfully stapled ticket to: $target"
            return 0
        fi

        echo "⚠️ Stapler attempt $attempt failed (CloudKit replication delay or transient network error: Error 68 / NSURLErrorDomain)."
        if [ $attempt -lt $max_attempts ]; then
            echo "⏳ Retrying in ${delay}s..."
            sleep $delay
            delay=$((delay + 5))
        fi
        attempt=$((attempt + 1))
    done

    echo "❌ Failed to staple ticket to $target after $max_attempts attempts."
    return 1
}

# Check for --staple-only flag
if [[ "${1:-}" == "--staple-only" ]]; then
    TARGET="${2:?Usage: notarize_artifact.sh --staple-only <path-to-file>}"
    echo "=== Stapling ticket for: $TARGET ==="
    staple_with_retry "$TARGET"
    echo "✅ Stapling hoàn tất thành công cho: $TARGET"
    exit 0
fi

TARGET="${1:?Usage: notarize_artifact.sh [--staple-only] <path-to-file>}"

echo "=== Apple Notarization for: $TARGET ==="

if [[ -n "${NOTARY_KEY_PATH:-}" && -n "${NOTARY_KEY_ID:-}" && -n "${NOTARY_ISSUER:-}" ]]; then
    echo "→ Using App Store Connect API Key (Key ID: $NOTARY_KEY_ID)"
    xcrun notarytool submit "$TARGET" \
        --key "$NOTARY_KEY_PATH" \
        --key-id "$NOTARY_KEY_ID" \
        --issuer "$NOTARY_ISSUER" \
        --wait
elif [[ -n "${NOTARY_APPLE_ID:-}" && -n "${NOTARY_PASSWORD:-}" ]]; then
    echo "→ Using Apple ID: $NOTARY_APPLE_ID (Team ID: $TEAM_ID)"
    xcrun notarytool submit "$TARGET" \
        --apple-id "$NOTARY_APPLE_ID" \
        --password "$NOTARY_PASSWORD" \
        --team-id "$TEAM_ID" \
        --wait
else
    # Check if profile exists in keychain
    if ! xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
        echo ""
        echo "❌ [Apple Notarization Error]: Chưa tìm thấy thông tin xác thực Apple Notary (Keychain profile: '$PROFILE')."
        echo ""
        echo "Để gửi công chứng lên Apple, bạn cần cấu hình một lần duy nhất theo 1 trong 2 cách sau:"
        echo ""
        echo "👉 CÁCH 1 (Khuyên dùng - Lưu an toàn vào macOS Keychain):"
        echo "   xcrun notarytool store-credentials \"$PROFILE\" \\"
        echo "     --apple-id \"<email-apple-developer-cua-ban>\" \\"
        echo "     --team-id \"$TEAM_ID\" \\"
        echo "     --password \"<app-specific-password-tao-tu-appleid.apple.com>\""
        echo ""
        echo "👉 CÁCH 2 (Chạy trực tiếp qua biến môi trường):"
        echo "   NOTARIZE=1 NOTARY_APPLE_ID=\"<email>\" NOTARY_PASSWORD=\"<app-specific-password>\" ./scripts/build_lab_dmg.sh"
        echo ""
        exit 1
    fi

    echo "→ Using Keychain Profile: $PROFILE"
    xcrun notarytool submit "$TARGET" --keychain-profile "$PROFILE" --wait
fi

staple_with_retry "$TARGET"

echo "✅ Notarization & Stapling hoàn tất thành công cho: $TARGET"
