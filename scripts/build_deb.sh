#!/bin/bash
set -euo pipefail

# ==============================================================================
# Sen Việt (VieLotusIM) - All-in-One Debian / Ubuntu (.deb) Packaging Script
# Generates self-contained installers:
#   vielotus_${VERSION}_amd64.deb
#   vielotus_${VERSION}_arm64.deb
# containing:
#   1. Shared C-ABI Engine Library (libVieLotusCAPI.so + Swift Linux Runtime)
#   2. Fcitx5 Input Method Addon (vielotus.so + addon/vielotus.conf + inputmethod/*.conf)
#   3. IBus Input Method Engine (ibus-engine-vielotus + vielotus.xml)
#   4. Desktop Settings Utility (vielotus-settings), Freedesktop Icons & typing-modes.yml
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

VERSION="${1:-2.0.0}"
ARCH="${2:-amd64}"

DIST_LINUX="${ROOT_DIR}/dist/linux"
DEB_BASE="${ROOT_DIR}/dist/deb"
PACKAGING_LINUX="${ROOT_DIR}/CrossPlatform/packaging/linux"

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
    elif command -v python3 >/dev/null 2>&1; then
        python3 - "${pkg_dir}" "${output_file}" <<'PYEOF'
import io, lzma, os, stat, sys, tarfile, time

pkg_dir = os.path.abspath(sys.argv[1])
output_file = os.path.abspath(sys.argv[2])
control_dir = os.path.join(pkg_dir, "DEBIAN")
mtime = int(time.time())

def reset_root(ti):
    ti.uid = 0
    ti.gid = 0
    ti.uname = "root"
    ti.gname = "root"
    ti.mtime = mtime
    return ti

def build_tar_xz(root_dir, is_control=False):
    raw_buf = io.BytesIO()
    with tarfile.open(fileobj=raw_buf, mode="w", format=tarfile.GNU_FORMAT) as tf:
        root_ti = tarfile.TarInfo(name=".")
        root_ti.type = tarfile.DIRTYPE
        root_ti.mode = 0o755
        tf.addfile(reset_root(root_ti))

        for dirpath, dirnames, filenames in os.walk(root_dir):
            dirnames.sort()
            filenames.sort()
            rel_dir = os.path.relpath(dirpath, root_dir)
            if is_control and rel_dir != ".":
                continue
            if not is_control and (rel_dir == "DEBIAN" or rel_dir.startswith("DEBIAN" + os.sep)):
                dirnames[:] = []
                continue

            if rel_dir != ".":
                arc_dir = "./" + rel_dir.replace(os.sep, "/")
                ti = tf.gettarinfo(dirpath, arcname=arc_dir)
                ti.mode = 0o755
                tf.addfile(reset_root(ti))

            for fname in filenames:
                fpath = os.path.join(dirpath, fname)
                arc_name = "./" + fname if rel_dir == "." else "./" + os.path.join(rel_dir, fname).replace(os.sep, "/")
                st = os.lstat(fpath)
                ti = tf.gettarinfo(fpath, arcname=arc_name)
                if stat.S_ISLNK(st.st_mode):
                    ti.mode = 0o777
                    tf.addfile(reset_root(ti))
                else:
                    if is_control and fname in ("postinst", "postrm", "preinst", "prerm"):
                        ti.mode = 0o755
                    elif st.st_mode & stat.S_IXUSR:
                        ti.mode = 0o755
                    else:
                        ti.mode = 0o644
                    with open(fpath, "rb") as fobj:
                        tf.addfile(reset_root(ti), fileobj=fobj)

    return lzma.compress(raw_buf.getvalue(), preset=6)

def ar_member(name, data):
    hdr = f"{name:<16}{mtime:<12}{0:<6}{0:<6}{0o100644:<8o}{len(data):<10}`\n".encode("ascii")
    pad = b"\n" if (len(data) % 2 == 1) else b""
    return hdr + data + pad

control_xz = build_tar_xz(control_dir, is_control=True)
data_xz = build_tar_xz(pkg_dir, is_control=False)

os.makedirs(os.path.dirname(output_file), exist_ok=True)
with open(output_file, "wb") as out:
    out.write(b"!<arch>\n")
    out.write(ar_member("debian-binary", b"2.0\n"))
    out.write(ar_member("control.tar.xz", control_xz))
    out.write(ar_member("data.tar.xz", data_xz))
PYEOF
    else
        echo "❌ Không tìm thấy dpkg-deb hoặc python3 để đóng gói .deb."
        exit 1
    fi
}

verify_elf_arch() {
    local target_arch="$1"
    shift
    python3 - "${target_arch}" "$@" <<'PYEOF'
import struct, sys

target_arch = sys.argv[1]
expected_machine = {"amd64": 62, "arm64": 183}.get(target_arch)
if expected_machine is None:
    sys.exit(0)

for path in sys.argv[2:]:
    with open(path, "rb") as f:
        hdr = f.read(20)
    if len(hdr) < 20 or hdr[:4] != b"\x7fELF":
        raise SystemExit(f"❌ Tệp không phải ELF hợp lệ: {path}")
    e_machine = struct.unpack("<H", hdr[18:20])[0]
    if e_machine != expected_machine:
        raise SystemExit(
            f"❌ Sai kiến trúc ELF cho {path}: e_machine={e_machine} (kỳ vọng {expected_machine} cho {target_arch})"
        )
PYEOF
}

install_desktop_integration() {
    local target_root="$1"
    mkdir -p "${target_root}/usr/bin"
    mkdir -p "${target_root}/usr/share/applications"
    mkdir -p "${target_root}/usr/share/metainfo"

    cp "${PACKAGING_LINUX}/vielotus-settings" "${target_root}/usr/bin/vielotus-settings"
    chmod 755 "${target_root}/usr/bin/vielotus-settings"
    ln -sf vielotus-settings "${target_root}/usr/bin/vielotus"

    cp "${PACKAGING_LINUX}/vielotus.desktop" "${target_root}/usr/share/applications/vielotus.desktop"
    for setup_name in ibus-setup-vielotus.desktop ibus-setup-vielotus-vni.desktop; do
        cp "${PACKAGING_LINUX}/vielotus.desktop" "${target_root}/usr/share/applications/${setup_name}"
        echo "NoDisplay=true" >> "${target_root}/usr/share/applications/${setup_name}"
    done
    cp "${PACKAGING_LINUX}/org.vielotus.VieLotus.metainfo.xml" \
       "${target_root}/usr/share/metainfo/org.vielotus.VieLotus.metainfo.xml"
}

write_maintainer_scripts() {
    local target_root="$1"
    cp "${PACKAGING_LINUX}/postinst" "${target_root}/DEBIAN/postinst"
    chmod 755 "${target_root}/DEBIAN/postinst"

    cp "${PACKAGING_LINUX}/postrm" "${target_root}/DEBIAN/postrm"
    chmod 755 "${target_root}/DEBIAN/postrm"
}

resolve_arch_bin_dir() {
    local target_arch="$1"
    local candidate="${DIST_LINUX}/${target_arch}"
    if [ -d "${candidate}" ] && [ -f "${candidate}/vielotus.so" ] && [ -f "${candidate}/ibus-engine-vielotus" ] && [ -f "${candidate}/libVieLotusCAPI.so" ]; then
        if verify_elf_arch "${target_arch}" "${candidate}/libVieLotusCAPI.so" "${candidate}/vielotus.so" "${candidate}/ibus-engine-vielotus" 2>/dev/null; then
            # Prefer top-level DIST_LINUX if its binaries are newer AND match target_arch
            if [ -f "${DIST_LINUX}/vielotus.so" ] && [ "${DIST_LINUX}/vielotus.so" -nt "${candidate}/vielotus.so" ]; then
                if verify_elf_arch "${target_arch}" "${DIST_LINUX}/libVieLotusCAPI.so" "${DIST_LINUX}/vielotus.so" "${DIST_LINUX}/ibus-engine-vielotus" 2>/dev/null; then
                    echo "${DIST_LINUX}"
                    return 0
                fi
            fi
            echo "${candidate}"
            return 0
        fi
    fi
    echo "${DIST_LINUX}"
}

package_single_arch() {
    local target_arch="$1"
    local arch_bin_dir
    arch_bin_dir="$(resolve_arch_bin_dir "${target_arch}")"

    verify_elf_arch "${target_arch}" \
        "${arch_bin_dir}/libVieLotusCAPI.so" \
        "${arch_bin_dir}/vielotus.so" \
        "${arch_bin_dir}/ibus-engine-vielotus"

    local pkg_name="vielotus"
    local pkg_dir="${DEB_BASE}/${pkg_name}_${VERSION}_${target_arch}"
    echo "📦 Đóng gói All-in-One ${pkg_name}_${VERSION}_${target_arch}.deb (từ ${arch_bin_dir#"${ROOT_DIR}/"})..."

    rm -rf "${pkg_dir}"
    mkdir -p "${pkg_dir}/DEBIAN"
    mkdir -p "${pkg_dir}/usr/lib"
    mkdir -p "${pkg_dir}/usr/lib/vielotus"
    mkdir -p "${pkg_dir}/etc/ld.so.conf.d"
    mkdir -p "${pkg_dir}/usr/include"
    mkdir -p "${pkg_dir}/usr/lib/fcitx5"
    mkdir -p "${pkg_dir}/usr/share/fcitx5/addon"
    mkdir -p "${pkg_dir}/usr/share/fcitx5/inputmethod"
    mkdir -p "${pkg_dir}/usr/lib/ibus"
    mkdir -p "${pkg_dir}/usr/share/ibus/component"
    mkdir -p "${pkg_dir}/usr/share/doc/${pkg_name}"

    # 1. Core C-ABI Library & Header
    cp "${arch_bin_dir}/libVieLotusCAPI.so" "${pkg_dir}/usr/lib/"
    cp "${ROOT_DIR}/Sources/VieLotusCAPI/include/vielotus.h" "${pkg_dir}/usr/include/vielotus.h"

    if [ -d "${arch_bin_dir}/swift-runtime" ]; then
        cp -a "${arch_bin_dir}/swift-runtime/"*.so* "${pkg_dir}/usr/lib/vielotus/" 2>/dev/null || true
    elif [ -d "${DIST_LINUX}/swift-runtime" ]; then
        cp -a "${DIST_LINUX}/swift-runtime/"*.so* "${pkg_dir}/usr/lib/vielotus/" 2>/dev/null || true
    fi
    echo "/usr/lib/vielotus" > "${pkg_dir}/etc/ld.so.conf.d/vielotus.conf"

    # 2. Fcitx5 Addon & InputMethod definitions
    cp "${arch_bin_dir}/vielotus.so" "${pkg_dir}/usr/lib/fcitx5/"
    if [ "${target_arch}" = "amd64" ]; then
        mkdir -p "${pkg_dir}/usr/lib/x86_64-linux-gnu/fcitx5"
        ln -sf ../../fcitx5/vielotus.so "${pkg_dir}/usr/lib/x86_64-linux-gnu/fcitx5/vielotus.so"
    elif [ "${target_arch}" = "arm64" ]; then
        mkdir -p "${pkg_dir}/usr/lib/aarch64-linux-gnu/fcitx5"
        ln -sf ../../fcitx5/vielotus.so "${pkg_dir}/usr/lib/aarch64-linux-gnu/fcitx5/vielotus.so"
    fi
    cp "${ROOT_DIR}/CrossPlatform/fcitx5-vielotus/vielotus.conf.in" "${pkg_dir}/usr/share/fcitx5/addon/vielotus.conf"
    cp "${ROOT_DIR}/CrossPlatform/fcitx5-vielotus/vielotus-telex.conf" "${pkg_dir}/usr/share/fcitx5/inputmethod/vielotus-telex.conf"
    cp "${ROOT_DIR}/CrossPlatform/fcitx5-vielotus/vielotus-vni.conf" "${pkg_dir}/usr/share/fcitx5/inputmethod/vielotus-vni.conf"
    cp "${ROOT_DIR}/CrossPlatform/fcitx5-vielotus/README.md" "${pkg_dir}/usr/share/doc/${pkg_name}/"

    # 3. IBus Engine
    cp "${arch_bin_dir}/ibus-engine-vielotus" "${pkg_dir}/usr/lib/ibus/"
    cp "${DIST_LINUX}/vielotus.xml" "${pkg_dir}/usr/share/ibus/component/"

    # 4. Freedesktop hicolor icons (16x16 -> 512x512) & status indicators
    for size in 16x16 24x24 32x32 48x48 64x64 128x128 256x256 512x512; do
        ICON_SRC="${ROOT_DIR}/CrossPlatform/linux-icons/hicolor_${size}_apps/vielotus.png"
        if [ -f "${ICON_SRC}" ]; then
            mkdir -p "${pkg_dir}/usr/share/icons/hicolor/${size}/apps"
            cp "${ICON_SRC}" "${pkg_dir}/usr/share/icons/hicolor/${size}/apps/vielotus.png"
        fi
    done

    if [ -d "${ROOT_DIR}/CrossPlatform/linux-icons/status_indicators" ]; then
        mkdir -p "${pkg_dir}/usr/share/vielotus/icons"
        cp "${ROOT_DIR}/CrossPlatform/linux-icons/status_indicators/"*.png "${pkg_dir}/usr/share/vielotus/icons/"
    fi

    # 5. Desktop resource files (typing-modes.yml only)
    if [ -f "${ROOT_DIR}/Resources/typing-modes.yml" ]; then
        mkdir -p "${pkg_dir}/usr/share/vielotus/VietLotusIM_VieLotusCore.resources"
        cp "${ROOT_DIR}/Resources/typing-modes.yml" "${pkg_dir}/usr/share/vielotus/VietLotusIM_VieLotusCore.resources/"
    elif [ -f "${ROOT_DIR}/Sources/VieLotusCore/Resources/typing-modes.yml" ]; then
        mkdir -p "${pkg_dir}/usr/share/vielotus/VietLotusIM_VieLotusCore.resources"
        cp "${ROOT_DIR}/Sources/VieLotusCore/Resources/typing-modes.yml" "${pkg_dir}/usr/share/vielotus/VietLotusIM_VieLotusCore.resources/"
    fi

    # 6. Desktop Application Launcher, GUI/CLI Settings Utility & AppStream Metadata
    install_desktop_integration "${pkg_dir}"

    # 7. System-wide Fontconfig rule for Vietnamese Latin Extended Additional (U+1EA0..U+1EF9: ệ, ộ, ậ, ử...)
    mkdir -p "${pkg_dir}/etc/fonts/conf.d"
    cat <<'FC_SYS_EOF' > "${pkg_dir}/etc/fonts/conf.d/99-vielotus-vietnamese.conf"
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<fontconfig>
  <selectfont>
    <rejectfont>
      <glob>/usr/share/fonts/truetype/ubuntu/*</glob>
      <glob>/var/lib/snapd/hostfs/usr/share/fonts/truetype/ubuntu/*</glob>
      <glob>/snap/*/usr/share/fonts/truetype/ubuntu/*</glob>
    </rejectfont>
  </selectfont>
  <match target="pattern">
    <test qual="any" name="family">
      <string>Ubuntu</string>
    </test>
    <edit name="family" mode="assign" binding="same">
      <string>DejaVu Sans</string>
    </edit>
  </match>
  <match target="pattern">
    <test qual="any" name="family">
      <string>Ubuntu Sans</string>
    </test>
    <edit name="family" mode="assign" binding="same">
      <string>DejaVu Sans</string>
    </edit>
  </match>
  <match target="pattern">
    <test qual="any" name="family">
      <string>Ubuntu Mono</string>
    </test>
    <edit name="family" mode="assign" binding="same">
      <string>DejaVu Sans Mono</string>
    </edit>
  </match>
  <match target="pattern">
    <test qual="any" name="family">
      <string>Ubuntu Sans Mono</string>
    </test>
    <edit name="family" mode="assign" binding="same">
      <string>DejaVu Sans Mono</string>
    </edit>
  </match>
  <alias>
    <family>sans-serif</family>
    <prefer>
      <family>DejaVu Sans</family>
      <family>Noto Sans</family>
    </prefer>
  </alias>
</fontconfig>
FC_SYS_EOF
    cp -f "${pkg_dir}/etc/fonts/conf.d/99-vielotus-vietnamese.conf" "${pkg_dir}/etc/fonts/conf.d/64-vielotus-vietnamese.conf"

    local installed_size
    installed_size=$(du -sk "${pkg_dir}" | awk '{print $1}')

    cat <<EOF > "${pkg_dir}/DEBIAN/control"
Package: ${pkg_name}
Version: ${VERSION}
Section: utils
Priority: optional
Architecture: ${target_arch}
Installed-Size: ${installed_size}
Maintainer: Trần Phát Đạt (Steve Dat) <https://github.com/stevedat/VieLotus-IM>
Homepage: https://github.com/stevedat/VieLotus-IM
Depends: libc6, libstdc++6, libgcc-s1, libglib2.0-0t64 | libglib2.0-0, libibus-1.0-5, libfcitx5core7, libfcitx5config6, libfcitx5utils2, python3, python3-gi, gir1.2-gtk-3.0, fonts-dejavu-core | fonts-noto-core
Recommends: ibus | fcitx5, im-config, zenity, fonts-noto-core, fonts-dejavu-core, fonts-ubuntu-classic
Suggests: fcitx5, fcitx5-config-qt, fcitx5-frontend-all, ibus, zenity
Provides: fcitx5-vielotus, ibus-vielotus
Enhances: fcitx5, ibus, language-selector-common
Description: VieLotusIM (Sen Viet) - Next-Gen Vietnamese Input Method (IBus & Fcitx5)
 All-in-one installer containing the native C++20 Vietnamese engine core
 (libVieLotusCAPI.so) alongside both native IBus and Fcitx5 input method
 plugins for Ubuntu, Debian, Mint, and Pop!_OS.
EOF

    if command -v md5sum >/dev/null 2>&1; then
        (cd "${pkg_dir}" && find usr etc -type f -exec md5sum {} + > DEBIAN/md5sums)
    fi

    write_maintainer_scripts "${pkg_dir}"

    build_deb "${pkg_dir}" "${DIST_LINUX}/${pkg_name}_${VERSION}_${target_arch}.deb"

    # Also build Debian/Ubuntu split packages (libvielotus0, ibus-vielotus, fcitx5-vielotus)
    local multiarch_dir="x86_64-linux-gnu"
    if [ "${target_arch}" = "arm64" ]; then
        multiarch_dir="aarch64-linux-gnu"
    fi

    # 1) libvielotus0
    local lib_dir="${DEB_BASE}/libvielotus0_${VERSION}_${target_arch}"
    rm -rf "${lib_dir}"
    mkdir -p "${lib_dir}/DEBIAN" "${lib_dir}/usr/lib/${multiarch_dir}" "${lib_dir}/usr/include" "${lib_dir}/usr/share"
    cp "${arch_bin_dir}/libVieLotusCAPI.so" "${lib_dir}/usr/lib/${multiarch_dir}/libVieLotusCAPI.so.0"
    ln -sf "libVieLotusCAPI.so.0" "${lib_dir}/usr/lib/${multiarch_dir}/libVieLotusCAPI.so"
    ln -sf "${multiarch_dir}/libVieLotusCAPI.so.0" "${lib_dir}/usr/lib/libVieLotusCAPI.so"
    cp "${pkg_dir}/usr/include/vielotus.h" "${lib_dir}/usr/include/vielotus.h"
    cp -a "${pkg_dir}/usr/share/icons" "${lib_dir}/usr/share/" 2>/dev/null || true
    cp -a "${pkg_dir}/usr/share/vielotus" "${lib_dir}/usr/share/" 2>/dev/null || true
    local lib_size
    lib_size=$(du -sk "${lib_dir}" | awk '{print $1}')
    cat <<EOF > "${lib_dir}/DEBIAN/control"
Package: libvielotus0
Source: vielotus
Version: ${VERSION}
Section: libs
Priority: optional
Architecture: ${target_arch}
Multi-Arch: same
Installed-Size: ${lib_size}
Maintainer: Trần Phát Đạt (Steve Dat) <https://github.com/stevedat/VieLotus-IM>
Homepage: https://github.com/stevedat/VieLotus-IM
Depends: libc6, libstdc++6, libgcc-s1
Description: VieLotusIM (Sen Viet) Vietnamese Input Method shared C-ABI core
 Shared C-ABI engine library (libVieLotusCAPI.so) implementing the VieLotusIM
 (Sen Viet) Vietnamese syllable state machine, SEN Flex free-tone Telex/VNI
 composition, and Smart Bilingual (English-Vietnamese) collision resolution.
EOF
    build_deb "${lib_dir}" "${DIST_LINUX}/libvielotus0_${VERSION}_${target_arch}.deb"

    # 2) ibus-vielotus
    local ibus_dir="${DEB_BASE}/ibus-vielotus_${VERSION}_${target_arch}"
    rm -rf "${ibus_dir}"
    mkdir -p "${ibus_dir}/DEBIAN" "${ibus_dir}/usr/lib/ibus" "${ibus_dir}/usr/share/ibus/component"
    cp "${arch_bin_dir}/ibus-engine-vielotus" "${ibus_dir}/usr/lib/ibus/"
    cp "${DIST_LINUX}/vielotus.xml" "${ibus_dir}/usr/share/ibus/component/"
    install_desktop_integration "${ibus_dir}"
    local ibus_size
    ibus_size=$(du -sk "${ibus_dir}" | awk '{print $1}')
    cat <<EOF > "${ibus_dir}/DEBIAN/control"
Package: ibus-vielotus
Source: vielotus
Version: ${VERSION}
Section: utils
Priority: optional
Architecture: ${target_arch}
Installed-Size: ${ibus_size}
Maintainer: Trần Phát Đạt (Steve Dat) <https://github.com/stevedat/VieLotus-IM>
Homepage: https://github.com/stevedat/VieLotus-IM
Depends: libvielotus0 (= ${VERSION}), libc6, libglib2.0-0t64 | libglib2.0-0, libibus-1.0-5, ibus (>= 1.5), python3, python3-gi, gir1.2-gtk-3.0
Recommends: im-config, zenity, fonts-dejavu-core | fonts-noto-core
Enhances: ibus, language-selector-common
Description: VieLotusIM (Sen Viet) Vietnamese Input Method plugin for IBus
 Native IBus input method engine (ibus-engine-vielotus) for VieLotusIM
 (Sen Viet), supporting Telex and VNI with free-tone SEN Flex composition
 and Smart Bilingual English-Vietnamese restoration on GNOME and IBus desktops.
EOF
    build_deb "${ibus_dir}" "${DIST_LINUX}/ibus-vielotus_${VERSION}_${target_arch}.deb"

    # 3) fcitx5-vielotus
    local fcitx_dir="${DEB_BASE}/fcitx5-vielotus_${VERSION}_${target_arch}"
    rm -rf "${fcitx_dir}"
    mkdir -p "${fcitx_dir}/DEBIAN" "${fcitx_dir}/usr/lib/fcitx5" "${fcitx_dir}/usr/lib/${multiarch_dir}/fcitx5" "${fcitx_dir}/usr/share/fcitx5/addon" "${fcitx_dir}/usr/share/fcitx5/inputmethod"
    cp "${arch_bin_dir}/vielotus.so" "${fcitx_dir}/usr/lib/fcitx5/"
    ln -sf ../../fcitx5/vielotus.so "${fcitx_dir}/usr/lib/${multiarch_dir}/fcitx5/vielotus.so"
    cp "${ROOT_DIR}/CrossPlatform/fcitx5-vielotus/vielotus.conf.in" "${fcitx_dir}/usr/share/fcitx5/addon/vielotus.conf"
    cp "${ROOT_DIR}/CrossPlatform/fcitx5-vielotus/vielotus-telex.conf" "${fcitx_dir}/usr/share/fcitx5/inputmethod/vielotus-telex.conf"
    cp "${ROOT_DIR}/CrossPlatform/fcitx5-vielotus/vielotus-vni.conf" "${fcitx_dir}/usr/share/fcitx5/inputmethod/vielotus-vni.conf"
    local fcitx_size
    fcitx_size=$(du -sk "${fcitx_dir}" | awk '{print $1}')
    cat <<EOF > "${fcitx_dir}/DEBIAN/control"
Package: fcitx5-vielotus
Source: vielotus
Version: ${VERSION}
Section: utils
Priority: optional
Architecture: ${target_arch}
Installed-Size: ${fcitx_size}
Maintainer: Trần Phát Đạt (Steve Dat) <https://github.com/stevedat/VieLotus-IM>
Homepage: https://github.com/stevedat/VieLotus-IM
Depends: libvielotus0 (= ${VERSION}), libc6, libstdc++6, libgcc-s1, libfcitx5core7, libfcitx5config6, libfcitx5utils2, fcitx5
Recommends: fcitx5-config-qt, fonts-dejavu-core | fonts-noto-core
Enhances: fcitx5, language-selector-common
Description: VieLotusIM (Sen Viet) Vietnamese Input Method plugin for Fcitx5
 Native Fcitx5 input method addon (vielotus.so) for VieLotusIM (Sen Viet),
 supporting Telex and VNI with free-tone SEN Flex composition and Smart
 Bilingual English-Vietnamese restoration on KDE Plasma and Fcitx5 desktops.
EOF
    build_deb "${fcitx_dir}" "${DIST_LINUX}/fcitx5-vielotus_${VERSION}_${target_arch}.deb"
}

package_single_arch "${ARCH}"

if [ "${ARCH}" = "amd64" ] && [ -d "${DIST_LINUX}/arm64" ] && [ -f "${DIST_LINUX}/arm64/vielotus.so" ]; then
    package_single_arch "arm64"
fi

rm -rf "${DEB_BASE}"

# Generate Official APT Repository Metadata (Packages, Packages.gz, Release) & Arch PKGBUILD SHA256
python3 - "${DIST_LINUX}" "${VERSION}" "${ROOT_DIR}" <<'PYEOF'
import datetime, gzip, hashlib, os, re, sys, tarfile

dist_dir, version, root_dir = sys.argv[1], sys.argv[2], sys.argv[3]
deb_files = sorted(
    f for f in os.listdir(dist_dir)
    if f.endswith(".deb") and f"_{version}_" in f
)

def extract_control_from_deb(deb_path):
    with open(deb_path, "rb") as f:
        if f.read(8) != b"!<arch>\n":
            raise RuntimeError(f"Invalid deb: {deb_path}")
        while True:
            hdr = f.read(60)
            if len(hdr) < 60:
                break
            name = hdr[:16].decode("ascii", errors="ignore").strip().rstrip("/")
            size = int(hdr[48:58].decode("ascii").strip())
            data = f.read(size)
            if size % 2 == 1:
                f.read(1)
            if name.startswith("control.tar"):
                import io
                with tarfile.open(fileobj=io.BytesIO(data), mode="r:*") as tf:
                    for member in tf.getmembers():
                        if member.name.endswith("/control") or member.name == "control":
                            return tf.extractfile(member).read().decode("utf-8").strip()
    raise RuntimeError(f"No control found in {deb_path}")

stanzas = []
arch_sha256 = {}

for fname in deb_files:
    fpath = os.path.join(dist_dir, fname)
    with open(fpath, "rb") as f:
        blob = f.read()
    size = len(blob)
    md5 = hashlib.md5(blob).hexdigest()
    sha1 = hashlib.sha1(blob).hexdigest()
    sha256 = hashlib.sha256(blob).hexdigest()
    if fname == f"vielotus_{version}_amd64.deb":
        arch_sha256["amd64"] = sha256
    elif fname == f"vielotus_{version}_arm64.deb":
        arch_sha256["arm64"] = sha256
    ctrl = extract_control_from_deb(fpath)
    stanza = (
        f"{ctrl}\n"
        f"Filename: ./{fname}\n"
        f"Size: {size}\n"
        f"MD5sum: {md5}\n"
        f"SHA1: {sha1}\n"
        f"SHA256: {sha256}\n"
    )
    stanzas.append(stanza)

packages_content = "\n".join(stanzas).encode("utf-8")
packages_gz_content = gzip.compress(packages_content, compresslevel=9, mtime=0)

now_rfc2822 = datetime.datetime.now(datetime.timezone.utc).strftime("%a, %d %b %Y %H:%M:%S UTC")

def hashes_line(data, name):
    return (
        hashlib.md5(data).hexdigest(),
        hashlib.sha256(data).hexdigest(),
        len(data),
        name,
    )

p_md5, p_sha256, p_len, _ = hashes_line(packages_content, "Packages")
gz_md5, gz_sha256, gz_len, _ = hashes_line(packages_gz_content, "Packages.gz")

release_content = (
    "Origin: VieLotusIM (Sen Viet)\n"
    "Label: VieLotusIM Official APT Repository\n"
    "Suite: stable\n"
    "Codename: stable\n"
    f"Version: {version}\n"
    "Architectures: amd64 arm64\n"
    "Components: main\n"
    "Description: Official APT Repository for VieLotusIM (Sen Viet) Next-Gen Vietnamese Input Method\n"
    f"Date: {now_rfc2822}\n"
    "MD5Sum:\n"
    f" {p_md5} {p_len:16d} Packages\n"
    f" {gz_md5} {gz_len:16d} Packages.gz\n"
    "SHA256:\n"
    f" {p_sha256} {p_len:16d} Packages\n"
    f" {gz_sha256} {gz_len:16d} Packages.gz\n"
).encode("utf-8")

for target_dir in (dist_dir, os.path.join(root_dir, "docs", "apt")):
    os.makedirs(target_dir, exist_ok=True)
    with open(os.path.join(target_dir, "Packages"), "wb") as f:
        f.write(packages_content)
    with open(os.path.join(target_dir, "Packages.gz"), "wb") as f:
        f.write(packages_gz_content)
    with open(os.path.join(target_dir, "Release"), "wb") as f:
        f.write(release_content)

pkgbuild_path = os.path.join(root_dir, "CrossPlatform", "packaging", "arch", "PKGBUILD")
if os.path.isfile(pkgbuild_path) and "amd64" in arch_sha256 and "arm64" in arch_sha256:
    with open(pkgbuild_path, "r", encoding="utf-8") as f:
        pb = f.read()
    pb = re.sub(r"sha256sums_x86_64=\([^)]*\)", f"sha256sums_x86_64=('{arch_sha256['amd64']}')", pb)
    pb = re.sub(r"sha256sums_aarch64=\([^)]*\)", f"sha256sums_aarch64=('{arch_sha256['arm64']}')", pb)
    with open(pkgbuild_path, "w", encoding="utf-8") as f:
        f.write(pb)
PYEOF

echo "======================================================="
echo "🎉 Gói All-in-One Debian/Ubuntu (.deb) & APT Repo đã sẵn sàng tại:"
ls -lh "${DIST_LINUX}/vielotus_${VERSION}"_*.deb "${DIST_LINUX}/Packages"* "${DIST_LINUX}/Release"
echo "======================================================="
