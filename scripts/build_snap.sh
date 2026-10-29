#!/bin/bash
set -euo pipefail

# ==============================================================================
# Sen Việt (VieLotusIM) - Canonical Snap (.snap) Packaging Script
# Generates self-contained Snap packages for Snap Store (core24):
#   dist/linux/vielotus_${VERSION}_amd64.snap
#   dist/linux/vielotus_${VERSION}_arm64.snap
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

VERSION="${1:-2.0.0}"
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

    echo "🌸 === Đóng gói Snap: vielotus_${VERSION}_${arch}.snap (${arch}) ==="

    if [ ! -f "${deb_file}" ]; then
        echo "⚠️  Chưa thấy ${deb_file}, đang tạo gói .deb trước..."
        "${SCRIPT_DIR}/build_deb.sh" "${VERSION}" "${arch}"
    fi

    rm -rf "${prime_dir}"
    mkdir -p "${prime_dir}/meta/gui"

    # 1. Extract Linux payload from the verified .deb package
    ar p "${deb_file}" data.tar.xz | tar -xJf - -C "${prime_dir}"

    # Remove Debian-specific ld.so.conf.d (Snap uses LD_LIBRARY_PATH in snap.yaml)
    rm -rf "${prime_dir}/etc"

    # Replace any symlinks with regular files so macOS symlink permissions (0755 vs Linux 0777)
    # never cause SquashFS inode/checksum mismatches on Snap Store review-tools
    find "${prime_dir}" -type l | while read -r link_path; do
        target_path="$(cd "$(dirname "${link_path}")" && realpath "$(readlink "${link_path}")")"
        rm -f "${link_path}"
        cp -p "${target_path}" "${link_path}"
    done

    # 2. Create Snap runner wrappers
    cat << 'RUNNER_EOF' > "${prime_dir}/usr/bin/ibus-engine-vielotus-runner"
#!/bin/sh
export LD_LIBRARY_PATH="${SNAP}/usr/lib:${SNAP}/usr/lib/vielotus:${SNAP}/usr/lib/x86_64-linux-gnu:${SNAP}/usr/lib/aarch64-linux-gnu:${LD_LIBRARY_PATH:-}"
export VIELOTUS_RESOURCE_PATH="${SNAP}/usr/share/vielotus/VietLotusIM_VieLotusCore.resources"
exec "${SNAP}/usr/lib/ibus/ibus-engine-vielotus" "$@"
RUNNER_EOF
    chmod 755 "${prime_dir}/usr/bin/ibus-engine-vielotus-runner"

    cat << 'SNAP_SETTINGS_EOF' > "${prime_dir}/usr/bin/vielotus-snap-runner"
#!/bin/sh
set -e

export LD_LIBRARY_PATH="${SNAP}/usr/lib:${SNAP}/usr/lib/vielotus:${SNAP}/usr/lib/x86_64-linux-gnu:${SNAP}/usr/lib/aarch64-linux-gnu:${LD_LIBRARY_PATH:-}"
export VIELOTUS_RESOURCE_PATH="${SNAP}/usr/share/vielotus/VietLotusIM_VieLotusCore.resources"

# Export Fcitx5 addon, IBus engine & runtime libraries into ~/.local/lib/vielotus so host fcitx5/ibus can load them
USER_LIB_BASE="${HOME}/.local/lib/vielotus"
mkdir -p "${USER_LIB_BASE}/fcitx5" "${USER_LIB_BASE}/ibus" "${USER_LIB_BASE}/lib"
cp -f "${SNAP}/usr/lib/fcitx5/vielotus.so" "${USER_LIB_BASE}/fcitx5/vielotus.so" 2>/dev/null || true
cp -f "${SNAP}/usr/lib/ibus/ibus-engine-vielotus" "${USER_LIB_BASE}/ibus/ibus-engine-vielotus" 2>/dev/null || true
chmod 755 "${USER_LIB_BASE}/ibus/ibus-engine-vielotus" 2>/dev/null || true
cp -f "${SNAP}/usr/lib/libVieLotusCAPI.so" "${USER_LIB_BASE}/lib/libVieLotusCAPI.so" 2>/dev/null || true
cp -f "${SNAP}/usr/lib/vielotus/"*.so* "${USER_LIB_BASE}/lib/" 2>/dev/null || true

cat <<IBUS_WRAP_EOF > "${USER_LIB_BASE}/ibus/ibus-engine-vielotus-runner"
#!/bin/sh
export LD_LIBRARY_PATH="${USER_LIB_BASE}/lib:/usr/lib:/usr/lib/vielotus:\${LD_LIBRARY_PATH:-}"
exec "${USER_LIB_BASE}/ibus/ibus-engine-vielotus" "\$@"
IBUS_WRAP_EOF
chmod 755 "${USER_LIB_BASE}/ibus/ibus-engine-vielotus-runner" 2>/dev/null || true

if [ ! -x /usr/lib/ibus/ibus-engine-vielotus ] && pgrep -x ibus-daemon >/dev/null 2>&1; then
    pkill -f ibus-engine-vielotus >/dev/null 2>&1 || true
    nohup "${USER_LIB_BASE}/ibus/ibus-engine-vielotus-runner" --ibus >/dev/null 2>&1 &
fi

ENV_D_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/environment.d"
mkdir -p "${ENV_D_DIR}"
cat <<ENV_EOF > "${ENV_D_DIR}/90-vielotus.conf"
FCITX_ADDON_DIRS=${USER_LIB_BASE}/fcitx5:/usr/lib/aarch64-linux-gnu/fcitx5:/usr/lib/x86_64-linux-gnu/fcitx5:/usr/lib/fcitx5
LD_LIBRARY_PATH=${USER_LIB_BASE}/lib:/usr/lib:/usr/lib/vielotus
ENV_EOF

export FCITX_ADDON_DIRS="${USER_LIB_BASE}/fcitx5:/usr/lib/aarch64-linux-gnu/fcitx5:/usr/lib/x86_64-linux-gnu/fcitx5:/usr/lib/fcitx5"
export LD_LIBRARY_PATH="${USER_LIB_BASE}/lib:${LD_LIBRARY_PATH}"

exec "${SNAP}/usr/bin/vielotus-settings" "$@"
SNAP_SETTINGS_EOF
    chmod 755 "${prime_dir}/usr/bin/vielotus-snap-runner"

    # 3. Populate meta/gui/icon.png and meta/gui/vielotus.desktop
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

    # 4. Write Canonical meta/snap.yaml
    cat << SNAP_YAML_EOF > "${prime_dir}/meta/snap.yaml"
name: vielotus
version: '${VERSION}'
title: Sen Việt (VieLotusIM)
summary: Sen Việt (VieLotusIM) - Next-Gen Vietnamese Input Method (IBus & Fcitx5)
description: |
  Sen Việt (VieLotusIM) là bộ gõ tiếng Việt thế hệ mới với lõi xử lý Pure Swift 6
  và trí tuệ song ngữ thông minh Anh–Việt (Smart Bilingual), đạt độ chính xác
  100.00% (9.091/9.091) trên bộ kiểm thử hồi quy chính thức (cùng 97.33% [365/375]
  ở vế đối xứng không ngữ cảnh ambiguous_both_sides và 100.00% [182/182] ở nhóm
  đường gõ duy nhất never).

  Tính năng nổi bật:
  - Gõ dấu tự do SEN Flex (Telex & VNI) tự nhiên, chuẩn xác.
  - Tự động nhận diện và khôi phục từ tiếng Anh / thuật ngữ lập trình khi gõ song ngữ.
  - Hỗ trợ đồng thời cả hai chuẩn bộ gõ phổ biến nhất trên Linux: IBus và Fcitx5.
  - Tương thích hoàn hảo với Ubuntu, Debian, Linux Mint, Pop!_OS, Fedora và Arch Linux.
architectures:
  - ${arch}
base: core24
confinement: strict
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
    plugs:
      - desktop
      - desktop-legacy
      - gsettings
      - home
      - wayland
      - x11
    environment:
      LD_LIBRARY_PATH: \$SNAP/usr/lib:\$SNAP/usr/lib/vielotus:\$SNAP/usr/lib/x86_64-linux-gnu:\$SNAP/usr/lib/aarch64-linux-gnu
      PATH: \$SNAP/usr/sbin:\$SNAP/usr/bin:\$SNAP/sbin:\$SNAP/bin:\$PATH
      VIELOTUS_RESOURCE_PATH: \$SNAP/usr/share/vielotus/VietLotusIM_VieLotusCore.resources
  ibus-engine:
    command: usr/bin/ibus-engine-vielotus-runner
    plugs:
      - desktop
      - desktop-legacy
      - gsettings
      - home
      - wayland
      - x11
    environment:
      LD_LIBRARY_PATH: \$SNAP/usr/lib:\$SNAP/usr/lib/vielotus:\$SNAP/usr/lib/x86_64-linux-gnu:\$SNAP/usr/lib/aarch64-linux-gnu
      PATH: \$SNAP/usr/sbin:\$SNAP/usr/bin:\$SNAP/sbin:\$SNAP/bin:\$PATH
      VIELOTUS_RESOURCE_PATH: \$SNAP/usr/share/vielotus/VietLotusIM_VieLotusCore.resources
SNAP_YAML_EOF

    # 5. Strip macOS extended attributes and Finder metadata files
    find "${prime_dir}" -name ".DS_Store" -o -name "._*" -delete 2>/dev/null || true
    if command -v xattr >/dev/null 2>&1; then
        xattr -cr "${prime_dir}" 2>/dev/null || true
    fi

    # 6. Validate skeleton with official `snap pack --check-skeleton`
    echo "🔍 Kiểm tra cấu trúc Snap skeleton (${arch})..."
    snap pack --check-skeleton "${prime_dir}"

    # 7. Pack .snap archive using official `snap pack`
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

echo "======================================================="
echo "🎉 Hoàn tất đóng gói Snap (.snap) tại ${DIST_LINUX}:"
ls -lh "${DIST_LINUX}"/*.snap
echo "======================================================="
