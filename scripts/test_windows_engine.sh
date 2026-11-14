#!/bin/bash
# ==============================================================================
# VieLotusIM — Windows Native Engine Lab & Regression Gate
# Usage:
#   ./scripts/test_windows_engine.sh                # Full 9,091-case + phrase benchmark
#   ./scripts/test_windows_engine.sh --trace "tooi sex ddi | phim sex | lufn turn | turn on"
#   ./scripts/test_windows_engine.sh --repl         # Interactive keystroke lab
# ==============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/.build/windows-lab"
GEN_DIR="${BUILD_DIR}/generated"
BIN="${BUILD_DIR}/VieLotusWinEngineLab"

mkdir -p "${BUILD_DIR}" "${GEN_DIR}/VieLotusLexicon"
rm -f "${GEN_DIR}/WindowsNativeLexiconGenerated.inc"

# 1. Verify reference prebuilt/VieLotusLexicon/WindowsNativeLexiconGenerated.inc matches canonical UTF-8 NFC wordlists
python3 "${ROOT_DIR}/Sources/VieLotusCoreWindows/scripts/generate_lexicon_hashes.py" --check

# 1b. Enforce ODR struct layout parity between Sources/VieLotusCoreWindows/WindowsNativeEngine.h and CrossPlatform/windows-tsf/src/WindowsNativeEngine.h
if ! cmp -s "${ROOT_DIR}/Sources/VieLotusCoreWindows/WindowsNativeEngine.h" "${ROOT_DIR}/CrossPlatform/windows-tsf/src/WindowsNativeEngine.h"; then
    echo "ERROR: ODR mismatch between Sources/VieLotusCoreWindows/WindowsNativeEngine.h and CrossPlatform/windows-tsf/src/WindowsNativeEngine.h" >&2
    diff -u "${ROOT_DIR}/Sources/VieLotusCoreWindows/WindowsNativeEngine.h" "${ROOT_DIR}/CrossPlatform/windows-tsf/src/WindowsNativeEngine.h" >&2 || true
    exit 1
fi

# 2. Generate fresh lexicon lookup header from plaintext wordlists into isolated build directory
#    Note: prebuilt/ is intentionally NOT in -I, so compilation exclusively uses ${GEN_DIR}/VieLotusLexicon/...
python3 "${ROOT_DIR}/Sources/VieLotusCoreWindows/scripts/generate_lexicon_hashes.py" \
    --output "${GEN_DIR}/VieLotusLexicon/WindowsNativeLexiconGenerated.inc"

CXX_BIN="${CXX:-}"
if [ -z "${CXX_BIN}" ]; then
    if command -v clang++ >/dev/null 2>&1; then
        CXX_BIN="clang++"
    elif command -v g++ >/dev/null 2>&1; then
        CXX_BIN="g++"
    else
        CXX_BIN="c++"
    fi
fi

"${CXX_BIN}" -std=c++20 -O2 \
    -I"${GEN_DIR}" \
    -I"${ROOT_DIR}/Sources/VieLotusCoreWindows" \
    -I"${ROOT_DIR}/Sources/VieLotusCAPI/include" \
    -I"${ROOT_DIR}/CrossPlatform/common" \
    "${ROOT_DIR}/Tests/WindowsEngineLab/main.cpp" \
    "${ROOT_DIR}/Sources/VieLotusCoreWindows/WindowsNativeEngine.cpp" \
    -o "${BIN}"

CC_BIN="${CC:-}"
if [ -z "${CC_BIN}" ]; then
    if command -v clang >/dev/null 2>&1; then
        CC_BIN="clang"
    elif command -v gcc >/dev/null 2>&1; then
        CC_BIN="gcc"
    else
        CC_BIN="cc"
    fi
fi
"${CC_BIN}" -std=c11 -Wall -Wextra -Werror \
    -I"${ROOT_DIR}/CrossPlatform/common" \
    -I"${ROOT_DIR}/Sources/VieLotusCAPI/include" \
    -fsyntax-only -x c "${ROOT_DIR}/CrossPlatform/common/vielotus_linux_common.h"

if command -v x86_64-w64-mingw32-g++ >/dev/null 2>&1; then
    x86_64-w64-mingw32-g++ -std=c++20 -DVIELOTUS_EMBEDDED_ENGINE=1 \
        -I"${GEN_DIR}" \
        -I"${ROOT_DIR}/CrossPlatform/windows-tsf/src" \
        -I"${ROOT_DIR}/Sources/VieLotusCAPI/include" \
        -I"${ROOT_DIR}/Sources/VieLotusCoreWindows" \
        -fsyntax-only "${ROOT_DIR}"/CrossPlatform/windows-tsf/src/*.cpp
fi

if [ $# -eq 0 ]; then
    "${BIN}" "${ROOT_DIR}/Sources/VieLotusCLI/Resources/test_suite.csv"
else
    "${BIN}" "$@"
fi
