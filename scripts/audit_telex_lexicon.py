#!/usr/bin/env python3
"""
VieLotusIM (Sen Việt) — Automated Bilingual Lexicon & Telex Prefix Audit
License: MIT

Verifies five structural and live cross-engine invariants across the bilingual
lexicons and canonical Vietnamese syllable dictionary:
  1. Lexicon hygiene (UTF-8 NFC, sorted, zero duplicates, hash table freshness)
  2. Cross-list mutual exclusion (unconditional vs context-only, EN vs VN anchors,
     zero contamination with test_suite.csv `whitelist_safe = never`)
  3. Exact & strict-prefix Telex shadowing scan against all canonical Vietnamese
     syllables in `VietnameseSyllableDictionary.swift`
  4. Live cross-engine survival verification (Swift 6 `VieLotusCLI` + C++20
     `VieLotusWinEngineLab`) for every prefix-shadowed Vietnamese syllable
  5. Live 0-loss verification on all `whitelist_safe = never` single-path
     Vietnamese rows across both engines.

Zero external dependencies (Python 3 standard library only, 100% offline).
"""

from __future__ import annotations

import argparse
import csv
import pathlib
import re
import subprocess
import sys
import unicodedata
from typing import Dict, List, Set, Tuple

ROOT = pathlib.Path(__file__).resolve().parent.parent
LEXICON_DIR = ROOT / "Sources" / "VieLotusCoreWindows" / "lexicon"
HASH_GEN = ROOT / "Sources" / "VieLotusCoreWindows" / "scripts" / "generate_lexicon_hashes.py"
VN_DICT_SWIFT = ROOT / "Sources" / "VieLotusCore" / "VietnameseSyllableDictionary.swift"
SWIFT_BILINGUAL = ROOT / "Sources" / "VieLotusCore" / "SmartBilingualDetector.swift"
TEST_SUITE_CSV = ROOT / "Sources" / "VieLotusCLI" / "Resources" / "test_suite.csv"

# Vietnamese vowel decomposition: char -> (base_ascii, shape_key, tone_key)
# shape_key: "" | "a" | "e" | "o" | "w"
# tone_key:  "" | "s" | "f" | "r" | "x" | "j"
VOWEL_TABLE: Dict[str, Tuple[str, str, str]] = {}
_VOWEL_ROWS = [
    ("a", "",  "aáàảãạ"),
    ("a", "w", "ăắằẳẵặ"),
    ("a", "a", "âấầẩẫậ"),
    ("e", "",  "eéèẻẽẹ"),
    ("e", "e", "êếềểễệ"),
    ("i", "",  "iíìỉĩị"),
    ("o", "",  "oóòỏõọ"),
    ("o", "o", "ôốồổỗộ"),
    ("o", "w", "ơớờởỡợ"),
    ("u", "",  "uúùủũụ"),
    ("u", "w", "ưứừửữự"),
    ("y", "",  "yýỳỷỹỵ"),
]
_TONES = ["", "s", "f", "r", "x", "j"]
for _base, _shape, _chars in _VOWEL_ROWS:
    for _ch, _tone in zip(_chars, _TONES):
        VOWEL_TABLE[_ch] = (_base, _shape, _tone)


def syllable_to_canonical_telex(syl: str) -> str:
    """Convert a lowercase Unicode NFC Vietnamese syllable into standard Telex."""
    out: List[str] = []
    tone = ""
    i = 0
    chars = list(syl)
    while i < len(chars):
        ch = chars[i]
        if ch == "đ":
            out.append("dd")
            i += 1
            continue
        # Handle compound ươ -> uow (single w)
        if ch in VOWEL_TABLE and i + 1 < len(chars) and chars[i + 1] in VOWEL_TABLE:
            b1, s1, t1 = VOWEL_TABLE[ch]
            b2, s2, t2 = VOWEL_TABLE[chars[i + 1]]
            if b1 == "u" and s1 == "w" and b2 == "o" and s2 == "w":
                out.append("uow")
                if t1:
                    tone = t1
                if t2:
                    tone = t2
                i += 2
                continue
        if ch in VOWEL_TABLE:
            base, shape, t = VOWEL_TABLE[ch]
            out.append(base + shape)
            if t:
                tone = t
        else:
            out.append(ch)
        i += 1
    return "".join(out) + tone


def load_lexicon_file(path: pathlib.Path) -> Tuple[List[str], List[str]]:
    """Return (entries, hygiene_issues)."""
    issues: List[str] = []
    raw_bytes = path.read_bytes()
    try:
        text = raw_bytes.decode("utf-8")
    except UnicodeDecodeError as exc:
        return [], [f"{path.name}: invalid UTF-8 ({exc})"]

    entries: List[str] = []
    seen: Set[str] = set()
    for lineno, raw_line in enumerate(text.splitlines(), 1):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line == "<EMPTY>":
            continue
        if unicodedata.normalize("NFC", line) != line:
            issues.append(f"{path.name}:{lineno}: non-NFC entry {line!r}")
        if line in seen:
            issues.append(f"{path.name}:{lineno}: duplicate entry {line!r}")
        seen.add(line)
        entries.append(line)

    if entries != sorted(entries):
        # Report first out-of-order pair
        for a, b in zip(entries, entries[1:]):
            if a > b:
                issues.append(f"{path.name}: not sorted ({a!r} > {b!r})")
                break

    return entries, issues


def load_canonical_vn_syllables() -> List[str]:
    text = VN_DICT_SWIFT.read_text(encoding="utf-8")
    match = re.search(
        r'private static let baseSyllableList: String = """(.*?)"""',
        text,
        re.DOTALL,
    )
    if not match:
        raise RuntimeError(f"Could not find baseSyllableList in {VN_DICT_SWIFT}")
    syllables = match.group(1).split()
    return sorted(set(unicodedata.normalize("NFC", s.lower()) for s in syllables if s))


def load_swift_supplementary_tokens() -> Set[str]:
    text = SWIFT_BILINGUAL.read_text(encoding="utf-8")
    match = re.search(
        r"private static let supplementaryTechAndBrandWords: Set<String> = \[(.*?)\]",
        text,
        re.DOTALL,
    )
    if not match:
        return set()
    return set(re.findall(r'"([^"]+)"', match.group(1)))


# Documented policy overrides in 04_unconditional_english_words.txt that intentionally
# supersede a rare Vietnamese Telex syllable when standalone (with documented alternate
# Telex path or compound-head exception in test_suite.csv):
#   - "down" -> Policy 2026-11-16: prefer English "down"; "dơn" stays accessible via
#     "donw" or after Vietnamese compound heads ("hoa/cây/củ/bông lay dơn").
DOCUMENTED_UNCONDITIONAL_VN_OVERRIDES: Set[str] = {"down"}


def load_never_whitelist_rows() -> Tuple[List[Tuple[str, str]], Set[str]]:
    """Return:
      - live_rows: [(raw_input, expected_vn_syllable)] for the 179 ratified lowercase
        `ambiguous_needs_context` rows with `whitelist_safe = never` (mirrors VNCollisionRatchetTests)
      - all_never_inputs: union of ALL lowercase `whitelist_safe = never` inputs across both
        `ambiguous_needs_context` and `transform` for static unconditional-list protection.
    """
    live_rows: List[Tuple[str, str]] = []
    all_never_inputs: Set[str] = set()
    with TEST_SUITE_CSV.open(encoding="utf-8") as fh:
        reader = csv.DictReader(fh)
        for row in reader:
            if row.get("whitelist_safe") != "never":
                continue
            if row.get("suite") == "case_variant":
                continue
            behavior = row.get("expected_behavior", "")
            raw = row.get("input", "").strip()
            vn = row.get("naive_telex_output", "").strip()
            if behavior in ("ambiguous_needs_context", "transform") and raw and raw == raw.lower():
                all_never_inputs.add(raw)
                if behavior == "ambiguous_needs_context" and vn:
                    live_rows.append((raw, vn))
    return live_rows, all_never_inputs


def find_swift_cli() -> pathlib.Path | None:
    for p in [
        ROOT / ".build" / "release" / "VieLotusCLI",
        ROOT / ".build" / "arm64-apple-macosx" / "release" / "VieLotusCLI",
    ]:
        if p.exists():
            return p
    return None


def find_cpp_lab() -> pathlib.Path | None:
    p = ROOT / ".build" / "windows-lab" / "VieLotusWinEngineLab"
    return p if p.exists() else None


def run_swift_batch(cli: pathlib.Path, inputs: List[str]) -> List[str]:
    if not inputs:
        return []
    payload = "\n".join(f"{w} " for w in inputs) + "\nexit\n"
    proc = subprocess.run(
        [str(cli)],
        input=payload,
        text=True,
        capture_output=True,
        cwd=ROOT,
        check=True,
    )
    outputs: List[str] = []
    for line in proc.stdout.splitlines():
        if "Kết quả: " in line:
            outputs.append(line.split("Kết quả: ", 1)[1].rstrip(" "))
    if len(outputs) != len(inputs):
        raise RuntimeError(f"VieLotusCLI output count mismatch: got {len(outputs)}, expected {len(inputs)}")
    return outputs


def run_cpp_batch(lab: pathlib.Path, inputs: List[str]) -> List[str]:
    if not inputs:
        return []
    outputs: List[str] = []
    chunk_size = 20
    for i in range(0, len(inputs), chunk_size):
        chunk = inputs[i : i + chunk_size]
        spec = " | ".join(w.rstrip(" ") for w in chunk)
        proc = subprocess.run(
            [str(lab), "--trace", spec],
            text=True,
            capture_output=True,
            cwd=ROOT,
            check=True,
        )
        for line in proc.stdout.splitlines():
            if line.startswith('FINAL OUTPUT: "') and line.endswith('"'):
                outputs.append(line[len('FINAL OUTPUT: "') : -1])
    if len(outputs) != len(inputs):
        raise RuntimeError(f"VieLotusWinEngineLab output count mismatch: got {len(outputs)}, expected {len(inputs)}")
    return outputs


def main() -> int:
    parser = argparse.ArgumentParser(description="Audit VieLotusIM bilingual lexicons & Telex prefixes.")
    parser.add_argument("--verbose", action="store_true", help="Print advisory prefix overlaps.")
    args = parser.parse_args()

    hard_failures: List[str] = []

    print("================================================================")
    print("  VieLotusIM Bilingual Lexicon & Telex Prefix Audit")
    print("================================================================")

    # 1. Lexicon file hygiene
    lexicon_data: Dict[str, List[str]] = {}
    hygiene_issues: List[str] = []
    for path in sorted(LEXICON_DIR.glob("*.txt")):
        entries, issues = load_lexicon_file(path)
        lexicon_data[path.name] = entries
        hygiene_issues.extend(issues)

    # Check hash table freshness via generate_lexicon_hashes.py --check
    hash_proc = subprocess.run(
        [sys.executable, str(HASH_GEN), "--check"],
        capture_output=True,
        text=True,
    )
    hash_fresh = hash_proc.returncode == 0
    if not hash_fresh:
        hygiene_issues.append(f"generate_lexicon_hashes.py --check failed: {hash_proc.stderr.strip() or hash_proc.stdout.strip()}")

    print(f"  1. Lexicon hygiene (12 files + hash check) : {'PASS' if not hygiene_issues else 'FAIL'}")
    for iss in hygiene_issues:
        print(f"     [FAIL] {iss}")
    hard_failures.extend(hygiene_issues)

    uncond = set(lexicon_data.get("04_unconditional_english_words.txt", []))
    ctx_coll = set(lexicon_data.get("05_context_english_collision_words.txt", []))
    en_anchors = set(lexicon_data.get("06_english_context_anchors.txt", []))
    vn_resets = set(lexicon_data.get("08_vietnamese_context_resets.txt", []))
    ext_escapes = set(lexicon_data.get("11_extended_english_escapes.txt", []))
    swift_supp = load_swift_supplementary_tokens()
    never_rows, all_never_inputs = load_never_whitelist_rows()

    # 2. Cross-list mutual exclusion
    cross_issues: List[str] = []
    both_uncond_ctx = sorted(uncond & ctx_coll)
    if both_uncond_ctx:
        cross_issues.append(f"04_unconditional ∩ 05_context_collision ({len(both_uncond_ctx)}): {both_uncond_ctx[:10]}")
    both_anchors = sorted(en_anchors & vn_resets)
    if both_anchors:
        cross_issues.append(f"06_en_anchors ∩ 08_vn_resets ({len(both_anchors)}): {both_anchors[:10]}")
    never_in_uncond = sorted(uncond & all_never_inputs)
    if never_in_uncond:
        cross_issues.append(f"04_unconditional ∩ whitelist_safe=never: {never_in_uncond}")
    never_in_swift_supp = sorted(swift_supp & all_never_inputs)
    if never_in_swift_supp:
        cross_issues.append(f"Swift supplementaryTechAndBrandWords ∩ whitelist_safe=never: {never_in_swift_supp}")

    print(f"  2. Cross-list & whitelist_safe=never gate  : {'PASS' if not cross_issues else 'FAIL'}")
    for iss in cross_issues:
        print(f"     [FAIL] {iss}")
    hard_failures.extend(cross_issues)

    # 3. Canonical Vietnamese syllable Telex expansion + prefix shadowing detection
    vn_syllables = load_canonical_vn_syllables()
    telex_to_vn: Dict[str, List[str]] = {}
    for syl in vn_syllables:
        tx = syllable_to_canonical_telex(syl)
        telex_to_vn.setdefault(tx, []).append(syl)

    # All ASCII English tokens that can restore unconditionally (C++20 + Swift)
    unconditional_pool = sorted((uncond | ext_escapes | swift_supp))

    # Build prefix index of all canonical Vietnamese Telex sequences
    exact_overlaps: List[Tuple[str, List[str]]] = []
    prefix_overlaps: List[Tuple[str, str, List[str]]] = []  # (en_word, vn_telex, [vn_syllables])

    all_vn_telex = sorted(telex_to_vn.keys())
    # Map every strict prefix -> list of (vn_telex, vn_syllables)
    prefix_map: Dict[str, List[Tuple[str, List[str]]]] = {}
    for tx in all_vn_telex:
        for k in range(2, len(tx)):
            prefix_map.setdefault(tx[:k], []).append((tx, telex_to_vn[tx]))

    for en in unconditional_pool:
        if en in telex_to_vn:
            # Ignore plain ASCII Vietnamese syllables that don't actually transform (raw == vn)
            transformed = [s for s in telex_to_vn[en] if s != en]
            if transformed:
                exact_overlaps.append((en, transformed))
        if en in prefix_map:
            for tx, syls in prefix_map[en]:
                transformed = [s for s in syls if s != tx]
                if transformed:
                    prefix_overlaps.append((en, tx, transformed))

    # Hard gate: 04_unconditional_english_words.txt must NEVER silently shadow a canonical
    # Vietnamese Telex syllable unless explicitly ratified in DOCUMENTED_UNCONDITIONAL_VN_OVERRIDES.
    uncond_vn_collisions = []
    for en in sorted(uncond):
        if en in telex_to_vn and en not in DOCUMENTED_UNCONDITIONAL_VN_OVERRIDES:
            transformed = [s for s in telex_to_vn[en] if s != en]
            if transformed:
                uncond_vn_collisions.append(f"04_unconditional '{en}' shadows canonical VN syllable {transformed}")
    if uncond_vn_collisions:
        for coll in uncond_vn_collisions:
            print(f"     [FAIL] {coll}")
        hard_failures.extend(uncond_vn_collisions)

    print(
        f"  3. Canonical VN Telex scan ({len(vn_syllables)} syls)   : "
        f"{len(uncond_vn_collisions)} unratified 04-collision(s), "
        f"{len(prefix_overlaps)} strict-prefix pair(s)"
    )

    # 4 & 5. Live cross-engine survival verification (Swift 6 + C++20)
    swift_cli = find_swift_cli()
    cpp_lab = find_cpp_lab()
    if swift_cli is None or cpp_lab is None:
        missing = []
        if swift_cli is None:
            missing.append("VieLotusCLI (run `./scripts/benchmark_ratchet.sh`)")
        if cpp_lab is None:
            missing.append("VieLotusWinEngineLab (run `./scripts/test_windows_engine.sh`)")
        hard_failures.append("Missing compiled engine binary for live audit: " + ", ".join(missing))
        print(f"  4. Live cross-engine survival audit        : FAIL (missing {', '.join(missing)})")
    else:
        # Collect unique Telex sequences from strict-prefix overlaps + exact overlaps
        prefix_telex_unique: List[Tuple[str, List[str], str]] = []
        seen_tx: Set[str] = set()
        for en, tx, syls in prefix_overlaps:
            if tx not in seen_tx:
                seen_tx.add(tx)
                prefix_telex_unique.append((tx, syls, en))

        prefix_inputs = [tx for tx, _, _ in prefix_telex_unique]
        swift_prefix_out = run_swift_batch(swift_cli, prefix_inputs)
        cpp_prefix_out = run_cpp_batch(cpp_lab, prefix_inputs)

        prefix_shadow_failures: List[str] = []
        for (tx, syls, en), s_out, c_out in zip(prefix_telex_unique, swift_prefix_out, cpp_prefix_out):
            if s_out not in syls:
                prefix_shadow_failures.append(
                    f"Swift shadowed by prefix '{en}': '{tx}' -> '{s_out}' (expected {syls})"
                )
            if c_out not in syls:
                prefix_shadow_failures.append(
                    f"C++20 shadowed by prefix '{en}': '{tx}' -> '{c_out}' (expected {syls})"
                )

        print(
            f"  4. Live prefix-shadowing check ({len(prefix_telex_unique)} VN)   : "
            f"{'PASS (0 broken)' if not prefix_shadow_failures else f'FAIL ({len(prefix_shadow_failures)} broken)'}"
        )
        for fail in prefix_shadow_failures[:20]:
            print(f"     [FAIL] {fail}")
        hard_failures.extend(prefix_shadow_failures)

        # Report exact overlaps (advisory if not in whitelist_safe=never; live check both engines)
        exact_inputs = [en for en, _ in exact_overlaps]
        swift_exact_out = run_swift_batch(swift_cli, exact_inputs)
        cpp_exact_out = run_cpp_batch(cpp_lab, exact_inputs)
        exact_mismatches: List[str] = []
        for (en, syls), s_out, c_out in zip(exact_overlaps, swift_exact_out, cpp_exact_out):
            if s_out != c_out:
                exact_mismatches.append(f"'{en}' (VN {syls}): Swift='{s_out}' vs C++20='{c_out}'")
        if args.verbose or exact_overlaps:
            print(
                f"     Exact EN-unconditional / VN-Telex collisions ({len(exact_overlaps)}): "
                + (", ".join(f"{en}({','.join(syls)})" for en, syls in exact_overlaps[:12]) or "none")
            )
            if exact_mismatches:
                print(f"     Advisory Swift↔C++20 delta on exact overlaps ({len(exact_mismatches)}):")
                for mm in exact_mismatches[:12]:
                    print(f"       • {mm}")

        # 5. Live 179 whitelist_safe=never check across BOTH engines
        never_raws = [raw for raw, _ in never_rows]
        swift_never_out = run_swift_batch(swift_cli, never_raws)
        cpp_never_out = run_cpp_batch(cpp_lab, never_raws)
        never_failures: List[str] = []
        for (raw, exp_vn), s_out, c_out in zip(never_rows, swift_never_out, cpp_never_out):
            if s_out != exp_vn:
                never_failures.append(f"Swift lost never-word '{raw}': got '{s_out}' (expected '{exp_vn}')")
            if c_out != exp_vn:
                never_failures.append(f"C++20 lost never-word '{raw}': got '{c_out}' (expected '{exp_vn}')")

        print(
            f"  5. Live whitelist_safe=never ({len(never_rows)} rows)  : "
            f"{'PASS (100% both engines)' if not never_failures else f'FAIL ({len(never_failures)} losses)'}"
        )
        for fail in never_failures[:20]:
            print(f"     [FAIL] {fail}")
        hard_failures.extend(never_failures)

        if args.verbose and prefix_overlaps:
            print(f"\n  Advisory prefix overlaps verified safe ({len(prefix_overlaps)} pairs):")
            for en, tx, syls in prefix_overlaps[:30]:
                print(f"    • prefix '{en}' -> VN '{tx}' ({'/'.join(syls)})")

    print("================================================================")
    if hard_failures:
        print(f"  RESULT: FAIL ({len(hard_failures)} hard violation(s))")
        return 1
    print("  RESULT: PASS (0 hard violations)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
