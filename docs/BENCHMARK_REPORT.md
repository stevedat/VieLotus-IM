# VieLotusIM — Official Benchmark & Regression Verification Report

> **Suite Version:** 9,091 Primary Cases + Symmetric No-Context Replay (10,140 Total Drives)
> **Engine Target:** `VieLotusCore` (Pure Swift 6)

---

## 1. Executive Summary

VieLotusIM (Sen Việt) is verified against an automated, deterministic 9,091-case regression suite covering Vietnamese syllable transformations (Telex & VNI), English vocabulary preservation, trailing modifier cancellation, Telex raw word restoration, and context-primed bilingual disambiguation.

To prevent single-sided accuracy inflation, the benchmark harness also replays all ambiguous collision rows **without** an English context (`vn_survives_collision` and `ambiguous_both_sides`) and enforces ratchet floors across separate OS processes in CI.

---

## 2. Accuracy Regression Matrix

### 2.1 Primary Buckets (9,091 Cases)

Each row is driven once under the condition specified by its dataset label, with per-row context isolation (`session.context` is assigned unconditionally per row so no state leaks across test cases):

| Bucket | Test Condition | Passing / Total | Pass Rate | Ratchet Floor |
| :--- | :--- | :---: | :---: | :---: |
| **`transform`** | Pure Vietnamese syllable transformation | **400 / 400** | **100.00%** | `100.00%` |
| **`keep_as_typed`** | Untouched English vocabulary | **362 / 362** | **100.00%** | `100.00%` |
| **`cancel_keep_composed`** | Trailing modifier cancellation (`zz`, `ss`, triple vowels) | **67 / 67** | **100.00%** | `100.00%` |
| **`restore_raw`** | Restoring English words mangled by Telex modifier keys | **7,213 / 7,213** | **100.00%** | `100.00%` |
| **`ambiguous_needs_context`** | Ambiguous spellings driven **with** English context primed | **1,049 / 1,049** | **100.00%** | `100.00%` |
| **Overall Primary Suite** | **All 5 primary buckets combined** | **9,091 / 9,091** | **100.00%** | **`100.00%`** |

### 2.2 Symmetric Collision Buckets (No-Context Replay)

Quoting `ambiguous_needs_context` (100.00%) alone only proves *"English context in → English out"*. To measure the symmetric trade-off when typing standalone Vietnamese words without context, the harness replays the 375 lowercase ambiguous collision rows with **no context** (`session.context = ""`):

| Symmetric Metric | Condition | Passing / Total | Rate | Ratchet Floor |
| :--- | :--- | :---: | :---: | :---: |
| **`vn_survives_collision`** | 375 lowercase ambiguous rows driven with **no context** | **365 / 375** | **97.33%** | `97.33%` |
| ↳ `whitelist_safe = never` | **Unique** keystroke path to that Vietnamese syllable | **182 / 182** | **100.00% (0 critical losses)** | `100.00%` |
| ↳ `whitelist_safe = degrades_vn` | One of multiple keystroke paths to that syllable | **183 / 193** | **94.82%** | — |
| **`ambiguous_both_sides`** | Correct as **English with context** AND **Vietnamese without context** | **365 / 375** | **97.33%** | `97.33%` |
| **`case_signal_restores`** | 674 capitalized `case_variant` rows replayed with no context | **66 / 674** | **9.79%** | `9.79%` |

> [!IMPORTANT]
> **Mandatory Symmetric Disclosure:**
> Any citation of the **100.00%** primary regression accuracy must always be accompanied by **`ambiguous_both_sides: 97.33% (365/375)`** and **`whitelist_safe = never: 100.00% (182/182, 0 critical losses)`**.

---

## 3. Dataset Self-Consistency Invariants

At load time, the benchmark harness scans the entire test suite and verifies two formal dataset properties before running any keystrokes:

1. **Satisfiability (`0 conflicts`)**: No raw input sequence is asked to produce two different outputs under identical drive conditions.
2. **Policy Coherence (`0 conflicts`)**: No collision word is simultaneously labeled `whitelist_safe = never` and `whitelist_safe = yes`.

---

## 4. Latency & High-Throughput Endurance

The high-throughput endurance suite drives **250,000 continuous keystrokes** across three interleaved workloads (Pure Telex Vietnamese, Pure VNI Vietnamese, and Mixed Bilingual Code/Prose) and gates both tail latency (`p99`) and sustained throughput:

| Workload / Metric | Ceiling / Floor Gate | Typical Apple Silicon Measurement |
| :--- | :---: | :---: |
| **Telex `p99` Keystroke Latency** | `≤ 500.00 µs` | `~150 – 220 µs` |
| **VNI `p99` Keystroke Latency** | `≤ 300.00 µs` | `~60 – 110 µs` |
| **Mixed Bilingual `p99` Latency** | `≤ 700.00 µs` | `~250 – 380 µs` |
| **Sustained Throughput** | `≥ 25,000 KPS` | `> 40,000 KPS` |

---

## 5. Open-Core Build & Integrity Verification

The 9,091-case regression dataset and internal CLI harness are maintained in the private core repository. In the Open-Core repository, you can verify cryptographic integrity of the prebuilt artifacts and compile the macOS InputMethodKit shell from source:

```bash
# 1. Verify SHA-256 integrity of all prebuilt frameworks and binaries
shasum -a 256 -c Binaries/checksums.sha256

# 2. Compile VieLotusIM from source against VieLotusCore.xcframework
swift build --product VieLotusIM
```
