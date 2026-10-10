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
   - Tích hợp trí tuệ song ngữ thông minh (Smart Bilingual) đạt độ chính xác **99.99%**, không làm hỏng từ tiếng Anh hay code khi gõ.

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
- `restore_raw`: Restoring English words mangled by Telex rules: **7,215 / 7,216 (99.99%)**.
- `ambiguous_needs_context`: Ambiguous English/Vietnamese spellings tested in context: **1,047 / 1,047 (100.00%)**.
- `transform`: Pure Vietnamese syllable transformation: **400 / 400 (100.00%)**.
- `keep_as_typed`: Untouched English vocabulary: **362 / 362 (100.00%)**.
- `cancel_keep_composed`: Trailing cancellation behavior: **66 / 66 (100.00%)**.
- **Overall Pass Rate:** **99.99%** (9,090 / 9,091).

### Bug Words Breakdown (1 Remaining Failing Test Case)

1. **`restore_raw` (1 case)**:
   - `ww` -> Expected: `ww`, Got: `w` (Special prefix shorthand handling in browser URLs).
