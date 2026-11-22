# `@vielotus/core` — Sen Việt WebAssembly SDK

Zero-dependency WebAssembly Vietnamese Input Method SDK compiled directly from the unmodified C++20 `Sources/VieLotusCoreWindows/WindowsNativeEngine.cpp` core using freestanding LLVM `wasm32` (no Emscripten, no libc, 0 WASM host imports).

## Key Properties

- **Single Source of Truth:** Compiles `Sources/VieLotusCoreWindows/WindowsNativeEngine.cpp` verbatim (0 lines modified) with deterministic FNV-1a lexicons regenerated from `Sources/VieLotusCoreWindows/lexicon/*.txt`.
- **Compact & Self-Contained:**
  - `dist/vielotus-core.wasm`: **80.60 KB** raw / **39.81 KB** gzip / **35.22 KB** Brotli (`0` host imports).
  - `dist/vielotus.mjs` (inlined base64 WASM): **108.29 KB** raw / **49.36 KB** gzip / **43.69 KB** Brotli — zero extra network fetches or bundler `.wasm` config.
  - `dist/vielotus-external.mjs`: **1.76 KB** raw / **0.65 KB** Brotli — loads `vielotus-core.wasm` separately (or accepts `wasmUrl` / `wasmBinary`).
- **Smart Bilingual & Production DOM Safety:**
  - Full Telex + VNI, Modern/Classic orthography, Quick Telex (`cc`/`gg`/`qq`), Relaxed Coda, and JSON Macros.
  - `attach(element, options)` supports `<input>`, `<textarea>`, and `contenteditable`.
  - Automatically skips `password`, `email`, `url`, `number`, `tel`, and non-text inputs.
  - **4-Layer OS-IME Auto-Yield (`yieldToSystemIme: true`):** Detects active OS Vietnamese IMEs (`compositionstart`, `keyCode 229`/`isComposing`, direct precomposed Vietnamese keystrokes, and foreign `insertText` diacritics while staying immune to paste/undo) and pauses cleanly to prevent double-diacritic collisions. Re-enable anytime via `Ctrl+Space` or `controller.setEnabled(true)`.

## Quick Start

### Attach to a DOM input / textarea / contenteditable

```js
import { attach } from "@vielotus/core";

const ime = await attach(document.querySelector("textarea"), {
  inputMethod: "telex",      // "telex" | "vni"
  smartBilingual: true,
  modernOrthography: true,
  yieldToSystemIme: true,
  onForeignIme: ({ reason }) => {
    console.log("Paused because system IME was detected:", reason);
  },
});

// Toggle programmatically or clean up on unmount
ime.setOptions({ inputMethod: "vni" });
ime.destroy();
```

### Low-level Engine API (headless / Node.js / Workers / custom editors)

```js
import { createEngine } from "@vielotus/core";

const engine = await createEngine({
  inputMethod: "telex",
  smartBilingual: true,
});

console.log(engine.typeString("DDawsk Lawsk — Kroong Pawcs "));
// => "Đắk Lắk — Krông Pắc "

engine.destroy();
```

### External `.wasm` Loader (streaming / CDN / custom binary)

```js
import { createEngine } from "@vielotus/core/external";

const engine = await createEngine({
  wasmUrl: "/assets/vielotus-core.wasm",
});
```

## Build & Verify

Prerequisites: Homebrew LLVM (`clang++` with `wasm32` target) + `lld` (`wasm-ld`), Python 3, Node.js 18+.

```bash
cd CrossPlatform/wasm-sdk
npm run build
npm test
```

### Stage Static GitHub Pages Playground (Streaming `.wasm`, Zero Base64 Bloat)

```bash
./CrossPlatform/wasm-sdk/scripts/build.sh --stage-pages /tmp/vielotus-try
python3 -m http.server 8765 --directory /tmp/vielotus-try
# Open http://localhost:8765/
```

### Preview Directly Inside the SDK Folder

```bash
cd CrossPlatform/wasm-sdk
python3 -m http.server 8765
# Open http://localhost:8765/demo/
```

## Verified Benchmark Results (2026-11-22)

Measured in Node.js (`v26.5.0`, V8 WebAssembly) via `npm test` (`test/test_suite.mjs`) against `Sources/VieLotusCLI/Resources/test_suite.csv` (9,091 rows, Telex + `senFlex` + Smart Bilingual, isolated per-row session state) and `scripts/test_cross_engine_parity.py`:

| Metric | Result |
| --- | --- |
| **Overall Primary Suite** (9,091 cases) | **9,091 / 9,091 (100.00%)** |
| **Symmetric No-Context (`ambiguous_both_sides`)** | **369 / 369 (100.00%)** |
| **Single-Path Vietnamese Preservation (`whitelist_safe = never`)** | **179 / 179 (100.00%)** |
| **Ratified Cross-Engine Parity Suite** (Swift 6 ↔ C++20 ↔ WASM) | **149 / 149 (100.00%)** |
| **Throughput** (63,730 keystrokes) | **~1.25–1.45 µs/key (~690k–800k keys/sec)** |

## License

MIT
