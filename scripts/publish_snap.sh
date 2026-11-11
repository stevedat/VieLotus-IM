#!/bin/bash
set -euo pipefail

# ==============================================================================
# Sen Việt (VieLotusIM) - Snap Store Upload & Release Script
# Uploads and releases amd64 & arm64 .snap packages to Canonical Snap Store
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

VERSION="${1:-2.0.0}"
CHANNEL="${2:-stable}"
DIST_LINUX="${ROOT_DIR}/dist/linux"

AMD64_SNAP="${DIST_LINUX}/vielotus_${VERSION}_amd64.snap"
ARM64_SNAP="${DIST_LINUX}/vielotus_${VERSION}_arm64.snap"

echo "🌸 === Đẩy gói Sen Việt (VieLotusIM) v${VERSION} lên Canonical Snap Store ==="

if ! command -v snapcraft >/dev/null 2>&1; then
    echo "❌ Lỗi: Chưa cài đặt snapcraft (chạy: brew install snapcraft squashfs)."
    exit 1
fi

# 1. Ensure .snap files exist
if [ ! -f "${AMD64_SNAP}" ] || [ ! -f "${ARM64_SNAP}" ]; then
    echo "📦 Chưa tìm thấy đầy đủ gói .snap, tiến hành build trước..."
    "${SCRIPT_DIR}/build_snap.sh" "${VERSION}"
fi

# 2. Check Snap Store login state
if ! snapcraft whoami >/dev/null 2>&1; then
    echo "🔑 Chưa đăng nhập Snap Store (Ubuntu One SSO)."
    echo "👉 Đang mở phiên đăng nhập 'snapcraft login'..."
    snapcraft login
fi

echo "✅ Tài khoản Snap Store hiện tại:"
snapcraft whoami

# 3. Ensure 'vielotus' name is registered on Snap Store
if ! snapcraft names 2>/dev/null | awk '{print $1}' | grep -qx "vielotus"; then
    echo "📝 Đang đăng ký định danh 'vielotus' trên Snap Store..."
    snapcraft register vielotus || true
fi

# 4. Upload and release amd64 & arm64 snaps
echo "🚀 Đang tải lên & phát hành bản amd64 (${AMD64_SNAP}) vào kênh '${CHANNEL}'..."
snapcraft upload "${AMD64_SNAP}" --release="${CHANNEL}"

echo "🚀 Đang tải lên & phát hành bản arm64 (${ARM64_SNAP}) vào kênh '${CHANNEL}'..."
snapcraft upload "${ARM64_SNAP}" --release="${CHANNEL}"

echo "🎨 Đang đồng bộ metadata & icon lên trang chủ Snap Store..."
snapcraft upload-metadata "${AMD64_SNAP}" --force || true

echo "======================================================="
echo "🎉 Đã đẩy thành công cả 2 kiến trúc (amd64 & arm64) lên Snap Store!"
snapcraft status vielotus || true
echo "======================================================="
