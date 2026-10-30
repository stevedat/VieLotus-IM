#!/bin/bash
set -euo pipefail

# ==============================================================================
# Sen Việt (VieLotusIM) — Complete PPA + Debian Distribution Pipeline
# Runs inside Docker (Ubuntu 24.04) to build, sign, lint, and prepare
# source packages for Launchpad PPA upload and Debian mentors.
#
# Usage (from repo root):
#   ./scripts/distribute_linux.sh [--upload]
#
# Without --upload: builds & signs packages only (dry run)
# With --upload:    also uploads to Launchpad PPA via dput
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

DO_UPLOAD=false
[[ "${1:-}" == "--upload" ]] && DO_UPLOAD=true

VERSION="2.0.0"
DEB_REV="1"
GPG_KEY_ID="9B5642F2EBA2A1EC"
GPG_FINGERPRINT="2B235C40889ABF9AAD701D149B5642F2EBA2A1EC"
MAINTAINER="Trần Phát Đạt (Steve Dat) <ttd1232004@gmail.com>"
PPA_SERIES="noble jammy"  # Ubuntu 24.04 LTS, 22.04 LTS

DIST_DIR="${ROOT_DIR}/dist/ppa"
DEBIAN_DIR="${ROOT_DIR}/dist/debian-upload"

echo "================================================================="
echo "🚀 Sen Việt (VieLotusIM) Linux Distribution Pipeline"
echo "   Version:  ${VERSION}-${DEB_REV}"
echo "   GPG Key:  ${GPG_KEY_ID}"
echo "   Series:   ${PPA_SERIES}"
echo "   Upload:   ${DO_UPLOAD}"
echo "================================================================="

# ── Step 0: Export GPG secret key for Docker container ──
echo ""
echo "━━━ Step 0: Preparing GPG key ━━━"
GPG_EXPORT_DIR=$(mktemp -d)
gpg --armor --export-secret-keys "${GPG_KEY_ID}" > "${GPG_EXPORT_DIR}/secret.asc"
gpg --armor --export "${GPG_KEY_ID}" > "${GPG_EXPORT_DIR}/public.asc"
echo "   ✅ GPG keys exported to temp dir"

# ── Step 1: Build Docker image ──
echo ""
echo "━━━ Step 1: Building PPA builder Docker image ━━━"
docker build -t vielotus-ppa-builder \
    -f "${ROOT_DIR}/CrossPlatform/packaging/Dockerfile.ppa" \
    "${ROOT_DIR}/CrossPlatform/packaging/" 2>&1 | tail -3

echo "   ✅ Docker image ready"

# ── Step 2: Prepare source tree ──
echo ""
echo "━━━ Step 2: Preparing source trees ━━━"
rm -rf "${DIST_DIR}" "${DEBIAN_DIR}"
mkdir -p "${DIST_DIR}" "${DEBIAN_DIR}"

# Build orig tarball
ORIG_TARBALL="vielotus_${VERSION}.orig.tar.xz"
TEMP_SRC=$(mktemp -d)
SRC_ROOT="${TEMP_SRC}/vielotus-${VERSION}"
mkdir -p "${SRC_ROOT}"

# Copy source files (pure C/C++ — no Swift, no prebuilt .so)
for path in \
    LICENSE README.md \
    Resources/typing-modes.yml \
    Sources/VieLotusCAPI/include/vielotus.h \
    Sources/VieLotusCoreWindows/WindowsNativeEngine.h \
    Sources/VieLotusCoreWindows/WindowsNativeEngine.cpp; do
    if [ -f "${ROOT_DIR}/${path}" ]; then
        mkdir -p "${SRC_ROOT}/$(dirname "${path}")"
        cp "${ROOT_DIR}/${path}" "${SRC_ROOT}/${path}"
    fi
done

for dir in \
    CrossPlatform/capi-native \
    CrossPlatform/fcitx5-vielotus \
    CrossPlatform/ibus-vielotus \
    CrossPlatform/linux-icons \
    CrossPlatform/packaging/linux; do
    if [ -d "${ROOT_DIR}/${dir}" ]; then
        mkdir -p "${SRC_ROOT}/$(dirname "${dir}")"
        cp -r "${ROOT_DIR}/${dir}" "${SRC_ROOT}/${dir}"
    fi
done

find "${SRC_ROOT}" -name '._*' -delete 2>/dev/null || true
find "${SRC_ROOT}" -name '.DS_Store' -delete 2>/dev/null || true
xattr -cr "${SRC_ROOT}" 2>/dev/null || true
COPYFILE_DISABLE=1 tar --no-xattrs -C "${TEMP_SRC}" -cJf "${DIST_DIR}/${ORIG_TARBALL}" "vielotus-${VERSION}"
echo "   ✅ ${ORIG_TARBALL} ($(du -h "${DIST_DIR}/${ORIG_TARBALL}" | cut -f1))"

# ── Step 3+: Run in Docker using scripts/docker_pipeline.sh ──
echo ""
echo "━━━ Step 3+: Running build pipeline in Docker ━━━"
docker run --rm \
    -v "${ROOT_DIR}:/src:ro" \
    -v "${DIST_DIR}:/output/ppa" \
    -v "${DEBIAN_DIR}:/output/debian" \
    -v "${GPG_EXPORT_DIR}:/gpg:ro" \
    -v "${ROOT_DIR}/scripts/docker_pipeline.sh:/run.sh:ro" \
    vielotus-ppa-builder \
    bash /run.sh

# ── Step 5: Upload if requested ──
if [ "${DO_UPLOAD}" = true ]; then
    echo ""
    echo "━━━ Step 5: Uploading to PPA ━━━"
    for series in ${PPA_SERIES}; do
        CHANGES=$(ls "${DIST_DIR}/${series}"/vielotus_*_source.changes 2>/dev/null | head -1)
        if [ -n "${CHANGES}" ]; then
            echo "   📤 Uploading ${series}..."
            docker run --rm \
                -v "${DIST_DIR}:/output/ppa" \
                -v "${GPG_EXPORT_DIR}:/gpg:ro" \
                vielotus-ppa-builder \
                bash -c "gpg --batch --import /gpg/secret.asc 2>/dev/null; dput ppa:stevedat/vielotus /output/ppa/${series}/vielotus_*_source.changes"
        fi
    done
fi

# Cleanup
rm -rf "${GPG_EXPORT_DIR}" "${TEMP_SRC}"

echo ""
echo "================================================================="
echo "🎉 Pipeline hoàn tất!"
echo ""
echo "📁 Artifacts:"
echo "   PPA (noble):   ${DIST_DIR}/noble/"
echo "   PPA (jammy):   ${DIST_DIR}/jammy/"
echo "   Debian:        ${DEBIAN_DIR}/"
echo ""
if [ "${DO_UPLOAD}" = false ]; then
    echo "💡 Chạy lại với --upload để upload PPA:"
    echo "   ./scripts/distribute_linux.sh --upload"
fi
echo "================================================================="
