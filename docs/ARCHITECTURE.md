# VieLotusIM (Sen Việt) — Open-Core System Architecture

## 1. Design Philosophy: Pure Apple Native & Zero Invasive Hooks

VieLotusIM is engineered to replace legacy low-level keyboard event hooks with a strictly sandboxed, native OS Input Method architecture:

- **macOS (`Sources/VieLotusIM/`)**: Built 100% on Apple's `InputMethodKit` (`IMKServer`, `IMKInputController`, `IMKTextInput`). Zero `CGEventTap`, zero `CGEventSource`, zero Carbon synthetic backspaces, and zero Accessibility permission requirements.
- **Windows (`CrossPlatform/windows-tsf/`)**: Built on Microsoft's Text Services Framework (`ITfTextInputProcessorEx`, `ITfKeyEventSink`, `ITfEditSession`) communicating with the core via the zero-copy C-ABI (`vielotus.h`).
- **Linux (`CrossPlatform/fcitx5-vielotus/` & `CrossPlatform/ibus-vielotus/`)**: Native Fcitx5 (`fcitx::InputMethodEngineV2`) and IBus (`IBusEngine`) modules backed by `libVieLotusCAPI.so`.
- **100% Offline & Zero-Logging Privacy**: No external network sockets, no telemetry collection, and zero disk logging of keystrokes.

---

## 2. Host Integration & Presentation Modes (`ClientAdapter` & `PresentationRules`)

Different host applications handle IME composition ranges differently. VieLotusIM dynamically selects the optimal presentation mode per bundle identifier:

1. **Marked Text (`markedText`)**: Standard macOS inline underline composition (`setMarkedText:selectionRange:replacementRange:`) for native Cocoa/AppKit/SwiftUI text views and Chromium/Safari address bars.
2. **Direct Replacement (`directReplacement`)**: Atomic UTF-16 `insertText:replacementRange:` updates for GPU-accelerated terminals (Ghostty, Alacritty, Kitty, iTerm2, Warp, WezTerm) and code editors where marked-text underlines interfere with terminal escape sequences or autocomplete popups.

Resolution order:
`User Per-App Override` → `User Global Preference` → `Resources/typing-modes.yml` → `ClientAdapter Category Heuristic`.

---

## 3. Open-Core Boundary (`VieLotusCore.xcframework` & `vielotus.h`)

To enable full security auditability of all OS-facing code while protecting proprietary linguistic and bilingual arbitration IP:

- **Open Source (MIT)**:
  - `Sources/VieLotusIM/`: Complete macOS `IMKInputController` implementation, preferences UI, and `DiagnosticLogger`.
  - `Sources/VieLotusTrace/`: Sanitized diagnostic event contracts.
  - `Sources/VieLotusCAPI/include/vielotus.h`: Stable C-ABI contract for Windows and Linux shells.
  - `CrossPlatform/`: Complete C/C++ source code for Windows TSF, Linux Fcitx5, and Linux IBus adapters.
- **Prebuilt Core & Desktop Installers (`Frameworks/VieLotusCore.xcframework` & `Binaries/`)**:
  - Compiled universal framework (`arm64` + `x86_64`) providing `InputSessionManager`, `EngineBridge`, `SmartBilingualDetector`, `MacroEngine`, `ClientAdapter`, and `PresentationRules`, plus final installers (`VieLotusIM.pkg`, `VieLotus-Setup-x64.exe`, and `*.deb`).
  - Verified against the 9,091-case regression matrix (**100.00% (9,091 / 9,091)** overall alongside symmetric collision survival `vn_survives_collision` / `ambiguous_both_sides` **97.33% (365 / 375)** and `whitelist_safe = never` **100.00% (182 / 182)**).
