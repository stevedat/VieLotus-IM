#!/bin/bash
set -euo pipefail

# ==============================================================================
# Sen Việt (VieLotusIM) - Debian / Ubuntu (.deb) Packaging Script
# Generates:
#   1. libvielotus (Shared C-ABI Engine Library)
#   2. fcitx5-vielotus (Fcitx5 Input Method Addon)
#   3. ibus-vielotus (IBus Input Method Engine)
#   4. vielotus (Meta-package)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

VERSION="${1:-1.1.1}"
ARCH="${2:-amd64}"

DIST_LINUX="${ROOT_DIR}/dist/linux"
DEB_BASE="${ROOT_DIR}/dist/deb"

echo "🌸 === Đóng gói Sen Việt (VieLotusIM) v${VERSION} (.deb) cho kiến trúc ${ARCH} ==="

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

# ==============================================================================
# 1. Package: libvielotus
# ==============================================================================
LIB_PKG="libvielotus"
LIB_DIR="${DEB_BASE}/${LIB_PKG}_${VERSION}_${ARCH}"
echo "📦 Đóng gói ${LIB_PKG}..."
mkdir -p "${LIB_DIR}/DEBIAN"
mkdir -p "${LIB_DIR}/usr/lib"
mkdir -p "${LIB_DIR}/usr/lib/vielotus"
mkdir -p "${LIB_DIR}/etc/ld.so.conf.d"
mkdir -p "${LIB_DIR}/usr/include"
mkdir -p "${LIB_DIR}/usr/share/doc/${LIB_PKG}"

cp "${DIST_LINUX}/libVieLotusCAPI.so" "${LIB_DIR}/usr/lib/"
cp "${ROOT_DIR}/Sources/VieLotusCAPI/include/vielotus.h" "${LIB_DIR}/usr/include/"

# Bundle Swift Linux runtime libraries so end-user machines do not need the Swift toolchain installed
if [ -d "${DIST_LINUX}/swift-runtime" ]; then
    cp -a "${DIST_LINUX}/swift-runtime/"*.so* "${LIB_DIR}/usr/lib/vielotus/" 2>/dev/null || true
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
            cp -L "/usr/lib/swift/linux/${lib}" "${LIB_DIR}/usr/lib/vielotus/"
        fi
    done
fi
echo "/usr/lib/vielotus" > "${LIB_DIR}/etc/ld.so.conf.d/vielotus.conf"

# Copy Freedesktop hicolor icons (16x16 -> 512x512) & status indicators
for size in 16x16 24x24 32x32 48x48 64x64 128x128 256x256 512x512; do
    ICON_SRC="${ROOT_DIR}/CrossPlatform/linux-icons/hicolor_${size}_apps/vielotus.png"
    if [ -f "${ICON_SRC}" ]; then
        mkdir -p "${LIB_DIR}/usr/share/icons/hicolor/${size}/apps"
        cp "${ICON_SRC}" "${LIB_DIR}/usr/share/icons/hicolor/${size}/apps/vielotus.png"
    fi
done

if [ -d "${ROOT_DIR}/CrossPlatform/linux-icons/status_indicators" ]; then
    mkdir -p "${LIB_DIR}/usr/share/vielotus/icons"
    cp "${ROOT_DIR}/CrossPlatform/linux-icons/status_indicators/"*.png "${LIB_DIR}/usr/share/vielotus/icons/"
fi

# Bundle VieLotusCore desktop resource files (typing-modes.yml only; exclude mobile suggestion dictionary)
if [ -f "${ROOT_DIR}/Resources/typing-modes.yml" ]; then
    mkdir -p "${LIB_DIR}/usr/share/vielotus/VietLotusIM_VieLotusCore.resources"
    cp "${ROOT_DIR}/Resources/typing-modes.yml" "${LIB_DIR}/usr/share/vielotus/VietLotusIM_VieLotusCore.resources/"
elif [ -f "${ROOT_DIR}/Sources/VieLotusCore/Resources/typing-modes.yml" ]; then
    mkdir -p "${LIB_DIR}/usr/share/vielotus/VietLotusIM_VieLotusCore.resources"
    cp "${ROOT_DIR}/Sources/VieLotusCore/Resources/typing-modes.yml" "${LIB_DIR}/usr/share/vielotus/VietLotusIM_VieLotusCore.resources/"
fi

cat <<EOF > "${LIB_DIR}/DEBIAN/control"
Package: ${LIB_PKG}
Version: ${VERSION}
Section: libs
Priority: optional
Architecture: ${ARCH}
Maintainer: Dat Nguyen <support@vielotus.org>
Depends: libc6 (>= 2.34)
Description: Next-Gen Pure Vietnamese Engine Shared Library (Sen Việt)
 Pure Swift 6 Vietnamese typing engine core exporting C-ABI.
 Features 99.97% smart bilingual auto-detection, zero-latency typing.
EOF

cat <<'EOF' > "${LIB_DIR}/DEBIAN/postinst"
#!/bin/sh
set -e
if command -v ldconfig >/dev/null 2>&1; then
    ldconfig
fi
exit 0
EOF
chmod 755 "${LIB_DIR}/DEBIAN/postinst"
build_deb "${LIB_DIR}" "${DIST_LINUX}/${LIB_PKG}_${VERSION}_${ARCH}.deb"
echo "✅ Thành công: dist/linux/${LIB_PKG}_${VERSION}_${ARCH}.deb"

# ==============================================================================
# 2. Package: fcitx5-vielotus
# ==============================================================================
FCITX_PKG="fcitx5-vielotus"
FCITX_DIR="${DEB_BASE}/${FCITX_PKG}_${VERSION}_${ARCH}"
echo "📦 Đóng gói ${FCITX_PKG}..."
mkdir -p "${FCITX_DIR}/DEBIAN"
mkdir -p "${FCITX_DIR}/usr/lib/fcitx5"
mkdir -p "${FCITX_DIR}/usr/share/fcitx5/addon"
mkdir -p "${FCITX_DIR}/usr/share/doc/${FCITX_PKG}"

cp "${DIST_LINUX}/vielotus.so" "${FCITX_DIR}/usr/lib/fcitx5/"
if [ "${ARCH}" = "amd64" ]; then
    mkdir -p "${FCITX_DIR}/usr/lib/x86_64-linux-gnu/fcitx5"
    ln -sf ../../fcitx5/vielotus.so "${FCITX_DIR}/usr/lib/x86_64-linux-gnu/fcitx5/vielotus.so"
elif [ "${ARCH}" = "arm64" ]; then
    mkdir -p "${FCITX_DIR}/usr/lib/aarch64-linux-gnu/fcitx5"
    ln -sf ../../fcitx5/vielotus.so "${FCITX_DIR}/usr/lib/aarch64-linux-gnu/fcitx5/vielotus.so"
fi
cp "${DIST_LINUX}/vielotus.conf" "${FCITX_DIR}/usr/share/fcitx5/addon/"
cp "${ROOT_DIR}/CrossPlatform/fcitx5-vielotus/README.md" "${FCITX_DIR}/usr/share/doc/${FCITX_PKG}/"

cat <<EOF > "${FCITX_DIR}/DEBIAN/control"
Package: ${FCITX_PKG}
Version: ${VERSION}
Section: utils
Priority: optional
Architecture: ${ARCH}
Maintainer: Dat Nguyen <support@vielotus.org>
Depends: fcitx5, ${LIB_PKG} (= ${VERSION}), libc6 (>= 2.34)
Description: Next-Gen Pure Vietnamese Input Engine for Fcitx5 (Sen Việt)
 Fcitx5 input method addon powered by Sen Việt (VieLotusIM) engine.
 Supports surrounding-text deletion with fallback to inline preedit.
EOF

cat <<'EOF' > "${FCITX_DIR}/DEBIAN/postinst"
#!/bin/sh
set -e
echo "🌸 Sen Việt (fcitx5-vielotus) đã được cài đặt thành công!"
echo "💡 Khởi động lại Fcitx5: fcitx5 -r -d"
exit 0
EOF
chmod 755 "${FCITX_DIR}/DEBIAN/postinst"
build_deb "${FCITX_DIR}" "${DIST_LINUX}/${FCITX_PKG}_${VERSION}_${ARCH}.deb"
echo "✅ Thành công: dist/linux/${FCITX_PKG}_${VERSION}_${ARCH}.deb"

# ==============================================================================
# 3. Package: ibus-vielotus
# ==============================================================================
IBUS_PKG="ibus-vielotus"
IBUS_DIR="${DEB_BASE}/${IBUS_PKG}_${VERSION}_${ARCH}"
echo "📦 Đóng gói ${IBUS_PKG}..."
mkdir -p "${IBUS_DIR}/DEBIAN"
mkdir -p "${IBUS_DIR}/usr/lib/ibus"
mkdir -p "${IBUS_DIR}/usr/share/ibus/component"
mkdir -p "${IBUS_DIR}/usr/share/doc/${IBUS_PKG}"

cp "${DIST_LINUX}/ibus-engine-vielotus" "${IBUS_DIR}/usr/lib/ibus/"
cp "${DIST_LINUX}/vielotus.xml" "${IBUS_DIR}/usr/share/ibus/component/"

cat <<EOF > "${IBUS_DIR}/DEBIAN/control"
Package: ${IBUS_PKG}
Version: ${VERSION}
Section: utils
Priority: optional
Architecture: ${ARCH}
Maintainer: Dat Nguyen <support@vielotus.org>
Depends: ibus, ${LIB_PKG} (= ${VERSION}), libc6 (>= 2.34), libglib2.0-0
Description: Next-Gen Pure Vietnamese Input Engine for IBus (Sen Việt)
 Native IBus input method engine daemon powered by Sen Việt engine.
 Ideal for default Ubuntu and GNOME desktop environments.
EOF

cat <<'EOF' > "${IBUS_DIR}/DEBIAN/postinst"
#!/bin/sh
set -e
echo "🌸 Sen Việt (ibus-vielotus) đã được cài đặt thành công!"
echo "💡 Khởi động lại IBus: ibus restart"
exit 0
EOF
chmod 755 "${IBUS_DIR}/DEBIAN/postinst"
build_deb "${IBUS_DIR}" "${DIST_LINUX}/${IBUS_PKG}_${VERSION}_${ARCH}.deb"
echo "✅ Thành công: dist/linux/${IBUS_PKG}_${VERSION}_${ARCH}.deb"

# ==============================================================================
# 4. Meta-package: vielotus
# ==============================================================================
META_PKG="vielotus"
META_DIR="${DEB_BASE}/${META_PKG}_${VERSION}_${ARCH}"
echo "📦 Đóng gói meta-package ${META_PKG}..."
mkdir -p "${META_DIR}/DEBIAN"
mkdir -p "${META_DIR}/usr/share/doc/${META_PKG}"

cat <<EOF > "${META_DIR}/DEBIAN/control"
Package: ${META_PKG}
Version: ${VERSION}
Section: metapackages
Priority: optional
Architecture: all
Maintainer: Dat Nguyen <support@vielotus.org>
Depends: ${LIB_PKG} (>= ${VERSION}), fcitx5-vielotus | ibus-vielotus
Description: VieLotusIM (Sen Việt) - Next-Gen Vietnamese Input Method Metapackage
 Installs VieLotus core library and either Fcitx5 or IBus frontend.
EOF
build_deb "${META_DIR}" "${DIST_LINUX}/${META_PKG}_${VERSION}_all.deb"
echo "✅ Thành công: dist/linux/${META_PKG}_${VERSION}_all.deb"

rm -rf "${DEB_BASE}"

echo "======================================================="
echo "🎉 Tất cả các gói Debian/Ubuntu (.deb) đã sẵn sàng tại:"
ls -lh "${DIST_LINUX}/"*.deb
echo "======================================================="
