#!/bin/sh
# ==============================================================================
# Sen Việt (VieLotusIM) v2.0.0 — Universal Linux (Multi-Distro & Multi-Arch)
# & macOS One-Line Installer
#
# Supported Linux Distros:
#   • Ubuntu, Debian, Linux Mint, Pop!_OS, Zorin, Elementary, Kali (apt / dpkg)
#   • Fedora, RHEL, CentOS Stream, Rocky, AlmaLinux (dnf)
#   • Arch Linux, Manjaro, EndeavourOS, CachyOS, Garuda (pacman)
#   • openSUSE Tumbleweed / Leap (zypper)
# Supported Architectures:
#   • x86_64 / amd64
#   • aarch64 / arm64
#
# Usage:
#   curl -fsSL https://stevedat.github.io/VieLotus-IM/install.sh | sh
# ==============================================================================
set -e

VERSION="${VIELOTUS_VERSION:-2.0.0}"
OS_NAME="$(uname -s)"
ARCH_RAW="$(uname -m)"

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "❌ Vui lòng chạy lệnh với quyền root hoặc cài đặt sudo."
        exit 1
    fi
fi

# ------------------------------------------------------------------------------
# macOS Support (if invoked on Darwin)
# ------------------------------------------------------------------------------
if [ "${OS_NAME}" = "Darwin" ]; then
    echo "🌸 === Cài đặt Sen Việt (VieLotusIM v${VERSION}) cho macOS ==="
    TMP_PKG="/tmp/VieLotusIM.pkg"
    echo "⬇️  Đang tải gói cài đặt VieLotusIM.pkg..."
    curl -fL --progress-bar "https://github.com/stevedat/VieLotus-IM/releases/latest/download/VieLotusIM.pkg" -o "${TMP_PKG}"
    echo "📦 Đang cài đặt vào /Library/Input Methods..."
    ${SUDO} installer -pkg "${TMP_PKG}" -target /
    rm -f "${TMP_PKG}"
    echo "✅ Cài đặt Sen Việt trên macOS hoàn tất!"
    exit 0
fi

# ------------------------------------------------------------------------------
# Linux Architecture Detection (x86_64/amd64 & aarch64/arm64)
# ------------------------------------------------------------------------------
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

echo "🌸 === Cài đặt Sen Việt (VieLotusIM v${VERSION}) cho Linux (${DEB_ARCH}) ==="

DEB_FILE="vielotus_${VERSION}_${DEB_ARCH}.deb"
PRIMARY_URL="https://github.com/stevedat/VieLotus-IM/releases/download/v${VERSION}/${DEB_FILE}"
FALLBACK_URL="https://github.com/stevedat/VieLotus-IM/releases/latest/download/${DEB_FILE}"
RAW_REPO_URL="https://raw.githubusercontent.com/stevedat/VieLotus-IM/main/Binaries/linux/${DEB_FILE}"
TMP_DEB="/tmp/${DEB_FILE}"

download_file() {
    url="$1"
    dest="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "${url}" -o "${dest}"
    elif command -v wget >/dev/null 2>&1; then
        wget -q "${url}" -O "${dest}"
    else
        echo "❌ Cần cài đặt curl hoặc wget để tải gói cài đặt."
        exit 1
    fi
}

echo "⬇️  Đang tải gói cài đặt (${DEB_FILE})..."
if ! download_file "${PRIMARY_URL}" "${TMP_DEB}" 2>/dev/null; then
    if ! download_file "${FALLBACK_URL}" "${TMP_DEB}" 2>/dev/null; then
        download_file "${RAW_REPO_URL}" "${TMP_DEB}"
    fi
fi

# Helper to extract .deb payload on non-Debian distros (Arch, Fedora, openSUSE)
extract_deb_to_root() {
    deb_path="$1"
    work_dir="/tmp/vielotus-extract-$$"
    rm -rf "${work_dir}"
    mkdir -p "${work_dir}"

    if command -v python3 >/dev/null 2>&1; then
        python3 - "${deb_path}" "${work_dir}" <<'PYEOF'
import os, sys, tarfile

deb_path = sys.argv[1]
work_dir = sys.argv[2]

with open(deb_path, "rb") as f:
    magic = f.read(8)
    if magic != b"!<arch>\n":
        raise SystemExit("Invalid .deb archive")
    while True:
        hdr = f.read(60)
        if len(hdr) < 60:
            break
        name = hdr[:16].decode("ascii", errors="ignore").strip().rstrip("/")
        size = int(hdr[48:58].decode("ascii").strip())
        data = f.read(size)
        if size % 2 == 1:
            f.read(1)
        if name.startswith("data.tar"):
            data_tar = os.path.join(work_dir, name)
            with open(data_tar, "wb") as out:
                out.write(data)
            with tarfile.open(data_tar, "r:*") as tf:
                tf.extractall(os.path.join(work_dir, "rootfs"))
            break
PYEOF
    elif command -v ar >/dev/null 2>&1; then
        mkdir -p "${work_dir}/rootfs"
        (cd "${work_dir}" && ar x "${deb_path}" && tar -xf data.tar.* -C "${work_dir}/rootfs")
    else
        echo "❌ Cần python3 hoặc binutils (ar) để giải nén gói cài đặt."
        rm -rf "${work_dir}"
        exit 1
    fi

    ${SUDO} cp -a "${work_dir}/rootfs/usr" /
    ${SUDO} cp -a "${work_dir}/rootfs/etc" /

    # Multiarch / lib64 compatibility for Fedora, RHEL, openSUSE, Arch
    if [ -d /usr/lib64 ]; then
        ${SUDO} ln -sf /usr/lib/libVieLotusCAPI.so /usr/lib64/libVieLotusCAPI.so
        ${SUDO} mkdir -p /usr/lib64/fcitx5
        ${SUDO} ln -sf /usr/lib/fcitx5/vielotus.so /usr/lib64/fcitx5/vielotus.so
    fi
    if [ -d /usr/libexec ] && [ ! -e /usr/libexec/ibus-engine-vielotus ]; then
        ${SUDO} ln -sf /usr/lib/ibus/ibus-engine-vielotus /usr/libexec/ibus-engine-vielotus
    fi

    rm -rf "${work_dir}"
}

finalize_linux_integration() {
    if command -v ldconfig >/dev/null 2>&1; then
        ${SUDO} ldconfig >/dev/null 2>&1 || true
    fi
    if command -v update-desktop-database >/dev/null 2>&1; then
        ${SUDO} update-desktop-database -q /usr/share/applications >/dev/null 2>&1 || true
    fi
    if command -v gtk-update-icon-cache >/dev/null 2>&1; then
        ${SUDO} gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor >/dev/null 2>&1 || true
    fi
    if command -v ibus >/dev/null 2>&1; then
        ${SUDO} ibus write-cache --system >/dev/null 2>&1 || true
    fi
}

# ------------------------------------------------------------------------------
# Distro Package Manager Dispatch
# ------------------------------------------------------------------------------
if command -v apt-get >/dev/null 2>&1 && command -v dpkg >/dev/null 2>&1; then
    echo "📦 Phát hiện hệ sinh thái Debian / Ubuntu (apt)..."
    PKG_DEPENDS="/usr/share/language-selector/data/pkg_depends"
    if [ -f "${PKG_DEPENDS}" ]; then
        if ! grep -q "im:vi::vielotus" "${PKG_DEPENDS}" 2>/dev/null; then
            printf "\n# Sen Việt (VieLotusIM) Vietnamese Input Method\nim:vi::vielotus\nim:vi:fcitx5:fcitx5-vielotus\nim:vi:ibus:ibus-vielotus\n" | ${SUDO} tee -a "${PKG_DEPENDS}" >/dev/null || true
        fi
    fi
    ${SUDO} apt-get update -qq || true
    ${SUDO} apt-get install -y "${TMP_DEB}" || (${SUDO} dpkg -i "${TMP_DEB}" && ${SUDO} apt-get install -f -y)
elif command -v pacman >/dev/null 2>&1; then
    echo "📦 Phát hiện hệ sinh thái Arch Linux / Manjaro (pacman)..."
    ${SUDO} pacman -S --needed --noconfirm python-gobject gtk3 2>/dev/null || true
    extract_deb_to_root "${TMP_DEB}"
    finalize_linux_integration
elif command -v dnf >/dev/null 2>&1; then
    echo "📦 Phát hiện hệ sinh thái Fedora / RHEL (dnf)..."
    ${SUDO} dnf install -y python3-gobject gtk3 2>/dev/null || true
    extract_deb_to_root "${TMP_DEB}"
    finalize_linux_integration
elif command -v zypper >/dev/null 2>&1; then
    echo "📦 Phát hiện hệ sinh thái openSUSE (zypper)..."
    ${SUDO} zypper --non-interactive install python3-gobject typelib-1_0-Gtk-3_0 2>/dev/null || true
    extract_deb_to_root "${TMP_DEB}"
    finalize_linux_integration
else
    echo "📦 Cài đặt trực tiếp vào /usr (Generic Linux)..."
    extract_deb_to_root "${TMP_DEB}"
    finalize_linux_integration
fi

rm -f "${TMP_DEB}"

if [ -x /usr/bin/vielotus-settings ]; then
    /usr/bin/vielotus-settings --activate || true
fi

if command -v fcitx5 >/dev/null 2>&1; then
    fcitx5 -r -d >/dev/null 2>&1 || true
fi

echo ""
echo "======================================================================"
echo "✅ Cài đặt & kích hoạt Sen Việt (VieLotusIM v${VERSION}) hoàn tất!"
echo "  • Kiến trúc CPU                 : ${DEB_ARCH} (${ARCH_RAW})"
echo "  • Đổi bộ gõ nhanh trên màn hình : Super + Space / Ctrl + Space"
echo "  • Mở ứng dụng cài đặt (GUI)     : Tìm 'Sen Việt' trong Menu ứng dụng (hoặc gõ: vielotus)"
echo "  • Chuyển sang kiểu gõ Telex     : vielotus --telex"
echo "  • Chuyển sang kiểu gõ VNI       : vielotus --vni"
echo "  • Xem trạng thái hiện tại       : vielotus --status"
echo "======================================================================"
