# VieLotusIM (Sen Việt) — Compatibility Matrix & Deployment Guide

## 1. macOS Version Support

| macOS Release | Version Range | Target Architecture | Status |
| :--- | :--- | :--- | :--- |
| **macOS 15 Sequoia** | 15.0+ | Apple Silicon (arm64) & Intel (x86_64) | ✅ Fully Supported & Tested |
| **macOS 14 Sonoma** | 14.0 - 14.7 | Apple Silicon (arm64) & Intel (x86_64) | ✅ Fully Supported |
| **macOS 13 Ventura** | 13.0 - 13.6 | Apple Silicon (arm64) & Intel (x86_64) | ✅ Fully Supported |

---

## 2. Application Compatibility Matrix

VieLotusIM uses an adaptive presentation engine to provide flicker-free direct replacement where supported, standard marked text for web and electron environments to prevent dropped/duplicated characters, and optimized direct input for terminal emulators:

| Application Category | Sample Applications | Presentation Mode | Behavior & Verification |
| :--- | :--- | :--- | :--- |
| **Standard AppKit / Cocoa** | TextEdit, Notes, Pages, Keynote, Numbers, Mail, Safari, Xcode, Finder | Direct Replacement | Zero flicker, no underline, native Cmd+Z undo stack. |
| **Chromium, Electron & CEF** | Chrome, Edge, Arc, Brave, Opera, Vivaldi, VS Code, Cursor, Windsurf, Slack, Discord, Notion, Obsidian, Logseq, Linear, Figma, Zalo, Telegram, Teams, WhatsApp, Signal, Postman | Marked Text (W3C IME Standard) | Synchronizes with W3C IME composition events (`compositionstart`, `compositionupdate`, `compositionend`). Eliminates character duplication (`t-ti-tiế-tiếng`) and caret jumping caused by asynchronous DOM/React diffing. Once the word completes, the underline clears immediately. |
| **Microsoft Office** | Word, Excel, PowerPoint, OneNote, Outlook | Direct Replacement | Clean typing buffer with accurate caret position. |
| **Terminal Emulators** | Terminal.app, iTerm2, Warp, Ghostty, Alacritty, Kitty, WezTerm, Rio, Hyper, Tabby | Terminal Direct / Marked Text | Real-time direct PTY emission (`\u{7F}`) or marked text inline composition. |
| **Quick Search & Overlays** | Spotlight, Raycast, Alfred, LaunchBar, Sol | Direct Replacement | Instant focus response without selection locking. |
| **Dynamic Fallback (Special Controls)** | Legacy webviews, custom canvas inputs returning `NSNotFound` or ignoring `replacementRange` | Dynamic `markedText` Fallback | Automatically activates inline marked text if client does not expose caret range or ignores in-place replacement ranges. |

### 2.1 Known Host Limitations & Underline Distinction

VieLotusIM does **not** claim universal underline-free behavior across every macOS application. Under Apple's official `InputMethodKit` / `NSTextInputClient` contract (without invasive `CGEventTap` or Accessibility hooks), underline behavior depends on how each host application implements text input:

1. **Host Support for `insertText(_:replacementRange:)` (`Direct Replacement` — Underline-Free):**
   - Native AppKit (`NSTextView`, `NSTextField`), Safari, Firefox, JetBrains IDEs, Sublime Text, Zed, and Microsoft Office honor `replacementRange` directly in UTF-16 code units. In these hosts, VieLotusIM mutates diacritics in place with **no IME composition underline**.
   - `DirectReplacementGuard` enforces strict session ownership: it never replaces characters outside `[compositionStartLocation, virtualCursorLocation]` and never replaces more UTF-16 code units than the active composition owns.
2. **Hosts Requiring `setMarkedText` (`Marked Text` — W3C Composition Lifecycle):**
   - Chromium, Electron, and CEF applications (Chrome, Arc, Brave, Edge, VS Code, Cursor, Slack, Discord, Notion, Obsidian, Linear, Figma, Zalo, Telegram) bridge `NSTextInputClient` to web editors (React controlled inputs, ProseMirror, Tiptap, Slate, Monaco) that rely on W3C `compositionstart` / `compositionupdate` / `compositionend` events to synchronize their virtual DOM.
   - Bypassing `setMarkedText` in these editors causes asynchronous virtual DOM diffing to duplicate syllables (`t-ti-tiế-tiếng`) or jump the caret. Therefore, VieLotusIM uses standards-compliant `setMarkedText` in `.chromium` hosts and automatically falls back to `.markedText` if any third-party host reports `NSNotFound` for `selectedRange()` or silently ignores `replacementRange`.
3. **IME Composition Underlines vs. Spell-Checking Underlines:**
   - **IME Composition Underline:** A solid or segmented underline drawn beneath the *currently composing syllable* while `setMarkedText` is active; it disappears as soon as Space, Enter, punctuation, or focus change commits the syllable.
   - **Spell-Checking Underline:** A red dotted/squiggly line drawn by macOS (`NSSpellChecker`) or a browser's built-in spellchecker *after* characters are inserted when the host's spellcheck language is set to English only. This is controlled by the host application's *Edit → Spelling and Grammar* settings, not by the input method's presentation mode.

---

## 3. Deliberate Architecture Boundary: No Event Tap, No Accessibility

VieLotusIM reaches the screen through **InputMethodKit only**. It never creates a
`CGEventTap`, never posts a synthetic keystroke via `CGEventSource` / `CGEvent.post`, and
never requires Accessibility permission in order to type. Verified by:

```bash
grep -rn "CGEvent" Sources/VieLotusIM Sources/VieLotusCore   # -> no matches
```

Every Accessibility call in the repository lives in `Sources/VieLotusLab/LabApp.swift` —
the **optional diagnostics app**, which is a separate bundle and is not required for
typing.

This is a deliberate trade, not an omission. Other input methods install a session-level
event tap and synthesise real Backspace + Unicode keystrokes to force the screen to
match the engine. That approach does work where IMKit alone struggles, so it is worth
stating exactly what we give up by refusing it:

| Situation | What a tap-based IME can do | What VieLotusIM does instead |
| :--- | :--- | :--- |
| **Terminal / iTerm prompt** | Intercept `keyDown` before the terminal, suppress it, then synthesise Backspace + the corrected character, so the shell never sees a composition buffer and `zsh-autosuggestions` / Tab completion keep working | `Terminal Direct` emits the DEL byte (`\u{7F}`) through the client, or uses marked text. Autocomplete keeps working only where the terminal honours IMKit suppression |
| **Browser address bar** with inline autocomplete | Select the partial text with synthetic Shift+← and overwrite it in a single write, sidestepping the race against the inline suggestion | Marked Text (W3C IME composition). The race is avoided rather than won |
| **Excel cell** with an active suggestion | Insert `U+202F` to dismiss the suggestion, then backspace-retype (Shift+← would select a neighbouring cell) | Direct Replacement, with the app pinned by `ClientAdapter.classify` |

**What the boundary buys:**

- **No Accessibility prompt, and no TCC failure mode.** An event tap needs a TCC
  Accessibility grant whose row records the app's Designated Requirement (`csreq`) at
  grant time. When the binary is later replaced by a differently-signed build, the tick
  stays visible in System Settings while the kernel silently drops the posted events —
  and `AXIsProcessTrusted()` still returns `true`, so the app cannot detect its own
  broken state. Nothing in VieLotusIM can enter that state.
- **Mac App Store distribution stays open.** Sandboxed apps may not post global events,
  so a tap-based IME is Developer-ID-only by construction.
- **No re-entrancy bug class.** Synthetic events re-enter the tap and the IME and must be
  stamped and filtered; `CGEvent.post` delivers in *timestamp* order, so back-to-back
  events need strictly increasing timestamps or the window server reorders them. Not
  synthesising events removes the whole class.
- **No tap-timeout risk.** A tap callback that is too slow gets disabled by the system
  (`.tapDisabledByTimeout`), after which physical keystrokes fall through unhandled.

**What it costs, stated plainly:** the three rows above are handled by cooperating with
the client rather than by force. In a client that neither honours `replacementRange` nor
accepts marked text, VieLotusIM degrades to the dynamic marked-text fallback instead of
overriding the screen. Please report those clients — that is precisely what
`typing-modes.yml` below exists for.

### 3.1 Per-app presentation rules are data, not code

`Sources/VieLotusCore/Resources/typing-modes.yml` holds `bundle-id: mode` rules that sit
**below** the user's own choices and **above** the built-in category heuristic. Adding
support for an application is a one-line data change — no Swift edit, no rebuild, no
release.

Resolution order, highest first:

1. the user's per-app override (Settings → *Bảng cơ chế gõ*)
2. the user's global presentation mode (Settings → *Mặc định*)
3. `typing-modes.yml`
4. `ClientAdapter.classify` + `ClientAdapter.presentationMode`

The file is read from the first of these paths that exists, so a rule can be validated on
a live machine in seconds:

1. `~/Library/Application Support/VieLotusIM/typing-modes.yml` ← editable, **no rebuild**
2. `VieLotusIM.app/Contents/Resources/typing-modes.yml` ← shipped copy
3. the `VieLotusCore` SwiftPM resource bundle ← CLI, tests, library consumers

Edits are picked up on the next focus change: `activateServer` calls
`ClientAdapter.reloadPresentationRulesIfChanged()`, which costs one `stat` and keeps disk
I/O off the keystroke path entirely. Malformed lines are ignored, so a hand-edited rule
file cannot take the input method down.

The repository ships this file with **no active rules**. An entry is added only when the
heuristic is known to guess wrong for a specific app, so the default behaviour of a fresh
install is exactly the behaviour described by the matrix in section 2.

---

## 4. Fresh-Machine Installation & Verification Protocol

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

---

## 5. External Tester & Diagnostic Guide
 
For a complete step-by-step walkthrough covering automated diagnostic packet exports, trace event collection with `VieLotusLab`, and clean uninstallation, see [docs/LAB_TESTING_GUIDE.md](LAB_TESTING_GUIDE.md).

For feedback, questions, and feature suggestions, visit [GitHub Discussions](https://github.com/stevedat/VieLotus-IM/discussions).
