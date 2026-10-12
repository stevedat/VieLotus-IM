# VieLotusIM (Sen Việt)

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platforms](https://img.shields.io/badge/Platforms-macOS%20%7C%20iPadOS%20%7C%20iOS-black.svg)](#architecture)
[![Language](https://img.shields.io/badge/Swift-6.0-orange.svg)](#tech-stack)
[![Accuracy](https://img.shields.io/badge/Regression-99.97%25%20(9%2C088%2F9%2C091)-emerald.svg)](#benchmark-matrix)
[![Website](https://img.shields.io/badge/Website-stevedat.github.io%2FVieLotus--IM-FF5E8E.svg)](https://stevedat.github.io/VieLotus-IM/)

A lightweight, memory-safe Vietnamese input method built natively for the Apple ecosystem (**macOS**, **iOS**, and **iPadOS**). Designed to replace legacy IME cores with a modern, zero-privilege, and crash-resilient architecture.

---

## Tech Stack

```
┌────────────────────────────────────────────────────────────────────────┐
│                        Apple Host Environment                          │
│   macOS (IMKInputController / IMKServer)   │   iOS (UIInputViewController)  │
└───────────────────▲────────────────────────────────────▲───────────────┘
                    │                                    │
┌───────────────────┴────────────────────────────────────┴───────────────┐
│                      VieLotusCore (Pure Swift 6)                       │
│  ┌────────────────────────┐  ┌──────────────────────────────────────┐  │
│  │  InputSessionManager   │  │        SmartBilingualDetector        │  │
│  │  - Composing state     │  │  - Heuristic tone rules              │  │
│  │  - Caret stepping      │  │  - NSSpellChecker / UITextChecker    │  │
│  │  - Telex / VNI engines │  │    via SpellCheckerProvider          │  │
│  └────────────────────────┘  └──────────────────────────────────────┘  │
│  ┌────────────────────────┐  ┌──────────────────────────────────────┐  │
│  │     ClientAdapter      │  │          PresentationRules           │  │
│  │  - App categorization  │  │  - typing-modes.yml (zero-dep)       │  │
│  │  - UTF-16 sync         │  │  - User/App preference overrides     │  │
│  └────────────────────────┘  └──────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────────┘
```

- **Core Engine (`VieLotusCore`)**: Pure Swift 6 with complete memory safety, zero C/C++ dependencies, and zero raw pointers. Built solely on Apple's `Foundation`.
- **macOS Integration (`VieLotusIM`)**: Apple's official `InputMethodKit` (`IMKInputController`, `IMKServer`, `IMKTextInput`). Operates as a native input method bundle.
- **iOS / iPadOS Integration**: `UIKit` (`UIInputViewController`, `UITextDocumentProxy`) sharing the identical underlying core state machine.
- **Bilingual & Lexical Intelligence**: Hybrid rule-based parser paired with `NLLanguageRecognizer` and system spell-checking via the `SpellCheckerProvider` protocol (macOS injects `NSSpellChecker` with a 64K LRU cache).
- **Client Configuration Engine**: `PresentationRules` parses `typing-modes.yml` with a custom zero-dependency parser, resolving application-specific typing behaviors in sub-millisecond time.
- **Diagnostics & Benchmarking**: `VieLotusCLI` and `VieLotusTrace` running a 9,091-case regression suite, latency gates, and continuous ratchet floors.

---

## Technical Challenges

### 1. The "Swallowed Letters" and Dropped Keystrokes in Web/Electron Apps
- **The Problem**: Legacy Vietnamese input methods rely on synthetic backspaces (via `CGEventTap` or Carbon key-up hacks) to delete raw keys and replace them with composed syllables. In modern frameworks with virtual DOMs or asynchronous input queues (Google Docs, Notion, Slack, VS Code Monaco Editor, React/Electron), these artificial backspaces race with user input, causing dropped characters, duplicated words, or cursor jumping.
- **Solution**: VieLotusIM strictly implements Apple's native composition protocol (`setMarkedText:selectionRange:replacementRange:`). Syllables are composed in-flight under an uncommitted underline and committed atomically upon space or punctuation (`insertText:replacementRange:`).

### 2. Bilingual Collisions & English Code Vocabulary
- **The Problem**: Common English words and programming syntax (`git`, `commit`, `test`, `restrict`, `toast`, `blood`, `floor`, `door`, `width`, `const`) collide with Telex transformation keys (`s`, `f`, `r`, `x`, `j`, `w`, `aa`, `ee`, `oo`). Eagerly transforming them breaks English typing, while overly broad whitelisting degrades Vietnamese typing.
- **Solution**: `SmartBilingualDetector` enforces linguistic constraints (e.g. stop-coda tone validation where `-c, -ch, -p, -t` strictly require Sắc/Nặng tones) and evaluates lexical context.

### 3. Preserving Native Undo Stack (`Cmd + Z`)
- **The Problem**: Firing bursts of backspaces corrupts the host application's undo stack, causing `Cmd + Z` to erase full paragraphs rather than stepping back keystroke by keystroke.
- **Solution**: Atomic buffer replacement preserves the text input client's undo manager integrity.

### 4. Terminal & CLI Synchronisation
- **The Problem**: Modern GPU-accelerated terminal emulators (Ghostty, Alacritty, Kitty) manage raw cursor positions and require strict UTF-16 code unit offset synchronization rather than loose Unicode grapheme cluster guesses.
- **Solution**: Direct replacement mode synchronizes UTF-16 code units with the terminal cursor to prevent trailing artifacts.

---

## Architectural Trade-offs

| Decision | Chosen Approach | Alternative | Rationale & Trade-off |
| :--- | :--- | :--- | :--- |
| **System Integration** | **Pure Apple Native (`InputMethodKit`)** | Accessibility API (`CGEventTap` hooks) | **Trade-off:** Cannot intercept keystrokes outside standard text fields. **Benefit:** Requires **zero Accessibility permissions**, eliminates security warnings, prevents keylogger vulnerabilities, and works out-of-the-box. |
| **Privacy & Architecture** | **100% Offline On-Device** | Cloud-based NLP / Telemetry | **Trade-off:** Dictionary updates are bundled with app releases. **Benefit:** Zero network sockets, zero disk logging, sub-millisecond p99 latency, and total privacy for sensitive credentials. |
| **Composition UX** | **Natural Underline Composition** | Instant Direct Injection | **Trade-off:** Displays a subtle system underline while a syllable is assembling. **Benefit:** Prevents web editor race conditions, guaranteeing zero dropped letters on Google Docs, Slack, and Notion. |
| **Core Decoupling** | **`SpellCheckerProvider` Protocol** | Direct `NSSpellChecker` calls in core | **Trade-off:** Requires dependency injection at runtime. **Benefit:** Enables `VieLotusCore` to run universally across macOS, iOS, iPadOS, and headless Linux test runners without UI dependencies. |
| **Configuration Engine** | **Zero-Dependency YAML Subset** | `YAMLEncoder` / External Parser | **Trade-off:** Only supports flat key-value and simple prefix/suffix patterns. **Benefit:** Zero third-party dependencies, instant parsing, and immune to malformed configuration crashes. |

---

## Benchmark Matrix

Measured on **2026-10-11** release build using the bundled 9,091-case regression suite:

| Test Bucket | Test Condition | Passing Rate |
| :--- | :--- | :--- |
| **Pure Vietnamese Transform** | Vietnamese syllables only | **400 / 400 (100.00%)** |
| **English Vocabulary Preservation** | Untouched English dictionary | **362 / 362 (100.00%)** |
| **Tone Cancellation** | Trailing cancel keys | **66 / 66 (100.00%)** |
| **Telex Raw Word Restoration** | Restoring mangled English words | **7,213 / 7,216 (99.96%)** |
| **Ambiguous Spellings (With Context)** | Primed with English context | **1,047 / 1,047 (100.00%)** |
| **Overall Accuracy** | Complete regression suite | **9,088 / 9,091 (99.97%)** |

> [!IMPORTANT]
> **Symmetric Benchmark Disclosure:**
> High English restoration accuracy must never come at the cost of Vietnamese collision survival. When running the ambiguous collision rows **without** English context priming, the engine maintains **86.33% (322 / 373)** Vietnamese syllable survival (`vn_survives_collision`), with all 21 remaining edge cases pinned by ratchet regression tests (`VNCollisionRatchetTests.swift`).

---

## Quick Start

### macOS Installation

#### Option 1: Homebrew (Recommended)
```bash
brew install stevedat/tap/vielotus
```

#### Option 2: Pre-built PKG Installer
1. Download `VieLotusIM.pkg` from the [Latest Release](https://github.com/stevedat/VieLotus-IM/releases/latest).
2. Run the installer (auto-registers the input method).
3. Open **System Settings** $\rightarrow$ **Keyboard** $\rightarrow$ **Text Input** $\rightarrow$ **Edit...**
4. Add **Vietnamese** $\rightarrow$ **Sen Việt** (`VieLotusIM`).
5. Remove the legacy Apple Vietnamese keyboard to prevent input conflicts.

### Building from Source

```bash
# Clone the repository
git clone https://github.com/stevedat/VieLotus-IM.git
cd VieLotus-IM

# Build all targets (Core, App, CLI, Lab, Trace)
swift build -c release

# Run the full unit test suite (102 tests)
swift test

# Run the 9,091-case regression benchmark
swift run VieLotusCLI --benchmark

# Run the ratchet check against benchmark floors
./scripts/benchmark_ratchet.sh

# Build release universal macOS application bundle
./scripts/build_imk.sh

# Build auto-registering installer package (VieLotusIM.pkg)
./scripts/build_pkg.sh
```

---

## License

VieLotusIM is licensed under the [MIT License](LICENSE).
Created and maintained by **Steve Dat** ([@stevedat](https://github.com/stevedat)).
