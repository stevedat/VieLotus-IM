# VieLotusIM (Sen Việt)

[![English](https://img.shields.io/badge/Language-English-2d3748.svg)](README.md)
[![Tiếng Việt](https://img.shields.io/badge/Ngôn_ngữ-Tiếng_Việt-1F5B3A.svg)](README.vi.md)
[![macOS](https://img.shields.io/badge/macOS-Bộ_cài_(.pkg)-000000.svg?logo=apple&logoColor=white)](https://github.com/stevedat/VieLotus-IM/releases/latest/download/VieLotusIM.pkg)
[![Windows Store](https://img.shields.io/badge/Microsoft_Store-Sen_Việt-0067B8.svg?logo=windows&logoColor=white)](https://apps.microsoft.com/detail/9PF5K64GXXSH)
[![Linux](https://img.shields.io/badge/Linux-PPA_%2F_.deb-E95420.svg?logo=ubuntu&logoColor=white)](https://launchpad.net/~stevedat/+archive/ubuntu/vielotus)
[![App Store](https://img.shields.io/badge/App_Store-Sen_Việt-000000.svg?logo=apple&logoColor=white)](https://apps.apple.com/us/app/sen-vi%E1%BB%87t/id6821782799)
[![Google Play](https://img.shields.io/badge/Google_Play-Sen_Việt-1F5B3A.svg?logo=googleplay&logoColor=white)](https://play.google.com/store/apps/details?id=org.vielotus.hardwarekeyboard)

Bộ gõ tiếng Việt gọn nhẹ, an toàn bộ nhớ lấy **hệ sinh thái Apple (macOS, iOS, iPadOS)** làm kiến trúc tham chiếu trọng tâm bằng ngôn ngữ **Pure Swift 6**, đồng thời biên dịch trực tiếp cùng một lõi ngôn ngữ sang **Windows**, **Linux** và **Android** — vận hành thuần qua giao thức bàn phím gốc của từng hệ điều hành, **không dùng bẫy phím ngầm (0 Global Hooks)** và **bảo mật 100% ngoại tuyến**.

📄 **[Hồ sơ Thực nghiệm & Mô phỏng](https://stevedat.github.io/VieLotus-IM/)** · 📐 **[Chuyên khảo Kiến trúc & Kiểm định](https://stevedat.github.io/VieLotus-IM/research.html)**

---

## Điểm Cốt Lõi

- **Giao Thức Hệ Thống Gốc (`0 Accessibility / Gõ Cơ Bản Không Cần Full Access / 0 Keyboard Hook`)**: Vận hành 100% qua kênh dịch vụ bàn phím chính thống (`InputMethodKit` trên macOS, `UIInputViewController` trên iOS/iPadOS, `Win32 TSF` trên Windows, `IBus / Fcitx5` trên Linux, `InputMethodService` trên Android) thay vì cài bẫy phím toàn cục. Không gặp lỗi kẹt quyền TCC trên macOS, tương thích tự nhiên với Linux Wayland và không phát sinh kết nối mạng nền.
- **Song Ngữ Theo Từ Vựng & Ngữ Cảnh (Telex & VNI)**: Loại bỏ các tổ hợp âm tiết không tồn tại trong tiếng Việt (`turn` giữ nguyên là `turn`, không biến thành `"tủn"`) và nhận diện mẫu `-s-t` giữa từ tiếng Anh (`last`, `best`, `cost`); đồng thời phân xử các cặp trùng phím 100% (`rest`/`rét`, `if`/`ì`, `as`/`á`) bằng ngữ cảnh từ đứng trước.
- **Thích Ứng Theo Từng Ứng Dụng (`< 0.2 ms` p99)**: Tự động chọn `Direct Replacement` (AppKit, Safari, Office) hoặc `Marked Text` chuẩn W3C (Chromium, Electron, React/ProseMirror, GPU Terminal) kết hợp đồng bộ vị trí con trỏ UTF-16 và bộ đệm hoàn tác 20 từ trong RAM.

---

## Danh Mục Dòng Máy, Hệ Điều Hành & Môi Trường Đã Kiểm Chứng

| Nền tảng & Hệ điều hành | Dòng máy & Kiến trúc CPU | Giao thức chuẩn | Ứng dụng & Môi trường đã kiểm thử |
| :--- | :--- | :--- | :--- |
| **macOS**<br>13 Ventura, 14 Sonoma, 15 Sequoia | **Apple Silicon** (`M1 / M2 / M3 / M4` — MacBook Air/Pro, Mac mini, iMac, Mac Studio)<br>**Intel** (`x86_64`) | `InputMethodKit` (`IMKServer`) | **Native**: Safari, Notes, Pages, Mail, Xcode, Spotlight<br>**Web/Electron**: Chrome, Arc, Edge, VS Code, Cursor, Slack, Discord, Notion, Zalo, Teams<br>**Terminal**: Terminal.app, iTerm2, Ghostty, Kitty, Alacritty, Warp<br>**Office**: Word, Excel, PowerPoint |
| **Windows**<br>Windows 10 (21H2+) & Windows 11 (22H2–24H2) | **Intel / AMD** (`x64`)<br>**ARM64** (Snapdragon X Elite/Plus, Surface Pro ARM, máy ảo Parallels trên Mac M-series) | `Win32 TSF` (`ITfTextInputProcessorEx`) | **WinUI 3 / UWP**: Windows 11 Notepad, Windows Terminal, Windows Search, Edge<br>**Win32 / Desktop**: Office 365, Chrome, VS Code, File Explorer, Zalo PC |
| **Linux**<br>Ubuntu 22.04/24.04 LTS, Debian 12, Mint, Pop!_OS, Fedora, Arch | **x86_64** (`amd64` PC/Laptop)<br>**ARM64** (`aarch64` — Raspberry Pi 4/5, máy trạm ARM) | `IBus` & `Fcitx5` (`libVieLotusCAPI.so`) | **Hiển thị**: X11 & Wayland (GNOME, KDE Plasma)<br>**Ứng dụng**: Firefox, Chromium, VS Code, LibreOffice, GNOME Terminal, Konsole, Ghostty |
| **iOS & iPadOS**<br>iOS / iPadOS 16, 17, 18 | **iPhone** (XS → 16 Pro Max)<br>**iPad** (Air, mini, Pro M1–M4) | `UIKit` (`UIInputViewController`) | Bàn phím cảm ứng (60/120Hz) & bàn phím cứng Magic Keyboard / Bluetooth (Gõ cơ bản không cần bật Full Access) |
| **Android**<br>Android 8.0 (API 26) – Android 15 | **ARM64 / ARMv7 / x86_64** (Samsung Galaxy Phone/Tab/DeX, Pixel, Xiaomi, OPPO) | `InputMethodService` (JNI C-ABI) | Bàn phím cảm ứng & bàn phím cứng rời USB / Bluetooth trên điện thoại và máy tính bảng / Samsung DeX |

---

## Tóm Tắt Thực Nghiệm (9.091 Ca Kiểm Thử)

| Nhóm chỉ số | Điều kiện đo kiểm | Kết quả |
| :--- | :--- | :--- |
| **Bộ kiểm thử chính (`Overall Primary`)** | Chuyển đổi âm tiết (400), Giữ nguyên tiếng Anh (362), Hủy dấu (67), Khôi phục từ (7.213), Từ lưỡng nghĩa có ngữ cảnh (1.049) | **9.091 / 9.091 (100.00%)** |
| **Đối xứng hai chiều (`ambiguous_both_sides`)** | 375 từ trùng phím viết thường chạy lặp lại ở cả 2 chiều: *có* ngữ cảnh tiếng Anh VÀ *không* ngữ cảnh (`vn_survives_collision`) | **365 / 375 (97.33%)** |
| **Đường gõ tiếng Việt duy nhất (`whitelist_safe = never`)** | Các âm tiết tiếng Việt chỉ có duy nhất một cách gõ Telex/VNI | **182 / 182 (100.00% — 0 mất từ)** |

---

## Cài Đặt Nhanh

### 1. macOS (macOS 13 trở lên)
- **Qua Homebrew**:
  ```bash
  brew install stevedat/tap/vielotus
  ```
- **Bộ cài trực tiếp (`.pkg`)**: Tải [`VieLotusIM.pkg`](https://github.com/stevedat/VieLotus-IM/releases/latest/download/VieLotusIM.pkg), mở để cài đặt tự động, sau đó vào **System Settings → Keyboard → Input Sources → Edit... → (+) → Tiếng Việt → Sen Việt**.

### 2. Windows (Windows 10 / 11 — `x64` & `ARM64`)
- **Bộ cài ký số bởi Microsoft Corporation (Khuyên dùng — 0 cảnh báo SmartScreen)**: Tải [`VieLotus-Store-Setup.exe`](https://github.com/stevedat/VieLotus-IM/releases/latest/download/VieLotus-Store-Setup.exe) hoặc cài trực tiếp trên [**Microsoft Store**](https://apps.microsoft.com/detail/9PF5K64GXXSH).
- **Bộ cài Offline độc lập**: Tải [`VieLotus-Setup-x64.exe`](https://github.com/stevedat/VieLotus-IM/releases/latest/download/VieLotus-Setup-x64.exe) (`x64`) hoặc [`VieLotus-Setup-arm64.exe`](https://github.com/stevedat/VieLotus-IM/releases/latest/download/VieLotus-Setup-arm64.exe) (`ARM64`) tại [Releases](https://github.com/stevedat/VieLotus-IM/releases/latest).
- Chạy bộ cài và nhấn **`Win + Space`** để chuyển sang **Sen Việt**.

### 3. Linux (Ubuntu / Debian / Mint / Fedora / Arch / openSUSE — `amd64` & `arm64`)
- **Kho Launchpad PPA chính thức cho Ubuntu (`Ubuntu 22.04 LTS, 24.04 LTS, 26.04 LTS & 26.10` — `amd64` & `arm64`)**:
  ```bash
  sudo rm -f /etc/apt/sources.list.d/vielotus.list   # Dọn nguồn APT tĩnh v1.x cũ (nếu từng cài bản 1.1.1)
  sudo add-apt-repository -y ppa:stevedat/vielotus
  sudo apt update
  sudo apt install -y vielotus   # Tự động cập nhật qua APT / Synaptic Package Manager
  ```
- **Cài đặt tự động 1 dòng lệnh (Tự nhận diện `apt`, `dnf`, `pacman`, `zypper` & `x86_64` / `aarch64`)**:
  ```bash
  curl -fsSL https://stevedat.github.io/VieLotus-IM/install.sh | sh
  ```
- **Cài gói `.deb` thủ công qua `apt` (Ubuntu / Debian / Mint / Pop!_OS)**:
  ```bash
  sudo apt update && sudo apt install ./vielotus_2.0.3_amd64.deb   # hoặc ./vielotus_2.0.3_arm64.deb
  ```
- **Arch Linux / Manjaro (`PKGBUILD`)**: `cd CrossPlatform/packaging/arch && makepkg -si`
- **Lệnh điều khiển nhanh**: `vielotus-settings` (cửa sổ cài đặt GTK3) · `vielotus-settings --telex` · `vielotus-settings --vni` · `vielotus-settings --doctor`.
- **Lưu ý lần đầu cài trên Ubuntu / GNOME (Wayland)**: Bộ cài tự động nạp lại IBus và đăng ký **Sen Việt (`🇻🇳 tex`)** ngay lập tức (`Super + Space` để chuyển gõ). Nếu thanh trên cùng vẫn lưu bộ nhớ đệm cũ hoặc Cài đặt Bàn phím tạm hiện chữ thường `vielotus`, bạn chỉ cần **Đăng xuất (Log Out) rồi Đăng nhập lại 1 lần duy nhất** (hoặc bấm **Riêng Linux ⚙ → Tự sửa & Kích hoạt** trong ứng dụng `Sen Việt`).

### 4. iOS / iPadOS & Android
- **iOS & iPadOS**: Tải trên [App Store](https://apps.apple.com/us/app/sen-vi%E1%BB%87t/id6821782799) → **Cài đặt → Cài đặt chung → Bàn phím → Thêm bàn phím mới... → Sen Việt**.
- **Android**: Tải trên [Google Play](https://play.google.com/store/apps/details?id=org.vielotus.hardwarekeyboard) và bật **Sen Việt** trong **Cài đặt → Hệ thống → Bàn phím**.

---

## Minh Bạch Mã Nguồn (Open-Core) & Tự Biên Dịch Từ Mã Nguồn

VieLotusIM áp dụng mô hình **Open-Core minh bạch** để bất kỳ kỹ sư bảo mật, quản trị viên gói Linux hay lập trình viên nào cũng có thể tự kiểm tra an toàn (Audit) và tự biên dịch (Build from Source) trên cả 3 hệ điều hành máy tính:

| Nền tảng | Lớp Giao Tiếp Hệ Điều Hành (OS Shell & UI) | Lõi Xử Lý Ngôn Ngữ (Engine Core) | Mức độ mở & Khả năng tự biên dịch |
| :--- | :--- | :--- | :--- |
| **Linux**<br>(`IBus` & `Fcitx5`) | Mã nguồn mở **100% (MIT)**<br>`CrossPlatform/ibus-vielotus/`<br>`CrossPlatform/fcitx5-vielotus/`<br>`CrossPlatform/capi-native/` | Mã nguồn mở **100% C++20 (MIT / Debian DFSG #2)**<br>`Sources/VieLotusCoreWindows/` + từ điển gốc UTF-8 NFC (`lexicon/*.txt`) + script sinh bảng băm tất định (`generate_lexicon_hashes.py`) | **100% Mã nguồn mở hoàn toàn (0 binary blob)**.<br>Tự biên dịch trực tiếp từ mã nguồn chuẩn Debian `dpkg-buildpackage`, Launchpad PPA hoặc `cmake` + `ninja`. |
| **Windows**<br>(`Win32 TSF`) | Mã nguồn mở **100% (MIT)**<br>`CrossPlatform/windows-tsf/` | Mã nguồn mở **100% C++20 (MIT)**<br>`Sources/VieLotusCoreWindows/` (không làm mờ mã nguồn / unobfuscated) | **100% Mã nguồn mở hoàn toàn (0 binary blob)**.<br>Tự biên dịch DLL & bộ cài trực tiếp bằng CMake / MSVC (`./scripts/build_windows.ps1`). |
| **macOS**<br>(`InputMethodKit`) | Mã nguồn mở **100% (MIT)**<br>`Sources/VieLotusIM/` (`IMKServer`, `IMKInputController`, Settings UI, `DiagnosticLogger`) & `Sources/VieLotusTrace/` | Binary XCFramework tiền biên dịch (`arm64` + `x86_64`)<br>`Frameworks/VieLotusCore.xcframework` (chia sẻ chung lõi Swift 6 với bản thương mại trên iOS / iPadOS App Store) | **Open-Core có thể kiểm toán bảo mật 100%**.<br>Toàn bộ lớp giao tiếp macOS mở hoàn toàn để xác minh **0 `CGEventTap`**, **0 quyền Accessibility**, **0 ghi phím**, **0 kết nối mạng**, và biên dịch ra `VieLotusIM.app` bằng `swift build`. |

### Lệnh Tự Biên Dịch (Build from Source)

1. **Xác thực toàn vẹn XCFramework tiền biên dịch (`SHA-256`)**:
   ```bash
   shasum -a 256 -c Frameworks/checksums.sha256
   ```
2. **macOS (`VieLotusIM.app` Universal `arm64` + `x86_64`)**:
   ```bash
   swift build -c release --product VieLotusIM
   ./scripts/build_imk.sh
   ```
3. **Linux (Từ mã nguồn C/C++20 thuần — Debian/Ubuntu `.deb` hoặc CMake)**:
   ```bash
   # Cách 1: Đóng gói chuẩn Debian / Ubuntu (tự sinh bảng băm từ điển từ lexicon/*.txt)
   dpkg-buildpackage -us -uc -b

   # Cách 2: Biên dịch trực tiếp bằng CMake
   cmake -B build/capi -S CrossPlatform/capi-native -DCMAKE_BUILD_TYPE=Release && cmake --build build/capi
   ```
4. **Windows (`Win32 TSF` `x64` & `ARM64` từ mã nguồn C++20)**:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\scripts\build_windows.ps1
   ```

---

## Giấy Phép

Phát hành theo giấy phép **[MIT License](LICENSE) (Mô hình Open-Core)**: toàn bộ mã nguồn trên kho lưu trữ (100% bộ gõ Linux & Windows cùng toàn bộ lớp giao tiếp hệ điều hành macOS `InputMethodKit`) và gói nhị phân `VieLotusCore.xcframework` đi kèm được cấp phép tự do sử dụng, tự biên dịch và phân phối theo điều khoản MIT. Phát triển và duy trì bởi **Steve Dat** ([@stevedat](https://github.com/stevedat)).
