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

echo "→ Target deployment path: $TARGET (elevated=$NEED_SUDO)"

# 2. P1 Fix: Atomic Staging and Rollback Architecture
# Stage the new app bundle first without touching the current live installation
echo "→ Staging new bundle to temporary location..."
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

# Clean any leftover temporary directories from prior interrupted runs
RUN_ELEVATED "rm -rf '$STAGE_TARGET' '$BAK_TARGET'"

# Perform safe staging and swap
echo "→ Copying new bundle into staging..."
if ! RUN_ELEVATED "ditto '$APP_SRC' '$STAGE_TARGET'"; then
    echo "❌ Lỗi: Sao chép file vào staging thất bại. Bộ gõ hiện tại được giữ nguyên an toàn."
    RUN_ELEVATED "rm -rf '$STAGE_TARGET'"
    exit 1
fi

# Verify staging directory integrity before replacing live target
if [ ! -f "$STAGE_TARGET/Contents/MacOS/VieLotusIM" ]; then
    echo "❌ Lỗi: Kiểm tra staging thất bại — thiếu executable."
    RUN_ELEVATED "rm -rf '$STAGE_TARGET'"
    exit 1
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
    echo "❌ Lỗi: Hoán đổi bundle thất bại! Đang phục hồi bản cài đặt cũ..."
    RUN_ELEVATED "[ -d '$BAK_TARGET' ] && [ ! -d '$TARGET' ] && mv '$BAK_TARGET' '$TARGET' ; rm -rf '$STAGE_TARGET'"
    open "$TARGET" 2>/dev/null || true
    exit 1
fi

# 3. Clean up conflicting opposite copy ONLY AFTER primary target swap succeeds
if [ "$TARGET" = "$SYS_TARGET" ] && [ -d "$USER_TARGET" ]; then
    echo "→ Dọn dẹp bản sao trùng lặp tại thư mục người dùng: $USER_TARGET"
    rm -rf "$USER_TARGET"
    "$LSREGISTER" -u "$USER_TARGET" 2>/dev/null || true
fi

# Update LaunchServices registration
echo "→ Updating LaunchServices registration..."
"$LSREGISTER" -f "$TARGET" 2>/dev/null || true

# Recompile and execute TIS registration helper cleanly (deduplicating sources)
echo "→ Registering Input Source with TIS..."
TMP_HELPER="/tmp/vielotus-reg-helper-$RAND_ID"
if swiftc -O "scripts/pkg-resources/register-source.swift" -framework Carbon -target arm64-apple-macos13 -o "$TMP_HELPER" 2>/dev/null; then
    "$TMP_HELPER" "$TARGET" || echo "⚠️ Cảnh báo: register-source trả về mã lỗi."
    rm -f "$TMP_HELPER"
fi

# Refresh TextInputMenuAgent to update the macOS input menu bar immediately
killall -9 TextInputMenuAgent 2>/dev/null || true

# 4. P2 Fix: Launch with Explicit Health Verification
echo "→ Launching newly installed VieLotusIM..."
if ! open "$TARGET"; then
    echo "❌ Lỗi: Lệnh 'open $TARGET' thất bại!"
    if [ -d "$BAK_TARGET" ]; then
        echo "→ Đang hoàn tác về bản cũ..."
        RUN_ELEVATED "rm -rf '$TARGET' && mv '$BAK_TARGET' '$TARGET'"
        open "$TARGET" 2>/dev/null || true
    fi
    exit 1
fi

# Health check: verify process is running within 5 seconds
echo "→ Verifying process health..."
RUNNING_PID=""
for i in {1..10}; do
    RUNNING_PID="$(pgrep -f "$TARGET/Contents/MacOS/VieLotusIM" | head -n 1 || true)"
    if [ -n "$RUNNING_PID" ]; then
        break
    fi
    sleep 0.5
done

if [ -z "$RUNNING_PID" ]; then
    echo "❌ Lỗi: Tiến trình VieLotusIM không khởi chạy thành công sau khi nạp!"
    if [ -d "$BAK_TARGET" ]; then
        echo "→ Đang hoàn tác về bản cũ..."
        RUN_ELEVATED "rm -rf '$TARGET' && mv '$BAK_TARGET' '$TARGET'"
        open "$TARGET" 2>/dev/null || true
    fi
    exit 1
fi

# Remove backup after verified successful launch
RUN_ELEVATED "rm -rf '$BAK_TARGET'"

DEPLOYED_VER="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$TARGET/Contents/Info.plist" 2>/dev/null || echo "Unknown")"
DEPLOYED_COMMIT="$(/usr/libexec/PlistBuddy -c "Print :GitCommitHash" "$TARGET/Contents/Info.plist" 2>/dev/null || echo "Unknown")"
DEPLOYED_TIME="$(/usr/libexec/PlistBuddy -c "Print :BuildTimestamp" "$TARGET/Contents/Info.plist" 2>/dev/null || echo "Unknown")"

echo "======================================================="
echo "✅ Nạp và khởi động thành công VieLotusIM!"
echo "  • Vị trí cài đặt : $TARGET"
echo "  • Tiến trình PID : $RUNNING_PID"
echo "  • Phiên bản      : $DEPLOYED_VER"
echo "  • Git Commit     : $DEPLOYED_COMMIT"
echo "  • Thời gian build: $DEPLOYED_TIME"
echo "======================================================="
