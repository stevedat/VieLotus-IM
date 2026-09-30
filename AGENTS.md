# AGENTS.md — VietLotusIM (Sen Việt)

## Build & Test Commands

```bash
swift build                             # Build all targets (Core, App, CLI)
swift test                              # Run unit tests (EngineBridge, InputSessionManager, SmartBilingual)
swift run VieLotusCLI --benchmark       # Run official 9,091-word regression suite (98.30% pass rate)
swift run VieLotusCLI                   # Interactive REPL typing test harness
./scripts/build_imk.sh                  # Build release universal VieLotusIM.app + ad-hoc codesign
./scripts/build_pkg.sh                  # Build auto-registering installer package (VieLotusIM.pkg)
```

## Architecture

VietLotusIM is a modern, native macOS Input Method built on Apple's `InputMethodKit` framework, avoiding invasive low-level event taps (`CGEventTap`) or Accessibility permissions.

### Modules:
- **`Sources/VieLotusCore`**: Shared Domain & Engine Library (Apple Platform Agnostic)
  - `EngineBridge.swift`: Native Pure Swift bridge wrapping VietnameseEngine.
  - `InputSessionManager.swift`: Single source of truth for composition state (`composingWord`, `rawWord`, `editCaretBack`), handling feed, backspace, and caret stepping. Shared universally across macOS and iOS.
  - `SmartBilingualDetector.swift`: Heuristic + `NLLanguageRecognizer` bilingual restore engine. Decoupled from OS spell-checker via the `SpellCheckerProvider` protocol.
  - `MacSpellChecker.swift`: `NSSpellChecker` implementation for macOS injected into `SmartBilingualDetector` at startup.
  - `ClientAdapter.swift`: Thread-safe app categorization and dynamic marked-text fallback.

### Cross-Platform Strategy (macOS + iOS / iPadOS)
To achieve true Apple ecosystem portability, VietLotusIM strictly separates the core logic from platform-specific UI and OS dependencies:
1. **Shared State Machine**: `InputSessionManager` and `VietnameseEngine` contain no UI or OS-specific code (only Foundation), making them fully portable.
2. **Spell-Checking Abstraction**: `SmartBilingualDetector` relies on the `SpellCheckerProvider` protocol. macOS injects `NSSpellChecker`, while future iOS/iPadOS targets will inject `UITextChecker` or an internal dictionary.
3. **Platform Adapters**: macOS text output uses `IMKInputController` (`insertText:replacementRange:`), whereas iOS/iPadOS will use `UIInputViewController` and its `textDocumentProxy`.

- **`Sources/VieLotusIM`**: Native macOS Input Method Server Bundle
  - `main.swift`: Clean application runner (`app.run()`).
  - `VieLotusIMController.swift`: `IMKInputController` handling client events, direct replacement (`insertText:replacementRange:`), and marked text fallback.
  - `Preferences.swift`: SwiftUI ObservableObject for user preferences.
  - `SettingsView.swift`: Apple Minimalist Inspector Card UI for preferences.
  - `DiagnosticLogger.swift`: Zero-logging privacy architecture (`os.Logger` for DEBUG only, zero disk file I/O).
- **`Sources/VieLotusCLI`**: Command Line Harness
  - `main.swift`: High-performance benchmark and interactive REPL test runner.
  - `Resources/test_suite.csv`: Bundled regression test suite (9,091 test cases).

## Benchmark Regression Matrix

The regression suite tests 9,091 words across 5 behavioral categories:
- `restore_raw`: Restoring English words mangled by Telex rules (99.85% pass rate - 7,205 / 7,216).
- `ambiguous_needs_context`: Words with ambiguous English/Vietnamese spellings tested in context (94.56% pass rate - 990 / 1,047).
- `transform`: Pure Vietnamese transformation (98.25% pass rate - 393 / 400).
- `keep_as_typed`: Untouched English vocabulary (100.00% pass rate - 362 / 362).
- `cancel_keep_composed`: Trailing cancellation behavior (36.36% - 24 / 66).
- **Overall Pass Rate:** **98.71%** (8,974 / 9,091).
