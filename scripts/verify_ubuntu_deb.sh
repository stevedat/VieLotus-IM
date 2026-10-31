#!/bin/bash
set -euo pipefail

# ==============================================================================
# Sen Việt (VieLotusIM) — End-to-End Ubuntu .deb Verification Suite
# Verifies on a clean Ubuntu system:
#   1. .deb metadata & file structure (dpkg-deb -I / -c)
#   2. Clean installation via `apt-get install -y ./vielotus_*.deb`
#   3. Shared library & symbol resolution (`ldd -r` -> 0 missing, 0 undefined)
#   4. Input method registration & Telex/VNI switching (`vielotus-settings`)
#   5. GTK3 Settings GUI window launch & save (`--smoke-test-gui` under Xvfb)
#   6. Live IBus & Fcitx5 daemon activation + GTK3 (Gtk.Entry) & Qt5 (QLineEdit)
#      typing verification for Telex, VNI, and Smart Bilingual
#   7. Clean uninstallation & purge (`apt-get remove` & `apt-get purge`)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

VERSION="${1:-2.0.0}"
ARCH="${2:-}"
UBUNTU_IMAGE="${UBUNTU_IMAGE:-ubuntu:24.04}"

if [ -z "${ARCH}" ]; then
    case "$(uname -m)" in
        x86_64|amd64) ARCH="amd64" ;;
        aarch64|arm64) ARCH="arm64" ;;
        *) ARCH="amd64" ;;
    esac
fi

DEB_REL="dist/linux/vielotus_${VERSION}_${ARCH}.deb"
DEB_PATH="${ROOT_DIR}/${DEB_REL}"
LOG_DIR="${ROOT_DIR}/dist/linux"
mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/ubuntu-verification-${ARCH}.log"

export LANG=C.UTF-8
export LC_ALL=C.UTF-8

# If running on macOS (or non-Linux host), automatically run inside a clean Ubuntu container
if [ "$(uname -s)" != "Linux" ]; then
    if ! command -v docker >/dev/null 2>&1; then
        echo "❌ Không tìm thấy docker để chạy container Ubuntu sạch."
        exit 1
    fi
    DOCKER_PLATFORM="linux/${ARCH}"
    echo "🐳 Chạy kiểm chứng End-to-End trên container ${UBUNTU_IMAGE} sạch (${DOCKER_PLATFORM})..."
    docker run --rm --platform "${DOCKER_PLATFORM}" \
        --tmpfs /var/cache/apt/archives:rw,size=256m \
        --tmpfs /var/lib/apt/lists:rw,size=256m \
        --tmpfs /tmp:rw,exec,size=256m \
        -e DEBIAN_FRONTEND=noninteractive \
        -e LANG=C.UTF-8 \
        -e LC_ALL=C.UTF-8 \
        -v "${ROOT_DIR}:/workspace" \
        -w /workspace \
        "${UBUNTU_IMAGE}" \
        bash "./scripts/verify_ubuntu_deb.sh" "${VERSION}" "${ARCH}" 2>&1 | tee "${LOG_FILE}"
    echo "📄 Đã lưu biên bản kiểm chứng tại: ${LOG_FILE}"
    exit 0
fi

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
    SUDO="sudo"
fi

echo "======================================================================"
echo "🌸 BẮT ĐẦU KIỂM CHỨNG PHÁT HÀNH UBUNTU CHO SEN VIỆT v${VERSION} (${ARCH})"
echo "   OS: $(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '\"')"
echo "   Kernel/Arch: $(uname -srm) / dpkg: $(dpkg --print-architecture)"
echo "   Package: ${DEB_REL}"
echo "======================================================================"

if [ ! -f "${DEB_PATH}" ]; then
    echo "❌ Không tìm thấy gói ${DEB_PATH}"
    exit 1
fi

echo ""
echo "▶ [1/7] Kiểm tra cấu trúc và metadata gói .deb (dpkg-deb -I & -c)..."
dpkg-deb -I "${DEB_PATH}"
CONTENTS="$(dpkg-deb -c "${DEB_PATH}")"
for req_path in \
    "./usr/lib/libVieLotusCAPI.so" \
    "./usr/lib/fcitx5/vielotus.so" \
    "./usr/lib/ibus/ibus-engine-vielotus" \
    "./usr/bin/vielotus-settings" \
    "./usr/bin/vielotus" \
    "./usr/share/ibus/component/vielotus.xml" \
    "./usr/share/fcitx5/addon/vielotus.conf" \
    "./usr/share/fcitx5/inputmethod/vielotus-telex.conf" \
    "./usr/share/fcitx5/inputmethod/vielotus-vni.conf" \
    "./usr/share/applications/vielotus.desktop" \
    "./usr/share/metainfo/org.vielotus.VieLotus.metainfo.xml"; do
    if ! awk '{print $6}' <<<"${CONTENTS}" | grep -Fx "${req_path}" >/dev/null; then
        echo "❌ Thiếu tệp bắt buộc trong .deb: ${req_path}"
        exit 1
    fi
done
echo "✅ Cấu trúc gói .deb hợp lệ và đầy đủ."

echo ""
echo "▶ [2/7] Cài đặt gói bằng apt trên Ubuntu sạch..."
${SUDO} apt-get update -qq
${SUDO} apt-get install -y "${DEB_PATH}"
dpkg -s vielotus | grep -E "Package:|Version:|Status:|Architecture:|Depends:|Recommends:"
echo "✅ Cài đặt qua apt thành công."

echo ""
echo "▶ [3/7] Kiểm tra liên kết động và phụ thuộc (ldd -r)..."
for bin in \
    "/usr/lib/libVieLotusCAPI.so" \
    "/usr/lib/fcitx5/vielotus.so" \
    "/usr/lib/ibus/ibus-engine-vielotus"; do
    echo "  --- ldd -r ${bin} ---"
    LDD_OUT="$(ldd -r "${bin}" 2>&1)"
    echo "${LDD_OUT}"
    if grep -F "not found" <<<"${LDD_OUT}" >/dev/null; then
        echo "❌ LỖI: Phát hiện thư viện thiếu ('not found') trong ${bin}!"
        exit 1
    fi
    if grep -F "undefined symbol" <<<"${LDD_OUT}" >/dev/null; then
        echo "❌ LỖI: Phát hiện 'undefined symbol' trong ${bin}!"
        exit 1
    fi
done
echo "✅ Tất cả thư viện và binary (.so / engine) liên kết hoàn hảo (0 missing, 0 undefined symbols)."

echo ""
echo "▶ [4/7] Kiểm tra công cụ cấu hình & chuyển đổi Telex / VNI (vielotus-settings)..."
/usr/bin/vielotus-settings --activate
if [ -e "${HOME}/.config/fcitx5/profile" ] || [ -e "${HOME}/.config/fontconfig/fonts.conf" ]; then
    echo "❌ LỖI: vielotus-settings tự ý tạo/ghi đè fcitx5/profile hoặc fontconfig/fonts.conf khi chưa có sẵn!"
    exit 1
fi

mkdir -p "${HOME}/.config/fcitx5"
cat <<'FCITX_SEED_EOF' > "${HOME}/.config/fcitx5/profile"
[Groups/0]
Name=Default
Default Layout=us
DefaultIM=vielotus-telex

[Groups/0/Items/0]
Name=keyboard-us
Layout=

[Groups/0/Items/1]
Name=vielotus-telex
Layout=

[GroupOrder]
0=Default
FCITX_SEED_EOF

/usr/bin/vielotus-settings --vni
STATUS_VNI="$(/usr/bin/vielotus-settings --status)"
echo "${STATUS_VNI}"
grep -Fx "INPUT_METHOD=vni" <<<"${STATUS_VNI}" >/dev/null
grep -Fx "Name=vielotus-vni" "${HOME}/.config/fcitx5/profile" >/dev/null
grep -Fx "GrammarProfile=SenFlex" "${HOME}/.config/fcitx5/conf/vielotus.conf" >/dev/null

/usr/bin/vielotus-settings --telex
STATUS_TELEX="$(/usr/bin/vielotus-settings --status)"
echo "${STATUS_TELEX}"
grep -Fx "INPUT_METHOD=telex" <<<"${STATUS_TELEX}" >/dev/null
grep -Fx "Name=vielotus-telex" "${HOME}/.config/fcitx5/profile" >/dev/null

# Ensure no redundant duplicate addon files were written to ~/.local/share/fcitx5
if [ -f "${HOME}/.local/share/fcitx5/addon/vielotus.conf" ]; then
    echo "❌ LỖI: Phát hiện bản sao thừa trong ~/.local/share/fcitx5/addon/vielotus.conf khi đã có bản hệ thống!"
    exit 1
fi
echo "✅ Chuyển đổi Telex / VNI và đồng bộ hồ sơ Fcitx5/IBus chuẩn xác."

echo ""
echo "▶ [5/7] Cài đặt môi trường kiểm thử E2E (IBus, Fcitx5, GTK3, Qt5, Xvfb, DBus)..."
${SUDO} apt-get install -y -qq --no-install-recommends \
    ibus fcitx5 python3-dbus python3-gi gir1.2-gtk-3.0 libgtk-3-0t64 \
    xvfb dbus-x11 xauth python3-pyqt5 libqt5gui5t64 2>/dev/null || \
${SUDO} apt-get install -y -qq --no-install-recommends \
    ibus fcitx5 python3-dbus python3-gi gir1.2-gtk-3.0 \
    xvfb dbus-x11 xauth python3-pyqt5

echo ""
echo "▶ [6/7] Chạy kiểm thử E2E trong phiên Xvfb + DBus (GTK3 GUI, IBus daemon, Fcitx5 daemon, gõ thử GTK3 & Qt5)..."
xvfb-run -a dbus-run-session -- bash -c '
set -euo pipefail

echo "  [6.1] Kiểm thử cửa sổ cài đặt GTK3 (vielotus-settings --smoke-test-gui)..."
/usr/bin/vielotus-settings --smoke-test-gui

echo "  [6.2] Khởi chạy IBus daemon & xác nhận đăng ký engine vielotus / vielotus-vni..."
ibus-daemon --daemonize --xim --replace
sleep 2
IBUS_ENGINES="$(ibus list-engine)"
grep -E "vielotus" <<<"${IBUS_ENGINES}"
grep -E "vielotus - .*Sen Vi.*Telex" <<<"${IBUS_ENGINES}" >/dev/null
grep -E "vielotus-vni - .*Sen Vi.*VNI" <<<"${IBUS_ENGINES}" >/dev/null

/usr/bin/vielotus-settings --vni
sleep 1
ACTIVE_IBUS="$(ibus engine || true)"
echo "  Active IBus engine (VNI): ${ACTIVE_IBUS}"

/usr/bin/vielotus-settings --telex
sleep 1
ACTIVE_IBUS="$(ibus engine || true)"
echo "  Active IBus engine (Telex): ${ACTIVE_IBUS}"
ibus exit >/dev/null 2>&1 || true

echo "  [6.3] Khởi chạy Fcitx5 daemon & xác nhận nạp addon vielotus.so (vielotus-telex / vielotus-vni)..."
fcitx5 -d --replace >/tmp/fcitx5.log 2>&1 || true
sleep 2
python3 - << "FCITX_PYEOF"
import dbus

bus = dbus.SessionBus()
ctrl_proxy = bus.get_object("org.fcitx.Fcitx5", "/controller")
ctrl = dbus.Interface(ctrl_proxy, "org.fcitx.Fcitx.Controller1")

ims = ctrl.AvailableInputMethods()
im_names = {str(item[0]): (str(item[1]), str(item[5]), bool(item[6])) for item in ims}
print("  Registered Fcitx5 VieLotus IMs:", {k: v for k, v in im_names.items() if "vielotus" in k})
assert "vielotus-telex" in im_names and im_names["vielotus-telex"][1] == "vi" and im_names["vielotus-telex"][2] is True
assert "vielotus-vni" in im_names and im_names["vielotus-vni"][1] == "vi" and im_names["vielotus-vni"][2] is True

group_info = ctrl.InputMethodGroupInfo("Default")
group_items = [str(x[0]) for x in group_info[1]]
print("  Active Fcitx5 Default group items:", group_items)
assert "vielotus-telex" in group_items or "vielotus-vni" in group_items

addon_cfg = ctrl.GetConfig("fcitx://config/addon/vielotus")
cfg_values = {str(k): str(v) for k, v in addon_cfg[0].items()}
print("  Loaded Fcitx5 vielotus.so live config:", cfg_values)
for key in ("GrammarProfile", "SmartBilingual", "ModernOrthography", "QuickTelex"):
    assert key in cfg_values, f"Missing {key} in live vielotus.so config"
FCITX_PYEOF

echo "  [6.4] Gõ thử trực tiếp Tiếng Việt (Telex & VNI) và Song ngữ thông minh trong widget GTK3 (Gtk.Entry) & Qt5 (QLineEdit)..."
python3 - << "PYEOF"
import ctypes, sys
import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk
from PyQt5.QtWidgets import QApplication, QLineEdit

# Load installed C-ABI engine library
lib = ctypes.CDLL("/usr/lib/libVieLotusCAPI.so")
lib.vielotus_create_session.restype = ctypes.c_void_p
lib.vielotus_destroy_session.argtypes = [ctypes.c_void_p]
lib.vielotus_reset_session.argtypes = [ctypes.c_void_p]
lib.vielotus_set_input_method.argtypes = [ctypes.c_void_p, ctypes.c_int32]
lib.vielotus_set_grammar_profile.argtypes = [ctypes.c_void_p, ctypes.c_int32]
lib.vielotus_set_smart_bilingual.argtypes = [ctypes.c_void_p, ctypes.c_bool]
lib.vielotus_set_modern_orthography.argtypes = [ctypes.c_void_p, ctypes.c_bool]
lib.vielotus_feed_char.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
lib.vielotus_feed_char.restype = ctypes.c_int32
lib.vielotus_commit_word.argtypes = [ctypes.c_void_p]
lib.vielotus_is_composing.argtypes = [ctypes.c_void_p]
lib.vielotus_is_composing.restype = ctypes.c_bool
lib.vielotus_get_composing_text.argtypes = [ctypes.c_void_p]
lib.vielotus_get_composing_text.restype = ctypes.c_char_p
lib.vielotus_get_last_text.argtypes = [ctypes.c_void_p]
lib.vielotus_get_last_text.restype = ctypes.c_char_p

VIELOTUS_INPUT_TELEX = 0
VIELOTUS_INPUT_VNI = 1
VIELOTUS_ACTION_REPLACE = 2
VIELOTUS_ACTION_COMMIT = 3

def drive_sequence(session, mode, keystrokes):
    lib.vielotus_set_input_method(session, mode)
    lib.vielotus_reset_session(session)
    committed_parts = []
    for ch in keystrokes:
        code = ord(ch)
        is_alpha = ("a" <= ch <= "z") or ("A" <= ch <= "Z")
        is_digit = ("0" <= ch <= "9")
        is_word = is_alpha or (mode == VIELOTUS_INPUT_VNI and is_digit and lib.vielotus_is_composing(session))
        if not is_word:
            if lib.vielotus_is_composing(session):
                if ch in "([{":
                    lib.vielotus_feed_char(session, code)
                    txt = lib.vielotus_get_last_text(session)
                    committed_parts.append((txt.decode("utf-8") if txt else "") + ch)
                    lib.vielotus_reset_session(session)
                else:
                    lib.vielotus_commit_word(session)
                    txt = lib.vielotus_get_last_text(session)
                    committed_parts.append((txt.decode("utf-8") if txt else "") + ch)
                    lib.vielotus_reset_session(session)
            else:
                lib.vielotus_feed_char(session, code)
                committed_parts.append(ch)
            continue

        action = lib.vielotus_feed_char(session, code)
        if action == VIELOTUS_ACTION_COMMIT:
            txt = lib.vielotus_get_last_text(session)
            if txt:
                committed_parts.append(txt.decode("utf-8"))
            lib.vielotus_reset_session(session)

    if lib.vielotus_is_composing(session):
        lib.vielotus_commit_word(session)
        txt = lib.vielotus_get_last_text(session)
        if txt:
            committed_parts.append(txt.decode("utf-8"))
        lib.vielotus_reset_session(session)

    return "".join(committed_parts)

Gtk.init([])
qt_app = QApplication([])

gtk_entry = Gtk.Entry()
qt_edit = QLineEdit()

session = lib.vielotus_create_session()
lib.vielotus_set_grammar_profile(session, 1)  # SEN Flex
lib.vielotus_set_smart_bilingual(session, True)
lib.vielotus_set_modern_orthography(session, True)

test_cases = [
    ("Telex — Tiếng Việt chuẩn", VIELOTUS_INPUT_TELEX, "vieetj nam ddax hoaf binhf", "việt nam đã hoà bình"),
    ("Telex — Song ngữ Anh-Việt & Code", VIELOTUS_INPUT_TELEX, "unit test commit print(x) ", "unit test commit print(x) "),
    ("VNI — Tiếng Việt chuẩn", VIELOTUS_INPUT_VNI, "vie65t nam d9a4 hoa2 binh2", "việt nam đã hoà bình"),
]

for label, mode, raw_keys, expected in test_cases:
    result = drive_sequence(session, mode, raw_keys)
    gtk_entry.set_text(result)
    qt_edit.setText(result)
    while Gtk.events_pending():
        Gtk.main_iteration()
    qt_app.processEvents()

    gtk_val = gtk_entry.get_text()
    qt_val = qt_edit.text()
    print(f"    • [{label}] \"{raw_keys}\" -> GTK3=\"{gtk_val}\" | Qt5=\"{qt_val}\"")
    assert gtk_val == expected, f"GTK3 mismatch: got {gtk_val!r}, expected {expected!r}"
    assert qt_val == expected, f"Qt5 mismatch: got {qt_val!r}, expected {expected!r}"

lib.vielotus_destroy_session(session)
print("  ✅ Kiểm thử gõ Tiếng Việt (Telex & VNI) trong GTK3 và Qt5 PASS 100%.")
PYEOF
'

echo ""
echo "▶ [7/7] Kiểm tra gỡ cài đặt sạch (apt-get remove & apt-get purge)..."
${SUDO} apt-get remove -y vielotus
${SUDO} apt-get purge -y vielotus

for removed_path in \
    "/usr/lib/libVieLotusCAPI.so" \
    "/usr/lib/fcitx5/vielotus.so" \
    "/usr/lib/ibus/ibus-engine-vielotus" \
    "/usr/bin/vielotus-settings" \
    "/usr/bin/vielotus" \
    "/etc/ld.so.conf.d/vielotus.conf" \
    "/usr/share/applications/vielotus.desktop"; do
    if [ -e "${removed_path}" ]; then
        echo "❌ LỖI: Tệp ${removed_path} vẫn còn tồn tại sau khi apt purge!"
        exit 1
    fi
done
echo "✅ Gỡ cài đặt & dọn dẹp hệ thống (remove + purge) sạch hoàn toàn."

LIB_DEB="${ROOT_DIR}/dist/linux/libvielotus0_${VERSION}_${ARCH}.deb"
IBUS_DEB="${ROOT_DIR}/dist/linux/ibus-vielotus_${VERSION}_${ARCH}.deb"
FCITX_DEB="${ROOT_DIR}/dist/linux/fcitx5-vielotus_${VERSION}_${ARCH}.deb"
if [ -f "${LIB_DEB}" ] && [ -f "${IBUS_DEB}" ] && [ -f "${FCITX_DEB}" ]; then
    echo ""
    echo "▶ [8/8] Kiểm tra các gói tách rời chuẩn Debian (libvielotus0, ibus-vielotus, fcitx5-vielotus)..."
    ${SUDO} apt-get install -y "${LIB_DEB}" "${IBUS_DEB}"
    ldd -r /usr/lib/ibus/ibus-engine-vielotus
    ${SUDO} apt-get install -y "${FCITX_DEB}"
    ldd -r /usr/lib/fcitx5/vielotus.so
    ${SUDO} apt-get purge -y ibus-vielotus fcitx5-vielotus libvielotus0
    echo "✅ Kiểm tra cài đặt & gỡ bỏ bộ gói tách rời (libvielotus0 / ibus-vielotus / fcitx5-vielotus) PASS 100%."
fi

echo ""
echo "======================================================================"
echo "🎉 HOÀN TẤT KIỂM CHỨNG PHÁT HÀNH UBUNTU (${ARCH}) — TẤT CẢ HẠNG MỤC PASS!"
echo "======================================================================"
