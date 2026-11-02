// =============================================================================
// VieLotusIM (Sen Việt) — Cross-Platform Native C++20 Input Method Engine
// Copyright (c) 2026 Trần Phát Đạt (Steve Dat) <ttd1232004@gmail.com>
// SPDX-License-Identifier: MIT
//
// Canonical C++20 maintenance source for Linux (libvielotus0 / IBus / Fcitx5)
// and Windows (Text Services Framework). Lexicon hash tables are generated
// deterministically from UTF-8 (Unicode NFC) wordlists in `./lexicon/*.txt`
// via `python3 Sources/VieLotusCoreWindows/scripts/generate_lexicon_hashes.py`.
// =============================================================================

#include "WindowsNativeEngine.h"

namespace vielotus_win {

namespace {

constexpr int kMaxWordTokens = WindowsNativeEngine::kMaxWordTokens;
constexpr int kMaxUtf8Bytes = WindowsNativeEngine::kMaxUtf8Bytes;

// Precomposed Unicode NFC Vietnamese vowel tables:
// Rows (12): a, ă, â, e, ê, i, o, ô, ơ, u, ư, y
// Columns (6): 0=ngang, 1=sắc, 2=huyền, 3=hỏi, 4=ngã, 5=nặng
constexpr wchar_t kLowerVowelTable[12][6] = {
    { 0x0061, 0x00E1, 0x00E0, 0x1EA3, 0x00E3, 0x1EA1 },
    { 0x0103, 0x1EAF, 0x1EB1, 0x1EB3, 0x1EB5, 0x1EB7 },
    { 0x00E2, 0x1EA5, 0x1EA7, 0x1EA9, 0x1EAB, 0x1EAD },
    { 0x0065, 0x00E9, 0x00E8, 0x1EBB, 0x1EBD, 0x1EB9 },
    { 0x00EA, 0x1EBF, 0x1EC1, 0x1EC3, 0x1EC5, 0x1EC7 },
    { 0x0069, 0x00ED, 0x00EC, 0x1EC9, 0x0129, 0x1ECB },
    { 0x006F, 0x00F3, 0x00F2, 0x1ECF, 0x00F5, 0x1ECD },
    { 0x00F4, 0x1ED1, 0x1ED3, 0x1ED5, 0x1ED7, 0x1ED9 },
    { 0x01A1, 0x1EDB, 0x1EDD, 0x1EDF, 0x1EE1, 0x1EE3 },
    { 0x0075, 0x00FA, 0x00F9, 0x1EE7, 0x0169, 0x1EE5 },
    { 0x01B0, 0x1EE9, 0x1EEB, 0x1EED, 0x1EEF, 0x1EF1 },
    { 0x0079, 0x00FD, 0x1EF3, 0x1EF7, 0x1EF9, 0x1EF5 }
};

constexpr wchar_t kUpperVowelTable[12][6] = {
    { 0x0041, 0x00C1, 0x00C0, 0x1EA2, 0x00C3, 0x1EA0 },
    { 0x0102, 0x1EAE, 0x1EB0, 0x1EB2, 0x1EB4, 0x1EB6 },
    { 0x00C2, 0x1EA4, 0x1EA6, 0x1EA8, 0x1EAA, 0x1EAC },
    { 0x0045, 0x00C9, 0x00C8, 0x1EBA, 0x1EBC, 0x1EB8 },
    { 0x00CA, 0x1EBE, 0x1EC0, 0x1EC2, 0x1EC4, 0x1EC6 },
    { 0x0049, 0x00CD, 0x00CC, 0x1EC8, 0x0128, 0x1ECA },
    { 0x004F, 0x00D3, 0x00D2, 0x1ECE, 0x00D5, 0x1ECC },
    { 0x00D4, 0x1ED0, 0x1ED2, 0x1ED4, 0x1ED6, 0x1ED8 },
    { 0x01A0, 0x1EDA, 0x1EDC, 0x1EDE, 0x1EE0, 0x1EE2 },
    { 0x0055, 0x00DA, 0x00D9, 0x1EE6, 0x0168, 0x1EE4 },
    { 0x01AF, 0x1EE8, 0x1EEA, 0x1EEC, 0x1EEE, 0x1EF0 },
    { 0x0059, 0x00DD, 0x1EF2, 0x1EF6, 0x1EF8, 0x1EF4 }
};

constexpr uint64_t fnv1aHash(const wchar_t *s, int len) {
    uint64_t h = 0xcbf29ce484222325ULL;
    for (int i = 0; i < len; ++i) {
        h ^= static_cast<uint64_t>(s[i]);
        h *= 0x100000001b3ULL;
    }
    return h;
}

template <size_t N>
bool hasSortedHash(const uint64_t (&arr)[N], uint64_t target) {
    size_t lo = 0, hi = N;
    while (lo < hi) {
        size_t mid = lo + (hi - lo) / 2;
        if (arr[mid] == target) return true;
        if (arr[mid] < target) lo = mid + 1;
        else hi = mid;
    }
    return false;
}

#include <VieLotusLexicon/WindowsNativeLexiconGenerated.inc>

bool isAsciiAlpha(uint32_t cp) {
    return (cp >= 'A' && cp <= 'Z') || (cp >= 'a' && cp <= 'z');
}

bool isAsciiDigit(uint32_t cp) {
    return (cp >= '0' && cp <= '9');
}

wchar_t toLowerAscii(wchar_t ch) {
    if (ch >= L'A' && ch <= L'Z') {
        return ch + (L'a' - L'A');
    }
    return ch;
}

bool hasDoubleO(const wchar_t *s, int len) {
    for (int i = 0; i + 1 < len; ++i) {
        if (s[i] == L'o' && s[i + 1] == L'o') return true;
    }
    return false;
}

bool isValidInitialOnset(const wchar_t *init, int initLen, bool hasStrokeD) {
    if (hasStrokeD) {
        return (initLen == 1 && init[0] == L'd');
    }
    return hasSortedHash(kValidInitialOnsets, fnv1aHash(init, initLen));
}

bool isValidFinalCoda(const wchar_t *coda, int codaLen) {
    return hasSortedHash(kValidFinalCodas, fnv1aHash(coda, codaLen));
}

bool isStopCoda(const wchar_t *coda, int codaLen) {
    return hasSortedHash(kStopCodas, fnv1aHash(coda, codaLen));
}

bool isValidDoubleOCoda(const wchar_t *coda, int codaLen) {
    return hasSortedHash(kDoubleOCodas, fnv1aHash(coda, codaLen));
}

bool isUnconditionalEnglishWord(const wchar_t *rawLower, int rawLen) {
    if (rawLen <= 0) return false;
    return hasSortedHash(kUnconditionalEnglishWords, fnv1aHash(rawLower, rawLen));
}

bool isContextEnglishCollisionWord(const wchar_t *rawLower, int rawLen) {
    if (rawLen <= 0) return false;
    return hasSortedHash(kContextEnglishCollisionWords, fnv1aHash(rawLower, rawLen));
}

bool isEnglishContextAnchor(const wchar_t *rawLower, int rawLen) {
    if (rawLen <= 0) return false;
    return hasSortedHash(kEnglishContextAnchors, fnv1aHash(rawLower, rawLen));
}

bool isSexLoanwordPrecedingHead(const wchar_t *w, int len) {
    if (len <= 0) return false;
    return hasSortedHash(kSexLoanwordPrecedingHeads, fnv1aHash(w, len));
}

bool isVietnameseContextReset(const wchar_t *w, int len) {
    if (len <= 0) return false;
    return hasSortedHash(kVietnameseContextResets, fnv1aHash(w, len));
}

bool isTurnPhrasalFollower(const wchar_t *w, int len) {
    if (len <= 0) return false;
    return hasSortedHash(kTurnPhrasalFollowers, fnv1aHash(w, len));
}

bool isSexEnglishFollower(const wchar_t *w, int len) {
    if (len <= 0) return false;
    return hasSortedHash(kSexEnglishFollowers, fnv1aHash(w, len));
}

bool isExtendedEnglishEscapeWord(const wchar_t *rawLower, int rawLen) {
    if (rawLen <= 0) return false;
    return hasSortedHash(kExtendedEnglishEscapeWords, fnv1aHash(rawLower, rawLen));
}

bool isExcludedTripleOrWwwEscape(const wchar_t *rawLower, int rawLen) {
    if (rawLen == 3 &&
        ((rawLower[0] == L'a' && rawLower[1] == L'a' && rawLower[2] == L'a') ||
         (rawLower[0] == L'o' && rawLower[1] == L'o' && rawLower[2] == L'o'))) {
        return true;
    }
    if (rawLen == 4 && rawLower[0] == L'i' && rawLower[1] == L'e' && rawLower[2] == L'e' && rawLower[3] == L'e') {
        return true;
    }
    if (rawLen >= 3 && rawLower[0] == L'w' && rawLower[1] == L'w' && rawLower[2] == L'w') {
        return true;
    }
    return false;
}

bool isLeadingSlashCommandOrPathToken(const wchar_t *rawLower, int rawLen) {
    if (rawLen < 2 || rawLen > 16) return false;
    static const wchar_t *const kSlashTokens[] = {
        L"add", L"agents", L"api", L"app", L"apps", L"ar", L"as", L"aw", L"awk", L"aws",
        L"bash", L"bin", L"boost", L"boot", L"browser", L"bug", L"build",
        L"cast", L"cash", L"clear", L"compact", L"config", L"core", L"cost",
        L"dash", L"dev", L"diff", L"dist", L"doc", L"docs", L"doctor",
        L"env", L"es", L"etc", L"ex", L"exit",
        L"fast", L"git", L"goal", L"hash", L"help", L"home", L"host",
        L"if", L"image", L"info", L"init", L"ir", L"is", L"ix",
        L"last", L"learn", L"lib", L"list", L"log", L"login", L"logout", L"logs", L"loop",
        L"mask", L"mcp", L"memory", L"mnt", L"model", L"models", L"more",
        L"new", L"of", L"opt", L"or", L"os", L"out",
        L"permissions", L"pkg", L"plan", L"port", L"post", L"pr", L"proc",
        L"quit", L"raw", L"reset", L"review", L"room", L"root", L"run",
        L"sbin", L"schedule", L"search", L"share", L"sort", L"src", L"srv", L"ssh", L"start", L"status", L"stop", L"store", L"sys",
        L"task", L"tasks", L"teamwork", L"terminal", L"test", L"tests", L"tmp", L"tool", L"tools",
        L"ur", L"us", L"user", L"users", L"usr",
        L"var", L"vim", L"voice", L"war", L"was", L"web", L"zoom"
    };
    for (const wchar_t *tok : kSlashTokens) {
        int i = 0;
        while (i < rawLen && tok[i] != L'\0' && rawLower[i] == tok[i]) {
            ++i;
        }
        if (i == rawLen && tok[i] == L'\0') {
            return true;
        }
    }
    return false;
}

// Per-character syllable token:
// shape: 0=plain, 1=circumflex (â/ê/ô), 2=horn (ơ/ư), 3=breve (ă), 4=stroke (đ)
struct SyllableToken {
    wchar_t baseLower{0};
    bool isUpper{false};
    int shape{0};
};

struct NativeEngineState {
    InputMethod m_inputMethod{InputMethod::Telex};
    int32_t m_grammarProfile{1};
    bool m_smartBilingual{true};
    bool m_modernOrthography{true};
    bool m_quickTelex{false};

    wchar_t m_rawWord[kMaxWordTokens]{};
    int m_rawLen{0};

    wchar_t m_displayed[kMaxWordTokens]{};
    int m_displayedLen{0};

    wchar_t m_literalTail[kMaxWordTokens]{};
    int m_literalTailLen{0};

    SyllableToken m_tokens[kMaxWordTokens]{};
    int m_tokenLen{0};

    int m_tone{0};
    wchar_t m_lastToneKey{0};
    wchar_t m_lastShapeKey{0};
    bool m_literalLock{false};
    bool m_shapeCancelledOnce{false};
    bool m_toneCancelledPlain{false};
    bool m_uHornFromOwnW{false};
    bool m_preVowelTone{false};
    bool m_nonAdjacentCircumflex{false};
    bool m_classicOrVniEscape{false};
    bool m_telexToneEscape{false};
    bool m_overflowLocked{false};
    int m_escapeLockTokenLen{0};

    bool m_hasUndoSnapshot{false};
    bool m_armedAfterSpace{false};
    SyllableToken m_undoTokens[kMaxWordTokens]{};
    int m_undoTokenLen{0};
    int m_undoTone{0};
    wchar_t m_undoLastToneKey{0};
    wchar_t m_undoLastShapeKey{0};
    wchar_t m_undoRawWord[kMaxWordTokens]{};
    int m_undoRawLen{0};
    wchar_t m_undoLiteralTail[kMaxWordTokens]{};
    int m_undoLiteralTailLen{0};
    bool m_undoLiteralLock{false};
    int m_undoEscapeLockTokenLen{0};
    bool m_undoClassicOrVniEscape{false};
    bool m_undoTelexToneEscape{false};
    bool m_undoOverflowLocked{false};

    int32_t m_lastBackspaces{0};
    bool m_lastIsOverride{false};
    char m_lastTextUtf8[kMaxUtf8Bytes]{};
    bool m_inEnglishContext{false};
    bool m_lastWordWasSexLoanwordHead{false};
    bool m_precededByTechDelimiter{false};
    bool m_afterDigit{false};
    bool m_precededByLeadingSlash{false};
    uint32_t m_pendingBoundaryCp{0};
    wchar_t m_prevCollisionDisplayed[16]{};
    int m_prevCollisionDisplayedLen{0};
    wchar_t m_prevCollisionRaw[16]{};
    int m_prevCollisionRawLen{0};

    void clearWordState() {
        m_rawLen = 0;
        m_rawWord[0] = 0;
        m_displayedLen = 0;
        m_displayed[0] = 0;
        m_literalTailLen = 0;
        m_literalTail[0] = 0;
        m_tokenLen = 0;
        m_tone = 0;
        m_lastToneKey = 0;
        m_lastShapeKey = 0;
        m_literalLock = false;
        m_shapeCancelledOnce = false;
        m_toneCancelledPlain = false;
        m_uHornFromOwnW = false;
        m_preVowelTone = false;
        m_nonAdjacentCircumflex = false;
        m_classicOrVniEscape = false;
        m_telexToneEscape = false;
        m_overflowLocked = false;
        m_escapeLockTokenLen = 0;
        m_hasUndoSnapshot = false;
        m_armedAfterSpace = false;
        m_lastBackspaces = 0;
        m_lastTextUtf8[0] = '\0';
    }

    bool isComposing() const {
        return m_displayedLen > 0 || m_armedAfterSpace;
    }

    bool rawWordStartsNonW() const {
        return m_rawLen > 0 && m_rawWord[0] != L'w' && m_rawWord[0] != L'W';
    }

    bool hasCompoundUoOrStrokeD() const {
        for (int i = 0; i < m_tokenLen; ++i) {
            if (m_tokens[i].baseLower == L'd' && m_tokens[i].shape == 4) {
                return true;
            }
            if (i + 1 < m_tokenLen &&
                m_tokens[i].baseLower == L'u' && m_tokens[i].shape == 2 &&
                m_tokens[i + 1].baseLower == L'o' && m_tokens[i + 1].shape == 2) {
                return true;
            }
        }
        return false;
    }

    bool isOpenSameVowelExtension() const {
        if (m_tone == 0 || m_literalTailLen <= 0 || m_tokenLen < 2 || !rawWordStartsNonW()) {
            return false;
        }
        int vStart = -1, vEnd = -1;
        bool hasCoda = false;
        findVowelCluster(vStart, vEnd, hasCoda);
        if (vStart <= 0 || hasCoda || vEnd != m_tokenLen - 1) {
            return false;
        }
        wchar_t initStr[16]{};
        int initLen = 0;
        for (int i = 0; i < vStart && initLen < 15; ++i) {
            initStr[initLen++] = m_tokens[i].baseLower;
        }
        const bool hasStrokeD = (vStart == 1 && m_tokens[0].baseLower == L'd' && m_tokens[0].shape == 4);
        if (!isValidInitialOnset(initStr, initLen, hasStrokeD)) {
            return false;
        }
        const wchar_t baseV = m_tokens[vEnd].baseLower;
        for (int i = 0; i < m_literalTailLen; ++i) {
            if (toLowerAscii(m_literalTail[i]) != baseV) {
                return false;
            }
        }
        return true;
    }

    void saveUndoSnapshot();
    void setInputMethod(InputMethod method);
    static bool isWordBoundaryDelimiter(uint32_t cp);
    static bool isAsciiBaseVowel(wchar_t lowerCh);
    static wchar_t renderTokenWithTone(const SyllableToken &tok, int tone);
    static void encodeWideToUtf8(const wchar_t *wstr, int wlen, char *outUtf8, int maxOut);
    void findVowelCluster(int &outStart, int &outEnd, bool &outHasCoda) const;
    int resolveToneTargetIndex(int vowelStart, int vowelEnd, bool hasCoda) const;
    bool hasVietnameseTransformation() const;
    bool isValidVietnameseSyllable() const;
    bool shouldRestoreRawEnglish() const;
    int composeOutputWord(wchar_t *outBuf, int maxLen) const;
    bool applyTelexCharacter(wchar_t ch, wchar_t lowerCh, bool isUpper);
    bool applyVniCharacter(wchar_t ch);
    int32_t emitIncrementalReplacement(const wchar_t *priorDisplayed, int priorLen, const wchar_t *newDisplayed, int newLen);
    int32_t feedChar(uint32_t codepoint);
    int32_t feedBackspace();
    int32_t commitWord();
};

void NativeEngineState::saveUndoSnapshot() {
    m_hasUndoSnapshot = true;
    m_undoTokenLen = m_tokenLen;
    for (int i = 0; i < m_tokenLen; ++i) {
        m_undoTokens[i] = m_tokens[i];
    }
    m_undoTone = m_tone;
    m_undoRawLen = (m_rawLen > 0) ? (m_rawLen - 1) : 0;
    for (int i = 0; i < m_undoRawLen; ++i) {
        m_undoRawWord[i] = m_rawWord[i];
    }
    m_undoRawWord[m_undoRawLen] = 0;
}

void NativeEngineState::setInputMethod(InputMethod method) {
    if (m_inputMethod != method) {
        m_inputMethod = method;
        clearWordState();
    }
}

bool NativeEngineState::isWordBoundaryDelimiter(uint32_t cp) {
    if (cp == ' ' || cp == '\t' || cp == '\r' || cp == '\n') return true;
    switch (cp) {
    case ',': case ';': case ':': case '!': case '?':
    case '"': case '\'': case '(': case ')': case '[':
    case ']': case '{': case '}': case '<': case '>':
    case '-': case '/': case '\\': case '.': case '_':
        return true;
    default:
        return false;
    }
}

bool NativeEngineState::isAsciiBaseVowel(wchar_t lowerCh) {
    return lowerCh == L'a' || lowerCh == L'e' || lowerCh == L'i' ||
           lowerCh == L'o' || lowerCh == L'u' || lowerCh == L'y';
}

wchar_t NativeEngineState::renderTokenWithTone(const SyllableToken &tok, int tone) {
    if (tok.baseLower == L'd') {
        if (tok.shape == 4) {
            return tok.isUpper ? static_cast<wchar_t>(0x0110) : static_cast<wchar_t>(0x0111);
        }
        return tok.isUpper ? L'D' : L'd';
    }

    int row = -1;
    switch (tok.baseLower) {
    case L'a':
        if (tok.shape == 3) row = 1;      // ă
        else if (tok.shape == 1) row = 2; // â
        else row = 0;                     // a
        break;
    case L'e':
        row = (tok.shape == 1) ? 4 : 3;   // ê : e
        break;
    case L'i':
        row = 5;
        break;
    case L'o':
        if (tok.shape == 1) row = 7;      // ô
        else if (tok.shape == 2) row = 8; // ơ
        else row = 6;                     // o
        break;
    case L'u':
        row = (tok.shape == 2) ? 10 : 9;  // ư : u
        break;
    case L'y':
        row = 11;
        break;
    default:
        break;
    }

    if (row >= 0 && tone >= 0 && tone <= 5) {
        return tok.isUpper ? kUpperVowelTable[row][tone] : kLowerVowelTable[row][tone];
    }

    return tok.isUpper ? static_cast<wchar_t>(tok.baseLower - (L'a' - L'A')) : tok.baseLower;
}

void NativeEngineState::encodeWideToUtf8(const wchar_t *wstr, int wlen, char *outUtf8, int maxOut) {
    int pos = 0;
    for (int i = 0; i < wlen && pos + 4 < maxOut; ++i) {
        uint32_t cp = static_cast<uint32_t>(wstr[i]);
        if constexpr (sizeof(wchar_t) == 2) {
            if (cp >= 0xD800 && cp <= 0xDBFF && (i + 1) < wlen) {
                uint32_t low = static_cast<uint32_t>(wstr[i + 1]);
                if (low >= 0xDC00 && low <= 0xDFFF) {
                    cp = 0x10000 + (((cp - 0xD800) << 10) | (low - 0xDC00));
                    ++i;
                }
            }
        }
        if (cp <= 0x7F) {
            outUtf8[pos++] = static_cast<char>(cp);
        } else if (cp <= 0x7FF) {
            outUtf8[pos++] = static_cast<char>(0xC0 | ((cp >> 6) & 0x1F));
            outUtf8[pos++] = static_cast<char>(0x80 | (cp & 0x3F));
        } else if (cp <= 0xFFFF) {
            outUtf8[pos++] = static_cast<char>(0xE0 | ((cp >> 12) & 0x0F));
            outUtf8[pos++] = static_cast<char>(0x80 | ((cp >> 6) & 0x3F));
            outUtf8[pos++] = static_cast<char>(0x80 | (cp & 0x3F));
        } else {
            outUtf8[pos++] = static_cast<char>(0xF0 | ((cp >> 18) & 0x07));
            outUtf8[pos++] = static_cast<char>(0x80 | ((cp >> 12) & 0x3F));
            outUtf8[pos++] = static_cast<char>(0x80 | ((cp >> 6) & 0x3F));
            outUtf8[pos++] = static_cast<char>(0x80 | (cp & 0x3F));
        }
    }
    outUtf8[pos] = '\0';
}

void NativeEngineState::findVowelCluster(int &outStart, int &outEnd, bool &outHasCoda) const {
    outStart = -1;
    outEnd = -1;
    outHasCoda = false;

    const int n = m_tokenLen;
    int i = 0;
    while (i < n && !isAsciiBaseVowel(m_tokens[i].baseLower)) {
        ++i;
    }
    if (i >= n) return;

    // Handle 'qu' + vowel where 'u' is part of the initial consonant
    if (i == 1 && m_tokens[0].baseLower == L'q' && m_tokens[1].baseLower == L'u' && m_tokens[1].shape == 0) {
        if (i + 1 < n && isAsciiBaseVowel(m_tokens[i + 1].baseLower)) {
            ++i;
        }
    }
    // Handle 'gi' + vowel where 'i' is part of the initial consonant (never plain 'gii')
    else if (i == 1 && m_tokens[0].baseLower == L'g' && m_tokens[1].baseLower == L'i' && m_tokens[1].shape == 0) {
        if (i + 1 < n && isAsciiBaseVowel(m_tokens[i + 1].baseLower) &&
            !(m_tokens[i + 1].baseLower == L'i' && m_tokens[i + 1].shape == 0)) {
            ++i;
        }
    }

    outStart = i;
    while (i < n && isAsciiBaseVowel(m_tokens[i].baseLower)) {
        outEnd = i;
        ++i;
    }
    outHasCoda = (outEnd + 1 < n);
}

int NativeEngineState::resolveToneTargetIndex(int vowelStart, int vowelEnd, bool hasCoda) const {
    if (vowelStart < 0 || vowelEnd < vowelStart) return -1;
    int len = vowelEnd - vowelStart + 1;
    if (len == 1) return vowelStart;

    // If 'ươ' is present, tone goes on 'ơ'
    for (int i = vowelStart; i < vowelEnd; ++i) {
        if (m_tokens[i].baseLower == L'u' && m_tokens[i].shape == 2 &&
            m_tokens[i + 1].baseLower == L'o' && m_tokens[i + 1].shape == 2) {
            return i + 1;
        }
    }

    // Otherwise if any vowel has a diacritic shape (ă, â, ê, ô, ơ, ư), tone goes on it
    for (int i = vowelStart; i <= vowelEnd; ++i) {
        if (m_tokens[i].shape != 0) {
            return i;
        }
    }

    if (len == 2) {
        if (hasCoda) {
            return vowelStart + 1;
        }
        wchar_t v1 = m_tokens[vowelStart].baseLower;
        wchar_t v2 = m_tokens[vowelStart + 1].baseLower;
        if (m_modernOrthography && ((v1 == L'o' && (v2 == L'a' || v2 == L'e')) || (v1 == L'u' && v2 == L'y'))) {
            return vowelStart + 1;
        }
        return vowelStart;
    }

    // 3 vowels (oai, oay, uây, uôi, ươi, iêu, yêu, uya)
    return vowelStart + 1;
}

bool NativeEngineState::hasVietnameseTransformation() const {
    if (m_tone != 0) return true;
    for (int i = 0; i < m_tokenLen; ++i) {
        if (m_tokens[i].shape != 0) return true;
    }
    if (m_tokenLen + m_literalTailLen < m_rawLen) return true;
    return false;
}

bool NativeEngineState::isValidVietnameseSyllable() const {
    if (m_tokenLen == 0) return true;

    int vStart = -1, vEnd = -1;
    bool hasCoda = false;
    findVowelCluster(vStart, vEnd, hasCoda);

    if (vStart == -1) {
        if (m_tokenLen == 1 && m_tokens[0].baseLower == L'd' && m_tokens[0].shape == 4) {
            return true;
        }
        bool hasStrokeDToken = false;
        for (int i = 0; i < m_tokenLen; ++i) {
            if (m_tokens[i].baseLower == L'd' && m_tokens[i].shape == 4) {
                hasStrokeDToken = true;
                break;
            }
        }
        if (hasStrokeDToken && m_tokenLen >= 2 && m_tone == 0 && m_literalTailLen == 0) {
            if (m_tokenLen == 2 &&
                m_tokens[0].baseLower == L'd' && m_tokens[0].shape == 4 && !m_tokens[0].isUpper &&
                m_tokens[1].baseLower == L'r' && !m_tokens[1].isUpper) {
                return false;
            }
            return true;
        }
        return false;
    }

    wchar_t initStr[16]{};
    int initLen = 0;
    for (int i = 0; i < vStart && initLen < 15; ++i) {
        initStr[initLen++] = m_tokens[i].baseLower;
    }
    bool hasStrokeD = (vStart == 1 && m_tokens[0].baseLower == L'd' && m_tokens[0].shape == 4);
    if (!isValidInitialOnset(initStr, initLen, hasStrokeD)) {
        return false;
    }

    if (m_literalTailLen > 0) return false;

    int vLen = vEnd - vStart + 1;
    if (vLen > 3) return false;

    wchar_t codaStr[16]{};
    int codaLen = 0;
    for (int i = vEnd + 1; i < m_tokenLen; ++i) {
        if (isAsciiBaseVowel(m_tokens[i].baseLower)) {
            return false;
        }
        if (codaLen < 15) {
            codaStr[codaLen++] = m_tokens[i].baseLower;
        }
    }

    if (!isValidFinalCoda(codaStr, codaLen)) {
        return false;
    }

    // Initial 'p' (without 'h') never precedes 'ư' in Vietnamese (e.g. 'pwd' -> 'pưd')
    if (initLen == 1 && initStr[0] == L'p' && m_tokens[vStart].baseLower == L'u' && m_tokens[vStart].shape == 2) {
        return false;
    }

    if (vLen == 2) {
        wchar_t v1 = m_tokens[vStart].baseLower;
        int s1 = m_tokens[vStart].shape;
        wchar_t v2 = m_tokens[vStart + 1].baseLower;
        int s2 = m_tokens[vStart + 1].shape;
        bool validPair = false;
        if (v1 == L'a') {
            if ((v2 == L'i' || v2 == L'o') && s1 == 0 && s2 == 0 && codaLen == 0) validPair = true;
            else if ((v2 == L'u' || v2 == L'y') && (s1 == 0 || s1 == 1) && s2 == 0 && codaLen == 0) validPair = true;
        } else if (v1 == L'e') {
            if (v2 == L'o' && s1 == 0 && s2 == 0 && codaLen == 0) validPair = true;
            else if (v2 == L'u' && s1 == 1 && s2 == 0 && codaLen == 0) validPair = true;
        } else if (v1 == L'i') {
            if (v2 == L'a' && s1 == 0 && s2 == 0 && codaLen == 0) validPair = true;
            else if (v2 == L'e' && s1 == 0 && s2 == 1) validPair = true;
            else if (v2 == L'u' && s1 == 0 && s2 == 0 && codaLen == 0) validPair = true;
        } else if (v1 == L'o') {
            if (v2 == L'a' && s1 == 0 && (s2 == 0 || s2 == 3)) validPair = true;
            else if (v2 == L'e' && s1 == 0 && s2 == 0) validPair = true;
            else if (v2 == L'i' && (s1 == 0 || s1 == 1 || s1 == 2) && s2 == 0 && codaLen == 0) validPair = true;
            else if (v2 == L'o' && s1 == 0 && s2 == 0 && isValidDoubleOCoda(codaStr, codaLen)) validPair = true;
        } else if (v1 == L'u') {
            if (v2 == L'a' && ((s1 == 0 && (s2 == 0 || s2 == 1 || (initLen == 0 && s2 == 3 && codaLen > 0))) || (s1 == 2 && s2 == 0 && codaLen == 0))) validPair = true;
            else if (v2 == L'e' && s1 == 0 && s2 == 1) validPair = true;
            else if (v2 == L'i' && (s1 == 0 || s1 == 2) && s2 == 0 && codaLen == 0) validPair = true;
            else if (v2 == L'o' && ((s1 == 0 && s2 == 1) || (s1 == 2 && s2 == 2) || (codaLen == 0 && s1 == 2 && s2 == 0))) validPair = true;
            else if (v2 == L'y' && s1 == 0 && s2 == 0) validPair = true;
            else if (v2 == L'u' && s1 == 2 && s2 == 0 && codaLen == 0) validPair = true;
        } else if (v1 == L'y') {
            if (v2 == L'a' && s1 == 0 && s2 == 0 && codaLen == 0) validPair = true;
            else if (v2 == L'e' && s1 == 0 && s2 == 1) validPair = true;
        }
        if (!validPair) return false;
    } else if (vLen == 3) {
        wchar_t v1 = m_tokens[vStart].baseLower;
        int s1 = m_tokens[vStart].shape;
        wchar_t v2 = m_tokens[vStart + 1].baseLower;
        int s2 = m_tokens[vStart + 1].shape;
        wchar_t v3 = m_tokens[vStart + 2].baseLower;
        int s3 = m_tokens[vStart + 2].shape;
        bool validTrip = false;
        if ((v1 == L'i' || v1 == L'y') && v2 == L'e' && v3 == L'u' && s1 == 0 && s2 == 1 && s3 == 0 && codaLen == 0) validTrip = true;
        else if (v1 == L'o' && v2 == L'a' && (v3 == L'i' || v3 == L'y') && s1 == 0 && s2 == 0 && s3 == 0 && codaLen == 0) validTrip = true;
        else if (v1 == L'u' && v2 == L'a' && v3 == L'y' && s1 == 0 && s2 == 1 && s3 == 0 && codaLen == 0) validTrip = true;
        else if (v1 == L'u' && v2 == L'o' && (v3 == L'i' || v3 == L'u') && ((s1 == 0 && s2 == 1 && v3 == L'i') || (s1 == 2 && s2 == 2)) && s3 == 0 && codaLen == 0) validTrip = true;
        else if (v1 == L'u' && v2 == L'y' && v3 == L'a' && s1 == 0 && s2 == 0 && s3 == 0 && codaLen == 0) validTrip = true;
        else if (v1 == L'u' && v2 == L'y' && v3 == L'e' && s1 == 0 && s2 == 0 && s3 == 1) validTrip = true;
        else if (v1 == L'u' && v2 == L'y' && v3 == L'u' && s1 == 0 && s2 == 0 && s3 == 0 && codaLen == 0) validTrip = true;
        if (!validTrip) return false;
    }

    // "ươ" cannot pair with palatal codas "ch" or "nh" in Vietnamese phonotactics
    if (codaLen == 2 && codaStr[1] == L'h' && (codaStr[0] == L'c' || codaStr[0] == L'n')) {
        for (int i = vStart; i < vEnd; ++i) {
            if (m_tokens[i].baseLower == L'u' && m_tokens[i + 1].baseLower == L'o') {
                return false;
            }
        }
    }

    if (isStopCoda(codaStr, codaLen) && m_tone != 0 && m_tone != 1 && m_tone != 5) {
        return false;
    }

    wchar_t rawLower[kMaxWordTokens]{};
    for (int i = 0; i < m_rawLen; ++i) {
        rawLower[i] = toLowerAscii(m_rawWord[i]);
    }

    if (hasDoubleO(rawLower, m_rawLen) && codaLen > 0 && !isValidDoubleOCoda(codaStr, codaLen)) {
        return false;
    }

    if (m_rawLen >= 2 && rawLower[0] == L'w') {
        wchar_t second = rawLower[1];
        if (second == L'h' || second == L'o' || second == L'e' || (second == L'r' && m_rawLen >= 3) || second == L'l' ||
            (second == L'i' && m_rawLen >= 3 && rawLower[2] != L'u')) {
            return false;
        }
    }

    if (m_preVowelTone) {
        bool hasVowelShape = false;
        for (int i = vStart; i <= vEnd; ++i) {
            if (m_tokens[i].shape != 0) {
                hasVowelShape = true;
                break;
            }
        }
        if (!hasVowelShape) {
            return false;
        }
    }

    return true;
}

bool NativeEngineState::shouldRestoreRawEnglish() const {
    if (!m_smartBilingual || !hasVietnameseTransformation()) return false;

    wchar_t rawLower[kMaxWordTokens]{};
    for (int i = 0; i < m_rawLen; ++i) {
        rawLower[i] = toLowerAscii(m_rawWord[i]);
    }

    if (!isValidVietnameseSyllable()) {
        if (m_precededByLeadingSlash && isLeadingSlashCommandOrPathToken(rawLower, m_rawLen)) {
            return true;
        }
        if (m_classicOrVniEscape && !isExcludedTripleOrWwwEscape(rawLower, m_rawLen)) {
            return false;
        }
        if ((m_telexToneEscape || m_overflowLocked || isOpenSameVowelExtension()) &&
            !m_precededByTechDelimiter &&
            m_pendingBoundaryCp != '[' &&
            m_pendingBoundaryCp != '_' &&
            m_pendingBoundaryCp != '.' &&
            m_pendingBoundaryCp != '/' &&
            !isUnconditionalEnglishWord(rawLower, m_rawLen) &&
            !isExtendedEnglishEscapeWord(rawLower, m_rawLen)) {
            return false;
        }
        return true;
    }

    if (isUnconditionalEnglishWord(rawLower, m_rawLen)) {
        return true;
    }
    if (m_precededByLeadingSlash && isLeadingSlashCommandOrPathToken(rawLower, m_rawLen)) {
        return true;
    }
    if (isContextEnglishCollisionWord(rawLower, m_rawLen)) {
        if (m_precededByTechDelimiter) return true;
        if (m_pendingBoundaryCp == '_' || m_pendingBoundaryCp == '/' || m_pendingBoundaryCp == '.') return true;
        if (m_rawLen == 3 && rawLower[0] == L's' && rawLower[1] == L'e' && rawLower[2] == L'x') {
            if (m_lastWordWasSexLoanwordHead) return true;
        }
        if (m_inEnglishContext) return true;
    }
    return false;
}

int NativeEngineState::composeOutputWord(wchar_t *outBuf, int maxLen) const {
    if (m_smartBilingual && hasVietnameseTransformation() && shouldRestoreRawEnglish()) {
        int n = (m_rawLen < maxLen - 1) ? m_rawLen : (maxLen - 1);
        for (int i = 0; i < n; ++i) outBuf[i] = m_rawWord[i];
        outBuf[n] = 0;
        return n;
    }

    int vStart = -1, vEnd = -1;
    bool hasCoda = false;
    findVowelCluster(vStart, vEnd, hasCoda);
    int toneIdx = (m_tone != 0) ? resolveToneTargetIndex(vStart, vEnd, hasCoda) : -1;

    int outLen = 0;
    for (int i = 0; i < m_tokenLen && outLen < maxLen - 1; ++i) {
        int t = (i == toneIdx) ? m_tone : 0;
        outBuf[outLen++] = renderTokenWithTone(m_tokens[i], t);
    }
    for (int i = 0; i < m_literalTailLen && outLen < maxLen - 1; ++i) {
        outBuf[outLen++] = m_literalTail[i];
    }
    outBuf[outLen] = 0;
    return outLen;
}

bool NativeEngineState::applyTelexCharacter(wchar_t ch, wchar_t lowerCh, bool isUpper) {
    if (m_literalLock) return false;
    if (m_literalTailLen > 0) {
        if (m_toneCancelledPlain && lowerCh != m_lastToneKey) {
            m_toneCancelledPlain = false;
        }
        if (m_literalTailLen < kMaxWordTokens - 1) {
            m_literalTail[m_literalTailLen++] = ch;
            m_literalTail[m_literalTailLen] = 0;
        }
        return true;
    }

    int vStart = -1, vEnd = -1;
    bool hasCoda = false;
    findVowelCluster(vStart, vEnd, hasCoda);

    // 1. Tone-Only 'z' (removes ONLY tone s/f/r/x/j, preserves ă/â/ê/ô/ơ/ư/đ)
    if (lowerCh == L'z') {
        if (m_tone != 0) {
            saveUndoSnapshot();
            m_tone = 0;
            m_lastToneKey = L'z';
            m_lastShapeKey = 0;
            return true;
        }
        if (hasVietnameseTransformation()) {
            if (hasCompoundUoOrStrokeD()) {
                m_overflowLocked = true;
            }
            if (m_lastToneKey == L'z') {
                m_telexToneEscape = true;
            }
            if (m_literalTailLen < kMaxWordTokens - 1) {
                m_literalTail[m_literalTailLen++] = ch;
                m_literalTail[m_literalTailLen] = 0;
            }
            return true;
        }
        return false;
    }

    // 2. 'd' -> 'đ'
    if (lowerCh == L'd') {
        if (vStart == -1 && m_tokenLen >= 1 && m_tokens[m_tokenLen - 1].baseLower == L'd') {
            if (m_tokens[m_tokenLen - 1].shape == 0) {
                m_tokens[m_tokenLen - 1].shape = 4;
                m_lastShapeKey = L'd';
                m_lastToneKey = 0;
                return true;
            } else if (m_tokens[m_tokenLen - 1].shape == 4 && m_lastShapeKey == L'd') {
                m_tokens[m_tokenLen - 1].shape = 0;
                m_literalLock = true;
                m_classicOrVniEscape = true;
                m_escapeLockTokenLen = m_tokenLen + 1;
                return false;
            }
        }
        if (m_tokenLen > 0 && m_tokens[0].baseLower == L'd' && m_tokens[0].shape == 0 && vStart == 1 && !hasCoda && m_tone == 0) {
            bool hasVnFeature = false;
            for (int i = vStart; i <= vEnd; ++i) {
                if (m_tokens[i].shape != 0) hasVnFeature = true;
            }
            if (!hasVnFeature && (vEnd - vStart + 1) >= 2 &&
                m_tokens[vStart].baseLower == L'u' && m_tokens[vStart + 1].baseLower == L'o') {
                hasVnFeature = true;
            }
            if (hasVnFeature) {
                m_tokens[0].shape = 4;
                m_lastShapeKey = L'd';
                return true;
            }
        }
        return false;
    }

    // 3. Circumflex 'a' -> 'â', 'e' -> 'ê', 'o' -> 'ô' AND Vowel-Shape Cancellation (088fc45)
    if (lowerCh == L'a' || lowerCh == L'e' || lowerCh == L'o') {
        // If we already cancelled a vowel shape once on the immediately preceding key, the 2nd extra press appends literally!
        if (m_shapeCancelledOnce && m_lastShapeKey == lowerCh) {
            if (hasCompoundUoOrStrokeD()) {
                m_overflowLocked = true;
            }
            if (m_literalTailLen < kMaxWordTokens - 1) {
                m_literalTail[m_literalTailLen++] = ch;
                m_literalTail[m_literalTailLen] = 0;
            }
            return true;
        }

        // Mutual exclusion reshape: 'trương' + 'o' -> 'truông' (ươ -> uô, only when not already finalized with coda + tone)
        if (lowerCh == L'o' && vStart != -1 && !(hasCoda && m_tone != 0)) {
            for (int i = vStart; i < vEnd; ++i) {
                if (m_tokens[i].baseLower == L'u' && m_tokens[i].shape == 2 &&
                    m_tokens[i + 1].baseLower == L'o' && m_tokens[i + 1].shape == 2) {
                    saveUndoSnapshot();
                    m_tokens[i].shape = 0;
                    m_tokens[i + 1].shape = 1;
                    m_lastShapeKey = L'o';
                    m_lastToneKey = 0;
                    m_shapeCancelledOnce = false;
                    m_uHornFromOwnW = false;
                    return true;
                }
            }
            // Single 'ơ' + 'o' -> 'ô' (e.g. 'cơ' + 'o' -> 'cô', 'hơn' + 'o' -> 'hôn')
            for (int i = vStart; i <= vEnd; ++i) {
                if (m_tokens[i].baseLower == L'o' && m_tokens[i].shape == 2) {
                    saveUndoSnapshot();
                    m_tokens[i].shape = 1;
                    m_lastShapeKey = L'o';
                    m_lastToneKey = 0;
                    m_shapeCancelledOnce = false;
                    return true;
                }
            }
        }

        // Mutual exclusion reshape: 'căn' + 'a' -> 'cân' (ă -> â)
        if (lowerCh == L'a' && vStart != -1 && !(hasCoda && m_tone != 0)) {
            for (int i = vStart; i <= vEnd; ++i) {
                if (m_tokens[i].baseLower == L'a' && m_tokens[i].shape == 3) {
                    saveUndoSnapshot();
                    m_tokens[i].shape = 1;
                    m_lastShapeKey = L'a';
                    m_lastToneKey = 0;
                    m_shapeCancelledOnce = false;
                    return true;
                }
            }
        }

        // Check if vowel in vStart..vEnd already has circumflex (shape == 1) for lowerCh:
        if (vStart != -1 && !(hasCoda && m_tone != 0)) {
            const bool isContiguousDouble = (m_rawLen >= 2 && toLowerAscii(m_rawWord[m_rawLen - 2]) == lowerCh);
            for (int i = vStart; i <= vEnd; ++i) {
                if (m_tokens[i].baseLower == lowerCh && m_tokens[i].shape == 1) {
                    if (!hasCoda && m_tone == 0 && i == m_tokenLen - 1 && m_lastShapeKey == lowerCh && isContiguousDouble) {
                        m_tokens[i].shape = 0;
                        m_literalLock = true;
                        m_classicOrVniEscape = true;
                        m_escapeLockTokenLen = m_tokenLen + 1;
                        return false;
                    }
                    saveUndoSnapshot();
                    m_tokens[i].shape = 0;
                    m_lastShapeKey = lowerCh;
                    m_lastToneKey = 0;
                    m_shapeCancelledOnce = true;
                    return true;
                }
            }
        }

        // Adjacent vowel doubling (Including late vowel modification after tone: 'đẻ' + 'e' -> 'để', 'đó' + 'o' -> 'đố', 'cá' + 'a' -> 'cấ')
        if (m_tokenLen > 0 && m_tokens[m_tokenLen - 1].baseLower == lowerCh && m_tokens[m_tokenLen - 1].shape == 0) {
            m_tokens[m_tokenLen - 1].shape = 1;
            m_lastShapeKey = lowerCh;
            m_lastToneKey = 0;
            m_shapeCancelledOnce = false;
            return true;
        }

        // Non-adjacent SEN Flex circumflex (e.g. 'ama' -> 'âm', 'eme' -> 'êm', 'cana' -> 'cân', 'toiso' -> 'tối')
        if (vStart != -1 && (hasCoda || vEnd > vStart)) {
            wchar_t codaStr[16]{};
            int codaLen = 0;
            for (int i = vEnd + 1; i < m_tokenLen && codaLen < 15; ++i) {
                codaStr[codaLen++] = m_tokens[i].baseLower;
            }
            if (isValidFinalCoda(codaStr, codaLen)) {
                for (int i = vStart; i <= vEnd; ++i) {
                    if (m_tokens[i].baseLower == lowerCh && m_tokens[i].shape == 0) {
                        m_tokens[i].shape = 1;
                        m_lastShapeKey = lowerCh;
                        m_lastToneKey = 0;
                        m_shapeCancelledOnce = false;
                        m_nonAdjacentCircumflex = true;
                        return true;
                    }
                }
            }
        }

        // If 'o' follows standalone 'w' + ('f') + 'u' ('trwfuong' / 'trwuong' -> 'trường' / 'trương')
        if (lowerCh == L'o' && vStart != -1 && (vEnd - vStart == 1) &&
            m_tokens[vStart].baseLower == L'u' && m_tokens[vStart].shape == 2 &&
            m_tokens[vEnd].baseLower == L'u' && m_tokens[vEnd].shape == 0 && m_uHornFromOwnW) {
            m_tokens[vEnd] = SyllableToken{ L'o', isUpper, 2 };
            m_lastShapeKey = 0;
            m_lastToneKey = 0;
            m_shapeCancelledOnce = false;
            return true;
        }
        return false;
    }

    // 4. Horn / Breve 'w' AND Vowel-Shape Cancellation (những + w -> nhũng, được + w -> đuọc, chứng + w -> chúng, trường + w -> truòng, cử + w -> củ, cửa + w -> của)
    if (lowerCh == L'w') {
        if (m_shapeCancelledOnce && m_lastShapeKey == L'w') {
            if (hasCompoundUoOrStrokeD()) {
                m_overflowLocked = true;
            }
            if (m_literalTailLen < kMaxWordTokens - 1) {
                m_literalTail[m_literalTailLen++] = ch;
                m_literalTail[m_literalTailLen] = 0;
            }
            return true;
        }

        if (vStart != -1) {
            // Absorb 2nd 'w' in 'dduwowng' ('ư' got horn from 1st 'w', then 'o' was typed and upgraded to 'ươ', then user immediately typed 'w' for 'ơ' before coda/tone)
            if (!hasCoda && m_tone == 0) {
                for (int i = vStart; i < vEnd; ++i) {
                    if (m_tokens[i].baseLower == L'u' && m_tokens[i].shape == 2 &&
                        m_tokens[i + 1].baseLower == L'o' && m_tokens[i + 1].shape == 2 &&
                        m_uHornFromOwnW && m_lastShapeKey != L'w') {
                        m_uHornFromOwnW = false;
                        m_lastShapeKey = L'w';
                        return true;
                    }
                }
            }

            bool alreadyHasHornOrBreve = false;
            for (int i = vStart; i <= vEnd; ++i) {
                if (m_tokens[i].shape == 2 || m_tokens[i].shape == 3) {
                    alreadyHasHornOrBreve = true;
                    break;
                }
            }
            // Compound 'uo' / 'ưo' / 'uơ' -> 'ươ'
            for (int i = vStart; i < vEnd; ++i) {
                if (m_tokens[i].baseLower == L'u' && m_tokens[i + 1].baseLower == L'o') {
                    if (m_tokens[i].shape != 2 || m_tokens[i + 1].shape != 2) {
                        m_tokens[i].shape = 2;
                        m_tokens[i + 1].shape = 2;
                        m_lastShapeKey = L'w';
                        m_lastToneKey = 0;
                        m_shapeCancelledOnce = false;
                        m_uHornFromOwnW = false;
                        return true;
                    }
                }
            }

            // Mutual exclusion reshape: 'cân' + 'w' -> 'căn', 'côn' + 'w' -> 'cơn'
            if (!(hasCoda && m_tone != 0)) {
                for (int i = vStart; i <= vEnd; ++i) {
                    if (m_tokens[i].baseLower == L'a' && m_tokens[i].shape == 1) {
                        saveUndoSnapshot();
                        m_tokens[i].shape = 3;
                        m_lastShapeKey = L'w';
                        m_lastToneKey = 0;
                        m_shapeCancelledOnce = false;
                        return true;
                    }
                    if (m_tokens[i].baseLower == L'o' && m_tokens[i].shape == 1) {
                        saveUndoSnapshot();
                        m_tokens[i].shape = 2;
                        m_lastShapeKey = L'w';
                        m_lastToneKey = 0;
                        m_shapeCancelledOnce = false;
                        return true;
                    }
                }
            }

            if (alreadyHasHornOrBreve) {
                if (hasCoda && m_tone != 0) {
                    return false;
                }
                // Immediate double 'ww' at word start ('ww' -> 'w', 'wwus' -> 'wus')
                if (m_rawLen == 2 && (m_rawWord[0] == L'w' || m_rawWord[0] == L'W')) {
                    m_tokenLen = 0;
                    m_literalLock = true;
                    m_classicOrVniEscape = true;
                    m_escapeLockTokenLen = 1;
                    return false;
                }
                // Classic open untoned single or compound vowel ('oww' -> 'ow', 'tuoww' -> 'tuow', 'muaww' -> 'muaw', 'cuuww' -> 'cuuw', 'hoaww' -> 'hoaw', 'huouww' -> 'huouw')
                const bool isContiguousDoubleW = (m_rawLen >= 2 && toLowerAscii(m_rawWord[m_rawLen - 2]) == L'w');
                if (!hasCoda && m_tone == 0 && m_lastShapeKey == L'w' && isContiguousDoubleW) {
                    for (int i = vStart; i <= vEnd; ++i) {
                        if (m_tokens[i].shape == 2 || m_tokens[i].shape == 3) {
                            m_tokens[i].shape = 0;
                        }
                    }
                    m_literalLock = true;
                    m_classicOrVniEscape = true;
                    m_escapeLockTokenLen = m_tokenLen + 1;
                    m_uHornFromOwnW = false;
                    return false;
                }
                // Strip horn/breve while preserving tone and coda when not finalized with coda + tone
                saveUndoSnapshot();
                for (int i = vStart; i <= vEnd; ++i) {
                    if (m_tokens[i].shape == 2 || m_tokens[i].shape == 3) {
                        m_tokens[i].shape = 0;
                    }
                }
                m_lastShapeKey = L'w';
                m_lastToneKey = 0;
                m_shapeCancelledOnce = true;
                m_uHornFromOwnW = false;
                return true;
            }

            // 'oa' + 'w' -> 'oă'
            for (int i = vStart; i < vEnd; ++i) {
                if (m_tokens[i].baseLower == L'o' && m_tokens[i + 1].baseLower == L'a' && m_tokens[i + 1].shape == 0) {
                    m_tokens[i + 1].shape = 3;
                    m_lastShapeKey = L'w';
                    m_lastToneKey = 0;
                    m_shapeCancelledOnce = false;
                    return true;
                }
            }

            // 'uu' + 'w' -> 'ưu' (e.g. 'cuuws' -> 'cứu', 'huuw' -> 'hưu', 'luuw' -> 'lưu')
            for (int i = vStart; i < vEnd; ++i) {
                if (m_tokens[i].baseLower == L'u' && m_tokens[i + 1].baseLower == L'u' && m_tokens[i].shape == 0) {
                    m_tokens[i].shape = 2;
                    m_lastShapeKey = L'w';
                    m_lastToneKey = 0;
                    m_shapeCancelledOnce = false;
                    m_uHornFromOwnW = true;
                    return true;
                }
            }

            // Open 'ua' + 'w' -> 'ưa' (e.g. 'muaw' -> 'mưa', 'cuaw' -> 'cưa', 'uaw' -> 'ưa'; standalone 'ưa' + coda reshapes to 'uă' + coda in feedChar)
            if (!hasCoda) {
                for (int i = vStart; i < vEnd; ++i) {
                    if (m_tokens[i].baseLower == L'u' && m_tokens[i + 1].baseLower == L'a' &&
                        m_tokens[i].shape == 0 && m_tokens[i + 1].shape == 0) {
                        m_tokens[i].shape = 2;
                        m_lastShapeKey = L'w';
                        m_lastToneKey = 0;
                        m_shapeCancelledOnce = false;
                        m_uHornFromOwnW = true;
                        return true;
                    }
                }
            }

            // Single 'a' -> 'ă', 'o' -> 'ơ', 'u' -> 'ư'
            for (int i = vEnd; i >= vStart; --i) {
                if (m_tokens[i].baseLower == L'a' && m_tokens[i].shape == 0) {
                    m_tokens[i].shape = 3;
                    m_lastShapeKey = L'w';
                    m_lastToneKey = 0;
                    m_shapeCancelledOnce = false;
                    return true;
                }
                if (m_tokens[i].baseLower == L'o' && m_tokens[i].shape == 0) {
                    m_tokens[i].shape = 2;
                    m_lastShapeKey = L'w';
                    m_lastToneKey = 0;
                    m_shapeCancelledOnce = false;
                    return true;
                }
                if (m_tokens[i].baseLower == L'u' && m_tokens[i].shape == 0) {
                    m_tokens[i].shape = 2;
                    m_lastShapeKey = L'w';
                    m_lastToneKey = 0;
                    m_shapeCancelledOnce = false;
                    m_uHornFromOwnW = true;
                    return true;
                }
            }
            return false;
        } else {
            // No vowel yet: standalone 'w' -> 'ư' if at start or after valid Vietnamese initial
            wchar_t initStr[16]{};
            int initLen = 0;
            for (int i = 0; i < m_tokenLen && initLen < 15; ++i) {
                initStr[initLen++] = m_tokens[i].baseLower;
            }
            bool hasStrokeD = (m_tokenLen == 1 && m_tokens[0].baseLower == L'd' && m_tokens[0].shape == 4);
            if (!hasStrokeD && isValidInitialOnset(initStr, initLen, false) && m_tokenLen < kMaxWordTokens) {
                m_tokens[m_tokenLen++] = SyllableToken{ L'u', isUpper, 2 };
                m_lastShapeKey = L'w';
                m_lastToneKey = 0;
                m_shapeCancelledOnce = false;
                m_uHornFromOwnW = true;
                return true;
            }
            return false;
        }
    }

    // 5. Tone keys: s (1), f (2), r (3), x (4), j (5)
    int targetTone = 0;
    switch (lowerCh) {
    case L's': targetTone = 1; break;
    case L'f': targetTone = 2; break;
    case L'r': targetTone = 3; break;
    case L'x': targetTone = 4; break;
    case L'j': targetTone = 5; break;
    default: break;
    }

    if (targetTone != 0 && vStart != -1) {
        wchar_t codaStr[16]{};
        int codaLen = 0;
        for (int i = vEnd + 1; i < m_tokenLen; ++i) {
            if (isAsciiBaseVowel(m_tokens[i].baseLower)) return false;
            if (codaLen < 15) codaStr[codaLen++] = m_tokens[i].baseLower;
        }
        if (!isValidFinalCoda(codaStr, codaLen)) {
            return false;
        }
        if (isStopCoda(codaStr, codaLen) && targetTone != 1 && targetTone != 5) {
            return false;
        }

        bool hasConsonantOnsetOrShape = (vStart > 0);
        if (!hasConsonantOnsetOrShape) {
            for (int i = 0; i < m_tokenLen; ++i) {
                if (m_tokens[i].shape != 0) {
                    hasConsonantOnsetOrShape = true;
                    break;
                }
            }
        }
        const bool validStemBeforeCancel = isValidVietnameseSyllable();
        const bool canCancelTone = (m_tone == targetTone) &&
                                   (m_lastToneKey == lowerCh || (hasConsonantOnsetOrShape && validStemBeforeCancel));
        if (m_tone == targetTone && !canCancelTone) {
            return false;
        }
        if (canCancelTone) {
            saveUndoSnapshot();
            m_tone = 0;
            if (validStemBeforeCancel && rawWordStartsNonW()) {
                m_telexToneEscape = true;
            }
            bool hasModifiedShape = m_shapeCancelledOnce;
            for (int i = 0; i < m_tokenLen; ++i) {
                if (m_tokens[i].shape != 0) {
                    hasModifiedShape = true;
                    break;
                }
            }
            m_toneCancelledPlain = !hasModifiedShape;
            if (m_literalTailLen < kMaxWordTokens - 1) {
                m_literalTail[m_literalTailLen++] = ch;
                m_literalTail[m_literalTailLen] = 0;
            }
            return true;
        }

        m_tone = targetTone;
        m_lastToneKey = lowerCh;
        m_lastShapeKey = 0;
        m_shapeCancelledOnce = false;
        return true;
    }

    // SEN Flex pre-vowel tone (e.g. "tseet" -> "tết"): tone key typed right after initial consonant before vowel
    if (m_grammarProfile == 1 && targetTone != 0 && lowerCh != L'r' && vStart == -1 && m_tokenLen > 0 && m_tone == 0) {
        wchar_t initStr[16]{};
        int initLen = 0;
        for (int i = 0; i < m_tokenLen && initLen < 15; ++i) {
            initStr[initLen++] = m_tokens[i].baseLower;
        }
        bool hasStrokeD = (m_tokenLen == 1 && m_tokens[0].baseLower == L'd' && m_tokens[0].shape == 4);
        if (!hasStrokeD && isValidInitialOnset(initStr, initLen, false) && !(initLen == 1 && initStr[0] == L'p' && lowerCh == L's')) {
            m_tone = targetTone;
            m_lastToneKey = lowerCh;
            m_preVowelTone = true;
            return true;
        }
    }

    // Quick Telex onset shortcuts (cc=ch, gg=gi, qq=qu)
    if (m_quickTelex && vStart == -1 && m_tokenLen == 1 && m_tokens[0].shape == 0 && m_tokens[0].baseLower == lowerCh) {
        if (lowerCh == L'c' && m_tokenLen < kMaxWordTokens) {
            m_tokens[m_tokenLen++] = SyllableToken{ L'h', false, 0 };
            return true;
        }
        if (lowerCh == L'g' && m_tokenLen < kMaxWordTokens) {
            m_tokens[m_tokenLen++] = SyllableToken{ L'i', false, 0 };
            return true;
        }
        if (lowerCh == L'q' && m_tokenLen < kMaxWordTokens) {
            m_tokens[m_tokenLen++] = SyllableToken{ L'u', false, 0 };
            return true;
        }
    }

    return false;
}

bool NativeEngineState::applyVniCharacter(wchar_t ch) {
    if (m_literalLock) return false;
    if (m_literalTailLen > 0) {
        if (m_literalTailLen < kMaxWordTokens - 1) {
            m_literalTail[m_literalTailLen++] = ch;
            m_literalTail[m_literalTailLen] = 0;
        }
        return true;
    }
    if (ch < L'0' || ch > L'9') return false;

    int vStart = -1, vEnd = -1;
    bool hasCoda = false;
    findVowelCluster(vStart, vEnd, hasCoda);

    if (ch == L'0') {
        if (m_tone != 0) {
            saveUndoSnapshot();
            m_tone = 0;
            m_lastToneKey = 0;
            return true;
        }
        return false;
    }

    if (ch == L'9') {
        if (m_tokenLen > 0 && m_tokens[0].baseLower == L'd') {
            if (m_tokens[0].shape == 0) {
                m_tokens[0].shape = 4;
                m_lastShapeKey = L'9';
                return true;
            } else if (m_tokens[0].shape == 4 && m_lastShapeKey == L'9') {
                m_tokens[0].shape = 0;
                m_lastShapeKey = L'9';
                m_shapeCancelledOnce = true;
                m_classicOrVniEscape = true;
                if (m_literalTailLen < kMaxWordTokens - 1) {
                    m_literalTail[m_literalTailLen++] = ch;
                    m_literalTail[m_literalTailLen] = 0;
                }
                return true;
            }
        }
        return false;
    }

    if (vStart == -1) return false;

    if (m_shapeCancelledOnce && m_lastShapeKey == ch) {
        m_classicOrVniEscape = true;
        if (m_literalTailLen < kMaxWordTokens - 1) {
            m_literalTail[m_literalTailLen++] = ch;
            m_literalTail[m_literalTailLen] = 0;
        }
        return true;
    }

    if (ch == L'6') {
        // Mutual exclusion reshape: 'trương' + '6' -> 'truông', 'cơn' + '6' -> 'côn', 'căn' + '6' -> 'cân'
        if (!(hasCoda && m_tone != 0)) {
            for (int i = vStart; i < vEnd; ++i) {
                if (m_tokens[i].baseLower == L'u' && m_tokens[i].shape == 2 &&
                    m_tokens[i + 1].baseLower == L'o' && m_tokens[i + 1].shape == 2) {
                    saveUndoSnapshot();
                    m_tokens[i].shape = 0;
                    m_tokens[i + 1].shape = 1;
                    m_lastShapeKey = L'6';
                    m_shapeCancelledOnce = false;
                    return true;
                }
            }
            for (int i = vStart; i <= vEnd; ++i) {
                if ((m_tokens[i].baseLower == L'o' && m_tokens[i].shape == 2) ||
                    (m_tokens[i].baseLower == L'a' && m_tokens[i].shape == 3)) {
                    saveUndoSnapshot();
                    m_tokens[i].shape = 1;
                    m_lastShapeKey = L'6';
                    m_shapeCancelledOnce = false;
                    return true;
                }
            }
        }
        // Vowel-shape cancellation: 'không' + '6' -> 'khong6', 'quyết' + '6' -> 'quyét6'
        for (int i = vStart; i <= vEnd; ++i) {
            wchar_t b = m_tokens[i].baseLower;
            if ((b == L'a' || b == L'e' || b == L'o') && m_tokens[i].shape == 1) {
                saveUndoSnapshot();
                m_tokens[i].shape = 0;
                m_lastShapeKey = L'6';
                m_shapeCancelledOnce = true;
                m_classicOrVniEscape = true;
                if (m_literalTailLen < kMaxWordTokens - 1) {
                    m_literalTail[m_literalTailLen++] = ch;
                    m_literalTail[m_literalTailLen] = 0;
                }
                return true;
            }
        }
        for (int i = vEnd; i >= vStart; --i) {
            wchar_t b = m_tokens[i].baseLower;
            if ((b == L'a' || b == L'e' || b == L'o') && m_tokens[i].shape != 1) {
                m_tokens[i].shape = 1;
                m_lastShapeKey = L'6';
                m_shapeCancelledOnce = false;
                return true;
            }
        }
        return false;
    }

    if (ch == L'7') {
        for (int i = vStart; i < vEnd; ++i) {
            if (m_tokens[i].baseLower == L'u' && m_tokens[i + 1].baseLower == L'o') {
                if (m_tokens[i].shape != 2 || m_tokens[i + 1].shape != 2) {
                    m_tokens[i].shape = 2;
                    m_tokens[i + 1].shape = 2;
                    m_lastShapeKey = L'7';
                    m_shapeCancelledOnce = false;
                    return true;
                } else {
                    // Cancel 'ươ' + '7' -> 'uo7' (e.g. 'trường' + '7' -> 'truòng7')
                    saveUndoSnapshot();
                    m_tokens[i].shape = 0;
                    m_tokens[i + 1].shape = 0;
                    m_lastShapeKey = L'7';
                    m_shapeCancelledOnce = true;
                    m_classicOrVniEscape = true;
                    if (m_literalTailLen < kMaxWordTokens - 1) {
                        m_literalTail[m_literalTailLen++] = ch;
                        m_literalTail[m_literalTailLen] = 0;
                    }
                    return true;
                }
            }
        }
        for (int i = vStart; i <= vEnd; ++i) {
            wchar_t b = m_tokens[i].baseLower;
            if ((b == L'o' || b == L'u') && m_tokens[i].shape == 2) {
                saveUndoSnapshot();
                m_tokens[i].shape = 0;
                m_lastShapeKey = L'7';
                m_shapeCancelledOnce = true;
                m_classicOrVniEscape = true;
                if (m_literalTailLen < kMaxWordTokens - 1) {
                    m_literalTail[m_literalTailLen++] = ch;
                    m_literalTail[m_literalTailLen] = 0;
                }
                return true;
            }
        }
        for (int i = vEnd; i >= vStart; --i) {
            wchar_t b = m_tokens[i].baseLower;
            if ((b == L'o' || b == L'u') && m_tokens[i].shape != 2) {
                m_tokens[i].shape = 2;
                m_lastShapeKey = L'7';
                m_shapeCancelledOnce = false;
                return true;
            }
        }
        return false;
    }

    if (ch == L'8') {
        for (int i = vStart; i <= vEnd; ++i) {
            if (m_tokens[i].baseLower == L'a' && m_tokens[i].shape == 3) {
                saveUndoSnapshot();
                m_tokens[i].shape = 0;
                m_lastShapeKey = L'8';
                m_shapeCancelledOnce = true;
                m_classicOrVniEscape = true;
                if (m_literalTailLen < kMaxWordTokens - 1) {
                    m_literalTail[m_literalTailLen++] = ch;
                    m_literalTail[m_literalTailLen] = 0;
                }
                return true;
            }
        }
        for (int i = vEnd; i >= vStart; --i) {
            if (m_tokens[i].baseLower == L'a' && m_tokens[i].shape != 3) {
                m_tokens[i].shape = 3;
                m_lastShapeKey = L'8';
                m_shapeCancelledOnce = false;
                return true;
            }
        }
        return false;
    }

    if (ch >= L'1' && ch <= L'5') {
        int targetTone = ch - L'0';
        wchar_t codaStr[16]{};
        int codaLen = 0;
        for (int i = vEnd + 1; i < m_tokenLen; ++i) {
            if (isAsciiBaseVowel(m_tokens[i].baseLower)) return false;
            if (codaLen < 15) codaStr[codaLen++] = m_tokens[i].baseLower;
        }
        if (!isValidFinalCoda(codaStr, codaLen)) {
            return false;
        }
        if (isStopCoda(codaStr, codaLen) && targetTone != 1 && targetTone != 5) {
            return false;
        }
        if (m_tone == targetTone && m_lastToneKey == ch) {
            saveUndoSnapshot();
            m_tone = 0;
            m_lastToneKey = 0;
            m_classicOrVniEscape = true;
            if (m_literalTailLen < kMaxWordTokens - 1) {
                m_literalTail[m_literalTailLen++] = ch;
                m_literalTail[m_literalTailLen] = 0;
            }
            return true;
        }
        m_tone = targetTone;
        m_lastToneKey = ch;
        return true;
    }

    return false;
}

int32_t NativeEngineState::emitIncrementalReplacement(const wchar_t *priorDisplayed, int priorLen, const wchar_t *newDisplayed, int newLen) {
    int commonPrefix = 0;
    const int minLen = (priorLen < newLen) ? priorLen : newLen;
    while (commonPrefix < minLen && priorDisplayed[commonPrefix] == newDisplayed[commonPrefix]) {
        ++commonPrefix;
    }

    m_lastBackspaces = static_cast<int32_t>(priorLen - commonPrefix);
    encodeWideToUtf8(newDisplayed + commonPrefix, newLen - commonPrefix, m_lastTextUtf8, kMaxUtf8Bytes);
    return static_cast<int32_t>(Action::Replace);
}

int32_t NativeEngineState::feedChar(uint32_t codepoint) {
    if (m_armedAfterSpace) {
        m_armedAfterSpace = false;
        m_hasUndoSnapshot = false;
    }

    if (isWordBoundaryDelimiter(codepoint)) {
        m_afterDigit = false;
        const bool wasInLeadingSlash = m_precededByLeadingSlash;
        m_pendingBoundaryCp = codepoint;
        if (m_displayedLen > 0) {
            int32_t act = commitWord();
            m_pendingBoundaryCp = 0;
            m_precededByLeadingSlash = (codepoint == '/' && wasInLeadingSlash);
            if (codepoint == '/' || codepoint == '\\' || codepoint == '_') {
                m_precededByTechDelimiter = true;
            } else if (codepoint == ' ' || codepoint == '\t' || codepoint == '\n' || codepoint == '\r') {
                m_precededByTechDelimiter = false;
            }
            return act;
        }
        m_pendingBoundaryCp = 0;
        m_prevCollisionDisplayedLen = 0;
        m_prevCollisionRawLen = 0;
        m_precededByLeadingSlash = (codepoint == '/');
        if (codepoint == '/' || codepoint == '\\' || codepoint == '_') {
            m_precededByTechDelimiter = true;
        } else if (codepoint == ' ' || codepoint == '\t' || codepoint == '\n' || codepoint == '\r') {
            m_precededByTechDelimiter = false;
        }
        m_lastBackspaces = 0;
        m_lastTextUtf8[0] = '\0';
        return static_cast<int32_t>(Action::PassThrough);
    }

    const bool isVniDigitCandidate = (m_inputMethod == InputMethod::VNI && isAsciiDigit(codepoint) && m_tokenLen > 0 && !m_literalLock);
    if (!isAsciiAlpha(codepoint) && !isVniDigitCandidate) {
        if (isComposing()) {
            clearWordState();
        }
        m_afterDigit = isAsciiDigit(codepoint);
        m_precededByLeadingSlash = false;
        m_lastBackspaces = 0;
        m_lastTextUtf8[0] = '\0';
        return static_cast<int32_t>(Action::PassThrough);
    }

    if (m_tokenLen == 0 && m_afterDigit) {
        m_literalLock = true;
    }

    wchar_t priorDisplayed[kMaxWordTokens]{};
    const int priorLen = m_displayedLen;
    for (int i = 0; i < priorLen; ++i) priorDisplayed[i] = m_displayed[i];

    const wchar_t ch = static_cast<wchar_t>(codepoint);
    const wchar_t lowerCh = toLowerAscii(ch);
    const bool isUpper = (ch >= L'A' && ch <= L'Z');

    // Prevent silent character truncation when a continuous token exceeds kMaxWordTokens - 1 (e.g. 80 consecutive 'b's)
    if (m_rawLen >= kMaxWordTokens - 1 || m_tokenLen >= kMaxWordTokens - 1) {
        clearWordState();
        m_lastBackspaces = 0;
        m_lastTextUtf8[0] = '\0';
        return static_cast<int32_t>(Action::PassThrough);
    }

    if (m_rawLen < kMaxWordTokens - 1) {
        m_rawWord[m_rawLen++] = ch;
        m_rawWord[m_rawLen] = 0;
    }

    bool consumedAsModifier = false;
    if (!m_literalLock && m_literalTailLen > 0 && m_inputMethod == InputMethod::VNI) {
        if (m_literalTailLen < kMaxWordTokens - 1) {
            m_literalTail[m_literalTailLen++] = ch;
            m_literalTail[m_literalTailLen] = 0;
        }
        consumedAsModifier = true;
    } else if (m_inputMethod == InputMethod::Telex && isAsciiAlpha(codepoint)) {
        consumedAsModifier = applyTelexCharacter(ch, lowerCh, isUpper);
    } else if (m_inputMethod == InputMethod::VNI && isAsciiDigit(codepoint)) {
        consumedAsModifier = applyVniCharacter(ch);
    }

    if (!consumedAsModifier) {
        // Post-Coda / Post-Syllable Overflow Lock (parity with macOS shouldLockPostCodaOverflow):
        // If m_tokens has already formed a valid Vietnamese syllable with Vietnamese-specific shapes (đ, ă, â, ơ, ư),
        // toned ê/ô, or a cancelled vowel shape, and appending lowerCh to m_tokens would violate Vietnamese phonotactics,
        // lock the syllable stem and append ch to m_literalTail so the Vietnamese syllable is never reverted to raw ASCII!
        bool lockOverflowToTail = false;
        if (m_tokenLen >= 2 && isValidVietnameseSyllable()) {
            int vStartNow = -1, vEndNow = -1;
            bool hasCodaNow = false;
            findVowelCluster(vStartNow, vEndNow, hasCodaNow);

            bool hasVnSpecific = m_shapeCancelledOnce || m_hasUndoSnapshot;
            for (int i = 0; i < m_tokenLen; ++i) {
                if (m_tokens[i].shape == 2 || m_tokens[i].shape == 3 || m_tokens[i].shape == 4 ||
                    (m_tokens[i].shape == 1 && m_tone != 0)) {
                    hasVnSpecific = true;
                    break;
                }
            }
            const bool isTonedOpenSameVowelRepeat =
                !hasCodaNow &&
                m_tone != 0 &&
                vStartNow > 0 &&
                vEndNow == m_tokenLen - 1 &&
                lowerCh == m_tokens[vEndNow].baseLower &&
                rawWordStartsNonW();
            if (!hasCodaNow && isAsciiBaseVowel(lowerCh) && !isTonedOpenSameVowelRepeat) {
                hasVnSpecific = false;
            }
            if (isTonedOpenSameVowelRepeat) {
                hasVnSpecific = true;
            }
            if (!hasCodaNow && vStartNow == 0 && vEndNow == 1 && rawWordStartsNonW() &&
                m_tokens[0].baseLower == L'u' && m_tokens[0].shape == 2 &&
                m_tokens[1].baseLower == L'a' && m_tokens[1].shape == 0 &&
                (lowerCh == L'c' || lowerCh == L'm' || lowerCh == L'n' || lowerCh == L'p' || lowerCh == L't')) {
                hasVnSpecific = false;
            }
            if (hasVnSpecific && m_tokenLen < kMaxWordTokens) {
                m_tokens[m_tokenLen++] = SyllableToken{ lowerCh, isUpper, 0 };
                int vS = -1, vE = -1;
                bool hC = false;
                findVowelCluster(vS, vE, hC);
                bool validExtended = isValidVietnameseSyllable();
                --m_tokenLen;
                if (!validExtended) {
                    lockOverflowToTail = true;
                }
            }
        }

        if (lockOverflowToTail) {
            if (hasCompoundUoOrStrokeD()) {
                m_overflowLocked = true;
            }
            if (m_literalTailLen < kMaxWordTokens - 1) {
                m_literalTail[m_literalTailLen++] = ch;
                m_literalTail[m_literalTailLen] = 0;
            }
        } else {
            if (m_tokenLen < kMaxWordTokens) {
                m_tokens[m_tokenLen++] = SyllableToken{ lowerCh, isUpper, 0 };
            }
            m_lastToneKey = 0;
            m_lastShapeKey = 0;
            m_shapeCancelledOnce = false;
            m_hasUndoSnapshot = false;

            int vStart = -1, vEnd = -1;
            bool hasCoda = false;
            findVowelCluster(vStart, vEnd, hasCoda);
            if (vStart != -1 && hasCoda) {
                for (int i = vStart; i < vEnd; ++i) {
                    if (m_tokens[i].baseLower == L'u' && m_tokens[i + 1].baseLower == L'o' &&
                        (m_tokens[i].shape == 2 || m_tokens[i + 1].shape == 2)) {
                        m_tokens[i].shape = 2;
                        m_tokens[i + 1].shape = 2;
                    }
                }
                if (vStart == 0 && vEnd == 1 && rawWordStartsNonW() &&
                    m_tokens[0].baseLower == L'u' && m_tokens[0].shape == 2 &&
                    m_tokens[1].baseLower == L'a' && m_tokens[1].shape == 0) {
                    m_tokens[0].shape = 0;
                    m_tokens[1].shape = 3;
                }
            }
        }
    }

    m_displayedLen = composeOutputWord(m_displayed, kMaxWordTokens);
    return emitIncrementalReplacement(priorDisplayed, priorLen, m_displayed, m_displayedLen);
}

int32_t NativeEngineState::feedBackspace() {
    if (!isComposing()) {
        m_afterDigit = false;
        m_precededByLeadingSlash = false;
        m_lastBackspaces = 0;
        m_lastTextUtf8[0] = '\0';
        return static_cast<int32_t>(Action::PassThrough);
    }

    // Re-arm committed Vietnamese word when user presses Backspace immediately after Space ("gõ xong + Space + Backspace rồi thêm")
    if (m_armedAfterSpace && m_displayedLen == 0) {
        m_armedAfterSpace = false;
        m_hasUndoSnapshot = false;
        m_shapeCancelledOnce = false;
        m_tokenLen = m_undoTokenLen;
        for (int i = 0; i < m_tokenLen; ++i) {
            m_tokens[i] = m_undoTokens[i];
        }
        m_tone = m_undoTone;
        m_lastToneKey = m_undoLastToneKey;
        m_lastShapeKey = m_undoLastShapeKey;
        m_rawLen = m_undoRawLen;
        for (int i = 0; i < m_rawLen; ++i) {
            m_rawWord[i] = m_undoRawWord[i];
        }
        m_rawWord[m_rawLen] = 0;
        m_literalTailLen = m_undoLiteralTailLen;
        for (int i = 0; i < m_literalTailLen; ++i) {
            m_literalTail[i] = m_undoLiteralTail[i];
        }
        m_literalTail[m_literalTailLen] = 0;
        m_literalLock = m_undoLiteralLock;
        m_escapeLockTokenLen = m_undoEscapeLockTokenLen;
        m_classicOrVniEscape = m_undoClassicOrVniEscape;
        m_telexToneEscape = m_undoTelexToneEscape;
        m_overflowLocked = m_undoOverflowLocked;
        m_displayedLen = composeOutputWord(m_displayed, kMaxWordTokens);
        m_lastBackspaces = 1;
        m_lastTextUtf8[0] = '\0';
        return static_cast<int32_t>(Action::Replace);
    }

    wchar_t priorDisplayed[kMaxWordTokens]{};
    const int priorLen = m_displayedLen;
    for (int i = 0; i < priorLen; ++i) priorDisplayed[i] = m_displayed[i];

    // 0. If there is a literal tail (e.g. 'rônz' -> 'rôn', 'nhũngw' -> 'nhũng'), pop from literalTail first
    if (m_literalTailLen > 0) {
        --m_literalTailLen;
        m_literalTail[m_literalTailLen] = 0;
        if (m_rawLen > 0) {
            --m_rawLen;
            m_rawWord[m_rawLen] = 0;
        }
        if (m_literalTailLen == 0) {
            m_telexToneEscape = false;
            m_overflowLocked = false;
            if (m_inputMethod == InputMethod::VNI) {
                m_classicOrVniEscape = false;
            }
            if (!m_shapeCancelledOnce && m_lastToneKey != L'z') {
                m_hasUndoSnapshot = false;
            }
            if (!shouldRestoreRawEnglish()) {
                m_displayedLen = composeOutputWord(m_displayed, kMaxWordTokens);
                m_rawLen = m_displayedLen;
                for (int i = 0; i <= m_displayedLen; ++i) m_rawWord[i] = m_displayed[i];
                return emitIncrementalReplacement(priorDisplayed, priorLen, m_displayed, m_displayedLen);
            }
        }
        m_displayedLen = composeOutputWord(m_displayed, kMaxWordTokens);
        return emitIncrementalReplacement(priorDisplayed, priorLen, m_displayed, m_displayedLen);
    }

    // 0b. If last action was a vowel-shape cancellation or 'z' tone clear, restore the saved undo snapshot
    if (m_hasUndoSnapshot) {
        m_hasUndoSnapshot = false;
        m_shapeCancelledOnce = false;
        m_tokenLen = m_undoTokenLen;
        for (int i = 0; i < m_tokenLen; ++i) {
            m_tokens[i] = m_undoTokens[i];
        }
        m_tone = m_undoTone;
        m_rawLen = m_undoRawLen;
        for (int i = 0; i < m_rawLen; ++i) {
            m_rawWord[i] = m_undoRawWord[i];
        }
        m_rawWord[m_rawLen] = 0;
        m_displayedLen = composeOutputWord(m_displayed, kMaxWordTokens);
        return emitIncrementalReplacement(priorDisplayed, priorLen, m_displayed, m_displayedLen);
    }

    // If currently displaying raw fallback or literal lock, delete last character directly
    bool isRawFallback = (priorLen == m_rawLen);
    if (isRawFallback) {
        for (int i = 0; i < priorLen; ++i) {
            if (priorDisplayed[i] != m_rawWord[i]) {
                isRawFallback = false;
                break;
            }
        }
    }
    if (m_literalLock || isRawFallback) {
        if (m_rawLen > 0) {
            --m_rawLen;
            m_rawWord[m_rawLen] = 0;
        }
        if (m_tokenLen > 0) {
            --m_tokenLen;
        }
        if (m_tokenLen == 0) {
            clearWordState();
            return static_cast<int32_t>(Action::Reset);
        }
        if (m_literalLock && m_escapeLockTokenLen > 0 && m_tokenLen < m_escapeLockTokenLen) {
            m_literalLock = false;
            m_classicOrVniEscape = false;
            m_escapeLockTokenLen = 0;
            m_displayedLen = composeOutputWord(m_displayed, kMaxWordTokens);
            m_rawLen = m_displayedLen;
            for (int i = 0; i <= m_displayedLen; ++i) m_rawWord[i] = m_displayed[i];
            return emitIncrementalReplacement(priorDisplayed, priorLen, m_displayed, m_displayedLen);
        }
        m_displayedLen = composeOutputWord(m_displayed, kMaxWordTokens);
        return emitIncrementalReplacement(priorDisplayed, priorLen, m_displayed, m_displayedLen);
    }

    // Apple-style semantic Backspace:
    // 1. First remove active tone
    if (m_tone != 0) {
        m_tone = 0;
        m_lastToneKey = 0;
        m_displayedLen = composeOutputWord(m_displayed, kMaxWordTokens);
        m_rawLen = m_displayedLen;
        for (int i = 0; i <= m_displayedLen; ++i) m_rawWord[i] = m_displayed[i];
        return emitIncrementalReplacement(priorDisplayed, priorLen, m_displayed, m_displayedLen);
    }

    // 2. Next remove vowel diacritic shapes (ă/â/ê/ô/ơ/ư -> a/e/o/u)
    bool hadVowelShape = false;
    for (int i = 0; i < m_tokenLen; ++i) {
        if (m_tokens[i].baseLower != L'd' && m_tokens[i].shape != 0) {
            m_tokens[i].shape = 0;
            hadVowelShape = true;
        }
    }
    if (hadVowelShape) {
        m_lastShapeKey = 0;
        m_uHornFromOwnW = false;
        m_displayedLen = composeOutputWord(m_displayed, kMaxWordTokens);
        m_rawLen = m_displayedLen;
        for (int i = 0; i <= m_displayedLen; ++i) m_rawWord[i] = m_displayed[i];
        return emitIncrementalReplacement(priorDisplayed, priorLen, m_displayed, m_displayedLen);
    }

    // 3. If more than 1 token remains, pop the last token
    if (m_tokenLen > 1) {
        --m_tokenLen;
        m_displayedLen = composeOutputWord(m_displayed, kMaxWordTokens);
        m_rawLen = m_displayedLen;
        for (int i = 0; i <= m_displayedLen; ++i) m_rawWord[i] = m_displayed[i];
        return emitIncrementalReplacement(priorDisplayed, priorLen, m_displayed, m_displayedLen);
    }

    // 4. Single token 'đ' -> 'd'
    if (m_tokenLen == 1 && m_tokens[0].baseLower == L'd' && m_tokens[0].shape == 4) {
        m_tokens[0].shape = 0;
        m_displayedLen = composeOutputWord(m_displayed, kMaxWordTokens);
        m_rawLen = m_displayedLen;
        for (int i = 0; i <= m_displayedLen; ++i) m_rawWord[i] = m_displayed[i];
        return emitIncrementalReplacement(priorDisplayed, priorLen, m_displayed, m_displayedLen);
    }

    // 5. Last single character deleted -> empty
    clearWordState();
    return static_cast<int32_t>(Action::Reset);
}

int32_t NativeEngineState::commitWord() {
    if (m_displayedLen == 0) {
        m_armedAfterSpace = false;
        m_hasUndoSnapshot = false;
        m_lastBackspaces = 0;
        m_lastTextUtf8[0] = '\0';
        return static_cast<int32_t>(Action::PassThrough);
    }

    wchar_t rawLower[kMaxWordTokens]{};
    for (int i = 0; i < m_rawLen; ++i) rawLower[i] = toLowerAscii(m_rawWord[i]);

    const bool isPreservedEscape =
        !shouldRestoreRawEnglish() && (m_classicOrVniEscape || m_telexToneEscape || m_overflowLocked || isOpenSameVowelExtension());
    const bool canArmPostCommit =
        (!m_literalLock && m_literalTailLen == 0 && !shouldRestoreRawEnglish() && isValidVietnameseSyllable()) ||
        (m_pendingBoundaryCp == ' ' && isPreservedEscape);
    SyllableToken savedTokens[kMaxWordTokens]{};
    int savedTokenLen = m_tokenLen;
    int savedTone = m_tone;
    wchar_t savedLastToneKey = m_lastToneKey;
    wchar_t savedLastShapeKey = m_lastShapeKey;
    wchar_t savedRaw[kMaxWordTokens]{};
    int savedRawLen = m_rawLen;
    wchar_t savedLiteralTail[kMaxWordTokens]{};
    int savedLiteralTailLen = m_literalTailLen;
    bool savedLiteralLock = m_literalLock;
    int savedEscapeLockTokenLen = m_escapeLockTokenLen;
    bool savedClassicOrVniEscape = m_classicOrVniEscape;
    bool savedTelexToneEscape = m_telexToneEscape;
    bool savedOverflowLocked = m_overflowLocked;
    if (canArmPostCommit) {
        for (int i = 0; i < savedTokenLen; ++i) savedTokens[i] = m_tokens[i];
        for (int i = 0; i < savedRawLen; ++i) savedRaw[i] = m_rawWord[i];
        savedRaw[savedRawLen] = 0;
        for (int i = 0; i < savedLiteralTailLen; ++i) savedLiteralTail[i] = m_literalTail[i];
        savedLiteralTail[savedLiteralTailLen] = 0;
    }

    if (m_smartBilingual && m_prevCollisionRawLen > 0 && m_prevCollisionDisplayedLen > 0) {
        wchar_t prevLower[16]{};
        for (int i = 0; i < m_prevCollisionRawLen; ++i) prevLower[i] = toLowerAscii(m_prevCollisionRaw[i]);
        bool isTurnHead = (m_prevCollisionRawLen == 4 && prevLower[0] == L't' && prevLower[1] == L'u' && prevLower[2] == L'r' && prevLower[3] == L'n');
        bool isSexHead = (m_prevCollisionRawLen == 3 && prevLower[0] == L's' && prevLower[1] == L'e' && prevLower[2] == L'x');
        if ((isTurnHead && isTurnPhrasalFollower(rawLower, m_rawLen)) || (isSexHead && isSexEnglishFollower(rawLower, m_rawLen))) {
            wchar_t combined[kMaxWordTokens]{};
            int cLen = 0;
            for (int i = 0; i < m_prevCollisionRawLen && cLen < kMaxWordTokens - 1; ++i) combined[cLen++] = m_prevCollisionRaw[i];
            if (cLen < kMaxWordTokens - 1) combined[cLen++] = L' ';
            for (int i = 0; i < m_rawLen && cLen < kMaxWordTokens - 1; ++i) combined[cLen++] = m_rawWord[i];
            combined[cLen] = 0;
            const int32_t retroBs = static_cast<int32_t>(m_prevCollisionDisplayedLen + 1 + m_displayedLen);
            char utf8Retro[kMaxUtf8Bytes]{};
            encodeWideToUtf8(combined, cLen, utf8Retro, kMaxUtf8Bytes);
            m_prevCollisionDisplayedLen = 0;
            m_prevCollisionRawLen = 0;
            m_inEnglishContext = true;
            m_lastWordWasSexLoanwordHead = false;
            clearWordState();
            m_lastBackspaces = retroBs;
            m_lastIsOverride = true;
            for (int i = 0; i < kMaxUtf8Bytes; ++i) {
                m_lastTextUtf8[i] = utf8Retro[i];
                if (utf8Retro[i] == '\0') break;
            }
            return static_cast<int32_t>(Action::Commit);
        }
    }

    const bool wasBilingualRestore = (m_smartBilingual && hasVietnameseTransformation() && shouldRestoreRawEnglish());
    wchar_t finalWord[kMaxWordTokens]{};
    const int finalLen = composeOutputWord(finalWord, kMaxWordTokens);
    const int32_t bs = static_cast<int32_t>(m_displayedLen);

    wchar_t finalLower[kMaxWordTokens]{};
    bool hasNonAscii = false;
    for (int i = 0; i < finalLen; ++i) {
        if (finalWord[i] > 0x7F) hasNonAscii = true;
        finalLower[i] = toLowerAscii(finalWord[i]);
    }
    m_lastWordWasSexLoanwordHead = isSexLoanwordPrecedingHead(finalLower, finalLen) || isSexLoanwordPrecedingHead(rawLower, m_rawLen);
    if (hasNonAscii || isVietnameseContextReset(finalLower, finalLen)) {
        m_inEnglishContext = false;
    } else if (wasBilingualRestore || (!isValidVietnameseSyllable() && !m_classicOrVniEscape && !m_telexToneEscape && !m_overflowLocked && !isOpenSameVowelExtension() && finalLen >= 2) || isUnconditionalEnglishWord(rawLower, m_rawLen) || isEnglishContextAnchor(rawLower, m_rawLen)) {
        m_inEnglishContext = true;
    }

    bool isTurnOrSex = (m_rawLen == 4 && rawLower[0] == L't' && rawLower[1] == L'u' && rawLower[2] == L'r' && rawLower[3] == L'n') ||
                       (m_rawLen == 3 && rawLower[0] == L's' && rawLower[1] == L'e' && rawLower[2] == L'x');
    if (m_smartBilingual && isTurnOrSex && hasNonAscii && m_pendingBoundaryCp == ' ' && finalLen < 15 && m_rawLen < 15) {
        for (int i = 0; i < finalLen; ++i) m_prevCollisionDisplayed[i] = finalWord[i];
        m_prevCollisionDisplayed[finalLen] = 0;
        m_prevCollisionDisplayedLen = finalLen;
        for (int i = 0; i < m_rawLen; ++i) m_prevCollisionRaw[i] = m_rawWord[i];
        m_prevCollisionRaw[m_rawLen] = 0;
        m_prevCollisionRawLen = m_rawLen;
    } else {
        m_prevCollisionDisplayedLen = 0;
        m_prevCollisionRawLen = 0;
    }

    char utf8Final[kMaxUtf8Bytes]{};
    encodeWideToUtf8(finalWord, finalLen, utf8Final, kMaxUtf8Bytes);

    clearWordState();
    if (canArmPostCommit) {
        m_armedAfterSpace = true;
        m_undoTokenLen = savedTokenLen;
        for (int i = 0; i < savedTokenLen; ++i) m_undoTokens[i] = savedTokens[i];
        m_undoTone = savedTone;
        m_undoLastToneKey = savedLastToneKey;
        m_undoLastShapeKey = savedLastShapeKey;
        m_undoRawLen = savedRawLen;
        for (int i = 0; i < savedRawLen; ++i) m_undoRawWord[i] = savedRaw[i];
        m_undoRawWord[savedRawLen] = 0;
        m_undoLiteralTailLen = savedLiteralTailLen;
        for (int i = 0; i < savedLiteralTailLen; ++i) m_undoLiteralTail[i] = savedLiteralTail[i];
        m_undoLiteralTail[savedLiteralTailLen] = 0;
        m_undoLiteralLock = savedLiteralLock;
        m_undoEscapeLockTokenLen = savedEscapeLockTokenLen;
        m_undoClassicOrVniEscape = savedClassicOrVniEscape;
        m_undoTelexToneEscape = savedTelexToneEscape;
        m_undoOverflowLocked = savedOverflowLocked;
    }
    m_lastBackspaces = bs;
    m_lastIsOverride = wasBilingualRestore;
    for (int i = 0; i < kMaxUtf8Bytes; ++i) {
        m_lastTextUtf8[i] = utf8Final[i];
        if (utf8Final[i] == '\0') break;
    }
    return static_cast<int32_t>(Action::Commit);
}



static_assert(sizeof(NativeEngineState) <= 4096, "NativeEngineState exceeds m_opaqueState buffer");

inline NativeEngineState *getImpl(uint8_t *buf) {
    return reinterpret_cast<NativeEngineState *>(buf);
}

inline void syncOut(WindowsNativeEngine *pub, NativeEngineState *impl, int32_t &outBs, char *outUtf8, bool &outComp) {
    (void)pub;
    outBs = impl->m_lastBackspaces;
    for (int i = 0; i < kMaxUtf8Bytes; ++i) {
        outUtf8[i] = impl->m_lastTextUtf8[i];
        if (impl->m_lastTextUtf8[i] == '\0') break;
    }
    outComp = impl->isComposing();
}

} // namespace

WindowsNativeEngine::WindowsNativeEngine() {
    clearWordState();
}

void WindowsNativeEngine::reset() {
    auto *impl = getImpl(m_opaqueState);
    impl->m_inEnglishContext = false;
    impl->m_lastWordWasSexLoanwordHead = false;
    impl->m_precededByTechDelimiter = false;
    impl->m_afterDigit = false;
    impl->m_precededByLeadingSlash = false;
    impl->m_pendingBoundaryCp = 0;
    impl->m_prevCollisionDisplayedLen = 0;
    impl->m_prevCollisionRawLen = 0;
    clearWordState();
}

void WindowsNativeEngine::clearWordState() {
    auto *impl = getImpl(m_opaqueState);
    impl->m_inputMethod = m_inputMethod;
    impl->m_smartBilingual = m_smartBilingual;
    impl->m_modernOrthography = m_modernOrthography;
    impl->clearWordState();
    m_composingFlag = false;
    m_lastBackspaces = 0;
    m_lastTextUtf8[0] = '\0';
}

void WindowsNativeEngine::setInputMethod(InputMethod method) {
    m_inputMethod = method;
    auto *impl = getImpl(m_opaqueState);
    impl->setInputMethod(method);
    m_composingFlag = impl->isComposing();
    m_lastBackspaces = impl->m_lastBackspaces;
    m_lastTextUtf8[0] = '\0';
}

int32_t WindowsNativeEngine::feedChar(uint32_t codepoint) {
    auto *impl = getImpl(m_opaqueState);
    impl->m_inputMethod = m_inputMethod;
    impl->m_smartBilingual = m_smartBilingual;
    impl->m_modernOrthography = m_modernOrthography;
    int32_t act = impl->feedChar(codepoint);
    syncOut(this, impl, m_lastBackspaces, m_lastTextUtf8, m_composingFlag);
    return act;
}

int32_t WindowsNativeEngine::feedBackspace() {
    auto *impl = getImpl(m_opaqueState);
    impl->m_inputMethod = m_inputMethod;
    impl->m_smartBilingual = m_smartBilingual;
    impl->m_modernOrthography = m_modernOrthography;
    int32_t act = impl->feedBackspace();
    syncOut(this, impl, m_lastBackspaces, m_lastTextUtf8, m_composingFlag);
    return act;
}

int32_t WindowsNativeEngine::commitWord() {
    auto *impl = getImpl(m_opaqueState);
    impl->m_inputMethod = m_inputMethod;
    impl->m_smartBilingual = m_smartBilingual;
    impl->m_modernOrthography = m_modernOrthography;
    int32_t act = impl->commitWord();
    syncOut(this, impl, m_lastBackspaces, m_lastTextUtf8, m_composingFlag);
    return act;
}

} // namespace vielotus_win

#if defined(_WIN32)
#define VIELOTUS_CAPI_EXPORT extern "C" __declspec(dllexport)
#else
#define VIELOTUS_CAPI_EXPORT extern "C" __attribute__((visibility("default")))
#endif

namespace {

struct VieLotusNativeCapiSession {
    vielotus_win::NativeEngineState impl{};
    int32_t lastAction{0};
    int32_t postCommitBackspaceStep{0};
    char composingUtf8[vielotus_win::kMaxUtf8Bytes]{};
    char rawUtf8[vielotus_win::kMaxUtf8Bytes]{};
    char lastTextUtf8[vielotus_win::kMaxUtf8Bytes]{};

    void syncStrings() {
        vielotus_win::NativeEngineState::encodeWideToUtf8(impl.m_displayed, impl.m_displayedLen, composingUtf8, vielotus_win::kMaxUtf8Bytes);
        vielotus_win::NativeEngineState::encodeWideToUtf8(impl.m_rawWord, impl.m_rawLen, rawUtf8, vielotus_win::kMaxUtf8Bytes);
        for (int i = 0; i < vielotus_win::kMaxUtf8Bytes; ++i) {
            lastTextUtf8[i] = impl.m_lastTextUtf8[i];
            if (lastTextUtf8[i] == '\0') break;
        }
    }
};

inline VieLotusNativeCapiSession *asSession(void *ptr) {
    return reinterpret_cast<VieLotusNativeCapiSession *>(ptr);
}

} // namespace

VIELOTUS_CAPI_EXPORT void *vielotus_create_session(void) {
    auto *s = new VieLotusNativeCapiSession();
    s->impl.clearWordState();
    return s;
}

VIELOTUS_CAPI_EXPORT void vielotus_destroy_session(void *session) {
    delete asSession(session);
}

VIELOTUS_CAPI_EXPORT void vielotus_reset_session(void *session) {
    auto *s = asSession(session);
    if (!s) return;
    s->impl.clearWordState();
    s->impl.m_afterDigit = false;
    s->impl.m_precededByLeadingSlash = false;
    s->impl.m_prevCollisionDisplayedLen = 0;
    s->impl.m_prevCollisionRawLen = 0;
    s->lastAction = 4;
    s->postCommitBackspaceStep = 0;
    s->impl.m_lastIsOverride = false;
    s->syncStrings();
}

VIELOTUS_CAPI_EXPORT void vielotus_set_input_method(void *session, int32_t method) {
    auto *s = asSession(session);
    if (!s) return;
    s->impl.setInputMethod(method == 1 ? vielotus_win::InputMethod::VNI : vielotus_win::InputMethod::Telex);
    s->postCommitBackspaceStep = 0;
    s->syncStrings();
}

VIELOTUS_CAPI_EXPORT void vielotus_set_grammar_profile(void *session, int32_t profile) {
    auto *s = asSession(session);
    if (!s) return;
    s->impl.m_grammarProfile = (profile == 0) ? 0 : 1;
}

VIELOTUS_CAPI_EXPORT int32_t vielotus_get_grammar_profile(void *session) {
    auto *s = asSession(session);
    if (!s) return 1;
    return s->impl.m_grammarProfile;
}

VIELOTUS_CAPI_EXPORT void vielotus_set_smart_bilingual(void *session, bool enabled) {
    auto *s = asSession(session);
    if (!s) return;
    s->impl.m_smartBilingual = enabled;
}

VIELOTUS_CAPI_EXPORT void vielotus_set_modern_orthography(void *session, bool enabled) {
    auto *s = asSession(session);
    if (!s) return;
    s->impl.m_modernOrthography = enabled;
}

VIELOTUS_CAPI_EXPORT void vielotus_set_quick_telex(void *session, bool enabled) {
    auto *s = asSession(session);
    if (!s) return;
    s->impl.m_quickTelex = enabled;
}

VIELOTUS_CAPI_EXPORT int32_t vielotus_feed_char(void *session, uint32_t codepoint) {
    auto *s = asSession(session);
    if (!s) return 0;
    s->postCommitBackspaceStep = 0;
    if (s->impl.m_displayedLen > 0 &&
        !vielotus_win::NativeEngineState::isWordBoundaryDelimiter(codepoint) &&
        !vielotus_win::isAsciiAlpha(codepoint) &&
        !(s->impl.m_inputMethod == vielotus_win::InputMethod::VNI && vielotus_win::isAsciiDigit(codepoint) && s->impl.m_tokenLen > 0 && !s->impl.m_literalLock)) {
        int32_t act = s->impl.commitWord();
        s->impl.m_afterDigit = vielotus_win::isAsciiDigit(codepoint);
        s->impl.m_precededByLeadingSlash = false;
        s->lastAction = act;
        s->syncStrings();
        return act;
    }
    int32_t act = s->impl.feedChar(codepoint);
    if (act == 3 && codepoint == ' ' && s->impl.m_armedAfterSpace) {
        s->postCommitBackspaceStep = 1;
    }
    s->lastAction = act;
    s->syncStrings();
    return act;
}

VIELOTUS_CAPI_EXPORT int32_t vielotus_commit_word(void *session) {
    auto *s = asSession(session);
    if (!s) return 0;
    s->postCommitBackspaceStep = 0;
    int32_t act = s->impl.commitWord();
    s->lastAction = act;
    s->syncStrings();
    return act;
}

VIELOTUS_CAPI_EXPORT int32_t vielotus_feed_backspace(void *session) {
    auto *s = asSession(session);
    if (!s) return 0;
    if (s->impl.m_displayedLen == 0) {
        if (s->postCommitBackspaceStep == 1 && s->impl.m_armedAfterSpace) {
            s->postCommitBackspaceStep = 2;
            s->lastAction = 0;
            s->impl.m_lastBackspaces = 0;
            s->impl.m_lastTextUtf8[0] = '\0';
            s->syncStrings();
            return 0;
        }
        if (s->postCommitBackspaceStep == 2 && s->impl.m_armedAfterSpace) {
            s->postCommitBackspaceStep = 0;
            s->impl.m_armedAfterSpace = false;
            if (s->impl.m_undoLiteralTailLen > 0) {
                s->impl.m_tokenLen = s->impl.m_undoTokenLen;
                for (int i = 0; i < s->impl.m_tokenLen; ++i) {
                    s->impl.m_tokens[i] = s->impl.m_undoTokens[i];
                }
                s->impl.m_tone = s->impl.m_undoTone;
                s->impl.m_lastToneKey = s->impl.m_undoLastToneKey;
                s->impl.m_lastShapeKey = s->impl.m_undoLastShapeKey;
                s->impl.m_literalTailLen = s->impl.m_undoLiteralTailLen - 1;
                for (int i = 0; i < s->impl.m_literalTailLen; ++i) {
                    s->impl.m_literalTail[i] = s->impl.m_undoLiteralTail[i];
                }
                s->impl.m_literalTail[s->impl.m_literalTailLen] = 0;
                s->impl.m_literalLock = s->impl.m_undoLiteralLock;
                s->impl.m_escapeLockTokenLen = s->impl.m_undoEscapeLockTokenLen;
                if (s->impl.m_literalTailLen > 0 || s->impl.m_literalLock) {
                    s->impl.m_classicOrVniEscape = s->impl.m_undoClassicOrVniEscape;
                }
                if (s->impl.m_literalTailLen > 0) {
                    s->impl.m_telexToneEscape = s->impl.m_undoTelexToneEscape;
                    s->impl.m_overflowLocked = s->impl.m_undoOverflowLocked;
                }
                s->impl.m_displayedLen = s->impl.composeOutputWord(s->impl.m_displayed, vielotus_win::kMaxWordTokens);
                if (s->impl.m_literalTailLen > 0 || s->impl.m_literalLock) {
                    s->impl.m_rawLen = (s->impl.m_undoRawLen > 0) ? (s->impl.m_undoRawLen - 1) : 0;
                    for (int i = 0; i < s->impl.m_rawLen; ++i) {
                        s->impl.m_rawWord[i] = s->impl.m_undoRawWord[i];
                    }
                    s->impl.m_rawWord[s->impl.m_rawLen] = 0;
                } else {
                    s->impl.m_rawLen = s->impl.m_displayedLen;
                    for (int i = 0; i <= s->impl.m_displayedLen; ++i) {
                        s->impl.m_rawWord[i] = s->impl.m_displayed[i];
                    }
                }
            } else {
                s->impl.m_tokenLen = (s->impl.m_undoTokenLen > 1) ? (s->impl.m_undoTokenLen - 1) : 0;
                for (int i = 0; i < s->impl.m_tokenLen; ++i) {
                    s->impl.m_tokens[i] = s->impl.m_undoTokens[i];
                }
                s->impl.m_tone = s->impl.m_undoTone;
                s->impl.m_lastToneKey = s->impl.m_undoLastToneKey;
                s->impl.m_lastShapeKey = s->impl.m_undoLastShapeKey;
                if (s->impl.m_undoLiteralLock &&
                    (s->impl.m_undoEscapeLockTokenLen == 0 || s->impl.m_tokenLen >= s->impl.m_undoEscapeLockTokenLen)) {
                    s->impl.m_literalLock = true;
                    s->impl.m_escapeLockTokenLen = s->impl.m_undoEscapeLockTokenLen;
                    s->impl.m_classicOrVniEscape = s->impl.m_undoClassicOrVniEscape;
                    s->impl.m_displayedLen = s->impl.composeOutputWord(s->impl.m_displayed, vielotus_win::kMaxWordTokens);
                    s->impl.m_rawLen = (s->impl.m_undoRawLen > 0) ? (s->impl.m_undoRawLen - 1) : 0;
                    for (int i = 0; i < s->impl.m_rawLen; ++i) {
                        s->impl.m_rawWord[i] = s->impl.m_undoRawWord[i];
                    }
                    s->impl.m_rawWord[s->impl.m_rawLen] = 0;
                } else {
                    s->impl.m_displayedLen = s->impl.composeOutputWord(s->impl.m_displayed, vielotus_win::kMaxWordTokens);
                    s->impl.m_rawLen = s->impl.m_displayedLen;
                    for (int i = 0; i <= s->impl.m_displayedLen; ++i) {
                        s->impl.m_rawWord[i] = s->impl.m_displayed[i];
                    }
                }
            }
            s->impl.m_lastBackspaces = 1;
            s->impl.m_lastTextUtf8[0] = '\0';
            s->lastAction = 2;
            s->syncStrings();
            return 2;
        }
        s->postCommitBackspaceStep = 0;
        s->impl.m_armedAfterSpace = false;
        s->lastAction = 0;
        s->syncStrings();
        return 0;
    }
    int32_t act = s->impl.feedBackspace();
    s->lastAction = act;
    s->syncStrings();
    return act;
}

VIELOTUS_CAPI_EXPORT int32_t vielotus_feed_key(void *session, uint32_t key_code, char char_code, uint32_t modifiers) {
    (void)modifiers;
    if (!session) return 0;
    if (key_code == 51 || key_code == 8) {
        return vielotus_feed_backspace(session);
    }
    if (char_code >= 32 && char_code < 127) {
        return vielotus_feed_char(session, static_cast<uint32_t>(static_cast<unsigned char>(char_code)));
    }
    return 0;
}

VIELOTUS_CAPI_EXPORT int32_t vielotus_feed_char_ex(void *session, uint32_t codepoint, int32_t *out_backspaces, const char **out_text) {
    int32_t act = vielotus_feed_char(session, codepoint);
    auto *s = asSession(session);
    if (!s) return act;
    if (out_backspaces) *out_backspaces = s->impl.m_lastBackspaces;
    if (out_text) *out_text = s->lastTextUtf8;
    return act;
}

VIELOTUS_CAPI_EXPORT int32_t vielotus_get_last_action(void *session) {
    auto *s = asSession(session);
    return s ? s->lastAction : 0;
}

VIELOTUS_CAPI_EXPORT int32_t vielotus_get_last_backspaces(void *session) {
    auto *s = asSession(session);
    return s ? s->impl.m_lastBackspaces : 0;
}

VIELOTUS_CAPI_EXPORT const char *vielotus_get_last_text(void *session) {
    auto *s = asSession(session);
    return s ? s->lastTextUtf8 : "";
}

VIELOTUS_CAPI_EXPORT bool vielotus_get_last_is_override(void *session) {
    auto *s = asSession(session);
    return s ? s->impl.m_lastIsOverride : false;
}

VIELOTUS_CAPI_EXPORT bool vielotus_is_composing(void *session) {
    auto *s = asSession(session);
    return s ? (s->impl.m_displayedLen > 0) : false;
}

VIELOTUS_CAPI_EXPORT const char *vielotus_get_composing_text(void *session) {
    auto *s = asSession(session);
    if (!s) return "";
    s->syncStrings();
    return s->composingUtf8;
}

VIELOTUS_CAPI_EXPORT const char *vielotus_get_raw_text(void *session) {
    auto *s = asSession(session);
    if (!s) return "";
    s->syncStrings();
    return s->rawUtf8;
}

VIELOTUS_CAPI_EXPORT void vielotus_append_context(void *session, const char *context_word) {
    auto *s = asSession(session);
    if (!s || !context_word) return;
    if (context_word[0] == '\0') {
        s->impl.m_inEnglishContext = false;
        s->impl.m_lastWordWasSexLoanwordHead = false;
        s->impl.m_precededByTechDelimiter = false;
        s->impl.m_afterDigit = false;
        s->impl.m_precededByLeadingSlash = false;
        s->impl.m_pendingBoundaryCp = 0;
        s->impl.m_prevCollisionDisplayedLen = 0;
        s->impl.m_prevCollisionRawLen = 0;
        return;
    }
    vielotus_win::NativeEngineState temp = s->impl;
    temp.clearWordState();
    for (const unsigned char *p = reinterpret_cast<const unsigned char *>(context_word); *p; ++p) {
        temp.feedChar(static_cast<uint32_t>(*p));
    }
    temp.feedChar(static_cast<uint32_t>(' '));
    s->impl.m_inEnglishContext = temp.m_inEnglishContext;
    s->impl.m_lastWordWasSexLoanwordHead = temp.m_lastWordWasSexLoanwordHead;
    s->impl.m_precededByTechDelimiter = temp.m_precededByTechDelimiter;
    s->impl.m_prevCollisionDisplayedLen = 0;
    s->impl.m_prevCollisionRawLen = 0;
}

VIELOTUS_CAPI_EXPORT void vielotus_sync_armed_word(void *session, const char *before_context_utf8) {
    (void)session;
    (void)before_context_utf8;
}

VIELOTUS_CAPI_EXPORT const char *vielotus_get_version(void) {
    return "2.0.1";
}
