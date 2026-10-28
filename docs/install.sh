#!/bin/sh
# ==============================================================================
# Sen Việt (VieLotusIM) — One-Line Linux Installer & Language Support
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

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "❌ Vui lòng chạy lệnh với quyền root hoặc cài đặt sudo."
        exit 1
    fi
fi

echo "🌸 === Cài đặt Sen Việt (VieLotusIM) & Tích hợp Ubuntu Language Support ==="

# Register into Ubuntu Language Support (gnome-language-selector / check-language-support -l vi)
PKG_DEPENDS="/usr/share/language-selector/data/pkg_depends"
if [ -f "${PKG_DEPENDS}" ]; then
    if ! grep -q "im:vi::vielotus" "${PKG_DEPENDS}" 2>/dev/null; then
        printf "\n# Sen Việt (VieLotusIM) Vietnamese Input Method\nim:vi::vielotus\nim:vi:fcitx5:fcitx5-vielotus\nim:vi:ibus:ibus-vielotus\n" | ${SUDO} tee -a "${PKG_DEPENDS}" >/dev/null || true
    fi
fi

DEB_FILE="vielotus_${VERSION}_${DEB_ARCH}.deb"
DOWNLOAD_URL="https://github.com/stevedat/VieLotus-IM/releases/download/v${VERSION}/${DEB_FILE}"
TMP_DEB="/tmp/${DEB_FILE}"

echo "⬇️  Đang tải gói cài đặt từ: ${DOWNLOAD_URL}..."

if command -v curl >/dev/null 2>&1; then
    curl -fL --progress-bar "${DOWNLOAD_URL}" -o "${TMP_DEB}"
elif command -v wget >/dev/null 2>&1; then
    wget -q --show-progress "${DOWNLOAD_URL}" -O "${TMP_DEB}"
else
    echo "❌ Cần cài đặt curl hoặc wget để tải gói cài đặt."
    exit 1
fi

echo "📦 Đang cài đặt ${DEB_FILE} qua apt..."
${SUDO} apt-get update -qq || true
${SUDO} apt-get install -y "${TMP_DEB}" || (${SUDO} dpkg -i "${TMP_DEB}" && ${SUDO} apt-get install -f -y)
rm -f "${TMP_DEB}"

if [ -x /usr/bin/vielotus-settings ]; then
    /usr/bin/vielotus-settings --activate || true
fi

if command -v fcitx5 >/dev/null 2>&1; then
    fcitx5 -r -d >/dev/null 2>&1 || true
fi

echo ""
echo "======================================================================"
echo "✅ Cài đặt & tích hợp Ubuntu Language Support cho Sen Việt hoàn tất!"
echo "  • Tự động nhận diện khi cài ngôn ngữ Tiếng Việt (check-language-support -l vi)"
echo "  • Đổi bộ gõ nhanh trên màn hình : Super + Space / Ctrl + Space"
echo "  • Mở ứng dụng cài đặt (GUI)     : Tìm 'Sen Việt' trong Menu ứng dụng"
echo "  • Chuyển sang kiểu gõ Telex     : vielotus --telex"
echo "  • Chuyển sang kiểu gõ VNI       : vielotus --vni"
echo "======================================================================"
