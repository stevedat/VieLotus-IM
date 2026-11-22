#!/usr/bin/env python3
"""
VieLotusIM — Cross-Engine Behavioral Parity Gate (Swift 6 VieLotusCore <-> C++20 WindowsNativeEngine)

Usage:
  ./scripts/test_cross_engine_parity.py              # Gate ratified parity suite (exit 1 on mismatch)
  ./scripts/test_cross_engine_parity.py --report-all # Gate + audit all kBilingualPhrases architectural deltas
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import List, Tuple

ROOT = Path(__file__).resolve().parent.parent

# Ratified cross-engine behavioral contract: BOTH Swift (VieLotusCLI) AND C++ (VieLotusWinEngineLab)
# MUST produce the exact `expected` string (stripped of trailing space for trace comparison).
RATIFIED_PARITY_SUITE: List[Tuple[str, str, str]] = [
    # 1. lost / lót priority & Vietnamese compound heads (including Unicode capitals & ALL-CAPS)
    ("lost ", "lost", "Standalone 'lost' -> English"),
    ("Lost ", "Lost", "Titlecase 'Lost' -> English"),
    ("LOST ", "LOST", "ALL-CAPS 'LOST' -> English"),
    ("the lost city ", "the lost city", "EN phrase 'the lost city'"),
    ("bij lost ", "bị lost", "Non-head VN verb 'bị' keeps English 'lost'"),
    ("lots ", "lót", "Canonical VN Telex 'lots' -> 'lót'"),
    ("mieengs lost ", "miếng lót", "VN compound 'miếng lót'"),
    ("taams lost ", "tấm lót", "VN compound 'tấm lót'"),
    ("Aos lost ", "Áo lót", "Capitalized Unicode head 'Áo lót'"),
    ("Ddeemj lost ", "Đệm lót", "Capitalized Đ head 'Đệm lót'"),
    ("Ddoof lost ", "Đồ lót", "Capitalized Đ head 'Đồ lót'"),
    ("MIEENGS LOST ", "MIẾNG LÓT", "ALL-CAPS VN compound 'MIẾNG LÓT'"),
    ("AOS LOST ", "ÁO LÓT", "ALL-CAPS VN compound 'ÁO LÓT'"),
    ("mieengs lost tay ", "miếng lót tay", "3-word VN compound 'miếng lót tay'"),
    # 2. down / dơn priority & botanical compound heads (including 2-word 'hoa lay dơn')
    ("down ", "down", "Standalone 'down' -> English"),
    ("Down ", "Down", "Titlecase 'Down' -> English"),
    ("DOWN ", "DOWN", "ALL-CAPS 'DOWN' -> English"),
    ("go down ", "go down", "EN phrasal 'go down'"),
    ("turn down the music ", "turn down the music", "EN phrasal 'turn down the music'"),
    ("nhows turn down ", "nhớ turn down", "Mixed VN+EN 'nhớ turn down'"),
    ("keos down ", "kéo down", "Non-head VN verb 'kéo' keeps English 'down'"),
    ("lay down ", "lay down", "Standalone 'lay down' stays English without 'hoa'"),
    ("he lay down ", "he lay down", "EN clause 'he lay down' stays English"),
    ("donw ", "dơn", "Canonical VN Telex 'donw' -> 'dơn'"),
    ("hoa down ", "hoa dơn", "VN compound 'hoa dơn'"),
    ("HOA DOWN ", "HOA DƠN", "ALL-CAPS VN compound 'HOA DƠN'"),
    ("hoa lay down ", "hoa lay dơn", "Two-word VN compound head 'hoa lay dơn'"),
    ("Hoa lay down ", "Hoa lay dơn", "Capitalized two-word VN compound head 'Hoa lay dơn'"),
    ("caay down ", "cây dơn", "VN compound 'cây dơn'"),
    ("cayj down ", "cạy down", "Non-head 'cạy' keeps English 'down'"),
    ("hoa down do ", "hoa dơn do", "Committed 'hoa dơn' never reverts on following word"),
    # 3. downw / downward family & Backspace recovery
    ("downw ", "downw", "English 'downw' never renders 'dơnw'"),
    ("downwa ", "downwa", "English prefix 'downwa' never renders 'dơnwa'"),
    ("downwar ", "downwar", "English prefix 'downwar' never renders 'dơnwar'"),
    ("downward ", "downward", "English 'downward' never renders 'dơnward'"),
    ("downwards ", "downwards", "English 'downwards' never renders 'dơnwards'"),
    ("turn downw ", "turn downw", "EN phrasal 'turn downw'"),
    ("hoa downw ", "hoa downw", "'hoa downw' restores 'downw' on extra 'w'"),
    ("hoa downw< ", "hoa dơn", "Backspace on 'hoa downw' restores 'hoa dơn'"),
    ("donww ", "dơnw", "Explicit Telex 'donww' preserves 'dơnw' saturation"),
    # 4. Vietnamese compound heads across other collision words (Phase 0 verified parity)
    ("cas tree ", "cá trê", "VN compound 'cá trê'"),
    ("con bee ", "con bê", "VN compound 'con bê'"),
    ("booj moon ", "bộ môn", "VN compound 'bộ môn'"),
    ("ddooi boots ", "đôi bốt", "VN compound 'đôi bốt'"),
    ("banhs bar ", "bánh bả", "VN compound 'bánh bả'"),
    ("cais now ", "cái nơ", "VN compound 'cái nơ'"),
    ("nguy cow ", "nguy cơ", "VN compound 'nguy cơ'"),
    ("cais is ", "cái í", "VN compound 'cái í'"),
    ("nuwowcs mix ", "nước mĩ", "VN compound 'nước mĩ'"),
    ("ther or ", "thẻ ỏ", "VN compound 'thẻ ỏ'"),
    ("keeu of ", "kêu ò", "VN compound 'kêu ò'"),
    ("aamf if ", "ầm ì", "VN compound 'ầm ì'"),
    ("chaau as ", "châu á", "VN compound 'châu á'"),
    ("beos us ", "béo ú", "VN compound 'béo ú'"),
    ("cuwowif his ", "cười hí", "VN compound 'cười hí'"),
    ("vui her ", "vui hẻ", "VN compound 'vui hẻ'"),
    ("hangj best ", "hạng bét", "VN compound 'hạng bét'"),
    ("mooix last ", "mỗi lát", "VN compound 'mỗi lát'"),
    ("taats car ", "tất cả", "VN compound 'tất cả'"),
    # 5. Pronoun/auxiliary anchors, '-ist'/'-ust' collisions, 'wus'/'ddwjuoc', & starter continuations
    ("He must ", "He must", "Pronoun anchor 'He must'"),
    ("he must ", "he must", "Lowercase pronoun anchor 'he must'"),
    ("I must ", "I must", "First-person anchor 'I must'"),
    ("she must ", "she must", "Pronoun anchor 'she must'"),
    ("we must ", "we must", "Pronoun anchor 'we must'"),
    ("they must ", "they must", "Pronoun anchor 'they must'"),
    ("you must ", "you must", "Pronoun anchor 'you must'"),
    ("have been must ", "have been must", "Auxiliary chain 'have been must'"),
    ("has been must ", "has been must", "Space-prefix + auxiliary 'has been must'"),
    ("He has ", "He has", "Pronoun + auxiliary 'He has'"),
    ("the bees ", "the bees", "Article + plural 'the bees'"),
    ("Car must ", "Car must", "Starter 'Car' + modal 'must'"),
    ("what must ", "what must", "Interrogative anchor 'what must'"),
    ("when must ", "when must", "Interrogative anchor 'when must'"),
    ("where must ", "where must", "Interrogative anchor 'where must'"),
    ("which must ", "which must", "Interrogative anchor 'which must'"),
    ("while must ", "while must", "Conjunction anchor 'while must'"),
    ("He hist ", "He hist", "Pronoun + '-ist' collision 'He hist'"),
    ("He mist ", "He mist", "Pronoun + '-ist' collision 'He mist'"),
    ("He vist ", "He vist", "Pronoun + '-ist' collision 'He vist'"),
    ("He zist ", "He zist", "Non-VN initial 'z' collision 'He zist'"),
    ("He jist ", "He jist", "Non-VN initial 'j' collision 'He jist'"),
    ("zist ", "zist", "Standalone non-VN initial 'zist'"),
    ("jist ", "jist", "Standalone non-VN initial 'jist'"),
    ("wus ", "wus", "Standalone 'wus' never renders 'ứu'"),
    ("ddwjuoc ", "được", "SenFlex interleaved 'ddwjuoc' -> 'được'"),
    ("this thaan ", "thí thân", "VN compound 'thí thân'"),
    ("has gan ", "há gan", "VN compound 'há gan'"),
    ("was mieengj ", "ứa miệng", "VN compound 'ứa miệng'"),
    ("cofn its vees ", "còn ít vế", "VN phrase 'còn ít vế' keeps VN after 'ít'"),
    # 6. Tech / brand preservation & bilingual context across Swift 6 and C++20
    ("siri ", "siri", "Tech/brand 'siri' stays English"),
    ("Siri ", "Siri", "Titlecase 'Siri' stays English"),
    ("SIRI ", "SIRI", "ALL-CAPS 'SIRI' stays English"),
    ("toi hoi siri ", "toi hoi siri", "Tech/brand 'siri' stays English in untoned phrase"),
    ("Siri giup toi ", "Siri giup toi", "Titlecase 'Siri' stays English before untoned phrase"),
    ("iphone ", "iphone", "Tech/brand 'iphone' stays English"),
    ("ipad ", "ipad", "Tech/brand 'ipad' stays English"),
    ("macos ", "macos", "Tech/brand 'macos' stays English"),
    ("airpods ", "airpods", "Tech/brand 'airpods' stays English"),
    ("carplay ", "carplay", "Tech/brand 'carplay' stays English"),
    ("chatgpt ", "chatgpt", "Tech/brand 'chatgpt' stays English"),
    ("gemini ", "gemini", "Tech/brand 'gemini' stays English"),
    ("claude ", "claude", "Tech/brand 'claude' stays English"),
    ("zalo ", "zalo", "Tech/brand 'zalo' stays English"),
    # 7. Cross-platform parity audit (modifier switching, 'as' particle, 'err', post-coda 'đ', invalid rimes)
    ("caamsw ", "cắm", "Circumflex->breve switch preserving tone 'cấm'+w -> 'cắm'"),
    ("tooiw ", "tơi", "Circumflex->horn switch 'tôi'+w -> 'tơi'"),
    ("cawmsa ", "cấm", "Breve->circumflex switch preserving tone 'cắm'+a -> 'cấm'"),
    ("towio ", "tôi", "Horn->circumflex switch across semi-vowel coda 'tơi'+o -> 'tôi'"),
    ("dowifo ", "dồi", "Horn->circumflex switch preserving tone 'dời'+o -> 'dồi'"),
    ("ddowifo ", "đồi", "Horn->circumflex switch preserving tone 'đời'+o -> 'đồi'"),
    ("mowio ", "môi", "Horn->circumflex switch 'mơi'+o -> 'môi'"),
    ("radio ", "radio", "English '-io' word 'radio' never triggers circumflex"),
    ("folio ", "folio", "English '-io' word 'folio' never triggers circumflex"),
    ("patio ", "patio", "English '-io' word 'patio' never triggers circumflex"),
    ("chi as ", "chi á", "VN particle 'chi á' after 'chi'"),
    ("gif as ", "gì á", "VN particle 'gì á' after 'gì'"),
    ("vaayj as ", "vậy á", "VN particle 'vậy á' after 'vậy'"),
    ("chaau as ", "châu á", "VN compound 'châu á' after 'châu'"),
    ("same as ", "same as", "English 'same as' stays English"),
    ("as ", "as", "Standalone 'as' stays English"),
    ("err ", "err", "Short English/dev token 'err' stays 'err'"),
    ("Err ", "Err", "Titlecase 'Err' stays 'Err'"),
    ("ERR ", "ERR", "ALL-CAPS 'ERR' stays 'ERR'"),
    ("dongdof ", "đồng", "Post-coda stroke-d + circumflex + tone 'dongdof' -> 'đồng'"),
    ("download ", "download", "English 'download' never triggers post-coda stroke-d"),
    ("dashboard ", "dashboard", "English 'dashboard' never triggers post-coda stroke-d"),
    ("depend ", "depend", "English 'depend' never triggers post-coda stroke-d"),
    ("diamond ", "diamond", "English 'diamond' never triggers post-coda stroke-d"),
    ("benhj ", "benhj", "Invalid uncircumflexed 'enh'+tone stays raw 'benhj'"),
    ("lechj ", "lechj", "Invalid uncircumflexed 'ech'+tone stays raw 'lechj'"),
    ("luanj ", "luanj", "Invalid uncircumflexed non-qu 'uan'+tone stays raw 'luanj'"),
    ("quanr ", "quản", "Valid qu-onset 'quanr' -> 'quản'"),
    (":w ", ":w", "Vim ':w' stays ':w'"),
    (":wq ", ":wq", "Vim ':wq' stays ':wq'"),
    (":wwq ", ":wq", "Vim ':wwq' collapses to ':wq'"),
    ("onw own ", "ơn ơn", "Telex 'onw' and 'own' -> 'ơn ơn'"),
    ("chafo ", "chào", "Inline tone placement 'chafo' -> 'chào'"),
    ("Nghixa laf cho duf ", "Nghĩa là cho dù", "VN phrase 'Nghĩa là cho dù'"),
    ("beef ", "bề", "Single-path VN 'bề' never shadowed by unconditional EN 'beef'"),
    ("mas ", "má", "Single-path VN 'má' never shadowed by unconditional EN 'mas'"),
    ("lux ", "lũ", "Single-path VN 'lũ' never shadowed by unconditional EN 'lux'"),
    ("the beef ", "the beef", "English context 'the beef' restores 'beef'"),
    # 8. Central Highlands / ethnic-minority Vietnamese proper nouns + kr- English safety
    ("DDawsk Lawsk ", "Đắk Lắk", "Central Highlands province 'Đắk Lắk' (tone before coda k)"),
    ("DDawks Lawks ", "Đắk Lắk", "Central Highlands province 'Đắk Lắk' (tone after coda k)"),
    ("lawsk ", "lắk", "Lowercase 'lawsk' -> 'lắk'"),
    ("Kroong Pawcs ", "Krông Pắc", "Central Highlands district 'Krông Pắc'"),
    ("Krongo ", "Krông", "Post-coda circumflex 'Krongo' -> 'Krông'"),
    ("kroong ", "krông", "Lowercase 'kroong' -> 'krông'"),
    ("kruger ", "kruger", "English kr- word 'kruger' stays English"),
    ("krisflyer ", "krisflyer", "English kr- word 'krisflyer' stays English"),
]


def ensure_swift_cli() -> Path:
    candidates = [
        ROOT / ".build" / "release" / "VieLotusCLI",
        ROOT / ".build" / "arm64-apple-macosx" / "release" / "VieLotusCLI",
        ROOT / ".build" / "x86_64-apple-macosx" / "release" / "VieLotusCLI",
        ROOT / ".build" / "debug" / "VieLotusCLI",
    ]
    for p in candidates:
        if p.is_file() and os.access(p, os.X_OK):
            return p
    print("-> Building Swift VieLotusCLI (release)...", flush=True)
    subprocess.run(
        ["swift", "build", "-c", "release", "--product", "VieLotusCLI"],
        cwd=ROOT,
        check=True,
    )
    for p in candidates:
        if p.is_file() and os.access(p, os.X_OK):
            return p
    raise RuntimeError("Could not locate VieLotusCLI binary after swift build")


def ensure_cpp_lab() -> Path:
    lab_bin = ROOT / ".build" / "windows-lab" / "VieLotusWinEngineLab"
    cpp_src = ROOT / "Sources" / "VieLotusCoreWindows" / "WindowsNativeEngine.cpp"
    test_src = ROOT / "Tests" / "WindowsEngineLab" / "main.cpp"
    needs_build = (
        not lab_bin.is_file()
        or lab_bin.stat().st_mtime < cpp_src.stat().st_mtime
        or lab_bin.stat().st_mtime < test_src.stat().st_mtime
    )
    if needs_build:
        print("-> Building C++ VieLotusWinEngineLab...", flush=True)
        subprocess.run(
            [str(ROOT / "scripts" / "test_windows_engine.sh")],
            cwd=ROOT,
            check=True,
        )
    return lab_bin


def run_swift_batch(swift_bin: Path, inputs: List[str]) -> List[str]:
    payload = "\n".join(inputs) + "\nexit\n"
    proc = subprocess.run(
        [str(swift_bin)],
        input=payload,
        text=True,
        capture_output=True,
        cwd=ROOT,
        check=True,
    )
    outs: List[str] = []
    for line in proc.stdout.splitlines():
        if "Kết quả: " in line:
            outs.append(line.split("Kết quả: ", 1)[1].rstrip(" "))
    if len(outs) != len(inputs):
        raise RuntimeError(f"Swift REPL output count mismatch: got {len(outs)}, expected {len(inputs)}")
    return outs


def run_cpp_batch(cpp_bin: Path, inputs: List[str]) -> List[str]:
    outs: List[str] = []
    chunk_size = 20
    for i in range(0, len(inputs), chunk_size):
        chunk = inputs[i : i + chunk_size]
        spec = " | ".join(s.rstrip(" ") for s in chunk)
        proc = subprocess.run(
            [str(cpp_bin), "--trace", spec],
            text=True,
            capture_output=True,
            cwd=ROOT,
            check=True,
        )
        for line in proc.stdout.splitlines():
            if line.startswith('FINAL OUTPUT: "') and line.endswith('"'):
                outs.append(line[len('FINAL OUTPUT: "') : -1])
    if len(outs) != len(inputs):
        raise RuntimeError(f"C++ trace output count mismatch: got {len(outs)}, expected {len(inputs)}")
    return outs


def extract_cpp_bilingual_phrases() -> List[Tuple[str, str, str]]:
    text = (ROOT / "Tests" / "WindowsEngineLab" / "main.cpp").read_text(encoding="utf-8")
    block = text.split("const PhraseTest kBilingualPhrases[] = {", 1)[1].split("};", 1)[0]
    items: List[Tuple[str, str, str]] = []
    pattern = re.compile(r'\{\s*"((?:[^"\\]|\\.)*)"\s*,\s*"((?:[^"\\]|\\.)*)"\s*,\s*"((?:[^"\\]|\\.)*)"\s*\}')
    for m in pattern.finditer(block):
        raw = bytes(m.group(1), "utf-8").decode("unicode_escape").encode("latin1").decode("utf-8")
        exp = bytes(m.group(2), "utf-8").decode("unicode_escape").encode("latin1").decode("utf-8")
        if "\b" in raw:
            continue
        items.append((raw, exp.rstrip(" "), m.group(3)))
    return items


def main() -> int:
    parser = argparse.ArgumentParser(description="Cross-engine Swift <-> C++ behavioral parity gate")
    parser.add_argument("--report-all", action="store_true", help="Also report deltas across all kBilingualPhrases")
    args = parser.parse_args()

    swift_bin = ensure_swift_cli()
    cpp_bin = ensure_cpp_lab()

    inputs = [row[0] for row in RATIFIED_PARITY_SUITE]
    swift_outs = run_swift_batch(swift_bin, inputs)
    cpp_outs = run_cpp_batch(cpp_bin, inputs)

    failures: List[str] = []
    for (raw, expected, note), sw, cp in zip(RATIFIED_PARITY_SUITE, swift_outs, cpp_outs):
        if sw != expected or cp != expected:
            failures.append(
                f"  FAIL [{note}]\n"
                f"    raw     : {raw!r}\n"
                f"    expected: {expected!r}\n"
                f"    Swift   : {sw!r}\n"
                f"    C++     : {cp!r}"
            )

    total = len(RATIFIED_PARITY_SUITE)
    passed = total - len(failures)
    print("================================================================")
    print("  VieLotusIM Cross-Engine Parity Gate (Swift 6 <-> C++20)")
    print("================================================================")
    print(f"  RATIFIED PARITY SUITE    : {passed:4d} / {total:4d} ({100.0 * passed / total:6.2f}%)")
    print("================================================================")

    if failures:
        for f in failures:
            print(f)
        return 1

    if args.report_all:
        phrases = extract_cpp_bilingual_phrases()
        p_inputs = [p[0] for p in phrases]
        p_swift = run_swift_batch(swift_bin, p_inputs)
        p_cpp = run_cpp_batch(cpp_bin, p_inputs)
        deltas = []
        for (raw, exp, note), sw, cp in zip(phrases, p_swift, p_cpp):
            if sw != cp:
                deltas.append((raw.strip(), sw, cp, note))
        print(f"\n  FULL kBilingualPhrases AUDIT: {len(phrases) - len(deltas)}/{len(phrases)} identical, {len(deltas)} architectural/policy deltas:")
        for raw_s, sw, cp, note in deltas:
            print(f"    - {raw_s!r:20s} | Swift={sw!r:18s} | C++={cp!r:18s} | {note}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
