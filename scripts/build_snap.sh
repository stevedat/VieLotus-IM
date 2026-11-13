#!/bin/bash
set -euo pipefail

# ==============================================================================
# Sen Việt (VieLotusIM) - Canonical Classic Snap (.snap) Packaging Script
# Generates classic-confined Snap packages for Snap Store (core24):
#   dist/linux/vielotus_${VERSION}_amd64.snap
#   dist/linux/vielotus_${VERSION}_arm64.snap
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

VERSION="${1:-2.0.2}"
TARGET_ARCH="${2:-all}"

DIST_LINUX="${ROOT_DIR}/dist/linux"
SNAP_STAGE_BASE="${ROOT_DIR}/.build/snap-stage"

if ! command -v snap >/dev/null 2>&1; then
    echo "❌ Lỗi: Không tìm thấy công cụ 'snap' (cài qua: brew install snapcraft squashfs)."
    exit 1
fi

build_arch_snap() {
    local arch="$1"
    local deb_file="${DIST_LINUX}/vielotus_${VERSION}_${arch}.deb"
    local prime_dir="${SNAP_STAGE_BASE}/prime-${arch}"
    local out_snap="${DIST_LINUX}/vielotus_${VERSION}_${arch}.snap"

    echo "🌸 === Đóng gói Classic Snap: vielotus_${VERSION}_${arch}.snap (${arch}) ==="

    if [ ! -f "${deb_file}" ]; then
        echo "⚠️  Chưa thấy ${deb_file}, đang tạo gói .deb trước..."
        "${SCRIPT_DIR}/build_deb.sh" "${VERSION}" "${arch}"
        deb_file="${DIST_LINUX}/vielotus_${VERSION}_${arch}.deb"
    fi

    rm -rf "${prime_dir}"
    mkdir -p "${prime_dir}/meta/gui" "${prime_dir}/meta/hooks" "${prime_dir}/usr/share/vielotus/fontconfig"

    # 1. Extract Linux payload from the verified .deb package
    ar p "${deb_file}" data.tar.xz | tar -xJf - -C "${prime_dir}"

    # Overlay latest vielotus-settings script & fontconfig rules from source tree
    if [ -f "${ROOT_DIR}/CrossPlatform/packaging/linux/vielotus-settings" ]; then
        cp -f "${ROOT_DIR}/CrossPlatform/packaging/linux/vielotus-settings" "${prime_dir}/usr/bin/vielotus-settings"
        chmod 755 "${prime_dir}/usr/bin/vielotus-settings"
    fi
    if [ -d "${prime_dir}/etc/fonts/conf.d" ]; then
        cp -f "${prime_dir}/etc/fonts/conf.d/"*.conf "${prime_dir}/usr/share/vielotus/fontconfig/" 2>/dev/null || true
    fi
    rm -rf "${prime_dir}/etc"

    # Replace any symlinks with regular files so macOS symlink permissions (0755 vs Linux 0777)
    # never cause SquashFS inode/checksum warnings on Snap Store review-tools
    find "${prime_dir}" -type l | while read -r link_path; do
        target_path="$(cd "$(dirname "${link_path}")" && realpath "$(readlink "${link_path}")")"
        rm -f "${link_path}"
        cp -p "${target_path}" "${link_path}"
    done

    # 2. Create Classic Snap runner wrappers
    cat << 'RUNNER_EOF' > "${prime_dir}/usr/bin/ibus-engine-vielotus-runner"
#!/bin/sh
SNAP_ROOT="${SNAP:-/snap/vielotus/current}"
export LD_LIBRARY_PATH="${SNAP_ROOT}/usr/lib:${SNAP_ROOT}/usr/lib/vielotus:${LD_LIBRARY_PATH:-}"
export VIELOTUS_RESOURCE_PATH="${SNAP_ROOT}/usr/share/vielotus/VietLotusIM_VieLotusCore.resources"
exec "${SNAP_ROOT}/usr/lib/ibus/ibus-engine-vielotus" "$@"
RUNNER_EOF
    chmod 755 "${prime_dir}/usr/bin/ibus-engine-vielotus-runner"

    cat << 'SNAP_SETTINGS_EOF' > "${prime_dir}/usr/bin/vielotus-snap-runner"
#!/bin/sh
set -e

SNAP_ROOT="${SNAP:-/snap/vielotus/current}"
export PATH="/usr/local/bin:/usr/bin:/bin:${SNAP_ROOT}/usr/bin:${PATH:-}"
export VIELOTUS_RESOURCE_PATH="${SNAP_ROOT}/usr/share/vielotus/VietLotusIM_VieLotusCore.resources"

# Export Fcitx5 addon & C-ABI library into user XDG addon path for host fcitx5
USER_LIB_BASE="${HOME}/.local/lib/vielotus"
mkdir -p "${USER_LIB_BASE}/fcitx5" "${USER_LIB_BASE}/lib" 2>/dev/null || true
cp -f "${SNAP_ROOT}/usr/lib/fcitx5/vielotus.so" "${USER_LIB_BASE}/fcitx5/vielotus.so" 2>/dev/null || true
cp -f "${SNAP_ROOT}/usr/lib/libVieLotusCAPI.so" "${USER_LIB_BASE}/lib/libVieLotusCAPI.so" 2>/dev/null || true

ENV_D_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/environment.d"
mkdir -p "${ENV_D_DIR}" 2>/dev/null || true
cat <<ENV_EOF > "${ENV_D_DIR}/90-vielotus.conf" 2>/dev/null || true
FCITX_ADDON_DIRS=${USER_LIB_BASE}/fcitx5:/usr/lib/aarch64-linux-gnu/fcitx5:/usr/lib/x86_64-linux-gnu/fcitx5:/usr/lib/fcitx5
LD_LIBRARY_PATH=${USER_LIB_BASE}/lib:/usr/lib:/usr/lib/vielotus
ENV_EOF

# On first interactive launch, auto-activate IBus / GNOME Input Sources immediately
if [ "$#" -eq 0 ] && [ ! -f "${XDG_CONFIG_HOME:-$HOME/.config}/vielotus/config.env" ]; then
    "${SNAP_ROOT}/usr/bin/vielotus-settings" --activate >/dev/null 2>&1 || true
fi

exec "${SNAP_ROOT}/usr/bin/vielotus-settings" "$@"
SNAP_SETTINGS_EOF
    chmod 755 "${prime_dir}/usr/bin/vielotus-snap-runner"

    # 3. Create non-conflicting Classic lifecycle hooks (install, post-refresh, remove)
    cat << HOOK_INSTALL_EOF > "${prime_dir}/meta/hooks/install"
#!/bin/sh
set -e

SNAP_CURRENT="/snap/vielotus/current"

# Register IBus component under distinct vielotus-snap.xml if dpkg ibus-vielotus is not installed
if [ ! -x /usr/lib/ibus/ibus-engine-vielotus ] && [ -d /usr/share/ibus/component ]; then
    cat << 'XML_EOF' > /usr/share/ibus/component/vielotus-snap.xml
<?xml version="1.0" encoding="utf-8"?>
<component>
    <name>org.freedesktop.IBus.VieLotus</name>
    <description>VieLotusIM (Sen Việt) Vietnamese Input Method</description>
    <version>${VERSION}</version>
    <author>Nido Holdings (Steve Dat)</author>
    <homepage>https://github.com/stevedat/VieLotus-IM</homepage>
    <license>MIT</license>
    <exec>/snap/vielotus/current/usr/bin/ibus-engine-vielotus-runner --ibus</exec>
    <textdomain>ibus-vielotus</textdomain>
    <observed-paths>
        <path>/snap/vielotus/current/usr/lib/ibus/ibus-engine-vielotus</path>
    </observed-paths>
    <engines>
        <engine>
            <name>vielotus</name>
            <longname>Sen Việt - Telex</longname>
            <description>Bộ gõ tiếng Việt Sen Việt thế hệ mới (Telex)</description>
            <language>vi</language>
            <license>MIT</license>
            <author>Nido Holdings (Steve Dat)</author>
            <icon>/snap/vielotus/current/meta/gui/icon.png</icon>
            <layout>us</layout>
            <rank>99</rank>
            <symbol>🇻🇳 tex</symbol>
            <setup>/snap/vielotus/current/usr/bin/vielotus-snap-runner</setup>
        </engine>
        <engine>
            <name>vielotus-vni</name>
            <longname>Sen Việt - VNI</longname>
            <description>Bộ gõ tiếng Việt Sen Việt thế hệ mới (VNI)</description>
            <language>vi</language>
            <license>MIT</license>
            <author>Nido Holdings (Steve Dat)</author>
            <icon>/snap/vielotus/current/meta/gui/icon.png</icon>
            <layout>us</layout>
            <rank>98</rank>
            <symbol>🇻🇳 vni</symbol>
            <setup>/snap/vielotus/current/usr/bin/vielotus-snap-runner</setup>
        </engine>
    </engines>
</component>
XML_EOF
    if command -v ibus >/dev/null 2>&1; then
        ibus write-cache --system >/dev/null 2>&1 || true
    fi
fi

# Install Vietnamese hook-above monospace fontconfig rule if not already provided by .deb
if [ ! -f /etc/fonts/conf.d/51-vielotus-vietnamese.conf ] && [ -d /etc/fonts/conf.d ]; then
    if [ -f "\${SNAP_CURRENT}/usr/share/vielotus/fontconfig/51-vielotus-vietnamese.conf" ]; then
        cp -f "\${SNAP_CURRENT}/usr/share/vielotus/fontconfig/51-vielotus-vietnamese.conf" /etc/fonts/conf.d/51-vielotus-snap-vietnamese.conf 2>/dev/null || true
    fi
fi
exit 0
HOOK_INSTALL_EOF
    chmod 755 "${prime_dir}/meta/hooks/install"
    cp -p "${prime_dir}/meta/hooks/install" "${prime_dir}/meta/hooks/post-refresh"

    cat << 'HOOK_REMOVE_EOF' > "${prime_dir}/meta/hooks/remove"
#!/bin/sh
set -e
rm -f /usr/share/ibus/component/vielotus-snap.xml 2>/dev/null || true
rm -f /etc/fonts/conf.d/51-vielotus-snap-vietnamese.conf 2>/dev/null || true
if command -v ibus >/dev/null 2>&1; then
    ibus write-cache --system >/dev/null 2>&1 || true
fi
exit 0
HOOK_REMOVE_EOF
    chmod 755 "${prime_dir}/meta/hooks/remove"

    # 4. Populate meta/gui/icon.png and meta/gui/vielotus.desktop
    if [ -f "${ROOT_DIR}/CrossPlatform/linux-icons/hicolor_512x512_apps/vielotus.png" ]; then
        cp "${ROOT_DIR}/CrossPlatform/linux-icons/hicolor_512x512_apps/vielotus.png" "${prime_dir}/meta/gui/icon.png"
    elif [ -f "${prime_dir}/usr/share/icons/hicolor/512x512/apps/vielotus.png" ]; then
        cp "${prime_dir}/usr/share/icons/hicolor/512x512/apps/vielotus.png" "${prime_dir}/meta/gui/icon.png"
    fi

    cat << 'GUI_DESKTOP_EOF' > "${prime_dir}/meta/gui/vielotus.desktop"
[Desktop Entry]
Version=1.0
Type=Application
Name=Sen Việt (VieLotus)
Name[vi]=Sen Việt (Bộ gõ tiếng Việt)
GenericName=Vietnamese Input Method
GenericName[vi]=Bộ gõ tiếng Việt
Comment=Configure and activate Sen Việt Vietnamese Input Method (Telex & VNI)
Comment[vi]=Cài đặt và kích hoạt bộ gõ tiếng Việt Sen Việt (Telex & VNI)
Exec=vielotus
Icon=${SNAP}/meta/gui/icon.png
Terminal=false
Categories=Utility;Settings;DesktopSettings;
Keywords=Vietnamese;Telex;VNI;Input Method;IBus;Fcitx5;Sen Viet;VieLotus;Bo go tieng Viet;
StartupNotify=true
GUI_DESKTOP_EOF

    # 5. Write Canonical meta/snap.yaml (confinement: classic -> zero plugs allowed per review-tools)
    cat << SNAP_YAML_EOF > "${prime_dir}/meta/snap.yaml"
name: vielotus
version: '${VERSION}'
title: Sen Việt (VieLotusIM)
summary: Sen Việt (VieLotusIM) - Next-Gen Vietnamese Input Method (IBus & Fcitx5)
description: |
  Sen Việt (VieLotusIM) là bộ gõ tiếng Việt thế hệ mới phát triển bởi Nido Holdings,
  đạt độ chính xác 100.00% (9.091/9.091) trên bộ kiểm thử hồi quy chính thức
  (cùng 97.33% [365/375] ở vế đối xứng không ngữ cảnh ambiguous_both_sides và
  100.00% [182/182] ở nhóm đường gõ duy nhất never).

  Tính năng nổi bật:
  - Gõ dấu tự do SEN Flex & Chuẩn cổ điển (Telex & VNI) tự nhiên, chuẩn xác.
  - Tự động nhận diện và khôi phục từ tiếng Anh / thuật ngữ lập trình khi gõ song ngữ.
  - Hỗ trợ đồng thời cả hai chuẩn bộ gõ phổ biến nhất trên Linux: IBus và Fcitx5.
  - Đồng bộ trải nghiệm đa nền tảng: macOS, iOS/iPadOS (App Store), Windows (Microsoft Store), Android (Google Play) và Linux.
architectures:
  - ${arch}
base: core24
confinement: classic
grade: stable
license: MIT
links:
  contact:
    - https://github.com/stevedat/VieLotus-IM/issues
  issues:
    - https://github.com/stevedat/VieLotus-IM/issues
  source-code:
    - https://github.com/stevedat/VieLotus-IM
  website:
    - https://stevedat.github.io/VieLotus-IM/
apps:
  vielotus:
    command: usr/bin/vielotus-snap-runner
    common-id: org.vielotus.VieLotus
  ibus-engine:
    command: usr/bin/ibus-engine-vielotus-runner
SNAP_YAML_EOF

    # 6. Strip macOS extended attributes and Finder metadata files
    find "${prime_dir}" -name ".DS_Store" -o -name "._*" -delete 2>/dev/null || true
    if command -v xattr >/dev/null 2>&1; then
        xattr -cr "${prime_dir}" 2>/dev/null || true
    fi

    # 7. Validate skeleton with official `snap pack --check-skeleton`
    echo "🔍 Kiểm tra cấu trúc Classic Snap skeleton (${arch})..."
    snap pack --check-skeleton "${prime_dir}"

    # 8. Pack .snap archive using official `snap pack`
    mkdir -p "${DIST_LINUX}"
    rm -f "${out_snap}"
    snap pack --compression xz --filename "vielotus_${VERSION}_${arch}.snap" "${prime_dir}" "${DIST_LINUX}"

    echo "✅ Đã tạo thành công: ${out_snap}"
    ls -lh "${out_snap}"
}

rm -rf "${SNAP_STAGE_BASE}"
mkdir -p "${SNAP_STAGE_BASE}"

if [ "${TARGET_ARCH}" = "all" ]; then
    build_arch_snap "amd64"
    build_arch_snap "arm64"
else
    build_arch_snap "${TARGET_ARCH}"
fi

rm -rf "${SNAP_STAGE_BASE}"
