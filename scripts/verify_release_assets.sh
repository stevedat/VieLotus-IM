#!/bin/bash
set -eu

# scripts/verify_release_assets.sh
# Verifies Developer ID signatures, Apple Notarization tickets, SHA-256 manifest integrity,
# and release completeness for VieLotusIM and VieLotusLab deliverables.

EXPECTED_TEAM_ID="9QCZ4F58K8"
REQUIRED_FILES=(
    "VieLotusIM.pkg"
    "VieLotusIM.dmg"
    "VieLotusIM.app.zip"
    "VieLotusLab.dmg"
    "checksums.sha256"
)

TARGET_DIR=".build/dist"
REMOTE_TAG=""
CLEANUP_TMP=0

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --remote|--github)
            REMOTE_TAG="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [target_directory] | [--remote <tag>]"
            echo "  target_directory : Local path containing release deliverables (default: .build/dist)"
            echo "  --remote <tag>   : Download and verify assets directly from GitHub Release <tag>"
            exit 0
            ;;
        *)
            TARGET_DIR="$1"
            shift
            ;;
    esac
done

if [[ -n "$REMOTE_TAG" ]]; then
    TMP_DOWNLOAD="/tmp/vielotus-verify-remote-$$-${REMOTE_TAG}"
    mkdir -p "$TMP_DOWNLOAD"
    TARGET_DIR="$TMP_DOWNLOAD"
    CLEANUP_TMP=1
    echo "=========================================================="
    echo "📥 Downloading public assets for GitHub Release '$REMOTE_TAG'..."
    echo "=========================================================="
    if ! gh release download "$REMOTE_TAG" --dir "$TARGET_DIR"; then
        echo "❌ Failed to download release assets for tag '$REMOTE_TAG'!"
        rm -rf "$TMP_DOWNLOAD"
        exit 1
    fi
fi

echo "=========================================================="
echo "🌸 VieLotus Release Artifact Integrity & Completeness Audit"
echo "Target directory       : $TARGET_DIR"
echo "Expected Apple Team ID : $EXPECTED_TEAM_ID"
echo "Required Artifacts     : ${REQUIRED_FILES[*]}"
echo "=========================================================="

if [ ! -d "$TARGET_DIR" ]; then
    echo "❌ Error: Target directory '$TARGET_DIR' not found."
    exit 1
fi

FAILURES=0

# 1. Strict Completeness Check against Required Manifest
echo ""
echo "--- 📋 1. Kiểm tra danh mục tệp bắt buộc (Manifest Completeness) ---"
for req in "${REQUIRED_FILES[@]}"; do
    if [ -f "$TARGET_DIR/$req" ]; then
        echo "  ✅ Tệp tồn tại: $req"
    else
        echo "  ❌ THIẾU TỆP BẮT BUỘC: $req"
        FAILURES=$((FAILURES + 1))
    fi
done

# 2. Checksum Manifest Verification
echo ""
echo "--- 🔐 2. Kiểm tra mã băm SHA-256 đối chiếu (Checksum Verification) ---"
if [ -f "$TARGET_DIR/checksums.sha256" ]; then
    echo "  • Đang đối chiếu mã băm trong checksums.sha256..."
    CURRENT_DIR="$(pwd)"
    cd "$TARGET_DIR"
    if shasum -a 256 -c checksums.sha256; then
        echo "  ✅ TẤT CẢ TỆP TRÙNG KHỚP 100% MÃ BĂM SHA-256 ĐÃ CÔNG BỐ!"
    else
        echo "  ❌ MÃ BĂM SHA-256 KHÔNG KHỚP HOẶC THIẾU TỆP TRONG MANIFEST!"
        FAILURES=$((FAILURES + 1))
    fi
    cd "$CURRENT_DIR"
else
    echo "  ❌ Không tìm thấy tệp checksums.sha256 để đối chiếu mã băm!"
    FAILURES=$((FAILURES + 1))
fi

# 3. Cryptographic Signature & Notarization Checks
echo ""
echo "--- 🔏 3. Kiểm tra chữ ký số Developer ID & Apple Notarization ---"

check_pkg() {
    local pkg_path="$1"
    echo ""
    echo "  [PKG] $(basename "$pkg_path")"
    if [ ! -f "$pkg_path" ]; then
        echo "    ❌ Không tìm thấy file"
        FAILURES=$((FAILURES + 1))
        return
    fi

    local sig_output
    sig_output=$(pkgutil --check-signature "$pkg_path" 2>&1 || true)

    if echo "$sig_output" | grep -q "trusted by the Apple notary service"; then
        echo "    ✅ Apple Notarization: TRUSTED"
    else
        echo "    ❌ Apple Notarization: NOT TRUSTED"
        FAILURES=$((FAILURES + 1))
    fi

    if echo "$sig_output" | grep -q "$EXPECTED_TEAM_ID"; then
        echo "    ✅ Developer ID Installer: VALID ($EXPECTED_TEAM_ID)"
    else
        echo "    ❌ Team ID mismatch: expected $EXPECTED_TEAM_ID"
        FAILURES=$((FAILURES + 1))
    fi
}

check_dmg() {
    local dmg_path="$1"
    echo ""
    echo "  [DMG] $(basename "$dmg_path")"
    if [ ! -f "$dmg_path" ]; then
        echo "    ❌ Không tìm thấy file"
        FAILURES=$((FAILURES + 1))
        return
    fi

    local cs_info
    cs_info=$(codesign -dv --verbose=4 "$dmg_path" 2>&1 || true)
    if echo "$cs_info" | grep -q "TeamIdentifier=$EXPECTED_TEAM_ID"; then
        echo "    ✅ Codesign Team ID: VALID ($EXPECTED_TEAM_ID)"
    else
        echo "    ❌ Codesign Team ID mismatch!"
        FAILURES=$((FAILURES + 1))
    fi

    local staple_info
    staple_info=$(xcrun stapler validate "$dmg_path" 2>&1 || true)
    if echo "$staple_info" | grep -q "worked"; then
        echo "    ✅ Notarization Staple: VALID"
    else
        echo "    ❌ Notarization Staple validation failed!"
        FAILURES=$((FAILURES + 1))
    fi
}

check_zip_app() {
    local zip_path="$1"
    echo ""
    echo "  [ZIP] $(basename "$zip_path")"
    if [ ! -f "$zip_path" ]; then
        echo "    ❌ Không tìm thấy file"
        FAILURES=$((FAILURES + 1))
        return
    fi

    local tmp_dir="/tmp/verify-zip-$$"
    mkdir -p "$tmp_dir"
    unzip -q "$zip_path" -d "$tmp_dir"

    local found_app=0
    for app in "$tmp_dir"/*.app; do
        if [ -d "$app" ]; then
            found_app=1
            local spctl_out
            spctl_out=$(spctl -a -t exec -vv "$app" 2>&1 || true)
            if echo "$spctl_out" | grep -q "accepted"; then
                echo "    ✅ Gatekeeper Assessment: ACCEPTED ($(basename "$app"))"
            else
                echo "    ❌ Gatekeeper Assessment: REJECTED ($(basename "$app"))"
                echo "$spctl_out"
                FAILURES=$((FAILURES + 1))
            fi
            local version
            version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app/Contents/Info.plist" 2>/dev/null || echo "unknown")
            local commit
            commit=$(/usr/libexec/PlistBuddy -c "Print :GitCommitHash" "$app/Contents/Info.plist" 2>/dev/null || echo "unknown")
            echo "    • Version: $version"
            echo "    • Git Commit: $commit"
        fi
    done
    if [ "$found_app" -eq 0 ]; then
        echo "    ❌ Không tìm thấy .app bundle bên trong zip archive!"
        FAILURES=$((FAILURES + 1))
    fi
    rm -rf "$tmp_dir"
}

check_pkg "$TARGET_DIR/VieLotusIM.pkg"
check_dmg "$TARGET_DIR/VieLotusIM.dmg"
check_dmg "$TARGET_DIR/VieLotusLab.dmg"
check_zip_app "$TARGET_DIR/VieLotusIM.app.zip"

if [ "$CLEANUP_TMP" -eq 1 ]; then
    rm -rf "$TARGET_DIR"
fi

echo ""
echo "=========================================================="
if [ "$FAILURES" -eq 0 ]; then
    echo "🏆 TẤT CẢ ARTIFACTS ĐẠT CHUẨN ĐÚNG, ĐỦ & CÔNG CHỨNG APPLE!"
    echo "=========================================================="
    exit 0
else
    echo "❌ PHÁT HIỆN $FAILURES LỖI THIẾU TỆP, SAI MÃ BĂM HOẶC LỖI KÝ SỐ!"
    echo "=========================================================="
    exit 1
fi
