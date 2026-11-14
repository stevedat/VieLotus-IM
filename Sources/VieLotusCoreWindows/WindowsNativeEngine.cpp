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
#include <cstring>
#include <cwchar>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

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

bool isMathFunctionAnchor(const wchar_t *word, int len) {
    static const wchar_t *const anchors[] = {
        L"sin", L"cos", L"tan", L"cot", L"sine", L"cosine", L"tangent", L"trig", L"trigonometry"
    };
    for (const auto *anchor : anchors) {
        if (static_cast<int>(std::wcslen(anchor)) == len && std::wmemcmp(word, anchor, len) == 0) return true;
    }
    return false;
}

bool isEnglishContextAnchor(const wchar_t *rawLower, int rawLen) {
    if (rawLen <= 0) return false;
    if (rawLen == 1 && (rawLower[0] == L'a' || rawLower[0] == L'i')) return true;
    if (rawLen == 2 && rawLower[0] == L'a' && rawLower[1] == L'n') return true;
    return hasSortedHash(kEnglishContextAnchors, fnv1aHash(rawLower, rawLen));
}

bool isSyntheticInflectionTrapWord(const wchar_t *rawLower, int rawLen) {
    if (rawLen < 3 || rawLen > 6) return false;
    static const wchar_t *const kTraps[] = {
        L"beest", L"deest", L"heer", L"heest", L"hoest", L"leer", L"leest",
        L"loest", L"meest", L"neer", L"neest", L"oer", L"queest", L"reer",
        L"reest", L"seer", L"teest", L"theer", L"theest", L"toer", L"toest",
        L"vees", L"veest"
    };
    for (const wchar_t *w : kTraps) {
        int i = 0;
        while (i < rawLen && w[i] != L'\0' && rawLower[i] == w[i]) ++i;
        if (i == rawLen && w[i] == L'\0') return true;
    }
    return false;
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

bool isDefaultNoContextShortEnglishWord(const wchar_t *rawLower, int rawLen) {
    if (rawLen == 2) {
        return (rawLower[0] == L'o' && rawLower[1] == L'f') || // of
               (rawLower[0] == L'i' && rawLower[1] == L's') || // is
               (rawLower[0] == L'o' && rawLower[1] == L'r') || // or
               (rawLower[0] == L'a' && rawLower[1] == L's') || // as
               (rawLower[0] == L'i' && rawLower[1] == L'f') || // if
               (rawLower[0] == L'u' && rawLower[1] == L's');   // us
    }
    if (rawLen == 3) {
        return (rawLower[0] == L'o' && rawLower[1] == L'f' && rawLower[2] == L'f');   // off
    }
    if (rawLen == 4) {
        return (rawLower[0] == L'a' && rawLower[1] == L'j' && rawLower[2] == L'a' && rawLower[3] == L'x'); // ajax
    }
    return false;
}

bool prefersEnglishByOrthographicCase(
    const wchar_t *rawWord,
    const wchar_t *rawLower,
    int rawLen,
    int tone,
    bool isEscape
) {
    if (rawLen < 2) return false;
    bool allCaps = true;
    bool seenLower = false;
    bool hasInternalUpperAfterLower = false;
    for (int i = 0; i < rawLen; ++i) {
        const bool isUpper = (rawWord[i] >= L'A' && rawWord[i] <= L'Z');
        const bool isLower = (rawWord[i] >= L'a' && rawWord[i] <= L'z');
        if (!isUpper) allCaps = false;
        if (isLower) seenLower = true;
        if (seenLower && isUpper) hasInternalUpperAfterLower = true;
    }
    if (!isEscape && hasInternalUpperAfterLower) {
        if (isContextEnglishCollisionWord(rawLower, rawLen) ||
            isUnconditionalEnglishWord(rawLower, rawLen) ||
            (rawLen >= 3 && rawLower[rawLen - 2] == L'o' && rawLower[rawLen - 1] == L's') ||
            (rawLen == 4 && rawLower[1] == L'a' && rawLower[2] == L'a' && rawWord[3] == L'S')) {
            return true;
        }
    }
    if (!allCaps || tone == 0 || rawLen > 3) return false;
    if (rawLen == 2) {
        return (rawLower[0] == L'o' && rawLower[1] == L's') || // OS
               (rawLower[0] == L'i' && rawLower[1] == L'r') || // IR
               (rawLower[0] == L'i' && rawLower[1] == L'x');   // IX
    }
    if (rawLen == 3) {
        return (rawLower[0] == L'e' && rawLower[1] == L's' && rawLower[2] == L't'); // EST
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

uint32_t toLowerCodepointVn(uint32_t cp) {
    if (cp >= 'A' && cp <= 'Z') return cp + ('a' - 'A');
    if (cp == 0x0110) return 0x0111; // Đ -> đ
    for (int r = 0; r < 12; ++r) {
        for (int c = 0; c < 6; ++c) {
            if (cp == static_cast<uint32_t>(kUpperVowelTable[r][c])) {
                return static_cast<uint32_t>(kLowerVowelTable[r][c]);
            }
        }
    }
    return cp;
}

uint32_t toUpperCodepointVn(uint32_t cp) {
    if (cp >= 'a' && cp <= 'z') return cp - ('a' - 'A');
    if (cp == 0x0111) return 0x0110; // đ -> Đ
    for (int r = 0; r < 12; ++r) {
        for (int c = 0; c < 6; ++c) {
            if (cp == static_cast<uint32_t>(kLowerVowelTable[r][c])) {
                return static_cast<uint32_t>(kUpperVowelTable[r][c]);
            }
        }
    }
    return cp;
}

bool isUpperCodepointVn(uint32_t cp) {
    if (cp >= 'A' && cp <= 'Z') return true;
    if (cp == 0x0110) return true;
    for (int r = 0; r < 12; ++r) {
        for (int c = 0; c < 6; ++c) {
            if (cp == static_cast<uint32_t>(kUpperVowelTable[r][c])) return true;
        }
    }
    return false;
}

bool isLetterCodepointVn(uint32_t cp) {
    if ((cp >= 'A' && cp <= 'Z') || (cp >= 'a' && cp <= 'z')) return true;
    if (cp == 0x0110 || cp == 0x0111) return true;
    for (int r = 0; r < 12; ++r) {
        for (int c = 0; c < 6; ++c) {
            if (cp == static_cast<uint32_t>(kLowerVowelTable[r][c]) ||
                cp == static_cast<uint32_t>(kUpperVowelTable[r][c])) {
                return true;
            }
        }
    }
    return false;
}

void appendCodepointUtf8(std::string &out, uint32_t cp) {
    if (cp < 0x80) {
        out.push_back(static_cast<char>(cp));
    } else if (cp < 0x800) {
        out.push_back(static_cast<char>(0xC0 | (cp >> 6)));
        out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
    } else if (cp < 0x10000) {
        out.push_back(static_cast<char>(0xE0 | (cp >> 12)));
        out.push_back(static_cast<char>(0x80 | ((cp >> 6) & 0x3F)));
        out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
    } else if (cp <= 0x10FFFF) {
        out.push_back(static_cast<char>(0xF0 | (cp >> 18)));
        out.push_back(static_cast<char>(0x80 | ((cp >> 12) & 0x3F)));
        out.push_back(static_cast<char>(0x80 | ((cp >> 6) & 0x3F)));
        out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
    }
}

std::vector<uint32_t> decodeUtf8Codepoints(const std::string &s) {
    std::vector<uint32_t> cps;
    size_t i = 0;
    while (i < s.size()) {
        unsigned char c = static_cast<unsigned char>(s[i]);
        uint32_t cp = 0;
        if (c < 0x80) {
            cp = c;
            i += 1;
        } else if ((c & 0xE0) == 0xC0 && i + 1 < s.size()) {
            cp = ((c & 0x1F) << 6) | (static_cast<unsigned char>(s[i + 1]) & 0x3F);
            i += 2;
        } else if ((c & 0xF0) == 0xE0 && i + 2 < s.size()) {
            cp = ((c & 0x0F) << 12) |
                 ((static_cast<unsigned char>(s[i + 1]) & 0x3F) << 6) |
                 (static_cast<unsigned char>(s[i + 2]) & 0x3F);
            i += 3;
        } else if ((c & 0xF8) == 0xF0 && i + 3 < s.size()) {
            cp = ((c & 0x07) << 18) |
                 ((static_cast<unsigned char>(s[i + 1]) & 0x3F) << 12) |
                 ((static_cast<unsigned char>(s[i + 2]) & 0x3F) << 6) |
                 (static_cast<unsigned char>(s[i + 3]) & 0x3F);
            i += 4;
        } else {
            cp = c;
            i += 1;
        }
        cps.push_back(cp);
    }
    return cps;
}

std::string utf8TrimAscii(const std::string &s) {
    size_t b = 0;
    while (b < s.size() && (s[b] == ' ' || s[b] == '\t' || s[b] == '\r' || s[b] == '\n')) ++b;
    size_t e = s.size();
    while (e > b && (s[e - 1] == ' ' || s[e - 1] == '\t' || s[e - 1] == '\r' || s[e - 1] == '\n')) --e;
    return s.substr(b, e - b);
}

std::string utf8ToLowerVn(const std::string &s) {
    std::string out;
    out.reserve(s.size());
    for (uint32_t cp : decodeUtf8Codepoints(s)) {
        appendCodepointUtf8(out, toLowerCodepointVn(cp));
    }
    return out;
}

std::string utf8ToUpperVn(const std::string &s) {
    std::string out;
    out.reserve(s.size());
    for (uint32_t cp : decodeUtf8Codepoints(s)) {
        appendCodepointUtf8(out, toUpperCodepointVn(cp));
    }
    return out;
}

std::string utf8UpperFirstVn(const std::string &s) {
    auto cps = decodeUtf8Codepoints(s);
    if (cps.empty()) return s;
    cps[0] = toUpperCodepointVn(cps[0]);
    std::string out;
    out.reserve(s.size());
    for (uint32_t cp : cps) {
        appendCodepointUtf8(out, cp);
    }
    return out;
}

bool isMacroTechnicalDelimiter(uint32_t cp) {
    if (cp >= '0' && cp <= '9') return true;
    switch (cp) {
    case '.': case ':': case '/': case '@': case '_':
    case '-': case '#': case '\\': case '=': case '$':
    case '~': case '`':
        return true;
    default:
        return false;
    }
}

bool shouldSuppressMacroExpansion(bool precededByMacroDelimiter, uint32_t boundaryCp) {
    if (precededByMacroDelimiter) return true;
    if (boundaryCp != 0) {
        if (isMacroTechnicalDelimiter(boundaryCp)) return true;
        if (boundaryCp == '(' || boundaryCp == '[' || boundaryCp == '{' || boundaryCp == '<') return true;
    }
    return false;
}

class GlobalMacroStore {
public:
    static GlobalMacroStore &instance() {
        static GlobalMacroStore s;
        return s;
    }

    void resetToDefaults() {
        std::lock_guard<std::mutex> lock(m_mutex);
        populateDefaultsUnlocked(m_macros);
    }

    bool loadJson(const char *jsonUtf8) {
        if (!jsonUtf8) return false;
        std::unordered_map<std::string, std::string> parsed;
        size_t pos = 0;
        const size_t len = std::strlen(jsonUtf8);
        auto skipWs = [&]() {
            while (pos < len) {
                char c = jsonUtf8[pos];
                if (c == ' ' || c == '\t' || c == '\r' || c == '\n') ++pos;
                else break;
            }
        };
        auto parseHex4 = [&](uint32_t &outVal) -> bool {
            if (pos + 4 > len) return false;
            outVal = 0;
            for (int k = 0; k < 4; ++k) {
                char h = jsonUtf8[pos++];
                outVal <<= 4;
                if (h >= '0' && h <= '9') outVal |= static_cast<uint32_t>(h - '0');
                else if (h >= 'a' && h <= 'f') outVal |= static_cast<uint32_t>(10 + (h - 'a'));
                else if (h >= 'A' && h <= 'F') outVal |= static_cast<uint32_t>(10 + (h - 'A'));
                else return false;
            }
            return true;
        };
        auto parseString = [&](std::string &outStr) -> bool {
            outStr.clear();
            if (pos >= len || jsonUtf8[pos] != '"') return false;
            ++pos;
            while (pos < len) {
                unsigned char c = static_cast<unsigned char>(jsonUtf8[pos++]);
                if (c == '"') return true;
                if (c < 0x20) return false;
                if (c == '\\') {
                    if (pos >= len) return false;
                    char esc = jsonUtf8[pos++];
                    switch (esc) {
                    case '"':  outStr.push_back('"'); break;
                    case '\\': outStr.push_back('\\'); break;
                    case '/':  outStr.push_back('/'); break;
                    case 'b':  outStr.push_back('\b'); break;
                    case 'f':  outStr.push_back('\f'); break;
                    case 'n':  outStr.push_back('\n'); break;
                    case 'r':  outStr.push_back('\r'); break;
                    case 't':  outStr.push_back('\t'); break;
                    case 'u': {
                        uint32_t u1 = 0;
                        if (!parseHex4(u1)) return false;
                        if (u1 >= 0xD800 && u1 <= 0xDBFF) {
                            if (pos + 2 > len || jsonUtf8[pos] != '\\' || jsonUtf8[pos + 1] != 'u') return false;
                            pos += 2;
                            uint32_t u2 = 0;
                            if (!parseHex4(u2) || u2 < 0xDC00 || u2 > 0xDFFF) return false;
                            uint32_t fullCp = 0x10000 + (((u1 - 0xD800) << 10) | (u2 - 0xDC00));
                            appendCodepointUtf8(outStr, fullCp);
                        } else {
                            appendCodepointUtf8(outStr, u1);
                        }
                        break;
                    }
                    default:
                        return false;
                    }
                } else {
                    outStr.push_back(static_cast<char>(c));
                }
            }
            return false;
        };

        skipWs();
        if (pos >= len || jsonUtf8[pos] != '{') return false;
        ++pos;
        skipWs();
        if (pos < len && jsonUtf8[pos] == '}') {
            ++pos;
            skipWs();
            if (pos != len) return false;
            std::lock_guard<std::mutex> lock(m_mutex);
            m_macros.swap(parsed);
            return true;
        }
        while (pos < len) {
            skipWs();
            std::string rawKey;
            if (!parseString(rawKey)) return false;
            skipWs();
            if (pos >= len || jsonUtf8[pos] != ':') return false;
            ++pos;
            skipWs();
            std::string rawVal;
            if (!parseString(rawVal)) return false;
            std::string cleanK = utf8ToLowerVn(utf8TrimAscii(rawKey));
            std::string cleanV = utf8TrimAscii(rawVal);
            if (!cleanK.empty() && !cleanV.empty()) {
                parsed[cleanK] = cleanV;
            }
            skipWs();
            if (pos >= len) return false;
            if (jsonUtf8[pos] == ',') {
                ++pos;
                continue;
            }
            if (jsonUtf8[pos] == '}') {
                ++pos;
                skipWs();
                if (pos != len) return false;
                std::lock_guard<std::mutex> lock(m_mutex);
                m_macros.swap(parsed);
                return true;
            }
            return false;
        }
        return false;
    }

    bool lookup(const std::string &wordUtf8, std::string &outExpanded) {
        if (wordUtf8.empty()) return false;
        std::lock_guard<std::mutex> lock(m_mutex);
        auto directIt = m_macros.find(wordUtf8);
        if (directIt != m_macros.end()) {
            outExpanded = directIt->second;
            return true;
        }
        std::string lowerKey = utf8ToLowerVn(wordUtf8);
        auto lowerIt = m_macros.find(lowerKey);
        if (lowerIt == m_macros.end()) return false;

        const std::string &expansion = lowerIt->second;
        auto cps = decodeUtf8Codepoints(wordUtf8);
        std::string upperWord = utf8ToUpperVn(wordUtf8);
        bool hasLetter = false;
        for (uint32_t cp : cps) {
            if (isLetterCodepointVn(cp)) {
                hasLetter = true;
                break;
            }
        }
        if (cps.size() >= 2 && hasLetter && wordUtf8 == upperWord) {
            outExpanded = utf8ToUpperVn(expansion);
            return true;
        }
        if (!cps.empty() && isUpperCodepointVn(cps[0])) {
            outExpanded = utf8UpperFirstVn(expansion);
            return true;
        }
        outExpanded = expansion;
        return true;
    }

private:
    GlobalMacroStore() {
        populateDefaultsUnlocked(m_macros);
    }

    static void populateDefaultsUnlocked(std::unordered_map<std::string, std::string> &m) {
        m.clear();
        static const std::pair<const char *, const char *> kDefaults[] = {
            // Địa danh Việt Nam phổ biến (không mặc định "vn" hay "k")
            { "sg", "Sài Gòn" },
            { "hn", "Hà Nội" },
            { "dn", "Đà Nẵng" },
            { "hp", "Hải Phòng" },
            { "ct", "Cần Thơ" },
            { "dl", "Đà Lạt" },
            { "vt", "Vũng Tàu" },
            { "bd", "Bình Dương" },
            { "đn", "Đồng Nai" },
            { "qn", "Quảng Ninh" },
            { "hue", "Thừa Thiên Huế" },
            { "ntr", "Nha Trang" },
            { "hl", "Hạ Long" },
            { "hcm", "Hồ Chí Minh" },
            { "tphcm", "TP. Hồ Chí Minh" },
            // Từ giao tiếp & đời sống
            { "dc", "được" },
            { "đc", "được" },
            { "ko", "không" },
            { "vs", "với" },
            { "ng", "người" },
            { "ch", "chưa" },
            { "nt", "nhắn tin" },
            { "kb", "không biết" },
            { "tn", "thế nào" },
            { "bh", "bây giờ" },
            { "tc", "tất cả" },
            // Từ công việc & văn phòng
            { "cty", "công ty" },
            { "sđt", "số điện thoại" },
            { "sdt", "số điện thoại" },
            { "tk", "tài khoản" },
            { "kh", "khách hàng" },
            { "sp", "sản phẩm" },
            { "dv", "dịch vụ" },
            { "tg", "thời gian" },
            { "tt", "thông tin" },
            { "lh", "liên hệ" },
            { "kn", "kinh nghiệm" },
            { "pt", "phát triển" },
            { "nv", "nhân viên" },
            { "ql", "quản lý" },
            { "gd", "giám đốc" }
        };
        for (const auto &kv : kDefaults) {
            m[kv.first] = kv.second;
        }
    }

    std::mutex m_mutex;
    std::unordered_map<std::string, std::string> m_macros;
};

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
    bool m_relaxedCoda{false};
    bool m_macroEnabled{false};

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
    bool m_relaxedCodaExpanded{false};
    bool m_suppressEnglishRestoreAfterBackspace{false};
    bool m_toneRetainedFromBackspace{false};
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
    int32_t m_lastCommitDiffBackspaces{0};
    char m_lastCommitDiffTextUtf8[kMaxUtf8Bytes]{};
    bool m_inEnglishContext{false};
    bool m_inVietnameseContext{false};
    bool m_hadVietnameseInSentence{false};
    bool m_lastWordWasEnglishAnchor{false};
    int m_mathContextWordsRemaining{0};
    bool m_lastWordWasSexLoanwordHead{false};
    bool m_lastWordWasTunCollocationHead{false};
    bool m_prevTurnCanBecomeTun{false};
    bool m_precededByTechDelimiter{false};
    bool m_precededByMacroDelimiter{false};
    bool m_afterDigit{false};
    bool m_precededByLeadingSlash{false};
    bool m_inSubwordEval{false};
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
        m_relaxedCodaExpanded = false;
        m_suppressEnglishRestoreAfterBackspace = false;
        m_toneRetainedFromBackspace = false;
        m_escapeLockTokenLen = 0;
        m_hasUndoSnapshot = false;
        m_armedAfterSpace = false;
        m_lastBackspaces = 0;
        m_lastTextUtf8[0] = '\0';
        m_lastCommitDiffBackspaces = 0;
        m_lastCommitDiffTextUtf8[0] = '\0';
        m_afterDigit = false;
    }

    bool isComposing() const {
        return m_displayedLen > 0 || m_armedAfterSpace;
    }

    bool rawWordStartsNonW() const {
        return m_rawLen > 0 && m_rawWord[0] != L'w' && m_rawWord[0] != L'W';
    }

    bool allRawCharsAreW() const {
        if (m_rawLen <= 0) return false;
        for (int i = 0; i < m_rawLen; ++i) {
            if (m_rawWord[i] != L'w' && m_rawWord[i] != L'W') return false;
        }
        return true;
    }

    void rebuildCanonicalRawFromTokens() {
        m_rawLen = 0;
        const bool vni = (m_inputMethod == InputMethod::VNI);
        for (int i = 0; i < m_tokenLen && m_rawLen < kMaxWordTokens - 1; ++i) {
            const SyllableToken &tk = m_tokens[i];
            const wchar_t base = tk.isUpper ? static_cast<wchar_t>(tk.baseLower - (L'a' - L'A')) : tk.baseLower;
            m_rawWord[m_rawLen++] = base;
            if (m_rawLen >= kMaxWordTokens - 1) break;
            if (tk.baseLower == L'd' && tk.shape == 4) {
                m_rawWord[m_rawLen++] = vni ? L'9' : (tk.isUpper ? L'D' : L'd');
            } else if (tk.shape == 1) {
                m_rawWord[m_rawLen++] = vni ? L'6' : base;
            } else if (tk.shape == 2) {
                const bool isFirstOfCompoundUo =
                    (tk.baseLower == L'u' && (i + 1) < m_tokenLen &&
                     m_tokens[i + 1].baseLower == L'o' && m_tokens[i + 1].shape == 2);
                if (!isFirstOfCompoundUo) {
                    m_rawWord[m_rawLen++] = vni ? L'7' : (tk.isUpper ? L'W' : L'w');
                }
            } else if (tk.shape == 3) {
                m_rawWord[m_rawLen++] = vni ? L'8' : (tk.isUpper ? L'W' : L'w');
            }
        }
        if (m_tone != 0 && m_rawLen < kMaxWordTokens - 1) {
            if (vni) {
                m_rawWord[m_rawLen++] = static_cast<wchar_t>(L'0' + m_tone);
            } else {
                wchar_t tKey = 0;
                switch (m_tone) {
                case 1: tKey = L's'; break;
                case 2: tKey = L'f'; break;
                case 3: tKey = L'r'; break;
                case 4: tKey = L'x'; break;
                case 5: tKey = L'j'; break;
                default: break;
                }
                if (tKey != 0) {
                    m_rawWord[m_rawLen++] = tKey;
                }
            }
        }
        for (int i = 0; i < m_literalTailLen && m_rawLen < kMaxWordTokens - 1; ++i) {
            m_rawWord[m_rawLen++] = m_literalTail[i];
        }
        m_rawWord[m_rawLen] = 0;
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

    bool hasStrongVietnameseSyllableAnchor() const {
        if (hasCompoundUoOrStrokeD()) return true;
        if (!m_nonAdjacentCircumflex && m_tone != 0) {
            int vStart = -1, vEnd = -1;
            bool hasCoda = false;
            findVowelCluster(vStart, vEnd, hasCoda);
            if (hasCoda) {
                for (int i = vStart; i < vEnd; ++i) {
                    const wchar_t c0 = m_tokens[i].baseLower;
                    const wchar_t c1 = m_tokens[i + 1].baseLower;
                    if (((c0 == L'i' || c0 == L'y') && c1 == L'e' && m_tokens[i + 1].shape == 1) ||
                        (c0 == L'u' && c1 == L'o' && m_tokens[i + 1].shape == 1)) {
                        return true;
                    }
                }
            }
        }
        return false;
    }

    bool isOpenSameVowelExtension() const {
        if (m_tone == 0 || m_literalTailLen <= 0 || m_tokenLen < 1 || !rawWordStartsNonW()) {
            return false;
        }
        int vStart = -1, vEnd = -1;
        bool hasCoda = false;
        findVowelCluster(vStart, vEnd, hasCoda);
        if (vStart < 0 || hasCoda || vEnd != m_tokenLen - 1) {
            return false;
        }
        if (vStart == 0 && m_tokens[vEnd].shape == 0) {
            return false;
        }
        if (vStart > 0) {
            wchar_t initStr[16]{};
            int initLen = 0;
            for (int i = 0; i < vStart && initLen < 15; ++i) {
                initStr[initLen++] = m_tokens[i].baseLower;
            }
            const bool hasStrokeD = (vStart == 1 && m_tokens[0].baseLower == L'd' && m_tokens[0].shape == 4);
            if (!isValidInitialOnset(initStr, initLen, hasStrokeD)) {
                return false;
            }
        }
        const wchar_t baseV = m_tokens[vEnd].baseLower;
        for (int i = 0; i < m_literalTailLen; ++i) {
            if (toLowerAscii(m_literalTail[i]) != baseV) {
                return false;
            }
        }
        return true;
    }

    bool isSingleModifiedVowelOverflow() const {
        if (m_tokenLen != 1 || m_literalTailLen <= 0 || !rawWordStartsNonW()) {
            return false;
        }
        if (m_tokens[0].shape != 1 && m_tokens[0].shape != 2 && m_tokens[0].shape != 3) {
            return false;
        }
        for (int i = 0; i < m_literalTailLen; ++i) {
            if (!isAsciiBaseVowel(toLowerAscii(m_literalTail[i]))) {
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
    bool tryComposeMixedCaseCompound(wchar_t *outBuf, int maxLen) const;
    int composeOutputWord(wchar_t *outBuf, int maxLen) const;
    bool applyTelexCharacter(wchar_t ch, wchar_t lowerCh, bool isUpper);
    bool applyVniCharacter(wchar_t ch);
    int32_t emitIncrementalReplacement(const wchar_t *priorDisplayed, int priorLen, const wchar_t *newDisplayed, int newLen);
    int32_t feedChar(uint32_t codepoint);
    int32_t feedBackspace();
    int32_t commitWord();
    void appendContextWord(const char *contextWord);
    void syncSurroundingContext(const char *beforeContextUtf8);
    bool tryRehydrateAndFeed(const wchar_t *precedingWord, int wordLen, uint32_t codepoint);
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
    m_afterDigit = false;
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
    if (allRawCharsAreW()) return false;
    if (m_relaxedCodaExpanded) return true;
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

    if (m_tone == 0 && (m_tokenLen == 3 || m_tokenLen == 4) &&
        m_tokens[0].baseLower == L'u' && m_tokens[0].shape == 2 &&
        m_tokens[1].baseLower == L'c' && m_tokens[1].shape == 0 &&
        m_tokens[2].baseLower == L'l' && m_tokens[2].shape == 0 &&
        (m_tokenLen == 3 || (m_tokens[3].baseLower == L'n' && m_tokens[3].shape == 0))) {
        return true;
    }

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

    wchar_t rawLower[kMaxWordTokens]{};
    for (int i = 0; i < m_rawLen; ++i) {
        rawLower[i] = toLowerAscii(m_rawWord[i]);
    }

    bool hasShapeOrTone = (m_tone != 0);
    for (int i = 0; i < m_tokenLen && !hasShapeOrTone; ++i) {
        if (m_tokens[i].shape != 0) hasShapeOrTone = true;
    }

    const bool isRelaxedH =
        m_relaxedCoda && hasShapeOrTone && codaLen == 1 && codaStr[0] == L'h' &&
        !(m_rawLen >= 2 && rawLower[m_rawLen - 2] == L's' && rawLower[m_rawLen - 1] == L'h');
    const bool isEthnicDakLakK =
        codaLen == 1 && codaStr[0] == L'k' &&
        vLen == 1 && m_tokens[vStart].baseLower == L'a' && m_tokens[vStart].shape == 3 &&
        (hasStrokeD ||
         (initLen == 1 && initStr[0] == L'l' && (m_tone != 0 || m_tokens[0].isUpper || m_inVietnameseContext)));
    const bool isRelaxedK =
        isEthnicDakLakK ||
        (m_relaxedCoda && hasShapeOrTone && codaLen == 1 && codaStr[0] == L'k' &&
         !(m_rawLen >= 2 && rawLower[m_rawLen - 2] == L's' && rawLower[m_rawLen - 1] == L'k'));

    wchar_t effectiveCoda[16]{};
    int effectiveCodaLen = codaLen;
    if (isRelaxedH) {
        effectiveCoda[0] = L'n';
        effectiveCoda[1] = L'h';
        effectiveCodaLen = 2;
    } else if (isRelaxedK) {
        effectiveCoda[0] = L'c';
        effectiveCodaLen = 1;
    } else {
        for (int i = 0; i < codaLen; ++i) effectiveCoda[i] = codaStr[i];
    }

    if (!isValidFinalCoda(effectiveCoda, effectiveCodaLen)) {
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
            if ((v2 == L'i' || v2 == L'o') && s1 == 0 && s2 == 0 && effectiveCodaLen == 0) validPair = true;
            else if ((v2 == L'u' || v2 == L'y') && (s1 == 0 || s1 == 1) && s2 == 0 && effectiveCodaLen == 0) validPair = true;
        } else if (v1 == L'e') {
            if (v2 == L'o' && s1 == 0 && s2 == 0 && effectiveCodaLen == 0) validPair = true;
            else if (v2 == L'u' && s1 == 1 && s2 == 0 && effectiveCodaLen == 0 && !(initLen == 2 && initStr[0] == L'q' && initStr[1] == L'u')) validPair = true;
        } else if (v1 == L'i') {
            if (v2 == L'a' && s1 == 0 && s2 == 0 && effectiveCodaLen == 0) validPair = true;
            else if (v2 == L'e' && s1 == 0 && s2 == 1) validPair = true;
            else if (v2 == L'u' && s1 == 0 && s2 == 0 && effectiveCodaLen == 0) validPair = true;
        } else if (v1 == L'o') {
            if (v2 == L'a' && s1 == 0 && (s2 == 0 || s2 == 3)) validPair = true;
            else if (v2 == L'e' && s1 == 0 && s2 == 0 &&
                     (effectiveCodaLen == 0 || (effectiveCodaLen == 1 && (effectiveCoda[0] == L'n' || effectiveCoda[0] == L't')))) {
                if (initLen == 0) {
                    validPair = true;
                } else if (initLen == 1) {
                    const wchar_t c0 = initStr[0];
                    validPair = !hasStrokeD && (c0 == L'h' || c0 == L'l' || c0 == L't' || c0 == L'x');
                } else if (initLen == 2) {
                    validPair = (initStr[0] == L'c' && initStr[1] == L'h') ||
                                (initStr[0] == L'k' && initStr[1] == L'h') ||
                                (initStr[0] == L'n' && initStr[1] == L'g') ||
                                (initStr[0] == L'n' && initStr[1] == L'h') ||
                                (initStr[0] == L't' && initStr[1] == L'h') ||
                                (initStr[0] == L'q' && initStr[1] == L'u');
                } else if (initLen == 3) {
                    validPair = (initStr[0] == L'n' && initStr[1] == L'g' && initStr[2] == L'h');
                }
            }
            else if (v2 == L'i' && (s1 == 0 || s1 == 1 || s1 == 2) && s2 == 0 && effectiveCodaLen == 0) validPair = true;
            else if (v2 == L'o' && s1 == 0 && s2 == 0 && isValidDoubleOCoda(effectiveCoda, effectiveCodaLen)) validPair = true;
        } else if (v1 == L'u') {
            if (v2 == L'a' && ((s1 == 0 && (s2 == 0 || s2 == 1 || (initLen == 0 && s2 == 3 && effectiveCodaLen > 0))) || (s1 == 2 && s2 == 0 && effectiveCodaLen == 0))) validPair = true;
            else if (v2 == L'e' && s1 == 0 && s2 == 1) validPair = true;
            else if (v2 == L'i' && (s1 == 0 || s1 == 2) && s2 == 0 && effectiveCodaLen == 0) validPair = true;
            else if (v2 == L'o' && ((s1 == 0 && s2 == 1) || (s1 == 2 && s2 == 2) || (effectiveCodaLen == 0 && s1 == 2 && s2 == 0) || ((hasStrokeD || m_shapeCancelledOnce) && s1 == 0 && s2 == 0))) validPair = true;
            else if (v2 == L'y' && s1 == 0 && s2 == 0) validPair = true;
            else if (v2 == L'u' && s1 == 2 && s2 == 0 && effectiveCodaLen == 0) validPair = true;
        } else if (v1 == L'y') {
            if (v2 == L'a' && s1 == 0 && s2 == 0 && effectiveCodaLen == 0) validPair = true;
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
        if ((v1 == L'i' || v1 == L'y') && v2 == L'e' && v3 == L'u' && s1 == 0 && s2 == 1 && s3 == 0 && effectiveCodaLen == 0) validTrip = true;
        else if (v1 == L'o' && v2 == L'a' && (v3 == L'i' || v3 == L'y') && s1 == 0 && s2 == 0 && s3 == 0 && effectiveCodaLen == 0) validTrip = true;
        else if (v1 == L'u' && v2 == L'a' && v3 == L'y' && s1 == 0 && s2 == 1 && s3 == 0 && effectiveCodaLen == 0) validTrip = true;
        else if (v1 == L'u' && v2 == L'o' && (v3 == L'i' || v3 == L'u') && ((s1 == 0 && s2 == 1 && v3 == L'i') || (s1 == 2 && s2 == 2)) && s3 == 0 && effectiveCodaLen == 0) validTrip = true;
        else if (v1 == L'u' && v2 == L'y' && v3 == L'a' && s1 == 0 && s2 == 0 && s3 == 0 && effectiveCodaLen == 0) validTrip = true;
        else if (v1 == L'u' && v2 == L'y' && v3 == L'e' && s1 == 0 && s2 == 0 && s3 == 1) validTrip = true;
        else if (v1 == L'u' && v2 == L'y' && v3 == L'u' && s1 == 0 && s2 == 0 && s3 == 0 && effectiveCodaLen == 0) validTrip = true;
        if (!validTrip) return false;
    }

    // "ươ" cannot pair with palatal codas "ch" or "nh" in Vietnamese phonotactics
    if (effectiveCodaLen == 2 && effectiveCoda[1] == L'h' && (effectiveCoda[0] == L'c' || effectiveCoda[0] == L'n')) {
        for (int i = vStart; i < vEnd; ++i) {
            if (m_tokens[i].baseLower == L'u' && m_tokens[i + 1].baseLower == L'o') {
                return false;
            }
        }
    }

    if (isStopCoda(effectiveCoda, effectiveCodaLen) && m_tone != 0 && m_tone != 1 && m_tone != 5) {
        return false;
    }

    if (hasDoubleO(rawLower, m_rawLen) && effectiveCodaLen > 0 && !isValidDoubleOCoda(effectiveCoda, effectiveCodaLen)) {
        return false;
    }

    if (m_rawLen >= 2 && rawLower[0] == L'w') {
        wchar_t second = rawLower[1];
        if (second == L'h' || second == L'o' || second == L'e' || (second == L'r' && m_rawLen >= 3) || second == L'l' ||
            (second == L'i' && m_rawLen >= 3 && rawLower[2] != L'u')) {
            return false;
        }
        if ((second == L'a' || second == L'u') && m_rawLen == 2) {
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
        const bool isFlexToneOnset =
            (m_grammarProfile == 1 && m_rawLen >= 3 &&
             !(m_rawLen == 3 && rawLower[0] == L'r' && rawLower[1] == L's' && rawLower[2] == L'a') &&
             !(m_rawLen >= 4 && rawLower[0] == L't' && (rawLower[1] == L's' || rawLower[1] == L'z') && rawLower[2] == L'a' && rawLower[3] == L'r') &&
             !(m_rawLen >= 4 && rawLower[0] == L'h' && rawLower[1] == L'r' && rawLower[2] == L'e' && rawLower[3] == L'f'));
        if (!hasVowelShape && !isFlexToneOnset && !(m_rawLen == 3 && rawLower[0] == L'm' && rawLower[1] == L'x' && rawLower[2] == L'i')) {
            return false;
        }
    }

    return true;
}

bool isPostCodaCircumflexEnglishWord(const wchar_t *lower, int len) {
    if (len < 4 || len > 7) return false;
    static const wchar_t *const kWords[] = {
        L"coco", L"cocos", L"como", L"data", L"dense", L"donor", L"donors",
        L"gene", L"genes", L"genre", L"goto", L"honor", L"honors", L"lana",
        L"mama", L"mana", L"meme", L"memes", L"mete", L"meter", L"meters",
        L"metes", L"momo", L"momos", L"mono", L"monos", L"moto", L"motor",
        L"motors", L"motos", L"nana", L"papa", L"pete", L"peter", L"petes",
        L"photo", L"photos", L"scene", L"scenes", L"sense", L"senses",
        L"tata", L"tense", L"tenses", L"theme", L"themed", L"themer",
        L"themes", L"toto", L"xanax"
    };
    for (const wchar_t *w : kWords) {
        int i = 0;
        while (i < len && w[i] != 0 && lower[i] == w[i]) ++i;
        if (i == len && w[i] == 0) return true;
    }
    return false;
}

bool isTunCollocationPrecedingHead(const wchar_t *w, int len) {
    if (len <= 0) return false;
    if (len == 3 && w[0] == L'l' && (w[1] == static_cast<wchar_t>(0x00F9) || w[1] == static_cast<wchar_t>(0x1EE7)) && w[2] == L'n') {
        return true; // "lùn", "lủn"
    }
    if (len == 3 && w[0] == L'n' && w[1] == L'h' && w[2] == static_cast<wchar_t>(0x1ECF)) {
        return true; // "nhỏ"
    }
    if (len == 4 && w[0] == L'n' && w[1] == L'g' && w[2] == static_cast<wchar_t>(0x1EAF) && w[3] == L'n') {
        return true; // "ngắn"
    }
    if (len == 3 && w[0] == L'c' && w[1] == static_cast<wchar_t>(0x1EE5) && w[2] == L't') {
        return true; // "cụt"
    }
    if (len == 4 && w[0] == L'l' && w[1] == L'u' &&
        ((w[2] == L'f' && w[3] == L'n') || (w[2] == L'n' && w[3] == L'f') ||
         (w[2] == L'r' && w[3] == L'n') || (w[2] == L'n' && w[3] == L'r'))) {
        return true;
    }
    if (len == 4 && w[0] == L'n' && w[1] == L'h' && w[2] == L'o' && w[3] == L'r') {
        return true;
    }
    return false;
}

bool isSpacePrefixStarter(const wchar_t *lower, int len) {
    if (len == 2) {
        return std::wmemcmp(lower, L"is", 2) == 0;
    }
    if (len == 3) {
        return std::wmemcmp(lower, L"his", 3) == 0 ||
               std::wmemcmp(lower, L"her", 3) == 0 ||
               std::wmemcmp(lower, L"was", 3) == 0 ||
               std::wmemcmp(lower, L"has", 3) == 0 ||
               std::wmemcmp(lower, L"car", 3) == 0;
    }
    if (len == 4) {
        return std::wmemcmp(lower, L"this", 4) == 0 ||
               std::wmemcmp(lower, L"here", 4) == 0 ||
               std::wmemcmp(lower, L"test", 4) == 0 ||
               std::wmemcmp(lower, L"best", 4) == 0 ||
               std::wmemcmp(lower, L"last", 4) == 0 ||
               std::wmemcmp(lower, L"list", 4) == 0 ||
               std::wmemcmp(lower, L"cost", 4) == 0 ||
               std::wmemcmp(lower, L"host", 4) == 0;
    }
    if (len == 5) {
        return std::wmemcmp(lower, L"there", 5) == 0;
    }
    return false;
}

bool isVietnameseCompoundContinuationAfterStarter(
    const wchar_t *starterLower, int starterLen,
    const wchar_t *secondCompLower, int secondCompLen,
    const wchar_t *secondRawLower, int secondRawLen
) {
    auto eq = [](const wchar_t *s, int slen, const wchar_t *lit, int llen) {
        return slen == llen && std::wmemcmp(s, lit, llen) == 0;
    };
    if (eq(starterLower, starterLen, L"this", 4)) {
        return eq(secondCompLower, secondCompLen, L"sinh", 4) || eq(secondRawLower, secondRawLen, L"sinh", 4) ||
               eq(secondCompLower, secondCompLen, L"cho", 3)  || eq(secondRawLower, secondRawLen, L"cho", 3) ||
               eq(secondRawLower, secondRawLen, L"duj", 3)    || eq(secondRawLower, secondRawLen, L"toots", 5) ||
               eq(secondRawLower, secondRawLen, L"thaan", 5)  || eq(secondRawLower, secondRawLen, L"mangj", 5) ||
               eq(secondRawLower, secondRawLen, L"ddieemr", 7) || eq(secondRawLower, secondRawLen, L"nghieemj", 8);
    }
    if (eq(starterLower, starterLen, L"his", 3)) {
        return eq(secondRawLower, secondRawLen, L"huwngr", 6) ||
               eq(secondRawLower, secondRawLen, L"hoays", 5)  ||
               eq(secondRawLower, secondRawLen, L"hoaj", 4)   ||
               eq(secondRawLower, secondRawLen, L"kichj", 5)  ||
               eq(secondRawLower, secondRawLen, L"mawts", 5);
    }
    if (eq(starterLower, starterLen, L"was", 3) || eq(starterLower, starterLen, L"has", 3)) {
        return eq(secondCompLower, secondCompLen, L"ra", 2)  || eq(secondRawLower, secondRawLen, L"ra", 2) ||
               eq(secondCompLower, secondCompLen, L"gan", 3) || eq(secondRawLower, secondRawLen, L"gan", 3) ||
               eq(secondRawLower, secondRawLen, L"leej", 4)  ||
               eq(secondRawLower, secondRawLen, L"maus", 4)  ||
               eq(secondRawLower, secondRawLen, L"maatj", 5) ||
               eq(secondRawLower, secondRawLen, L"hoocs", 5) ||
               eq(secondRawLower, secondRawLen, L"mieengj", 7) ||
               eq(secondRawLower, secondRawLen, L"moofm", 5);
    }
    if (eq(starterLower, starterLen, L"there", 5)) {
        return eq(secondCompLower, secondCompLen, L"thao", 4) || eq(secondRawLower, secondRawLen, L"thao", 4) ||
               eq(secondRawLower, secondRawLen, L"ducj", 4) ||
               eq(secondRawLower, secondRawLen, L"hieenj", 6) ||
               eq(secondRawLower, secondRawLen, L"loaij", 5) ||
               eq(secondRawLower, secondRawLen, L"chaats", 6) ||
               eq(secondRawLower, secondRawLen, L"tichs", 5) ||
               eq(secondRawLower, secondRawLen, L"trangj", 6) ||
               eq(secondRawLower, secondRawLen, L"dieenj", 6) ||
               eq(secondRawLower, secondRawLen, L"leej", 4) ||
               eq(secondRawLower, secondRawLen, L"thuwcs", 6);
    }
    if (eq(starterLower, starterLen, L"last", 4)) {
        return eq(secondCompLower, secondCompLen, L"sau", 3) || eq(secondRawLower, secondRawLen, L"sau", 3) ||
               eq(secondRawLower, secondRawLen, L"nuwax", 5) ||
               eq(secondRawLower, secondRawLen, L"cawts", 5);
    }
    if (eq(starterLower, starterLen, L"best", 4)) {
        return eq(secondRawLower, secondRawLen, L"nhef", 4);
    }
    if (eq(starterLower, starterLen, L"test", 4)) {
        return eq(secondRawLower, secondRawLen, L"moong", 5) ||
               eq(secondRawLower, secondRawLen, L"ddits", 5);
    }
    if (eq(starterLower, starterLen, L"car", 3)) {
        return !(eq(secondRawLower, secondRawLen, L"is", 2) ||
                 eq(secondRawLower, secondRawLen, L"was", 3) ||
                 eq(secondRawLower, secondRawLen, L"has", 3) ||
                 eq(secondRawLower, secondRawLen, L"had", 3) ||
                 eq(secondRawLower, secondRawLen, L"will", 4) ||
                 eq(secondRawLower, secondRawLen, L"can", 3) ||
                 eq(secondRawLower, secondRawLen, L"in", 2) ||
                 eq(secondRawLower, secondRawLen, L"on", 2) ||
                 eq(secondRawLower, secondRawLen, L"at", 2) ||
                 eq(secondRawLower, secondRawLen, L"to", 2) ||
                 eq(secondRawLower, secondRawLen, L"from", 4) ||
                 eq(secondRawLower, secondRawLen, L"with", 4) ||
                 eq(secondRawLower, secondRawLen, L"for", 3) ||
                 eq(secondRawLower, secondRawLen, L"of", 2) ||
                 eq(secondRawLower, secondRawLen, L"and", 3) ||
                 eq(secondRawLower, secondRawLen, L"or", 2) ||
                 eq(secondRawLower, secondRawLen, L"park", 4) ||
                 eq(secondRawLower, secondRawLen, L"key", 3) ||
                 eq(secondRawLower, secondRawLen, L"keys", 4) ||
                 eq(secondRawLower, secondRawLen, L"door", 4) ||
                 eq(secondRawLower, secondRawLen, L"seat", 4) ||
                 eq(secondRawLower, secondRawLen, L"wash", 4) ||
                 eq(secondRawLower, secondRawLen, L"crash", 5) ||
                 eq(secondRawLower, secondRawLen, L"driver", 6) ||
                 eq(secondRawLower, secondRawLen, L"engine", 6) ||
                 eq(secondRawLower, secondRawLen, L"rental", 6) ||
                 eq(secondRawLower, secondRawLen, L"owner", 5));
    }
    return false;
}

bool isPostDigitTechnicalUnitSuffix(const wchar_t *lower, int len) {
    if (len < 2 || len > 5) return false;
    auto eq = [&](const wchar_t *lit, int litLen) {
        return len == litLen && std::wmemcmp(lower, lit, static_cast<size_t>(litLen)) == 0;
    };
    return eq(L"us", 2) || eq(L"as", 2) || eq(L"es", 2) || eq(L"is", 2) || eq(L"os", 2) ||
           eq(L"ex", 2) || eq(L"mos", 3) || eq(L"deg", 3) || eq(L"rad", 3) || eq(L"rem", 3) ||
           eq(L"sec", 3) || eq(L"min", 3) || eq(L"hrs", 3) || eq(L"yrs", 3) ||
           eq(L"degs", 4) || eq(L"rads", 4) || eq(L"rems", 4) || eq(L"secs", 4) ||
           eq(L"mins", 4) || eq(L"turn", 4) || eq(L"turns", 5);
}

int partitionMixedCaseSubwords(const wchar_t *raw, int rawLen, int segStarts[16], int segLens[16]) {
    if (rawLen < 4 || rawLen >= WindowsNativeEngine::kMaxWordTokens) return 0;
    bool hasUpper = false;
    bool hasLower = false;
    bool restAllLower = true;
    for (int i = 0; i < rawLen; ++i) {
        const wchar_t c = raw[i];
        if (c >= L'A' && c <= L'Z') {
            hasUpper = true;
            if (i > 0) restAllLower = false;
        } else if (c >= L'a' && c <= L'z') {
            hasLower = true;
        } else {
            return 0;
        }
    }
    if (!hasUpper || !hasLower) return 0;
    if (raw[0] >= L'A' && raw[0] <= L'Z' && restAllLower) return 0;

    int segCount = 0;
    int curStart = 0;
    int i = 0;

    int leadUpper = 0;
    while (leadUpper < rawLen && raw[leadUpper] >= L'A' && raw[leadUpper] <= L'Z') {
        ++leadUpper;
    }
    if (leadUpper >= 3 && leadUpper < rawLen && raw[leadUpper] >= L'a' && raw[leadUpper] <= L'z') {
        int splitAt = leadUpper - 1;
        if (leadUpper >= 4 && raw[leadUpper - 2] == L'D' && raw[leadUpper - 1] == L'D') {
            splitAt = leadUpper - 2;
        }
        if (splitAt >= 2) {
            segStarts[segCount] = 0;
            segLens[segCount] = splitAt;
            ++segCount;
            curStart = splitAt;
            i = splitAt;
        }
    }

    bool curSegHasVowel = false;
    for (; i < rawLen; ++i) {
        const wchar_t c = raw[i];
        const bool isUpper = (c >= L'A' && c <= L'Z');
        if (i > curStart && isUpper && (raw[i - 1] >= L'a' && raw[i - 1] <= L'z') && curSegHasVowel) {
            if (segCount >= 15) return 0;
            segStarts[segCount] = curStart;
            segLens[segCount] = i - curStart;
            ++segCount;
            curStart = i;
            curSegHasVowel = NativeEngineState::isAsciiBaseVowel(toLowerAscii(c));
        } else {
            if (NativeEngineState::isAsciiBaseVowel(toLowerAscii(c))) {
                curSegHasVowel = true;
            }
        }
    }
    if (curStart < rawLen) {
        if (segCount >= 16) return 0;
        segStarts[segCount] = curStart;
        segLens[segCount] = rawLen - curStart;
        ++segCount;
    }
    if (segCount < 2) return 0;
    for (int s = 0; s < segCount; ++s) {
        const int len = segLens[s];
        if (len < 2) return 0;
        const wchar_t *seg = raw + segStarts[s];
        bool allUpper = true;
        bool allLower = true;
        bool hasVowel = false;
        for (int j = 0; j < len; ++j) {
            const wchar_t c = seg[j];
            if (!(c >= L'A' && c <= L'Z')) allUpper = false;
            if (!(c >= L'a' && c <= L'z')) allLower = false;
            if (NativeEngineState::isAsciiBaseVowel(toLowerAscii(c))) hasVowel = true;
        }
        if (allUpper) continue;
        if (!hasVowel) return 0;
        if (s == 0 && allLower) continue;
        if (!(seg[0] >= L'A' && seg[0] <= L'Z')) return 0;
        const int tailStart = (len >= 3 && seg[0] == L'D' && seg[1] == L'D') ? 2 : 1;
        for (int j = tailStart; j < len; ++j) {
            if (!(seg[j] >= L'a' && seg[j] <= L'z')) return 0;
        }
    }
    return segCount;
}

bool NativeEngineState::shouldRestoreRawEnglish() const {
    if (!m_smartBilingual || !hasVietnameseTransformation() || m_suppressEnglishRestoreAfterBackspace) return false;

    wchar_t rawLower[kMaxWordTokens]{};
    for (int i = 0; i < m_rawLen; ++i) {
        rawLower[i] = toLowerAscii(m_rawWord[i]);
    }

    if (m_afterDigit) {
        bool rawHasAsciiVowel = false;
        for (int i = 0; i < m_rawLen; ++i) {
            if (isAsciiBaseVowel(rawLower[i])) {
                rawHasAsciiVowel = true;
                break;
            }
        }
        const bool isCurrencyStrokeD =
            (m_rawLen == 2 && rawLower[0] == L'd' && rawLower[1] == L'd');
        if ((!rawHasAsciiVowel && !isCurrencyStrokeD) ||
            isPostDigitTechnicalUnitSuffix(rawLower, m_rawLen)) {
            return true;
        }
    }

    if (m_rawLen == 3 && m_rawWord[0] == L'c' && m_rawWord[1] == L'o' && m_rawWord[2] == L's') {
        return m_mathContextWordsRemaining > 0 || m_precededByTechDelimiter ||
               m_pendingBoundaryCp == '(' || m_pendingBoundaryCp == '[';
    }

    if (m_nonAdjacentCircumflex && isPostCodaCircumflexEnglishWord(rawLower, m_rawLen)) {
        return true;
    }

    if (!isValidVietnameseSyllable()) {
        if (m_precededByLeadingSlash && isLeadingSlashCommandOrPathToken(rawLower, m_rawLen)) {
            return true;
        }
        if (m_classicOrVniEscape && !isExcludedTripleOrWwwEscape(rawLower, m_rawLen)) {
            return false;
        }
        if (m_telexToneEscape && !m_inVietnameseContext &&
            (isDefaultNoContextShortEnglishWord(rawLower, m_rawLen) ||
             (m_inEnglishContext && m_rawLen == 4 && rawLower[0] == L'm' && rawLower[1] == L'i' && rawLower[2] == L'x' && rawLower[3] == L'x'))) {
            return true;
        }
        if ((m_telexToneEscape || m_overflowLocked || isOpenSameVowelExtension() || isSingleModifiedVowelOverflow()) &&
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

    const bool isIsaInVnContext =
        m_inVietnameseContext && m_rawLen == 3 &&
        rawLower[0] == L'i' && rawLower[1] == L's' && rawLower[2] == L'a';
    if (!isIsaInVnContext && isUnconditionalEnglishWord(rawLower, m_rawLen)) {
        return true;
    }
    if (m_precededByLeadingSlash && isLeadingSlashCommandOrPathToken(rawLower, m_rawLen)) {
        return true;
    }
    if (!m_inVietnameseContext && isDefaultNoContextShortEnglishWord(rawLower, m_rawLen)) {
        return true;
    }
    if (m_prevCollisionRawLen > 0) {
        wchar_t prevLower[16]{};
        for (int i = 0; i < m_prevCollisionRawLen && i < 15; ++i) {
            prevLower[i] = toLowerAscii(m_prevCollisionRaw[i]);
        }
        if (isSpacePrefixStarter(prevLower, m_prevCollisionRawLen) &&
            (isDefaultNoContextShortEnglishWord(rawLower, m_rawLen) || isContextEnglishCollisionWord(rawLower, m_rawLen)) &&
            !isVietnameseCompoundContinuationAfterStarter(prevLower, m_prevCollisionRawLen, rawLower, m_rawLen, rawLower, m_rawLen)) {
            return true;
        }
    }
    if (!m_inVietnameseContext &&
        prefersEnglishByOrthographicCase(m_rawWord, rawLower, m_rawLen, m_tone, m_classicOrVniEscape || m_telexToneEscape)) {
        return true;
    }
    if (isContextEnglishCollisionWord(rawLower, m_rawLen)) {
        if (m_precededByTechDelimiter) return true;
        if (m_pendingBoundaryCp == '_' || m_pendingBoundaryCp == '/' || m_pendingBoundaryCp == '.' ||
            (m_inputMethod == InputMethod::Telex && isAsciiDigit(m_pendingBoundaryCp))) return true;
        if (m_rawLen == 4 && rawLower[0] == L't' && rawLower[1] == L'u' && rawLower[2] == L'r' && rawLower[3] == L'n') {
            return !m_lastWordWasTunCollocationHead;
        }
        if (m_rawLen == 3 && rawLower[0] == L's' && rawLower[1] == L'e' && rawLower[2] == L'x') {
            if (m_lastWordWasSexLoanwordHead) return true;
        }
        if (m_hadVietnameseInSentence && !m_lastWordWasEnglishAnchor &&
            m_rawLen == 3 && rawLower[0] == L'n' && rawLower[1] == L'o' && rawLower[2] == L's') {
            return false;
        }
        if (isSyntheticInflectionTrapWord(rawLower, m_rawLen)) {
            return m_lastWordWasEnglishAnchor;
        }
        if (m_inEnglishContext) return true;
    }
    return false;
}

bool NativeEngineState::tryComposeMixedCaseCompound(wchar_t *outBuf, int maxLen) const {
    if (m_inSubwordEval || !m_smartBilingual || m_inputMethod != InputMethod::Telex ||
        m_precededByTechDelimiter || m_precededByLeadingSlash ||
        m_suppressEnglishRestoreAfterBackspace || isValidVietnameseSyllable()) {
        return false;
    }

    int segStarts[16]{};
    int segLens[16]{};
    const int segCount = partitionMixedCaseSubwords(m_rawWord, m_rawLen, segStarts, segLens);
    if (segCount < 2) return false;

    wchar_t combined[kMaxWordTokens]{};
    int combinedLen = 0;
    bool compoundHasNonAscii = false;
    bool compoundRestoredEscapeSubword = false;

    for (int s = 0; s < segCount; ++s) {
        const wchar_t *segPtr = m_rawWord + segStarts[s];
        const int segLen = segLens[s];
        bool segAllCaps = true;
        for (int j = 0; j < segLen; ++j) {
            if (!(segPtr[j] >= L'A' && segPtr[j] <= L'Z')) {
                segAllCaps = false;
                break;
            }
        }
        if (segAllCaps) {
            if (combinedLen + segLen >= kMaxWordTokens) return false;
            for (int j = 0; j < segLen; ++j) {
                combined[combinedLen++] = segPtr[j];
            }
            continue;
        }

        wchar_t segLower[kMaxWordTokens]{};
        for (int j = 0; j < segLen; ++j) {
            segLower[j] = toLowerAscii(segPtr[j]);
        }
        if (isExtendedEnglishEscapeWord(segLower, segLen)) {
            compoundRestoredEscapeSubword = true;
        }
        if (isEnglishContextAnchor(segLower, segLen) || isSpacePrefixStarter(segLower, segLen)) {
            if (combinedLen + segLen >= kMaxWordTokens) return false;
            for (int j = 0; j < segLen; ++j) {
                combined[combinedLen++] = segPtr[j];
            }
            continue;
        }

        NativeEngineState sub{};
        sub.m_inputMethod = m_inputMethod;
        sub.m_grammarProfile = m_grammarProfile;
        sub.m_smartBilingual = true;
        sub.m_modernOrthography = m_modernOrthography;
        sub.m_quickTelex = m_quickTelex;
        sub.m_relaxedCoda = false;
        sub.m_inEnglishContext = true;
        sub.m_lastWordWasEnglishAnchor = true;
        sub.m_inSubwordEval = true;
        for (int j = 0; j < segLen; ++j) {
            sub.feedChar(static_cast<uint32_t>(segPtr[j]));
        }

        bool segHasNonAscii = false;
        for (int j = 0; j < sub.m_displayedLen; ++j) {
            if (sub.m_displayed[j] > 0x7F) {
                segHasNonAscii = true;
                break;
            }
        }
        if (segHasNonAscii) {
            if (!sub.isValidVietnameseSyllable()) {
                return false;
            }
            compoundHasNonAscii = true;
        }
        if (combinedLen + sub.m_displayedLen >= kMaxWordTokens) return false;
        for (int j = 0; j < sub.m_displayedLen; ++j) {
            combined[combinedLen++] = sub.m_displayed[j];
        }
    }

    if ((!compoundHasNonAscii && !compoundRestoredEscapeSubword) || combinedLen <= 0 || combinedLen >= maxLen) {
        return false;
    }
    for (int i = 0; i < combinedLen; ++i) {
        outBuf[i] = combined[i];
    }
    outBuf[combinedLen] = 0;
    return true;
}

int NativeEngineState::composeOutputWord(wchar_t *outBuf, int maxLen) const {
    if (tryComposeMixedCaseCompound(outBuf, maxLen)) {
        int len = 0;
        while (len < maxLen - 1 && outBuf[len] != 0) ++len;
        return len;
    }
    wchar_t rawLower[kMaxWordTokens]{};
    for (int i = 0; i < m_rawLen; ++i) {
        rawLower[i] = toLowerAscii(m_rawWord[i]);
    }
    if (allRawCharsAreW() ||
        (m_nonAdjacentCircumflex && isPostCodaCircumflexEnglishWord(rawLower, m_rawLen)) ||
        (m_smartBilingual && hasVietnameseTransformation() && shouldRestoreRawEnglish())) {
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

    // 2. 'd' -> 'đ' and Stroke-D Cancellation ('duocwjd' -> 'được', 'được' + 'd' -> 'dược')
    if (lowerCh == L'd') {
        if (m_shapeCancelledOnce && m_lastShapeKey == L'd') {
            if (hasCompoundUoOrStrokeD() || isValidVietnameseSyllable()) {
                m_overflowLocked = true;
            }
            if (m_literalTailLen < kMaxWordTokens - 1) {
                m_literalTail[m_literalTailLen++] = ch;
                m_literalTail[m_literalTailLen] = 0;
            }
            return true;
        }
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
        if (m_tokenLen > 0 && m_tokens[0].baseLower == L'd' && vStart == 1) {
            wchar_t codaStr[16]{};
            int codaLen = 0;
            bool codaOnlyConsonants = true;
            for (int i = vEnd + 1; i < m_tokenLen; ++i) {
                if (isAsciiBaseVowel(m_tokens[i].baseLower)) {
                    codaOnlyConsonants = false;
                    break;
                }
                if (codaLen < 15) codaStr[codaLen++] = m_tokens[i].baseLower;
            }
            const bool validCoda = !hasCoda || (codaOnlyConsonants && isValidFinalCoda(codaStr, codaLen));
            if (validCoda) {
                bool hasVnFeature = (m_tone != 0);
                for (int i = vStart; i <= vEnd; ++i) {
                    if (m_tokens[i].shape != 0) hasVnFeature = true;
                }
                if (!hasVnFeature && (vEnd - vStart + 1) >= 2 &&
                    m_tokens[vStart].baseLower == L'u' && m_tokens[vStart + 1].baseLower == L'o') {
                    hasVnFeature = true;
                }
                if (m_tokens[0].shape == 0 && hasVnFeature && !m_nonAdjacentCircumflex) {
                    wchar_t rawLower[kMaxWordTokens]{};
                    for (int i = 0; i < m_rawLen; ++i) rawLower[i] = toLowerAscii(m_rawWord[i]);
                    if (!isUnconditionalEnglishWord(rawLower, m_rawLen) &&
                        !isContextEnglishCollisionWord(rawLower, m_rawLen)) {
                        m_tokens[0].shape = 4;
                        m_lastShapeKey = L'd';
                        m_shapeCancelledOnce = false;
                        return true;
                    }
                } else if (m_tokens[0].shape == 4 && (hasVnFeature || isValidVietnameseSyllable())) {
                    saveUndoSnapshot();
                    m_tokens[0].shape = 0;
                    m_lastShapeKey = L'd';
                    m_shapeCancelledOnce = true;
                    m_overflowLocked = true;
                    return true;
                }
            }
        }
        return false;
    }

    // 3. Circumflex 'a' -> 'â', 'e' -> 'ê', 'o' -> 'ô' AND Vowel-Shape Cancellation (088fc45)
    if (lowerCh == L'a' || lowerCh == L'e' || lowerCh == L'o') {
        // If we already cancelled a vowel shape once on the immediately preceding key, the 2nd extra press appends literally!
        if (m_shapeCancelledOnce && m_lastShapeKey == lowerCh) {
            if (hasCompoundUoOrStrokeD() || isValidVietnameseSyllable()) {
                m_overflowLocked = true;
            }
            if (m_literalTailLen < kMaxWordTokens - 1) {
                m_literalTail[m_literalTailLen++] = ch;
                m_literalTail[m_literalTailLen] = 0;
            }
            return true;
        }

        // Mutual exclusion reshape: 'trương'/'trường'/'được' + 'o' -> 'truông'/'truồng'/'đuộc' (ươ -> uô)
        if (lowerCh == L'o' && vStart != -1) {
            for (int i = vStart; i < vEnd; ++i) {
                if (m_tokens[i].baseLower == L'u' && m_tokens[i].shape == 2 &&
                    m_tokens[i + 1].baseLower == L'o' && m_tokens[i + 1].shape == 2) {
                    saveUndoSnapshot();
                    m_tokens[i].shape = 0;
                    m_tokens[i + 1].shape = 1;
                    if (!hasCoda || isValidVietnameseSyllable()) {
                        m_lastShapeKey = L'o';
                        m_lastToneKey = 0;
                        m_shapeCancelledOnce = false;
                        m_uHornFromOwnW = false;
                        return true;
                    }
                    m_tokens[i].shape = 2;
                    m_tokens[i + 1].shape = 2;
                    m_hasUndoSnapshot = false;
                    break;
                }
            }
            // Single 'ơ' + 'o' -> 'ô' (e.g. 'cơ' + 'o' -> 'cô', 'hơn' + 'o' -> 'hôn', 'hớn' + 'o' -> 'hốn')
            for (int i = vStart; i <= vEnd; ++i) {
                if (m_tokens[i].baseLower == L'o' && m_tokens[i].shape == 2) {
                    saveUndoSnapshot();
                    m_tokens[i].shape = 1;
                    if (!hasCoda || isValidVietnameseSyllable()) {
                        m_lastShapeKey = L'o';
                        m_lastToneKey = 0;
                        m_shapeCancelledOnce = false;
                        return true;
                    }
                    m_tokens[i].shape = 2;
                    m_hasUndoSnapshot = false;
                    break;
                }
            }
        }

        // Mutual exclusion reshape: 'căn'/'cắm' + 'a' -> 'cân'/'cấm' (ă -> â)
        if (lowerCh == L'a' && vStart != -1) {
            for (int i = vStart; i <= vEnd; ++i) {
                if (m_tokens[i].baseLower == L'a' && m_tokens[i].shape == 3) {
                    saveUndoSnapshot();
                    m_tokens[i].shape = 1;
                    if (!hasCoda || isValidVietnameseSyllable()) {
                        m_lastShapeKey = L'a';
                        m_lastToneKey = 0;
                        m_shapeCancelledOnce = false;
                        return true;
                    }
                    m_tokens[i].shape = 3;
                    m_hasUndoSnapshot = false;
                    break;
                }
            }
        }

        // Check if vowel in vStart..vEnd already has circumflex (shape == 1) for lowerCh:
        if (vStart != -1 && !(hasCoda && m_tone != 0) && !(m_relaxedCodaExpanded && hasCoda)) {
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
                    if (!hasCoda && m_tone != 0 && i == m_tokenLen - 1 && m_nonAdjacentCircumflex) {
                        return false;
                    }
                    saveUndoSnapshot();
                    m_tokens[i].shape = 0;
                    m_lastShapeKey = lowerCh;
                    m_shapeCancelledOnce = true;
                    return true;
                }
            }
        }

        bool hasPriorCircumflexOrBreve = false;
        if (vStart != -1) {
            for (int i = vStart; i <= vEnd; ++i) {
                if (m_tokens[i].shape == 1 || m_tokens[i].shape == 3 ||
                    ((lowerCh == L'a' || lowerCh == L'e') && m_tokens[i].shape == 2)) {
                    hasPriorCircumflexOrBreve = true;
                    break;
                }
            }
        }

        // Adjacent vowel doubling (Including late vowel modification after tone: 'đẻ' + 'e' -> 'để', 'đó' + 'o' -> 'đố', 'cá' + 'a' -> 'cấ')
        if (!hasPriorCircumflexOrBreve && m_tokenLen > 0 && m_tokens[m_tokenLen - 1].baseLower == lowerCh && m_tokens[m_tokenLen - 1].shape == 0) {
            const bool isContiguousDouble = (m_rawLen >= 2 && toLowerAscii(m_rawWord[m_rawLen - 2]) == lowerCh);
            if (!(vEnd > vStart && m_tone != 0 && !isContiguousDouble)) {
                m_tokens[m_tokenLen - 1].shape = 1;
                m_lastShapeKey = lowerCh;
                m_lastToneKey = 0;
                m_shapeCancelledOnce = false;
                if (!isContiguousDouble) {
                    m_nonAdjacentCircumflex = true;
                }
                return true;
            }
        }

        // Non-adjacent SEN Flex circumflex (e.g. 'ama' -> 'âm', 'eme' -> 'êm', 'cana' -> 'cân', 'toiso' -> 'tối')
        if (!hasPriorCircumflexOrBreve && vStart != -1 && (hasCoda || vEnd > vStart)) {
            wchar_t codaStr[16]{};
            int codaLen = 0;
            for (int i = vEnd + 1; i < m_tokenLen && codaLen < 15; ++i) {
                codaStr[codaLen++] = m_tokens[i].baseLower;
            }
            if (isValidFinalCoda(codaStr, codaLen)) {
                const int maxCircIdx = hasCoda ? vEnd : (vEnd - 1);
                for (int i = vStart; i <= maxCircIdx; ++i) {
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
            if (hasCompoundUoOrStrokeD() || isValidVietnameseSyllable()) {
                m_overflowLocked = true;
            }
            if (m_literalTailLen < kMaxWordTokens - 1) {
                m_literalTail[m_literalTailLen++] = ch;
                m_literalTail[m_literalTailLen] = 0;
            }
            return true;
        }

        if (vStart != -1) {
            // Absorb 2nd 'w' in 'dduwowng' / 'buwsowm' / 'muwfowi' ('ư' got horn from 1st 'w', then 'o' was typed and upgraded to 'ươ', then user immediately typed 'w' for 'ơ' before coda/offglide)
            if (!hasCoda && vEnd == m_tokenLen - 1) {
                for (int i = vStart; i < vEnd; ++i) {
                    if (m_tokens[i].baseLower == L'u' && m_tokens[i].shape == 2 &&
                        m_tokens[i + 1].baseLower == L'o' && m_tokens[i + 1].shape == 2 &&
                        (i + 1 == vEnd) && m_uHornFromOwnW && m_lastShapeKey != L'w') {
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

            // Mutual exclusion reshape: 'cân'/'cấm' + 'w' -> 'căn'/'cắm', 'côn'/'đuộc' + 'w' -> 'cơn'/'được'
            if (!(hasCoda && m_tone != 0 && m_nonAdjacentCircumflex)) {
                for (int i = vStart; i <= vEnd; ++i) {
                    if (m_tokens[i].baseLower == L'a' && m_tokens[i].shape == 1) {
                        saveUndoSnapshot();
                        m_tokens[i].shape = 3;
                        if (!hasCoda || isValidVietnameseSyllable()) {
                            m_lastShapeKey = L'w';
                            m_lastToneKey = 0;
                            m_shapeCancelledOnce = false;
                            return true;
                        }
                        m_tokens[i].shape = 1;
                        m_hasUndoSnapshot = false;
                        break;
                    }
                    if (m_tokens[i].baseLower == L'o' && m_tokens[i].shape == 1) {
                        saveUndoSnapshot();
                        const bool hasPrevU = (i > vStart && m_tokens[i - 1].baseLower == L'u');
                        const int prevUShape = hasPrevU ? m_tokens[i - 1].shape : 0;
                        if (hasPrevU) m_tokens[i - 1].shape = 2;
                        m_tokens[i].shape = 2;
                        if (!hasCoda || isValidVietnameseSyllable()) {
                            m_lastShapeKey = L'w';
                            m_lastToneKey = 0;
                            m_shapeCancelledOnce = false;
                            m_uHornFromOwnW = false;
                            return true;
                        }
                        if (hasPrevU) m_tokens[i - 1].shape = prevUShape;
                        m_tokens[i].shape = 1;
                        m_hasUndoSnapshot = false;
                        break;
                    }
                }
            }

            if (alreadyHasHornOrBreve) {
                // Immediate double 'ww' at word start ('ww' -> 'w', 'wwus' -> 'wus')
                if (m_rawLen == 2 && (m_rawWord[0] == L'w' || m_rawWord[0] == L'W')) {
                    m_tokenLen = 0;
                    m_literalLock = true;
                    m_classicOrVniEscape = true;
                    m_escapeLockTokenLen = 1;
                    return false;
                }
                // Classic open untoned single or compound vowel ('oww' -> 'ow', 'tuoww' -> 'tuow', 'muaww' -> 'muaw', 'cuuww' -> 'cuuw', 'hoaww' -> 'hoaw', 'huouww' -> 'huouw', 'tww' -> 'tw', 'nhww' -> 'nhw')
                const bool isContiguousDoubleW = (m_rawLen >= 2 && toLowerAscii(m_rawWord[m_rawLen - 2]) == L'w');
                if (!hasCoda && m_tone == 0 && m_lastShapeKey == L'w' && isContiguousDoubleW) {
                    const bool isSyntheticUHorn =
                        (vStart == vEnd && vStart == m_tokenLen - 1 &&
                         m_tokens[vStart].baseLower == L'u' && m_uHornFromOwnW && m_rawLen >= 3 &&
                         (toLowerAscii(m_rawWord[m_rawLen - 3]) != L'u' ||
                          (vStart == 2 && m_tokens[0].baseLower == L'q' && m_tokens[1].baseLower == L'u')));
                    if (isSyntheticUHorn) {
                        --m_tokenLen;
                    } else {
                        for (int i = vStart; i <= vEnd; ++i) {
                            if (m_tokens[i].shape == 2 || m_tokens[i].shape == 3) {
                                m_tokens[i].shape = 0;
                            }
                        }
                    }
                    m_literalLock = true;
                    m_classicOrVniEscape = true;
                    m_escapeLockTokenLen = m_tokenLen + 1;
                    m_uHornFromOwnW = false;
                    return false;
                }
                // Policy 3B+ Semantic Saturation: on completed closed/offglide Vietnamese syllables
                // (e.g. 'được' + 'w' -> 'đượcw', 'trưởng' + 'w' -> 'trưởngw', 'người' + 'w' -> 'ngườiw', 'cửa' + 'w' -> 'cửaw'),
                // lock the syllable stem and emit literal 'w' without stripping horn/breve so Backspace restores 'được'/'trưởng'.
                const bool stemWasValidVn = rawWordStartsNonW() && isValidVietnameseSyllable();
                if ((hasCoda || vEnd > vStart) && stemWasValidVn) {
                    m_telexToneEscape = true;
                    m_overflowLocked = true;
                    if (m_literalTailLen < kMaxWordTokens - 1) {
                        m_literalTail[m_literalTailLen++] = ch;
                        m_literalTail[m_literalTailLen] = 0;
                    }
                    return true;
                }
                // Strip horn/breve on open single-vowel stems while preserving tone, and emit literal 'w' on valid Vietnamese stems
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
                if (stemWasValidVn) {
                    m_telexToneEscape = true;
                    if (hasCompoundUoOrStrokeD()) {
                        m_overflowLocked = true;
                    }
                    if (m_literalTailLen < kMaxWordTokens - 1) {
                        m_literalTail[m_literalTailLen++] = ch;
                        m_literalTail[m_literalTailLen] = 0;
                    }
                }
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
            bool isSingleOnsetPreVowelToneBeforeW = (m_preVowelTone && m_tokenLen == 1 && m_lastToneKey == L's' && m_tokens[0].baseLower != L's');
            if (!hasStrokeD && !isSingleOnsetPreVowelToneBeforeW && isValidInitialOnset(initStr, initLen, false) && m_tokenLen < kMaxWordTokens) {
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
        bool expandedPendingG = false;
        if (m_relaxedCoda && codaLen == 1 && codaStr[0] == L'g' && m_tokenLen < kMaxWordTokens) {
            codaStr[0] = L'n';
            codaStr[1] = L'g';
            codaLen = 2;
            expandedPendingG = true;
        }
        wchar_t effectiveCoda[16]{};
        int effectiveCodaLen = codaLen;
        const bool isEthnicDakLakK =
            codaLen == 1 && codaStr[0] == L'k' && (vEnd == vStart) &&
            m_tokens[vStart].baseLower == L'a' && m_tokens[vStart].shape == 3 &&
            ((vStart == 1 && m_tokens[0].baseLower == L'd' && m_tokens[0].shape == 4) ||
             (vStart == 1 && m_tokens[0].baseLower == L'l'));
        if (m_relaxedCoda && codaLen == 1 && codaStr[0] == L'h' &&
            !(m_rawLen >= 3 && toLowerAscii(m_rawWord[m_rawLen - 3]) == L's' && toLowerAscii(m_rawWord[m_rawLen - 2]) == L'h')) {
            effectiveCoda[0] = L'n';
            effectiveCoda[1] = L'h';
            effectiveCodaLen = 2;
        } else if (isEthnicDakLakK ||
                   (m_relaxedCoda && codaLen == 1 && codaStr[0] == L'k' &&
                    !(m_rawLen >= 3 && toLowerAscii(m_rawWord[m_rawLen - 3]) == L's' && toLowerAscii(m_rawWord[m_rawLen - 2]) == L'k'))) {
            effectiveCoda[0] = L'c';
            effectiveCodaLen = 1;
        } else {
            for (int i = 0; i < codaLen; ++i) effectiveCoda[i] = codaStr[i];
        }
        if (!isValidFinalCoda(effectiveCoda, effectiveCodaLen)) {
            return false;
        }
        if (isStopCoda(effectiveCoda, effectiveCodaLen) && targetTone != 1 && targetTone != 5) {
            return false;
        }
        if (expandedPendingG) {
            const bool gUpper = m_tokens[m_tokenLen - 1].isUpper;
            m_tokens[m_tokenLen - 1] = SyllableToken{ L'n', gUpper, 0 };
            m_tokens[m_tokenLen++] = SyllableToken{ L'g', gUpper, 0 };
            m_relaxedCodaExpanded = true;
        }

        bool hasConsonantOnsetOrShape = (vStart > 0) || m_shapeCancelledOnce || (m_inVietnameseContext && m_tokenLen >= 2);
        if (!hasConsonantOnsetOrShape) {
            for (int i = 0; i < m_tokenLen; ++i) {
                if (m_tokens[i].shape != 0) {
                    hasConsonantOnsetOrShape = true;
                    break;
                }
            }
        }
        if (m_tone == targetTone && m_toneRetainedFromBackspace) {
            m_toneRetainedFromBackspace = false;
            m_lastToneKey = lowerCh;
            m_lastShapeKey = 0;
            return true;
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
            m_toneRetainedFromBackspace = false;
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
        m_toneRetainedFromBackspace = false;
        m_lastToneKey = lowerCh;
        m_lastShapeKey = 0;
        m_shapeCancelledOnce = false;
        return true;
    }

    // SEN Flex pre-vowel tone (e.g. "tseet" -> "tết", "rrung rrinh" -> "rủng rỉnh"):
    // tone key typed right after initial consonant before vowel
    const bool allowPreVowelR = (lowerCh == L'r' && m_tokenLen == 1 && m_tokens[0].baseLower == L'r');
    if (m_grammarProfile == 1 && targetTone != 0 && (lowerCh != L'r' || allowPreVowelR) && vStart == -1 && m_tokenLen > 0 && m_tone == 0) {
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
    if (ch < L'0' || ch > L'9') return false;

    int vStart = -1, vEnd = -1;
    bool hasCoda = false;
    findVowelCluster(vStart, vEnd, hasCoda);

    if (m_literalTailLen > 0) {
        if (ch == L'9' && m_tokenLen > 0 && m_tokens[0].baseLower == L'd' && m_tokens[0].shape == 4) {
            saveUndoSnapshot();
            m_tokens[0].shape = 0;
            m_lastShapeKey = L'9';
            m_shapeCancelledOnce = true;
        } else if (ch == L'6' && vStart != -1) {
            bool cancelled = false;
            for (int i = vStart; i <= vEnd; ++i) {
                wchar_t b = m_tokens[i].baseLower;
                if ((b == L'a' || b == L'e' || b == L'o') && m_tokens[i].shape == 1) {
                    if (!cancelled) {
                        saveUndoSnapshot();
                        cancelled = true;
                    }
                    m_tokens[i].shape = 0;
                }
            }
            if (cancelled) {
                m_lastShapeKey = L'6';
                m_shapeCancelledOnce = true;
            }
        } else if (ch == L'7' && vStart != -1) {
            bool cancelled = false;
            for (int i = vStart; i <= vEnd; ++i) {
                wchar_t b = m_tokens[i].baseLower;
                if ((b == L'o' || b == L'u') && m_tokens[i].shape == 2) {
                    if (!cancelled) {
                        saveUndoSnapshot();
                        cancelled = true;
                    }
                    m_tokens[i].shape = 0;
                }
            }
            if (cancelled) {
                m_lastShapeKey = L'7';
                m_shapeCancelledOnce = true;
            }
        } else if (ch == L'8' && vStart != -1) {
            bool cancelled = false;
            for (int i = vStart; i <= vEnd; ++i) {
                if (m_tokens[i].baseLower == L'a' && m_tokens[i].shape == 3) {
                    if (!cancelled) {
                        saveUndoSnapshot();
                        cancelled = true;
                    }
                    m_tokens[i].shape = 0;
                }
            }
            if (cancelled) {
                m_lastShapeKey = L'8';
                m_shapeCancelledOnce = true;
            }
        } else if (ch >= L'1' && ch <= L'5' && m_tone == static_cast<int>(ch - L'0')) {
            saveUndoSnapshot();
            m_tone = 0;
            m_lastToneKey = 0;
        }
        m_classicOrVniEscape = true;
        if (m_literalTailLen < kMaxWordTokens - 1) {
            m_literalTail[m_literalTailLen++] = ch;
            m_literalTail[m_literalTailLen] = 0;
        }
        return true;
    }

    const bool stemWasValidVn = isValidVietnameseSyllable();

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
                m_shapeCancelledOnce = false;
                return true;
            } else if (m_tokens[0].shape == 4) {
                if (!stemWasValidVn) return false;
                saveUndoSnapshot();
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
        if (!stemWasValidVn) return false;
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
                if (!stemWasValidVn) return false;
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
                    if (!stemWasValidVn) return false;
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
                if (!stemWasValidVn) return false;
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
                if (!stemWasValidVn) return false;
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
        bool expandedPendingG = false;
        if (m_relaxedCoda && codaLen == 1 && codaStr[0] == L'g' && m_tokenLen < kMaxWordTokens) {
            codaStr[0] = L'n';
            codaStr[1] = L'g';
            codaLen = 2;
            expandedPendingG = true;
        }
        wchar_t effectiveCoda[16]{};
        int effectiveCodaLen = codaLen;
        const bool isEthnicDakLakK =
            codaLen == 1 && codaStr[0] == L'k' && (vEnd == vStart) &&
            m_tokens[vStart].baseLower == L'a' && m_tokens[vStart].shape == 3 &&
            ((vStart == 1 && m_tokens[0].baseLower == L'd' && m_tokens[0].shape == 4) ||
             (vStart == 1 && m_tokens[0].baseLower == L'l'));
        if (m_relaxedCoda && codaLen == 1 && codaStr[0] == L'h' &&
            !(m_rawLen >= 3 && toLowerAscii(m_rawWord[m_rawLen - 3]) == L's' && toLowerAscii(m_rawWord[m_rawLen - 2]) == L'h')) {
            effectiveCoda[0] = L'n';
            effectiveCoda[1] = L'h';
            effectiveCodaLen = 2;
        } else if (isEthnicDakLakK ||
                   (m_relaxedCoda && codaLen == 1 && codaStr[0] == L'k' &&
                    !(m_rawLen >= 3 && toLowerAscii(m_rawWord[m_rawLen - 3]) == L's' && toLowerAscii(m_rawWord[m_rawLen - 2]) == L'k'))) {
            effectiveCoda[0] = L'c';
            effectiveCodaLen = 1;
        } else {
            for (int i = 0; i < codaLen; ++i) effectiveCoda[i] = codaStr[i];
        }
        if (!isValidFinalCoda(effectiveCoda, effectiveCodaLen)) {
            return false;
        }
        if (isStopCoda(effectiveCoda, effectiveCodaLen) && targetTone != 1 && targetTone != 5) {
            return false;
        }
        if (expandedPendingG) {
            const bool gUpper = m_tokens[m_tokenLen - 1].isUpper;
            m_tokens[m_tokenLen - 1] = SyllableToken{ L'n', gUpper, 0 };
            m_tokens[m_tokenLen++] = SyllableToken{ L'g', gUpper, 0 };
            m_relaxedCodaExpanded = true;
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
        const bool wasInLeadingSlash = m_precededByLeadingSlash;
        m_pendingBoundaryCp = codepoint;
        if (m_displayedLen > 0) {
            int32_t act = commitWord();
            m_afterDigit = false;
            m_pendingBoundaryCp = 0;
            m_precededByLeadingSlash = (codepoint == '/' && wasInLeadingSlash);
            m_precededByMacroDelimiter = isMacroTechnicalDelimiter(codepoint);
            if (codepoint == '/' || codepoint == '\\' || codepoint == '_') {
                m_precededByTechDelimiter = true;
            } else if (codepoint == ' ' || codepoint == '\t' || codepoint == '\n' || codepoint == '\r') {
                m_precededByTechDelimiter = false;
            }
            if (codepoint == '.' || codepoint == '!' || codepoint == '?' || codepoint == '\n' || codepoint == '\r') {
                m_inVietnameseContext = false;
                m_hadVietnameseInSentence = false;
                m_lastWordWasEnglishAnchor = false;
        m_mathContextWordsRemaining = 0;
            }
            return act;
        }
        m_afterDigit = false;
        m_pendingBoundaryCp = 0;
        m_prevCollisionDisplayedLen = 0;
        m_prevCollisionRawLen = 0;
        m_precededByLeadingSlash = (codepoint == '/');
        m_precededByMacroDelimiter = isMacroTechnicalDelimiter(codepoint);
        if (codepoint == '/' || codepoint == '\\' || codepoint == '_') {
            m_precededByTechDelimiter = true;
        } else if (codepoint == ' ' || codepoint == '\t' || codepoint == '\n' || codepoint == '\r') {
            m_precededByTechDelimiter = false;
        }
        if (codepoint == '.' || codepoint == '!' || codepoint == '?' || codepoint == '\n' || codepoint == '\r') {
            m_inVietnameseContext = false;
            m_hadVietnameseInSentence = false;
            m_lastWordWasEnglishAnchor = false;
        m_mathContextWordsRemaining = 0;
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
        m_precededByMacroDelimiter = isMacroTechnicalDelimiter(codepoint);
        m_precededByLeadingSlash = false;
        m_lastBackspaces = 0;
        m_lastTextUtf8[0] = '\0';
        return static_cast<int32_t>(Action::PassThrough);
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
    if (m_inputMethod == InputMethod::VNI && isAsciiDigit(codepoint)) {
        consumedAsModifier = applyVniCharacter(ch);
    } else if (!m_literalLock && m_literalTailLen > 0 && m_inputMethod == InputMethod::VNI) {
        m_classicOrVniEscape = true;
        if (m_literalTailLen < kMaxWordTokens - 1) {
            m_literalTail[m_literalTailLen++] = ch;
            m_literalTail[m_literalTailLen] = 0;
        }
        consumedAsModifier = true;
    } else if (m_inputMethod == InputMethod::Telex && isAsciiAlpha(codepoint)) {
        consumedAsModifier = applyTelexCharacter(ch, lowerCh, isUpper);
    }

    if (!consumedAsModifier) {
        // SEN Flex transposed compound vowel after coda for 'đ + u/ư + coda + o' (e.g. 'dducowj' / 'dduwcoj' -> 'được'):
        bool transposedAfterCoda = false;
        if (m_grammarProfile == 1 && !m_literalLock && m_literalTailLen == 0 && lowerCh == L'o' &&
            m_tokenLen >= 3 && m_tokenLen < kMaxWordTokens &&
            m_tokens[0].baseLower == L'd' && m_tokens[0].shape == 4 &&
            m_tokens[1].baseLower == L'u') {
            int vS0 = -1, vE0 = -1;
            bool hC0 = false;
            findVowelCluster(vS0, vE0, hC0);
            if (vS0 == 1 && vE0 == 1 && hC0) {
                const int prevUShape = m_tokens[1].shape;
                for (int i = m_tokenLen; i > 2; --i) {
                    m_tokens[i] = m_tokens[i - 1];
                }
                m_tokens[1].shape = 2;
                m_tokens[2] = SyllableToken{ L'o', isUpper, 2 };
                ++m_tokenLen;
                if (isValidVietnameseSyllable()) {
                    m_tokens[1].shape = prevUShape;
                    m_tokens[2].shape = (prevUShape == 2) ? 2 : 0;
                    transposedAfterCoda = true;
                    m_lastToneKey = 0;
                    m_lastShapeKey = 0;
                    m_shapeCancelledOnce = false;
                    m_hasUndoSnapshot = false;
                } else {
                    m_tokens[1].shape = prevUShape;
                    for (int i = 2; i < m_tokenLen - 1; ++i) {
                        m_tokens[i] = m_tokens[i + 1];
                    }
                    --m_tokenLen;
                }
            }
        }
    if (!consumedAsModifier && !transposedAfterCoda) {
        // Relaxed Coda '-g' -> '-ng' expansion after a Vietnamese vowel when tone or shape modifier is present
        bool expandedRelaxedG = false;
        if (m_relaxedCoda && !m_literalLock && m_literalTailLen == 0 && lowerCh == L'g' &&
            m_tokenLen >= 1 && m_tokenLen + 1 < kMaxWordTokens) {
            int vS = -1, vE = -1;
            bool hC = false;
            findVowelCluster(vS, vE, hC);
            if (vS != -1 && !hC && vE == m_tokenLen - 1 && isValidVietnameseSyllable()) {
                bool hasShapeOrTone = (m_tone != 0);
                for (int i = 0; i < m_tokenLen && !hasShapeOrTone; ++i) {
                    if (m_tokens[i].shape != 0) hasShapeOrTone = true;
                }
                wchar_t rawLowerTmp[kMaxWordTokens]{};
                for (int i = 0; i < m_rawLen; ++i) rawLowerTmp[i] = toLowerAscii(m_rawWord[i]);
                if (hasShapeOrTone && !isUnconditionalEnglishWord(rawLowerTmp, m_rawLen)) {
                    saveUndoSnapshot();
                    m_tokens[m_tokenLen++] = SyllableToken{ L'n', isUpper, 0 };
                    m_tokens[m_tokenLen++] = SyllableToken{ L'g', isUpper, 0 };
                    int vS2 = -1, vE2 = -1;
                    bool hC2 = false;
                    findVowelCluster(vS2, vE2, hC2);
                    if (vS2 != -1 && hC2) {
                        for (int i = vS2; i < vE2; ++i) {
                            if (m_tokens[i].baseLower == L'u' && m_tokens[i + 1].baseLower == L'o' &&
                                (m_tokens[i].shape == 2 || m_tokens[i + 1].shape == 2)) {
                                m_tokens[i].shape = 2;
                                m_tokens[i + 1].shape = 2;
                            }
                        }
                    }
                    if (isValidVietnameseSyllable()) {
                        m_relaxedCodaExpanded = true;
                        m_lastToneKey = 0;
                        m_lastShapeKey = 0;
                        m_shapeCancelledOnce = false;
                        expandedRelaxedG = true;
                    } else {
                        m_tokenLen -= 2;
                        m_hasUndoSnapshot = false;
                    }
                }
            }
        }
    if (!expandedRelaxedG) {
        // Pre-vowel horn after 'đ' ('ddwuocj' -> 'được', 'ddwoij' -> 'đợi', 'ddwats' -> 'đắt', while standalone 'ddw' remains 'đw')
        if (m_inputMethod == InputMethod::Telex && !m_literalLock && m_literalTailLen == 0 &&
            m_tokenLen == 2 &&
            m_tokens[0].baseLower == L'd' && m_tokens[0].shape == 4 &&
            m_tokens[1].baseLower == L'w' && m_tokens[1].shape == 0 &&
            (lowerCh == L'u' || lowerCh == L'o' || lowerCh == L'a')) {
            const int targetShape = (lowerCh == L'a') ? 3 : 2;
            m_tokens[1] = SyllableToken{ lowerCh, isUpper, targetShape };
            m_uHornFromOwnW = (lowerCh == L'u');
            m_lastToneKey = 0;
            m_lastShapeKey = 0;
            m_shapeCancelledOnce = false;
            m_hasUndoSnapshot = false;
        } else {
        // Post-Coda / Post-Syllable Overflow Lock (parity with macOS shouldLockPostCodaOverflow):
        // If m_tokens has already formed a valid Vietnamese syllable with Vietnamese-specific shapes (đ, ă, â, ơ, ư),
        // toned ê/ô, or a cancelled vowel shape, and appending lowerCh to m_tokens would violate Vietnamese phonotactics,
        // lock the syllable stem and append ch to m_literalTail so the Vietnamese syllable is never reverted to raw ASCII!
        bool lockOverflowToTail = false;
        bool lockHornedDiphthongRepeat = false;
        const bool isSingleModifiedVowelStem =
            (m_tokenLen == 1 && rawWordStartsNonW() &&
             (m_tokens[0].shape == 1 || m_tokens[0].shape == 3 ||
              (m_tokens[0].shape == 2 && m_tone != 0 && !(m_tokens[0].baseLower == L'u' && lowerCh == L'o'))) &&
             isAsciiBaseVowel(lowerCh));
        if ((m_tokenLen >= 2 || isSingleModifiedVowelStem) && isValidVietnameseSyllable()) {
            int vStartNow = -1, vEndNow = -1;
            bool hasCodaNow = false;
            findVowelCluster(vStartNow, vEndNow, hasCodaNow);

            bool hasVnSpecific = m_shapeCancelledOnce || m_hasUndoSnapshot || isSingleModifiedVowelStem || m_relaxedCodaExpanded;
            for (int i = 0; i < m_tokenLen; ++i) {
                if (m_tokens[i].shape == 2 || m_tokens[i].shape == 3 || m_tokens[i].shape == 4 ||
                    (m_tokens[i].shape == 1 && m_tone != 0)) {
                    hasVnSpecific = true;
                    break;
                }
            }
            const bool isHornedDiphthongSameVowelRepeat =
                !hasCodaNow &&
                vStartNow >= 0 && vEndNow > vStartNow &&
                m_tokens[vStartNow].shape == 2 &&
                vEndNow == m_tokenLen - 1 &&
                lowerCh == m_tokens[vEndNow].baseLower &&
                rawWordStartsNonW();
            const bool isTonedOpenSameVowelRepeat =
                (!hasCodaNow &&
                 m_tone != 0 &&
                 (vStartNow > 0 || (vStartNow == 0 && m_tokens[vEndNow].shape != 0)) &&
                 vEndNow == m_tokenLen - 1 &&
                 lowerCh == m_tokens[vEndNow].baseLower &&
                 rawWordStartsNonW()) ||
                isHornedDiphthongSameVowelRepeat;
            if (!hasCodaNow && isAsciiBaseVowel(lowerCh) && !isTonedOpenSameVowelRepeat && !isSingleModifiedVowelStem) {
                hasVnSpecific = false;
            }
            if (isTonedOpenSameVowelRepeat || isSingleModifiedVowelStem) {
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
                int savedUoIdx = -1;
                int savedUShape = 0, savedOShape = 0;
                if (vS != -1 && !m_shapeCancelledOnce) {
                    for (int i = vS; i < vE; ++i) {
                        if (m_tokens[i].baseLower == L'u' && m_tokens[i + 1].baseLower == L'o' &&
                            (m_tokens[i].shape == 2 || m_tokens[i + 1].shape == 2)) {
                            savedUoIdx = i;
                            savedUShape = m_tokens[i].shape;
                            savedOShape = m_tokens[i + 1].shape;
                            m_tokens[i].shape = 2;
                            m_tokens[i + 1].shape = 2;
                            break;
                        }
                    }
                }
                const int savedToneForExtend = m_tone;
                if (!hasCodaNow && !isAsciiBaseVowel(lowerCh)) {
                    m_tone = 0;
                }
                bool validExtended = isValidVietnameseSyllable();
                m_tone = savedToneForExtend;
                if (savedUoIdx != -1) {
                    m_tokens[savedUoIdx].shape = savedUShape;
                    m_tokens[savedUoIdx + 1].shape = savedOShape;
                }
                --m_tokenLen;
                if (!validExtended) {
                    lockOverflowToTail = true;
                    lockHornedDiphthongRepeat = isHornedDiphthongSameVowelRepeat;
                }
            }
        }

        if (lockOverflowToTail) {
            if (m_inputMethod == InputMethod::VNI) {
                m_classicOrVniEscape = true;
            }
            if (hasStrongVietnameseSyllableAnchor() || lockHornedDiphthongRepeat || m_relaxedCodaExpanded) {
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
            if (vStart != -1 && !m_shapeCancelledOnce) {
                for (int i = vStart; i < vEnd; ++i) {
                    if (m_tokens[i].baseLower == L'u' && m_tokens[i + 1].baseLower == L'o' &&
                        (m_tokens[i].shape == 2 || m_tokens[i + 1].shape == 2)) {
                        m_tokens[i].shape = 2;
                        m_tokens[i + 1].shape = 2;
                    }
                }
            }
            if (vStart != -1 && hasCoda) {
                if (vStart == 0 && vEnd == 1 && rawWordStartsNonW() &&
                    m_tokens[0].baseLower == L'u' && m_tokens[0].shape == 2 &&
                    m_tokens[1].baseLower == L'a' && m_tokens[1].shape == 0) {
                    m_tokens[0].shape = 0;
                    m_tokens[1].shape = 3;
                }
            }
        }
        }
    }
    }
    }

    if (!hasVietnameseTransformation()) {
        m_suppressEnglishRestoreAfterBackspace = false;
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

    wchar_t mixedCompoundBuf[kMaxWordTokens]{};
    if (tryComposeMixedCaseCompound(mixedCompoundBuf, kMaxWordTokens)) {
        int segStarts[16]{};
        int segLens[16]{};
        const int segCount = partitionMixedCaseSubwords(m_rawWord, m_rawLen, segStarts, segLens);
        if (segCount >= 2) {
            const int lastStart = segStarts[segCount - 1];
            const int lastLen = segLens[segCount - 1];
            wchar_t newRaw[kMaxWordTokens]{};
            int newRawLen = 0;
            for (int i = 0; i < lastStart && newRawLen < kMaxWordTokens - 1; ++i) {
                newRaw[newRawLen++] = m_rawWord[i];
            }
            bool lastAllCaps = true;
            for (int j = 0; j < lastLen; ++j) {
                if (!(m_rawWord[lastStart + j] >= L'A' && m_rawWord[lastStart + j] <= L'Z')) {
                    lastAllCaps = false;
                    break;
                }
            }
            bool lastDirectPop = lastAllCaps;
            if (!lastDirectPop) {
                wchar_t lastLower[kMaxWordTokens]{};
                for (int j = 0; j < lastLen; ++j) {
                    lastLower[j] = toLowerAscii(m_rawWord[lastStart + j]);
                }
                if (isEnglishContextAnchor(lastLower, lastLen) || isSpacePrefixStarter(lastLower, lastLen)) {
                    lastDirectPop = true;
                }
            }
            if (lastDirectPop) {
                for (int j = 0; j < lastLen - 1 && newRawLen < kMaxWordTokens - 1; ++j) {
                    newRaw[newRawLen++] = m_rawWord[lastStart + j];
                }
            } else {
                NativeEngineState sub{};
                sub.m_inputMethod = m_inputMethod;
                sub.m_grammarProfile = m_grammarProfile;
                sub.m_smartBilingual = true;
                sub.m_modernOrthography = m_modernOrthography;
                sub.m_quickTelex = m_quickTelex;
                sub.m_relaxedCoda = false;
                sub.m_inEnglishContext = true;
                sub.m_lastWordWasEnglishAnchor = true;
                sub.m_inSubwordEval = true;
                for (int j = 0; j < lastLen; ++j) {
                    sub.feedChar(static_cast<uint32_t>(m_rawWord[lastStart + j]));
                }
                sub.feedBackspace();
                for (int j = 0; j < sub.m_rawLen && newRawLen < kMaxWordTokens - 1; ++j) {
                    newRaw[newRawLen++] = sub.m_rawWord[j];
                }
            }
            newRaw[newRawLen] = 0;
            const bool savedEngCtx = m_inEnglishContext;
            const bool savedVnCtx = m_inVietnameseContext;
            const bool savedHadVn = m_hadVietnameseInSentence;
            const bool savedAfterDigit = m_afterDigit;
            const bool savedTechDelim = m_precededByTechDelimiter;
            const bool savedMacroDelim = m_precededByMacroDelimiter;
            clearWordState();
            m_inEnglishContext = savedEngCtx;
            m_inVietnameseContext = savedVnCtx;
            m_hadVietnameseInSentence = savedHadVn;
            m_afterDigit = savedAfterDigit;
            m_precededByTechDelimiter = savedTechDelim;
            m_precededByMacroDelimiter = savedMacroDelim;
            for (int i = 0; i < newRawLen; ++i) {
                feedChar(static_cast<uint32_t>(newRaw[i]));
            }
            return emitIncrementalReplacement(priorDisplayed, priorLen, m_displayed, m_displayedLen);
        }
    } else if (m_smartBilingual && m_inputMethod == InputMethod::Telex && !m_literalLock &&
               m_rawLen >= 3 && m_rawLen + 1 < kMaxWordTokens) {
        int probeStarts[16]{};
        int probeLens[16]{};
        if (partitionMixedCaseSubwords(m_rawWord, m_rawLen, probeStarts, probeLens) < 2) {
            wchar_t probe[kMaxWordTokens]{};
            for (int i = 0; i < m_rawLen; ++i) probe[i] = m_rawWord[i];
            probe[m_rawLen] = L'a';
            probe[m_rawLen + 1] = 0;
            if (partitionMixedCaseSubwords(probe, m_rawLen + 1, probeStarts, probeLens) >= 2) {
                wchar_t newRaw[kMaxWordTokens]{};
                const int newRawLen = m_rawLen - 1;
                for (int i = 0; i < newRawLen; ++i) newRaw[i] = m_rawWord[i];
                newRaw[newRawLen] = 0;
                const bool savedEngCtx = m_inEnglishContext;
                const bool savedVnCtx = m_inVietnameseContext;
                const bool savedHadVn = m_hadVietnameseInSentence;
                const bool savedAfterDigit = m_afterDigit;
                const bool savedTechDelim = m_precededByTechDelimiter;
                const bool savedMacroDelim = m_precededByMacroDelimiter;
                clearWordState();
                m_inEnglishContext = savedEngCtx;
                m_inVietnameseContext = savedVnCtx;
                m_hadVietnameseInSentence = savedHadVn;
                m_afterDigit = savedAfterDigit;
                m_precededByTechDelimiter = savedTechDelim;
                m_precededByMacroDelimiter = savedMacroDelim;
                for (int i = 0; i < newRawLen; ++i) {
                    feedChar(static_cast<uint32_t>(newRaw[i]));
                }
                return emitIncrementalReplacement(priorDisplayed, priorLen, m_displayed, m_displayedLen);
            }
        }
    }

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
                rebuildCanonicalRawFromTokens();
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
    bool isRawFallback = (priorLen == m_rawLen) && !hasVietnameseTransformation();
    if (priorLen == m_rawLen && !isRawFallback) {
        isRawFallback = true;
        for (int i = 0; i < priorLen; ++i) {
            if (priorDisplayed[i] != m_rawWord[i]) {
                isRawFallback = false;
                break;
            }
        }
    } else if (isRawFallback) {
        for (int i = 0; i < priorLen; ++i) {
            if (priorDisplayed[i] != m_rawWord[i]) {
                isRawFallback = false;
                break;
            }
        }
    }
    if (!m_literalLock && isRawFallback) {
        if (m_rawLen <= 1) {
            clearWordState();
            return static_cast<int32_t>(Action::Reset);
        }
        wchar_t savedRaw[kMaxWordTokens]{};
        const int newRawLen = m_rawLen - 1;
        for (int i = 0; i < newRawLen; ++i) {
            savedRaw[i] = m_rawWord[i];
        }
        clearWordState();
        for (int i = 0; i < newRawLen; ++i) {
            feedChar(static_cast<uint32_t>(savedRaw[i]));
        }
        return emitIncrementalReplacement(priorDisplayed, priorLen, m_displayed, m_displayedLen);
    }
    if (m_literalLock) {
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
            rebuildCanonicalRawFromTokens();
            return emitIncrementalReplacement(priorDisplayed, priorLen, m_displayed, m_displayedLen);
        }
        m_displayedLen = composeOutputWord(m_displayed, kMaxWordTokens);
        return emitIncrementalReplacement(priorDisplayed, priorLen, m_displayed, m_displayedLen);
    }

    // Character-by-character Backspace: delete the last token from the end of the word.
    // If the popped token was the vowel carrying the tone (or no vowels remain), clear the tone;
    // otherwise keep the tone on the remaining vowel.
    if (m_tokenLen > 1) {
        int vStart = -1, vEnd = -1;
        bool hasCoda = false;
        findVowelCluster(vStart, vEnd, hasCoda);
        const int toneIdx = (m_tone != 0) ? resolveToneTargetIndex(vStart, vEnd, hasCoda) : -1;
        const int poppedIdx = m_tokenLen - 1;
        --m_tokenLen;

        int nvStart = -1, nvEnd = -1;
        bool nhasCoda = false;
        findVowelCluster(nvStart, nvEnd, nhasCoda);
        if (m_tone != 0) {
            if (poppedIdx == toneIdx || nvStart == -1) {
                m_tone = 0;
                m_toneRetainedFromBackspace = false;
            } else {
                m_toneRetainedFromBackspace = true;
            }
        }
        m_lastToneKey = 0;
        m_lastShapeKey = 0;
        m_uHornFromOwnW = false;
        m_nonAdjacentCircumflex = false;
        rebuildCanonicalRawFromTokens();
        m_suppressEnglishRestoreAfterBackspace = hasVietnameseTransformation();
        m_displayedLen = composeOutputWord(m_displayed, kMaxWordTokens);
        return emitIncrementalReplacement(priorDisplayed, priorLen, m_displayed, m_displayedLen);
    }

    // Last single character deleted -> empty
    clearWordState();
    return static_cast<int32_t>(Action::Reset);
}

int32_t NativeEngineState::commitWord() {
    if (m_displayedLen == 0) {
        m_afterDigit = false;
        m_armedAfterSpace = false;
        m_hasUndoSnapshot = false;
        m_lastBackspaces = 0;
        m_lastTextUtf8[0] = '\0';
        return static_cast<int32_t>(Action::PassThrough);
    }

    wchar_t rawLower[kMaxWordTokens]{};
    for (int i = 0; i < m_rawLen; ++i) rawLower[i] = toLowerAscii(m_rawWord[i]);

    const bool isPreservedEscape =
        !shouldRestoreRawEnglish() && (m_classicOrVniEscape || m_telexToneEscape || m_overflowLocked || isOpenSameVowelExtension() || isSingleModifiedVowelOverflow());
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
        const bool isMunFollower =
            m_prevTurnCanBecomeTun && isTurnHead &&
            m_tokenLen == 3 && m_literalTailLen == 0 && m_tone == 3 &&
            m_tokens[0].baseLower == L'm' && m_tokens[0].shape == 0 &&
            m_tokens[1].baseLower == L'u' && m_tokens[1].shape == 0 &&
            m_tokens[2].baseLower == L'n' && m_tokens[2].shape == 0;
        if (isMunFollower) {
            wchar_t finalSecond[kMaxWordTokens]{};
            const int finalSecondLen = composeOutputWord(finalSecond, kMaxWordTokens);
            wchar_t combined[kMaxWordTokens]{};
            int cLen = 0;
            combined[cLen++] = (m_prevCollisionRaw[0] == L'T') ? L'T' : L't';
            combined[cLen++] = (m_prevCollisionRaw[1] == L'U') ? static_cast<wchar_t>(0x1EE6) : static_cast<wchar_t>(0x1EE7);
            combined[cLen++] = (m_prevCollisionRaw[3] == L'N') ? L'N' : L'n';
            combined[cLen++] = L' ';
            for (int i = 0; i < finalSecondLen && cLen < kMaxWordTokens - 1; ++i) combined[cLen++] = finalSecond[i];
            combined[cLen] = 0;
            const int32_t retroBs = static_cast<int32_t>(m_prevCollisionDisplayedLen + 1 + m_displayedLen);
            char utf8Retro[kMaxUtf8Bytes]{};
            encodeWideToUtf8(combined, cLen, utf8Retro, kMaxUtf8Bytes);
            m_prevCollisionDisplayedLen = 0;
            m_prevCollisionRawLen = 0;
            m_prevTurnCanBecomeTun = false;
            m_inEnglishContext = false;
            m_inVietnameseContext = true;
            m_hadVietnameseInSentence = true;
            m_lastWordWasSexLoanwordHead = false;
            m_lastWordWasTunCollocationHead = false;
            clearWordState();
            m_lastBackspaces = retroBs;
            m_lastCommitDiffBackspaces = retroBs;
            m_lastIsOverride = false;
            for (int i = 0; i < kMaxUtf8Bytes; ++i) {
                m_lastTextUtf8[i] = utf8Retro[i];
                m_lastCommitDiffTextUtf8[i] = utf8Retro[i];
                if (utf8Retro[i] == '\0') break;
            }
            return static_cast<int32_t>(Action::Commit);
        }
        if ((!m_prevTurnCanBecomeTun && isTurnHead && isTurnPhrasalFollower(rawLower, m_rawLen)) || (isSexHead && isSexEnglishFollower(rawLower, m_rawLen))) {
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
            m_prevTurnCanBecomeTun = false;
            m_inEnglishContext = true;
            m_inVietnameseContext = false;
            m_lastWordWasSexLoanwordHead = false;
            m_lastWordWasTunCollocationHead = false;
            clearWordState();
            m_lastBackspaces = retroBs;
            m_lastCommitDiffBackspaces = retroBs;
            m_lastIsOverride = true;
            for (int i = 0; i < kMaxUtf8Bytes; ++i) {
                m_lastTextUtf8[i] = utf8Retro[i];
                m_lastCommitDiffTextUtf8[i] = utf8Retro[i];
                if (utf8Retro[i] == '\0') break;
            }
            return static_cast<int32_t>(Action::Commit);
        }
        if (isSpacePrefixStarter(prevLower, m_prevCollisionRawLen)) {
            wchar_t finalSecond[kMaxWordTokens]{};
            const int finalSecondLen = composeOutputWord(finalSecond, kMaxWordTokens);
            wchar_t secondLower[kMaxWordTokens]{};
            bool secondHasNonAscii = false;
            for (int i = 0; i < finalSecondLen; ++i) {
                if (finalSecond[i] > 0x7F) secondHasNonAscii = true;
                secondLower[i] = toLowerAscii(finalSecond[i]);
            }
            const bool secondIsEnglishFollower =
                !secondHasNonAscii &&
                !isVietnameseCompoundContinuationAfterStarter(prevLower, m_prevCollisionRawLen, secondLower, finalSecondLen, rawLower, m_rawLen) &&
                ((hasVietnameseTransformation() && shouldRestoreRawEnglish()) ||
                 isUnconditionalEnglishWord(rawLower, m_rawLen) ||
                 isDefaultNoContextShortEnglishWord(rawLower, m_rawLen) ||
                 isContextEnglishCollisionWord(rawLower, m_rawLen) ||
                 isEnglishContextAnchor(rawLower, m_rawLen) ||
                 (!isValidVietnameseSyllable() && !m_classicOrVniEscape && !m_telexToneEscape && !m_overflowLocked && finalSecondLen >= 2));
            if (secondIsEnglishFollower) {
                wchar_t combined[kMaxWordTokens]{};
                int cLen = 0;
                for (int i = 0; i < m_prevCollisionRawLen && cLen < kMaxWordTokens - 1; ++i) combined[cLen++] = m_prevCollisionRaw[i];
                if (cLen < kMaxWordTokens - 1) combined[cLen++] = L' ';
                for (int i = 0; i < finalSecondLen && cLen < kMaxWordTokens - 1; ++i) combined[cLen++] = finalSecond[i];
                combined[cLen] = 0;
                const int32_t retroBs = static_cast<int32_t>(m_prevCollisionDisplayedLen + 1 + m_displayedLen);
                char utf8Retro[kMaxUtf8Bytes]{};
                encodeWideToUtf8(combined, cLen, utf8Retro, kMaxUtf8Bytes);
                m_prevCollisionDisplayedLen = 0;
                m_prevCollisionRawLen = 0;
                m_prevTurnCanBecomeTun = false;
                m_inEnglishContext = true;
                m_inVietnameseContext = false;
                m_lastWordWasEnglishAnchor = isEnglishContextAnchor(rawLower, m_rawLen);
                m_lastWordWasSexLoanwordHead = false;
                m_lastWordWasTunCollocationHead = false;
                clearWordState();
                m_lastBackspaces = retroBs;
                m_lastCommitDiffBackspaces = retroBs;
                m_lastIsOverride = true;
                for (int i = 0; i < kMaxUtf8Bytes; ++i) {
                    m_lastTextUtf8[i] = utf8Retro[i];
                    m_lastCommitDiffTextUtf8[i] = utf8Retro[i];
                    if (utf8Retro[i] == '\0') break;
                }
                return static_cast<int32_t>(Action::Commit);
            }
        }
    }

    if (m_macroEnabled && m_rawLen > 0 &&
        !shouldSuppressMacroExpansion(m_precededByMacroDelimiter, m_pendingBoundaryCp)) {
        char rawUtf8[kMaxUtf8Bytes]{};
        encodeWideToUtf8(m_rawWord, m_rawLen, rawUtf8, kMaxUtf8Bytes);
        std::string expandedUtf8;
        bool macroHit = GlobalMacroStore::instance().lookup(rawUtf8, expandedUtf8);
        if (!macroHit && !m_literalLock && m_tokenLen > 0) {
            int mvStart = -1, mvEnd = -1;
            bool mHasCoda = false;
            findVowelCluster(mvStart, mvEnd, mHasCoda);
            const int mToneIdx = (m_tone != 0) ? resolveToneTargetIndex(mvStart, mvEnd, mHasCoda) : -1;
            wchar_t tokWide[kMaxWordTokens]{};
            int tokWideLen = 0;
            for (int i = 0; i < m_tokenLen && tokWideLen < kMaxWordTokens - 1; ++i) {
                tokWide[tokWideLen++] = renderTokenWithTone(m_tokens[i], (i == mToneIdx) ? m_tone : 0);
            }
            for (int i = 0; i < m_literalTailLen && tokWideLen < kMaxWordTokens - 1; ++i) {
                tokWide[tokWideLen++] = m_literalTail[i];
            }
            tokWide[tokWideLen] = 0;
            char tokUtf8[kMaxUtf8Bytes]{};
            encodeWideToUtf8(tokWide, tokWideLen, tokUtf8, kMaxUtf8Bytes);
            if (std::string(tokUtf8) != std::string(rawUtf8)) {
                macroHit = GlobalMacroStore::instance().lookup(tokUtf8, expandedUtf8);
            }
        }
        if (macroHit && !expandedUtf8.empty()) {
            auto expCps = decodeUtf8Codepoints(expandedUtf8);
            wchar_t expWide[kMaxUtf8Bytes]{};
            int expWideLen = 0;
            int utf8BytesUsed = 0;
            bool expHasNonAscii = false;
            for (uint32_t cp : expCps) {
                const int cpBytes = (cp < 0x80) ? 1 : (cp < 0x800 ? 2 : (cp < 0x10000 ? 3 : 4));
                if (utf8BytesUsed + cpBytes >= kMaxUtf8Bytes || expWideLen >= kMaxUtf8Bytes - 1) break;
                if (cp > 0x7F) expHasNonAscii = true;
                expWide[expWideLen++] = static_cast<wchar_t>(cp);
                utf8BytesUsed += cpBytes;
            }
            expWide[expWideLen] = 0;

            const int32_t macroBs = static_cast<int32_t>(m_displayedLen);
            int commonPrefix = 0;
            const int minLen = (m_displayedLen < expWideLen) ? m_displayedLen : expWideLen;
            while (commonPrefix < minLen && m_displayed[commonPrefix] == expWide[commonPrefix]) {
                ++commonPrefix;
            }
            const int32_t macroDiffBs = static_cast<int32_t>(m_displayedLen - commonPrefix);
            char utf8MacroFull[kMaxUtf8Bytes]{};
            char utf8MacroDiff[kMaxUtf8Bytes]{};
            encodeWideToUtf8(expWide, expWideLen, utf8MacroFull, kMaxUtf8Bytes);
            encodeWideToUtf8(expWide + commonPrefix, expWideLen - commonPrefix, utf8MacroDiff, kMaxUtf8Bytes);

            if (expHasNonAscii) {
                m_inVietnameseContext = true;
                m_hadVietnameseInSentence = true;
                m_inEnglishContext = false;
                m_mathContextWordsRemaining = 0;
            } else {
                m_inEnglishContext = true;
                m_inVietnameseContext = false;
            }
            m_lastWordWasEnglishAnchor = false;
            m_lastWordWasSexLoanwordHead = false;
            m_lastWordWasTunCollocationHead = false;
            m_prevTurnCanBecomeTun = false;
            m_prevCollisionDisplayedLen = 0;
            m_prevCollisionRawLen = 0;

            clearWordState();
            m_lastBackspaces = macroBs;
            m_lastCommitDiffBackspaces = macroDiffBs;
            m_lastIsOverride = true;
            for (int i = 0; i < kMaxUtf8Bytes; ++i) {
                m_lastTextUtf8[i] = utf8MacroFull[i];
                if (utf8MacroFull[i] == '\0') break;
            }
            for (int i = 0; i < kMaxUtf8Bytes; ++i) {
                m_lastCommitDiffTextUtf8[i] = utf8MacroDiff[i];
                if (utf8MacroDiff[i] == '\0') break;
            }
            return static_cast<int32_t>(Action::Commit);
        }
    }

    const bool wasInEnglishContextBeforeCommit = m_inEnglishContext;
    const bool wasTunHeadBeforeCommit = m_lastWordWasTunCollocationHead;
    wchar_t finalWord[kMaxWordTokens]{};
    const int finalLen = composeOutputWord(finalWord, kMaxWordTokens);
    bool finalMatchesRaw = (finalLen == m_rawLen);
    for (int i = 0; finalMatchesRaw && i < finalLen; ++i) {
        if (finalWord[i] != m_rawWord[i]) finalMatchesRaw = false;
    }
    const bool wasBilingualRestore = finalMatchesRaw && (m_smartBilingual && hasVietnameseTransformation() && shouldRestoreRawEnglish());
    const int32_t bs = static_cast<int32_t>(m_displayedLen);

    int commonCommitPrefix = 0;
    const int minCommitLen = (m_displayedLen < finalLen) ? m_displayedLen : finalLen;
    while (commonCommitPrefix < minCommitLen && m_displayed[commonCommitPrefix] == finalWord[commonCommitPrefix]) {
        ++commonCommitPrefix;
    }
    const int32_t commitDiffBs = static_cast<int32_t>(m_displayedLen - commonCommitPrefix);
    char utf8CommitDiff[kMaxUtf8Bytes]{};
    encodeWideToUtf8(finalWord + commonCommitPrefix, finalLen - commonCommitPrefix, utf8CommitDiff, kMaxUtf8Bytes);

    wchar_t finalLower[kMaxWordTokens]{};
    bool hasNonAscii = false;
    for (int i = 0; i < finalLen; ++i) {
        if (finalWord[i] > 0x7F) hasNonAscii = true;
        finalLower[i] = toLowerAscii(finalWord[i]);
    }
    const bool isTurnWord = (m_rawLen == 4 && rawLower[0] == L't' && rawLower[1] == L'u' && rawLower[2] == L'r' && rawLower[3] == L'n');
    const bool isSexWord = (m_rawLen == 3 && rawLower[0] == L's' && rawLower[1] == L'e' && rawLower[2] == L'x');
    bool isTurnOrSex = isTurnWord || isSexWord;
    const bool isAnchor = isEnglishContextAnchor(rawLower, m_rawLen);
    if (!hasNonAscii && isMathFunctionAnchor(rawLower, m_rawLen)) m_mathContextWordsRemaining = 4;
    else if (hasNonAscii) m_mathContextWordsRemaining = 0;
    else if (m_mathContextWordsRemaining > 0) {
        const bool joiner = (m_rawLen == 3 && std::wmemcmp(rawLower, L"and", 3) == 0) ||
                            (m_rawLen == 2 && std::wmemcmp(rawLower, L"or", 2) == 0) ||
                            (m_rawLen == 4 && std::wmemcmp(rawLower, L"plus", 4) == 0) ||
                            (m_rawLen == 5 && std::wmemcmp(rawLower, L"minus", 5) == 0);
        if (joiner) --m_mathContextWordsRemaining;
        else m_mathContextWordsRemaining = 0;
    }
    m_lastWordWasEnglishAnchor = isAnchor;
    m_lastWordWasSexLoanwordHead = isSexLoanwordPrecedingHead(finalLower, finalLen) || isSexLoanwordPrecedingHead(rawLower, m_rawLen);
    m_lastWordWasTunCollocationHead = isTunCollocationPrecedingHead(finalLower, finalLen) || isTunCollocationPrecedingHead(rawLower, m_rawLen);
    if (hasNonAscii || isVietnameseContextReset(finalLower, finalLen)) {
        m_inEnglishContext = false;
        if (!isTurnOrSex) {
            m_inVietnameseContext = true;
            m_hadVietnameseInSentence = true;
        }
    } else if (wasBilingualRestore || (!isValidVietnameseSyllable() && !m_classicOrVniEscape && !m_telexToneEscape && !m_overflowLocked && !isOpenSameVowelExtension() && !isSingleModifiedVowelOverflow() && finalLen >= 2) || isUnconditionalEnglishWord(rawLower, m_rawLen) || isAnchor) {
        m_inEnglishContext = true;
        m_inVietnameseContext = false;
    }

    const bool isSpaceStarterWord = isSpacePrefixStarter(rawLower, m_rawLen);
    if (m_smartBilingual && isTurnWord && !hasNonAscii && !wasInEnglishContextBeforeCommit && !wasTunHeadBeforeCommit && m_pendingBoundaryCp == ' ' && finalLen < 15 && m_rawLen < 15) {
        m_prevTurnCanBecomeTun = true;
        for (int i = 0; i < finalLen; ++i) m_prevCollisionDisplayed[i] = finalWord[i];
        m_prevCollisionDisplayed[finalLen] = 0;
        m_prevCollisionDisplayedLen = finalLen;
        for (int i = 0; i < m_rawLen; ++i) m_prevCollisionRaw[i] = m_rawWord[i];
        m_prevCollisionRaw[m_rawLen] = 0;
        m_prevCollisionRawLen = m_rawLen;
    } else if (m_smartBilingual && (isTurnOrSex || isSpaceStarterWord) && hasNonAscii && m_pendingBoundaryCp == ' ' && finalLen < 15 && m_rawLen < 15) {
        m_prevTurnCanBecomeTun = false;
        for (int i = 0; i < finalLen; ++i) m_prevCollisionDisplayed[i] = finalWord[i];
        m_prevCollisionDisplayed[finalLen] = 0;
        m_prevCollisionDisplayedLen = finalLen;
        for (int i = 0; i < m_rawLen; ++i) m_prevCollisionRaw[i] = m_rawWord[i];
        m_prevCollisionRaw[m_rawLen] = 0;
        m_prevCollisionRawLen = m_rawLen;
    } else {
        m_prevTurnCanBecomeTun = false;
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
    m_lastCommitDiffBackspaces = commitDiffBs;
    m_lastIsOverride = wasBilingualRestore;
    for (int i = 0; i < kMaxUtf8Bytes; ++i) {
        m_lastTextUtf8[i] = utf8Final[i];
        if (utf8Final[i] == '\0') break;
    }
    for (int i = 0; i < kMaxUtf8Bytes; ++i) {
        m_lastCommitDiffTextUtf8[i] = utf8CommitDiff[i];
        if (utf8CommitDiff[i] == '\0') break;
    }
    return static_cast<int32_t>(Action::Commit);
}



static_assert(sizeof(NativeEngineState) <= 4608, "NativeEngineState exceeds m_opaqueState buffer");

inline NativeEngineState *getImpl(uint8_t *buf) {
    return reinterpret_cast<NativeEngineState *>(buf);
}

inline void syncOut(WindowsNativeEngine *pub, NativeEngineState *impl, int32_t &outBs, char *outUtf8, int32_t &outCommitDiffBs, char *outCommitDiffUtf8, bool &outComp, bool &outActiveWord) {
    (void)pub;
    outBs = impl->m_lastBackspaces;
    for (int i = 0; i < kMaxUtf8Bytes; ++i) {
        outUtf8[i] = impl->m_lastTextUtf8[i];
        if (impl->m_lastTextUtf8[i] == '\0') break;
    }
    outCommitDiffBs = impl->m_lastCommitDiffBackspaces;
    for (int i = 0; i < kMaxUtf8Bytes; ++i) {
        outCommitDiffUtf8[i] = impl->m_lastCommitDiffTextUtf8[i];
        if (impl->m_lastCommitDiffTextUtf8[i] == '\0') break;
    }
    outComp = impl->isComposing();
    outActiveWord = (impl->m_displayedLen > 0);
}

} // namespace

WindowsNativeEngine::WindowsNativeEngine() {
    clearWordState();
}

void WindowsNativeEngine::reset() {
    auto *impl = getImpl(m_opaqueState);
    impl->m_inEnglishContext = false;
    impl->m_inVietnameseContext = false;
    impl->m_hadVietnameseInSentence = false;
    impl->m_lastWordWasEnglishAnchor = false;
    impl->m_mathContextWordsRemaining = 0;
    impl->m_lastWordWasSexLoanwordHead = false;
    impl->m_lastWordWasTunCollocationHead = false;
    impl->m_prevTurnCanBecomeTun = false;
    impl->m_precededByTechDelimiter = false;
    impl->m_precededByMacroDelimiter = false;
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
    impl->m_grammarProfile = m_grammarProfile;
    impl->m_quickTelex = m_quickTelex;
    impl->m_relaxedCoda = m_relaxedCoda;
    impl->m_macroEnabled = m_macroEnabled;
    impl->clearWordState();
    m_composingFlag = false;
    m_activeWordFlag = false;
    m_lastBackspaces = 0;
    m_lastTextUtf8[0] = '\0';
    m_lastCommitDiffBackspaces = 0;
    m_lastCommitDiffTextUtf8[0] = '\0';
}

void WindowsNativeEngine::setInputMethod(InputMethod method) {
    m_inputMethod = method;
    auto *impl = getImpl(m_opaqueState);
    impl->setInputMethod(method);
    m_composingFlag = impl->isComposing();
    m_activeWordFlag = (impl->m_displayedLen > 0);
    m_lastBackspaces = impl->m_lastBackspaces;
    m_lastTextUtf8[0] = '\0';
    m_lastCommitDiffBackspaces = 0;
    m_lastCommitDiffTextUtf8[0] = '\0';
}

int32_t WindowsNativeEngine::feedChar(uint32_t codepoint) {
    auto *impl = getImpl(m_opaqueState);
    impl->m_inputMethod = m_inputMethod;
    impl->m_smartBilingual = m_smartBilingual;
    impl->m_modernOrthography = m_modernOrthography;
    impl->m_grammarProfile = m_grammarProfile;
    impl->m_quickTelex = m_quickTelex;
    impl->m_relaxedCoda = m_relaxedCoda;
    impl->m_macroEnabled = m_macroEnabled;
    int32_t act = impl->feedChar(codepoint);
    syncOut(this, impl, m_lastBackspaces, m_lastTextUtf8, m_lastCommitDiffBackspaces, m_lastCommitDiffTextUtf8, m_composingFlag, m_activeWordFlag);
    return act;
}

int32_t WindowsNativeEngine::feedBackspace() {
    auto *impl = getImpl(m_opaqueState);
    impl->m_inputMethod = m_inputMethod;
    impl->m_smartBilingual = m_smartBilingual;
    impl->m_modernOrthography = m_modernOrthography;
    impl->m_grammarProfile = m_grammarProfile;
    impl->m_quickTelex = m_quickTelex;
    impl->m_relaxedCoda = m_relaxedCoda;
    impl->m_macroEnabled = m_macroEnabled;
    int32_t act = impl->feedBackspace();
    syncOut(this, impl, m_lastBackspaces, m_lastTextUtf8, m_lastCommitDiffBackspaces, m_lastCommitDiffTextUtf8, m_composingFlag, m_activeWordFlag);
    return act;
}

int32_t WindowsNativeEngine::commitWord() {
    auto *impl = getImpl(m_opaqueState);
    impl->m_inputMethod = m_inputMethod;
    impl->m_smartBilingual = m_smartBilingual;
    impl->m_modernOrthography = m_modernOrthography;
    impl->m_grammarProfile = m_grammarProfile;
    impl->m_quickTelex = m_quickTelex;
    impl->m_relaxedCoda = m_relaxedCoda;
    impl->m_macroEnabled = m_macroEnabled;
    int32_t act = impl->commitWord();
    syncOut(this, impl, m_lastBackspaces, m_lastTextUtf8, m_lastCommitDiffBackspaces, m_lastCommitDiffTextUtf8, m_composingFlag, m_activeWordFlag);
    return act;
}

bool WindowsNativeEngine::loadMacrosJson(const char *jsonUtf8) {
    return GlobalMacroStore::instance().loadJson(jsonUtf8);
}

void WindowsNativeEngine::resetDefaultMacros() {
    GlobalMacroStore::instance().resetToDefaults();
}

void NativeEngineState::appendContextWord(const char *contextWord) {
    if (!contextWord || contextWord[0] == '\0') {
        m_inEnglishContext = false;
        m_inVietnameseContext = false;
        m_hadVietnameseInSentence = false;
        m_lastWordWasEnglishAnchor = false;
        m_mathContextWordsRemaining = 0;
        m_lastWordWasSexLoanwordHead = false;
        m_lastWordWasTunCollocationHead = false;
        m_prevTurnCanBecomeTun = false;
        m_precededByTechDelimiter = false;
        m_precededByMacroDelimiter = false;
        m_afterDigit = false;
        m_precededByLeadingSlash = false;
        m_pendingBoundaryCp = 0;
        m_prevCollisionDisplayedLen = 0;
        m_prevCollisionRawLen = 0;
        return;
    }
    bool hasNonAscii = false;
    for (const unsigned char *p = reinterpret_cast<const unsigned char *>(contextWord); *p; ++p) {
        if (*p >= 0x80) {
            hasNonAscii = true;
            break;
        }
    }
    if (hasNonAscii) {
        auto utf8Eq = [](const char *a, const char *b) -> bool {
            while (*a && *b && *a == *b) { ++a; ++b; }
            return *a == '\0' && *b == '\0';
        };
        m_inVietnameseContext = true;
        m_hadVietnameseInSentence = true;
        m_inEnglishContext = false;
        m_lastWordWasEnglishAnchor = false;
        m_mathContextWordsRemaining = 0;
        m_lastWordWasSexLoanwordHead =
            utf8Eq(contextWord, "ảnh") || utf8Eq(contextWord, "cảnh") ||
            utf8Eq(contextWord, "hình") || utf8Eq(contextWord, "truyện");
        m_lastWordWasTunCollocationHead =
            utf8Eq(contextWord, "lùn") || utf8Eq(contextWord, "lủn") ||
            utf8Eq(contextWord, "nhỏ") || utf8Eq(contextWord, "ngắn") ||
            utf8Eq(contextWord, "cụt");
        m_prevTurnCanBecomeTun = false;
        m_precededByTechDelimiter = false;
        m_afterDigit = false;
        m_prevCollisionDisplayedLen = 0;
        m_prevCollisionRawLen = 0;
        return;
    }
    NativeEngineState temp = *this;
    temp.clearWordState();
    for (const unsigned char *p = reinterpret_cast<const unsigned char *>(contextWord); *p; ++p) {
        temp.feedChar(static_cast<uint32_t>(*p));
    }
    temp.feedChar(static_cast<uint32_t>(' '));
    m_inEnglishContext = temp.m_inEnglishContext;
    m_inVietnameseContext = temp.m_inVietnameseContext;
    m_hadVietnameseInSentence = temp.m_hadVietnameseInSentence;
    m_lastWordWasEnglishAnchor = temp.m_lastWordWasEnglishAnchor;
    m_mathContextWordsRemaining = temp.m_mathContextWordsRemaining;
    m_lastWordWasSexLoanwordHead = temp.m_lastWordWasSexLoanwordHead;
    m_lastWordWasTunCollocationHead = temp.m_lastWordWasTunCollocationHead;
    m_prevTurnCanBecomeTun = false;
    m_precededByTechDelimiter = temp.m_precededByTechDelimiter;
    m_afterDigit = false;
    m_prevCollisionDisplayedLen = 0;
    m_prevCollisionRawLen = 0;
}

void NativeEngineState::syncSurroundingContext(const char *beforeContextUtf8) {
    if (m_displayedLen > 0) return;
    if (!beforeContextUtf8 || beforeContextUtf8[0] == '\0') {
        appendContextWord("");
        return;
    }
    int rawEnd = 0;
    while (beforeContextUtf8[rawEnd] != '\0') {
        ++rawEnd;
    }

    // 1. Preserve in-flight retroactive collocation state (e.g. "this ", "turn ", "sex ", "there ")
    // when the surrounding text still ends with the exact word + space just committed by the engine.
    if (m_prevCollisionDisplayedLen > 0 && rawEnd >= 2 && beforeContextUtf8[rawEnd - 1] == ' ') {
        char expectedUtf8[64]{};
        encodeWideToUtf8(m_prevCollisionDisplayed, m_prevCollisionDisplayedLen, expectedUtf8, sizeof(expectedUtf8));
        int expLen = 0;
        while (expectedUtf8[expLen] != '\0') ++expLen;
        if (expLen > 0 && rawEnd >= expLen + 1) {
            const int matchStart = rawEnd - 1 - expLen;
            const bool cleanStart = (matchStart == 0) ||
                                    beforeContextUtf8[matchStart - 1] == ' ' ||
                                    beforeContextUtf8[matchStart - 1] == '\t' ||
                                    beforeContextUtf8[matchStart - 1] == '\n' ||
                                    beforeContextUtf8[matchStart - 1] == '\r';
            bool matched = cleanStart;
            for (int i = 0; matched && i < expLen; ++i) {
                if (beforeContextUtf8[matchStart + i] != expectedUtf8[i]) {
                    matched = false;
                }
            }
            if (matched) {
                return;
            }
        }
    }

    // 2. Preserve immediate non-whitespace prefix state (digit-prefix "100W"/"4K60W", leading slash "/aws", tech delimiters)
    const unsigned char tailCh = static_cast<unsigned char>(beforeContextUtf8[rawEnd - 1]);
    if (tailCh != ' ' && tailCh != '\t' && tailCh != '\n' && tailCh != '\r') {
        int tokStart = rawEnd;
        while (tokStart > 0) {
            char c = beforeContextUtf8[tokStart - 1];
            if (c == ' ' || c == '\t' || c == '\n' || c == '\r') break;
            --tokStart;
        }
        bool tokHasDigit = false;
        for (int i = tokStart; i < rawEnd; ++i) {
            if (beforeContextUtf8[i] >= '0' && beforeContextUtf8[i] <= '9') {
                tokHasDigit = true;
                break;
            }
        }
        if ((tailCh >= '0' && tailCh <= '9') || (tokHasDigit && beforeContextUtf8[tokStart] >= '0' && beforeContextUtf8[tokStart] <= '9')) {
            m_afterDigit = true;
            m_precededByLeadingSlash = false;
            m_prevCollisionDisplayedLen = 0;
            m_prevCollisionRawLen = 0;
            return;
        }
        if (tailCh == '/') {
            const bool isLeadingSlash = (beforeContextUtf8[tokStart] == '/');
            m_precededByLeadingSlash = isLeadingSlash;
            m_precededByTechDelimiter = isLeadingSlash || !m_inVietnameseContext;
            m_afterDigit = false;
            m_prevCollisionDisplayedLen = 0;
            m_prevCollisionRawLen = 0;
            return;
        }
        if (tailCh == '_' || tailCh == '\\') {
            m_precededByTechDelimiter = true;
            m_precededByLeadingSlash = false;
            m_afterDigit = false;
            m_prevCollisionDisplayedLen = 0;
            m_prevCollisionRawLen = 0;
            return;
        }
    }

    int endPos = rawEnd;
    // If trailing characters are ASCII letters (partial word before cursor), drop them before extracting context words
    while (endPos > 0) {
        unsigned char c = static_cast<unsigned char>(beforeContextUtf8[endPos - 1]);
        if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')) {
            --endPos;
        } else {
            break;
        }
    }
    while (endPos > 0) {
        char ch = beforeContextUtf8[endPos - 1];
        if (ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r') {
            --endPos;
        } else {
            break;
        }
    }
    if (endPos <= 0) {
        return;
    }
    int startPos = endPos;
    while (startPos > 0) {
        char ch = beforeContextUtf8[startPos - 1];
        if (ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r') {
            break;
        }
        --startPos;
    }
    const int wordLen = endPos - startPos;
    if (wordLen > 0 && wordLen <= 48) {
        // Also extract the word immediately preceding `lastWord` (within the same sentence)
        // so 2-word context chains such as "sin and cos" survive surrounding-text sync.
        int prevEnd = startPos;
        while (prevEnd > 0) {
            char ch = beforeContextUtf8[prevEnd - 1];
            if (ch == ' ' || ch == '\t') {
                --prevEnd;
            } else {
                break;
            }
        }
        int prevStart = prevEnd;
        while (prevStart > 0) {
            char ch = beforeContextUtf8[prevStart - 1];
            if (ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r' ||
                ch == '.' || ch == '!' || ch == '?') {
                break;
            }
            --prevStart;
        }
        const int prevLen = prevEnd - prevStart;
        if (prevLen > 0 && prevLen <= 48 &&
            (prevStart == 0 || (beforeContextUtf8[prevStart - 1] != '.' &&
                                beforeContextUtf8[prevStart - 1] != '!' &&
                                beforeContextUtf8[prevStart - 1] != '?'))) {
            char prevWord[64]{};
            for (int i = 0; i < prevLen; ++i) {
                prevWord[i] = beforeContextUtf8[prevStart + i];
            }
            prevWord[prevLen] = '\0';
            appendContextWord(prevWord);
        }

        char lastWord[64]{};
        bool lastWordHasNonAscii = false;
        for (int i = 0; i < wordLen; ++i) {
            lastWord[i] = beforeContextUtf8[startPos + i];
            if (static_cast<unsigned char>(lastWord[i]) >= 0x80) {
                lastWordHasNonAscii = true;
            }
        }
        lastWord[wordLen] = '\0';
        bool sentenceHasNonAscii = false;
        for (int i = startPos - 1; i >= 0; --i) {
            char ch = beforeContextUtf8[i];
            if (ch == '.' || ch == '!' || ch == '?' || ch == '\n' || ch == '\r') {
                break;
            }
            if (static_cast<unsigned char>(ch) >= 0x80) {
                sentenceHasNonAscii = true;
                break;
            }
        }
        appendContextWord(lastWord);
        if (!lastWordHasNonAscii && sentenceHasNonAscii) {
            wchar_t wLower[48]{};
            for (int i = 0; i < wordLen; ++i) {
                wLower[i] = toLowerAscii(static_cast<wchar_t>(static_cast<unsigned char>(lastWord[i])));
            }
            const bool isKnownEnglish =
                isUnconditionalEnglishWord(wLower, wordLen) ||
                isEnglishContextAnchor(wLower, wordLen) ||
                isDefaultNoContextShortEnglishWord(wLower, wordLen) ||
                isContextEnglishCollisionWord(wLower, wordLen);
            if (!isKnownEnglish) {
                m_inVietnameseContext = true;
                m_hadVietnameseInSentence = true;
                m_inEnglishContext = false;
            }
        }
    }
}

void WindowsNativeEngine::syncSurroundingContext(const char *beforeContextUtf8) {
    auto *impl = getImpl(m_opaqueState);
    impl->m_inputMethod = m_inputMethod;
    impl->m_smartBilingual = m_smartBilingual;
    impl->m_modernOrthography = m_modernOrthography;
    impl->m_grammarProfile = m_grammarProfile;
    impl->m_quickTelex = m_quickTelex;
    impl->m_relaxedCoda = m_relaxedCoda;
    impl->m_macroEnabled = m_macroEnabled;
    impl->syncSurroundingContext(beforeContextUtf8);
}

static bool decodePrecomposedVnChar(wchar_t ch, SyllableToken &outTok, int &outTone) {
    outTok = {};
    outTone = 0;
    if (ch == 0x0111) { // đ
        outTok.baseLower = L'd';
        outTok.isUpper = false;
        outTok.shape = 4;
        return true;
    }
    if (ch == 0x0110) { // Đ
        outTok.baseLower = L'd';
        outTok.isUpper = true;
        outTok.shape = 4;
        return true;
    }
    static constexpr wchar_t kRowBaseLower[12] = {
        L'a', L'a', L'a', L'e', L'e', L'i', L'o', L'o', L'o', L'u', L'u', L'y'
    };
    static constexpr int kRowShape[12] = {
        0,    3,    1,    0,    1,    0,    0,    1,    2,    0,    2,    0
    };
    for (int r = 0; r < 12; ++r) {
        for (int c = 0; c < 6; ++c) {
            if (ch == kLowerVowelTable[r][c]) {
                outTok.baseLower = kRowBaseLower[r];
                outTok.isUpper = false;
                outTok.shape = kRowShape[r];
                outTone = c;
                return true;
            }
            if (ch == kUpperVowelTable[r][c]) {
                outTok.baseLower = kRowBaseLower[r];
                outTok.isUpper = true;
                outTok.shape = kRowShape[r];
                outTone = c;
                return true;
            }
        }
    }
    if (ch >= L'a' && ch <= L'z') {
        outTok.baseLower = ch;
        outTok.isUpper = false;
        outTok.shape = 0;
        return true;
    }
    if (ch >= L'A' && ch <= L'Z') {
        outTok.baseLower = static_cast<wchar_t>(ch + (L'a' - L'A'));
        outTok.isUpper = true;
        outTok.shape = 0;
        return true;
    }
    return false;
}

bool NativeEngineState::tryRehydrateAndFeed(const wchar_t *precedingWord, int wordLen, uint32_t codepoint) {
    if (!precedingWord || wordLen < 1 || wordLen > 6 || m_displayedLen > 0) {
        return false;
    }
    SyllableToken toks[8]{};
    int wordTone = 0;
    bool hasPreExistingVn = false;
    for (int i = 0; i < wordLen; ++i) {
        int t = 0;
        if (!decodePrecomposedVnChar(precedingWord[i], toks[i], t)) {
            return false;
        }
        if (precedingWord[i] > 0x7F) {
            hasPreExistingVn = true;
        }
        if (t != 0) {
            if (wordTone != 0) {
                return false;
            }
            wordTone = t;
        }
    }

    NativeEngineState temp = *this;
    temp.clearWordState();
    for (int i = 0; i < wordLen; ++i) {
        temp.m_tokens[i] = toks[i];
    }
    temp.m_tokenLen = wordLen;
    temp.m_tone = wordTone;
    temp.rebuildCanonicalRawFromTokens();
    temp.m_suppressEnglishRestoreAfterBackspace = hasPreExistingVn;
    temp.m_displayedLen = temp.composeOutputWord(temp.m_displayed, kMaxWordTokens);
    if (temp.m_displayedLen != wordLen || std::wmemcmp(temp.m_displayed, precedingWord, wordLen) != 0) {
        return false;
    }

    int32_t act = temp.feedChar(codepoint);
    if (act != static_cast<int32_t>(Action::Replace) ||
        temp.m_displayedLen != wordLen ||
        std::wmemcmp(temp.m_displayed, precedingWord, wordLen) == 0 ||
        !temp.isValidVietnameseSyllable() ||
        !temp.hasVietnameseTransformation() ||
        temp.shouldRestoreRawEnglish()) {
        return false;
    }

    if (!hasPreExistingVn) {
        wchar_t rawLower[kMaxWordTokens]{};
        for (int i = 0; i < temp.m_rawLen; ++i) {
            rawLower[i] = toLowerAscii(temp.m_rawWord[i]);
        }
        if (isUnconditionalEnglishWord(rawLower, temp.m_rawLen) ||
            isContextEnglishCollisionWord(rawLower, temp.m_rawLen) ||
            isExtendedEnglishEscapeWord(rawLower, temp.m_rawLen) ||
            isDefaultNoContextShortEnglishWord(rawLower, temp.m_rawLen)) {
            return false;
        }
    }

    int commonPrefix = 0;
    while (commonPrefix < wordLen && precedingWord[commonPrefix] == temp.m_displayed[commonPrefix]) {
        ++commonPrefix;
    }
    temp.m_lastBackspaces = wordLen - commonPrefix;
    encodeWideToUtf8(
        temp.m_displayed + commonPrefix,
        wordLen - commonPrefix,
        temp.m_lastTextUtf8,
        sizeof(temp.m_lastTextUtf8)
    );
    *this = temp;
    return true;
}

bool WindowsNativeEngine::tryRehydrateAndFeed(const wchar_t *precedingWord, int wordLen, uint32_t codepoint) {
    auto *impl = getImpl(m_opaqueState);
    impl->m_inputMethod = m_inputMethod;
    impl->m_smartBilingual = m_smartBilingual;
    impl->m_modernOrthography = m_modernOrthography;
    impl->m_grammarProfile = m_grammarProfile;
    impl->m_quickTelex = m_quickTelex;
    impl->m_relaxedCoda = m_relaxedCoda;
    impl->m_macroEnabled = m_macroEnabled;
    if (!impl->tryRehydrateAndFeed(precedingWord, wordLen, codepoint)) {
        return false;
    }
    syncOut(this, impl, m_lastBackspaces, m_lastTextUtf8, m_lastCommitDiffBackspaces, m_lastCommitDiffTextUtf8, m_composingFlag, m_activeWordFlag);
    return true;
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
    s->impl.m_precededByMacroDelimiter = false;
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

VIELOTUS_CAPI_EXPORT void vielotus_set_macro_enabled(void *session, bool enabled) {
    auto *s = asSession(session);
    if (!s) return;
    s->impl.m_macroEnabled = enabled;
}

VIELOTUS_CAPI_EXPORT bool vielotus_load_macros_json(const char *json_utf8) {
    return vielotus_win::WindowsNativeEngine::loadMacrosJson(json_utf8);
}

VIELOTUS_CAPI_EXPORT void vielotus_reset_default_macros(void) {
    vielotus_win::WindowsNativeEngine::resetDefaultMacros();
}

VIELOTUS_CAPI_EXPORT void vielotus_set_relaxed_coda(void *session, bool enabled) {
    auto *s = asSession(session);
    if (!s) return;
    s->impl.m_relaxedCoda = enabled;
}

VIELOTUS_CAPI_EXPORT int32_t vielotus_feed_char(void *session, uint32_t codepoint) {
    auto *s = asSession(session);
    if (!s) return 0;
    s->postCommitBackspaceStep = 0;
    if (s->impl.m_displayedLen > 0 &&
        !vielotus_win::NativeEngineState::isWordBoundaryDelimiter(codepoint) &&
        !vielotus_win::isAsciiAlpha(codepoint) &&
        !(s->impl.m_inputMethod == vielotus_win::InputMethod::VNI && vielotus_win::isAsciiDigit(codepoint) && s->impl.m_tokenLen > 0 && !s->impl.m_literalLock)) {
        s->impl.m_pendingBoundaryCp = codepoint;
        int32_t act = s->impl.commitWord();
        s->impl.m_pendingBoundaryCp = 0;
        s->impl.m_afterDigit = vielotus_win::isAsciiDigit(codepoint);
        s->impl.m_precededByMacroDelimiter = vielotus_win::isMacroTechnicalDelimiter(codepoint);
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
                    s->impl.rebuildCanonicalRawFromTokens();
                }
            } else {
                s->impl.m_tokenLen = s->impl.m_undoTokenLen;
                for (int i = 0; i < s->impl.m_tokenLen; ++i) {
                    s->impl.m_tokens[i] = s->impl.m_undoTokens[i];
                }
                s->impl.m_tone = s->impl.m_undoTone;
                int vStart = -1, vEnd = -1;
                bool hasCoda = false;
                s->impl.findVowelCluster(vStart, vEnd, hasCoda);
                const int toneIdx = (s->impl.m_tone != 0) ? s->impl.resolveToneTargetIndex(vStart, vEnd, hasCoda) : -1;
                const int poppedIdx = s->impl.m_tokenLen - 1;
                s->impl.m_tokenLen = (s->impl.m_undoTokenLen > 1) ? (s->impl.m_undoTokenLen - 1) : 0;
                int nvStart = -1, nvEnd = -1;
                bool nhasCoda = false;
                s->impl.findVowelCluster(nvStart, nvEnd, nhasCoda);
                if (s->impl.m_tone != 0) {
                    if (poppedIdx == toneIdx || nvStart == -1) {
                        s->impl.m_tone = 0;
                        s->impl.m_toneRetainedFromBackspace = false;
                    } else {
                        s->impl.m_toneRetainedFromBackspace = true;
                    }
                }
                s->impl.m_lastToneKey = 0;
                s->impl.m_lastShapeKey = 0;
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
                    s->impl.rebuildCanonicalRawFromTokens();
                    s->impl.m_suppressEnglishRestoreAfterBackspace = s->impl.hasVietnameseTransformation();
                    s->impl.m_displayedLen = s->impl.composeOutputWord(s->impl.m_displayed, vielotus_win::kMaxWordTokens);
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
    s->impl.appendContextWord(context_word);
}

VIELOTUS_CAPI_EXPORT void vielotus_sync_armed_word(void *session, const char *before_context_utf8) {
    auto *s = asSession(session);
    if (!s) return;
    s->impl.syncSurroundingContext(before_context_utf8);
}

VIELOTUS_CAPI_EXPORT const char *vielotus_get_version(void) {
    return "2.0.3";
}

VIELOTUS_CAPI_EXPORT const char *vielotus_get_build_stamp(void) {
    return "2.0.3-r12 (PureTSF+Tray+Feedback)";
}
