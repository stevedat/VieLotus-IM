# VieLotusIM (Sen Việt) — Native C++20 Engine Lexicon & Phonotactic Tables

## 1. Overview & Canonical Maintenance Status

This directory (`Sources/VieLotusCoreWindows/lexicon/`) contains the **canonical,
human-editable plaintext source wordlists** used to maintain and build the
Cross-Platform / Linux / Windows C++20 Vietnamese input method engine
(`Sources/VieLotusCoreWindows/WindowsNativeEngine.cpp`).

Starting with **`v2.0.1`** (DFSG #2 compliance), inline hex arrays have been
permanently retired from `WindowsNativeEngine.cpp`:
- `Sources/VieLotusCoreWindows/lexicon/*.txt` and
  `Sources/VieLotusCoreWindows/WindowsNativeEngine.{h,cpp}` are the **sole
  canonical upstream maintenance source** for the C++20 desktop/Linux engine,
  maintained directly in version control under the **Expat (MIT)** license
  (there is no private transpiler, hidden wordlist, or external code generator
  upstream of these files).
- During CMake builds (`CrossPlatform/capi-native/CMakeLists.txt`, including
  `debian/rules`), `scripts/generate_lexicon_hashes.py` generates
  `${CMAKE_CURRENT_BINARY_DIR}/generated/VieLotusLexicon/WindowsNativeLexiconGenerated.inc`
  directly from these `.txt` files, and `WindowsNativeEngine.cpp` includes it
  via `#include <VieLotusLexicon/WindowsNativeLexiconGenerated.inc>`.
- A reference snapshot is kept at
  `Sources/VieLotusCoreWindows/prebuilt/VieLotusLexicon/WindowsNativeLexiconGenerated.inc`
  solely for `--check` byte-for-byte determinism verification and bare-Windows
  environments lacking Python 3; `prebuilt/` is **never** added to compiler
  include paths (`-I`) on Linux/Debian builds, guaranteeing that every build
  compiles the freshly generated header.

---

## 2. Table Inventory, Historical Provenance & Reconstitution Methodology

Prior to `v2.0.1`, `WindowsNativeEngine.cpp` embedded precomputed sorted 64-bit
FNV-1a lookup arrays (`D0..D10` totaling `1,189` entries in `v2.0.0` / commit
`c9420e6`, plus `D11` with `819` entries added in the `v2.0.1` explicit Telex
double-tap escape update, totaling **`2,008` entries**) without committing the
separate plaintext wordlists alongside the C++ translation unit.

For `v2.0.1`, all 12 tables (`2,008 / 2,008` entries, zero hash collisions,
100% bit-for-bit verified against the pre-refactor `D0..D11` arrays) were
consolidated, audited, and committed as canonical UTF-8 (`Unicode NFC`)
wordlists:

| File | C++ Symbol (Legacy ID) | Entries | Historical Source & Reconstitution Breakdown |
| :--- | :--- | :---: | :--- |
| `00_initial_onsets.txt` | `kValidInitialOnsets` (`D0` in `c9420e6`) | 27 | First-party Vietnamese syllable initial consonant clusters (plus `<empty>` for zero-onset syllables); `27/27` directly from project grammar rules. |
| `01_final_codas.txt` | `kValidFinalCodas` (`D1` in `c9420e6`) | 9 | First-party Vietnamese syllable final consonant codas (plus `<empty>` for open syllables); `9/9` directly from project grammar rules. |
| `02_stop_codas.txt` | `kStopCodas` (`D2` in `c9420e6`) | 4 | Vietnamese voiceless stop codas (`c`, `ch`, `p`, `t`) restricted to Sắc/Nặng tones; `4/4` directly from project grammar rules. |
| `03_double_o_codas.txt` | `kDoubleOCodas` (`D3` in `c9420e6`) | 6 | Final codas permitted after Vietnamese double-`oo` nuclei (`c`, `m`, `n`, `ng`, `p`, `t`); `6/6` directly from project grammar rules. |
| `04_unconditional_english_words.txt` | `kUnconditionalEnglishWords` (`D4` in `c9420e6`) | 625 | Unambiguous English & technical words whose raw Telex keystrokes collide with Vietnamese modifiers: `525` directly present in project bilingual detector & regression suite, `90` standard English inflected/derived forms, and `10` short tech/multilingual tokens (`aux`, `blacklist`, `como`, `entre`, `irl`, `malware`, `pero`, `sobre`, `todo`, `vida`) confirmed via exact 64-bit FNV-1a preimage audit against `D4[625]`. |
| `05_context_english_collision_words.txt` | `kContextEnglishCollisionWords` (`D5` in `c9420e6`) | 371 | Bilingual collision words valid in both Vietnamese and English, disambiguated by sentence/technical context; `371/371` directly present in project regression suite & detector sets. |
| `06_english_context_anchors.txt` | `kEnglishContextAnchors` (`D6` in `c9420e6`) | 49 | High-frequency English function and anchor words establishing English sentence context; `49/49` directly present in project detector sets. |
| `07_sex_loanword_preceding_heads.txt` | `kSexLoanwordPrecedingHeads` (`D7` in `c9420e6`) | 23 | Preceding Vietnamese/English heads before loanword `sex` (vs Vietnamese future marker `sẽ`); `23/23` directly present in project bilingual phrase rules. |
| `08_vietnamese_context_resets.txt` | `kVietnameseContextResets` (`D8` in `c9420e6`) | 29 | Common Vietnamese words (including ASCII-only syllables) that reset English sentence momentum; `29/29` directly present in project bilingual phrase rules. |
| `09_turn_phrasal_followers.txt` | `kTurnPhrasalFollowers` (`D9` in `c9420e6`) | 23 | English phrasal particles/nouns following `turn` for retroactive `tủn` → `turn` restoration; `22/23` in project tests + `1` standard English collocation noun. |
| `10_sex_english_followers.txt` | `kSexEnglishFollowers` (`D10` in `c9420e6`) | 23 | English collocation followers after `sex` for retroactive `sẽ` → `sex` restoration; `17/23` in project tests + `6` standard English collocation followers. |
| `11_extended_english_escapes.txt` | `kExtendedEnglishEscapeWords` (`D11` in `v2.0.1` escape update) | 819 | English words (plus stem `reser`) containing doubled Telex modifier letters (`ff`, `rr`, `ss`, `ww`) for explicit Telex escape preservation: `328` directly in project regression/escape tests + `490` standard English words + `1` prefix stem (`reser`), verified 100% bit-for-bit against `D11[819]`. |

All word selections consist solely of uncopyrightable individual lexical tokens
and Vietnamese phonological clusters curated by upstream and licensed under
**Expat (MIT)** (matching `LICENSE` and `debian/copyright`; zero third-party
dictionary definitions, annotations, or restricted datasets are included).

---

## 3. File Format & Normalization Invariants

1. **Encoding**: `UTF-8` without BOM, `\n` (LF) line endings.
2. **Unicode Normalization**: Precomposed **Unicode NFC** (`unicodedata.normalize("NFC", s)`). All entries stay within the Basic Multilingual Plane (`<= U+FFFF`) so 64-bit FNV-1a over `wchar_t` produces identical digests on Linux/macOS (32-bit UTF-32 `wchar_t`) and Windows (16-bit UTF-16 `wchar_t`).
3. **Case & Syntax**:
   - Lines beginning with `#` and blank lines are ignored.
   - `<empty>` denotes an empty string (`""`, length 0) in `00_initial_onsets.txt` and `01_final_codas.txt`.
   - Every lexical entry must be lowercase, contain no whitespace or control characters, and appear at most once per file.
4. **Hash Function & Ordering**:
   - Standard unsalted 64-bit FNV-1a (`offset_basis = 0xcbf29ce484222325`, `prime = 0x100000001b3` mod 2^64) over Unicode codepoints.
   - Output `uint64_t` arrays are sorted in strictly ascending numerical order for `O(log N)` binary search (`hasSortedHash`), with build-time assertion of zero hash collisions.

---

## 4. Offline Regeneration & Verification

```bash
# Regenerate build-time header into a custom build directory
python3 Sources/VieLotusCoreWindows/scripts/generate_lexicon_hashes.py \
    --output build/generated/VieLotusLexicon/WindowsNativeLexiconGenerated.inc

# Update or verify the reference snapshot (prebuilt/VieLotusLexicon/WindowsNativeLexiconGenerated.inc)
python3 Sources/VieLotusCoreWindows/scripts/generate_lexicon_hashes.py
python3 Sources/VieLotusCoreWindows/scripts/generate_lexicon_hashes.py --check
```
