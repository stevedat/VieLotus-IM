# VieLotusIM (Sen Việt)

[![English](https://img.shields.io/badge/Language-English-2d3748.svg)](README.md)
[![Tiếng Việt](https://img.shields.io/badge/Ngôn_ngữ-Tiếng_Việt-1F5B3A.svg)](README.vi.md)
[![macOS](https://img.shields.io/badge/macOS-Bộ_cài_(.pkg)-000000.svg?logo=apple&logoColor=white)](https://github.com/stevedat/VieLotus-IM/releases/latest/download/VieLotusIM.pkg)
[![Windows Store](https://img.shields.io/badge/Microsoft_Store-Sen_Việt-0067B8.svg?logo=windows&logoColor=white)](https://github.com/stevedat/VieLotus-IM/releases/latest)
[![Linux](https://img.shields.io/badge/Linux-Snap_%2F_.deb-E95420.svg?logo=ubuntu&logoColor=white)](https://snapcraft.io/vielotus)
[![App Store](https://img.shields.io/badge/App_Store-Sen_Việt-000000.svg?logo=apple&logoColor=white)](https://apps.apple.com/us/app/sen-vi%E1%BB%87t/id6821782799)
[![Google Play](https://img.shields.io/badge/Google_Play-Sen_Việt-1F5B3A.svg?logo=googleplay&logoColor=white)](https://play.google.com/store/apps/details?id=org.vielotus.hardwarekeyboard)

Bộ gõ tiếng Việt gọn nhẹ, an toàn bộ nhớ lấy **hệ sinh thái Apple (macOS, iOS, iPadOS)** làm kiến trúc tham chiếu trọng tâm bằng ngôn ngữ **Pure Swift 6**, đồng thời biên dịch trực tiếp cùng một lõi ngôn ngữ sang **Windows**, **Linux** và **Android** — vận hành thuần qua giao thức bàn phím gốc của từng hệ điều hành, **không dùng bẫy phím ngầm (0 Global Hooks)** và **bảo mật 100% ngoại tuyến**.

📄 **[Hồ sơ Thực nghiệm & Mô phỏng](https://stevedat.github.io/VieLotus-IM/)** · 📐 **[Chuyên khảo Kiến trúc & Kiểm định](https://stevedat.github.io/VieLotus-IM/research.html)**

---

## Điểm Cốt Lõi

- **Giao Thức Hệ Thống Gốc (`0 Accessibility / 0 Full Access / 0 Keyboard Hook`)**: Vận hành 100% qua kênh dịch vụ bàn phím chính thống (`InputMethodKit` trên macOS, `UIInputViewController` trên iOS/iPadOS, `Win32 TSF` trên Windows, `IBus / Fcitx5` trên Linux, `InputMethodService` trên Android) thay vì cài bẫy phím toàn cục. Không gặp lỗi kẹt quyền TCC trên macOS, tương thích tự nhiên với Linux Wayland và không phát sinh kết nối mạng nền.
- **Song Ngữ Theo Từ Vựng & Ngữ Cảnh (Telex & VNI)**: Loại bỏ các tổ hợp âm tiết không tồn tại trong tiếng Việt (`turn` giữ nguyên là `turn`, không biến thành `"tủn"`) và nhận diện mẫu `-s-t` giữa từ tiếng Anh (`last`, `best`, `cost`); đồng thời phân xử các cặp trùng phím 100% (`rest`/`rét`, `if`/`ì`, `as`/`á`) bằng ngữ cảnh từ đứng trước.
- **Thích Ứng Theo Từng Ứng Dụng (`< 0.2 ms` p99)**: Tự động chọn `Direct Replacement` (AppKit, Safari, Office) hoặc `Marked Text` chuẩn W3C (Chromium, Electron, React/ProseMirror, GPU Terminal) kết hợp đồng bộ vị trí con trỏ UTF-16 và bộ đệm hoàn tác 20 từ trong RAM.

---

## Danh Mục Dòng Máy, Hệ Điều Hành & Môi Trường Đã Kiểm Chứng

| Nền tảng & Hệ điều hành | Dòng máy & Kiến trúc CPU | Giao thức chuẩn | Ứng dụng & Môi trường đã kiểm thử |
| :--- | :--- | :--- | :--- |
| **macOS**<br>13 Ventura, 14 Sonoma, 15 Sequoia | **Apple Silicon** (`M1 / M2 / M3 / M4` — MacBook Air/Pro, Mac mini, iMac, Mac Studio)<br>**Intel** (`x86_64`) | `InputMethodKit` (`IMKServer`) | **Native**: Safari, Notes, Pages, Mail, Xcode, Spotlight<br>**Web/Electron**: Chrome, Arc, Edge, VS Code, Cursor, Slack, Discord, Notion, Zalo, Teams<br>**Terminal**: Terminal.app, iTerm2, Ghostty, Kitty, Alacritty, Warp<br>**Office**: Word, Excel, PowerPoint |
| **Windows**<br>Windows 10 (21H2+) & Windows 11 (22H2–24H2) | **Intel / AMD** (`x64`)<br>**ARM64** (Snapdragon X Elite/Plus, Surface Pro ARM, máy ảo Parallels trên Mac M-series) | `Win32 TSF` (`ITfTextInputProcessorEx`) | **WinUI 3 / UWP**: Windows 11 Notepad, Windows Terminal, Windows Search, Edge<br>**Win32 / Desktop**: Office 365, Chrome, VS Code, File Explorer, Zalo PC |
| **Linux**<br>Ubuntu 22.04/24.04 LTS, Debian 12, Mint, Pop!_OS, Fedora, Arch | **x86_64** (`amd64` PC/Laptop)<br>**ARM64** (`aarch64` — Raspberry Pi 4/5, máy trạm ARM) | `IBus` & `Fcitx5` (`libVieLotusCAPI.so`) | **Hiển thị**: X11 & Wayland (GNOME, KDE Plasma)<br>**Ứng dụng**: Firefox, Chromium, VS Code, LibreOffice, GNOME Terminal, Konsole, Ghostty |
| **iOS & iPadOS**<br>iOS / iPadOS 16, 17, 18 | **iPhone** (XS → 16 Pro Max)<br>**iPad** (Air, mini, Pro M1–M4) | `UIKit` (`UIInputViewController`) | Bàn phím cảm ứng (60/120Hz) & bàn phím cứng Magic Keyboard / Bluetooth (Không cần bật Full Access) |
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
- Tải [`VieLotus-Setup-x64.exe`](https://github.com/stevedat/VieLotus-IM/releases/latest/download/VieLotus-Setup-x64.exe) hoặc [`VieLotus-Setup-arm64.exe`](https://github.com/stevedat/VieLotus-IM/releases/latest/download/VieLotus-Setup-arm64.exe) tại [Releases](https://github.com/stevedat/VieLotus-IM/releases/latest) (hoặc cài qua **Microsoft Store**).
- Chạy bộ cài và nhấn **`Win + Space`** để chuyển sang **Sen Việt**.

### 3. Linux (Ubuntu / Debian / Snap — `amd64` & `arm64`)
- **Cài đặt tự động 1 dòng lệnh (Ubuntu / Debian `.deb`)**:
  ```bash
  curl -fsSL https://stevedat.github.io/VieLotus-IM/install.sh | sh
  ```
- **Qua Snap Store**:
  ```bash
  sudo snap install vielotus
  ```
- **Cài gói `.deb` thủ công qua `apt`**:
  ```bash
  sudo apt update && sudo apt install ./vielotus_1.1.1_amd64.deb   # hoặc ./vielotus_1.1.1_arm64.deb
  ```
- **Lệnh điều khiển nhanh**: `vielotus-settings` (cửa sổ cài đặt GTK3) · `vielotus --telex` · `vielotus --vni` · `vielotus --status`.

### 4. iOS / iPadOS & Android
- **iOS & iPadOS**: Tải trên [App Store](https://apps.apple.com/us/app/sen-vi%E1%BB%87t/id6821782799) → **Cài đặt → Cài đặt chung → Bàn phím → Thêm bàn phím mới... → Sen Việt**.
- **Android**: Tải trên [Google Play](https://play.google.com/store/apps/details?id=org.vielotus.hardwarekeyboard) và bật **Sen Việt** trong **Cài đặt → Hệ thống → Bàn phím**.

---

## Giấy Phép

Phát hành theo giấy phép [MIT License](LICENSE). Phát triển và duy trì bởi **Steve Dat** ([@stevedat](https://github.com/stevedat)).
