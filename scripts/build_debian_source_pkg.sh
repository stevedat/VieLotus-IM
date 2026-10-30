#!/bin/bash
set -euo pipefail

# ==============================================================================
# Sen Việt (VieLotusIM) — Standard 3.0 (quilt) Debian Source Package Builder
# Generates offline-buildable Debian source package artifacts in dist/debian-src/:
#   - vielotus_${VERSION}.orig.tar.xz
#   - vielotus_${VERSION}-${DEB_REV}.debian.tar.xz
#   - vielotus_${VERSION}-${DEB_REV}.dsc
# Ready for:
#   - Clean chroot builds (`sbuild -d unstable dist/debian-src/vielotus_*.dsc`)
#   - Launchpad PPA upload (`debsign` + `dput ppa:<user>/vielotus ...`)
#   - Debian Mentors / RFS (`dput mentors ...`)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

VERSION="${1:-2.0.0}"
DEB_REV="${2:-1}"
OUT_DIR="${ROOT_DIR}/dist/debian-src"

rm -rf "${OUT_DIR}"
mkdir -p "${OUT_DIR}"

python3 - "${ROOT_DIR}" "${OUT_DIR}" "${VERSION}" "${DEB_REV}" <<'PYEOF'
import hashlib, io, lzma, os, stat, sys, tarfile, time

root_dir, out_dir, version, deb_rev = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
full_ver = f"{version}-{deb_rev}"
orig_name = f"vielotus_{version}.orig.tar.xz"
deb_name = f"vielotus_{full_ver}.debian.tar.xz"
dsc_name = f"vielotus_{full_ver}.dsc"

mtime = 1730246400  # deterministic timestamp

def norm_tarinfo(ti):
    ti.uid = 0
    ti.gid = 0
    ti.uname = "root"
    ti.gname = "root"
    ti.mtime = mtime
    return ti

def add_tree_to_tar(tf, src_base, rel_paths, arc_prefix):
    for rel in rel_paths:
        abs_p = os.path.join(src_base, rel)
        if not os.path.exists(abs_p):
            continue
        if os.path.isfile(abs_p):
            arc = f"{arc_prefix}/{rel}" if arc_prefix else rel
            ti = tf.gettarinfo(abs_p, arcname=arc)
            st = os.lstat(abs_p)
            ti.mode = 0o755 if (st.st_mode & stat.S_IXUSR) else 0o644
            with open(abs_p, "rb") as f:
                tf.addfile(norm_tarinfo(ti), fileobj=f)
        else:
            for dp, dns, fns in os.walk(abs_p):
                dns.sort()
                fns.sort()
                for fn in fns:
                    fp = os.path.join(dp, fn)
                    sub_rel = os.path.relpath(fp, src_base).replace(os.sep, "/")
                    arc = f"{arc_prefix}/{sub_rel}" if arc_prefix else sub_rel
                    ti = tf.gettarinfo(fp, arcname=arc)
                    st = os.lstat(fp)
                    ti.mode = 0o755 if (st.st_mode & stat.S_IXUSR) else 0o644
                    with open(fp, "rb") as f:
                        tf.addfile(norm_tarinfo(ti), fileobj=f)

# 1. Build orig.tar.xz (pure C/C++ source tree, zero prebuilt .so blobs)
orig_buf = io.BytesIO()
orig_paths = [
    "LICENSE",
    "README.md",
    "Resources/typing-modes.yml",
    "Sources/VieLotusCAPI/include/vielotus.h",
    "Sources/VieLotusCoreWindows/WindowsNativeEngine.h",
    "Sources/VieLotusCoreWindows/WindowsNativeEngine.cpp",
    "CrossPlatform/capi-native",
    "CrossPlatform/fcitx5-vielotus",
    "CrossPlatform/ibus-vielotus",
    "CrossPlatform/linux-icons",
    "CrossPlatform/packaging/linux",
]
with tarfile.open(fileobj=orig_buf, mode="w", format=tarfile.GNU_FORMAT) as tf:
    add_tree_to_tar(tf, root_dir, orig_paths, f"vielotus-{version}")

orig_xz = lzma.compress(orig_buf.getvalue(), preset=6)
orig_path = os.path.join(out_dir, orig_name)
with open(orig_path, "wb") as f:
    f.write(orig_xz)

# 2. Build debian.tar.xz
deb_buf = io.BytesIO()
deb_src = os.path.join(root_dir, "CrossPlatform", "packaging", "debian")
with tarfile.open(fileobj=deb_buf, mode="w", format=tarfile.GNU_FORMAT) as tf:
    for dp, dns, fns in os.walk(deb_src):
        dns.sort()
        fns.sort()
        for fn in fns:
            fp = os.path.join(dp, fn)
            sub_rel = os.path.relpath(fp, deb_src).replace(os.sep, "/")
            arc = f"debian/{sub_rel}"
            ti = tf.gettarinfo(fp, arcname=arc)
            ti.mode = 0o755 if fn == "rules" else 0o644
            with open(fp, "rb") as f:
                tf.addfile(norm_tarinfo(ti), fileobj=f)

deb_xz = lzma.compress(deb_buf.getvalue(), preset=6)
deb_path = os.path.join(out_dir, deb_name)
with open(deb_path, "wb") as f:
    f.write(deb_xz)

# 3. Build .dsc
def file_hashes(data):
    return (
        hashlib.md5(data).hexdigest(),
        hashlib.sha1(data).hexdigest(),
        hashlib.sha256(data).hexdigest(),
        len(data),
    )

o_md5, o_sha1, o_sha256, o_len = file_hashes(orig_xz)
d_md5, d_sha1, d_sha256, d_len = file_hashes(deb_xz)

dsc_content = f"""Format: 3.0 (quilt)
Source: vielotus
Binary: libvielotus0, ibus-vielotus, fcitx5-vielotus, vielotus
Architecture: any all
Version: {full_ver}
Maintainer: Trần Phát Đạt (Steve Dat) <ttd1232004@gmail.com>
Homepage: https://github.com/stevedat/VieLotus-IM
Standards-Version: 4.6.2
Vcs-Browser: https://github.com/stevedat/VieLotus-IM
Vcs-Git: https://github.com/stevedat/VieLotus-IM.git
Build-Depends: debhelper-compat (= 13), cmake (>= 3.16), extra-cmake-modules, g++ (>= 4:11), ninja-build, pkg-config, fcitx5-modules-dev, libfcitx5config-dev, libfcitx5core-dev, libfcitx5utils-dev, libibus-1.0-dev, libglib2.0-dev
Package-List:
 fcitx5-vielotus deb utils optional arch=any
 ibus-vielotus deb utils optional arch=any
 libvielotus0 deb libs optional arch=any
 vielotus deb metapackages optional arch=all
Checksums-Sha1:
 {o_sha1} {o_len} {orig_name}
 {d_sha1} {d_len} {deb_name}
Checksums-Sha256:
 {o_sha256} {o_len} {orig_name}
 {d_sha256} {d_len} {deb_name}
Files:
 {o_md5} {o_len} {orig_name}
 {d_md5} {d_len} {deb_name}
"""

dsc_path = os.path.join(out_dir, dsc_name)
with open(dsc_path, "w", encoding="utf-8") as f:
    f.write(dsc_content)
PYEOF

chmod +x "${ROOT_DIR}/scripts/build_debian_source_pkg.sh"
echo "================================================================="
echo "📦 Đã tạo bộ gói nguồn Debian 3.0 (quilt) tại ${OUT_DIR}:"
ls -lh "${OUT_DIR}"
echo "================================================================="
