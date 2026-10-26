#!/bin/sh
# ==============================================================================
# Sen Việt (VieLotusIM) — One-Line Linux Installer & Auto-Activator
# Usage:
#   curl -fsSL https://stevedat.github.io/VieLotus-IM/install.sh | sh
# ==============================================================================
set -e

VERSION="${VIELOTUS_VERSION:-1.1.1}"
ARCH_RAW="$(uname -m)"

case "${ARCH_RAW}" in
    x86_64|amd64)
        DEB_ARCH="amd64"
        ;;
    aarch64|arm64)
        DEB_ARCH="arm64"
        ;;
    *)
        echo "❌ Kiến trúc CPU chưa hỗ trợ tự động: ${ARCH_RAW} (Hỗ trợ: x86_64/amd64 và aarch64/arm64)"
        exit 1
        ;;
esac

DEB_FILE="vielotus_${VERSION}_${DEB_ARCH}.deb"
DOWNLOAD_URL="https://github.com/stevedat/VieLotus-IM/releases/download/v${VERSION}/${DEB_FILE}"
TMP_DEB="/tmp/${DEB_FILE}"

echo "🌸 === Cài đặt bộ gõ tiếng Việt Sen Việt (VieLotusIM v${VERSION} — ${DEB_ARCH}) ==="
echo "⬇️  Đang tải gói cài đặt từ: ${DOWNLOAD_URL}..."

if command -v curl >/dev/null 2>&1; then
    curl -fL --progress-bar "${DOWNLOAD_URL}" -o "${TMP_DEB}"
elif command -v wget >/dev/null 2>&1; then
    wget -q --show-progress "${DOWNLOAD_URL}" -O "${TMP_DEB}"
else
    echo "❌ Cần cài đặt curl hoặc wget để tải gói cài đặt."
    exit 1
fi

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "❌ Vui lòng chạy lệnh với quyền root hoặc cài đặt sudo."
        exit 1
    fi
fi

echo "📦 Đang cài đặt ${DEB_FILE}..."
${SUDO} dpkg -i "${TMP_DEB}" || ${SUDO} apt-get install -f -y
rm -f "${TMP_DEB}"

if [ -x /usr/bin/vielotus-settings ]; then
    /usr/bin/vielotus-settings --activate || true
fi

echo ""
echo "======================================================================"
echo "✅ Cài đặt & kích hoạt Sen Việt (VieLotusIM) hoàn tất!"
echo "  • Đổi bộ gõ nhanh trên màn hình : Super + Space"
echo "  • Mở ứng dụng cài đặt (GUI)     : Tìm 'Sen Việt' trong Menu ứng dụng"
echo "  • Chuyển sang kiểu gõ Telex     : vielotus --telex"
echo "  • Chuyển sang kiểu gõ VNI       : vielotus --vni"
echo "======================================================================"
