#!/bin/bash
set -euo pipefail

# ==============================================================================
# Sen Việt (VieLotusIM) — Standard 3.0 (quilt) Debian Source Package Builder
# Generates offline-buildable Debian source package artifacts in dist/debian-src/:
#   - vielotus_${VERSION}.orig.tar.gz   (aligned with debian/watch GitHub tag)
#   - vielotus_${VERSION}-${DEB_REV}.debian.tar.xz
#   - vielotus_${VERSION}-${DEB_REV}.dsc
#   - vielotus_${VERSION}-${DEB_REV}_source.changes
# Ready for:
#   - Clean chroot builds (`sbuild -d unstable dist/debian-src/vielotus_*.dsc`)
#   - Debian Mentors / RFS (`dput mentors dist/debian-src/vielotus_${VERSION}-${DEB_REV}_source.changes`)
#   - Launchpad PPA upload (`dput ppa:<user>/vielotus ...`)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

VERSION="${1:-2.0.3}"
DEB_REV="${2:-1}"
OUT_DIR="${ROOT_DIR}/dist/debian-src"

if [ -z "${PUBLIC_REPO_DIR:-}" ]; then
    if [ -f "${ROOT_DIR}/Sources/VieLotusCore/Resources/English/scowl-en.txt" ] && [ -f "${ROOT_DIR}/CrossPlatform/packaging/debian/changelog" ]; then
        PUBLIC_REPO_DIR="${ROOT_DIR}"
    elif [ -d "/Volumes/SSD128/GIT/VieLotus-IM-Public" ]; then
        PUBLIC_REPO_DIR="/Volumes/SSD128/GIT/VieLotus-IM-Public"
    else
        PUBLIC_REPO_DIR="${ROOT_DIR}"
    fi
fi

rm -rf "${OUT_DIR}"
mkdir -p "${OUT_DIR}"

ORIG_NAME="vielotus_${VERSION}.orig.tar.gz"
ORIG_PATH="${OUT_DIR}/${ORIG_NAME}"
GITHUB_TAR_URL="https://github.com/stevedat/VieLotus-IM/archive/refs/tags/v${VERSION}.tar.gz"

if [ "${USE_LOCAL_GIT_ARCHIVE:-0}" != "1" ] && command -v curl >/dev/null 2>&1; then
    if curl -fsSL --max-time 20 "${GITHUB_TAR_URL}" -o "${ORIG_PATH}" 2>/dev/null && gzip -t "${ORIG_PATH}" >/dev/null 2>&1; then
        echo "✓ Đã tải upstream tarball chuẩn uscan từ tag v${VERSION}: ${ORIG_NAME}"
    else
        rm -f "${ORIG_PATH}"
    fi
fi

if [ ! -f "${ORIG_PATH}" ]; then
    if command -v git >/dev/null 2>&1 && git -C "${PUBLIC_REPO_DIR}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        git -C "${PUBLIC_REPO_DIR}" archive --format=tar.gz --prefix="VieLotus-IM-${VERSION}/" HEAD > "${ORIG_PATH}"
        echo "ℹ Tag v${VERSION} chưa phát hành trên GitHub; đã dựng ${ORIG_NAME} từ HEAD của ${PUBLIC_REPO_DIR} (cùng cấu trúc git archive)."
    else
        python3 - "${PUBLIC_REPO_DIR}" "${ORIG_PATH}" "${VERSION}" <<'TAREOF'
import io, os, stat, sys, tarfile

src_dir, orig_path, version = sys.argv[1], sys.argv[2], sys.argv[3]
prefix = f"VieLotus-IM-{version}"
skip_top = {".git", ".build", "dist"}
mtime = 1763102100

with tarfile.open(orig_path, "w:gz") as tf:
    for dp, dns, fns in os.walk(src_dir):
        rel_dp = os.path.relpath(dp, src_dir)
        top_part = rel_dp.split(os.sep)[0] if rel_dp != "." else ""
        if top_part in skip_top:
            dns[:] = []
            continue
        dns[:] = sorted(d for d in dns if d not in (".git", ".build", "dist", "__pycache__", "build"))
        for fn in sorted(fns):
            if fn == ".DS_Store" or fn.startswith("._"):
                continue
            fp = os.path.join(dp, fn)
            rel_fp = os.path.relpath(fp, src_dir).replace(os.sep, "/")
            ti = tf.gettarinfo(fp, arcname=f"{prefix}/{rel_fp}")
            st = os.lstat(fp)
            if not ti.issym():
                ti.mode = 0o755 if (st.st_mode & stat.S_IXUSR) else 0o644
            ti.uid = 0
            ti.gid = 0
            ti.uname = "root"
            ti.gname = "root"
            ti.mtime = mtime
            if ti.issym():
                tf.addfile(ti)
            else:
                with open(fp, "rb") as f:
                    tf.addfile(ti, fileobj=f)
TAREOF
        echo "ℹ Đã dựng ${ORIG_NAME} từ cây nguồn ${PUBLIC_REPO_DIR}."
    fi
fi

DEB_SRC_DIR="${PUBLIC_REPO_DIR}/CrossPlatform/packaging/debian"
if [ ! -d "${DEB_SRC_DIR}" ]; then
    DEB_SRC_DIR="${ROOT_DIR}/CrossPlatform/packaging/debian"
fi

python3 - "${DEB_SRC_DIR}" "${OUT_DIR}" "${VERSION}" "${DEB_REV}" "${ORIG_NAME}" <<'PYEOF'
import hashlib, io, lzma, os, re, sys, tarfile

deb_src, out_dir, version, deb_rev, orig_name = sys.argv[1:6]
full_ver = f"{version}-{deb_rev}"
deb_name = f"vielotus_{full_ver}.debian.tar.xz"
dsc_name = f"vielotus_{full_ver}.dsc"
orig_path = os.path.join(out_dir, orig_name)
deb_path = os.path.join(out_dir, deb_name)
dsc_path = os.path.join(out_dir, dsc_name)

mtime = 1763102100

def norm_tarinfo(ti):
    ti.uid = 0
    ti.gid = 0
    ti.uname = "root"
    ti.gname = "root"
    ti.mtime = mtime
    return ti

# Build debian.tar.xz cleanly without macOS resource-fork files
deb_buf = io.BytesIO()
with tarfile.open(fileobj=deb_buf, mode="w", format=tarfile.GNU_FORMAT) as tf:
    for dp, dns, fns in os.walk(deb_src):
        dns[:] = sorted(d for d in dns if d != "__pycache__")
        fns = sorted(f for f in fns if f != ".DS_Store" and not f.startswith("._"))
        for fn in fns:
            fp = os.path.join(dp, fn)
            sub_rel = os.path.relpath(fp, deb_src).replace(os.sep, "/")
            arc = f"debian/{sub_rel}"
            ti = tf.gettarinfo(fp, arcname=arc)
            ti.mode = 0o755 if (fn == "rules" or fn.endswith((".postinst", ".postrm", ".preinst", ".prerm"))) else 0o644
            with open(fp, "rb") as f:
                tf.addfile(norm_tarinfo(ti), fileobj=f)

deb_xz = lzma.compress(deb_buf.getvalue(), preset=6)
with open(deb_path, "wb") as f:
    f.write(deb_xz)

with open(orig_path, "rb") as f:
    orig_bytes = f.read()

def file_hashes(data):
    return (
        hashlib.md5(data).hexdigest(),
        hashlib.sha1(data).hexdigest(),
        hashlib.sha256(data).hexdigest(),
        len(data),
    )

o_md5, o_sha1, o_sha256, o_len = file_hashes(orig_bytes)
d_md5, d_sha1, d_sha256, d_len = file_hashes(deb_xz)

control_text = open(os.path.join(deb_src, "control"), "r", encoding="utf-8").read()
src_stanza = control_text.split("\n\n", 1)[0]

def parse_deb822_field(stanza, key):
    m = re.search(rf"^{re.escape(key)}:\s*(.*?)(?=\n[^\s#:]+:|\Z)", stanza, re.M | re.S)
    if not m:
        return ""
    lines = [ln.strip() for ln in m.group(1).splitlines() if ln.strip()]
    return " ".join(lines).replace(", ", ", ")

maintainer = parse_deb822_field(src_stanza, "Maintainer")
homepage = parse_deb822_field(src_stanza, "Homepage")
standards = parse_deb822_field(src_stanza, "Standards-Version")
vcs_browser = parse_deb822_field(src_stanza, "Vcs-Browser")
vcs_git = parse_deb822_field(src_stanza, "Vcs-Git")
build_deps = parse_deb822_field(src_stanza, "Build-Depends")
build_deps = ", ".join(p.strip() for p in build_deps.split(",") if p.strip())

dsc_content = f"""Format: 3.0 (quilt)
Source: vielotus
Binary: libvielotus0, ibus-vielotus, fcitx5-vielotus, vielotus
Architecture: any all
Version: {full_ver}
Maintainer: {maintainer}
Homepage: {homepage}
Standards-Version: {standards}
Vcs-Browser: {vcs_browser}
Vcs-Git: {vcs_git}
Build-Depends: {build_deps}
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

with open(dsc_path, "w", encoding="utf-8") as f:
    f.write(dsc_content)
PYEOF

GPG_KEY="${GPG_KEY:-9B5642F2EBA2A1EC}"
DSC_PATH="${OUT_DIR}/vielotus_${VERSION}-${DEB_REV}.dsc"
CHANGES_PATH="${OUT_DIR}/vielotus_${VERSION}-${DEB_REV}_source.changes"

if [ "${SKIP_GPG_SIGN:-0}" != "1" ] && command -v gpg >/dev/null 2>&1 && gpg --list-secret-keys "${GPG_KEY}" >/dev/null 2>&1; then
    gpg --batch --yes --default-key "${GPG_KEY}" --digest-algo SHA256 --clearsign "${DSC_PATH}"
    mv "${DSC_PATH}.asc" "${DSC_PATH}"
fi

python3 - "${DEB_SRC_DIR}" "${OUT_DIR}" "${VERSION}" "${DEB_REV}" "${ORIG_NAME}" <<'CHANGES_PYEOF'
import email.utils, hashlib, os, re, sys

deb_src, out_dir, version, deb_rev, orig_name = sys.argv[1:6]
full_ver = f"{version}-{deb_rev}"
deb_name = f"vielotus_{full_ver}.debian.tar.xz"
dsc_name = f"vielotus_{full_ver}.dsc"
changes_name = f"vielotus_{full_ver}_source.changes"

# Parse topmost stanza from debian/changelog dynamically
cl_text = open(os.path.join(deb_src, "changelog"), "r", encoding="utf-8").read()
stanza_match = re.match(
    r"^(\S+)\s+\(([^)]+)\)\s+([^;]+);\s+urgency=(\S+)\n(.*?)\n -- ([^<]+<[^>]+>)\s+([^\n]+)",
    cl_text,
    re.S,
)
if not stanza_match:
    raise SystemExit("Invalid debian/changelog format")
pkg_name, cl_ver, dist_name, urgency, body_raw, changed_by, _cl_date = stanza_match.groups()
if cl_ver != full_ver:
    print(f"⚠ Lưu ý: debian/changelog đang ở {cl_ver}, khác với tham số {full_ver}; _source.changes dùng {full_ver}.", file=sys.stderr)

closes_nums = []
for c in re.findall(r"Closes:\s*#(\d+)", body_raw, re.I):
    if c not in closes_nums:
        closes_nums.append(c)

changes_lines = [f" {pkg_name} ({full_ver}) {dist_name}; urgency={urgency}"]
for ln in body_raw.splitlines():
    if ln.strip() == "":
        changes_lines.append(" .")
    else:
        changes_lines.append(" " + ln)
changes_block = "\n".join(changes_lines)

def file_info(fname):
    p = os.path.join(out_dir, fname)
    with open(p, "rb") as f:
        data = f.read()
    return (
        hashlib.md5(data).hexdigest(),
        hashlib.sha1(data).hexdigest(),
        hashlib.sha256(data).hexdigest(),
        len(data),
        fname,
    )

files = [file_info(dsc_name), file_info(orig_name), file_info(deb_name)]
date_str = email.utils.formatdate(localtime=True)

sha1_lines = "\n".join(f" {s1} {sz} {fn}" for _, s1, _, sz, fn in files)
sha256_lines = "\n".join(f" {s256} {sz} {fn}" for _, _, s256, sz, fn in files)
files_lines = "\n".join(f" {md5} {sz} utils optional {fn}" for md5, _, _, sz, fn in files)
closes_line = f"Closes: {' '.join(closes_nums)}\n" if closes_nums else ""

changes_content = f"""Format: 1.8
Date: {date_str}
Source: {pkg_name}
Architecture: source
Version: {full_ver}
Distribution: {dist_name}
Urgency: {urgency}
Maintainer: {changed_by.strip()}
Changed-By: {changed_by.strip()}
Description:
 fcitx5-vielotus - VieLotusIM (Sen Viet) Vietnamese Input Method plugin for Fcitx5
 ibus-vielotus - VieLotusIM (Sen Viet) Vietnamese Input Method plugin for IBus
 libvielotus0 - VieLotusIM (Sen Viet) Vietnamese Input Method shared C-ABI core
 vielotus   - VieLotusIM (Sen Viet) - Next-Gen Vietnamese Input Method metapackage
{closes_line}Changes:
{changes_block}
Checksums-Sha1:
{sha1_lines}
Checksums-Sha256:
{sha256_lines}
Files:
{files_lines}
"""

with open(os.path.join(out_dir, changes_name), "w", encoding="utf-8") as f:
    f.write(changes_content)
CHANGES_PYEOF

if [ "${SKIP_GPG_SIGN:-0}" != "1" ] && command -v gpg >/dev/null 2>&1 && gpg --list-secret-keys "${GPG_KEY}" >/dev/null 2>&1; then
    gpg --batch --yes --default-key "${GPG_KEY}" --digest-algo SHA256 --clearsign "${CHANGES_PATH}"
    mv "${CHANGES_PATH}.asc" "${CHANGES_PATH}"
    echo "✓ Đã ký số GPG (${GPG_KEY}) cho .dsc và _source.changes"
fi

echo "================================================================="
echo "📦 Đã tạo bộ gói nguồn Debian 3.0 (quilt) tại ${OUT_DIR}:"
ls -lh "${OUT_DIR}"
echo "================================================================="
