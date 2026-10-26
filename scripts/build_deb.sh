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
        dpkg-deb -Zxz --build --root-owner-group "${pkg_dir}" "${output_file}"
    elif command -v docker >/dev/null 2>&1; then
        local rel_pkg_dir="${pkg_dir#"${ROOT_DIR}/"}"
        local rel_out="${output_file#"${ROOT_DIR}/"}"
        docker run --rm \
            -v "${ROOT_DIR}:/workspace" \
            -w /workspace \
            vielotus-linux-builder:latest \
            dpkg-deb -Zxz --build --root-owner-group "${rel_pkg_dir}" "${rel_out}"
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
python3 - "${ROOT_DIR}/Sources/VieLotusCAPI/include/vielotus.h" "${PKG_DIR}/usr/include/vielotus.h" << 'PYEOF'
import re, sys
with open(sys.argv[1], "r", encoding="utf-8") as f:
    h = f.read()
h = re.sub(r"// =+\n// Context-Aware Word Suggestion Engine\n// =+\n.*?(?=// =+\n// Version & Metadata)", "", h, flags=re.S)
h = re.sub(r"\n*// =+\n// EDU-TYPE Local Loopback Bridge.*?(?=\n#ifdef __cplusplus)", "\n", h, flags=re.S)
with open(sys.argv[2], "w", encoding="utf-8") as f:
    f.write(h)
PYEOF

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

# 6. Desktop Application Launcher, GUI/CLI Settings Utility & AppStream Metadata
install_desktop_integration() {
    local target_root="$1"
    mkdir -p "${target_root}/usr/bin"
    mkdir -p "${target_root}/usr/share/applications"
    mkdir -p "${target_root}/usr/share/metainfo"

    cat <<'SETTINGS_EOF' > "${target_root}/usr/bin/vielotus-settings"
#!/bin/sh
# ==============================================================================
# Sen Việt (VieLotusIM) — Linux Desktop Settings & Auto-Activation Utility
# ==============================================================================
set -e

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/vielotus"
CONFIG_FILE="${CONFIG_DIR}/config.env"
mkdir -p "${CONFIG_DIR}"

INPUT_METHOD="telex"
if [ -f "${CONFIG_FILE}" ]; then
    . "${CONFIG_FILE}" 2>/dev/null || true
fi

save_and_apply() {
    MODE="$1"
    printf 'INPUT_METHOD="%s"\n' "${MODE}" > "${CONFIG_FILE}"
    ENGINE_ID="vielotus"
    if [ "${MODE}" = "vni" ]; then
        ENGINE_ID="vielotus-vni"
    fi

    # 1. Refresh IBus cache & switch active engine
    if command -v ibus >/dev/null 2>&1; then
        ibus write-cache >/dev/null 2>&1 || true
        ibus engine "${ENGINE_ID}" >/dev/null 2>&1 || true
    fi

    # 2. Register into GNOME / Ubuntu Input Sources (org.gnome.desktop.input-sources)
    if command -v gsettings >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
        python3 - "${ENGINE_ID}" <<'PYEOF' 2>/dev/null || true
import subprocess, sys, ast
engine_id = sys.argv[1]
try:
    raw = subprocess.check_output(
        ["gsettings", "get", "org.gnome.desktop.input-sources", "sources"],
        stderr=subprocess.DEVNULL
    ).decode().strip()
    if raw.startswith("@a(ss) "):
        raw = raw[len("@a(ss) "):]
    sources = list(ast.literal_eval(raw)) if raw else []
except Exception:
    sources = []

if not sources:
    sources = [("xkb", "us")]

# Replace any existing vielotus entry or append
sources = [s for s in sources if not (s[0] == "ibus" and s[1] in ("vielotus", "vielotus-vni"))]
sources.append(("ibus", engine_id))
formatted = "[" + ", ".join(f"('{k}', '{v}')" for k, v in sources) + "]"
subprocess.call(["gsettings", "set", "org.gnome.desktop.input-sources", "sources", formatted],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
PYEOF
    fi
}

case "${1:-}" in
    --activate)
        save_and_apply "${INPUT_METHOD}"
        echo "✅ Đã kích hoạt bộ gõ Sen Việt (${INPUT_METHOD})."
        exit 0
        ;;
    --telex)
        save_and_apply "telex"
        echo "✅ Đã chuyển Sen Việt sang kiểu gõ Telex."
        exit 0
        ;;
    --vni)
        save_and_apply "vni"
        echo "✅ Đã chuyển Sen Việt sang kiểu gõ VNI."
        exit 0
        ;;
esac

# Always ensure the input source is registered when the user opens the app
save_and_apply "${INPUT_METHOD}"

if command -v zenity >/dev/null 2>&1 && [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
    TELEX_TRUE="TRUE"
    VNI_TRUE="FALSE"
    if [ "${INPUT_METHOD}" = "vni" ]; then
        TELEX_TRUE="FALSE"
        VNI_TRUE="TRUE"
    fi
    CHOICE=$(zenity --list --radiolist \
        --title="Sen Việt (VieLotusIM) — Cài đặt bộ gõ" \
        --text="Bộ gõ tiếng Việt Sen Việt đã được kích hoạt trên thanh ngôn ngữ hệ thống (Super + Space).\nChọn kiểu gõ mặc định:" \
        --width=460 --height=260 \
        --column="Chọn" --column="Mã" --column="Kiểu gõ tiếng Việt" \
        "${TELEX_TRUE}" "telex" "Telex (Gõ dấu tự do SEN Flex & Song ngữ thông minh)" \
        "${VNI_TRUE}" "vni" "VNI (Gõ dấu bằng phím số 1–9)" \
        --hide-column=2 2>/dev/null || true)
    if [ -n "${CHOICE}" ]; then
        save_and_apply "${CHOICE}"
        zenity --notification --text="Sen Việt: Đã kích hoạt kiểu gõ $(echo "${CHOICE}" | tr 'a-z' 'A-Z')" 2>/dev/null || true
    fi
    exit 0
fi

echo "🌸 === Sen Việt (VieLotusIM) cho Linux ==="
echo "Trạng thái: Đã kích hoạt (${INPUT_METHOD})"
echo "  • Chuyển sang Telex : vielotus --telex"
echo "  • Chuyển sang VNI   : vielotus --vni"
echo "  • Phím tắt đổi bộ gõ: Super + Space"
SETTINGS_EOF
    chmod 755 "${target_root}/usr/bin/vielotus-settings"
    ln -sf vielotus-settings "${target_root}/usr/bin/vielotus"

    cat <<'DESKTOP_EOF' > "${target_root}/usr/share/applications/vielotus.desktop"
[Desktop Entry]
Version=1.0
Type=Application
Name=Sen Việt (VieLotus)
Name[vi]=Sen Việt (Bộ gõ tiếng Việt)
GenericName=Vietnamese Input Method
GenericName[vi]=Bộ gõ tiếng Việt
Comment=Configure and activate Sen Việt Vietnamese Input Method (Telex & VNI)
Comment[vi]=Cài đặt và kích hoạt bộ gõ tiếng Việt Sen Việt (Telex & VNI)
Exec=/usr/bin/vielotus-settings
Icon=vielotus
Terminal=false
Categories=Utility;Settings;DesktopSettings;
Keywords=Vietnamese;Telex;VNI;Input Method;IBus;Fcitx5;Sen Viet;VieLotus;Bo go tieng Viet;
StartupNotify=true
DESKTOP_EOF

    cat <<'META_EOF' > "${target_root}/usr/share/metainfo/org.vielotus.VieLotus.metainfo.xml"
<?xml version="1.0" encoding="UTF-8"?>
<component type="desktop-application">
  <id>org.vielotus.VieLotus</id>
  <metadata_license>MIT</metadata_license>
  <project_license>MIT</project_license>
  <name>Sen Việt (VieLotusIM)</name>
  <summary>Bộ gõ tiếng Việt thế hệ mới cho Linux (IBus &amp; Fcitx5)</summary>
  <description>
    <p>Sen Việt (VieLotusIM) là bộ gõ tiếng Việt thuần khiết với lõi xử lý song ngữ thông minh Anh–Việt (Smart Bilingual) và gõ dấu tự do Telex / VNI, hỗ trợ đồng thời cả IBus và Fcitx5 trên Ubuntu, Debian, Linux Mint và Pop!_OS.</p>
  </description>
  <launchable type="desktop-id">vielotus.desktop</launchable>
  <url type="homepage">https://stevedat.github.io/VieLotus-IM/</url>
  <developer_name>Trần Phát Đạt (Steve Dat)</developer_name>
  <provides>
    <binary>vielotus</binary>
    <binary>vielotus-settings</binary>
  </provides>
</component>
META_EOF
}

write_maintainer_scripts() {
    local target_root="$1"
    cat <<'EOF' > "${target_root}/DEBIAN/postinst"
#!/bin/sh
set -e
if command -v ldconfig >/dev/null 2>&1; then
    ldconfig >/dev/null 2>&1 || true
fi
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database -q /usr/share/applications >/dev/null 2>&1 || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor >/dev/null 2>&1 || true
fi
if command -v ibus >/dev/null 2>&1; then
    ibus write-cache --system >/dev/null 2>&1 || true
fi

# Auto-register Sen Việt into the active desktop user's GNOME/IBus session
TARGET_USER="${SUDO_USER:-}"
if [ -z "${TARGET_USER}" ] && [ -n "${PKEXEC_UID:-}" ]; then
    TARGET_USER=$(id -nu "${PKEXEC_UID}" 2>/dev/null || true)
fi
if [ -z "${TARGET_USER}" ]; then
    TARGET_USER=$(who 2>/dev/null | awk '{print $1; exit}' || true)
fi
if [ -n "${TARGET_USER}" ] && [ "${TARGET_USER}" != "root" ] && [ -x /usr/bin/vielotus-settings ]; then
    TARGET_UID=$(id -u "${TARGET_USER}" 2>/dev/null || true)
    if [ -n "${TARGET_UID}" ] && [ -S "/run/user/${TARGET_UID}/bus" ]; then
        su - "${TARGET_USER}" -c "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/${TARGET_UID}/bus /usr/bin/vielotus-settings --activate" >/dev/null 2>&1 || true
    fi
fi
exit 0
EOF
    chmod 755 "${target_root}/DEBIAN/postinst"

    cat <<'EOF' > "${target_root}/DEBIAN/postrm"
#!/bin/sh
set -e
if command -v ldconfig >/dev/null 2>&1; then
    ldconfig >/dev/null 2>&1 || true
fi
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database -q /usr/share/applications >/dev/null 2>&1 || true
fi
if command -v ibus >/dev/null 2>&1; then
    ibus write-cache --system >/dev/null 2>&1 || true
fi
exit 0
EOF
    chmod 755 "${target_root}/DEBIAN/postrm"
}

install_desktop_integration "${PKG_DIR}"

INSTALLED_SIZE=$(du -sk "${PKG_DIR}" | awk '{print $1}')

cat <<EOF > "${PKG_DIR}/DEBIAN/control"
Package: ${PKG_NAME}
Version: ${VERSION}
Section: utils
Priority: optional
Architecture: ${ARCH}
Installed-Size: ${INSTALLED_SIZE}
Maintainer: Trần Phát Đạt (Steve Dat) <https://github.com/stevedat/VieLotus-IM>
Homepage: https://github.com/stevedat/VieLotus-IM
Depends: libc6
Suggests: ibus, fcitx5, zenity
Description: Sen Việt (VieLotusIM) - Next-Gen Vietnamese Input Method (IBus & Fcitx5)
 All-in-one installer containing the Pure Swift 6 Vietnamese engine core
 (libVieLotusCAPI.so + bundled Swift runtime) alongside both native IBus
 and Fcitx5 input method plugins for Ubuntu, Debian, Mint, and Pop!_OS.
EOF

if command -v md5sum >/dev/null 2>&1; then
    (cd "${PKG_DIR}" && find usr etc -type f -exec md5sum {} + > DEBIAN/md5sums)
fi

write_maintainer_scripts "${PKG_DIR}"

build_deb "${PKG_DIR}" "${DIST_LINUX}/${PKG_NAME}_${VERSION}_${ARCH}.deb"
rm -rf "${DEB_BASE}"

if [ "${ARCH}" = "amd64" ] && [ -f "${ROOT_DIR}/Binaries/linux/${PKG_NAME}_${VERSION}_arm64.deb" ] && command -v dpkg-deb >/dev/null 2>&1; then
    echo "📦 Đồng bộ gói ${PKG_NAME}_${VERSION}_arm64.deb..."
    rm -rf /tmp/deb-arm64
    dpkg-deb -R "${ROOT_DIR}/Binaries/linux/${PKG_NAME}_${VERSION}_arm64.deb" /tmp/deb-arm64
    cp "${DIST_LINUX}/vielotus.xml" /tmp/deb-arm64/usr/share/ibus/component/vielotus.xml
    install_desktop_integration /tmp/deb-arm64
    rm -rf /tmp/deb-arm64/DEBIAN
    mkdir -p /tmp/deb-arm64/DEBIAN
    ARM64_SIZE=$(du -sk /tmp/deb-arm64 | awk '{print $1}')
    cat <<EOF > /tmp/deb-arm64/DEBIAN/control
Package: ${PKG_NAME}
Version: ${VERSION}
Section: utils
Priority: optional
Architecture: arm64
Installed-Size: ${ARM64_SIZE}
Maintainer: Trần Phát Đạt (Steve Dat) <https://github.com/stevedat/VieLotus-IM>
Homepage: https://github.com/stevedat/VieLotus-IM
Depends: libc6
Suggests: ibus, fcitx5, zenity
Description: Sen Việt (VieLotusIM) - Next-Gen Vietnamese Input Method (IBus & Fcitx5)
 All-in-one installer containing the Pure Swift 6 Vietnamese engine core
 (libVieLotusCAPI.so + bundled Swift runtime) alongside both native IBus
 and Fcitx5 input method plugins for Ubuntu, Debian, Mint, and Pop!_OS.
EOF
    if command -v md5sum >/dev/null 2>&1; then
        (cd /tmp/deb-arm64 && find usr etc -type f -exec md5sum {} + > DEBIAN/md5sums)
    fi
    write_maintainer_scripts /tmp/deb-arm64
    dpkg-deb -Zxz --build --root-owner-group /tmp/deb-arm64 "${DIST_LINUX}/${PKG_NAME}_${VERSION}_arm64.deb"
    rm -rf /tmp/deb-arm64
fi

echo "======================================================="
echo "🎉 Gói All-in-One Debian/Ubuntu (.deb) đã sẵn sàng tại:"
ls -lh "${DIST_LINUX}/${PKG_NAME}_${VERSION}_${ARCH}.deb"
echo "======================================================="
