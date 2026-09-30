#!/bin/bash
set -e

echo "=== Cài đặt Sen Việt (VieLotusIM) cho macOS ==="
TEMP_PKG="/tmp/VieLotusIM.pkg"

echo "1/3 Đang tải bản phát hành mới nhất từ GitHub..."
curl -sL "https://github.com/stevedat/VietLotus-IM/releases/latest/download/VieLotusIM.pkg" -o "$TEMP_PKG"

if [ ! -f "$TEMP_PKG" ] || [ $(wc -c <"$TEMP_PKG") -lt 1000 ]; then
    echo "❌ Lỗi: Không thể tải gói cài đặt từ GitHub Releases."
    exit 1
fi

echo "2/3 Đang tiến hành cài đặt vào hệ thống..."
sudo installer -pkg "$TEMP_PKG" -target /
rm -f "$TEMP_PKG"

echo "3/3 Đang mở Cài đặt Bàn phím..."
open "x-apple.systempreferences:com.apple.Keyboard-Settings.extension" 2>/dev/null || open "/System/Library/PreferencePanes/Keyboard.prefPane" 2>/dev/null || true

echo "✅ Cài đặt Sen Việt hoàn tất!"
echo "👉 Lưu ý quan trọng: Nếu cài lần đầu, vui lòng Đăng xuất (Log Out) và đăng nhập lại để macOS hiển thị 'VieLotusIM' trong danh sách Tiếng Việt."
