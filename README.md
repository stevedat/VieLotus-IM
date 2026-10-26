# VieLotusIM (Sen Việt)

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platforms](https://img.shields.io/badge/Platforms-macOS%20%7C%20Windows%20%7C%20Linux%20%7C%20iOS%20%7C%20Android-1F5B3A.svg)](#platform-ecosystem)
[![App Store](https://img.shields.io/badge/App_Store-Sen_Việt-000000.svg?logo=apple&logoColor=white)](https://apps.apple.com/us/app/sen-vi%E1%BB%87t/id6821782799)
[![Google Play](https://img.shields.io/badge/Google_Play-Sen_Việt-1F5B3A.svg?logo=googleplay&logoColor=white)](https://play.google.com/store/apps/details?id=org.vielotus.hardwarekeyboard)
[![Language](https://img.shields.io/badge/Swift-6.0-orange.svg)](#platform-ecosystem)
[![Accuracy](https://img.shields.io/badge/Regression-100.00%25%20(9%2C091%2F9%2C091)-emerald.svg)](#benchmark-matrix)
[![Website](https://img.shields.io/badge/Website-stevedat.github.io%2FVieLotus--IM-1E6B7B.svg)](https://stevedat.github.io/VieLotus-IM/)

A lightweight, memory-safe Vietnamese input method powered by a unified **Pure Swift 6** core across **macOS**, **Windows**, **Linux**, **iOS & iPadOS**, and **Android**. Designed to deliver natural bilingual typing with zero invasive system hooks and 100% offline privacy.

---

## Platform Ecosystem

```
┌──────────────────────────────────────────────────────────────────────────────────┐
│                              Host Platform Adapters                              │
│  macOS (InputMethodKit)  │  Windows (TSF)  │  Linux (IBus/Fcitx5)  │ iOS/Android │
└─────────────▲────────────────────▲────────────────────▲───────────────────▲──────┘
              │                    │                    │                   │
┌─────────────┴────────────────────┴────────────────────┴───────────────────┴──────┐
│                     VieLotusCore & VieLotusCAPI (Pure Swift 6)                   │
│  ┌────────────────────────┐  ┌────────────────────────────────────────────────┐  │
│  │  InputSessionManager   │  │             SmartBilingualDetector             │  │
│  │  - Composing state     │  │  - Vietnamese phonotactic & stop-coda rules    │  │
│  │  - Caret stepping      │  │  - Context-aware bilingual collision arbiter   │  │
│  │  - Telex / VNI engines │  │  - Pluggable SpellCheckerProvider              │  │
│  └────────────────────────┘  └────────────────────────────────────────────────┘  │
│  ┌────────────────────────┐  ┌────────────────────────────────────────────────┐  │
│  │     ClientAdapter      │  │               PresentationRules                │  │
│  │  - App categorization  │  │  - typing-modes.yml (zero-dependency parser)   │  │
│  │  - UTF-16 cursor sync  │  │  - Per-app & global presentation overrides     │  │
│  └────────────────────────┘  └────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────────────────┘
```

- **Unified Core (`VieLotusCore` & `VieLotusCAPI`)**: Pure Swift 6 state machine (`InputSessionManager`, `VietnameseEngine`, `SmartBilingualDetector`) shared across Apple platforms and exposed via a zero-copy C-ABI bridge for Windows and Linux.
- **macOS (`VieLotusIM`)**: Built strictly on Apple's `InputMethodKit` (`IMKInputController`, `IMKServer`, `IMKTextInput`) requiring zero Accessibility permissions.
- **Windows (`windows-tsf`)**: Native Text Services Framework (TSF) Text Input Processor (`ITfTextInputProcessorEx`) communicating with `VieLotusCAPI`.
- **Linux (`ibus-vielotus` & `fcitx5-vielotus`)**: Native IBus and Fcitx5 engines backed by `libVieLotusCAPI.so`.
- **iOS, iPadOS & Android**: Native mobile keyboard extensions powered by the same syllable and bilingual arbitration core.

---

## Key Capabilities

### 1. Zero Dropped Letters in Web, Electron & Modern Editors
- **Problem**: Legacy input methods rely on synthetic backspace injection (`CGEventTap` or key-up hooks) to erase raw characters and type composed syllables. In modern virtual-DOM editors (Google Docs, Notion, Slack, VS Code, Electron), synthetic backspaces race with user keystrokes, causing dropped letters or duplicated words.
- **Approach**: Uses native system composition (`setMarkedText` / atomic `insertText:replacementRange:`) and UTF-16 code unit synchronization for GPU terminals (Ghostty, Alacritty, Kitty, iTerm2).

### 2. Context-Aware Bilingual Typing (Telex & VNI)
- **Problem**: Everyday English words and code identifiers (`test`, `restrict`, `toast`, `blood`, `floor`, `door`, `git`, `commit`, `const`) collide with Telex modifier keys (`s`, `f`, `r`, `x`, `j`, `w`, `aa`, `ee`, `oo`).
- **Approach**: `SmartBilingualDetector` validates Vietnamese phonotactic rules (such as stop-coda `-c, -ch, -p, -t` tone constraints) alongside lexical context so users can write Vietnamese and English seamlessly without toggling modes.

### 3. Native Undo Integrity & 100% On-Device Privacy
- **Undo Preservation**: Atomic text replacement keeps the host application's `Cmd + Z` / `Ctrl + Z` undo history intact.
- **Zero-Logging Privacy**: Operates 100% offline with zero network sockets, zero telemetry, and zero keystroke logging.

---

## Benchmark Matrix

Measured against the bundled 9,091-case regression suite:

| Test Bucket | Test Condition | Passing Rate |
| :--- | :--- | :--- |
| **Pure Vietnamese Transform** | Vietnamese syllables only | **400 / 400 (100.00%)** |
| **English Vocabulary Preservation** | Untouched English dictionary | **362 / 362 (100.00%)** |
| **Tone Cancellation** | Trailing cancel keys | **67 / 67 (100.00%)** |
| **Telex Raw Word Restoration** | Restoring mangled English words | **7,213 / 7,213 (100.00%)** |
| **Ambiguous Spellings (With Context)** | Primed with English context | **1,049 / 1,049 (100.00%)** |
| **Overall Suite** | Complete 9,091-case regression suite | **9,091 / 9,091 (100.00%)** |

> [!IMPORTANT]
> **Symmetric Collision Disclosure:**
> High English restoration accuracy must always be reported alongside its symmetric no-context counterpart. When the 375 lowercase ambiguous collision words are driven **without** English context priming:
> - **`vn_survives_collision` / `ambiguous_both_sides`**: **365 / 375 (97.33%)** survival (correct as English *with* context and as Vietnamese *without* context).
> - **Unique Vietnamese keystroke paths (`whitelist_safe = never`)**: **182 / 182 (100.00% — 0 critical losses)**.

---

## Installation

### macOS (macOS 13+)

#### Option 1: Homebrew (Recommended)
```bash
brew install stevedat/tap/vielotus
```

#### Option 2: Installer Package (`.pkg`)
1. Download `VieLotusIM.pkg` from the [Latest Release](https://github.com/stevedat/VieLotus-IM/releases/latest) (or `Binaries/VieLotusIM.pkg`).
2. Open the installer to automatically register **Sen Việt**.
3. Open **System Settings** → **Keyboard** → **Text Input** → **Edit...** and add **Vietnamese** → **Sen Việt**.

### Windows (Windows 10 / 11 x64)

1. Download `VieLotus-Setup-x64.exe` from the [Latest Release](https://github.com/stevedat/VieLotus-IM/releases/latest) (or `Binaries/windows/VieLotus-Setup-x64.exe`).
2. Run the installer to automatically register the **Sen Việt (VieLotus)** Text Services Framework (TSF) input method.
3. Press **`Win + Space`** to switch to **Sen Việt**.

### Linux (Ubuntu / Debian — `amd64` & `arm64`)

Install the all-in-one `.deb` package (includes Core Engine + both IBus & Fcitx5 plugins) from the [Latest Release](https://github.com/stevedat/VieLotus-IM/releases/latest) (or `Binaries/linux/`):
```bash
# For x86_64 (amd64):
sudo apt install ./Binaries/linux/vielotus_1.1.1_amd64.deb

# For ARM64 (aarch64):
sudo apt install ./Binaries/linux/vielotus_1.1.1_arm64.deb
```

### iOS & iPadOS (iPhone & iPad)

1. Install **Sen Việt** from the [Apple App Store](https://apps.apple.com/us/app/sen-vi%E1%BB%87t/id6821782799).
2. Open **Settings** → **General** → **Keyboard** → **Keyboards** → **Add New Keyboard...** and select **Sen Việt**.
3. Switch to **Sen Việt** in any app using the **Globe (🌐)** key (100% offline, no Full Access required).

### Android

1. Install **Sen Việt** from [Google Play](https://play.google.com/store/apps/details?id=org.vielotus.hardwarekeyboard).
2. Open the **Sen Việt** app and follow the quick setup steps to enable the virtual and physical keyboard in Android **Settings** → **System** → **Keyboard**.

---

## License

VieLotusIM is licensed under the [MIT License](LICENSE).
Created and maintained by **Steve Dat** ([@stevedat](https://github.com/stevedat)).
