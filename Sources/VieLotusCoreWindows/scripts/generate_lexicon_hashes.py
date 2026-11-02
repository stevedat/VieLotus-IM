#!/usr/bin/env python3
"""
 VieLotusIM (Sen Việt) — Deterministic FNV-1a Lexicon Hash Table Generator
 License: Expat (MIT)

 Reads canonical UTF-8 (Unicode NFC) plaintext wordlists from:
   Sources/VieLotusCoreWindows/lexicon/*.txt
 and generates (or verifies with --check) the sorted 64-bit FNV-1a constexpr
 lookup arrays in:
   <build-dir>/generated/VieLotusLexicon/WindowsNativeLexiconGenerated.inc
 (default reference snapshot for --check / bare-Windows fallback:
   Sources/VieLotusCoreWindows/prebuilt/VieLotusLexicon/WindowsNativeLexiconGenerated.inc)

 Zero external dependencies (Python 3 standard library only, 100% offline).
"""

import argparse
import pathlib
import sys
import unicodedata
from typing import Dict, List, Tuple

FNV1A_64_OFFSET_BASIS = 0xCBF29CE484222325
FNV1A_64_PRIME = 0x100000001B3
MASK_64 = 0xFFFFFFFFFFFFFFFF

# (filename, C++ constexpr symbol name, allow_empty_sentinel, description)
LEXICON_SPECS: List[Tuple[str, str, bool, str]] = [
    (
        "00_initial_onsets.txt",
        "kValidInitialOnsets",
        True,
        "Valid Vietnamese syllable initial consonant clusters (plus empty zero-onset)",
    ),
    (
        "01_final_codas.txt",
        "kValidFinalCodas",
        True,
        "Valid Vietnamese syllable final consonant codas (plus empty open-syllable coda)",
    ),
    (
        "02_stop_codas.txt",
        "kStopCodas",
        False,
        "Vietnamese voiceless stop codas (-c, -ch, -p, -t) restricted to Sac/Nang tones",
    ),
    (
        "03_double_o_codas.txt",
        "kDoubleOCodas",
        False,
        "Valid codas permitted after Vietnamese double-'oo' nuclei (e.g. xoong, boong)",
    ),
    (
        "04_unconditional_english_words.txt",
        "kUnconditionalEnglishWords",
        False,
        "Unambiguous English/technical words whose raw Telex keystrokes collide with Vietnamese modifiers",
    ),
    (
        "05_context_english_collision_words.txt",
        "kContextEnglishCollisionWords",
        False,
        "Bilingual collision words valid in both Vietnamese and English (disambiguated by sentence/tech context)",
    ),
    (
        "06_english_context_anchors.txt",
        "kEnglishContextAnchors",
        False,
        "High-frequency English function and anchor words that establish English sentence momentum",
    ),
    (
        "07_sex_loanword_preceding_heads.txt",
        "kSexLoanwordPrecedingHeads",
        False,
        "Preceding Vietnamese/English heads before loanword 'sex' (vs Vietnamese future particle 'sẽ')",
    ),
    (
        "08_vietnamese_context_resets.txt",
        "kVietnameseContextResets",
        False,
        "Common Vietnamese words (including ASCII-only syllables) that reset English sentence momentum",
    ),
    (
        "09_turn_phrasal_followers.txt",
        "kTurnPhrasalFollowers",
        False,
        "English phrasal particles/nouns following 'turn' to retroactively disambiguate 'tủn' -> 'turn'",
    ),
    (
        "10_sex_english_followers.txt",
        "kSexEnglishFollowers",
        False,
        "English collocation followers after 'sex' to retroactively disambiguate 'sẽ' -> 'sex'",
    ),
    (
        "11_extended_english_escapes.txt",
        "kExtendedEnglishEscapeWords",
        False,
        "English words and prefixes containing doubled Telex modifier letters (ff, rr, ss, ww) for escape restoration",
    ),
]


def fnv1a_64_wchar(entry: str) -> int:
    """
    Computes 64-bit FNV-1a over BMP Unicode codepoints, matching C++
    `fnv1aHash(const wchar_t *s, int len)` across both Linux/macOS (UTF-32 wchar_t)
    and Windows (UTF-16 wchar_t for BMP codepoints <= U+FFFF).
    """
    h = FNV1A_64_OFFSET_BASIS
    for ch in entry:
        cp = ord(ch)
        if cp > 0xFFFF:
            raise ValueError(
                f"Entry {entry!r} contains non-BMP codepoint U+{cp:04X}; "
                "all lexicon entries must stay within BMP (<= U+FFFF) for cross-platform wchar_t parity."
            )
        h ^= cp
        h = (h * FNV1A_64_PRIME) & MASK_64
    return h


def load_wordlist(path: pathlib.Path, allow_empty: bool) -> List[Tuple[int, str]]:
    if not path.is_file():
        raise FileNotFoundError(f"Missing required lexicon wordlist: {path}")

    raw_text = path.read_text(encoding="utf-8")
    seen_words: Dict[str, int] = {}
    seen_hashes: Dict[int, str] = {}
    entries: List[Tuple[int, str]] = []

    for line_no, raw_line in enumerate(raw_text.splitlines(), start=1):
        stripped = raw_line.strip()
        if not stripped or stripped.startswith("#"):
            continue

        if stripped == "<empty>":
            if not allow_empty:
                raise ValueError(f"{path.name}:{line_no}: '<empty>' sentinel is not permitted in this table")
            word = ""
        else:
            nfc_word = unicodedata.normalize("NFC", stripped)
            if stripped != nfc_word:
                raise ValueError(
                    f"{path.name}:{line_no}: entry {stripped!r} is not in Unicode NFC form (expected {nfc_word!r})"
                )
            if nfc_word != nfc_word.lower():
                raise ValueError(
                    f"{path.name}:{line_no}: entry {nfc_word!r} must be lowercase (expected {nfc_word.lower()!r})"
                )
            if any(ch.isspace() or unicodedata.category(ch).startswith("C") for ch in nfc_word):
                raise ValueError(
                    f"{path.name}:{line_no}: entry {nfc_word!r} contains whitespace or control characters"
                )
            word = nfc_word

        if word in seen_words:
            raise ValueError(
                f"{path.name}:{line_no}: duplicate entry {word or '<empty>'!r} (first seen at line {seen_words[word]})"
            )
        seen_words[word] = line_no

        digest = fnv1a_64_wchar(word)
        if digest in seen_hashes:
            raise ValueError(
                f"{path.name}:{line_no}: 64-bit FNV-1a hash collision (0x{digest:016x}) "
                f"between {seen_hashes[digest] or '<empty>'!r} and {word or '<empty>'!r}"
            )
        seen_hashes[digest] = word
        entries.append((digest, word))

    if not entries:
        raise ValueError(f"{path.name}: wordlist produced 0 entries")

    entries.sort(key=lambda item: item[0])
    return entries


def render_inc(lexicon_dir: pathlib.Path) -> str:
    lines: List[str] = [
        "// =============================================================================",
        "// AUTO-GENERATED FILE — DO NOT EDIT DIRECTLY",
        "// Generated from UTF-8 (Unicode NFC) plaintext wordlists in:",
        "//   Sources/VieLotusCoreWindows/lexicon/*.txt",
        "// by:",
        "//   python3 Sources/VieLotusCoreWindows/scripts/generate_lexicon_hashes.py",
        "// License: Expat (MIT)",
        "// =============================================================================",
        "",
    ]

    for filename, symbol, allow_empty, desc in LEXICON_SPECS:
        entries = load_wordlist(lexicon_dir / filename, allow_empty=allow_empty)
        count = len(entries)
        lines.append(f"// {desc}")
        lines.append(f"// Source: lexicon/{filename} ({count} entries)")
        lines.append(f"constexpr uint64_t {symbol}[{count}] = {{")
        for idx in range(0, count, 6):
            chunk = entries[idx : idx + 6]
            formatted = ", ".join(f"0x{h:016x}ULL" for h, _ in chunk)
            suffix = "," if (idx + 6) < count else ""
            lines.append(f"    {formatted}{suffix}")
        lines.append("};")
        lines.append("")

    return "\n".join(lines)


def main() -> int:
    script_dir = pathlib.Path(__file__).resolve().parent
    default_lexicon_dir = script_dir.parent / "lexicon"
    default_output = (
        script_dir.parent / "prebuilt" / "VieLotusLexicon" / "WindowsNativeLexiconGenerated.inc"
    )

    parser = argparse.ArgumentParser(
        description="Generate or verify sorted 64-bit FNV-1a C++ lookup tables from plaintext UTF-8 NFC wordlists."
    )
    parser.add_argument(
        "--lexicon-dir",
        type=pathlib.Path,
        default=default_lexicon_dir,
        help="Directory containing lexicon/*.txt files",
    )
    parser.add_argument(
        "--output",
        type=pathlib.Path,
        default=default_output,
        help="Path to generated C++ .inc file",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Verify that --output matches freshly generated output byte-for-byte without modifying files",
    )
    args = parser.parse_args()

    try:
        rendered = render_inc(args.lexicon_dir)
    except Exception as exc:
        print(f"ERROR: lexicon generation failed: {exc}", file=sys.stderr)
        return 1

    if args.check:
        if not args.output.is_file():
            print(f"ERROR: generated file does not exist: {args.output}", file=sys.stderr)
            return 1
        existing = args.output.read_text(encoding="utf-8")
        if existing != rendered:
            print(
                f"ERROR: {args.output} is out of sync with {args.lexicon_dir}.\n"
                f"Run: python3 Sources/VieLotusCoreWindows/scripts/generate_lexicon_hashes.py",
                file=sys.stderr,
            )
            return 1
        return 0

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="utf-8", newline="\n") as out_f:
        out_f.write(rendered)
    return 0


if __name__ == "__main__":
    sys.exit(main())
