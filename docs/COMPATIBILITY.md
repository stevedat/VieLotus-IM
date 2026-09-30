# VieLotusIM (Sen Việt) — Compatibility Matrix & Deployment Guide

## 1. macOS Version Support

| macOS Release | Version Range | Target Architecture | Status |
| :--- | :--- | :--- | :--- |
| **macOS 15 Sequoia** | 15.0+ | Apple Silicon (arm64) & Intel (x86_64) | ✅ Fully Supported & Tested |
| **macOS 14 Sonoma** | 14.0 - 14.7 | Apple Silicon (arm64) & Intel (x86_64) | ✅ Fully Supported |
| **macOS 13 Ventura** | 13.0 - 13.6 | Apple Silicon (arm64) & Intel (x86_64) | ✅ Fully Supported |

---

## 2. Application Compatibility Matrix

VieLotusIM uses an adaptive presentation engine to provide flicker-free direct replacement where supported, and standard marked text for terminal emulators and dynamic fallback for edge-case controls:

| Application Category | Sample Applications | Presentation Mode | Behavior & Verification |
| :--- | :--- | :--- | :--- |
| **Standard AppKit / Cocoa** | TextEdit, Notes, Pages, Keynote, Numbers, Mail, Safari | Direct Replacement | Zero flicker, no CJK underline, native Cmd+Z undo stack. |
| **Chromium & Electron** | Google Chrome, Microsoft Edge, Brave, VS Code, Slack, Discord, Notion, Obsidian | Direct Replacement | Instant syllable replacement via `replacementRange`. |
| **Microsoft Office** | Word, Excel, PowerPoint | Direct Replacement | Clean typing buffer with accurate caret position. |
| **Terminal Emulators** | Terminal.app, iTerm2, Ghostty, Alacritty, Kitty, WezTerm | Marked Text | Standard marked buffer inline composition. |
| **Dynamic Fallback (Special Controls)** | Legacy webviews, custom canvas inputs returning `NSNotFound` | Dynamic `markedText` Fallback | Automatically activates inline marked text if client does not expose caret range. |

---

## 3. Fresh-Machine Installation & Verification Protocol

### Step 1: Install via PKG Installer or Manual Bundle Copy
- **Option A (Standard Installer Package)**:
  Double-click `VieLotusIM.pkg` and follow the on-screen installer prompts.
- **Option B (Manual Installation)**:
  ```bash
  cp -R ".build/dist/VieLotusIM.app" ~/Library/Input\ Methods/
  killall -9 VieLotusIM 2>/dev/null || true
  ```

### Step 2: Register Input Method in macOS Settings
> [!IMPORTANT]
> **Log Out Requirement**: When installing for the first time on a fresh macOS system, please **Log Out** of macOS and log back in once. This allows macOS `TextInputMenuAgent` to refresh and display newly installed third-party input methods in the available list.

1. Open **System Settings** $\rightarrow$ **Keyboard** $\rightarrow$ **Text Input** $\rightarrow$ Click **Edit...** under *Input Sources*.
2. Click the `+` (Add) button at the bottom left.
3. Select **Vietnamese** from the language list.
4. Choose **VieLotusIM** (or Sen Việt) and click **Add**.

### Step 3: Clean Machine Verification Test Matrix
Test typing in the following 5 representative application environments:
1. **TextEdit / Notes**: Type `Tiếng Việt thân yêu` $\rightarrow$ Confirm zero underline flicker and accurate diacritics.
2. **Google Chrome / Safari**: Type in URL search bar and rich textarea $\rightarrow$ Confirm instant composition.
3. **VS Code**: Type comments `// Kiểm tra bộ gõ tiếng Việt` $\rightarrow$ Confirm auto-closing bracket and caret position stability.
4. **Terminal / iTerm2**: Type `echo "Chào Việt Nam"` $\rightarrow$ Confirm marked text inline composition.
5. **Context Switch Test**: Highlight a word with mouse/keyboard and start typing $\rightarrow$ Confirm active selection is overwritten immediately without ghost characters.
