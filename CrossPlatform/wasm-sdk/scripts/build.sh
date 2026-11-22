#!/usr/bin/env bash
set -euo pipefail

SDK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO_ROOT="$(cd "$SDK_DIR/../.." && pwd)"
CORE_DIR="$REPO_ROOT/Sources/VieLotusCoreWindows"
DIST_DIR="$SDK_DIR/dist"
BUILD_TMP="$SDK_DIR/.build-tmp"
STAGE_PAGES_DIR=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --stage-pages)
      shift
      STAGE_PAGES_DIR="${1:-}"
      if [ -z "$STAGE_PAGES_DIR" ]; then
        echo "ERROR: --stage-pages requires a target directory path." >&2
        exit 1
      fi
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
  shift
done

# Locate LLVM clang++ with wasm32 backend + wasm-ld
find_clang() {
  for cand in \
    "${CLANGXX:-}" \
    "/opt/homebrew/opt/llvm/bin/clang++" \
    "/usr/local/opt/llvm/bin/clang++" \
    "$(command -v clang++ 2>/dev/null || true)"; do
    if [ -n "$cand" ] && [ -x "$cand" ]; then
      if "$cand" --target=wasm32 -x c++ -c -o /dev/null - </dev/null 2>/dev/null; then
        echo "$cand"
        return 0
      fi
    fi
  done
  return 1
}

find_wasm_ld() {
  for cand in \
    "${WASM_LD:-}" \
    "/opt/homebrew/bin/wasm-ld" \
    "/opt/homebrew/opt/llvm/bin/wasm-ld" \
    "/usr/local/bin/wasm-ld" \
    "/usr/bin/wasm-ld" \
    "$(command -v wasm-ld 2>/dev/null || true)"; do
    if [ -n "$cand" ] && [ -x "$cand" ]; then
      echo "$cand"
      return 0
    fi
  done
  return 1
}

CLANG_BIN="$(find_clang)" || {
  echo "ERROR: Could not find an LLVM clang++ supporting --target=wasm32." >&2
  echo "macOS: brew install llvm lld | Ubuntu/Debian: sudo apt-get install clang lld" >&2
  exit 1
}

WASM_LD_BIN="$(find_wasm_ld)" || {
  echo "ERROR: Could not find wasm-ld (LLVM lld)." >&2
  echo "macOS: brew install lld | Ubuntu/Debian: sudo apt-get install lld" >&2
  exit 1
}

rm -rf "$BUILD_TMP"
mkdir -p "$DIST_DIR" "$BUILD_TMP/VieLotusLexicon"

# 1. Regenerate canonical FNV-1a lexicon header from plaintext lexicon/*.txt (DFSG-clean)
python3 "$CORE_DIR/scripts/generate_lexicon_hashes.py" \
  --lexicon-dir "$CORE_DIR/lexicon" \
  --output "$BUILD_TMP/VieLotusLexicon/WindowsNativeLexiconGenerated.inc"

# 2. Compile Sources/VieLotusCoreWindows/WindowsNativeEngine.cpp verbatim + freestanding runtime
echo "-> Compiling VieLotus C++20 core to freestanding wasm32..."
"$CLANG_BIN" \
  --target=wasm32 \
  -std=c++20 \
  -Oz \
  -Wall -Wextra -Wno-unused-parameter -Wno-unused-function \
  -fno-exceptions \
  -fno-rtti \
  -fno-threadsafe-statics \
  -fvisibility=hidden \
  -ffunction-sections \
  -fdata-sections \
  -nostdinc \
  -nostdinc++ \
  -nostdlib \
  -isystem "$SDK_DIR/sysroot" \
  -I "$CORE_DIR" \
  -I "$BUILD_TMP" \
  -DVIELOTUS_CAPI_EXPORT='extern "C" __attribute__((visibility("default")))' \
  -fuse-ld="$WASM_LD_BIN" \
  -Wl,--no-entry \
  -Wl,--export-dynamic \
  -Wl,--gc-sections \
  -Wl,--strip-all \
  -Wl,-z,stack-size=262144 \
  "$CORE_DIR/WindowsNativeEngine.cpp" \
  "$SDK_DIR/runtime/wasm_runtime.cpp" \
  -o "$DIST_DIR/vielotus-core.wasm"

# Optional post-link optimization if Binaryen wasm-opt is installed
if command -v wasm-opt >/dev/null 2>&1; then
  echo "-> Optimizing with wasm-opt -Oz..."
  wasm-opt -Oz "$DIST_DIR/vielotus-core.wasm" -o "$DIST_DIR/vielotus-core.wasm"
fi

# 3. Copy ESM core & TypeScript declarations and emit inline + streaming external entrypoints
cp "$SDK_DIR/src/core.mjs" "$DIST_DIR/core.mjs"
cp "$SDK_DIR/src/index.d.ts" "$DIST_DIR/index.d.ts"

node - "$DIST_DIR" <<'NODE_EOF'
import fs from "node:fs";
import path from "node:path";
import zlib from "node:zlib";

const distDir = process.argv[2];
const wasmPath = path.join(distDir, "vielotus-core.wasm");
const wasmBytes = fs.readFileSync(wasmPath);
const wasmB64 = wasmBytes.toString("base64");

const inlineEntry = `/*
 * VieLotusIM (Sen Việt) — Self-Contained ESM Entrypoint (inlined WASM)
 * Zero network fetches; works in bundlers, CDNs, and Node.js.
 * License: MIT
 */
import {
  ACTION,
  INPUT_METHOD,
  GRAMMAR_PROFILE,
  VieLotusEngine,
  isEligibleElement,
  decodeBase64,
  createEngineFromSource,
  attachWithLoader,
} from "./core.mjs";

const WASM_BASE64 = "${wasmB64}";
let cachedBytes = null;

export { ACTION, INPUT_METHOD, GRAMMAR_PROFILE, VieLotusEngine, isEligibleElement };

export async function getWasmBytes() {
  if (!cachedBytes) cachedBytes = decodeBase64(WASM_BASE64);
  return cachedBytes;
}

export async function createEngine(options = {}) {
  return createEngineFromSource(await getWasmBytes(), options);
}

export async function attach(element, options = {}) {
  return attachWithLoader(getWasmBytes, element, options);
}
`;

const externalEntry = `/*
 * VieLotusIM (Sen Việt) — External WASM ESM Entrypoint (Streaming-capable)
 * Loads ./vielotus-core.wasm separately (or via options.wasmUrl / options.wasmBinary).
 * Uses WebAssembly.compileStreaming on HTTPS/HTTP servers serving application/wasm.
 * License: MIT
 */
import {
  ACTION,
  INPUT_METHOD,
  GRAMMAR_PROFILE,
  VieLotusEngine,
  isEligibleElement,
  createEngineFromSource,
  attachWithLoader,
} from "./core.mjs";

let defaultBytesPromise = null;
let defaultModulePromise = null;

export { ACTION, INPUT_METHOD, GRAMMAR_PROFILE, VieLotusEngine, isEligibleElement };

function resolveWasmUrl(wasmUrl) {
  if (!wasmUrl) return new URL("./vielotus-core.wasm", import.meta.url);
  return wasmUrl instanceof URL ? wasmUrl : new URL(String(wasmUrl), import.meta.url);
}

async function fetchBytes(targetUrl) {
  if (targetUrl.protocol === "file:" && typeof process !== "undefined" && process.versions?.node) {
    const { readFile } = await import("node:fs/promises");
    const buf = await readFile(targetUrl);
    return new Uint8Array(buf.buffer, buf.byteOffset, buf.byteLength);
  }
  const resp = await fetch(targetUrl);
  if (!resp.ok) {
    throw new Error(\`Failed to load VieLotus WASM from \${targetUrl}: HTTP \${resp.status}\`);
  }
  return new Uint8Array(await resp.arrayBuffer());
}

async function loadModuleFromUrl(targetUrl) {
  if (targetUrl.protocol === "file:" && typeof process !== "undefined" && process.versions?.node) {
    return WebAssembly.compile(await fetchBytes(targetUrl));
  }
  const resp = await fetch(targetUrl);
  if (!resp.ok) {
    throw new Error(\`Failed to load VieLotus WASM from \${targetUrl}: HTTP \${resp.status}\`);
  }
  const contentType = resp.headers?.get?.("content-type") ?? "";
  if (typeof WebAssembly.compileStreaming === "function" && contentType.includes("application/wasm")) {
    return WebAssembly.compileStreaming(resp);
  }
  return WebAssembly.compile(await resp.arrayBuffer());
}

export async function getWasmBytes(options = {}) {
  if (options.wasmBinary) {
    return options.wasmBinary instanceof Uint8Array
      ? options.wasmBinary
      : new Uint8Array(options.wasmBinary);
  }
  const url = resolveWasmUrl(options.wasmUrl);
  if (!options.wasmUrl) {
    if (!defaultBytesPromise) defaultBytesPromise = fetchBytes(url);
    return defaultBytesPromise;
  }
  return fetchBytes(url);
}

async function loadWasmSource(options = {}) {
  if (options.wasmBinary) {
    return options.wasmBinary instanceof Uint8Array
      ? options.wasmBinary
      : new Uint8Array(options.wasmBinary);
  }
  const url = resolveWasmUrl(options.wasmUrl);
  if (!options.wasmUrl) {
    if (!defaultModulePromise) defaultModulePromise = loadModuleFromUrl(url);
    return defaultModulePromise;
  }
  return loadModuleFromUrl(url);
}

export async function createEngine(options = {}) {
  return createEngineFromSource(await loadWasmSource(options), options);
}

export async function attach(element, options = {}) {
  return attachWithLoader(loadWasmSource, element, options);
}
`;

fs.writeFileSync(path.join(distDir, "vielotus.mjs"), inlineEntry, "utf8");
fs.writeFileSync(path.join(distDir, "vielotus-external.mjs"), externalEntry, "utf8");

// Size telemetry
const report = (label, buf) => {
  const gz = zlib.gzipSync(buf, { level: 9 }).length;
  const br = zlib.brotliCompressSync(buf, {
    params: { [zlib.constants.BROTLI_PARAM_QUALITY]: 11 },
  }).length;
  const kb = (n) => (n / 1024).toFixed(2).padStart(7) + " KB";
  console.log(`  ${label.padEnd(24)} raw:${kb(buf.length)}  gzip:${kb(gz)}  brotli:${kb(br)}`);
};

console.log("\nBuild complete -> dist/");
report("vielotus-core.wasm", wasmBytes);
report("core.mjs", fs.readFileSync(path.join(distDir, "core.mjs")));
report("vielotus.mjs (inline)", Buffer.from(inlineEntry, "utf8"));
report("vielotus-external.mjs", Buffer.from(externalEntry, "utf8"));
NODE_EOF

# 4. Optional: stage a clean static GitHub Pages bundle (external streaming .wasm, zero base64 bloat)
if [ -n "$STAGE_PAGES_DIR" ]; then
  mkdir -p "$STAGE_PAGES_DIR/dist"
  cp "$DIST_DIR/core.mjs" "$STAGE_PAGES_DIR/dist/core.mjs"
  cp "$DIST_DIR/vielotus-external.mjs" "$STAGE_PAGES_DIR/dist/vielotus-external.mjs"
  cp "$DIST_DIR/vielotus-core.wasm" "$STAGE_PAGES_DIR/dist/vielotus-core.wasm"
  node - "$SDK_DIR/demo/index.html" "$STAGE_PAGES_DIR/index.html" <<'STAGE_EOF'
import fs from "node:fs";
const [src, dst] = process.argv.slice(2);
const html = fs.readFileSync(src, "utf8")
  .replace('../dist/vielotus.mjs', './dist/vielotus-external.mjs');
fs.writeFileSync(dst, html, "utf8");
STAGE_EOF
  echo "-> Staged GitHub Pages playground -> $STAGE_PAGES_DIR"
fi

rm -rf "$BUILD_TMP"
