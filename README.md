# VieLotusIM (Sen Việt)

[![English](https://img.shields.io/badge/Language-English-1F5B3A.svg)](README.md)
[![Tiếng Việt](https://img.shields.io/badge/Ngôn_ngữ-Tiếng_Việt-2d3748.svg)](README.vi.md)
[![macOS](https://img.shields.io/badge/macOS-Installer_(.pkg)-000000.svg?logo=apple&logoColor=white)](https://github.com/stevedat/VieLotus-IM/releases/latest/download/VieLotusIM.pkg)
[![Windows Store](https://img.shields.io/badge/Microsoft_Store-Sen_Việt-0067B8.svg?logo=windows&logoColor=white)](https://github.com/stevedat/VieLotus-IM/releases/latest)
[![Linux](https://img.shields.io/badge/Linux-Snap_%2F_.deb-E95420.svg?logo=ubuntu&logoColor=white)](https://snapcraft.io/vielotus)
[![App Store](https://img.shields.io/badge/App_Store-Sen_Việt-000000.svg?logo=apple&logoColor=white)](https://apps.apple.com/us/app/sen-vi%E1%BB%87t/id6821782799)
[![Google Play](https://img.shields.io/badge/Google_Play-Sen_Việt-1F5B3A.svg?logo=googleplay&logoColor=white)](https://play.google.com/store/apps/details?id=org.vielotus.hardwarekeyboard)

A lightweight, memory-safe Vietnamese input method anchored in the **Apple ecosystem (macOS, iOS, iPadOS)** as its primary **Pure Swift 6** reference architecture, and compiled natively across **Windows**, **Linux**, and **Android** — operating strictly through official OS input protocols with **zero global keystroke hooks** and **100% offline privacy**.

📄 **[Technical Dossier & Interactive Specimen](https://stevedat.github.io/VieLotus-IM/)** · 📐 **[Architecture & Benchmark Monograph](https://stevedat.github.io/VieLotus-IM/research.html)**

---

## Core Highlights

- **Zero Global Hooks (`0 Accessibility / 0 Full Access / 0 Keyboard Hook`)**: Uses official OS input contracts (`InputMethodKit` on macOS, `UIInputViewController` on iOS/iPadOS, `Win32 TSF` on Windows, `IBus / Fcitx5` on Linux, `InputMethodService` on Android) rather than global event taps. Immune to macOS TCC permission breakage, Linux Wayland isolation issues, and operates 100% offline.
- **Lexical & Context-Aware Bilingual Typing (Telex & VNI)**: Rejects non-existent Vietnamese syllables (`turn` stays `turn`, never `"tủn"`) and mid-word English `-s-t` patterns (`last`, `best`, `cost`), while resolving true single-path collisions (`rest`/`rét`, `if`/`ì`, `as`/`á`) via preceding context.
- **Adaptive Per-App Presentation (`< 0.2 ms` p99)**: Dynamically switches between `Direct Replacement` (AppKit, Safari, Office) and standards-compliant `Marked Text` (Chromium, Electron, React/ProseMirror, GPU terminals) with UTF-16 cursor synchronization and a 20-word backspace ring buffer.

---

## Verified Hardware, OS & Environment Matrix

| Platform & OS | Verified Hardware & CPU | Native Framework | Verified Applications & Environments |
| :--- | :--- | :--- | :--- |
| **macOS**<br>13 Ventura, 14 Sonoma, 15 Sequoia | **Apple Silicon** (`M1 / M2 / M3 / M4` — MacBook Air/Pro, Mac mini, iMac, Mac Studio)<br>**Intel** (`x86_64`) | `InputMethodKit` (`IMKServer`) | **Native**: Safari, Notes, Pages, Mail, Xcode, Spotlight<br>**Web/Electron**: Chrome, Arc, Edge, VS Code, Cursor, Slack, Discord, Notion, Zalo, Teams<br>**Terminals**: Terminal.app, iTerm2, Ghostty, Kitty, Alacritty, Warp<br>**Office**: Word, Excel, PowerPoint |
| **Windows**<br>Windows 10 (21H2+) & Windows 11 (22H2–24H2) | **Intel / AMD** (`x64`)<br>**ARM64** (Snapdragon X Elite/Plus, Surface Pro ARM, Parallels on Apple Silicon) | `Win32 TSF` (`ITfTextInputProcessorEx`) | **WinUI 3 / UWP**: Windows 11 Notepad, Windows Terminal, Windows Search, Edge<br>**Win32 / Desktop**: Office 365, Chrome, VS Code, File Explorer, Zalo PC |
| **Linux**<br>Ubuntu 22.04/24.04 LTS, Debian 12, Mint, Pop!_OS, Fedora, Arch | **x86_64** (`amd64` PC/Laptop)<br>**ARM64** (`aarch64` — Raspberry Pi 4/5, ARM workstations) | `IBus` & `Fcitx5` (`libVieLotusCAPI.so`) | **Display**: X11 & Wayland (GNOME, KDE Plasma)<br>**Apps**: Firefox, Chromium, VS Code, LibreOffice, GNOME Terminal, Konsole, Ghostty |
| **iOS & iPadOS**<br>iOS / iPadOS 16, 17, 18 | **iPhone** (XS → 16 Pro Max)<br>**iPad** (Air, mini, Pro M1–M4) | `UIKit` (`UIInputViewController`) | On-screen touch keyboard (60/120Hz) & physical Magic Keyboard / Bluetooth keyboards (Zero Full Access) |
| **Android**<br>Android 8.0 (API 26) – Android 15 | **ARM64 / ARMv7 / x86_64** (Samsung Galaxy Phone/Tab/DeX, Pixel, Xiaomi, OPPO) | `InputMethodService` (JNI C-ABI) | On-screen touch keyboard & physical USB / Bluetooth keyboards across mobile and tablet/DeX modes |

---

## Benchmark Summary (9,091-Case Suite)

| Metric Bucket | Drive Condition | Result |
| :--- | :--- | :--- |
| **Primary Regression Suite** | Transform (400), English Keep (362), Cancel (67), Restore Raw (7,213), Ambiguous w/ Context (1,049) | **9,091 / 9,091 (100.00%)** |
| **Symmetric Collision (`ambiguous_both_sides`)** | 375 lowercase collision words replayed *with* English context AND *without* context (`vn_survives_collision`) | **365 / 375 (97.33%)** |
| **Unique Vietnamese Paths (`whitelist_safe = never`)** | Syllables with only one Telex/VNI keystroke path | **182 / 182 (100.00% — 0 critical losses)** |

---

## Quick Installation

### 1. macOS (macOS 13+)
- **Homebrew**:
  ```bash
  brew install stevedat/tap/vielotus
  ```
- **Direct Installer (`.pkg`)**: Download [`VieLotusIM.pkg`](https://github.com/stevedat/VieLotus-IM/releases/latest/download/VieLotusIM.pkg), run the installer, then open **System Settings → Keyboard → Input Sources → Edit... → (+) → Vietnamese → Sen Việt**.

### 2. Windows (Windows 10 / 11 — `x64` & `ARM64`)
- Download [`VieLotus-Setup-x64.exe`](https://github.com/stevedat/VieLotus-IM/releases/latest/download/VieLotus-Setup-x64.exe) or [`VieLotus-Setup-arm64.exe`](https://github.com/stevedat/VieLotus-IM/releases/latest/download/VieLotus-Setup-arm64.exe) from [Releases](https://github.com/stevedat/VieLotus-IM/releases/latest) (or install via **Microsoft Store**).
- Run the installer and press **`Win + Space`** to select **Sen Việt**.

### 3. Linux (Ubuntu / Debian / Snap — `amd64` & `arm64`)
- **One-line installer (Ubuntu / Debian `.deb`)**:
  ```bash
  curl -fsSL https://stevedat.github.io/VieLotus-IM/install.sh | sh
  ```
- **Snap Store**:
  ```bash
  sudo snap install vielotus
  ```
- **Manual `.deb` install via `apt`**:
  ```bash
  sudo apt update && sudo apt install ./vielotus_2.0.0_amd64.deb   # or ./vielotus_2.0.0_arm64.deb
  ```
- **Quick CLI controls**: `vielotus-settings` (GTK3 GUI) · `vielotus --telex` · `vielotus --vni` · `vielotus --status`.

### 4. iOS / iPadOS & Android
- **iOS & iPadOS**: Install from the [App Store](https://apps.apple.com/us/app/sen-vi%E1%BB%87t/id6821782799) → **Settings → General → Keyboard → Keyboards → Add New Keyboard... → Sen Việt**.
- **Android**: Install from [Google Play](https://play.google.com/store/apps/details?id=org.vielotus.hardwarekeyboard) and enable **Sen Việt** in **Settings → System → Keyboard**.

---

## License

Licensed under the [MIT License](LICENSE). Maintained by **Steve Dat** ([@stevedat](https://github.com/stevedat)).
