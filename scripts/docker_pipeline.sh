#!/bin/bash
set -euo pipefail

VERSION="2.0.0"
DEB_REV="1"
GPG_KEY_ID="9B5642F2EBA2A1EC"
MAINTAINER="Trần Phát Đạt (Steve Dat) <ttd1232004@gmail.com>"

# Helper: strip macOS resource fork files from Docker volume mounts
strip_macos_junk() {
    find "$1" -name '._*' -delete 2>/dev/null || true
    find "$1" -name '.DS_Store' -delete 2>/dev/null || true
}

# Import GPG key
gpg --batch --import /gpg/secret.asc 2>/dev/null || true
gpg --batch --import /gpg/public.asc 2>/dev/null || true
echo "${GPG_KEY_ID}:6:" | gpg --batch --import-ownertrust 2>/dev/null || true

echo ""
echo "GPG keys imported:"
gpg --list-secret-keys --keyid-format long 2>&1 | head -8

# ── PPA source packages (noble + jammy) ──
FIRST_SERIES=true
for series in noble jammy; do
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Building PPA source for: ${series}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    SERIES_DIR="/output/ppa/${series}"
    mkdir -p "${SERIES_DIR}"

    # Copy orig tarball
    cp "/output/ppa/vielotus_${VERSION}.orig.tar.xz" "${SERIES_DIR}/"

    # Unpack orig
    cd "${SERIES_DIR}"
    tar xf "vielotus_${VERSION}.orig.tar.xz"
    SRC_DIR="${SERIES_DIR}/vielotus-${VERSION}"

    # Copy debian/
    cp -r /src/CrossPlatform/packaging/debian "${SRC_DIR}/debian"
    # Strip macOS resource fork files created by Docker volume mount from macOS host
    strip_macos_junk "${SRC_DIR}"

    # PPA version
    PPA_VERSION="${VERSION}-${DEB_REV}ppa1~${series}1"

    cat > "${SRC_DIR}/debian/changelog" << CHLOG
vielotus (${PPA_VERSION}) ${series}; urgency=medium

  * Official multi-architecture (amd64 & arm64) release of Sen Việt (VieLotusIM).
  * Pure C++20 native engine — zero Swift runtime dependency (~250 KB .so).
  * Native Fcitx5 addon and IBus engine integration.
  * Smart Bilingual English-Vietnamese collision resolution (100.00% on 9,091 tests).
  * Split Debian packages: libvielotus0, ibus-vielotus, fcitx5-vielotus.

 -- ${MAINTAINER}  $(date -R)
CHLOG

    echo "   📋 Version: ${PPA_VERSION}"

    # Build source-only package (-sa for first series, -sd for subsequent series sharing orig.tar.xz)
    cd "${SRC_DIR}"
    if [ "${FIRST_SERIES}" = true ]; then
        dpkg-buildpackage -S -sa -d -us -uc 2>&1 | tail -15
        FIRST_SERIES=false
    else
        dpkg-buildpackage -S -sd -d -us -uc 2>&1 | tail -15
    fi

    # Sign with debsign
    cd "${SERIES_DIR}"
    CHANGES_FILE=$(ls vielotus_*_source.changes 2>/dev/null | head -1)

    if [ -n "${CHANGES_FILE}" ]; then
        debsign -k "${GPG_KEY_ID}" "${CHANGES_FILE}" 2>&1 || echo "   ⚠️ debsign failed (may need manual signing)"
        echo "   ✅ Source package ready: ${CHANGES_FILE}"
    else
        echo "   ⚠️ No .changes file generated"
    fi

    # Lintian
    DSC_FILE=$(ls vielotus_*.dsc 2>/dev/null | head -1)
    if [ -n "${DSC_FILE}" ]; then
        echo ""
        echo "   🔍 Lintian on .dsc:"
        lintian --no-tag-display-limit "${DSC_FILE}" 2>&1 | head -20 || true
    fi

    # Clean up unpacked source
    rm -rf "${SRC_DIR}"
done

# ── Debian unstable source package ──
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Building Debian (unstable) source package"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

DEB_DIR="/output/debian"
mkdir -p "${DEB_DIR}"

cp "/output/ppa/vielotus_${VERSION}.orig.tar.xz" "${DEB_DIR}/"
cd "${DEB_DIR}"
tar xf "vielotus_${VERSION}.orig.tar.xz"
SRC_DIR="${DEB_DIR}/vielotus-${VERSION}"

cp -r /src/CrossPlatform/packaging/debian "${SRC_DIR}/debian"
strip_macos_junk "${SRC_DIR}"

DEB_VERSION="${VERSION}-${DEB_REV}"
cat > "${SRC_DIR}/debian/changelog" << CHLOG
vielotus (${DEB_VERSION}) unstable; urgency=medium

  * Initial release. (Closes: #XXXXXX)
  * Pure C++20 native engine — zero Swift runtime dependency.
  * Native Fcitx5 addon and IBus engine integration.
  * Smart Bilingual English-Vietnamese collision resolution.

 -- ${MAINTAINER}  $(date -R)
CHLOG

cd "${SRC_DIR}"
dpkg-buildpackage -S -d -us -uc 2>&1 | tail -15

cd "${DEB_DIR}"
CHANGES_FILE=$(ls vielotus_*_source.changes 2>/dev/null | head -1)
if [ -n "${CHANGES_FILE}" ]; then
    debsign -k "${GPG_KEY_ID}" "${CHANGES_FILE}" 2>&1 || echo "   ⚠️ debsign failed"
    echo "   ✅ Debian source package ready"
fi

DSC_FILE=$(ls vielotus_*.dsc 2>/dev/null | head -1)
if [ -n "${DSC_FILE}" ]; then
    echo ""
    echo "   🔍 Lintian:"
    lintian --no-tag-display-limit "${DSC_FILE}" 2>&1 | head -20 || true
fi

rm -rf "${SRC_DIR}"

# ── Full binary build test ──
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Full binary build test (dpkg-buildpackage)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

BUILD_DIR="/tmp/build-test"
mkdir -p "${BUILD_DIR}"
cp "/output/ppa/vielotus_${VERSION}.orig.tar.xz" "${BUILD_DIR}/"
cd "${BUILD_DIR}"
tar xf "vielotus_${VERSION}.orig.tar.xz"
cp -r /src/CrossPlatform/packaging/debian "${BUILD_DIR}/vielotus-${VERSION}/debian"
strip_macos_junk "${BUILD_DIR}/vielotus-${VERSION}"

cat > "${BUILD_DIR}/vielotus-${VERSION}/debian/changelog" << CHLOG
vielotus (${VERSION}-${DEB_REV}) unstable; urgency=medium

  * Build test.

 -- ${MAINTAINER}  $(date -R)
CHLOG

cd "${BUILD_DIR}/vielotus-${VERSION}"
dpkg-buildpackage -us -uc -b 2>&1 | tail -25

echo ""
echo "━━━ Generated .deb packages ━━━"
ls -lh "${BUILD_DIR}"/*.deb 2>/dev/null || echo "No .deb files found"

# Copy .deb files to output
cp "${BUILD_DIR}"/*.deb /output/debian/ 2>/dev/null || true

echo ""
echo "━━━ Lintian on .deb packages ━━━"
for deb in "${BUILD_DIR}"/*.deb; do
    [ -f "$deb" ] || continue
    echo "  → $(basename "${deb}"):"
    lintian "${deb}" 2>&1 | head -15 || true
    echo ""
done

echo ""
echo "━━━ Package details (dpkg -I) ━━━"
for deb in "${BUILD_DIR}"/*.deb; do
    [ -f "$deb" ] || continue
    echo "  → $(basename "${deb}"):"
    dpkg -I "${deb}" 2>&1 | grep -E "(Package|Version|Architecture|Installed-Size|Depends)" | head -8
    echo ""
done

echo ""
echo "================================================================="
echo "✅ Distribution pipeline complete!"
echo ""
echo "PPA uploads (run from host macOS via Docker):"
echo "  dput ppa:stevedat/vielotus dist/ppa/noble/vielotus_*_source.changes"
echo "  dput ppa:stevedat/vielotus dist/ppa/jammy/vielotus_*_source.changes"
echo ""
echo "Debian mentors upload:"
echo "  dput mentors dist/debian-upload/vielotus_*_source.changes"
echo "================================================================="
