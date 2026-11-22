#!/usr/bin/env node
/*
 * VieLotusIM (Sen Việt) — WebAssembly SDK Regression & Parity Test Suite
 * Verifies:
 *   1. Zero-import freestanding WASM binary & session slot lifecycle
 *   2. Both inline (dist/vielotus.mjs) and external (dist/vielotus-external.mjs) loaders
 *   3. Full 9,091-case official regression suite (Primary + Symmetric No-Context + Single-Path VN)
 *   4. All ratified cross-engine parity cases from scripts/test_cross_engine_parity.py
 *   5. VNI, Modern/Classic orthography, Quick Telex, Macros (default + custom JSON), Backspace, Isolation
 */

import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { performance } from "node:perf_hooks";

import * as inlineSdk from "../dist/vielotus.mjs";
import * as externalSdk from "../dist/vielotus-external.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(__dirname, "../../..");
const CSV_PATH = path.join(REPO_ROOT, "Sources/VieLotusCLI/Resources/test_suite.csv");
const PARITY_PY_PATH = path.join(REPO_ROOT, "scripts/test_cross_engine_parity.py");

async function testBinaryAndLoaders() {
  const inlineBytes = await inlineSdk.getWasmBytes();
  const externalBytes = await externalSdk.getWasmBytes();
  assert.equal(inlineBytes.length, externalBytes.length, "Inline and external WASM byte lengths must match");
  assert.deepEqual(inlineBytes, externalBytes, "Inline and external WASM bytes must be bit-identical");

  const mod = await WebAssembly.compile(inlineBytes);
  const imports = WebAssembly.Module.imports(mod);
  assert.equal(imports.length, 0, `Expected 0 WASM imports (freestanding), got ${imports.length}`);

  // Test inline loader
  const e1 = await inlineSdk.createEngine();
  assert.equal(e1.typeString("Vieejt Nam "), "Việt Nam ");
  assert.equal(e1.activeSessions, 1);
  assert.equal(e1.maxSessions, 32);
  e1.destroy();
  assert.equal(e1.destroyed, true);
  assert.equal(e1.activeSessions, 0);

  // Test external loader (file URL + wasmBinary override)
  const e2 = await externalSdk.createEngine();
  assert.equal(e2.typeString("DDawsk Lawsk "), "Đắk Lắk ");
  e2.destroy();
  assert.equal(e2.activeSessions, 0);

  const e3 = await externalSdk.createEngine({ wasmBinary: externalBytes });
  assert.equal(e3.typeString("Kroong Pawcs "), "Krông Pắc ");
  e3.destroy();

  // Test streaming / precompiled WebAssembly.Module instantiation path
  const { createEngineFromSource } = await import("../dist/core.mjs");
  const e4 = await createEngineFromSource(mod);
  assert.equal(e4.typeString("chi as, same as "), "chi á, same as ");
  e4.destroy();
  assert.equal(e4.activeSessions, 0);

  // Test isolated WebAssembly.Instance creation
  const isolated = await inlineSdk.createEngine({ isolate: true });
  assert.equal(isolated.typeString("tieengs Vieejt "), "tiếng Việt ");
  assert.equal(isolated.activeSessions, 1);
  isolated.destroy();
  assert.equal(isolated.activeSessions, 0);

  console.log(`[PASS] Binary & Loaders: ${inlineBytes.length} bytes, 0 imports, inline + external + isolate OK`);
}

async function testFeaturesAndModes() {
  const eng = await inlineSdk.createEngine();

  // 1. VNI mode
  eng.setOptions({ inputMethod: "vni", smartBilingual: true });
  assert.equal(eng.getOptions().inputMethod, "vni");
  const vniCases = [
    ["Vie65t Nam ", "Việt Nam "],
    ["tie61ng Vie65t ", "tiếng Việt "],
    ["D9a81k La81k ", "Đắk Lắk "],
    ["Kro6ng Pa81c ", "Krông Pắc "],
    ["download ", "download "],
    ["github ", "github "],
  ];
  for (const [inp, exp] of vniCases) {
    eng.resetContext();
    const got = eng.typeString(inp);
    assert.equal(got, exp, `VNI failed for ${JSON.stringify(inp)}: got ${JSON.stringify(got)}, expected ${JSON.stringify(exp)}`);
  }

  // 2. Modern vs Classic Orthography (hoà vs hòa, thuỷ vs thủy)
  eng.setOptions({ inputMethod: "telex", modernOrthography: true });
  eng.resetContext();
  assert.equal(eng.typeString("hoaf "), "hoà ");
  eng.resetContext();
  assert.equal(eng.typeString("thuyr "), "thuỷ ");

  eng.setOptions({ modernOrthography: false });
  eng.resetContext();
  assert.equal(eng.typeString("hoaf "), "hòa ");
  eng.resetContext();
  assert.equal(eng.typeString("thuyr "), "thủy ");
  eng.setOptions({ modernOrthography: true });

  // 3. Quick Telex (cc -> ch, gg -> gi, qq -> qu)
  eng.setOptions({ quickTelex: true });
  eng.resetContext();
  assert.equal(eng.typeString("ccao "), "chao ");
  eng.resetContext();
  assert.equal(eng.typeString("ggas "), "giá ");
  eng.resetContext();
  assert.equal(eng.typeString("qqanr "), "quản ");
  eng.setOptions({ quickTelex: false });

  // 4. Macros (default + custom JSON + casing + reset)
  eng.setOptions({ macroEnabled: true });
  eng.resetDefaultMacros();
  eng.resetContext();
  assert.equal(eng.typeString("hn "), "Hà Nội ");
  eng.resetContext();
  assert.equal(eng.typeString("HN "), "HÀ NỘI ");

  const loaded = eng.loadMacros({ sv: "Sen Việt", vn: "Việt Nam" });
  assert.equal(loaded, true, "loadMacros() should return true for valid JSON");
  eng.resetContext();
  assert.equal(eng.typeString("sv "), "Sen Việt ");
  eng.resetContext();
  assert.equal(eng.typeString("SV "), "SEN VIỆT ");
  eng.resetContext();
  assert.equal(eng.typeString("hn "), "hn ", "Custom macro load replaces defaults until reset");

  eng.resetDefaultMacros();
  eng.resetContext();
  assert.equal(eng.typeString("hn "), "Hà Nội ");
  eng.setOptions({ macroEnabled: false });

  // 5. Backspace recovery
  eng.resetContext();
  assert.equal(eng.typeString("vieejtk< ", { interpretBackspace: true }), "việt ");
  eng.resetContext();
  assert.equal(eng.typeString("vieejk<t ", { interpretBackspace: true }), "việt ");
  eng.resetContext();
  assert.equal(eng.typeString("hoa downw< ", { interpretBackspace: true }), "hoa dơn ");

  // 6. Session pool exhaustion guard + clean reuse
  eng.destroy();
  const pool = [];
  for (let i = 0; i < 32; i++) {
    pool.push(await inlineSdk.createEngine());
  }
  assert.equal(pool[0].activeSessions, 32);
  await assert.rejects(
    () => inlineSdk.createEngine(),
    /session pool exhausted/i,
    "33rd shared session should throw clean RangeError"
  );
  // Isolated instance still succeeds even when shared pool is full
  const extraIso = await inlineSdk.createEngine({ isolate: true });
  assert.equal(extraIso.typeString("sen "), "sen ");
  extraIso.destroy();

  for (const s of pool) s.destroy();
  const check = await inlineSdk.createEngine();
  assert.equal(check.activeSessions, 1);
  check.destroy();

  console.log("[PASS] Features: VNI, Modern/Classic Orthography, Quick Telex, Macros, Backspace, 32-Slot Pool OK");
}

function parseRatifiedParityCases() {
  const src = fs.readFileSync(PARITY_PY_PATH, "utf8");
  const startIdx = src.indexOf("RATIFIED_PARITY_SUITE");
  assert.ok(startIdx >= 0, "Could not locate RATIFIED_PARITY_SUITE in scripts/test_cross_engine_parity.py");
  const slice = src.slice(startIdx);
  const endIdx = slice.indexOf("\n]");
  const block = slice.slice(0, endIdx);
  const re = /^\s*\("((?:\\.|[^"\\])*)",\s*"((?:\\.|[^"\\])*)",\s*"((?:\\.|[^"\\])*)"\),/gm;
  const cases = [];
  let m;
  while ((m = re.exec(block)) !== null) {
    cases.push({ input: m[1], expected: m[2], note: m[3] });
  }
  return cases;
}

async function testRatifiedParitySuite() {
  const cases = parseRatifiedParityCases();
  assert.ok(cases.length >= 149, `Expected >= 149 ratified parity cases, parsed ${cases.length}`);

  const eng = await inlineSdk.createEngine({
    inputMethod: "telex",
    grammarProfile: "senFlex",
    smartBilingual: true,
    modernOrthography: true,
  });

  const failures = [];
  for (const c of cases) {
    eng.resetContext();
    const got = eng.typeString(c.input, { interpretBackspace: true, commit: true }).trimEnd();
    if (got !== c.expected) {
      failures.push(`${JSON.stringify(c.input)} -> ${JSON.stringify(got)} (expected ${JSON.stringify(c.expected)}) [${c.note}]`);
    }
  }
  eng.destroy();

  assert.equal(
    failures.length,
    0,
    `Parity mismatches (${failures.length}/${cases.length}):\n  ${failures.slice(0, 10).join("\n  ")}`
  );
  console.log(`[PASS] Ratified Cross-Engine Parity Suite: ${cases.length} / ${cases.length} (100.00%)`);
}

async function testOfficial9091Suite() {
  const known = new Set([
    "transform",
    "keep_as_typed",
    "cancel_keep_composed",
    "restore_raw",
    "ambiguous_needs_context",
  ]);
  const lines = fs.readFileSync(CSV_PATH, "utf8").split(/\r?\n/);
  const rows = [];
  for (let i = 1; i < lines.length; i++) {
    const line = lines[i];
    if (!line.trim()) continue;
    const cols = line.split(",");
    if (cols.length < 9) continue;
    const behavior = cols[5];
    if (!known.has(behavior)) continue;
    const expectedRaw = cols[4];
    const expected = expectedRaw.includes(" / ")
      ? expectedRaw.split(" / ").map((s) => s.trim())
      : [expectedRaw.trim()];
    rows.push({
      suite: cols[0],
      input: cols[1],
      naiveTelex: cols[3],
      expected,
      behavior,
      whitelistSafe: cols[8],
    });
  }
  assert.equal(rows.length, 9091, `Expected 9,091 official regression rows, got ${rows.length}`);

  const eng = await inlineSdk.createEngine({
    inputMethod: "telex",
    grammarProfile: "senFlex",
    smartBilingual: true,
    modernOrthography: true,
  });

  const bucketTot = {};
  const bucketPass = {};
  let passed = 0;
  let vnTot = 0;
  let vnPass = 0;
  let neverTot = 0;
  let neverPass = 0;
  let bothPass = 0;
  let totalKeys = 0;

  const t0 = performance.now();
  for (const r of rows) {
    const bilingual = r.behavior !== "transform" && r.behavior !== "cancel_keep_composed";
    const primeEn = r.behavior === "ambiguous_needs_context";

    eng.resetContext();
    eng.setOptions({ smartBilingual: bilingual });
    if (primeEn) {
      eng.appendContext("he");
      eng.appendContext("is");
    }
    totalKeys += r.input.length;
    const got = eng.typeString(r.input, { interpretBackspace: true, commit: true });
    const ok = r.expected.includes(got);
    bucketTot[r.behavior] = (bucketTot[r.behavior] || 0) + 1;
    if (ok) {
      passed++;
      bucketPass[r.behavior] = (bucketPass[r.behavior] || 0) + 1;
    }

    if (
      r.behavior === "ambiguous_needs_context" &&
      r.suite !== "case_variant" &&
      (r.whitelistSafe === "never" || r.whitelistSafe === "degrades_vn")
    ) {
      eng.resetContext();
      eng.setOptions({ smartBilingual: true });
      totalKeys += r.input.length;
      const gotVn = eng.typeString(r.input, { interpretBackspace: true, commit: true });
      const vnOk = gotVn === r.naiveTelex;
      vnTot++;
      if (vnOk) vnPass++;
      if (ok && vnOk) bothPass++;
      if (r.whitelistSafe === "never") {
        neverTot++;
        if (vnOk) neverPass++;
      }
    }
  }
  const elapsedMs = performance.now() - t0;
  eng.destroy();

  console.log("\n=== @vielotus/core WASM on Official 9,091-Case Suite ===");
  for (const k of ["transform", "keep_as_typed", "cancel_keep_composed", "restore_raw", "ambiguous_needs_context"]) {
    const p = bucketPass[k] || 0;
    const t = bucketTot[k] || 0;
    console.log(`  ${k.padEnd(25)}: ${String(p).padStart(4)} / ${String(t).padEnd(4)} (${((100 * p) / t).toFixed(2)}%)`);
  }
  console.log(`  OVERALL PRIMARY          : ${passed} / ${rows.length} (${((100 * passed) / rows.length).toFixed(2)}%)`);
  console.log(`  vn_survives_collision    : ${vnPass} / ${vnTot} (${((100 * vnPass) / vnTot).toFixed(2)}%)`);
  console.log(`  whitelist_safe = never   : ${neverPass} / ${neverTot} (${((100 * neverPass) / neverTot).toFixed(2)}%)`);
  console.log(`  ambiguous_both_sides     : ${bothPass} / ${vnTot} (${((100 * bothPass) / vnTot).toFixed(2)}%)`);
  console.log(
    `  Speed                    : ${elapsedMs.toFixed(1)} ms for ${totalKeys} keystrokes (${Math.round(
      totalKeys / (elapsedMs / 1000)
    ).toLocaleString()} keys/sec, ${((elapsedMs * 1000) / totalKeys).toFixed(2)} µs/key)\n`
  );

  assert.equal(passed, rows.length, `Primary suite regression: ${passed}/${rows.length}`);
  assert.equal(neverPass, neverTot, `Critical single-path VN loss: ${neverPass}/${neverTot}`);
  assert.equal(bothPass, vnTot, `Symmetric ambiguous_both_sides regression: ${bothPass}/${vnTot}`);
}

await testBinaryAndLoaders();
await testFeaturesAndModes();
await testRatifiedParitySuite();
await testOfficial9091Suite();
console.log("ALL WASM CORE SUITE CHECKS PASSED.");
