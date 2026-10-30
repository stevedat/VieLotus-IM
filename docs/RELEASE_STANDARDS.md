# 🔐 Public Release Standards — VieLotusIM (Sen Việt)

> **Tài liệu quy chuẩn bắt buộc** cho mọi bản phát hành công khai (GitHub
> Release, PPA, Debian Mentors). Mọi maintainer và CI pipeline phải tuân thủ.
>
> Lần cập nhật: 2026-10-30 — Bài học từ v2.0.0 release.

---

## 1. GitHub Release — Danh Sách Tệp Cho Phép (Allowlist)

Mỗi GitHub Release tag (ví dụ `v2.0.0`) **CHỈ ĐƯỢC** chứa đúng **7 tệp**:

| # | Tên tệp | Mô tả |
|---|---------|--------|
| 1 | `checksums.sha256` | SHA-256 checksums cho tất cả 6 installer |
| 2 | `VieLotusIM.pkg` | macOS Universal Installer (Apple Silicon + Intel) |
| 3 | `VieLotus-Store-Setup.exe` | Windows Microsoft Store Signed Installer |
| 4 | `VieLotus-Setup-x64.exe` | Windows Offline Installer (x64) |
| 5 | `VieLotus-Setup-arm64.exe` | Windows Offline Installer (ARM64) |
| 6 | `vielotus_<ver>_amd64.deb` | Linux All-in-One .deb (amd64) |
| 7 | `vielotus_<ver>_arm64.deb` | Linux All-in-One .deb (arm64) |

### ⛔ TUYỆT ĐỐI KHÔNG ĐƯỢC upload lên GitHub Releases:

| Loại tệp | Lý do cấm |
|-----------|-----------|
| `*.orig.tar.xz` | **CHỨA MÃ NGUỒN ENGINE (WindowsNativeEngine.cpp)** — lộ IP |
| `*.debian.tar.xz` | Packaging internals, không dành cho end-user |
| `*.dsc` | Debian source control file, không dành cho end-user |
| `*.snap` | Chưa publish chính thức, gây nhầm lẫn |
| `Packages`, `Packages.gz`, `Release` | APT repo metadata, dùng PPA thay thế |
| Split `.deb`: `libvielotus0_*`, `ibus-vielotus_*`, `fcitx5-vielotus_*` | Internals, user chỉ cần metapackage `vielotus_*` |
| Bất kỳ source tarball nào | Open-Core model: source chỉ qua Mentors/PPA |

---

## 2. Open-Core Security Boundary

```
┌─────────────────────────────────────────────────────────────┐
│  PROPRIETARY (Private Repo Only)                            │
│  ├─ Sources/VieLotusCore/**  (Swift engine)                 │
│  ├─ CrossPlatform/WindowsNativeEngine.cpp  (C++20 engine)   │
│  ├─ Binaries/linux/libvielotus0_*.deb (shared library)      │
│  ├─ Binaries/linux/ibus-vielotus_*.deb                      │
│  └─ Binaries/linux/fcitx5-vielotus_*.deb                    │
├─────────────────────────────────────────────────────────────┤
│  PUBLIC (Open-Core Repo — github.com/stevedat/VieLotus-IM)  │
│  ├─ CrossPlatform/WindowsNativeEngine.h  (header only, OK)  │
│  ├─ Scripts, packaging specs, CI workflows                   │
│  ├─ Prebuilt binaries (*.xcframework, *.dll, *.so)           │
│  └─ Documentation, README, LICENSE (MIT for shell/packaging) │
└─────────────────────────────────────────────────────────────┘
```

**Quy tắc vàng:** `WindowsNativeEngine.cpp` và toàn bộ `Sources/VieLotusCore/`
KHÔNG BAO GIỜ xuất hiện trong:
- Public git history (bất kỳ commit nào)
- GitHub Release assets
- Bất kỳ URL công khai nào

---

## 3. CI Workflow (`release.yml`) — Quy Tắc Glob

```yaml
# ✅ ĐÚNG — chỉ match metapackage all-in-one
cp Binaries/linux/vielotus_*.deb .build/dist/

# ❌ SAI — sẽ capture split packages
cp Binaries/linux/*.deb .build/dist/
```

```yaml
# ✅ ĐÚNG — release assets chỉ có metapackage
files: |
  .build/dist/VieLotusIM.pkg
  .build/dist/VieLotus-Store-Setup.exe
  .build/dist/VieLotus-Setup-*.exe
  .build/dist/vielotus_*.deb
  .build/dist/checksums.sha256

# ❌ SAI — *.deb sẽ leak split packages
files: |
  .build/dist/*.deb
```

---

## 4. Debian Source Packages — Kênh Phân Phối

| Kênh | Chứa source? | Công khai? | Cho phép? |
|------|-------------|-----------|----------|
| `mentors.debian.net` | ✅ `orig.tar.xz` | Có (nhưng cần tài khoản DD) | ✅ Đúng kênh |
| `ppa.launchpad.net` | ✅ `orig.tar.xz` | Có (ký số GPG) | ✅ Đúng kênh |
| GitHub Releases | ❌ KHÔNG ĐƯỢC | Hoàn toàn công khai | ⛔ CẤM |
| GitHub repo commits | ❌ KHÔNG ĐƯỢC | Hoàn toàn công khai | ⛔ CẤM |

---

## 5. Post-Release Checklist (Bắt Buộc Sau Mỗi Release)

Chạy ngay sau khi GitHub Actions Release workflow hoàn thành:

```bash
# 1. Kiểm tra danh sách assets (PHẢI đúng 7 tệp)
gh release view v<VERSION> --json assets -q '.assets[].name' | sort

# 2. Đối chiếu với allowlist
EXPECTED="VieLotusIM.pkg
VieLotus-Setup-arm64.exe
VieLotus-Setup-x64.exe
VieLotus-Store-Setup.exe
checksums.sha256
vielotus_<VERSION>_amd64.deb
vielotus_<VERSION>_arm64.deb"

ACTUAL=$(gh release view v<VERSION> --json assets -q '.assets[].name' | sort)
if [ "$ACTUAL" = "$EXPECTED" ]; then
  echo "✅ Release assets CLEAN"
else
  echo "⛔ MISMATCH — kiểm tra và xóa assets thừa!"
  diff <(echo "$EXPECTED") <(echo "$ACTUAL")
fi

# 3. Kiểm tra KHÔNG có source tarball
gh release view v<VERSION> --json assets -q '.assets[].name' | grep -E '\.(tar\.(xz|gz)|\.dsc|\.snap|Packages)' && echo "⛔ CÓ TỆP CẤM!" || echo "✅ Không có tệp cấm"

# 4. Verify checksums
gh release download v<VERSION> -p checksums.sha256 -D /tmp/release-check/
cd /tmp/release-check/
gh release download v<VERSION>
shasum -a 256 -c checksums.sha256
```

---

## 6. Benchmark Citation Rule (Release Notes)

Mọi release notes **BẮT BUỘC** trích dẫn đầy đủ 3 chỉ số:

```markdown
- **Overall Primary Suite:** **100.00% (9,091 / 9,091)**
- **Symmetric No-Context (`vn_survives_collision` / `ambiguous_both_sides`):** **97.33% (365 / 375)**
- **Single-Path Vietnamese Preservation (`whitelist_safe = never`):** **100.00% (182 / 182 — 0 critical losses)**
```

**KHÔNG ĐƯỢC** trích dẫn riêng lẻ "100.00%" mà thiếu hai chỉ số đối xứng.

---

## 7. `docs/apt/` — Đã Loại Bỏ

Thư mục `docs/apt/` (chứa `Packages`, `Packages.gz`, `Release`) đã bị **xóa
khỏi public repo** từ v2.0.0. Người dùng Linux sử dụng:

```bash
# Cách cài chính thức — Launchpad PPA
sudo add-apt-repository ppa:stevedat/vielotus
sudo apt update
sudo apt install vielotus

# Hoặc tải .deb trực tiếp từ GitHub Release
wget https://github.com/stevedat/VieLotus-IM/releases/latest/download/vielotus_2.0.0_amd64.deb
sudo apt install ./vielotus_2.0.0_amd64.deb
```

---

## 8. `softprops/action-gh-release@v2` — Hành Vi Cần Biết

- **KHÔNG tự xóa assets cũ** — nếu release trước đã upload `*.snap`,
  `*.orig.tar.xz`, chúng **sẽ vẫn còn** sau khi re-run.
- Luôn chạy Post-Release Checklist (mục 5) sau mỗi release.
- Nếu cần xóa assets thừa:
  ```bash
  gh release delete-asset v<VERSION> <tên-tệp-cần-xóa>
  ```

---

## Revision History

| Ngày | Thay đổi |
|------|---------|
| 2026-10-30 | v1.0 — Tạo tiêu chuẩn sau sự cố v2.0.0 (lộ `orig.tar.xz` + split debs trên GitHub Release) |
