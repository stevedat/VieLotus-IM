# VieLotusIM (Sen Việt)

[![English](https://img.shields.io/badge/Language-English-1F5B3A.svg)](README.md)
[![Tiếng Việt](https://img.shields.io/badge/Ngôn_ngữ-Tiếng_Việt-2d3748.svg)](README.vi.md)
[![macOS](https://img.shields.io/badge/macOS-Installer_(.pkg)-000000.svg?logo=apple&logoColor=white)](https://github.com/stevedat/VieLotus-IM/releases/latest/download/VieLotusIM.pkg)
[![Windows Store](https://img.shields.io/badge/Microsoft_Store-Sen_Việt-0067B8.svg?logo=windows&logoColor=white)](https://apps.microsoft.com/detail/9PF5K64GXXSH)
[![Linux](https://img.shields.io/badge/Linux-PPA_%2F_.deb-E95420.svg?logo=ubuntu&logoColor=white)](https://launchpad.net/~stevedat/+archive/ubuntu/vielotus)
[![App Store](https://img.shields.io/badge/App_Store-Sen_Việt-000000.svg?logo=apple&logoColor=white)](https://apps.apple.com/us/app/sen-vi%E1%BB%87t/id6821782799)
[![Google Play](https://img.shields.io/badge/Google_Play-Sen_Việt-1F5B3A.svg?logo=googleplay&logoColor=white)](https://play.google.com/store/apps/details?id=org.vielotus.hardwarekeyboard)

A lightweight, memory-safe Vietnamese input method anchored in the **Apple ecosystem (macOS, iOS, iPadOS)** as its primary **Pure Swift 6** reference architecture, and compiled natively across **Windows**, **Linux**, and **Android** — operating strictly through official OS input protocols with **zero global keystroke hooks** and **100% offline privacy**.

📄 **[Technical Dossier & Interactive Specimen](https://stevedat.github.io/VieLotus-IM/)** · 📐 **[Architecture & Benchmark Monograph](https://stevedat.github.io/VieLotus-IM/research.html)**

---

## Core Highlights

- **Zero Global Hooks (`0 Accessibility / Core Typing Without Full Access / 0 Keyboard Hook`)**: Uses official OS input contracts (`InputMethodKit` on macOS, `UIInputViewController` on iOS/iPadOS, `Win32 TSF` on Windows, `IBus / Fcitx5` on Linux, `InputMethodService` on Android) rather than global event taps. Immune to macOS TCC permission breakage, Linux Wayland isolation issues, and operates 100% offline.
- **Lexical & Context-Aware Bilingual Typing (Telex & VNI)**: Rejects non-existent Vietnamese syllables (`turn` stays `turn`, never `"tủn"`) and mid-word English `-s-t` patterns (`last`, `best`, `cost`), while resolving true single-path collisions (`rest`/`rét`, `if`/`ì`, `as`/`á`) via preceding context.
- **Adaptive Per-App Presentation (`< 0.2 ms` p99)**: Dynamically switches between `Direct Replacement` (AppKit, Safari, Office) and standards-compliant `Marked Text` (Chromium, Electron, React/ProseMirror, GPU terminals) with UTF-16 cursor synchronization and a 20-word backspace ring buffer.

---

## Verified Hardware, OS & Environment Matrix

| Platform & OS | Verified Hardware & CPU | Native Framework | Verified Applications & Environments |
| :--- | :--- | :--- | :--- |
| **macOS**<br>13 Ventura, 14 Sonoma, 15 Sequoia | **Apple Silicon** (`M1 / M2 / M3 / M4` — MacBook Air/Pro, Mac mini, iMac, Mac Studio)<br>**Intel** (`x86_64`) | `InputMethodKit` (`IMKServer`) | **Native**: Safari, Notes, Pages, Mail, Xcode, Spotlight<br>**Web/Electron**: Chrome, Arc, Edge, VS Code, Cursor, Slack, Discord, Notion, Zalo, Teams<br>**Terminals**: Terminal.app, iTerm2, Ghostty, Kitty, Alacritty, Warp<br>**Office**: Word, Excel, PowerPoint |
| **Windows**<br>Windows 10 (21H2+) & Windows 11 (22H2–24H2) | **Intel / AMD** (`x64`)<br>**ARM64** (Snapdragon X Elite/Plus, Surface Pro ARM, Parallels on Apple Silicon) | `Win32 TSF` (`ITfTextInputProcessorEx`) | **WinUI 3 / UWP**: Windows 11 Notepad, Windows Terminal, Windows Search, Edge<br>**Win32 / Desktop**: Office 365, Chrome, VS Code, File Explorer, Zalo PC |
| **Linux**<br>Ubuntu 22.04/24.04 LTS, Debian 12, Mint, Pop!_OS, Fedora, Arch | **x86_64** (`amd64` PC/Laptop)<br>**ARM64** (`aarch64` — Raspberry Pi 4/5, ARM workstations) | `IBus` & `Fcitx5` (`libVieLotusCAPI.so`) | **Display**: X11 & Wayland (GNOME, KDE Plasma)<br>**Apps**: Firefox, Chromium, VS Code, LibreOffice, GNOME Terminal, Konsole, Ghostty |
| **iOS & iPadOS**<br>iOS / iPadOS 16, 17, 18 | **iPhone** (XS → 16 Pro Max)<br>**iPad** (Air, mini, Pro M1–M4) | `UIKit` (`UIInputViewController`) | On-screen touch keyboard (60/120Hz) & physical Magic Keyboard / Bluetooth keyboards (Core typing without Full Access) |
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
- **Microsoft Corporation Signed Web Installer (Recommended — Zero SmartScreen warning)**: Download [`VieLotus-Store-Setup.exe`](https://github.com/stevedat/VieLotus-IM/releases/latest/download/VieLotus-Store-Setup.exe) or install directly from the [**Microsoft Store**](https://apps.microsoft.com/detail/9PF5K64GXXSH).
- **Standalone Offline Installers**: Download [`VieLotus-Setup-x64.exe`](https://github.com/stevedat/VieLotus-IM/releases/latest/download/VieLotus-Setup-x64.exe) (`x64`) or [`VieLotus-Setup-arm64.exe`](https://github.com/stevedat/VieLotus-IM/releases/latest/download/VieLotus-Setup-arm64.exe) (`ARM64`) from [Releases](https://github.com/stevedat/VieLotus-IM/releases/latest).
- Run the installer and press **`Win + Space`** to select **Sen Việt**.

### 3. Linux (Ubuntu / Debian / Mint / Fedora / Arch / openSUSE — `amd64` & `arm64`)
- **Ubuntu Official Launchpad PPA (`Ubuntu 22.04 LTS, 24.04 LTS, 26.04 LTS & 26.10` — `amd64` & `arm64`)**:
  ```bash
  sudo rm -f /etc/apt/sources.list.d/vielotus.list   # Clean legacy v1.x static APT file if upgrading
  sudo add-apt-repository -y ppa:stevedat/vielotus
  sudo apt update
  sudo apt install -y vielotus   # Installs IBus/Fcitx5 plugins + GTK3 Settings GUI (Synaptic/APT auto-updated)
  ```
- **Universal one-line installer (Auto-detects `apt`, `dnf`, `pacman`, `zypper` & `x86_64` / `aarch64`)**:
  ```bash
  curl -fsSL https://stevedat.github.io/VieLotus-IM/install.sh | sh
  ```
- **Manual `.deb` install via `apt` (Ubuntu / Debian / Mint / Pop!_OS)**:
  ```bash
  sudo apt update && sudo apt install ./vielotus_2.0.3_amd64.deb   # or ./vielotus_2.0.3_arm64.deb
  ```
- **Arch Linux / Manjaro (`PKGBUILD`)**: `cd CrossPlatform/packaging/arch && makepkg -si`
- **Quick CLI controls**: `vielotus-settings` (GTK3 GUI) · `vielotus-settings --telex` · `vielotus-settings --vni` · `vielotus-settings --doctor`.
- **First-install note on Ubuntu / GNOME (Wayland)**: The installer auto-reloads IBus and registers **Sen Việt (`🇻🇳 tex`)** immediately (`Super + Space` to switch). If GNOME Shell's top bar still caches the old input list or Settings temporarily displays raw `vielotus`, simply **Log Out and Log In once** (or click **Riêng Linux ⚙ → Tự sửa & Kích hoạt** in `Sen Việt`).

### 4. iOS / iPadOS & Android
- **iOS & iPadOS**: Install from the [App Store](https://apps.apple.com/us/app/sen-vi%E1%BB%87t/id6821782799) → **Settings → General → Keyboard → Keyboards → Add New Keyboard... → Sen Việt**.
- **Android**: Install from [Google Play](https://play.google.com/store/apps/details?id=org.vielotus.hardwarekeyboard) and enable **Sen Việt** in **Settings → System → Keyboard**.

---

## Open-Core Architecture & Building from Source

VieLotusIM follows a **transparent Open-Core model** designed so security researchers, Linux package maintainers, and developers can audit OS permissions and build working binaries directly from this repository across all three desktop platforms:

| Platform | OS Integration Layer (Shell & UI) | Linguistic Engine Core | Openness & Build-from-Source Status |
| :--- | :--- | :--- | :--- |
| **Linux**<br>(`IBus` & `Fcitx5`) | **100% Open Source (MIT)**<br>`CrossPlatform/ibus-vielotus/`<br>`CrossPlatform/fcitx5-vielotus/`<br>`CrossPlatform/capi-native/` | **100% Open Source C++20 (MIT / Debian DFSG #2)**<br>`Sources/VieLotusCoreWindows/` + canonical UTF-8 NFC wordlists (`lexicon/*.txt`) + deterministic FNV-1a generator (`generate_lexicon_hashes.py`) | **100% Open Source (Zero binary blobs)**.<br>Compiles entirely from source via Debian `dpkg-buildpackage`, Launchpad PPA builders, or standard `cmake` + `ninja`. |
| **Windows**<br>(`Win32 TSF`) | **100% Open Source (MIT)**<br>`CrossPlatform/windows-tsf/` | **100% Open Source C++20 (MIT)**<br>`Sources/VieLotusCoreWindows/` (unobfuscated C++20 implementation) | **100% Open Source (Zero binary blobs)**.<br>Compiles the TSF DLLs and installers directly from source via CMake / MSVC (`./scripts/build_windows.ps1`). |
| **macOS**<br>(`InputMethodKit`) | **100% Open Source (MIT)**<br>`Sources/VieLotusIM/` (`IMKServer`, `IMKInputController`, Settings UI, `DiagnosticLogger`) & `Sources/VieLotusTrace/` | Prebuilt Universal XCFramework (`arm64` + `x86_64`)<br>`Frameworks/VieLotusCore.xcframework` (shared Swift 6 core with the commercial iOS / iPadOS App Store edition) | **100% Security-Auditable Open-Core**.<br>Every line of macOS OS integration is open source to verify **0 `CGEventTap` hooks**, **0 Accessibility permissions**, **0 keystroke logging**, and **0 network calls**, and builds `VieLotusIM.app` via `swift build`. |

### Build from Source Commands

1. **Verify Prebuilt XCFramework Checksum (`SHA-256`)**:
   ```bash
   shasum -a 256 -c Frameworks/checksums.sha256
   ```
2. **macOS (`VieLotusIM.app` Universal `arm64` + `x86_64`)**:
   ```bash
   swift build -c release --product VieLotusIM
   ./scripts/build_imk.sh
   ```
3. **Linux (100% from C/C++20 Source — Debian/Ubuntu `.deb` or CMake)**:
   ```bash
   # Option 1: Full Debian / Ubuntu package build (regenerates lexicon tables from lexicon/*.txt)
   dpkg-buildpackage -us -uc -b

   # Option 2: Direct CMake shared library build
   cmake -B build/capi -S CrossPlatform/capi-native -DCMAKE_BUILD_TYPE=Release && cmake --build build/capi
   ```
4. **Windows (`Win32 TSF` `x64` & `ARM64` from C++20 Source)**:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\scripts\build_windows.ps1
   ```

---

## License

Released under the **[MIT License](LICENSE) (Open-Core Model)**: all source code in this repository (100% of the Linux & Windows input methods and the full macOS `InputMethodKit` shell) along with the bundled `VieLotusCore.xcframework` binary may be freely used, built from source, modified, and redistributed under the terms of the MIT License. Maintained by **Steve Dat** ([@stevedat](https://github.com/stevedat)).
