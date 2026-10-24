#!/bin/bash
set -euo pipefail

# ==============================================================================
# Sen Việt (VieLotusIM) - All-in-One Debian / Ubuntu (.deb) Packaging Script
# Generates a single self-contained installer:
#   vielotus_${VERSION}_${ARCH}.deb
# containing:
#   1. Shared C-ABI Engine Library (libVieLotusCAPI.so + Swift Linux Runtime)
#   2. Fcitx5 Input Method Addon (vielotus.so + vielotus.conf)
#   3. IBus Input Method Engine (ibus-engine-vielotus + vielotus.xml)
#   4. Freedesktop Icons & typing-modes.yml
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

VERSION="${1:-1.1.1}"
ARCH="${2:-amd64}"

DIST_LINUX="${ROOT_DIR}/dist/linux"
DEB_BASE="${ROOT_DIR}/dist/deb"

echo "🌸 === Đóng gói Sen Việt (VieLotusIM) All-in-One v${VERSION} (.deb) cho kiến trúc ${ARCH} ==="

if [ ! -f "${DIST_LINUX}/vielotus.so" ] || [ ! -f "${DIST_LINUX}/libVieLotusCAPI.so" ] || [ ! -f "${DIST_LINUX}/ibus-engine-vielotus" ]; then
    echo "⚠️  Chưa tìm thấy đầy đủ binary tại ${DIST_LINUX}."
    echo "💡 Đang chạy build qua Docker trước..."
    "${SCRIPT_DIR}/docker_build_linux.sh"
fi

rm -rf "${DEB_BASE}"
mkdir -p "${DEB_BASE}"
mkdir -p "${ROOT_DIR}/dist"

build_deb() {
    local pkg_dir="$1"
    local output_file="$2"
    if command -v dpkg-deb >/dev/null 2>&1; then
        dpkg-deb --build --root-owner-group "${pkg_dir}" "${output_file}"
    elif command -v docker >/dev/null 2>&1; then
        local rel_pkg_dir="${pkg_dir#"${ROOT_DIR}/"}"
        local rel_out="${output_file#"${ROOT_DIR}/"}"
        docker run --rm \
            -v "${ROOT_DIR}:/workspace" \
            -w /workspace \
            vielotus-linux-builder:latest \
            dpkg-deb --build --root-owner-group "${rel_pkg_dir}" "${rel_out}"
    fi
}

PKG_NAME="vielotus"
PKG_DIR="${DEB_BASE}/${PKG_NAME}_${VERSION}_${ARCH}"
echo "📦 Đóng gói All-in-One ${PKG_NAME}_${VERSION}_${ARCH}.deb..."

mkdir -p "${PKG_DIR}/DEBIAN"
mkdir -p "${PKG_DIR}/usr/lib"
mkdir -p "${PKG_DIR}/usr/lib/vielotus"
mkdir -p "${PKG_DIR}/etc/ld.so.conf.d"
mkdir -p "${PKG_DIR}/usr/include"
mkdir -p "${PKG_DIR}/usr/lib/fcitx5"
mkdir -p "${PKG_DIR}/usr/share/fcitx5/addon"
mkdir -p "${PKG_DIR}/usr/lib/ibus"
mkdir -p "${PKG_DIR}/usr/share/ibus/component"
mkdir -p "${PKG_DIR}/usr/share/doc/${PKG_NAME}"

# 1. Core C-ABI Library & Header
cp "${DIST_LINUX}/libVieLotusCAPI.so" "${PKG_DIR}/usr/lib/"
cp "${ROOT_DIR}/Sources/VieLotusCAPI/include/vielotus.h" "${PKG_DIR}/usr/include/"

# Bundle Swift Linux runtime libraries so end-user machines do not need the Swift toolchain installed
if [ -d "${DIST_LINUX}/swift-runtime" ]; then
    cp -a "${DIST_LINUX}/swift-runtime/"*.so* "${PKG_DIR}/usr/lib/vielotus/" 2>/dev/null || true
elif [ -d "/usr/lib/swift/linux" ]; then
    for lib in \
        libswiftCore.so \
        libswift_Concurrency.so \
        libswift_StringProcessing.so \
        libswift_RegexParser.so \
        libswiftGlibc.so \
        libswiftSynchronization.so \
        libBlocksRuntime.so \
        libdispatch.so \
        libswiftDispatch.so \
        libFoundation.so \
        libFoundationEssentials.so \
        libFoundationInternationalization.so \
        lib_FoundationICU.so; do
        if [ -f "/usr/lib/swift/linux/${lib}" ]; then
            cp -L "/usr/lib/swift/linux/${lib}" "${PKG_DIR}/usr/lib/vielotus/"
        fi
    done
fi
echo "/usr/lib/vielotus" > "${PKG_DIR}/etc/ld.so.conf.d/vielotus.conf"

# 2. Fcitx5 Addon
cp "${DIST_LINUX}/vielotus.so" "${PKG_DIR}/usr/lib/fcitx5/"
if [ "${ARCH}" = "amd64" ]; then
    mkdir -p "${PKG_DIR}/usr/lib/x86_64-linux-gnu/fcitx5"
    ln -sf ../../fcitx5/vielotus.so "${PKG_DIR}/usr/lib/x86_64-linux-gnu/fcitx5/vielotus.so"
elif [ "${ARCH}" = "arm64" ]; then
    mkdir -p "${PKG_DIR}/usr/lib/aarch64-linux-gnu/fcitx5"
    ln -sf ../../fcitx5/vielotus.so "${PKG_DIR}/usr/lib/aarch64-linux-gnu/fcitx5/vielotus.so"
fi
cp "${DIST_LINUX}/vielotus.conf" "${PKG_DIR}/usr/share/fcitx5/addon/"
cp "${ROOT_DIR}/CrossPlatform/fcitx5-vielotus/README.md" "${PKG_DIR}/usr/share/doc/${PKG_NAME}/"

# 3. IBus Engine
cp "${DIST_LINUX}/ibus-engine-vielotus" "${PKG_DIR}/usr/lib/ibus/"
cp "${DIST_LINUX}/vielotus.xml" "${PKG_DIR}/usr/share/ibus/component/"

# 4. Freedesktop hicolor icons (16x16 -> 512x512) & status indicators
for size in 16x16 24x24 32x32 48x48 64x64 128x128 256x256 512x512; do
    ICON_SRC="${ROOT_DIR}/CrossPlatform/linux-icons/hicolor_${size}_apps/vielotus.png"
    if [ -f "${ICON_SRC}" ]; then
        mkdir -p "${PKG_DIR}/usr/share/icons/hicolor/${size}/apps"
        cp "${ICON_SRC}" "${PKG_DIR}/usr/share/icons/hicolor/${size}/apps/vielotus.png"
    fi
done

if [ -d "${ROOT_DIR}/CrossPlatform/linux-icons/status_indicators" ]; then
    mkdir -p "${PKG_DIR}/usr/share/vielotus/icons"
    cp "${ROOT_DIR}/CrossPlatform/linux-icons/status_indicators/"*.png "${PKG_DIR}/usr/share/vielotus/icons/"
fi

# 5. Desktop resource files (typing-modes.yml only)
if [ -f "${ROOT_DIR}/Resources/typing-modes.yml" ]; then
    mkdir -p "${PKG_DIR}/usr/share/vielotus/VietLotusIM_VieLotusCore.resources"
    cp "${ROOT_DIR}/Resources/typing-modes.yml" "${PKG_DIR}/usr/share/vielotus/VietLotusIM_VieLotusCore.resources/"
elif [ -f "${ROOT_DIR}/Sources/VieLotusCore/Resources/typing-modes.yml" ]; then
    mkdir -p "${PKG_DIR}/usr/share/vielotus/VietLotusIM_VieLotusCore.resources"
    cp "${ROOT_DIR}/Sources/VieLotusCore/Resources/typing-modes.yml" "${PKG_DIR}/usr/share/vielotus/VietLotusIM_VieLotusCore.resources/"
fi

cat <<EOF > "${PKG_DIR}/DEBIAN/control"
Package: ${PKG_NAME}
Version: ${VERSION}
Section: utils
Priority: optional
Architecture: ${ARCH}
Maintainer: Dat Nguyen <support@vielotus.org>
Depends: libc6 (>= 2.34), libglib2.0-0 | libglib2.0-0t64
Recommends: ibus | fcitx5
Provides: libvielotus, ibus-vielotus, fcitx5-vielotus
Replaces: libvielotus, ibus-vielotus, fcitx5-vielotus
Conflicts: libvielotus, ibus-vielotus, fcitx5-vielotus
Description: Sen Việt (VieLotusIM) — Next-Gen Vietnamese Input Method (IBus & Fcitx5)
 All-in-one installer containing the Pure Swift 6 Vietnamese engine core
 (libVieLotusCAPI.so + bundled Swift runtime) alongside both native IBus
 and Fcitx5 input method plugins for Ubuntu, Debian, Mint, and Pop!_OS.
EOF

cat <<'EOF' > "${PKG_DIR}/DEBIAN/postinst"
#!/bin/sh
set -e
if command -v ldconfig >/dev/null 2>&1; then
    ldconfig
fi
echo "🌸 Sen Việt (VieLotusIM) v1.1.1 đã được cài đặt thành công (IBus & Fcitx5)!"
exit 0
EOF
chmod 755 "${PKG_DIR}/DEBIAN/postinst"

build_deb "${PKG_DIR}" "${DIST_LINUX}/${PKG_NAME}_${VERSION}_${ARCH}.deb"
rm -rf "${DEB_BASE}"

echo "======================================================="
echo "🎉 Gói All-in-One Debian/Ubuntu (.deb) đã sẵn sàng tại:"
ls -lh "${DIST_LINUX}/${PKG_NAME}_${VERSION}_${ARCH}.deb"
echo "======================================================="
