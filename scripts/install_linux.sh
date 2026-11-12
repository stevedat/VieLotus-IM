#!/bin/sh
# ==============================================================================
# Sen Việt (VieLotusIM) v2.0.2 — Universal Linux (Multi-Distro & Multi-Arch)
# & macOS One-Line Installer / Uninstaller
#
# Supported Linux Distros:
#   • Ubuntu, Debian, Raspberry Pi OS, Mint, Pop!_OS, Zorin, Kali (apt / dpkg)
#   • Arch Linux, Arch ARM, Arch RISC-V, Manjaro, EndeavourOS, CachyOS (pacman)
#   • Fedora, RHEL, CentOS Stream, Rocky, AlmaLinux (dnf)
#   • openSUSE Tumbleweed / Leap (zypper)
#   • Alpine Linux / postmarketOS (apk) & Void Linux (xbps)
# Supported Architectures:
#   • Prebuilt fast-path + Native source : x86_64 / amd64, aarch64 / arm64
#   • Automatic Native C++20 source build: armv7l / armhf (Raspberry Pi 32-bit),
#     riscv64 (RISC-V), i686 / i386 (x86 32-bit), ppc64le, s390x, loongarch64
#
# Usage:
#   Install   : curl -fsSL https://stevedat.github.io/VieLotus-IM/install.sh | sh
#   From Src  : curl -fsSL https://stevedat.github.io/VieLotus-IM/install.sh | VIELOTUS_BUILD_FROM_SOURCE=1 sh
#   Uninstall : curl -fsSL https://stevedat.github.io/VieLotus-IM/install.sh | sh -s -- --uninstall
# ==============================================================================
set -e

compute_sha256() {
    target_file="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "${target_file}" | awk '{print tolower($1)}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "${target_file}" | awk '{print tolower($1)}'
    elif command -v openssl >/dev/null 2>&1; then
        openssl dgst -sha256 "${target_file}" | awk '{print tolower($NF)}'
    else
        echo ""
    fi
}

verify_artifact_sha256() {
    artifact_path="$1"
    artifact_name="$2"
    checksums_file="$3"
    strict_mode="$4"

    if [ ! -f "${checksums_file}" ]; then
        if [ "${strict_mode}" = "1" ]; then
            echo "❌ Không tìm thấy tệp kiểm tra toàn vẹn SHA-256 (${checksums_file}). Huỷ cài đặt."
            rm -f "${artifact_path}"
            exit 1
        fi
        echo "⚠️  Không tải được checksums.sha256 để đối chiếu; tiếp tục cài đặt..."
        return 0
    fi

    expected_hash="$(awk -v fname="${artifact_name}" '
        NF >= 2 {
            h = tolower($1)
            p = $2
            sub(/^\*/, "", p)
            n = split(p, parts, "/")
            base = parts[n]
            if (base == fname && h ~ /^[0-9a-f]{64}$/) {
                print h
                exit
            }
        }
    ' "${checksums_file}")"

    if [ -z "${expected_hash}" ]; then
        if [ "${strict_mode}" = "1" ]; then
            echo "❌ Không tìm thấy mã băm SHA-256 cho ${artifact_name} trong checksums.sha256. Huỷ cài đặt."
            rm -f "${artifact_path}"
            exit 1
        fi
        echo "⚠️  checksums.sha256 không chứa mục ${artifact_name}; bỏ qua bước đối chiếu."
        return 0
    fi

    actual_hash="$(compute_sha256 "${artifact_path}")"
    if [ -z "${actual_hash}" ]; then
        if [ "${strict_mode}" = "1" ]; then
            echo "❌ Thiếu công cụ tính SHA-256 (sha256sum / shasum / openssl). Huỷ cài đặt."
            rm -f "${artifact_path}"
            exit 1
        fi
        return 0
    fi

    if [ "${actual_hash}" != "${expected_hash}" ]; then
        echo "❌ LỖI BẢO MẬT: Mã SHA-256 của ${artifact_name} KHÔNG KHỚP!"
        echo "   • Kỳ vọng : ${expected_hash}"
        echo "   • Thực tế : ${actual_hash}"
        rm -f "${artifact_path}"
        exit 1
    fi

    echo "🔒 Đã xác thực SHA-256 hợp lệ cho ${artifact_name} (${actual_hash})."
}

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

uninstall_vielotus() {
    OS_NAME="$(uname -s)"
    if [ "${OS_NAME}" = "Darwin" ]; then
        echo "🧹 === Đang gỡ cài đặt Sen Việt (VieLotusIM) trên macOS ==="
        ${SUDO} pkill -9 -x "VieLotusIM" >/dev/null 2>&1 || true
        ${SUDO} rm -rf "/Library/Input Methods/VieLotusIM.app"
        echo "✅ Đã gỡ cài đặt Sen Việt trên macOS."
        exit 0
    fi

    echo "🧹 === Đang gỡ cài đặt Sen Việt (VieLotusIM) trên Linux ==="
    if command -v pkill >/dev/null 2>&1; then
        ${SUDO} pkill -9 -f "[i]bus-engine-vielotus" >/dev/null 2>&1 || true
    fi

    if command -v apt-get >/dev/null 2>&1 && command -v dpkg >/dev/null 2>&1; then
        if dpkg -s vielotus >/dev/null 2>&1 || dpkg -s ibus-vielotus >/dev/null 2>&1 || dpkg -s fcitx5-vielotus >/dev/null 2>&1 || dpkg -s libvielotus0 >/dev/null 2>&1; then
            ${SUDO} env DEBIAN_FRONTEND=noninteractive apt-get remove --purge -y vielotus ibus-vielotus fcitx5-vielotus libvielotus0 >/dev/null 2>&1 || \
                ${SUDO} dpkg -r vielotus ibus-vielotus fcitx5-vielotus libvielotus0 >/dev/null 2>&1 || true
        fi
    fi
    if command -v pacman >/dev/null 2>&1; then
        for pkg in vielotus vielotus-bin fcitx5-vielotus ibus-vielotus; do
            if pacman -Qi "${pkg}" >/dev/null 2>&1; then
                ${SUDO} pacman -Rns --noconfirm "${pkg}" >/dev/null 2>&1 || true
            fi
        done
    fi
    if command -v dnf >/dev/null 2>&1; then
        if rpm -q vielotus >/dev/null 2>&1 || rpm -q ibus-vielotus >/dev/null 2>&1 || rpm -q fcitx5-vielotus >/dev/null 2>&1 || rpm -q libvielotus0 >/dev/null 2>&1; then
            ${SUDO} dnf remove -y vielotus ibus-vielotus fcitx5-vielotus libvielotus0 >/dev/null 2>&1 || true
        fi
    fi
    if command -v zypper >/dev/null 2>&1; then
        if rpm -q vielotus >/dev/null 2>&1 || rpm -q ibus-vielotus >/dev/null 2>&1 || rpm -q fcitx5-vielotus >/dev/null 2>&1 || rpm -q libvielotus0 >/dev/null 2>&1; then
            ${SUDO} zypper --non-interactive remove vielotus ibus-vielotus fcitx5-vielotus libvielotus0 >/dev/null 2>&1 || true
        fi
    fi

    MANIFEST_FILE="/usr/share/vielotus/install.manifest"
    if [ -f "${MANIFEST_FILE}" ]; then
        while IFS= read -r installed_path || [ -n "${installed_path}" ]; do
            case "${installed_path}" in
                ''|\#*) continue ;;
                /usr/*|/etc/ld.so.conf.d/vielotus.conf|/etc/fonts/conf.d/*vielotus*|/etc/xdg/autostart/vielotus*)
                    if [ -f "${installed_path}" ] || [ -L "${installed_path}" ]; then
                        ${SUDO} rm -f "${installed_path}" 2>/dev/null || true
                    fi
                    ;;
            esac
        done < "${MANIFEST_FILE}"
        ${SUDO} rm -f "${MANIFEST_FILE}" 2>/dev/null || true
    fi

    # Clean known standalone binary/config paths if any remain
    for p in \
        /etc/ld.so.conf.d/vielotus.conf \
        /etc/fonts/conf.d/99-vielotus-vietnamese.conf \
        /etc/fonts/conf.d/64-vielotus-vietnamese.conf \
        /etc/fonts/conf.d/51-vielotus-vietnamese.conf \
        /etc/xdg/autostart/vielotus-onboard.desktop \
        /usr/bin/vielotus \
        /usr/bin/vielotus-settings \
        /usr/include/vielotus.h \
        /usr/lib/libVieLotusCAPI.so \
        /usr/lib/libVieLotusCAPI.so.0 \
        /usr/lib/libVieLotusCAPI.so.0.2.2 \
        /usr/lib64/libVieLotusCAPI.so \
        /usr/lib64/libVieLotusCAPI.so.0 \
        /usr/lib64/libVieLotusCAPI.so.0.2.2 \
        /usr/lib/fcitx5/vielotus.so \
        /usr/lib64/fcitx5/vielotus.so \
        /usr/lib/ibus/ibus-engine-vielotus \
        /usr/libexec/ibus-engine-vielotus \
        /usr/share/ibus/component/vielotus.xml \
        /usr/share/fcitx5/addon/vielotus.conf \
        /usr/share/fcitx5/inputmethod/vielotus-telex.conf \
        /usr/share/fcitx5/inputmethod/vielotus-vni.conf \
        /usr/share/applications/vielotus.desktop \
        /usr/share/applications/ibus-setup-vielotus.desktop \
        /usr/share/applications/ibus-setup-vielotus-vni.desktop \
        /usr/share/metainfo/org.vielotus.VieLotus.metainfo.xml \
        /usr/share/man/man1/vielotus-settings.1 \
        /usr/share/man/man1/vielotus-settings.1.gz
    do
        ${SUDO} rm -f "${p}" 2>/dev/null || true
    done
    for multi_p in \
        /usr/lib/*-linux-*/libVieLotusCAPI.so \
        /usr/lib/*-linux-*/libVieLotusCAPI.so.0 \
        /usr/lib/*-linux-*/libVieLotusCAPI.so.0.* \
        /usr/lib/*-linux-*/fcitx5/vielotus.so
    do
        if [ -e "${multi_p}" ] || [ -L "${multi_p}" ]; then
            ${SUDO} rm -f "${multi_p}" 2>/dev/null || true
        fi
    done
    ${SUDO} rm -rf /usr/lib/vielotus /usr/share/vielotus /usr/share/doc/vielotus 2>/dev/null || true
    rm -f "${HOME}/.config/fontconfig/conf.d/99-vielotus-vietnamese.conf" \
          "${HOME}/.config/fontconfig/conf.d/51-vielotus-vietnamese.conf" \
          "${HOME}/.config/environment.d/fcitx5-vielotus.conf" 2>/dev/null || true
    ${SUDO} rm -f /home/*/.config/fontconfig/conf.d/99-vielotus-vietnamese.conf \
                  /home/*/.config/fontconfig/conf.d/51-vielotus-vietnamese.conf \
                  /home/*/.config/environment.d/fcitx5-vielotus.conf 2>/dev/null || true
    for sz in 16x16 24x24 32x32 48x48 64x64 128x128 256x256 512x512; do
        ${SUDO} rm -f "/usr/share/icons/hicolor/${sz}/apps/vielotus.png" 2>/dev/null || true
    done

    if command -v gsettings >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
        python3 - <<'CLEAN_GNOME_PY' 2>/dev/null || true
import ast, subprocess
for key in ("sources", "mru-sources"):
    try:
        raw = subprocess.check_output(["gsettings", "get", "org.gnome.desktop.input-sources", key], stderr=subprocess.DEVNULL).decode().strip()
        if raw.startswith("@a(ss) "):
            raw = raw[len("@a(ss) "):]
        lst = list(ast.literal_eval(raw)) if raw else []
        filtered = [s for s in lst if not (s[0] == "ibus" and s[1] in ("vielotus", "vielotus-vni"))]
        if filtered != lst:
            val = "[" + ", ".join(f"('{k}', '{v}')" for k, v in filtered) + "]"
            subprocess.call(["gsettings", "set", "org.gnome.desktop.input-sources", key, val], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception:
        pass
CLEAN_GNOME_PY
    fi

    finalize_linux_integration
    if command -v fcitx5 >/dev/null 2>&1 && pgrep -x fcitx5 >/dev/null 2>&1; then
        fcitx5 -r -d >/dev/null 2>&1 || true
    fi

    echo "✅ Đã gỡ cài đặt Sen Việt hoàn tất (giữ nguyên cấu hình cá nhân tại ~/.config/vielotus nếu có)."
    exit 0
}

verify_installed_elf_links() {
    if ! command -v ldd >/dev/null 2>&1; then
        return 0
    fi
    if command -v ldconfig >/dev/null 2>&1; then
        ${SUDO} ldconfig >/dev/null 2>&1 || true
    fi

    # Check Fcitx5 plugin ABI compatibility on non-Debian distros (soname guard)
    for fcitx_plugin in /usr/lib64/fcitx5/vielotus.so /usr/lib/fcitx5/vielotus.so /usr/lib/*-linux-*/fcitx5/vielotus.so; do
        if [ -e "${fcitx_plugin}" ]; then
            LDD_OUT="$(LC_ALL=C ldd -r "${fcitx_plugin}" 2>&1 || true)"
            if printf '%s\n' "${LDD_OUT}" | grep -E -q 'not found|undefined symbol:'; then
                echo "⚠️  Phát hiện khác biệt ABI Fcitx5 trên bản phân phối hiện tại đối với ${fcitx_plugin}."
                echo "   → Tạm gỡ plugin Fcitx5 nhị phân để bảo vệ tiến trình fcitx5 (IBus vẫn hoạt động bình thường)."
                echo "   → Mẹo: chạy lại với VIELOTUS_BUILD_FROM_SOURCE=1 để biên dịch C++20 trực tiếp theo ABI máy bạn."
                ${SUDO} rm -f /usr/lib64/fcitx5/vielotus.so /usr/lib/fcitx5/vielotus.so /usr/lib/*-linux-*/fcitx5/vielotus.so 2>/dev/null || true
                break
            fi
        fi
    done

    for core_bin in /usr/lib/ibus/ibus-engine-vielotus /usr/libexec/ibus-engine-vielotus /usr/lib/libVieLotusCAPI.so /usr/lib64/libVieLotusCAPI.so /usr/lib/*-linux-*/libVieLotusCAPI.so; do
        if [ -e "${core_bin}" ]; then
            LDD_CORE="$(LC_ALL=C ldd -r "${core_bin}" 2>&1 || true)"
            if printf '%s\n' "${LDD_CORE}" | grep -E -q 'not found|undefined symbol:'; then
                echo "⚠️  Cảnh báo liên kết động tại ${core_bin}:"
                printf '%s\n' "${LDD_CORE}" | grep -E 'not found|undefined symbol:' | head -n 4 || true
            fi
        fi
    done
}

install_staging_rootfs_with_manifest() {
    staging_root="$1"
    manifest_tmp="${staging_root}.manifest"
    : > "${manifest_tmp}"

    (
        cd "${staging_root}"
        find . \( -type f -o -type l \) | sed 's|^\./|/|' | sort
    ) >> "${manifest_tmp}"

    if [ -d "${staging_root}/usr" ]; then
        ${SUDO} cp -a "${staging_root}/usr" /
    fi
    if [ -d "${staging_root}/etc" ]; then
        ${SUDO} cp -a "${staging_root}/etc" /
    fi

    if [ -d /usr/lib64 ]; then
        if [ -e /usr/lib/libVieLotusCAPI.so ] && [ ! -e /usr/lib64/libVieLotusCAPI.so ]; then
            ${SUDO} ln -sf /usr/lib/libVieLotusCAPI.so /usr/lib64/libVieLotusCAPI.so
            echo "/usr/lib64/libVieLotusCAPI.so" >> "${manifest_tmp}"
        fi
        if [ -e /usr/lib/fcitx5/vielotus.so ] && [ ! -e /usr/lib64/fcitx5/vielotus.so ]; then
            ${SUDO} mkdir -p /usr/lib64/fcitx5
            ${SUDO} ln -sf /usr/lib/fcitx5/vielotus.so /usr/lib64/fcitx5/vielotus.so
            echo "/usr/lib64/fcitx5/vielotus.so" >> "${manifest_tmp}"
        fi
    fi
    if [ -d /usr/libexec ] && [ -e /usr/lib/ibus/ibus-engine-vielotus ] && [ ! -e /usr/libexec/ibus-engine-vielotus ]; then
        ${SUDO} ln -sf /usr/lib/ibus/ibus-engine-vielotus /usr/libexec/ibus-engine-vielotus
        echo "/usr/libexec/ibus-engine-vielotus" >> "${manifest_tmp}"
    fi

    ${SUDO} mkdir -p /usr/share/vielotus
    ${SUDO} cp "${manifest_tmp}" /usr/share/vielotus/install.manifest
    ${SUDO} chmod 0644 /usr/share/vielotus/install.manifest
    rm -f "${manifest_tmp}"
}

try_native_cmake_build() {
    src_ver="$1"
    if ! command -v cmake >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1; then
        return 1
    fi
    if ! command -v g++ >/dev/null 2>&1 && ! command -v c++ >/dev/null 2>&1 && ! command -v clang++ >/dev/null 2>&1; then
        return 1
    fi
    HAS_IBUS_DEV=0
    HAS_FCITX5_DEV=0
    if command -v pkg-config >/dev/null 2>&1 && pkg-config --exists ibus-1.0 glib-2.0 2>/dev/null; then
        HAS_IBUS_DEV=1
    fi
    if [ -d /usr/lib64/cmake/Fcitx5Core ] || [ -d /usr/lib/cmake/Fcitx5Core ] || [ -d /usr/share/cmake/Fcitx5Core ]; then
        HAS_FCITX5_DEV=1
    elif command -v pkg-config >/dev/null 2>&1 && pkg-config --exists Fcitx5Core 2>/dev/null; then
        HAS_FCITX5_DEV=1
    else
        for _fcm in /usr/lib/*-linux-*/cmake/Fcitx5Core; do
            if [ -d "${_fcm}" ]; then
                HAS_FCITX5_DEV=1
                break
            fi
        done
    fi
    if [ "${HAS_IBUS_DEV}" = "0" ] && [ "${HAS_FCITX5_DEV}" = "0" ]; then
        return 1
    fi

    build_ws="/tmp/vielotus-srcbuild-$$"
    rm -rf "${build_ws}"
    mkdir -p "${build_ws}"

    SRC_ROOT=""
    if [ -n "${VIELOTUS_SOURCE_DIR:-}" ] && [ -d "${VIELOTUS_SOURCE_DIR}/CrossPlatform/capi-native" ]; then
        SRC_ROOT="${VIELOTUS_SOURCE_DIR}"
    else
        PRIMARY_TAR_URL="https://github.com/stevedat/VieLotus-IM/archive/refs/heads/main.tar.gz"
        FALLBACK_TAR_URL="https://github.com/stevedat/VieLotus-IM/archive/refs/tags/v${src_ver}.tar.gz"
        if [ "${VIELOTUS_VERSION_PINNED:-0}" = "1" ]; then
            PRIMARY_TAR_URL="https://github.com/stevedat/VieLotus-IM/archive/refs/tags/v${src_ver}.tar.gz"
            FALLBACK_TAR_URL="https://github.com/stevedat/VieLotus-IM/archive/refs/heads/main.tar.gz"
        fi
        if ! download_file "${PRIMARY_TAR_URL}" "${build_ws}/src.tar.gz" 2>/dev/null && \
           ! download_file "${FALLBACK_TAR_URL}" "${build_ws}/src.tar.gz" 2>/dev/null; then
            rm -rf "${build_ws}"
            return 1
        fi
        tar -xzf "${build_ws}/src.tar.gz" -C "${build_ws}" 2>/dev/null || {
            rm -rf "${build_ws}"
            return 1
        }
        for d in "${build_ws}"/VieLotus-IM-*; do
            if [ -d "${d}/CrossPlatform/capi-native" ]; then
                SRC_ROOT="${d}"
                break
            fi
        done
    fi

    if [ -z "${SRC_ROOT}" ]; then
        rm -rf "${build_ws}"
        return 1
    fi

    echo "🛠️  Đang biên dịch C++20 bản địa (Native ABI cho $(uname -m)) trực tiếp từ mã nguồn MIT..."
    LIBDIR_REL="lib"
    if command -v dpkg-architecture >/dev/null 2>&1; then
        MULTIARCH_TRIPLET="$(dpkg-architecture -qDEB_HOST_MULTIARCH 2>/dev/null || true)"
        if [ -n "${MULTIARCH_TRIPLET}" ] && [ -d "/usr/lib/${MULTIARCH_TRIPLET}" ]; then
            LIBDIR_REL="lib/${MULTIARCH_TRIPLET}"
        fi
    elif [ -d /usr/lib64 ] && [ ! -L /usr/lib64 ]; then
        case "$(uname -m)" in
            x86_64|amd64|aarch64|arm64|riscv64|ppc64*|s390x|loongarch64|mips64*)
                LIBDIR_REL="lib64"
                ;;
        esac
    fi
    STAGE_DIR="${build_ws}/rootfs"
    mkdir -p "${STAGE_DIR}/etc/ld.so.conf.d"
    printf '/usr/%s\n' "${LIBDIR_REL}" > "${STAGE_DIR}/etc/ld.so.conf.d/vielotus.conf"

    if ! (
        cmake -S "${SRC_ROOT}/CrossPlatform/capi-native" -B "${build_ws}/build-core" \
            -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_INSTALL_PREFIX=/usr \
            -DCMAKE_INSTALL_LIBDIR="${LIBDIR_REL}" >/dev/null &&
        cmake --build "${build_ws}/build-core" --parallel >/dev/null &&
        DESTDIR="${STAGE_DIR}" cmake --install "${build_ws}/build-core" >/dev/null
    ); then
        rm -rf "${build_ws}"
        return 1
    fi

    CORE_SO_BUILT="$(find "${build_ws}/build-core" -name 'libVieLotusCAPI.so*' | head -n 1)"

    if [ "${HAS_FCITX5_DEV}" = "1" ] && [ -n "${CORE_SO_BUILT}" ]; then
        (
            cmake -S "${SRC_ROOT}/CrossPlatform/fcitx5-vielotus" -B "${build_ws}/build-fcitx5" \
                -DCMAKE_BUILD_TYPE=Release \
                -DCMAKE_INSTALL_PREFIX=/usr \
                -DCMAKE_INSTALL_LIBDIR="${LIBDIR_REL}" \
                -DCMAKE_SKIP_RPATH=ON \
                -DVIELOTUS_LIB_PATH="${CORE_SO_BUILT}" >/dev/null &&
            cmake --build "${build_ws}/build-fcitx5" --parallel >/dev/null &&
            DESTDIR="${STAGE_DIR}" cmake --install "${build_ws}/build-fcitx5" >/dev/null
        ) || echo "⚠️  Bỏ qua biên dịch Fcitx5 addon (thiếu gói header phụ trợ)."
    fi

    if [ "${HAS_IBUS_DEV}" = "1" ] && [ -n "${CORE_SO_BUILT}" ]; then
        IBUS_LIBEXEC="/usr/lib/ibus"
        if [ -d /usr/libexec ] && [ ! -d /usr/lib/ibus ]; then
            IBUS_LIBEXEC="/usr/libexec"
        fi
        (
            cmake -S "${SRC_ROOT}/CrossPlatform/ibus-vielotus" -B "${build_ws}/build-ibus" \
                -DCMAKE_BUILD_TYPE=Release \
                -DCMAKE_INSTALL_PREFIX=/usr \
                -DCMAKE_INSTALL_LIBDIR="${LIBDIR_REL}" \
                -DCMAKE_INSTALL_LIBEXECDIR="${IBUS_LIBEXEC#/usr/}" \
                -DLIBEXECDIR="${IBUS_LIBEXEC}" \
                -DCMAKE_SKIP_RPATH=ON \
                -DVIELOTUS_LIB_PATH="${CORE_SO_BUILT}" >/dev/null &&
            cmake --build "${build_ws}/build-ibus" --parallel >/dev/null &&
            DESTDIR="${STAGE_DIR}" cmake --install "${build_ws}/build-ibus" >/dev/null
        ) || echo "⚠️  Bỏ qua biên dịch IBus engine (thiếu gói header phụ trợ)."
    fi

    mkdir -p "${STAGE_DIR}/usr/bin" \
             "${STAGE_DIR}/usr/share/applications" \
             "${STAGE_DIR}/usr/share/metainfo" \
             "${STAGE_DIR}/usr/share/man/man1" \
             "${STAGE_DIR}/usr/share/vielotus/VietLotusIM_VieLotusCore.resources" \
             "${STAGE_DIR}/etc/fonts/conf.d" \
             "${STAGE_DIR}/etc/xdg/autostart"

    cp "${SRC_ROOT}/CrossPlatform/packaging/linux/vielotus-settings" "${STAGE_DIR}/usr/bin/vielotus-settings"
    chmod 0755 "${STAGE_DIR}/usr/bin/vielotus-settings"
    ln -sf vielotus-settings "${STAGE_DIR}/usr/bin/vielotus"
    cp "${SRC_ROOT}/CrossPlatform/packaging/linux/vielotus.desktop" "${STAGE_DIR}/usr/share/applications/vielotus.desktop"
    if [ -f "${SRC_ROOT}/CrossPlatform/packaging/linux/vielotus-onboard.desktop" ]; then
        cp "${SRC_ROOT}/CrossPlatform/packaging/linux/vielotus-onboard.desktop" "${STAGE_DIR}/etc/xdg/autostart/vielotus-onboard.desktop"
    fi
    if [ -f "${SRC_ROOT}/CrossPlatform/packaging/linux/51-vielotus-vietnamese.conf" ]; then
        cp "${SRC_ROOT}/CrossPlatform/packaging/linux/51-vielotus-vietnamese.conf" "${STAGE_DIR}/etc/fonts/conf.d/51-vielotus-vietnamese.conf"
    fi
    cp "${SRC_ROOT}/CrossPlatform/packaging/linux/org.vielotus.VieLotus.metainfo.xml" "${STAGE_DIR}/usr/share/metainfo/org.vielotus.VieLotus.metainfo.xml"
    if [ -f "${SRC_ROOT}/CrossPlatform/packaging/linux/vielotus-settings.1" ]; then
        cp "${SRC_ROOT}/CrossPlatform/packaging/linux/vielotus-settings.1" "${STAGE_DIR}/usr/share/man/man1/vielotus-settings.1"
    fi
    for tm_candidate in "${SRC_ROOT}/Resources/typing-modes.yml" "${SRC_ROOT}/Sources/VieLotusCore/Resources/typing-modes.yml"; do
        if [ -f "${tm_candidate}" ]; then
            cp "${tm_candidate}" "${STAGE_DIR}/usr/share/vielotus/typing-modes.yml"
            cp "${tm_candidate}" "${STAGE_DIR}/usr/share/vielotus/VietLotusIM_VieLotusCore.resources/typing-modes.yml"
            break
        fi
    done
    for sz in 16x16 24x24 32x32 48x48 64x64 128x128 256x256 512x512; do
        if [ -f "${SRC_ROOT}/CrossPlatform/linux-icons/hicolor_${sz}_apps/vielotus.png" ]; then
            mkdir -p "${STAGE_DIR}/usr/share/icons/hicolor/${sz}/apps"
            cp "${SRC_ROOT}/CrossPlatform/linux-icons/hicolor_${sz}_apps/vielotus.png" \
               "${STAGE_DIR}/usr/share/icons/hicolor/${sz}/apps/vielotus.png"
        fi
    done

    install_staging_rootfs_with_manifest "${STAGE_DIR}"
    rm -rf "${build_ws}"
    echo "✅ Đã biên dịch & cài đặt bản địa C++20 thành công!"
    return 0
}

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

    install_staging_rootfs_with_manifest "${work_dir}/rootfs"
    rm -rf "${work_dir}"
    verify_installed_elf_links
}

main() {
ACTION_MODE="install"
for arg in "$@"; do
    case "${arg}" in
        --uninstall|uninstall|--remove)
            ACTION_MODE="uninstall"
            ;;
        --build-from-source)
            VIELOTUS_BUILD_FROM_SOURCE="1"
            ;;
        -h|--help)
            echo "Cách dùng: install.sh [--uninstall] [--build-from-source]"
            exit 0
            ;;
    esac
done
if [ "${VIELOTUS_UNINSTALL:-0}" = "1" ]; then
    ACTION_MODE="uninstall"
fi

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
        if ! ${SUDO} -n true >/dev/null 2>&1 && [ -c /dev/tty ]; then
            echo "🔐 Cần quyền quản trị (sudo) để cài đặt bộ gõ Sen Việt vào hệ thống..."
            ${SUDO} -v </dev/tty || exit 1
        fi
    else
        echo "❌ Vui lòng chạy lệnh với quyền root hoặc cài đặt sudo."
        exit 1
    fi
fi

if [ "${ACTION_MODE}" = "uninstall" ]; then
    uninstall_vielotus
fi

VIELOTUS_VERSION_PINNED="0"
if [ -n "${VIELOTUS_VERSION:-}" ]; then
    VERSION="${VIELOTUS_VERSION#v}"
    VIELOTUS_VERSION_PINNED="1"
else
    LATEST_TAG=""
    if command -v curl >/dev/null 2>&1 && [ -z "${VIELOTUS_DEB_PATH:-}" ]; then
        LATEST_TAG="$(curl -fsSL --max-time 4 https://api.github.com/repos/stevedat/VieLotus-IM/releases/latest 2>/dev/null | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"v\{0,1\}\([^"]*\)".*/\1/p' | head -n 1 || true)"
    fi
    VERSION="${LATEST_TAG:-2.0.2}"
fi
OS_NAME="$(uname -s)"
ARCH_RAW="$(uname -m)"

# ------------------------------------------------------------------------------
# macOS Support (if invoked on Darwin)
# ------------------------------------------------------------------------------
if [ "${OS_NAME}" = "Darwin" ]; then
    echo "🌸 === Cài đặt Sen Việt (VieLotusIM v${VERSION}) cho macOS ==="
    TMP_PKG="/tmp/VieLotusIM.pkg"
    TMP_SUMS="/tmp/vielotus-checksums-$$.sha256"
    echo "⬇️  Đang tải gói cài đặt VieLotusIM.pkg..."
    curl -fL --progress-bar "https://github.com/stevedat/VieLotus-IM/releases/latest/download/VieLotusIM.pkg" -o "${TMP_PKG}"
    if download_file "https://github.com/stevedat/VieLotus-IM/releases/latest/download/checksums.sha256" "${TMP_SUMS}" 2>/dev/null; then
        verify_artifact_sha256 "${TMP_PKG}" "VieLotusIM.pkg" "${TMP_SUMS}" "1"
    fi
    rm -f "${TMP_SUMS}"
    echo "📦 Đang cài đặt vào /Library/Input Methods..."
    ${SUDO} installer -pkg "${TMP_PKG}" -target /
    rm -f "${TMP_PKG}"
    echo "✅ Cài đặt Sen Việt trên macOS hoàn tất!"
    exit 0
fi

# ------------------------------------------------------------------------------
# Linux Architecture Detection (Multi-Arch: Prebuilt Fast-Path + Native C++20)
# ------------------------------------------------------------------------------
HAS_PREBUILT_DEB="0"
case "${ARCH_RAW}" in
    x86_64|amd64)
        DEB_ARCH="amd64"
        HAS_PREBUILT_DEB="1"
        ;;
    aarch64|arm64)
        DEB_ARCH="arm64"
        HAS_PREBUILT_DEB="1"
        ;;
    armv7*|armv6*|armhf|armel)
        DEB_ARCH="armhf"
        ;;
    riscv64)
        DEB_ARCH="riscv64"
        ;;
    i686|i586|i386|x86)
        DEB_ARCH="i386"
        ;;
    ppc64le|ppc64el)
        DEB_ARCH="ppc64el"
        ;;
    *)
        DEB_ARCH="${ARCH_RAW}"
        ;;
esac
if [ "${HAS_PREBUILT_DEB}" = "0" ]; then
    VIELOTUS_BUILD_FROM_SOURCE="1"
fi

echo "🌸 === Cài đặt Sen Việt (VieLotusIM v${VERSION}) cho Linux (${DEB_ARCH} / ${ARCH_RAW}) ==="

# Clean up any legacy user-local Snap export overrides (~/.local/lib/vielotus)
REAL_USER="${SUDO_USER:-$(id -un)}"
REAL_UID="$(id -u "${REAL_USER}" 2>/dev/null || id -u)"
REAL_HOME="$(getent passwd "${REAL_USER}" 2>/dev/null | cut -d: -f6 || echo "${HOME}")"
REAL_XDG_RUNTIME="${XDG_RUNTIME_DIR:-}"
if [ -z "${REAL_XDG_RUNTIME}" ] && [ -d "/run/user/${REAL_UID}" ]; then
    REAL_XDG_RUNTIME="/run/user/${REAL_UID}"
fi
REAL_DBUS="${DBUS_SESSION_BUS_ADDRESS:-}"
if [ -z "${REAL_DBUS}" ] && [ -n "${REAL_XDG_RUNTIME}" ] && [ -S "${REAL_XDG_RUNTIME}/bus" ]; then
    REAL_DBUS="unix:path=${REAL_XDG_RUNTIME}/bus"
fi
REAL_WAYLAND="${WAYLAND_DISPLAY:-}"
if [ -z "${REAL_WAYLAND}" ] && [ -n "${REAL_XDG_RUNTIME}" ]; then
    for _wsock in "${REAL_XDG_RUNTIME}"/wayland-[0-9]*; do
        if [ -S "${_wsock}" ]; then
            REAL_WAYLAND="$(basename "${_wsock}")"
            break
        fi
    done
fi
REAL_DISPLAY="${DISPLAY:-}"
if [ -z "${REAL_DISPLAY}" ] && [ -S /tmp/.X11-unix/X0 ]; then
    REAL_DISPLAY=":0"
fi
REAL_DESKTOP="${XDG_CURRENT_DESKTOP:-}"
if [ -z "${REAL_DESKTOP}" ] && command -v systemctl >/dev/null 2>&1 && [ "$(id -u)" -eq 0 ] && [ "${REAL_USER}" != "root" ]; then
    REAL_DESKTOP="$(systemctl --user -M "${REAL_USER}@" show-environment 2>/dev/null | sed -n 's/^XDG_CURRENT_DESKTOP=//p' | head -n 1 || true)"
fi

run_as_real_user() {
    if [ "$(id -u)" -ne 0 ] || [ -z "${REAL_USER}" ] || [ "${REAL_USER}" = "root" ]; then
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo -u "${REAL_USER}" env \
            HOME="${REAL_HOME}" \
            XDG_RUNTIME_DIR="${REAL_XDG_RUNTIME}" \
            DBUS_SESSION_BUS_ADDRESS="${REAL_DBUS}" \
            WAYLAND_DISPLAY="${REAL_WAYLAND}" \
            DISPLAY="${REAL_DISPLAY}" \
            XDG_CURRENT_DESKTOP="${REAL_DESKTOP}" \
            "$@"
    elif command -v su >/dev/null 2>&1; then
        su -s /bin/sh "${REAL_USER}" -c \
            "HOME='${REAL_HOME}' XDG_RUNTIME_DIR='${REAL_XDG_RUNTIME}' DBUS_SESSION_BUS_ADDRESS='${REAL_DBUS}' WAYLAND_DISPLAY='${REAL_WAYLAND}' DISPLAY='${REAL_DISPLAY}' XDG_CURRENT_DESKTOP='${REAL_DESKTOP}' $*"
    else
        "$@"
    fi
}

if [ -n "${REAL_HOME}" ] && [ -d "${REAL_HOME}" ]; then
    rm -rf "${REAL_HOME}/.local/lib/vielotus" 2>/dev/null || ${SUDO} rm -rf "${REAL_HOME}/.local/lib/vielotus" 2>/dev/null || true
    rm -f "${REAL_HOME}/.config/environment.d/90-vielotus.conf" 2>/dev/null || ${SUDO} rm -f "${REAL_HOME}/.config/environment.d/90-vielotus.conf" 2>/dev/null || true
    ${SUDO} rm -f /tmp/vielotus-settings.log 2>/dev/null || true
    if [ -d "${REAL_HOME}/.config/vielotus" ]; then
        ${SUDO} chown -R "${REAL_USER}:${REAL_USER}" "${REAL_HOME}/.config/vielotus" 2>/dev/null || true
    fi
fi

if command -v pkill >/dev/null 2>&1; then
    ${SUDO} pkill -9 -f "[i]bus-engine-vielotus" >/dev/null 2>&1 || true
    ${SUDO} pkill -9 -f "[v]ielotus-snap-runner" >/dev/null 2>&1 || true
fi

DEB_FILE="vielotus_${VERSION}_${DEB_ARCH}.deb"
TMP_DEB="/tmp/${DEB_FILE}"
TMP_SUMS="/tmp/vielotus-checksums-$$.sha256"

fetch_and_verify_deb() {
    if [ -n "${VIELOTUS_DEB_PATH:-}" ]; then
        if [ "${VIELOTUS_DEB_PATH}" != "${TMP_DEB}" ]; then
            cp "${VIELOTUS_DEB_PATH}" "${TMP_DEB}"
        fi
        if [ -n "${VIELOTUS_CHECKSUMS_PATH:-}" ]; then
            verify_artifact_sha256 "${TMP_DEB}" "$(basename "${VIELOTUS_DEB_PATH}")" "${VIELOTUS_CHECKSUMS_PATH}" "1"
        elif [ "${VIELOTUS_REQUIRE_SHA256:-0}" = "1" ]; then
            verify_artifact_sha256 "${TMP_DEB}" "${DEB_FILE}" "${TMP_SUMS}" "1"
        fi
        return 0
    fi

    PRIMARY_URL="https://github.com/stevedat/VieLotus-IM/releases/download/v${VERSION}/${DEB_FILE}"
    FALLBACK_URL="https://github.com/stevedat/VieLotus-IM/releases/latest/download/${DEB_FILE}"
    RAW_REPO_URL="https://raw.githubusercontent.com/stevedat/VieLotus-IM/main/Binaries/linux/${DEB_FILE}"

    SUMS_PRIMARY="https://github.com/stevedat/VieLotus-IM/releases/download/v${VERSION}/checksums.sha256"
    SUMS_FALLBACK="https://github.com/stevedat/VieLotus-IM/releases/latest/download/checksums.sha256"
    SUMS_RAW="https://raw.githubusercontent.com/stevedat/VieLotus-IM/main/Binaries/checksums.sha256"

    echo "⬇️  Đang tải gói cài đặt (${DEB_FILE})..."
    SUMS_FETCHED="0"
    if download_file "${PRIMARY_URL}" "${TMP_DEB}" 2>/dev/null; then
        download_file "${SUMS_PRIMARY}" "${TMP_SUMS}" 2>/dev/null && SUMS_FETCHED="1" || true
    elif download_file "${FALLBACK_URL}" "${TMP_DEB}" 2>/dev/null; then
        download_file "${SUMS_FALLBACK}" "${TMP_SUMS}" 2>/dev/null && SUMS_FETCHED="1" || true
    else
        download_file "${RAW_REPO_URL}" "${TMP_DEB}"
        download_file "${SUMS_RAW}" "${TMP_SUMS}" 2>/dev/null && SUMS_FETCHED="1" || true
    fi

    STRICT_SHA="${VIELOTUS_REQUIRE_SHA256:-${SUMS_FETCHED}}"
    verify_artifact_sha256 "${TMP_DEB}" "${DEB_FILE}" "${TMP_SUMS}" "${STRICT_SHA}"
    rm -f "${TMP_SUMS}"
}

abort_missing_build_deps() {
    echo "❌ Không thể biên dịch C++20 bản địa trên kiến trúc ${ARCH_RAW}."
    echo "   Vui lòng cài đặt: cmake, extra-cmake-modules, g++/clang++, pkgconf, python3, ibus-dev và/hoặc fcitx5-dev rồi chạy lại."
    exit 1
}

if command -v apt-get >/dev/null 2>&1 && command -v dpkg >/dev/null 2>&1; then
    echo "📦 Phát hiện hệ sinh thái Debian / Ubuntu / Raspberry Pi OS (apt)..."
    # Remove any sandboxed Snap installation so native /usr/bin/vielotus & system IBus/Fcitx5 take precedence
    if command -v snap >/dev/null 2>&1 && snap list vielotus >/dev/null 2>&1; then
        echo "🧹 Đang gỡ bản Snap cũ để đồng bộ sang gói hệ thống chuẩn..."
        for chg_id in $(snap changes 2>/dev/null | awk '/vielotus/ && ($2=="Doing" || $2=="Do") {print $1}'); do
            ${SUDO} snap abort "${chg_id}" >/dev/null 2>&1 || true
        done
        ${SUDO} snap remove --purge vielotus >/dev/null 2>&1 || ${SUDO} snap remove vielotus >/dev/null 2>&1 || true
    fi
    PKG_DEPENDS="/usr/share/language-selector/data/pkg_depends"
    if [ -f "${PKG_DEPENDS}" ]; then
        if ! grep -q "im:vi::vielotus" "${PKG_DEPENDS}" 2>/dev/null; then
            printf "\n# Sen Việt (VieLotusIM) Vietnamese Input Method\nim:vi::vielotus\nim:vi:fcitx5:fcitx5-vielotus\nim:vi:ibus:ibus-vielotus\n" | ${SUDO} tee -a "${PKG_DEPENDS}" >/dev/null || true
        fi
    fi
    if [ -f /etc/apt/sources.list.d/vielotus.list ] || [ -f /etc/apt/sources.list.d/vielotus.sources ]; then
        echo "🧹 Đang dọn nguồn APT tĩnh cũ (/etc/apt/sources.list.d/vielotus.list)..."
        ${SUDO} rm -f /etc/apt/sources.list.d/vielotus.list /etc/apt/sources.list.d/vielotus.sources 2>/dev/null || true
    fi
    ${SUDO} rm -f /var/cache/apt/archives/vielotus* 2>/dev/null || true

    if [ "${HAS_PREBUILT_DEB}" = "1" ] && [ "${VIELOTUS_BUILD_FROM_SOURCE:-0}" != "1" ]; then
        fetch_and_verify_deb
        ${SUDO} env DEBIAN_FRONTEND=noninteractive apt-get update -qq || true
        ${SUDO} env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends python3-gi gir1.2-gtk-3.0 zenity fonts-noto-core fonts-noto-mono fonts-liberation 2>/dev/null || true
        ${SUDO} env DEBIAN_FRONTEND=noninteractive dpkg -i --force-overwrite "${TMP_DEB}" || ${SUDO} env DEBIAN_FRONTEND=noninteractive apt-get install -f -y
    else
        echo "⬇️  Đang cài đặt các gói phụ trợ & trình biên dịch C++20 cho ${ARCH_RAW} (apt)..."
        APT_FCITX_PKGS="fcitx5 fcitx5-frontend-gtk3 fcitx5-frontend-qt5 fcitx5-config-qt"
        if printf '%s' "${REAL_DESKTOP}" | grep -qi "gnome"; then
            APT_FCITX_PKGS="fcitx5"
        fi
        ${SUDO} env DEBIAN_FRONTEND=noninteractive apt-get update -qq || true
        ${SUDO} env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
            ca-certificates curl tar build-essential cmake extra-cmake-modules pkg-config \
            python3 python3-gi gir1.2-gtk-3.0 zenity \
            fonts-noto-core fonts-noto-mono fonts-liberation \
            ibus libibus-1.0-dev libglib2.0-dev \
            ${APT_FCITX_PKGS} fcitx5-modules-dev libfcitx5core-dev libfcitx5config-dev libfcitx5utils-dev 2>/dev/null || \
        ${SUDO} env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
            ca-certificates curl tar build-essential cmake extra-cmake-modules pkgconf \
            python3 python3-gi gir1.2-gtk-3.0 \
            ibus libibus-1.0-dev libglib2.0-dev \
            fcitx5 fcitx5-modules-dev libfcitx5core-dev libfcitx5config-dev libfcitx5utils-dev || true
        if ! try_native_cmake_build "${VERSION}"; then
            if [ "${HAS_PREBUILT_DEB}" = "1" ]; then
                fetch_and_verify_deb
                ${SUDO} env DEBIAN_FRONTEND=noninteractive dpkg -i --force-overwrite "${TMP_DEB}" || ${SUDO} env DEBIAN_FRONTEND=noninteractive apt-get install -f -y
            else
                abort_missing_build_deps
            fi
        fi
        finalize_linux_integration
    fi
    if command -v fc-cache >/dev/null 2>&1; then
        nohup ${SUDO} fc-cache -f </dev/null >/dev/null 2>&1 &
    fi
elif command -v pacman >/dev/null 2>&1; then
    echo "📦 Phát hiện hệ sinh thái Arch Linux / Manjaro / CachyOS / EndeavourOS (pacman)..."
    ARCH_BUILD_SRC="${VIELOTUS_BUILD_FROM_SOURCE:-1}"
    ARCH_FCITX_PKGS="fcitx5-im"
    if printf '%s' "${REAL_DESKTOP}" | grep -qi "gnome"; then
        ARCH_FCITX_PKGS="fcitx5"
    fi
    ARCH_PKGS="python python-gobject gtk3 noto-fonts ibus ${ARCH_FCITX_PKGS}"
    if [ "${ARCH_BUILD_SRC}" = "1" ]; then
        ARCH_PKGS="${ARCH_PKGS} gcc make cmake extra-cmake-modules pkgconf"
    fi
    echo "⬇️  Đang kiểm tra & cài đặt các gói phụ trợ hệ thống (pacman)..."
    ${SUDO} pacman -S --needed --noconfirm ${ARCH_PKGS} >/dev/null 2>&1 || \
        ${SUDO} pacman -Sy --needed --noconfirm ${ARCH_PKGS} || true
    if [ "${ARCH_BUILD_SRC}" != "1" ] || ! try_native_cmake_build "${VERSION}"; then
        if [ "${HAS_PREBUILT_DEB}" = "1" ]; then
            fetch_and_verify_deb
            extract_deb_to_root "${TMP_DEB}"
        else
            abort_missing_build_deps
        fi
    fi
    finalize_linux_integration
    if command -v fc-cache >/dev/null 2>&1; then
        nohup ${SUDO} fc-cache -f </dev/null >/dev/null 2>&1 &
    fi
elif command -v dnf >/dev/null 2>&1; then
    echo "📦 Phát hiện hệ sinh thái Fedora / RHEL / Rocky / AlmaLinux (dnf)..."
    DNF_BUILD_SRC="${VIELOTUS_BUILD_FROM_SOURCE:-1}"
    DNF_FCITX_PKGS="fcitx5 fcitx5-autostart fcitx5-gtk fcitx5-qt fcitx5-configtool"
    if printf '%s' "${REAL_DESKTOP}" | grep -qi "gnome"; then
        DNF_FCITX_PKGS="fcitx5"
    fi
    ${SUDO} dnf install -y python3 python3-gobject gtk3 google-noto-sans-fonts ibus ${DNF_FCITX_PKGS} 2>/dev/null || \
        ${SUDO} dnf install -y python3 python3-gobject gtk3 ibus fcitx5 2>/dev/null || true
    if [ "${DNF_BUILD_SRC}" = "1" ]; then
        echo "⬇️  Đang kiểm tra trình biên dịch C++20 bản địa (dnf)..."
        ${SUDO} dnf install -y cmake extra-cmake-modules gcc-c++ make pkgconf-pkg-config ibus-devel glib2-devel fcitx5-devel 2>/dev/null || true
    fi
    if [ "${DNF_BUILD_SRC}" != "1" ] || ! try_native_cmake_build "${VERSION}"; then
        if [ "${HAS_PREBUILT_DEB}" = "1" ]; then
            fetch_and_verify_deb
            extract_deb_to_root "${TMP_DEB}"
        else
            abort_missing_build_deps
        fi
    fi
    finalize_linux_integration
elif command -v zypper >/dev/null 2>&1; then
    echo "📦 Phát hiện hệ sinh thái openSUSE (zypper)..."
    ZYPPER_BUILD_SRC="${VIELOTUS_BUILD_FROM_SOURCE:-1}"
    ${SUDO} zypper --non-interactive install python3 python3-gobject typelib-1_0-Gtk-3_0 google-noto-sans-fonts ibus fcitx5 fcitx5-configtool 2>/dev/null || \
        ${SUDO} zypper --non-interactive install python3 python3-gobject typelib-1_0-Gtk-3_0 ibus fcitx5 2>/dev/null || true
    if [ "${ZYPPER_BUILD_SRC}" = "1" ]; then
        echo "⬇️  Đang kiểm tra trình biên dịch C++20 bản địa (zypper)..."
        ${SUDO} zypper --non-interactive install cmake extra-cmake-modules gcc-c++ make pkgconf-pkg-config ibus-devel glib2-devel fcitx5-devel 2>/dev/null || true
    fi
    if [ "${ZYPPER_BUILD_SRC}" != "1" ] || ! try_native_cmake_build "${VERSION}"; then
        if [ "${HAS_PREBUILT_DEB}" = "1" ]; then
            fetch_and_verify_deb
            extract_deb_to_root "${TMP_DEB}"
        else
            abort_missing_build_deps
        fi
    fi
    finalize_linux_integration
elif command -v apk >/dev/null 2>&1; then
    echo "📦 Phát hiện hệ sinh thái Alpine Linux / postmarketOS (apk - musl)..."
    ${SUDO} apk add --no-cache ca-certificates curl tar python3 py3-gobject3 gtk+3.0 font-noto \
        build-base cmake extra-cmake-modules pkgconf ibus ibus-dev glib-dev fcitx5 fcitx5-dev 2>/dev/null || \
    ${SUDO} apk add --no-cache ca-certificates curl tar python3 py3-gobject3 gtk+3.0 \
        build-base cmake extra-cmake-modules pkgconf ibus ibus-dev glib-dev || true
    if ! try_native_cmake_build "${VERSION}"; then
        abort_missing_build_deps
    fi
    finalize_linux_integration
elif command -v xbps-install >/dev/null 2>&1; then
    echo "📦 Phát hiện hệ sinh thái Void Linux (xbps)..."
    ${SUDO} xbps-install -Sy curl tar python3 python3-gobject gtk+3 noto-fonts-ttf \
        base-devel cmake extra-cmake-modules pkg-config ibus ibus-devel glib-devel fcitx5 libfcitx5-devel 2>/dev/null || true
    if ! try_native_cmake_build "${VERSION}"; then
        if [ "${HAS_PREBUILT_DEB}" = "1" ]; then
            fetch_and_verify_deb
            extract_deb_to_root "${TMP_DEB}"
        else
            abort_missing_build_deps
        fi
    fi
    finalize_linux_integration
else
    echo "📦 Cài đặt trực tiếp vào /usr (Generic Linux — ${ARCH_RAW})..."
    if ! try_native_cmake_build "${VERSION}"; then
        if [ "${HAS_PREBUILT_DEB}" = "1" ]; then
            fetch_and_verify_deb
            extract_deb_to_root "${TMP_DEB}"
        else
            abort_missing_build_deps
        fi
    fi
    finalize_linux_integration
fi

rm -f "${TMP_DEB}" "${TMP_SUMS}"

if [ -x /usr/bin/vielotus-settings ]; then
    BOOTSTRAP_FCITX5="0"
    if [ -z "${CI:-}" ] && [ -n "${REAL_DISPLAY}${REAL_WAYLAND}" ] && ! printf '%s' "${REAL_DESKTOP}" | grep -qi "gnome"; then
        if ! pgrep -x ibus-daemon >/dev/null 2>&1 || printf '%s' "${REAL_DESKTOP}" | grep -Eqi 'kde|plasma|hyprland|sway|lxqt'; then
            BOOTSTRAP_FCITX5="1"
        fi
    fi
    run_as_real_user env VIELOTUS_BOOTSTRAP_FCITX5="${BOOTSTRAP_FCITX5}" /usr/bin/vielotus-settings --activate || true
fi

SETTINGS_OPENED="0"
if [ "${VIELOTUS_NO_OPEN_SETTINGS:-0}" != "1" ] && [ -z "${CI:-}" ] && [ -x /usr/bin/vielotus-settings ]; then
    if [ -n "${REAL_DISPLAY}${REAL_WAYLAND}" ]; then
        ( run_as_real_user nohup /usr/bin/vielotus-settings </dev/null >/dev/null 2>&1 & ) || true
        SETTINGS_OPENED="1"
    fi
fi

echo ""
echo "======================================================================"
echo "✅ Cài đặt & kích hoạt Sen Việt (VieLotusIM v${VERSION}) hoàn tất!"
echo "  • Kiến trúc CPU                 : ${DEB_ARCH} (${ARCH_RAW})"
if [ "${SETTINGS_OPENED}" = "1" ]; then
    echo "  • Cửa sổ Cài đặt Sen Việt       : Đã tự động mở — chọn Telex / VNI và gõ ngay!"
fi
echo "  • Đổi bộ gõ nhanh trên màn hình : Super + Space / Ctrl + Space"
echo "  • Mở ứng dụng cài đặt (GUI)     : Tìm 'Sen Việt' trong Menu ứng dụng (hoặc gõ: vielotus)"
echo "  • Chuyển sang kiểu gõ Telex     : vielotus --telex"
echo "  • Chuyển sang kiểu gõ VNI       : vielotus --vni"
echo "  • Chẩn đoán môi trường Linux    : vielotus --doctor"
echo "  • Lưu ý lần đầu cài (Wayland)   : Nếu thanh trên cùng chưa hiện '🇻🇳 tex' hoặc"
echo "                                    ứng dụng đang mở chưa nhận bộ gõ, hãy Log Out & Log In 1 lần."
echo "  • Gỡ cài đặt sạch               : sh install.sh --uninstall"
echo "======================================================================"
}

main "$@"
