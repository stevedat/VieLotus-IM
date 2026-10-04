# AGENTS.md — VietLotusIM (Sen Việt)

## Build & Test Commands

```bash
swift build                             # Build all targets (Core, App, CLI, Lab, Trace)
swift test                              # Run unit tests (EngineBridge, InputSessionManager, SmartBilingual)
swift run VieLotusCLI --benchmark       # Run official 9,091-word regression suite (99.99% pass rate)
swift run VieLotusCLI --stress          # Run 250,000-keystroke high-throughput stress & endurance benchmark
swift run VieLotusCLI                   # Interactive REPL typing test harness
./scripts/build_imk.sh                  # Build release universal VieLotusIM.app + ad-hoc codesign
./scripts/build_pkg.sh                  # Build auto-registering installer package (VieLotusIM.pkg)
./scripts/build_lab.sh                  # Build release universal VieLotusLab.app
```

## Architecture

VietLotusIM is a modern, native macOS Input Method built on Apple's `InputMethodKit` framework, avoiding invasive low-level event taps (`CGEventTap`) or Accessibility permissions.

### Modules:
- **`Sources/VieLotusCore`**: Shared Domain & Engine Library (Apple Platform Agnostic Pure Swift)
  - `EngineBridge.swift`: Native Pure Swift bridge wrapping VietnameseEngine.
  - `InputSessionManager.swift`: Single source of truth for composition state (`composingWord`, `rawWord`, `editCaretBack`), handling feed, backspace, and caret stepping. Shared universally across macOS and iOS.
  - `SmartBilingualDetector.swift`: Heuristic + `NLLanguageRecognizer` bilingual restore engine. Decoupled from OS spell-checker via the `SpellCheckerProvider` protocol. Enforces stop-coda tone rules (`-c, -ch, -p, -t` require Sắc/Nặng) and impossible diphthong detection.
  - `MacSpellChecker.swift`: `NSSpellChecker` implementation for macOS injected into `SmartBilingualDetector` at startup (64K LRU cache).
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

- **`Sources/VieLotusLab`**: Diagnostics & External Event Observer App
  - `LabApp.swift`: SwiftUI Inspector & trace recording suite (`VieLotusLab.dmg`).
  - Observes external app AX focus and keystroke streams with strict privacy masking.
  - One-click closed-loop diagnostic bundle export (JSON & Markdown).

- **`Sources/VieLotusTrace`**: Diagnostic & Trace Data Contracts
  - Trace event schemas, sanitized payload serialization, and export formatting.

- **`Sources/VieLotusCLI`**: Command Line Harness
  - `main.swift`: High-performance benchmark and interactive REPL test runner.
  - `Resources/test_suite.csv`: Bundled regression test suite (9,091 test cases).

## Benchmark Regression Matrix (v1.1.0 Milestone)

The official regression suite tests 9,091 words across 5 behavioral categories:
- `restore_raw`: Restoring English words mangled by Telex rules: **7,174 / 7,216 (99.42%)**.
- `ambiguous_needs_context`: Ambiguous English/Vietnamese spellings tested in context: **1,046 / 1,047 (99.90%)**.
- `transform`: Pure Vietnamese syllable transformation: **399 / 400 (99.75%)**.
- `keep_as_typed`: Untouched English vocabulary: **361 / 362 (99.72%)**.
- `cancel_keep_composed`: Trailing cancellation behavior: **66 / 66 (100.00%)**.
- **Overall Pass Rate:** **99.51%** (9,046 / 9,091).

### Bug Words Breakdown (45 Remaining Failing Test Cases)

1. **`transform` (1 case)**:
   - `vieejt-nam` -> Expected: `việt-nam`, Got: `viêt-nạm` (hyphen mid-word causes Nặng tone buffer displacement across the hyphen boundary).
2. **`ambiguous_needs_context` (1 case)**:
   - `SER` -> Expected: `SER`, Got: `SẺ` (all-caps acronym without dictionary match falls through to Telex `E + R = Ẻ`).
3. **`keep_as_typed` (1 case)**:
   - `oz` -> Expected: `oz`, Got: `o` (Telex `z` key acts as diacritic remover, consuming `z`).
4. **`restore_raw` (42 cases)**:
   - Words typed in isolation whose transformed form resembles valid Vietnamese phonotactics and are not in common word lists:
     - Diphthongs / Codas: `thereof` (`theèo`), `gains` (`gaín`), `chains` (`chaín`), `asin` (`aín`), `cure` (`củe`), `sox` (`sõ`), `layers` (`laýe`), `nursery` (`nuẻy`), `dairy` (`daỉy`), `lauren` (`lauẻn`), `ons` (`ón`), `pins` (`pín`), `syria` (`syỉa`), `tires` (`tíe`), `suits` (`suít`), `refuse` (`reúe`), `mixing` (`miĩng`), `sims` (`sím`), `suse` (`súe`), `carey` (`caẻy`), `horizon` (`hoion`), `surfing` (`suìng`), `pursue` (`puúe`), `mesa` (`méa`), `pens` (`pén`), `worm` (`ưỏm`), `deaf` (`dèa`), `tions` (`tión`), `peas` (`péa`), `ww` (`w`), `touring` (`touỉng`), `hayes` (`haýe`), `tear` (`tẻa`), `bufing` (`buìng`), `mixer` (`mỉe`), `wan` (`ưan`), `persian` (`peián`), `seas` (`séa`), `pose` (`poé`), `meyer` (`meỷe`), `peers` (`pế`), `ours` (`óu`).

*(Note: 35+ previously failing core words such as `more`, `your`, `are`, `we`, `bios`, `yarn`, `aes`, `await`, `ios`, `nginx`, `nostr`, `sizeof`, `uefi`, `where`, `there`, `their`, `share`, `before`, `sure`, `were`, `care`, `core`, `search`, `our`, `use`, `year`, `years`, `next`, `music`, `post`, `very`, `does`, `research`, `life`, `way` are now 100% PASS).*
