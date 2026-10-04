#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

echo "=== VieLotusIM Local Deployment (Sen Việt) ==="

# 1. P2 Fix: Always rebuild to ensure the latest source code, git commit hash, and timestamp are deployed
echo "→ Compiling latest universal binary..."
./scripts/build_imk.sh "$@"

APP_SRC="$SCRIPT_DIR/.build/dist/VieLotusIM.app"
if [ ! -d "$APP_SRC" ] || [ ! -f "$APP_SRC/Contents/MacOS/VieLotusIM" ]; then
    echo "❌ Lỗi: Thư mục ứng dụng nguồn không hợp lệ: $APP_SRC"
    exit 1
fi

USER_TARGET="$HOME/Library/Input Methods/VieLotusIM.app"
SYS_TARGET="/Library/Input Methods/VieLotusIM.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

# Determine target location: prefer /Library/Input Methods if it exists, otherwise ~/Library/Input Methods
if [ -d "$SYS_TARGET" ]; then
    TARGET="$SYS_TARGET"
    NEED_SUDO=1
else
    TARGET="$USER_TARGET"
    NEED_SUDO=0
fi

TARGET_DIR="$(dirname "$TARGET")"
RAND_ID="$$"
STAGE_TARGET="$TARGET_DIR/VieLotusIM.app.new.$RAND_ID"
BAK_TARGET="$TARGET_DIR/VieLotusIM.app.bak.$RAND_ID"
USER_BAK=""
TMP_HELPER="/tmp/vielotus-reg-helper-$RAND_ID"

echo "→ Target deployment path: $TARGET (elevated=$NEED_SUDO)"

if [ "$NEED_SUDO" -eq 1 ]; then
    RUN_ELEVATED() {
        local cmd="$1"
        if sudo -n true 2>/dev/null; then
            sudo sh -c "$cmd"
        else
            osascript -e "do shell script \"$cmd\" with administrator privileges"
        fi
    }
else
    RUN_ELEVATED() {
        local cmd="$1"
        sh -c "$cmd"
    }
fi

DO_ROLLBACK() {
    local reason="$1"
    echo "⚠️ BẮT ĐẦU HOÀN TÁC (ROLLBACK): $reason"
    pkill -9 VieLotusIM 2>/dev/null || true
    
    # Restore primary target from backup if backup exists
    if [ -d "$BAK_TARGET" ]; then
        echo "  ↳ Khôi phục bản cài đặt gốc tại: $TARGET"
        RUN_ELEVATED "rm -rf '$TARGET' && mv '$BAK_TARGET' '$TARGET'"
    fi
    
    # Restore user duplicate backup if quarantined
    if [ -n "$USER_BAK" ] && [ -d "$USER_BAK" ]; then
        echo "  ↳ Khôi phục bản sao người dùng: $USER_TARGET"
        mv "$USER_BAK" "$USER_TARGET"
        "$LSREGISTER" -f "$USER_TARGET" 2>/dev/null || true
    fi
    
    # Re-register original target with LaunchServices
    if [ -d "$TARGET" ]; then
        "$LSREGISTER" -f "$TARGET" 2>/dev/null || true
        open "$TARGET" 2>/dev/null || true
    fi
    
    # Clean staging files
    RUN_ELEVATED "rm -rf '$STAGE_TARGET'"
    rm -f "$TMP_HELPER"
    echo "❌ Hoàn tất hoàn nguyên. Trạng thái hệ thống đã trở về trước khi nạp."
    exit 1
}

# Clean any leftover temporary directories from prior interrupted runs
RUN_ELEVATED "rm -rf '$STAGE_TARGET' '$BAK_TARGET'"

# 2. P1 Fix: Stage to temporary directory first
echo "→ Staging new bundle to temporary location..."
if ! RUN_ELEVATED "ditto '$APP_SRC' '$STAGE_TARGET'"; then
    echo "❌ Lỗi: Sao chép file vào staging thất bại. Bản cài hiện tại được giữ nguyên an toàn."
    RUN_ELEVATED "rm -rf '$STAGE_TARGET'"
    exit 1
fi

# Verify staging directory integrity before replacing live target
if [ ! -f "$STAGE_TARGET/Contents/MacOS/VieLotusIM" ]; then
    echo "❌ Lỗi: Kiểm tra staging thất bại — thiếu executable."
    RUN_ELEVATED "rm -rf '$STAGE_TARGET'"
    exit 1
fi

# 3. P2 Fix: Quarantine (backup) user copy instead of deleting before health check
if [ "$TARGET" = "$SYS_TARGET" ] && [ -d "$USER_TARGET" ]; then
    USER_BAK="$HOME/Library/Input Methods/VieLotusIM.app.userbak.$RAND_ID"
    echo "→ Tạm lưu bản sao người dùng vào khu vực cách ly: $USER_BAK"
    mv "$USER_TARGET" "$USER_BAK"
    "$LSREGISTER" -u "$USER_TARGET" 2>/dev/null || true
fi

echo "→ Stopping active VieLotusIM process before swap..."
pkill -9 VieLotusIM 2>/dev/null || true

# Atomic swap with immediate rollback fallback
echo "→ Swapping live application bundle atomically..."
SWAP_SCRIPT="
if [ -d '$TARGET' ]; then
    mv '$TARGET' '$BAK_TARGET' || exit 10
fi
if mv '$STAGE_TARGET' '$TARGET'; then
    exit 0
else
    # Rollback immediately if move failed
    [ -d '$BAK_TARGET' ] && mv '$BAK_TARGET' '$TARGET'
    exit 20
fi
"

if ! RUN_ELEVATED "$SWAP_SCRIPT"; then
    DO_ROLLBACK "Hoán đổi bundle thất bại"
fi

# Update LaunchServices registration
echo "→ Updating LaunchServices registration..."
"$LSREGISTER" -f "$TARGET" 2>/dev/null || true

# 4. P1 Fix: Strict compilation and execution of register-source helper
echo "→ Compiling TIS registration helper..."
if ! swiftc -O "scripts/pkg-resources/register-source.swift" -framework Carbon -target arm64-apple-macos13 -o "$TMP_HELPER" 2>&1; then
    DO_ROLLBACK "Biên dịch register-source helper thất bại"
fi

echo "→ Registering Input Source with TIS..."
if ! "$TMP_HELPER" "$TARGET" 2>&1; then
    DO_ROLLBACK "Đăng ký hoặc kích hoạt TIS Input Source thất bại"
fi
rm -f "$TMP_HELPER"

# Refresh TextInputMenuAgent to update the macOS input menu bar immediately
killall -9 TextInputMenuAgent 2>/dev/null || true

# 5. P2 Fix: Launch with Explicit Multi-Stage Health Verification
echo "→ Launching newly installed VieLotusIM..."
if ! open "$TARGET"; then
    DO_ROLLBACK "Lệnh open $TARGET thất bại"
fi

# Health check Phase 1: Poll for initial process PID up to 5 seconds
echo "→ Verifying initial process spawn..."
RUNNING_PID=""
for i in {1..10}; do
    RUNNING_PID="$(pgrep -f "$TARGET/Contents/MacOS/VieLotusIM" | head -n 1 || true)"
    if [ -n "$RUNNING_PID" ]; then
        break
    fi
    sleep 0.5
done

if [ -z "$RUNNING_PID" ]; then
    DO_ROLLBACK "Tiến trình VieLotusIM không xuất hiện sau khi open"
fi

# Health check Phase 2: Process stability check (ensure process does NOT crash immediately)
echo "→ Verifying process stability (liveness across sampling)..."
sleep 1.5
if ! kill -0 "$RUNNING_PID" 2>/dev/null; then
    DO_ROLLBACK "Tiến trình VieLotusIM bị crash đột ngột sau khi khởi động"
fi

# Health check Phase 3: TIS functional readiness check
echo "→ Verifying TIS input source availability..."
TIS_CHECK_SCRIPT="
import Carbon
guard let list = TISCreateInputSourceList(nil, true)?.takeRetainedValue() as? [TISInputSource] else { exit(1) }
let found = list.contains { src in
    guard let idPtr = TISGetInputSourceProperty(src, kTISPropertyInputSourceID) else { return false }
    let id = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
    return id.lowercased().contains(\"vielotus\")
}
exit(found ? 0 : 2)
"
if ! swift -e "$TIS_CHECK_SCRIPT" 2>/dev/null; then
    DO_ROLLBACK "TIS không tìm thấy nguồn gõ Sen Việt khả dụng"
fi

# 6. Finalization: All health checks passed! Safely clean up backups
echo "→ Cleaning up temporary backups..."
RUN_ELEVATED "rm -rf '$BAK_TARGET'"
if [ -n "$USER_BAK" ] && [ -d "$USER_BAK" ]; then
    rm -rf "$USER_BAK"
fi

DEPLOYED_VER="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$TARGET/Contents/Info.plist" 2>/dev/null || echo "Unknown")"
DEPLOYED_COMMIT="$(/usr/libexec/PlistBuddy -c "Print :GitCommitHash" "$TARGET/Contents/Info.plist" 2>/dev/null || echo "Unknown")"
DEPLOYED_TIME="$(/usr/libexec/PlistBuddy -c "Print :BuildTimestamp" "$TARGET/Contents/Info.plist" 2>/dev/null || echo "Unknown")"

echo "======================================================="
echo "✅ NẠP VÀ KIỂM ĐỊNH THÀNH CÔNG VIELOTUSIM!"
echo "  • Vị trí cài đặt      : $TARGET"
echo "  • Tiến trình PID sống : $RUNNING_PID (ổn định)"
echo "  • Trạng thái TIS      : Sẵn sàng (Active / Enabled)"
echo "  • Phiên bản           : $DEPLOYED_VER"
echo "  • Git Commit          : $DEPLOYED_COMMIT"
echo "  • Thời gian build     : $DEPLOYED_TIME"
echo "======================================================="
