# AGENTS.md — VietLotusIM (Sen Việt)

## Build & Test Commands

```bash
swift build                             # Build all targets (Core, App, CLI, Lab, Trace)
swift test                              # Run unit tests (102 tests: EngineBridge, InputSessionManager, SmartBilingual, MacroEngine, ClientAdapter, PresentationRules, VNCollisionRatchet, KeyboardPreferences, WordSuggestionEngine)
swift run VieLotusCLI --benchmark       # Run official 9,091-case regression suite (see Benchmark Regression Matrix)
swift run VieLotusCLI --benchmark --json  # Same suite + one machine-readable BENCHMARK_JSON line
./scripts/benchmark_ratchet.sh          # Gate every metric against scripts/ratchet_floors.env (worst of 3 runs)
./scripts/benchmark_ratchet.sh --with-latency  # Gate accuracy + p99 latency ceilings and throughput floor
./scripts/benchmark_ratchet.sh --ratchet  # Gate, then tighten any floor that improved (never loosens)
swift run VieLotusCLI --stress          # Run 250,000-keystroke high-throughput stress & endurance benchmark
swift run VieLotusCLI                   # Interactive REPL typing test harness
./scripts/build_imk.sh                  # Build release universal VieLotusIM.app + ad-hoc codesign
./scripts/build_pkg.sh                  # Build auto-registering installer package (VieLotusIM.pkg)
./scripts/build_lab.sh                  # Build release universal VieLotusLab.app
```

## Ultimate Mission & North Star (Sứ Mệnh Tối Thượng)

VieLotusIM (Sen Việt) được thiết kế và xây dựng theo tiêu chuẩn kỹ thuật cao nhất của Apple để trở thành **bộ gõ tiếng Việt thế hệ mới thay thế hoàn hảo cho lõi engine mặc định hiện tại mà Apple đang sử dụng** (vốn kế thừa từ mã nguồn cũ của tác giả Phạm Kim Long từ nhiều năm trước).

### Tiêu Chuẩn "Pure Apple Native" (Tuyệt Đối Không Thoả Hiệp):
1. **Tuân thủ 100% chuẩn mực Apple**: Chỉ sử dụng các framework và giao thức chính thống của hệ điều hành — `InputMethodKit` (`IMKInputController`, `IMKServer`, `IMKTextInput`) trên macOS và chuẩn bị cho `UIKit` (`UIInputViewController`, `UITextDocumentProxy`) trên iOS / iPadOS / visionOS.
2. **Tuyệt đối KHÔNG dùng API can thiệp tầng thấp**: TUYỆT ĐỐI KHÔNG sử dụng `CGEventSource`, `CGEventTap`, `Carbon` keycodes, hay bất kỳ mánh lới (hacks) đòi hỏi quyền Trợ năng (Accessibility) nào.
3. **Pure Swift 6 & Memory Safety**: Toàn bộ lõi `VieLotusCore` được viết bằng Swift thuần túy, an toàn bộ nhớ, bất đồng bộ hiện đại, không phụ thuộc vào thư viện C/C++ cổ điển.
4. **Giải quyết triệt để các lỗi cố hữu của bộ gõ Apple cũ**:
   - Khắc phục hoàn toàn tình trạng nuốt chữ, mất ký tự khi gõ nhanh.
   - Triệt tiêu lỗi nhảy con trỏ, lặp từ khi nhập liệu trên trình duyệt web, thanh tìm kiếm và ứng dụng Electron/React.
   - Tương thích hoàn hảo với Terminal / CLI hiện đại (Ghostty, Alacritty, Kitty, Claude Code) bằng cơ chế Direct Replacement và đồng bộ UTF-16 code units.
   - Tích hợp trí tuệ song ngữ thông minh (Smart Bilingual) đạt **99.97%** trên bộ regression 9.091 ca, không làm hỏng từ tiếng Anh hay code khi gõ. Con số này phải luôn được trích dẫn **kèm** vế đối xứng `vn_survives_collision` (86.33%) — xem *Benchmark Regression Matrix*. Một vế đơn lẻ luôn phóng đại khả năng engine.

## Architecture

VietLotusIM is a modern, native macOS Input Method built on Apple's `InputMethodKit` framework, avoiding invasive low-level event taps (`CGEventTap`) or Accessibility permissions.

### Modules:
- **`Sources/VieLotusCore`**: Shared Domain & Engine Library (Apple Platform Agnostic Pure Swift)
  - `EngineBridge.swift`: Native Pure Swift bridge wrapping VietnameseEngine.
  - `InputSessionManager.swift`: Single source of truth for composition state (`composingWord`, `rawWord`, `editCaretBack`), handling feed, backspace, and caret stepping. Shared universally across macOS and iOS.
  - `SmartBilingualDetector.swift`: Heuristic + `NLLanguageRecognizer` bilingual restore engine. Decoupled from OS spell-checker via the `SpellCheckerProvider` protocol. Enforces stop-coda tone rules (`-c, -ch, -p, -t` require Sắc/Nặng) and impossible diphthong detection.
  - `MacSpellChecker.swift`: `NSSpellChecker` implementation for macOS injected into `SmartBilingualDetector` at startup (64K LRU cache).
  - `ClientAdapter.swift`: Thread-safe app categorization and dynamic marked-text fallback. Resolution order for presentation mode: user per-app override → user global preference → `typing-modes.yml` data rules → built-in category heuristic.
  - `PresentationRules.swift`: Parser + loader for `Resources/typing-modes.yml`, a flat `bundle-id: mode` subset of YAML (no external dependency). Exact, `*substring*`, `prefix*` and `*suffix` keys, first match wins, malformed lines ignored so a hand-edited file cannot take the IME down. Search order: `~/Library/Application Support/VieLotusIM/` → app bundle `Contents/Resources/` → `Bundle.module`. `reloadPresentationRulesIfChanged()` costs one `stat` and is called from `activateServer`, never from the keystroke path.

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




## Benchmark Regression Matrix

The official regression suite runs 9,091 cases. Numbers below were measured on
**2026-10-11** with a release build, after the two harness fixes in *Harness
Correctness*. **They are lower than the previously published 99.99% because that figure
was partly an artifact of a contaminated harness, not because the engine regressed.**

### Primary buckets (each row driven once, under the condition its label names)

- `transform`: Pure Vietnamese syllable transformation: **400 / 400 (100.00%)**.
- `keep_as_typed`: Untouched English vocabulary: **362 / 362 (100.00%)**.
- `cancel_keep_composed`: Trailing cancellation behavior: **66 / 66 (100.00%)**.
- `restore_raw`: Restoring English words mangled by Telex rules: **7,213 / 7,216 (99.96%)**.
- `ambiguous_needs_context`: Ambiguous spellings driven **with** an English context
  primed: **1,047 / 1,047 (100.00%)**.
- **Overall: 99.97% (9,088 / 9,091).**

### Symmetric buckets (the same ambiguous rows driven a second time, with NO context)

`ambiguous_needs_context` at 100% only proves *"English context in → English out"*. It
says nothing about the cost side of that trade, so the harness replays the same rows
without a context:

- `vn_survives_collision` — the **373** lowercase rows carry no orthographic English
  signal, so the Vietnamese syllable must survive: **322 / 373 (86.33%)**.
  - `whitelist_safe = never` (the **only** keystroke path to that syllable): **159 / 180**.
  - `whitelist_safe = degrades_vn` (one of several paths): **163 / 193**.
- `ambiguous_both_sides` — correct on **both** sides: English with a context *and*
  Vietnamese without: **322 / 373 (86.33%)**. **Quote this number, not either half.**
- `case_signal_restores` — the **674** `case_variant` rows replayed with no context,
  expecting capitalisation alone to restore English: **66 / 674 (9.79%)**. Ratcheted so it
  cannot regress, but **not gated as a quality target**: whether capitalisation alone
  *should* restore English without a context is an undecided product policy, and the suite
  files those rows under `ambiguous_needs_context`, i.e. it intends them to be judged with
  a context.

### Harness Correctness (why the numbers moved)

1. **Per-row context isolation.** `InputSessionManager.reset()` deliberately does *not*
   clear `context` (it must survive across words in real typing), but `driveInput` only
   *assigned* it when priming. Every row after the first primed one therefore inherited
   `"he is"`. Fixed by assigning unconditionally. This is what exposed `gif` and `gis` as
   genuine `restore_raw` misses and moved overall from 99.99% to 99.97%.
2. **Suite self-consistency scan.** The harness reports two dataset properties at load:
   - *Satisfiability* — whether any input is asked for two different outputs under
     identical drive conditions. Currently **clean**, so 99.97% is a real ceiling and not a
     dataset artifact. Grouping by drive condition matters: `gif` legitimately expects `gì`
     with Smart Bilingual off and `gif` with it on.
   - *Policy coherence* — **3 words** (`aaa`, `gif`, `ww`) carry `whitelist_safe = never`
     on one row and `= yes` on another: the dataset contradicts itself about whether
     restoring them is acceptable. Two of those three are exactly two of the three
     remaining `restore_raw` failures.

### Bug Words Breakdown (3 Remaining Failing Cases, all `restore_raw`)

1. `gif` → Expected `gif`, Got `gì`. **Also a `never`/`yes` policy conflict in the CSV.**
   The `vn_positive` row expects `gì` and its note says never to whitelist it for English
   restore, while the `en_top10k` row expects `gif`.
2. `gis` → Expected `gis`, Got `gí`. Genuine miss; no conflicting row.
3. `ww` → Expected `ww`, Got `w`. **Also a `never`/`yes` policy conflict in the CSV**
   (`spec_dependent` expects `w`, `en_top10k` expects `ww`).

Reconcile the CSV before chasing #1 and #3 in the engine.

### Ratchet Floors

`scripts/ratchet_floors.env` holds one floor per metric. `scripts/benchmark_ratchet.sh`
runs the suite N times in **separate processes**, gates on the **worst** result per metric
(a single lucky run is not evidence), and `--ratchet` rewrites a floor only upward,
truncated toward zero so it never sits above the measurement it came from. A worse build
fails; it never lowers a floor. The script is bash 3.2 compatible because that is what
`/bin/bash` is on every macOS.

The 21 critical `vn_survives_collision` losses are additionally pinned by
`Tests/VieLotusCoreTests/VNCollisionRatchetTests.swift`, which reads the same CSV as the
CLI and fails if a **new** word loses its only Vietnamese keystroke path *and* fails if a
listed word heals without `acceptedCriticalLosses` being shortened.
