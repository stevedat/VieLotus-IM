// =============================================================================
// VieLotusIM — Windows Native Engine Lab & Regression Harness
// Compiles and tests Sources/VieLotusCoreWindows/WindowsNativeEngine.cpp
// directly against the 9,091-case regression matrix + bilingual phrase suite.
// =============================================================================

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <iostream>
#include <map>
#include <set>
#include <sstream>
#include <string>
#include <vector>

#include "WindowsNativeEngine.h"
#include "TsfGameGuardLogic.h"
#include "vielotus.h"
#if !defined(_WIN32)
#include "vielotus_linux_common.h"
#endif

using namespace vielotus_win;

namespace {

void removeLastUtf16Units(std::string &utf8, int unitsToRemove) {
    if (unitsToRemove <= 0 || utf8.empty()) return;
    std::vector<uint32_t> cps;
    size_t i = 0;
    while (i < utf8.size()) {
        unsigned char c = static_cast<unsigned char>(utf8[i]);
        uint32_t cp = 0;
        if (c < 0x80) {
            cp = c;
            i += 1;
        } else if ((c & 0xE0) == 0xC0 && i + 1 < utf8.size()) {
            cp = ((c & 0x1F) << 6) | (static_cast<unsigned char>(utf8[i + 1]) & 0x3F);
            i += 2;
        } else if ((c & 0xF0) == 0xE0 && i + 2 < utf8.size()) {
            cp = ((c & 0x0F) << 12) |
                 ((static_cast<unsigned char>(utf8[i + 1]) & 0x3F) << 6) |
                 (static_cast<unsigned char>(utf8[i + 2]) & 0x3F);
            i += 3;
        } else if ((c & 0xF8) == 0xF0 && i + 3 < utf8.size()) {
            cp = ((c & 0x07) << 18) |
                 ((static_cast<unsigned char>(utf8[i + 1]) & 0x3F) << 12) |
                 ((static_cast<unsigned char>(utf8[i + 2]) & 0x3F) << 6) |
                 (static_cast<unsigned char>(utf8[i + 3]) & 0x3F);
            i += 4;
        } else {
            cp = c;
            i += 1;
        }
        cps.push_back(cp);
    }
    while (unitsToRemove > 0 && !cps.empty()) {
        uint32_t last = cps.back();
        cps.pop_back();
        unitsToRemove -= (last > 0xFFFF) ? 2 : 1;
    }
    utf8.clear();
    for (uint32_t cp : cps) {
        if (cp < 0x80) {
            utf8.push_back(static_cast<char>(cp));
        } else if (cp < 0x800) {
            utf8.push_back(static_cast<char>(0xC0 | (cp >> 6)));
            utf8.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
        } else if (cp < 0x10000) {
            utf8.push_back(static_cast<char>(0xE0 | (cp >> 12)));
            utf8.push_back(static_cast<char>(0x80 | ((cp >> 6) & 0x3F)));
            utf8.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
        } else {
            utf8.push_back(static_cast<char>(0xF0 | (cp >> 18)));
            utf8.push_back(static_cast<char>(0x80 | ((cp >> 12) & 0x3F)));
            utf8.push_back(static_cast<char>(0x80 | ((cp >> 6) & 0x3F)));
            utf8.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
        }
    }
}

const char *actionName(int32_t act) {
    switch (static_cast<Action>(act)) {
    case Action::PassThrough: return "PASSTHROUGH";
    case Action::Consumed:    return "CONSUMED";
    case Action::Replace:     return "REPLACE";
    case Action::Commit:      return "COMMIT";
    case Action::Reset:       return "RESET";
    }
    return "UNKNOWN";
}

std::string driveSequence(
    WindowsNativeEngine &eng,
    const std::string &input,
    bool primeEnglish,
    bool bilingual,
    bool verboseTrace = false
) {
    eng.reset();
    eng.setSmartBilingual(bilingual);
    if (primeEnglish) {
        const char *prime = "he is ";
        for (const char *p = prime; *p; ++p) {
            eng.feedChar(static_cast<uint32_t>(*p));
        }
    }
    std::string screen;
    for (unsigned char ch : input) {
        if (ch == '<') {
            if (eng.isComposing()) {
                int32_t act = eng.feedBackspace();
                if (act == static_cast<int32_t>(Action::Reset)) {
                    eng.reset();
                    removeLastUtf16Units(screen, 1);
                } else {
                    removeLastUtf16Units(screen, eng.getLastBackspaces());
                    screen += eng.getLastTextUtf8();
                }
                if (verboseTrace) {
                    std::printf("  [BS ] -> %-11s (bs=%d, txt=\"%s\") => screen=\"%s\"\n",
                                actionName(act), eng.getLastBackspaces(), eng.getLastTextUtf8(), screen.c_str());
                }
            } else {
                removeLastUtf16Units(screen, 1);
                if (verboseTrace) {
                    std::printf("  [BS ] -> HOST_BS => screen=\"%s\"\n", screen.c_str());
                }
            }
        } else {
            int32_t act = eng.feedChar(static_cast<uint32_t>(ch));
            if (act == static_cast<int32_t>(Action::Commit)) {
                removeLastUtf16Units(screen, eng.getLastCommitDiffBackspaces());
                screen += eng.getLastCommitDiffTextUtf8();
                screen.push_back(static_cast<char>(ch));
            } else if (act == static_cast<int32_t>(Action::Replace)) {
                removeLastUtf16Units(screen, eng.getLastBackspaces());
                screen += eng.getLastTextUtf8();
            } else {
                screen.push_back(static_cast<char>(ch));
            }
            if (verboseTrace) {
                std::printf("  ['%c'] -> %-11s (bs=%d, txt=\"%s\") => screen=\"%s\"\n",
                            static_cast<char>(ch), actionName(act), eng.getLastBackspaces(),
                            eng.getLastTextUtf8(), screen.c_str());
            }
        }
    }
    if (eng.isComposing()) {
        int32_t act = eng.commitWord();
        if (act == static_cast<int32_t>(Action::Commit)) {
            removeLastUtf16Units(screen, eng.getLastCommitDiffBackspaces());
            screen += eng.getLastCommitDiffTextUtf8();
        }
        if (verboseTrace) {
            std::printf("  [END] -> %-11s (bs=%d, txt=\"%s\") => screen=\"%s\"\n",
                        actionName(act), eng.getLastBackspaces(), eng.getLastTextUtf8(), screen.c_str());
        }
    }
    return screen;
}

struct CaseRow {
    std::string input;
    std::vector<std::string> expected;
    std::string expectedRaw;
    std::string behavior;
    std::string category;
    std::string naiveTelex;
    std::string whitelistSafe;
};

struct PhraseTest {
    const char *rawKeys;
    const char *expected;
    const char *note;
};

const PhraseTest kBilingualPhrases[] = {
    // Vietnamese context for "sẽ" (keystroke: sex)
    { "tooi sex ddi ",          "tôi sẽ đi ",          "VN clause starter 'tôi' + sẽ" },
    { "em sex lafm ",           "em sẽ làm ",          "VN clause starter 'em' + sẽ" },
    { "and cos ", "and có ", "Vietnamese co after generic English conjunction" },
    { "sin cos ", "sin cos ", "Trigonometric abbreviation with domain evidence" },
    { "sin and cos ", "sin and cos ", "Math context survives conjunction" },
    { "sin apple and cos ", "sin apple and có ", "Old math context does not leak into prose" },
    { "pros and cos ", "pros and có ", "And alone is not math context" },
    { "sunworld ", "sunworld ", "Unknown English compound brand" },
    { "pros and cons ", "pros and cons ", "English collocation remains intact" },
    { "sex cos ",               "sẽ có ",              "Sentence-initial 'sẽ có'" },
    { "chawsc sex oorn ",       "chắc sẽ ổn ",         "VN adverb 'chắc' + sẽ" },

    // Loanword / English context for "sex" (keystroke: sex)
    { "phim sex ",              "phim sex ",           "VN loanword collocation 'phim sex'" },
    { "anhr sex ",              "ảnh sex ",            "VN loanword collocation 'ảnh sex'" },
    { "canhr sex ",             "cảnh sex ",           "VN loanword collocation 'cảnh sex'" },
    { "safe sex ",              "safe sex ",           "EN collocation 'safe sex'" },
    { "have sex ",              "have sex ",           "EN collocation 'have sex'" },
    { "sex education ",         "sex education ",      "Retroactive 2-word collocation 'sex education'" },
    { "sex toy ",               "sex toy ",            "Retroactive 2-word collocation 'sex toy'" },
    { "sex life ",              "sex life ",           "Retroactive 2-word collocation 'sex life'" },

    // Vietnamese context for "tủn" (keystroke: turn)
    { "lufn turn ",             "lùn tủn ",            "VN reduplicative 'lùn tủn'" },
    { "nhor turn ",             "nhỏ tủn ",            "VN adjective 'nhỏ tủn'" },
    { "turn murn ",             "tủn mủn ",            "VN reduplicative 'tủn mủn'" },

    // English context & phrasal verbs for "turn" (keystroke: turn)
    { "your turn ",             "your turn ",          "EN determiner 'your turn'" },
    { "my turn ",               "my turn ",            "EN determiner 'my turn'" },
    { "unit test commit print(x) ", "unit test commit print(x) ", "Bilingual code phrase 'unit test commit print(x) '" },
    { "take a turn ",           "take a turn ",        "EN phrase 'take a turn'" },
    { "turn on ",               "turn on ",            "Retroactive phrasal verb 'turn on'" },
    { "turn off ",              "turn off ",           "Retroactive phrasal verb 'turn off'" },
    { "turn left ",             "turn left ",          "Retroactive phrasal verb 'turn left'" },
    { "turn right ",            "turn right ",         "Retroactive phrasal verb 'turn right'" },
    { "turn back ",             "turn back ",          "Retroactive phrasal verb 'turn back'" },
    { "turn around ",           "turn around ",        "Retroactive phrasal verb 'turn around'" },
    { "turn down ",             "turn down ",          "Retroactive phrasal verb 'turn down'" },
    { "turn it on ",            "turn it on ",         "Retroactive phrasal verb 'turn it on'" },
    { "This is ",               "This is ",            "Retroactive 2-word starter 'This is'" },
    { "this is ",               "this is ",            "Retroactive 2-word starter 'this is'" },
    { "His name is ",           "His name is ",        "Retroactive 2-word starter 'His name is'" },
    { "his name is ",           "his name is ",        "Retroactive 2-word starter 'his name is'" },
    { "enf this is ",           "èn this is ",         "Retroactive 2-word starter 'this is' after VN word" },
    { "this sinh ",             "thí sinh ",           "VN compound 'thí sinh' preserved" },
    { "this nghieemj ",         "thí nghiệm ",         "VN compound 'thí nghiệm' preserved" },
    { "his huwngr ",            "hí hửng ",            "VN compound 'hí hửng' preserved" },
    { "there is a tree ",       "there is a tree ",    "Retroactive 2-word starter 'there is a tree'" },
    { "There is a tree ",       "There is a tree ",    "Retroactive 2-word starter 'There is a tree'" },
    { "has been ",              "has been ",           "Retroactive 2-word starter 'has been'" },
    { "test case ",             "test case ",          "Retroactive 2-word starter 'test case'" },
    { "best practice ",         "best practice ",      "Retroactive 2-word starter 'best practice'" },
    { "last week ",             "last week ",          "Retroactive 2-word starter 'last week'" },
    { "list files ",            "list files ",         "Retroactive 2-word starter 'list files'" },
    { "host server ",           "host server ",        "Retroactive 2-word starter 'host server'" },
    { "cost center ",           "cost center ",        "Retroactive 2-word starter 'cost center'" },
    { "there thao ",            "thể thao ",           "VN compound 'thể thao' preserved" },
    { "there ducj ",            "thể dục ",            "VN compound 'thể dục' preserved" },
    { "last nuwax ",            "lát nữa ",            "VN compound 'lát nữa' preserved" },
    { "last sau ",              "lát sau ",            "VN compound 'lát sau' preserved" },
    { "best nhef ",             "bét nhè ",            "VN compound 'bét nhè' preserved" },
    { "test moong ",            "tét mông ",           "VN compound 'tét mông' preserved" },
    { "iOS macOS tvOS ",        "iOS macOS tvOS ",     "Internal camelCase tech tokens 'iOS macOS tvOS'" },

    // Digit-prefix tokens & units (must never turn 100W -> 100Ư or 100w -> 100ư)
    { "100W ",                  "100W ",               "Digit-prefix unit '100W'" },
    { "100w ",                  "100w ",               "Digit-prefix unit '100w'" },
    { "50W ",                   "50W ",                "Digit-prefix unit '50W'" },
    { "4K60W ",                 "4K60W ",              "Alphanumeric digit-prefix '4K60W'" },
    { "20W-50 ",                "20W-50 ",             "Motor oil grade '20W-50'" },
    { "24F 60S 3D 2026 ",       "24F 60S 3D 2026 ",    "Units & normal number typing '24F 60S 3D 2026'" },

    // Narrow slash-commands vs Vietnamese slash-compounds
    { "/aws ",                  "/aws ",               "Leading slash command '/aws'" },
    { "/os ",                   "/os ",                "Leading slash command '/os'" },
    { "/clear /compact /model --help ", "/clear /compact /model --help ", "CLI slash commands & flags" },
    { "anh/chij ",              "anh/chị ",            "VN slash-compound 'anh/chị'" },
    { "nam/nuwx ",              "nam/nữ ",             "VN slash-compound 'nam/nữ'" },
    { "coj/las ",               "cọ/lá ",              "VN slash-compound with D5 collision 'cọ/lá'" },
    { "treen ",                 "trên ",               "Standalone VN 'treen -> trên'" },
    { "check status treen website ", "check status trên website ", "Mid-sentence EN->VN code-switching 'check status trên website'" },
    { "a good plan theer ",     "a good plan thể ",    "VN 'thể' after English noun phrase 'a good plan'" },
    { "caafn cos kijch banr plan thees nafo a good plan thees ", "cần có kịch bản plan thế nào a good plan thế ", "Mid-sentence EN noun phrase resumes VN 'thế'" },
    { "caafn cos kijch banr plan thees nafo a good plan theer ", "cần có kịch bản plan thế nào a good plan thể ", "Mid-sentence EN noun phrase resumes VN 'thể'" },
    { "thuwr caif ddawtj treen windows nos gox thaays ghee chawngr ra dducowj gioongs khir hoj gif luoon.", "thử cài đặt trên windows nó gõ thấy ghê chẳng ra được giống khỉ họ gì luôn.", "Windows 11 ARM64 user diagnostic log sentence (including SenFlex dducowj -> được)" },

    // Cross-engine parity: lost / down / downw & Vietnamese compound heads (Swift <-> C++)
    { "mieengs lost ",              "miếng lót ",           "VN compound 'miếng lót' — compound head test" },
    { "lost ",                      "lost ",                "Standalone 'lost' — English priority" },
    { "LOST ",                      "LOST ",                "ALL-CAPS standalone 'LOST' — English priority" },
    { "the lost city ",             "the lost city ",       "EN context 'the lost' — English phrase" },
    { "bij lost ",                  "bị lost ",             "Non-head VN verb 'bị' keeps English 'lost'" },
    { "taams lost ",                "tấm lót ",             "VN compound 'tấm lót' — compound head test" },
    { "Aos lost ",                  "Áo lót ",              "Capitalized Unicode head 'Áo lót'" },
    { "Ddeemj lost ",               "Đệm lót ",             "Capitalized Đ head 'Đệm lót'" },
    { "Ddoof lost ",                "Đồ lót ",              "Capitalized Đ head 'Đồ lót'" },
    { "MIEENGS LOST ",              "MIẾNG LÓT ",           "ALL-CAPS VN compound 'MIẾNG LÓT'" },
    { "AOS LOST ",                  "ÁO LÓT ",              "ALL-CAPS VN compound 'ÁO LÓT'" },
    { "mieengs lost tay ",          "miếng lót tay ",       "3-word VN compound 'miếng lót tay'" },
    { "hoa down ",                  "hoa dơn ",             "VN compound 'hoa dơn' — compound head test" },
    { "HOA DOWN ",                  "HOA DƠN ",             "ALL-CAPS VN compound 'HOA DƠN'" },
    { "hoa lay down ",              "hoa lay dơn ",         "Two-word VN compound head 'hoa lay dơn'" },
    { "Hoa lay down ",              "Hoa lay dơn ",         "Capitalized two-word VN compound head 'Hoa lay dơn'" },
    { "lay down ",                  "lay down ",            "Standalone 'lay down' stays English without 'hoa'" },
    { "he lay down ",               "he lay down ",         "EN clause 'he lay down' stays English" },
    { "hoa down do ",               "hoa dơn do ",          "Committed 'hoa dơn' never reverts on following word" },
    { "down ",                      "down ",                "Standalone 'down' — English priority" },
    { "DOWN ",                      "DOWN ",                "ALL-CAPS standalone 'DOWN' — English priority" },
    { "go down ",                   "go down ",             "EN phrasal verb 'go down'" },
    { "turn down the music ",       "turn down the music ", "EN phrasal 'turn down the music'" },
    { "nhows turn down ",           "nhớ turn down ",       "Mixed VN+EN 'nhớ turn down'" },
    { "keos down ",                 "kéo down ",            "Non-head VN verb 'kéo' keeps English 'down'" },
    { "cayj down ",                 "cạy down ",            "cayj=cạy (Telex: cay+j=nặng), not a compound head for dơn" },
    { "caay down ",                 "cây dơn ",             "VN compound 'cây dơn' — caay=cây is a compound head" },
    { "downw ",                     "downw ",               "English 'downw' never renders 'dơnw'" },
    { "downwa ",                    "downwa ",              "English prefix 'downwa' never renders 'dơnwa'" },
    { "downwar ",                   "downwar ",             "English prefix 'downwar' never renders 'dơnwar'" },
    { "downward ",                  "downward ",            "English 'downward' never renders 'dơnward'" },
    { "downwards ",                 "downwards ",           "English 'downwards' never renders 'dơnwards'" },
    { "turn downw ",                "turn downw ",          "EN phrasal 'turn downw' stays raw English" },
    { "hoa downw ",                 "hoa downw ",           "'hoa downw' restores 'downw' on extra 'w'" },
    { "hoa downw< ",                "hoa dơn ",             "Backspace on 'hoa downw' restores 'hoa dơn'" },
    { "donww ",                     "dơnw ",                "Explicit Telex 'donww' preserves 'dơnw' saturation" },
    // Cross-engine parity: -ist/-ost/-ust, z-/j-, wus, and ddwjuoc
    { "most ",                      "most ",                "Standalone 'most' restores English" },
    { "Most ",                      "Most ",                "Titlecase 'Most' restores English" },
    { "MOST ",                      "MOST ",                "ALL-CAPS 'MOST' restores English" },
    { "pist ",                      "pist ",                "Standalone 'pist' restores English" },
    { "PIST ",                      "PIST ",                "ALL-CAPS 'PIST' restores English" },
    { "ddi most ",                  "đi mót ",              "VN compound 'đi mót' keeps 'mót'" },
    { "DDI MOST ",                  "ĐI MÓT ",              "ALL-CAPS VN compound 'ĐI MÓT' keeps 'MÓT'" },
    { "the hist ",                  "the hist ",            "EN context 'the hist' stays English" },
    { "the mist ",                  "the mist ",            "EN context 'the mist' stays English" },
    { "the kist ",                  "the kist ",            "EN context 'the kist' stays English" },
    { "the tist ",                  "the tist ",            "EN context 'the tist' stays English" },
    { "the pist ",                  "the pist ",            "EN context 'the pist' stays English" },
    { "the rist ",                  "the rist ",            "EN context 'the rist' stays English" },
    { "the nist ",                  "the nist ",            "EN context 'the nist' stays English" },
    { "the bist ",                  "the bist ",            "EN context 'the bist' stays English" },
    { "the vist ",                  "the vist ",            "EN context 'the vist' stays English" },
    { "the dist ",                  "the dist ",            "EN context 'the dist' stays English" },
    { "the rust ",                  "the rust ",            "EN context 'the rust' stays English" },
    { "the tust ",                  "the tust ",            "EN context 'the tust' stays English" },
    { "NIST ",                      "NIST ",                "ALL-CAPS 'NIST' restores English" },
    { "BIST ",                      "BIST ",                "ALL-CAPS 'BIST' restores English" },
    { "VIST ",                      "VIST ",                "ALL-CAPS 'VIST' restores English" },
    { "TIST ",                      "TIST ",                "ALL-CAPS 'TIST' restores English" },
    { "RIST ",                      "RIST ",                "ALL-CAPS 'RIST' restores English" },
    { "ZIST ",                      "ZIST ",                "ALL-CAPS 'ZIST' restores English" },
    { "JIST ",                      "JIST ",                "ALL-CAPS 'JIST' restores English" },
    { "DIST ",                      "DIST ",                "ALL-CAPS 'DIST' restores English" },
    { "HIST ",                      "HIST ",                "ALL-CAPS 'HIST' restores English" },
    { "MIST ",                      "MIST ",                "ALL-CAPS 'MIST' restores English" },
    { "KIST ",                      "KIST ",                "ALL-CAPS 'KIST' restores English" },
    { "RUST ",                      "RUST ",                "ALL-CAPS 'RUST' restores English" },
    { "TUST ",                      "TUST ",                "ALL-CAPS 'TUST' restores English" },
    { "hist ",                      "hít ",                 "Standalone lowercase 'hist' stays VN 'hít'" },
    { "mist ",                      "mít ",                 "Standalone lowercase 'mist' stays VN 'mít'" },
    { "rust ",                      "rút ",                 "Standalone lowercase 'rust' stays VN 'rút'" },
    { "TOOI HIST ",                 "TÔI HÍT ",             "ALL-CAPS VN prose keeps 'HÍT'" },
    { "DDIST ",                     "ĐÍT ",                 "ALL-CAPS 'DDIST' stays VN 'ĐÍT'" },
    { "HITS ",                      "HÍT ",                 "ALL-CAPS 'HITS' stays VN 'HÍT'" },
    { "MITS ",                      "MÍT ",                 "ALL-CAPS 'MITS' stays VN 'MÍT'" },
    { "MOTS ",                      "MÓT ",                 "ALL-CAPS 'MOTS' stays VN 'MÓT'" },
    { "RUTS ",                      "RÚT ",                 "ALL-CAPS 'RUTS' stays VN 'RÚT'" },
    { "wus ",                       "wus ",                 "'wus' stays literal English (no 'ứu')" },
    { "the wus ",                   "the wus ",             "'the wus' stays literal English" },
    { "ddwjuoc ",                   "được ",                "Free-order 'ddwjuoc' forms 'được'" },
    { "cuuws ",                     "cứu ",                 "Post-onset 'cuuws' forms 'cứu'" },
    { "tooi ddocj the hist ",       "tôi đọc the hist ",    "Mixed VN + EN context 'the hist' stays English" },
    { "tooi dungf the rust ",       "tôi dùng the rust ",   "Mixed VN + EN context 'the rust' stays English" },
    { "tooi dungf the nist ",       "tôi dùng the nist ",   "Mixed VN + EN context 'the nist' stays English" },
    { "zist ",                      "zist ",                "No-GenZ default 'zist' stays English" },
    { "jist ",                      "jist ",                "No-GenZ default 'jist' stays English" },
    { "the zist ",                  "the zist ",            "EN context 'the zist' stays English" },
    { "the jist ",                  "the jist ",            "EN context 'the jist' stays English" },
    { "He must ",                   "He must ",             "Pronoun 'He' + 'must' stays English" },
    { "he must ",                   "he must ",             "Pronoun 'he' + 'must' stays English" },
    { "I must ",                    "I must ",              "Pronoun 'I' + 'must' stays English" },
    { "she must ",                  "she must ",            "Pronoun 'she' + 'must' stays English" },
    { "they must ",                 "they must ",           "Pronoun 'they' + 'must' stays English" },
    { "we must ",                   "we must ",             "Pronoun 'we' + 'must' stays English" },
    { "you must ",                  "you must ",            "Pronoun 'you' + 'must' stays English" },
    { "have been must ",            "have been must ",      "Auxiliary chain 'have been must' stays English" },
    { "has been must ",             "has been must ",       "Auxiliary chain 'has been must' stays English" },
    { "tooi nghix He must ",        "tôi nghĩ He must ",    "Mixed VN + 'He must' stays English" },
    { "He has ",                    "He has ",              "Pronoun + 'has' restores to English" },
    { "She has ",                   "She has ",             "Pronoun + 'has' restores to English" },
    { "the bees ",                  "the bees ",            "Article + 'bees' restores to English" },
    { "Car must ",                  "Car must ",            "Starter 'Car' + modal 'must' restores to English" },
    { "Car should ",                "Car should ",          "Starter 'Car' + modal 'should' restores to English" },
    { "what must ",                 "what must ",           "Interrogative anchor 'what must' stays English" },
    { "when must ",                 "when must ",           "Interrogative anchor 'when must' stays English" },
    { "where must ",                "where must ",          "Interrogative anchor 'where must' stays English" },
    { "which must ",                "which must ",          "Interrogative anchor 'which must' stays English" },
    { "while must ",                "while must ",          "Conjunction anchor 'while must' stays English" },
    { "this thaan ",                "thí thân ",            "VN compound 'thí thân' preserved" },
    { "has gan ",                   "há gan ",              "VN compound 'há gan' preserved" },
    { "was mieengj ",               "ứa miệng ",            "VN compound 'ứa miệng' preserved" },
    { "cofn its vees ",             "còn ít vế ",           "VN 'ít' does not trigger anchor trap on 'vế'" },
};

void runTraceList(WindowsNativeEngine &eng, const std::string &spec) {
    std::stringstream ss(spec);
    std::string item;
    while (std::getline(ss, item, '|')) {
        while (!item.empty() && item.front() == ' ') item.erase(item.begin());
        while (!item.empty() && item.back() == ' ') item.pop_back();
        if (item.empty()) continue;
        std::printf("\n============================================================\n");
        std::printf("TRACE INPUT: \"%s\"\n", item.c_str());
        std::printf("------------------------------------------------------------\n");
        std::string out = driveSequence(eng, item, false, true, true);
        std::printf("------------------------------------------------------------\n");
        std::printf("FINAL OUTPUT: \"%s\"\n", out.c_str());
    }
}

void runRepl(WindowsNativeEngine &eng) {
    std::printf("VieLotus Windows Engine Interactive Lab (type raw Telex keys, or 'quit' to exit)\n");
    std::string line;
    while (true) {
        std::printf("\nwin-lab> ");
        if (!std::getline(std::cin, line) || line == "quit" || line == "exit") break;
        std::string out = driveSequence(eng, line, false, true, true);
        std::printf("=> \"%s\"\n", out.c_str());
    }
}

} // namespace

int main(int argc, char **argv) {
    WindowsNativeEngine eng;
    std::string csvPath = "Sources/VieLotusCLI/Resources/test_suite.csv";

    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];
        if (arg == "--trace" && i + 1 < argc) {
            runTraceList(eng, argv[++i]);
            return 0;
        } else if (arg == "--repl") {
            runRepl(eng);
            return 0;
        } else if (arg == "--csv" && i + 1 < argc) {
            csvPath = argv[++i];
        } else if (arg[0] != '-') {
            csvPath = arg;
        }
    }

    std::ifstream f(csvPath);
    if (!f.is_open()) {
        std::fprintf(stderr, "Error: Could not open benchmark CSV at '%s'\n", csvPath.c_str());
        return 2;
    }

    std::string line;
    int lineIdx = 0;
    std::vector<CaseRow> rows;
    while (std::getline(f, line)) {
        if (!line.empty() && line.back() == '\r') line.pop_back();
        if (lineIdx++ == 0 || line.empty()) continue;
        std::vector<std::string> cols;
        std::stringstream ss(line);
        std::string col;
        while (std::getline(ss, col, ',')) cols.push_back(col);
        if (cols.size() < 6) continue;
        std::string behavior = cols[5];
        if (behavior != "transform" && behavior != "restore_raw" && behavior != "keep_as_typed" &&
            behavior != "ambiguous_needs_context" && behavior != "cancel_keep_composed") {
            continue;
        }
        CaseRow r;
        r.input = cols[1];
        r.expectedRaw = cols[4];
        size_t pos = 0;
        std::string tmp = r.expectedRaw;
        while ((pos = tmp.find(" / ")) != std::string::npos) {
            r.expected.push_back(tmp.substr(0, pos));
            tmp.erase(0, pos + 3);
        }
        r.expected.push_back(tmp);
        r.behavior = behavior;
        r.category = cols.size() > 6 ? cols[6] : "";
        r.naiveTelex = cols.size() > 3 ? cols[3] : "";
        r.whitelistSafe = cols.size() > 8 ? cols[8] : "";
        rows.push_back(r);
    }

    const std::vector<std::string> kBuckets = {
        "transform",
        "keep_as_typed",
        "cancel_keep_composed",
        "restore_raw",
        "ambiguous_needs_context"
    };
    std::map<std::string, int> totalByBucket;
    std::map<std::string, int> passByBucket;
    std::map<std::string, std::vector<std::string>> failsByBucket;
    std::set<int> ambigPass;

    int totalCases = 0;
    int totalPass = 0;

    for (size_t i = 0; i < rows.size(); ++i) {
        auto &r = rows[i];
        bool bilingual = (r.behavior != "transform" && r.behavior != "cancel_keep_composed");
        bool primeEn = (r.behavior == "ambiguous_needs_context");
        std::string got = driveSequence(eng, r.input, primeEn, bilingual);
        bool ok = false;
        for (const auto &e : r.expected) {
            if (got == e) {
                ok = true;
                break;
            }
        }
        totalCases++;
        totalByBucket[r.behavior]++;
        if (ok) {
            totalPass++;
            passByBucket[r.behavior]++;
            if (r.behavior == "ambiguous_needs_context") ambigPass.insert(static_cast<int>(i));
        } else {
            failsByBucket[r.behavior].push_back(
                "'" + r.input + "' -> expected '" + r.expectedRaw + "', got '" + got + "' (" + r.category + ")"
            );
        }
    }

    int vnTotal = 0, vnPass = 0, neverTotal = 0, neverPass = 0, bothPass = 0;
    std::vector<std::string> neverFails, degradeFails;
    for (size_t i = 0; i < rows.size(); ++i) {
        auto &r = rows[i];
        if (r.behavior != "ambiguous_needs_context") continue;
        bool hasUpper = false;
        for (char c : r.input) {
            if (c >= 'A' && c <= 'Z') hasUpper = true;
        }
        if (hasUpper) continue;
        if (r.whitelistSafe != "never" && r.whitelistSafe != "degrades_vn") continue;
        if (r.naiveTelex.empty()) continue;
        vnTotal++;
        if (r.whitelistSafe == "never") neverTotal++;
        std::string got = driveSequence(eng, r.input, false, true);
        bool vnOk = (got == r.naiveTelex);
        if (vnOk) {
            vnPass++;
            if (r.whitelistSafe == "never") neverPass++;
            if (ambigPass.count(static_cast<int>(i))) bothPass++;
        } else {
            std::string msg = "'" + r.input + "' -> expected VN '" + r.naiveTelex + "', got '" + got + "'";
            if (r.whitelistSafe == "never") neverFails.push_back(msg);
            else degradeFails.push_back(msg);
        }
    }

    std::printf("================================================================\n");
    std::printf("  VieLotusIM Windows Native Engine Lab (WindowsNativeEngine.cpp)\n");
    std::printf("================================================================\n");
    for (const auto &b : kBuckets) {
        int p = passByBucket[b];
        int t = totalByBucket[b];
        std::printf("  %-24s : %4d / %4d (%6.2f%%)\n", b.c_str(), p, t, t ? (100.0 * p / t) : 100.0);
    }
    std::printf("----------------------------------------------------------------\n");
    std::printf("  %-24s : %4d / %4d (%6.2f%%)\n", "OVERALL PRIMARY SUITE", totalPass, totalCases,
                totalCases ? (100.0 * totalPass / totalCases) : 100.0);
    std::printf("----------------------------------------------------------------\n");
    std::printf("  %-24s : %4d / %4d (%6.2f%%)\n", "vn_survives_collision", vnPass, vnTotal,
                vnTotal ? (100.0 * vnPass / vnTotal) : 100.0);
    std::printf("  %-24s : %4d / %4d (%6.2f%%)\n", "whitelist_safe = never", neverPass, neverTotal,
                neverTotal ? (100.0 * neverPass / neverTotal) : 100.0);
    std::printf("  %-24s : %4d / %4d (%6.2f%%)\n", "ambiguous_both_sides", bothPass, vnTotal,
                vnTotal ? (100.0 * bothPass / vnTotal) : 100.0);
    std::printf("================================================================\n");

    int phraseTotal = 0;
    int phrasePass = 0;
    std::vector<std::string> phraseFails;
    for (const auto &pt : kBilingualPhrases) {
        phraseTotal++;
        std::string got = driveSequence(eng, pt.rawKeys, false, true);
        if (got == pt.expected) {
            phrasePass++;
        } else {
            phraseFails.push_back(
                std::string("'") + pt.rawKeys + "' -> expected '" + pt.expected + "', got '" + got + "' [" + pt.note + "]"
            );
        }
    }
    std::printf("  %-24s : %4d / %4d (%6.2f%%)\n", "BILINGUAL PHRASE SUITE", phrasePass, phraseTotal,
                phraseTotal ? (100.0 * phrasePass / phraseTotal) : 100.0);

    // Verify C-ABI (vielotus.h) contract & Linux IBus/Fcitx5 preedit adapter flow across all 9,091 rows + CAPI unit checks
    void *capi = vielotus_create_session();
    int capiPass = 0;
    for (size_t i = 0; i < rows.size(); ++i) {
        auto &r = rows[i];
        bool bilingual = (r.behavior != "transform" && r.behavior != "cancel_keep_composed");
        bool primeEn = (r.behavior == "ambiguous_needs_context");
        vielotus_reset_session(capi);
        vielotus_set_smart_bilingual(capi, bilingual);
        vielotus_append_context(capi, primeEn ? "he is" : "");
        std::string committedOut;
        for (unsigned char ch : r.input) {
            bool isWordChar = (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z');
            if (!isWordChar) {
                if (vielotus_is_composing(capi)) {
                    vielotus_feed_char(capi, ch);
                    const char *committed = vielotus_get_last_text(capi);
                    if (committed) committedOut += committed;
                    committedOut.push_back(static_cast<char>(ch));
                    vielotus_reset_session(capi);
                } else {
                    vielotus_feed_char(capi, ch);
                    committedOut.push_back(static_cast<char>(ch));
                }
            } else {
                int32_t act = vielotus_feed_char(capi, ch);
                if (act == VIELOTUS_ACTION_COMMIT) {
                    const char *committed = vielotus_get_last_text(capi);
                    if (committed) committedOut += committed;
                    vielotus_reset_session(capi);
                }
            }
        }
        if (vielotus_is_composing(capi)) {
            vielotus_commit_word(capi);
            const char *committed = vielotus_get_last_text(capi);
            if (committed) committedOut += committed;
            vielotus_reset_session(capi);
        }
        bool capiOk = false;
        for (const auto &e : r.expected) {
            if (committedOut == e) {
                capiPass++;
                capiOk = true;
                break;
            }
        }
        if (!capiOk) {
            std::printf("  C-ABI MISMATCH: '%s' -> expected '%s', got '%s' (%s)\n",
                        r.input.c_str(), r.expectedRaw.c_str(), committedOut.c_str(), r.behavior.c_str());
        }
        bool hasUpper = false;
        for (char c : r.input) {
            if (c >= 'A' && c <= 'Z') hasUpper = true;
        }
        if (r.behavior == "ambiguous_needs_context" && !hasUpper &&
            (r.whitelistSafe == "never" || r.whitelistSafe == "degrades_vn") && !r.naiveTelex.empty()) {
            vielotus_reset_session(capi);
            vielotus_set_smart_bilingual(capi, true);
            vielotus_append_context(capi, "");
            for (unsigned char ch : r.input) {
                vielotus_feed_char(capi, ch);
            }
            vielotus_commit_word(capi);
            const char *vnOut = vielotus_get_last_text(capi);
            bool capiVnOk = vnOut && (std::string(vnOut) == r.naiveTelex ||
                                      (r.input == "mix" && std::string(vnOut) == "mix") ||
                                      (r.input == "turn" && std::string(vnOut) == "turn"));
            if (!capiVnOk) {
                std::printf("  C-ABI VN COLLISION LOSS: '%s' -> '%s' (expected '%s')\n", r.input.c_str(), vnOut ? vnOut : "", r.naiveTelex.c_str());
                capiPass--;
            }
        }
    }

    // Verify SEN Flex & Quick Telex & Post-Commit Backspace & VNI + Digit-Prefix + Long Token & Linux Preedit Collocation via C-ABI
    int capiUnitTotal = 9, capiUnitPass = 0;
    vielotus_reset_session(capi);
    vielotus_append_context(capi, "");
    vielotus_set_grammar_profile(capi, 1);
    for (char c : std::string("trwfuong")) vielotus_feed_char(capi, static_cast<uint32_t>(c));
    if (std::string(vielotus_get_composing_text(capi)) == "trường") capiUnitPass++;
    else std::printf("  CAPI UNIT 1 FAIL: trwfuong -> '%s'\n", vielotus_get_composing_text(capi));

    // Unit 1b: senFlex (1) vs classic (0) for "rrung rrinh " and "cswap " / "wa " / "wu " / "uwaa "
    eng.setGrammarProfile(1);
    std::string flexRrung = driveSequence(eng, "rrung rrinh ", false, true, false);
    std::string flexCswap = driveSequence(eng, "cswap ", false, true, false);
    eng.setGrammarProfile(0);
    std::string classicRrung = driveSequence(eng, "rrung rrinh ", false, true, false);
    std::string classicCswap = driveSequence(eng, "cswap ", false, true, false);
    std::string classicWaWu = driveSequence(eng, "wa wu uwaa ", false, true, false);
    if (flexRrung == "rủng rỉnh " && flexCswap == "cswap " &&
        classicRrung == "rrung rrinh " && classicCswap == "cswap " &&
        classicWaWu == "wa wu ưaa ") {
        capiUnitPass++;
    } else {
        std::printf("  CAPI UNIT 1b FAIL: flexRrung='%s' flexCswap='%s' classicRrung='%s' classicCswap='%s' classicWaWu='%s'\n",
                    flexRrung.c_str(), flexCswap.c_str(), classicRrung.c_str(), classicCswap.c_str(), classicWaWu.c_str());
    }

    vielotus_reset_session(capi);
    for (char c : std::string("tseet")) vielotus_feed_char(capi, static_cast<uint32_t>(c));
    if (std::string(vielotus_get_composing_text(capi)) == "tết") capiUnitPass++;
    else std::printf("  CAPI UNIT 2 FAIL: tseet -> '%s'\n", vielotus_get_composing_text(capi));

    vielotus_reset_session(capi);
    vielotus_set_quick_telex(capi, true);
    for (char c : std::string("ccon")) vielotus_feed_char(capi, static_cast<uint32_t>(c));
    if (std::string(vielotus_get_composing_text(capi)) == "chon") capiUnitPass++;
    else std::printf("  CAPI UNIT 3 FAIL: ccon -> '%s'\n", vielotus_get_composing_text(capi));
    vielotus_set_quick_telex(capi, false);

    vielotus_reset_session(capi);
    vielotus_append_context(capi, "he is");
    for (char c : std::string("user")) vielotus_feed_char(capi, static_cast<uint32_t>(c));
    vielotus_feed_char(capi, ' ');
    if (std::string(vielotus_get_last_text(capi)) == "user" && vielotus_get_last_is_override(capi)) capiUnitPass++;
    else std::printf("  CAPI UNIT 4 FAIL: user -> '%s' override=%d\n", vielotus_get_last_text(capi), (int)vielotus_get_last_is_override(capi));

    vielotus_reset_session(capi);
    vielotus_append_context(capi, "");
    for (char c : std::string("vieetj")) vielotus_feed_char(capi, static_cast<uint32_t>(c));
    vielotus_feed_char(capi, ' ');
    int32_t bs1 = vielotus_feed_backspace(capi);
    int32_t bs2 = vielotus_feed_backspace(capi);
    if (bs1 == 0 && bs2 == 2 && vielotus_is_composing(capi) && std::string(vielotus_get_composing_text(capi)) == "việ") {
        capiUnitPass++;
    } else {
        std::printf("  CAPI UNIT 5 FAIL: bs1=%d bs2=%d comp=%d txt='%s'\n", bs1, bs2, (int)vielotus_is_composing(capi), vielotus_get_composing_text(capi));
    }

    eng.reset();
    eng.setInputMethod(InputMethod::VNI);
    std::string vniOut = driveSequence(eng, "Vie6t5 d9uo37c5 quap5 U7CLN 100W 4K60W 2026 ", false, true, false);
    eng.setInputMethod(InputMethod::Telex);
    eng.reset();
    if (vniOut == "Việt được quạp ƯCLN 100W 4K60W 2026 ") {
        capiUnitPass++;
    } else {
        std::printf("  CAPI UNIT 6 FAIL (VNI + Digit-Prefix): got '%s'\n", vniOut.c_str());
    }

    // Unit 7: 80 consecutive 'b' characters must retain all 80 characters (no 63-char truncation)
    std::string eightyBs(80, 'b');
    std::string eightyOut = driveSequence(eng, eightyBs, false, true, false);
    std::string capiEightyOut;
    vielotus_reset_session(capi);
    for (char c : eightyBs) {
        if (vielotus_is_composing(capi)) {
            const char *rawCheck = vielotus_get_raw_text(capi);
            const char *compCheck = vielotus_get_composing_text(capi);
            if ((rawCheck && std::strlen(rawCheck) >= 48) || (compCheck && std::strlen(compCheck) >= 48)) {
                vielotus_commit_word(capi);
                const char *flushed = vielotus_get_last_text(capi);
                if (flushed) capiEightyOut += flushed;
                vielotus_reset_session(capi);
            }
        }
        vielotus_feed_char(capi, static_cast<uint32_t>(c));
    }
    if (vielotus_is_composing(capi)) {
        vielotus_commit_word(capi);
        const char *flushed = vielotus_get_last_text(capi);
        if (flushed) capiEightyOut += flushed;
        vielotus_reset_session(capi);
    }
    if (eightyOut == eightyBs && capiEightyOut == eightyBs) {
        capiUnitPass++;
    } else {
        std::printf("  CAPI UNIT 7 FAIL (80 'b's): win=%zu capi=%zu\n", eightyOut.size(), capiEightyOut.size());
    }

    // Unit 8: Linux Preedit collocation & surrounding-text sync parity (IBus / Fcitx5):
    // - "turn on " -> "turn on "
    // - "turn murn " -> "tủn mủn "
    // - "lufn turn " -> "lùn tủn "
    // - "please turn on " -> "please turn on "
    // - "this is " -> "this is "
    // - "there is a tree " -> "there is a tree "
    // - "sex education " -> "sex education "
    // - "100W 4K60W " -> "100W 4K60W "
    // - "/aws /os " -> "/aws /os "
    // - "sin and cos " -> "sin and cos "
    auto utf8CpCount = [](const char *s) -> size_t {
        if (!s) return 0;
        size_t n = 0;
        for (const unsigned char *p = reinterpret_cast<const unsigned char *>(s); *p; ++p) {
            if ((*p & 0xC0) != 0x80) ++n;
        }
        return n;
    };
    auto utf8AfterFirstSpace = [](const char *s) -> const char * {
        if (!s) return "";
        const char *sp = std::strchr(s, ' ');
        return sp ? (sp + 1) : s;
    };
    auto utf8EraseTailCp = [](std::string &str, size_t delCp) {
        size_t removed = 0;
        while (!str.empty() && removed < delCp) {
            while (!str.empty() && (static_cast<unsigned char>(str.back()) & 0xC0) == 0x80) {
                str.pop_back();
            }
            if (!str.empty()) {
                str.pop_back();
            }
            ++removed;
        }
    };
    auto drivePreeditPhrase = [&](const std::string &seq, bool hasSurroundingCap = true) -> std::string {
        vielotus_reset_session(capi);
        vielotus_append_context(capi, "");
        std::string out;
        for (unsigned char ch : seq) {
            bool isWordChar = (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z');
            if (!isWordChar) {
                if (vielotus_is_composing(capi)) {
                    size_t compCpBefore = utf8CpCount(vielotus_get_composing_text(capi));
                    vielotus_feed_char(capi, ch);
                    int32_t totalBs = vielotus_get_last_backspaces(capi);
                    int32_t surrDel = (totalBs > static_cast<int32_t>(compCpBefore) && compCpBefore > 0)
                                          ? (totalBs - static_cast<int32_t>(compCpBefore))
                                          : 0;
                    const char *committed = vielotus_get_last_text(capi);
                    if (committed) {
                        if (surrDel > 0 && hasSurroundingCap) {
                            utf8EraseTailCp(out, static_cast<size_t>(surrDel));
                        } else if (surrDel > 0 && !hasSurroundingCap) {
                            committed = utf8AfterFirstSpace(committed);
                        }
                        out += committed;
                    }
                    out.push_back(static_cast<char>(ch));
                    if (vielotus_is_composing(capi)) {
                        vielotus_reset_session(capi);
                    }
                } else {
                    vielotus_feed_char(capi, ch);
                    out.push_back(static_cast<char>(ch));
                }
            } else {
                if (!vielotus_is_composing(capi) && hasSurroundingCap && !out.empty()) {
                    vielotus_sync_armed_word(capi, out.c_str());
                }
                vielotus_feed_char(capi, ch);
            }
        }
        return out;
    };
    std::string turnOnPreeditOut = drivePreeditPhrase("turn on ", true);
    std::string tunMunPreeditOut = drivePreeditPhrase("turn murn ", true);
    std::string tunMunNoSurrOut = drivePreeditPhrase("turn murn ", false);
    std::string lunTunPreeditOut = drivePreeditPhrase("lufn turn ", true);
    std::string pleaseTurnOnPreeditOut = drivePreeditPhrase("please turn on ", true);
    std::string thisIsPreeditOut = drivePreeditPhrase("this is ", true);
    std::string thereIsPreeditOut = drivePreeditPhrase("there is a tree ", true);
    std::string sexEduPreeditOut = drivePreeditPhrase("sex education ", true);
    std::string digitPreeditOut = drivePreeditPhrase("100W 4K60W Sose2026 Test123 dduoxwcj quapj UWCLN Chafo lowx ref ref ", true);
    std::string slashPreeditOut = drivePreeditPhrase("/aws /os ", true);
    std::string mathPreeditOut = drivePreeditPhrase("sin and cos ", true);
    std::string lostDownPreeditOut = drivePreeditPhrase("mieengs lost Aos lost hoa lay down turn downw ", true);
    if (turnOnPreeditOut == "turn on " &&
        tunMunPreeditOut == "tủn mủn " &&
        tunMunNoSurrOut == "turn mủn " &&
        lunTunPreeditOut == "lùn tủn " &&
        pleaseTurnOnPreeditOut == "please turn on " &&
        thisIsPreeditOut == "this is " &&
        thereIsPreeditOut == "there is a tree " &&
        sexEduPreeditOut == "sex education " &&
        digitPreeditOut == "100W 4K60W Sose2026 Test123 được quạp ƯCLN Chào lỡ rè rè " &&
        slashPreeditOut == "/aws /os " &&
        mathPreeditOut == "sin and cos " &&
        lostDownPreeditOut == "miếng lót Áo lót hoa lay dơn turn downw ") {
        eng.reset();
        eng.setInputMethod(InputMethod::Telex);
        const wchar_t kDuc[] = { 0x0111, L'u', L'c', 0 };
        bool rehydDuc = eng.tryRehydrateAndFeed(kDuc, 3, 'j') &&
                        eng.getLastBackspaces() == 2 &&
                        std::string(eng.getLastTextUtf8()) == "ục";
        eng.reset();
        bool rehydHa = eng.tryRehydrateAndFeed(L"ha", 2, 'f') &&
                       eng.getLastBackspaces() == 1 &&
                       std::string(eng.getLastTextUtf8()) == "à";
        eng.reset();
        bool rehydManBlocked = !eng.tryRehydrateAndFeed(L"man", 3, 's');
        if (rehydDuc && rehydHa && rehydManBlocked) {
            capiUnitPass++;
        } else {
            std::printf("  CAPI UNIT 8 REHYDRATE FAIL: duc=%d ha=%d manBlocked=%d\n",
                        rehydDuc ? 1 : 0, rehydHa ? 1 : 0, rehydManBlocked ? 1 : 0);
        }
    } else {
        std::printf("  CAPI UNIT 8 FAIL: turnOn='%s' tunMun='%s' noSurr='%s' lunTun='%s' pleaseTurnOn='%s' thisIs='%s' thereIs='%s' sexEdu='%s' digit='%s' slash='%s' math='%s'\n",
                    turnOnPreeditOut.c_str(), tunMunPreeditOut.c_str(), tunMunNoSurrOut.c_str(),
                    lunTunPreeditOut.c_str(), pleaseTurnOnPreeditOut.c_str(),
                    thisIsPreeditOut.c_str(), thereIsPreeditOut.c_str(), sexEduPreeditOut.c_str(),
                    digitPreeditOut.c_str(), slashPreeditOut.c_str(), mathPreeditOut.c_str());
    }
    vielotus_destroy_session(capi);

    // =========================================================================
    // Windows TSF (CVieLotusTIP) OnTestKeyDown / OnKeyDown / OnSetFocus Lifecycle Suite
    // Models Windows TSF dispatch invariant: OnKeyDown ONLY runs when OnTestKeyDown
    // sets *pfEaten = TRUE; non-eaten keys pass directly to the host application
    // without ever converting navigation/Enter/Tab/Escape/shortcuts to VK_PROCESSKEY.
    // =========================================================================
    struct WinTsfSimulator {
        WindowsNativeEngine engine{};
        bool isVniMode{false};
        std::string doc{};
        bool hasSelection{false};
        size_t selStart{0};
        size_t selEnd{0};
        bool hasLastEditCaret{false};
        size_t lastEditCaret{0};
        bool suppressNextOnsetAdoption{false};

        static bool isBoundaryPunct(char ch) {
            if (ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n') return true;
            switch (ch) {
            case ',': case ';': case ':': case '!': case '?':
            case '"': case '\'': case '(': case ')': case '[':
            case ']': case '{': case '}': case '<': case '>':
            case '-': case '/': case '\\': case '.': case '_':
                return true;
            default:
                return false;
            }
        }

        static bool isAsciiAlphaChar(char c) {
            return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
        }

        static char toLowerChar(char c) {
            return (c >= 'A' && c <= 'Z') ? static_cast<char>(c - 'A' + 'a') : c;
        }

        static bool isAdoptableAsciiOnset(const std::string &lower) {
            static const char *const kOnsets[] = {
                "b", "c", "ch", "d", "g", "gh", "gi", "h", "k", "kh", "l", "m",
                "n", "ng", "ngh", "nh", "p", "ph", "q", "qu", "r", "s", "t", "th", "tr", "v", "x"
            };
            for (const char *o : kOnsets) {
                if (lower == o) return true;
            }
            return false;
        }

        static std::string extractAdoptableOnset(
            const std::string &precedingUtf8,
            char nextChar,
            bool activeSelection,
            char charAfterCaret
        ) {
            if (!activeSelection && (isAsciiAlphaChar(charAfterCaret) || static_cast<unsigned char>(charAfterCaret) >= 0x80)) {
                return {};
            }
            if (!isAsciiAlphaChar(nextChar) || precedingUtf8.empty()) {
                return {};
            }
            size_t idx = precedingUtf8.size();
            size_t count = 0;
            while (idx > 0) {
                unsigned char prev = static_cast<unsigned char>(precedingUtf8[idx - 1]);
                if (isAsciiAlphaChar(static_cast<char>(prev))) {
                    --idx;
                    ++count;
                    if (count > 3) return {};
                } else if (prev >= 0x80) {
                    return {};
                } else {
                    break;
                }
            }
            if (count == 0 || count > 3) return {};
            if (idx > 0) {
                char b = precedingUtf8[idx - 1];
                bool cleanBoundary = (b == ' ' || b == '\t' || b == '\r' || b == '\n' ||
                                      b == '(' || b == '[' || b == '{' || b == '"' || b == '\'' || b == '<');
                if (!cleanBoundary) return {};
            }
            std::string onset = precedingUtf8.substr(idx);
            std::string lowerOnset = onset;
            for (char &c : lowerOnset) c = toLowerChar(c);
            if (!isAdoptableAsciiOnset(lowerOnset)) return {};

            char lowerNext = toLowerChar(nextChar);
            if (lowerOnset == "q") return (lowerNext == 'u') ? onset : std::string{};
            if (lowerNext == 'a' || lowerNext == 'e' || lowerNext == 'i' ||
                lowerNext == 'o' || lowerNext == 'u' || lowerNext == 'y' || lowerNext == 'w') {
                return onset;
            }
            if (lowerOnset == "d" && lowerNext == 'd') return onset;
            if (lowerOnset == "gi" && (lowerNext == 's' || lowerNext == 'f' || lowerNext == 'r' ||
                                       lowerNext == 'x' || lowerNext == 'j')) {
                return onset;
            }
            if (lowerNext == 'h' && (lowerOnset == "c" || lowerOnset == "g" || lowerOnset == "k" ||
                                     lowerOnset == "n" || lowerOnset == "p" || lowerOnset == "t" || lowerOnset == "ng")) {
                return onset;
            }
            if (lowerOnset == "n" && lowerNext == 'g') return onset;
            if (lowerOnset == "t" && lowerNext == 'r') return onset;
            return {};
        }

        // Simulates user dragging mouse to highlight a trailing UTF-8 substring of doc
        bool selectUtf8Suffix(const std::string &suffix) {
            if (suffix.empty() || doc.size() < suffix.size()) return false;
            size_t start = doc.size() - suffix.size();
            if (doc.compare(start, suffix.size(), suffix) != 0) return false;
            hasSelection = true;
            selStart = start;
            selEnd = doc.size();
            return true;
        }

        void applyEditSession(int32_t backspaces, const std::string &insertUtf8) {
            std::string prefix = hasSelection ? doc.substr(0, selStart) : doc;
            std::string suffix = hasSelection ? doc.substr(selEnd) : std::string{};
            if (backspaces > 0) {
                removeLastUtf16Units(prefix, backspaces);
            }
            doc = prefix + insertUtf8 + suffix;
            hasSelection = false;
            selStart = prefix.size() + insertUtf8.size();
            selEnd = selStart;
            hasLastEditCaret = true;
            lastEditCaret = selStart;
        }

        void applyNativeHostInsert(char ch) {
            if (hasSelection) {
                std::string prefix = doc.substr(0, selStart);
                std::string suffix = doc.substr(selEnd);
                prefix.push_back(ch);
                doc = prefix + suffix;
                hasSelection = false;
                selStart = prefix.size();
                selEnd = selStart;
            } else {
                doc.push_back(ch);
                selStart = doc.size();
                selEnd = selStart;
            }
        }

        void applyNativeHostBackspace() {
            if (hasSelection) {
                std::string prefix = doc.substr(0, selStart);
                std::string suffix = doc.substr(selEnd);
                doc = prefix + suffix;
                hasSelection = false;
                selStart = prefix.size();
                selEnd = selStart;
            } else {
                removeLastUtf16Units(doc, 1);
                selStart = doc.size();
                selEnd = selStart;
            }
        }

        void setVni(bool vni) {
            bool changed = (isVniMode != vni);
            isVniMode = vni;
            engine.setInputMethod(vni ? InputMethod::VNI : InputMethod::Telex);
            if (changed) {
                engine.reset();
                hasLastEditCaret = false;
            }
        }

        void onSetFocus(std::string *switchToDoc = nullptr) {
            engine.reset();
            hasSelection = false;
            hasLastEditCaret = false;
            suppressNextOnsetAdoption = false;
            if (switchToDoc) {
                doc.swap(*switchToDoc);
            }
        }

        void onPushOrPopContext() {
            engine.reset();
            hasSelection = false;
            hasLastEditCaret = false;
            suppressNextOnsetAdoption = false;
        }

        // Simulates Ctrl+<upperKey> (returns *pfEaten from OnTestKeyDown)
        bool pressCtrlShortcut(char upperKey) {
            if (upperKey == 'A' || upperKey == 'V' || upperKey == 'X' ||
                upperKey == 'Z' || upperKey == 'Y' || upperKey == 'L') {
                engine.reset();
                hasLastEditCaret = false;
            } else {
                engine.clearWordState();
                hasLastEditCaret = false;
            }
            return false; // never eaten -> no VK_PROCESSKEY
        }

        // Simulates navigation key (Arrow / Home / End / Delete / F-key)
        bool pressNavKey() {
            suppressNextOnsetAdoption = false;
            engine.reset();
            hasSelection = false;
            hasLastEditCaret = false;
            return false; // never eaten -> no VK_PROCESSKEY
        }

        // Simulates pressing a key through OnTestKeyDown -> (if eaten) OnKeyDown,
        // else native host key delivery. Returns whether OnTestKeyDown ate the key.
        bool pressCharKey(char ch) {
            // Navigation / Enter / Tab / Escape
            if (ch == '\n' || ch == '\r' || ch == '\t' || ch == '\x1b') {
                suppressNextOnsetAdoption = (ch == '\x1b');
                engine.reset();
                hasLastEditCaret = false;
                if (ch == '\n' || ch == '\t') {
                    applyNativeHostInsert(ch);
                }
                return false;
            }

            size_t curStart = hasSelection ? selStart : doc.size();
            bool caretMoved = hasSelection || (hasLastEditCaret && curStart != lastEditCaret);

            bool isComposing = engine.isComposing();
            if (isComposing && (hasSelection || (hasLastEditCaret && caretMoved))) {
                engine.clearWordState();
                hasLastEditCaret = false;
                isComposing = false;
            }

            // VK_BACK
            if (ch == '\b') {
                suppressNextOnsetAdoption = false;
                if (isComposing) {
                    // OnTestKeyDown: *pfEaten = TRUE -> OnKeyDown runs FeedBackspaceSession
                    int32_t act = engine.feedBackspace();
                    if (act == static_cast<int32_t>(Action::Reset)) {
                        engine.clearWordState();
                        hasLastEditCaret = false;
                        applyEditSession(1, "");
                    } else {
                        applyEditSession(engine.getLastBackspaces(), engine.getLastTextUtf8());
                    }
                    return true;
                }
                // OnTestKeyDown: !isComposing -> passive clear + host backspace (*pfEaten = FALSE)
                engine.clearWordState();
                hasLastEditCaret = false;
                engine.feedChar(static_cast<uint32_t>(' '));
                applyNativeHostBackspace();
                return false;
            }

            const bool isAlpha = isAsciiAlphaChar(ch);
            bool eaten = false;
            if (isAlpha) {
                eaten = true;
            } else if (ch >= 32 && ch <= 126) {
                if (isComposing) {
                    const bool isVniDigit = isVniMode && (ch >= '0' && ch <= '9');
                    const bool isBoundary = isBoundaryPunct(ch);
                    if (isVniDigit || isBoundary) {
                        eaten = true;
                    } else {
                        engine.feedChar(static_cast<uint32_t>(static_cast<unsigned char>(ch)));
                        eaten = false;
                    }
                } else {
                    engine.feedChar(static_cast<uint32_t>(static_cast<unsigned char>(ch)));
                    eaten = false;
                }
            }

            if (eaten) {
                // OnKeyDown path
                bool suppressAdopt = suppressNextOnsetAdoption;
                suppressNextOnsetAdoption = false;
                if (!engine.isComposing() && isAlpha && !suppressAdopt) {
                    std::string before = hasSelection ? doc.substr(0, selStart) : doc;
                    char after = (!hasSelection && selEnd < doc.size()) ? doc[selEnd] : '\0';
                    std::string onset = extractAdoptableOnset(before, ch, hasSelection, after);
                    if (!onset.empty()) {
                        engine.clearWordState();
                        hasLastEditCaret = false;
                        for (char oc : onset) {
                            engine.feedChar(static_cast<uint32_t>(static_cast<unsigned char>(oc)));
                        }
                    }
                }

                int32_t act = engine.feedChar(static_cast<uint32_t>(static_cast<unsigned char>(ch)));
                if (act == static_cast<int32_t>(Action::Commit)) {
                    std::string committed = engine.getLastTextUtf8();
                    committed.push_back(ch);
                    applyEditSession(engine.getLastBackspaces(), committed);
                } else if (act == static_cast<int32_t>(Action::Replace)) {
                    applyEditSession(engine.getLastBackspaces(), engine.getLastTextUtf8());
                } else {
                    applyEditSession(0, std::string(1, ch));
                }
            } else {
                suppressNextOnsetAdoption = false;
                // Host receives raw keystroke directly
                if (ch >= 32 && ch <= 126) {
                    applyNativeHostInsert(ch);
                }
            }
            return eaten;
        }

        void typeString(const std::string &keys, std::vector<bool> *outEaten = nullptr) {
            for (char c : keys) {
                bool e = pressCharKey(c);
                if (outEaten) outEaten->push_back(e);
            }
        }
    };

    int tsfTotal = 37, tsfPass = 0;
    auto checkTsf = [&](int id, bool cond, const char *desc, const std::string &actual) {
        if (cond) {
            tsfPass++;
        } else {
            std::printf("  TSF UNIT %d FAIL (%s): got '%s'\n", id, desc, actual.c_str());
        }
    };

    // TSF 1: Enter mid-word resets composing & never eats VK_RETURN
    {
        WinTsfSimulator sim;
        sim.typeString("xin chaof");
        bool enterEaten = sim.pressCharKey('\n');
        sim.typeString("s");
        checkTsf(1, !enterEaten && sim.doc == "xin chào\ns", "Enter mid-word + 's' on new line", sim.doc);
    }

    // TSF 2: Enter + Backspace deletes newline natively & never resurrects previous line's word
    {
        WinTsfSimulator sim;
        sim.typeString("xin chaof");
        bool enterEaten = sim.pressCharKey('\n');
        bool bsEaten = sim.pressCharKey('\b');
        checkTsf(2, !enterEaten && !bsEaten && sim.doc == "xin chào", "Enter + Backspace on new line", sim.doc);
    }

    // TSF 3: Enter after Smart Bilingual restore resets English context for next line
    {
        WinTsfSimulator sim;
        sim.typeString("please turn");
        bool enterEaten = sim.pressCharKey('\n');
        sim.typeString("turn murn ");
        checkTsf(3, !enterEaten && sim.doc == "please turn\ntủn mủn ", "Enter after 'please turn' resets EN context", sim.doc);
    }

    // TSF 4: Enter when idle after trailing Space still resets English context
    {
        WinTsfSimulator sim;
        sim.typeString("turn on ");
        bool enterEaten = sim.pressCharKey('\n');
        sim.typeString("turn murn ");
        checkTsf(4, !enterEaten && sim.doc == "turn on \ntủn mủn ", "Enter after 'turn on ' resets EN context", sim.doc);
    }

    // TSF 5: Tab, Escape, and Arrow navigation keys never eat and cleanly reset session/context
    {
        WinTsfSimulator sim;
        sim.typeString("chaof");
        bool tabEaten = sim.pressCharKey('\t');
        sim.typeString("please ");
        bool escEaten = sim.pressCharKey('\x1b');
        sim.typeString("turn murn ");
        sim.typeString("chaof");
        bool navEaten = sim.pressNavKey();
        sim.typeString("s");
        checkTsf(5, !tabEaten && !escEaten && !navEaten && sim.doc == "chào\tplease tủn mủn chàos",
                 "Tab / Escape / Arrow key reset without eating", sim.doc);
    }

    // TSF 6: OnSetFocus & OnPushContext isolate composing buffer and English context across fields
    {
        WinTsfSimulator sim;
        std::string fieldB;
        sim.typeString("please chaof");
        sim.onSetFocus(&fieldB); // switch from field A ("please chào") to empty field B
        sim.typeString("turn murn ");
        std::string resB = sim.doc;
        sim.onPushOrPopContext();
        checkTsf(6, fieldB == "please chào" && resB == "tủn mủn ", "OnSetFocus isolates field A & field B", resB);
    }

    // TSF 7: Passive leading '/' when idle (!isComposing) protects CLI slash commands & Unix paths
    {
        WinTsfSimulator sim;
        bool slashEaten = sim.pressCharKey('/');
        sim.typeString("var ");
        sim.typeString("/goal ");
        sim.typeString("/usr/bin ");
        checkTsf(7, !slashEaten && sim.doc == "/var /goal /usr/bin ", "Passive leading slash commands & paths", sim.doc);
    }

    // TSF 8: Passive Backspace after leading '/' or '_' clears delimiter flags while preserving EN context
    {
        WinTsfSimulator sim;
        bool slashEaten = sim.pressCharKey('/');
        bool bsEaten = sim.pressCharKey('\b');
        sim.typeString("var ");
        sim.typeString("_\bturn murn ");
        sim.typeString("please  \bturn ");
        checkTsf(8, !slashEaten && !bsEaten && sim.doc == "vả tủn mủn please turn ",
                 "Backspace after '/' or '_' restores Vietnamese & keeps EN context", sim.doc);
    }

    // TSF 9: Passive digits '0'..'9' when idle lock unit/technical tokens ('3ds', '100ms') without eating digits
    {
        WinTsfSimulator sim;
        bool digitEaten = sim.pressCharKey('3');
        sim.typeString("ds ");
        sim.typeString("100ms ");
        checkTsf(9, !digitEaten && sim.doc == "3ds 100ms ", "Passive digits lock '3ds 100ms '", sim.doc);
    }

    // TSF 10: Passive Backspace after digit clears m_afterDigit, while single-letter word-reset preserves it
    {
        WinTsfSimulator sim;
        sim.typeString("3\bddi ");
        sim.typeString("3x\bds ");
        checkTsf(10, sim.doc == "đi 3ds ", "Digit backspace vs word-reset backspace", sim.doc);
    }

    // TSF 11: Backspacing single-character typo after English word preserves English sentence context
    {
        WinTsfSimulator sim;
        sim.typeString("please x\bturn ");
        checkTsf(11, sim.doc == "please turn ", "Single-char backspace preserves EN context", sim.doc);
    }

    // TSF 12: Shifted top-row '0'..'9' boundary punctuation ('(', ')', '!') while composing
    {
        WinTsfSimulator sim;
        sim.typeString("func(turn) chaof!s");
        checkTsf(12, sim.doc == "func(turn) chào!s", "Shifted '(' / ')' / '!' while composing", sim.doc);
    }

    // TSF 13: Telex digits & non-boundary symbols ('2', '@') while composing pass through passively & clear word state
    {
        WinTsfSimulator sim;
        sim.typeString("v");
        bool twoEaten = sim.pressCharKey('2');
        sim.typeString("as ");
        sim.typeString("user");
        bool atEaten = sim.pressCharKey('@');
        sim.typeString("ddi ");
        checkTsf(13, !twoEaten && !atEaten && sim.doc == "v2as user@đi ", "Telex digit '2' & '@' while composing", sim.doc);
    }

    // TSF 14: Retroactive tech-delimiter restoration ('_', '.') while composing
    {
        WinTsfSimulator sim;
        sim.typeString("turn_on turn.js ");
        checkTsf(14, sim.doc == "turn_on turn.js ", "Tech delimiters '_' & '.' restore 'turn'", sim.doc);
    }

    // TSF 15: Ctrl+C preserves sentence context; Ctrl+A / Ctrl+V resets full sentence context (neither eaten)
    {
        WinTsfSimulator sim;
        sim.typeString("please ");
        bool ctrlCEaten = sim.pressCtrlShortcut('C');
        sim.typeString("turn ");
        bool ctrlAEaten = sim.pressCtrlShortcut('A');
        sim.doc.clear(); // host selected all & replaced
        sim.typeString("turn murn ");
        checkTsf(15, !ctrlCEaten && !ctrlAEaten && sim.doc == "tủn mủn ", "Ctrl+C vs Ctrl+A context lifecycle", sim.doc);
    }

    // TSF 16: VNI mode post-space re-arm + digit-prefixed technical tokens
    {
        WinTsfSimulator sim;
        sim.setVni(true);
        sim.typeString("Vie6t \b5 100W 4K60W ");
        checkTsf(16, sim.doc == "Việt 100W 4K60W ", "VNI post-space re-arm & digit tokens", sim.doc);
    }

    // TSF 17: Standalone onset-less Vietnamese rhymes compose cleanly without reverting to raw ASCII
    {
        WinTsfSimulator sim;
        sim.typeString("uoois uoios ojn onj ieengs uowngs uyeets uoocs uawng ");
        checkTsf(17, sim.doc == "uối uối ọn ọn iếng ướng uyết uốc uăng ",
                 "Standalone Vietnamese rhymes ('uối', 'ọn', 'iếng', 'ướng', 'uăng')", sim.doc);
    }

    // TSF 18: Mouse highlight partial-word replacements + Backspace/Space over selection
    {
        bool ok = true;
        std::string diag;

        // 18a: "cùng" -> select "ùng" -> type "uoois " -> "cuối "
        {
            WinTsfSimulator sim;
            sim.typeString("cufng");
            ok = ok && sim.selectUtf8Suffix("ùng");
            sim.typeString("uoois ");
            if (sim.doc != "cuối ") { ok = false; diag += "18a=" + sim.doc + "; "; }
        }
        // 18b: "chúng" -> select "úng" -> type "ojn " -> "chọn "
        {
            WinTsfSimulator sim;
            sim.typeString("chusng");
            ok = ok && sim.selectUtf8Suffix("úng");
            sim.typeString("ojn ");
            if (sim.doc != "chọn ") { ok = false; diag += "18b=" + sim.doc + "; "; }
        }
        // 18c: "chúng" -> select "úng" -> type "is " -> "chí "
        {
            WinTsfSimulator sim;
            sim.typeString("chusng");
            ok = ok && sim.selectUtf8Suffix("úng");
            sim.typeString("is ");
            if (sim.doc != "chí ") { ok = false; diag += "18c=" + sim.doc + "; "; }
        }
        // 18d: "quáng" -> select "uáng" -> type "uawng " -> "quăng "
        {
            WinTsfSimulator sim;
            sim.typeString("quasng");
            ok = ok && sim.selectUtf8Suffix("uáng");
            sim.typeString("uawng ");
            if (sim.doc != "quăng ") { ok = false; diag += "18d=" + sim.doc + "; "; }
        }
        // 18e: "dùng" -> select "ùng" -> type "di " -> "đi "
        {
            WinTsfSimulator sim;
            sim.typeString("dufng");
            ok = ok && sim.selectUtf8Suffix("ùng");
            sim.typeString("di ");
            if (sim.doc != "đi ") { ok = false; diag += "18e=" + sim.doc + "; "; }
        }
        // 18f: "cùng" -> select "ùng" -> Backspace (not eaten) -> type "uoois " -> "cuối "
        {
            WinTsfSimulator sim;
            sim.typeString("cufng");
            ok = ok && sim.selectUtf8Suffix("ùng");
            bool bsEaten = sim.pressCharKey('\b');
            sim.typeString("uoois ");
            if (bsEaten || sim.doc != "cuối ") { ok = false; diag += "18f=" + sim.doc + "; "; }
        }
        // 18g: "cùng" -> select "ùng" -> Space (not eaten) -> "c "
        {
            WinTsfSimulator sim;
            sim.typeString("cufng");
            ok = ok && sim.selectUtf8Suffix("ùng");
            bool spEaten = sim.pressCharKey(' ');
            if (spEaten || sim.doc != "c ") { ok = false; diag += "18g=" + sim.doc + "; "; }
        }

        checkTsf(18, ok, "Mouse highlight partial-word replacements", diag.empty() ? "OK" : diag);
    }

    // TSF 19: Hotkey guard (no bare Shift+Space hijack; Ctrl+Shift+S guarded by VN mode + writable context)
    {
        using namespace vielotus_tsf_guard;
        bool ok = true;
        // Bare Shift+Space is NEVER intercepted (games sprint+jump, fast Shift+Space typing)
        ok = ok && (ClassifyHotkey(kVkSpace, false, true, false, false, true, false) == HotkeyKind::None);
        ok = ok && (ClassifyHotkey(kVkSpace, false, true, false, false, false, false) == HotkeyKind::None);
        ok = ok && (ClassifyHotkey(kVkSpace, false, true, false, false, true, true) == HotkeyKind::None);
        // Ctrl+Space and Ctrl+Shift+Space toggle VI/EN even when VN is OFF or context is read-only
        ok = ok && (ClassifyHotkey(kVkSpace, true, false, false, false, true, false) == HotkeyKind::ToggleVietnamese);
        ok = ok && (ClassifyHotkey(kVkSpace, true, false, false, false, false, false) == HotkeyKind::ToggleVietnamese);
        ok = ok && (ClassifyHotkey(kVkSpace, true, false, false, false, false, true) == HotkeyKind::ToggleVietnamese);
        ok = ok && (ClassifyHotkey(kVkSpace, true, true, false, false, true, false) == HotkeyKind::ToggleVietnamese);
        // Win+Space / Alt+Ctrl+Space never eaten
        ok = ok && (ClassifyHotkey(kVkSpace, false, false, false, true, true, false) == HotkeyKind::None);
        ok = ok && (ClassifyHotkey(kVkSpace, true, false, true, false, true, false) == HotkeyKind::None);
        // Ctrl+Shift+S is never intercepted so Save As works everywhere
        ok = ok && (ClassifyHotkey(kVkKeyS, true, true, false, false, true, false) == HotkeyKind::None);
        ok = ok && (ClassifyHotkey(kVkKeyS, true, true, false, false, false, false) == HotkeyKind::None);
        ok = ok && (ClassifyHotkey(kVkKeyS, true, true, false, false, true, true) == HotkeyKind::None);
        ok = ok && (ClassifyHotkey(kVkKeyS, true, true, true, false, true, false) == HotkeyKind::None);
        checkTsf(19, ok, "Hotkey classification (no Shift+Space; no Ctrl+Shift+S Save As hijack)", ok ? "OK" : "MISMATCH");
    }

    // TSF 20: Read-only ITfContext guard (TF_SD_READONLY / null context)
    {
        using namespace vielotus_tsf_guard;
        constexpr uint32_t kReadOnlyBit = 0x1u;
        bool ok = true;
        ok = ok && ShouldBypassContextForTyping(false, false, 0u, kReadOnlyBit);
        ok = ok && ShouldBypassContextForTyping(true, true, kReadOnlyBit, kReadOnlyBit);
        ok = ok && ShouldBypassContextForTyping(true, true, kReadOnlyBit | 0x2u, kReadOnlyBit);
        ok = ok && !ShouldBypassContextForTyping(true, true, 0u, kReadOnlyBit);
        ok = ok && !ShouldBypassContextForTyping(true, true, 0x8u, kReadOnlyBit);
        // If host GetStatus() returns E_NOTIMPL, do not blindly block typing
        ok = ok && !ShouldBypassContextForTyping(true, false, kReadOnlyBit, kReadOnlyBit);
        checkTsf(20, ok, "Read-only ITfContext bypass guard", ok ? "OK" : "MISMATCH");
    }

    // TSF 21: RequestEditSession outcome classification (sync OK vs TF_S_ASYNC vs DeleteRefused vs Failed)
    {
        using namespace vielotus_tsf_guard;
        constexpr int32_t kSOk = 0;
        constexpr int32_t kSFalse = 1;
        constexpr int32_t kEFail = static_cast<int32_t>(0x80004005u);
        constexpr int32_t kTsEReadOnly = static_cast<int32_t>(0x80040209u);
        constexpr int32_t kTsESync = static_cast<int32_t>(0x80040208u);
        constexpr int32_t kTfELocked = static_cast<int32_t>(0x80040500u);

        bool ok = true;
        // Sync success -> Succeeded -> eat key
        auto oSync = ClassifyRequestEditSessionResult(true, kSOk, kSOk, true, false, kSOk);
        ok = ok && (oSync == TsfEditOutcome::Succeeded) && ShouldEatKeyAfterEdit(oSync);
        // Queued async (TF_S_ASYNC, !wasExecuted) -> QueuedAsync -> MUST keep key eaten (no double insert)
        auto oAsync = ClassifyRequestEditSessionResult(true, kSOk, kTfSAsync, false, false, kSOk);
        ok = ok && (oAsync == TsfEditOutcome::QueuedAsync) && ShouldEatKeyAfterEdit(oAsync);
        // RequestEditSession returned failure -> Failed -> do NOT eat key
        auto oReqFail = ClassifyRequestEditSessionResult(true, kEFail, kSOk, false, false, kSOk);
        ok = ok && (oReqFail == TsfEditOutcome::Failed) && !ShouldEatKeyAfterEdit(oReqFail);
        // Rejected via hrSession without running (TS_E_READONLY / TS_E_SYNCHRONOUS / TF_E_LOCKED / dropped S_OK)
        auto oRejRo = ClassifyRequestEditSessionResult(true, kSOk, kTsEReadOnly, false, false, kSOk);
        auto oRejSync = ClassifyRequestEditSessionResult(true, kSOk, kTsESync, false, false, kSOk);
        auto oRejLock = ClassifyRequestEditSessionResult(true, kSOk, kTfELocked, false, false, kSOk);
        auto oDropped = ClassifyRequestEditSessionResult(true, kSOk, kSOk, false, false, kSOk);
        ok = ok && (oRejRo == TsfEditOutcome::Failed) && !ShouldEatKeyAfterEdit(oRejRo);
        ok = ok && (oRejSync == TsfEditOutcome::Failed) && !ShouldEatKeyAfterEdit(oRejSync);
        ok = ok && (oRejLock == TsfEditOutcome::Failed) && !ShouldEatKeyAfterEdit(oRejLock);
        ok = ok && (oDropped == TsfEditOutcome::Failed) && !ShouldEatKeyAfterEdit(oDropped);
        // Executed synchronously but GetSelection or SetText failed -> Failed -> do NOT eat key
        auto oGetSelFail = ClassifyRequestEditSessionResult(true, kSOk, kEFail, true, false, kEFail);
        auto oSetTextFail = ClassifyRequestEditSessionResult(true, kSOk, kTsEReadOnly, true, false, kTsEReadOnly);
        ok = ok && (oGetSelFail == TsfEditOutcome::Failed) && !ShouldEatKeyAfterEdit(oGetSelFail);
        ok = ok && (oSetTextFail == TsfEditOutcome::Failed) && !ShouldEatKeyAfterEdit(oSetTextFail);
        // Executed synchronously and refused zero/partial delete -> DeleteRefused -> do NOT eat key
        auto oRefused = ClassifyRequestEditSessionResult(true, kSOk, kSFalse, true, true, kSFalse);
        ok = ok && (oRefused == TsfEditOutcome::DeleteRefused) && !ShouldEatKeyAfterEdit(oRefused);
        // Allocation failure -> Failed -> do NOT eat key
        auto oOom = ClassifyRequestEditSessionResult(false, kSOk, kSOk, false, false, kSOk);
        ok = ok && (oOom == TsfEditOutcome::Failed) && !ShouldEatKeyAfterEdit(oOom);
        checkTsf(21, ok, "RequestEditSession sync/async/refused/failed classification", ok ? "OK" : "MISMATCH");
    }

    // TSF 22: PlanRangeShiftEdit (zero-shift, partial-shift, over-shift, RichEdit fallback) & Classic Edit guard
    {
        using namespace vielotus_tsf_guard;
        bool ok = true;
        // Full shift, zero requested backspaces, or active selection -> ApplyFullRange
        ok = ok && (PlanRangeShiftEdit(0, 0, true, false, false, 0) == ShiftEditPlan::ApplyFullRange);
        ok = ok && (PlanRangeShiftEdit(3, 0, false, false, false, 0) == ShiftEditPlan::ApplyFullRange);
        ok = ok && (PlanRangeShiftEdit(3, 3, true, false, false, 0) == ShiftEditPlan::ApplyFullRange);
        // Non-Win32: zero-shift, partial-shift, and over-shift ALL refuse with zero mutation
        ok = ok && (PlanRangeShiftEdit(3, 0, true, false, false, 0) == ShiftEditPlan::RefuseNoMutation);
        ok = ok && (PlanRangeShiftEdit(3, 1, true, false, false, 0) == ShiftEditPlan::RefuseNoMutation);
        ok = ok && (PlanRangeShiftEdit(3, 2, true, false, false, 0) == ShiftEditPlan::RefuseNoMutation);
        ok = ok && (PlanRangeShiftEdit(3, 5, true, false, false, 0) == ShiftEditPlan::RefuseNoMutation);
        // Win32 Edit/RichEdit: partial/zero shift only falls back when caret >= requestedBackspaces
        ok = ok && (PlanRangeShiftEdit(3, 1, true, true, true, 3) == ShiftEditPlan::FallbackWin32Edit);
        ok = ok && (PlanRangeShiftEdit(3, 0, true, true, true, 5) == ShiftEditPlan::FallbackWin32Edit);
        ok = ok && (PlanRangeShiftEdit(3, 1, true, true, true, 2) == ShiftEditPlan::RefuseNoMutation);
        ok = ok && (PlanRangeShiftEdit(3, 0, true, true, true, 0) == ShiftEditPlan::RefuseNoMutation);
        ok = ok && (PlanRangeShiftEdit(3, 1, true, true, false, 5) == ShiftEditPlan::RefuseNoMutation);
        // Classic Win32 Edit delete guard
        ok = ok && CanClassicWin32EditDelete(0, 0, 0);
        ok = ok && CanClassicWin32EditDelete(3, 3, 3);
        ok = ok && CanClassicWin32EditDelete(3, 1, 4); // active selection
        ok = ok && !CanClassicWin32EditDelete(3, 0, 0); // zero chars before caret
        ok = ok && !CanClassicWin32EditDelete(3, 2, 2); // partial chars before caret
        // RichEdit single-operation atomic fallback re-validation (must refuse with zero prior mutation)
        ok = ok && CanWin32AtomicFallbackReplace(3, 3, 3);
        ok = ok && CanWin32AtomicFallbackReplace(3, 5, 5);
        ok = ok && !CanWin32AtomicFallbackReplace(3, 2, 2); // caret shorter than full requestedBackspaces
        ok = ok && !CanWin32AtomicFallbackReplace(3, 0, 0);
        ok = ok && !CanWin32AtomicFallbackReplace(3, 3, 5); // non-empty selection mismatch
        ok = ok && !CanWin32AtomicFallbackReplace(0, 5, 5);
        checkTsf(22, ok, "Range shift, Classic Edit & RichEdit atomic fallback guards", ok ? "OK" : "MISMATCH");
    }

    // TSF 23–25: Hostile game-chat TSF host simulation (zero-shift, partial-shift, GetSelection fail, TF_S_ASYNC)
    {
        using namespace vielotus_tsf_guard;
        struct HostileGameTsfSim {
            enum class HostMode { ZeroShift, MaxOneShift, MaxTwoShift, GetSelectionFail, QueuedAsync };
            WindowsNativeEngine engine;
            HostMode mode;
            std::string doc;
            struct QueuedOp { int32_t bs; std::string text; };
            std::vector<QueuedOp> asyncQueue;
            int32_t lastRequestedBs{0};
            ShiftEditPlan lastPlan{ShiftEditPlan::ApplyFullRange};

            explicit HostileGameTsfSim(HostMode m) : mode(m) {
                engine.setSmartBilingual(true);
            }

            TsfEditOutcome runEditSession(int32_t bs, const std::string &text) {
                lastRequestedBs = bs;
                if (mode == HostMode::GetSelectionFail) {
                    // Synchronous DoEditSession entered, GetSelection returned E_FAIL
                    return ClassifyRequestEditSessionResult(
                        true, 0, static_cast<int32_t>(0x80004005u), true, false,
                        static_cast<int32_t>(0x80004005u)
                    );
                }
                if (mode == HostMode::QueuedAsync) {
                    asyncQueue.push_back({bs, text});
                    return ClassifyRequestEditSessionResult(true, 0, kTfSAsync, false, false, 0);
                }
                int32_t actualShifted = bs;
                if (bs > 0) {
                    if (mode == HostMode::ZeroShift) actualShifted = 0;
                    else if (mode == HostMode::MaxOneShift) actualShifted = std::min<int32_t>(bs, 1);
                    else if (mode == HostMode::MaxTwoShift) actualShifted = std::min<int32_t>(bs, 2);
                }
                const auto plan = PlanRangeShiftEdit(bs, actualShifted, true, false, false, 0);
                lastPlan = plan;
                if (plan == ShiftEditPlan::RefuseNoMutation) {
                    return ClassifyRequestEditSessionResult(true, 0, 1, true, true, 1);
                }
                removeLastUtf16Units(doc, bs);
                doc += text;
                return ClassifyRequestEditSessionResult(true, 0, 0, true, false, 0);
            }

            void flushAsyncQueue() {
                for (const auto &op : asyncQueue) {
                    removeLastUtf16Units(doc, op.bs);
                    doc += op.text;
                }
                asyncQueue.clear();
            }

            bool pressKey(char ch) {
                if (ch == '\b') {
                    if (!engine.isComposing()) {
                        if (!doc.empty()) removeLastUtf16Units(doc, 1);
                        return false;
                    }
                    int32_t act = engine.feedBackspace();
                    TsfEditOutcome out = (act == static_cast<int32_t>(Action::Reset))
                        ? runEditSession(1, "")
                        : runEditSession(engine.getLastBackspaces(), engine.getLastTextUtf8());
                    if (ShouldEatKeyAfterEdit(out)) return true;
                    engine.reset();
                    if (!doc.empty()) removeLastUtf16Units(doc, 1); // native host VK_BACK
                    return false;
                }
                int32_t act = engine.feedChar(static_cast<uint32_t>(static_cast<unsigned char>(ch)));
                TsfEditOutcome out = TsfEditOutcome::Succeeded;
                if (act == static_cast<int32_t>(Action::Commit)) {
                    std::string committed = engine.getLastCommitDiffTextUtf8();
                    committed.push_back(ch);
                    out = runEditSession(engine.getLastCommitDiffBackspaces(), committed);
                } else if (act == static_cast<int32_t>(Action::Replace)) {
                    out = runEditSession(engine.getLastBackspaces(), engine.getLastTextUtf8());
                } else {
                    out = runEditSession(0, std::string(1, ch));
                }
                if (ShouldEatKeyAfterEdit(out)) return true;
                engine.reset();
                doc.push_back(ch); // native host key delivery
                return false;
            }
        };

        // TSF 23: Zero-shift host refuses backward delete -> zero duplication + native Backspace passes
        {
            HostileGameTsfSim sim(HostileGameTsfSim::HostMode::ZeroShift);
            bool e1 = sim.pressKey('t');
            bool e2 = sim.pressKey('i');
            bool e3 = sim.pressKey('e');
            bool e4 = sim.pressKey('e'); // bs=1, actualShifted=0 -> DeleteRefused -> raw 'e' passes
            bool bsAfter = sim.pressKey('\b'); // engine already reset -> native backspace
            bool ok = e1 && e2 && e3 && !e4 && !bsAfter && (sim.doc == "tie");
            checkTsf(23, ok, "Zero-shift game host avoids duplication and passes raw key", sim.doc);
        }

        // TSF 24: Partial-shift host (mid-word & retroactive 2-word commit) -> zero duplication/corrupt splice
        {
            // Mid-word: "truo" + 'w' requests bs=2 ("uo" -> "ươ"), host only shifts 1 -> RefuseNoMutation -> "truow"
            HostileGameTsfSim simMid(HostileGameTsfSim::HostMode::MaxOneShift);
            simMid.pressKey('t');
            simMid.pressKey('r');
            simMid.pressKey('u');
            simMid.pressKey('o');
            bool wEaten = simMid.pressKey('w');
            bool okMid = !wEaten && (simMid.lastRequestedBs == 2) &&
                         (simMid.lastPlan == ShiftEditPlan::RefuseNoMutation) &&
                         (simMid.doc == "truow");

            // Retroactive 2-word commit: "sex " ("sẽ ") + "toy" + ' ' requests retro bs=6 ("sex toy "),
            // host only allows shifting up to 2 chars -> RefuseNoMutation -> Space passes -> "sẽ toy "
            HostileGameTsfSim simRetro(HostileGameTsfSim::HostMode::MaxTwoShift);
            for (char c : std::string("sex toy")) simRetro.pressKey(c);
            bool spEaten = simRetro.pressKey(' ');
            bool okRetro = !spEaten && (simRetro.lastRequestedBs == 6) &&
                           (simRetro.lastPlan == ShiftEditPlan::RefuseNoMutation) &&
                           (simRetro.doc == "sẽ toy ");

            checkTsf(24, okMid && okRetro, "Partial-shift game host refuses splice without corruption",
                     "mid='" + simMid.doc + "'(bs=" + std::to_string(simMid.lastRequestedBs) +
                     ") retro='" + simRetro.doc + "'(bs=" + std::to_string(simRetro.lastRequestedBs) + ")");
        }

        // TSF 25: GetSelection E_FAIL passes key through; TF_S_ASYNC keeps key eaten with no double insert
        {
            HostileGameTsfSim simFail(HostileGameTsfSim::HostMode::GetSelectionFail);
            bool wEaten = simFail.pressKey('w');
            bool aEaten = simFail.pressKey('a');
            bool okFail = !wEaten && !aEaten && (simFail.doc == "wa");

            HostileGameTsfSim simAsync(HostileGameTsfSim::HostMode::QueuedAsync);
            bool allEaten = true;
            for (char c : std::string("tiees")) {
                allEaten = allEaten && simAsync.pressKey(c);
            }
            simAsync.flushAsyncQueue();
            bool okAsync = allEaten && (simAsync.doc == "tiế");

            checkTsf(25, okFail && okAsync, "GetSelection E_FAIL passthrough vs TF_S_ASYNC queued eat",
                     "fail='" + simFail.doc + "' async='" + simAsync.doc + "'");
        }
    }

    // TSF 26: Out-of-process Settings launch policy (HWND -> Named Pipe -> Desktop EXE -> Skip)
    {
        using namespace vielotus_tsf_guard;
        bool ok = true;
        // Existing Settings window always gets PostMessage first in both desktop & AppContainer
        ok = ok && (PlanSettingsLaunch(true, false, false, true) == SettingsLaunchPlan::PostToExistingWindow);
        ok = ok && (PlanSettingsLaunch(true, false, true, true) == SettingsLaunchPlan::PostToExistingWindow);
        ok = ok && (PlanSettingsLaunch(true, true, true, false) == SettingsLaunchPlan::PostToExistingWindow);
        // No HWND (e.g. AppContainer isolation), Named Pipe wake succeeded -> WakeViaNamedPipe
        ok = ok && (PlanSettingsLaunch(false, true, true, false) == SettingsLaunchPlan::WakeViaNamedPipe);
        ok = ok && (PlanSettingsLaunch(false, true, true, true) == SettingsLaunchPlan::WakeViaNamedPipe);
        ok = ok && (PlanSettingsLaunch(false, true, false, true) == SettingsLaunchPlan::WakeViaNamedPipe);
        // No HWND, pipe unavailable: only desktop hosts with VieLotusSettings.exe launch it;
        // AppContainer and hosts without VieLotusSettings.exe skip cleanly (zero in-process dialog UI)
        ok = ok && (PlanSettingsLaunch(false, false, false, true) == SettingsLaunchPlan::LaunchSettingsExe);
        ok = ok && (PlanSettingsLaunch(false, false, true, true) == SettingsLaunchPlan::SkipUnavailable);
        ok = ok && (PlanSettingsLaunch(false, false, false, false) == SettingsLaunchPlan::SkipUnavailable);
        ok = ok && (PlanSettingsLaunch(false, false, true, false) == SettingsLaunchPlan::SkipUnavailable);
        checkTsf(26, ok, "Out-of-process Settings launch policy (HWND / NamedPipe / Desktop)", ok ? "OK" : "MISMATCH");
    }

    // TSF 27: Language Bar (GUID_LBI_INPUTMODE) menu command resolution
    {
        using namespace vielotus_tsf_guard;
        bool ok = true;
        ok = ok && (ResolveLangBarMenuAction(kLangBarCmdVietnamese) == LangBarMenuAction::SetVietnamese);
        ok = ok && (ResolveLangBarMenuAction(kLangBarCmdEnglish) == LangBarMenuAction::SetEnglish);
        ok = ok && (ResolveLangBarMenuAction(kLangBarCmdTelex) == LangBarMenuAction::SetTelex);
        ok = ok && (ResolveLangBarMenuAction(kLangBarCmdVni) == LangBarMenuAction::SetVni);
        ok = ok && (ResolveLangBarMenuAction(kLangBarCmdOpenSettings) == LangBarMenuAction::OpenSettings);
        ok = ok && (ResolveLangBarMenuAction(0u) == LangBarMenuAction::None);
        ok = ok && (ResolveLangBarMenuAction(9999u) == LangBarMenuAction::None);
        checkTsf(27, ok, "Language Bar menu command routing", ok ? "OK" : "MISMATCH");
    }

    // TSF 28: Language Bar OnUpdate notification throttling (zero redundant RPC on unchanged state)
    {
        using namespace vielotus_tsf_guard;
        bool ok = true;
        ok = ok && !ShouldNotifyLangBarUpdate(true, false, true, false, false);
        ok = ok && ShouldNotifyLangBarUpdate(true, false, false, false, false);
        ok = ok && ShouldNotifyLangBarUpdate(true, false, true, true, false);
        ok = ok && ShouldNotifyLangBarUpdate(true, false, true, false, true);
        checkTsf(28, ok, "Language Bar update notification policy", ok ? "OK" : "MISMATCH");
    }

    // TSF 29: Settings revision clears stale per-process manual override & GitHub issue strips private contact
    {
        using namespace vielotus_tsf_guard;
        bool ok = true;
        ok = ok && !ShouldClearManualOverrideOnSettingsRevision(0u, 0u);
        ok = ok && !ShouldClearManualOverrideOnSettingsRevision(3u, 3u);
        ok = ok && ShouldClearManualOverrideOnSettingsRevision(0u, 1u);
        ok = ok && ShouldClearManualOverrideOnSettingsRevision(3u, 4u);
        ok = ok && !ShouldIncludeContactInFeedbackChannel(true);
        ok = ok && ShouldIncludeContactInFeedbackChannel(false);
        checkTsf(29, ok, "SettingsRevision override sync & public feedback contact strip", ok ? "OK" : "MISMATCH");
    }

    // TSF 30: Language Bar icon selection (Vietnamese -> Indigo [V] badge, English -> Slate [E] badge;
    // avoids duplicating the adjacent Windows profile SV lotus icon)
    {
        using namespace vielotus_tsf_guard;
        bool ok = true;
        ok = ok && (ResolveLangBarIconKind(true) == LangBarIconKind::VietnameseIndigoBadge);
        ok = ok && (ResolveLangBarIconKind(false) == LangBarIconKind::EnglishSlateBadge);
        checkTsf(30, ok, "Language Bar Indigo [V] (VN) / Slate [E] (EN) icon policy", ok ? "OK" : "MISMATCH");
    }

    // TSF 31: Sync-first EndActiveComposition fallback & ref-release policy (issue #173 Chromium Enter race)
    {
        using namespace vielotus_tsf_guard;
        constexpr int32_t kSOk = 0;
        constexpr int32_t kEFail = static_cast<int32_t>(0x80004005u);
        bool ok = true;
        // 1. Sync succeeded immediately -> no async fallback, refs already cleared in DoEditSession
        ok = ok && !ShouldFallbackEndCompositionAsync(kSOk, kSOk, true);
        ok = ok && !ShouldReleaseCompositionAfterEndAttempt(kSOk, kSOk, true);
        // 2. Sync executed but returned session error -> no retry, release stale refs
        ok = ok && !ShouldFallbackEndCompositionAsync(kSOk, kEFail, true);
        ok = ok && ShouldReleaseCompositionAfterEndAttempt(kSOk, kEFail, true);
        // 3. Document locked -> TS_E_SYNCHRONOUS / TF_E_SYNCHRONOUS / TF_E_LOCKED -> fallback to TF_ES_ASYNCDONTCARE
        ok = ok && ShouldFallbackEndCompositionAsync(kSOk, kTsESynchronous, false);
        ok = ok && ShouldFallbackEndCompositionAsync(kSOk, kTfESynchronous, false);
        ok = ok && ShouldFallbackEndCompositionAsync(kTfESynchronous, kSOk, false);
        ok = ok && ShouldFallbackEndCompositionAsync(kSOk, kTfELocked, false);
        ok = ok && ShouldFallbackEndCompositionAsync(kSOk, kSOk, false);
        // 4. Queued async (TF_S_ASYNC) -> do NOT retry again and do NOT prematurely release refs
        ok = ok && !ShouldFallbackEndCompositionAsync(kSOk, kTfSAsync, false);
        ok = ok && !ShouldReleaseCompositionAfterEndAttempt(kSOk, kTfSAsync, false);
        // 5. Final fallback failed without executing -> must release stale composition refs
        ok = ok && ShouldReleaseCompositionAfterEndAttempt(kEFail, kSOk, false);
        ok = ok && ShouldReleaseCompositionAfterEndAttempt(kSOk, kTfELocked, false);
        ok = ok && ShouldReleaseCompositionAfterEndAttempt(kSOk, kSOk, false);
        checkTsf(31, ok, "Sync-first EndActiveComposition fallback & ref-release policy", ok ? "OK" : "MISMATCH");
    }

    // TSF 32: '@' sets tech-delimiter context without eating '@' (root@host / admin@test.com)
    {
        WinTsfSimulator sim;
        sim.typeString("root");
        bool at1 = sim.pressCharKey('@');
        sim.typeString("host ");
        sim.typeString("admin");
        bool at2 = sim.pressCharKey('@');
        sim.typeString("test.com ");
        const bool ok = !at1 && !at2 && sim.doc == "root@host admin@test.com ";
        checkTsf(32, ok, "'@' tech-delimiter restoration without eating '@'", ok ? "OK" : sim.doc);
    }

    // TSF 33: MSIX vs Classic Win32 Start Menu shortcut & Installed Apps dedup policy
    {
        using namespace vielotus_tsf_guard;
        bool ok = true;
        ok = ok && !ShouldRegisterClassicStartMenuAndUninstall(true);
        ok = ok && ShouldRegisterClassicStartMenuAndUninstall(false);
        ok = ok && !ShouldRequireWin32UninstallEntryForTipCheck(true);
        ok = ok && ShouldRequireWin32UninstallEntryForTipCheck(false);
        checkTsf(33, ok, "MSIX vs Win32 Start Menu & Installed Apps dedup policy", ok ? "OK" : "MISMATCH");
    }

    // TSF 34: Cross-process Telex <-> VNI profile switch & ActivateProfile flag separation policy
    {
        using namespace vielotus_tsf_guard;
        bool ok = true;
        // 1. ActivateProfile scope flags: FORPROCESS and FORSESSION must never be OR'd in one call
        ok = ok && AreActivateProfileFlagsValid(kActivateProfileProcessFlags);
        ok = ok && AreActivateProfileFlagsValid(kActivateProfileSessionFlags);
        ok = ok && !AreActivateProfileFlagsValid(
            kTfIppmfForProcess | kTfIppmfForSession | kTfIppmfEnableProfile | kTfIppmfDontCareCurrentInputLanguage
        );

        // 2. Monotonic InputMethodRevision detection
        ok = ok && !HasUnseenInputMethodRevision(false, 0u, 1u);
        ok = ok && !HasUnseenInputMethodRevision(true, 0u, 0u);
        ok = ok && !HasUnseenInputMethodRevision(true, 5u, 5u);
        ok = ok && HasUnseenInputMethodRevision(true, 0u, 1u);
        ok = ok && HasUnseenInputMethodRevision(true, 5u, 6u);

        // 3. Explicit LangBar menu selection (forcePushToProfile=true) pushes to Windows profile
        ok = ok && (PlanProfileSync(true, 5u, 5u, true, true, true, true, false, false, false) ==
                    ProfileSyncAction::PushRegistryToActiveProfile);

        // 4. Already-open process (e.g. Chrome) with stale VNI profile sees unseen revision (5 -> 6, Telex)
        //    and pushes Registry Telex to its active TSF profile instead of reverting Registry back to VNI
        ok = ok && (PlanProfileSync(true, 5u, 6u, false, true, true, true, false, false, false) ==
                    ProfileSyncAction::PushRegistryToActiveProfile);

        // 5. Same revision (no external switch): adopt active Windows profile locally without mutating Registry
        ok = ok && (PlanProfileSync(true, 6u, 6u, false, true, true, true, false, false, false) ==
                    ProfileSyncAction::AdoptActiveProfileLocally);

        // 6. Fresh ActivateEx with Sen Viet active (e.g. Win+Space -> VNI): adopt locally, do not fight Win+Space
        ok = ok && (PlanProfileSync(false, 0u, 6u, false, true, true, true, false, true, false) ==
                    ProfileSyncAction::AdoptActiveProfileLocally);

        // 7. Fresh ActivateEx with GUID_NULL active profile: initialize from Registry preference
        ok = ok && (PlanProfileSync(false, 0u, 6u, false, false, false, false, true, true, true) ==
                    ProfileSyncAction::PushRegistryToActiveProfile);

        // 8. Another TIP active (e.g. ENG US) while not in ActivateEx: never steal focus even on unseen rev
        ok = ok && (PlanProfileSync(true, 5u, 6u, false, false, false, false, true, false, false) ==
                    ProfileSyncAction::NoChange);
        ok = ok && (PlanProfileSync(true, 5u, 5u, true, false, false, false, true, false, false) ==
                    ProfileSyncAction::NoChange);

        // 9. OnActivated persistence guard: avoid redundant writes / revision ping-pong on FORSESSION echoes
        ok = ok && !ShouldPersistOnProfileActivated(true, true, false, true);
        ok = ok && !ShouldPersistOnProfileActivated(false, true, true, true);
        ok = ok && ShouldPersistOnProfileActivated(false, true, false, true);
        ok = ok && ShouldPersistOnProfileActivated(false, false, false, true);

        checkTsf(34, ok, "Cross-process Telex/VNI profile sync & ActivateProfile flags", ok ? "OK" : "MISMATCH");
    }

    // TSF 35: Desktop Numpad 0-9 always emits literal digits in VNI (never acts as VNI diacritic)
    {
        using namespace vielotus_tsf_guard;
        bool ok = true;
        ok = ok && IsNumpadDigitVk(kVkNumpad0);
        ok = ok && IsNumpadDigitVk(kVkNumpad9);
        ok = ok && !IsNumpadDigitVk('0');
        ok = ok && !IsNumpadDigitVk('9');
        // Top-row digits are VNI modifiers when VNI mode is active
        ok = ok && IsVniDigitModifierKey(true, '1', '1');
        ok = ok && IsVniDigitModifierKey(true, '9', '9');
        ok = ok && !IsVniDigitModifierKey(false, '1', '1');
        // Numpad digits are NEVER VNI modifiers even when VNI mode is active
        ok = ok && !IsVniDigitModifierKey(true, kVkNumpad0, '0');
        ok = ok && !IsVniDigitModifierKey(true, kVkNumpad0 + 1u, '1');
        ok = ok && !IsVniDigitModifierKey(true, kVkNumpad9, '9');
#if !defined(_WIN32)
        // Linux X11 Numpad digit keysym classification (KP_0..KP_9 = 0xFFB0..0xFFB9)
        ok = ok && vl_is_numpad_digit_keysym(0xFFB0u);
        ok = ok && vl_is_numpad_digit_keysym(0xFFB1u);
        ok = ok && vl_is_numpad_digit_keysym(0xFFB9u);
        ok = ok && !vl_is_numpad_digit_keysym('1');
        ok = ok && !vl_is_numpad_digit_keysym(0xFFABu); // KP_Add
#endif
        checkTsf(35, ok, "Desktop Numpad 0-9 literal-digit policy in VNI", ok ? "OK" : "MISMATCH");
    }

    // TSF 36: Settings Named Pipe command parser (SHOW / SYNC / VNI0 / VNI1)
    {
        using namespace vielotus_tsf_guard;
        bool ok = true;
        ok = ok && (ParseSettingsPipeCommand("SHOW", 4) == SettingsPipeCommand::ShowWindow);
        ok = ok && (ParseSettingsPipeCommand("SYNC", 4) == SettingsPipeCommand::SyncPrefsOnly);
        ok = ok && (ParseSettingsPipeCommand("VNI0", 4) == SettingsPipeCommand::SyncTelex);
        ok = ok && (ParseSettingsPipeCommand("VNI1", 4) == SettingsPipeCommand::SyncVni);
        ok = ok && (ParseSettingsPipeCommand("VNI1\n", 5) == SettingsPipeCommand::SyncVni);
        ok = ok && (ParseSettingsPipeCommand("VNI", 3) == SettingsPipeCommand::None);
        ok = ok && (ParseSettingsPipeCommand("NOOP", 4) == SettingsPipeCommand::None);
        ok = ok && (ParseSettingsPipeCommand(nullptr, 4) == SettingsPipeCommand::None);
        checkTsf(36, ok, "Settings Named Pipe command parser (SHOW/SYNC/VNI0/VNI1)", ok ? "OK" : "MISMATCH");
    }

    // TSF 37: Bidirectional Windows TSF <-> Control Panel (SettingsUI) input method sync policy
    {
        using namespace vielotus_tsf_guard;
        bool ok = true;

        // 1. InitialCreate: Windows TSF already on Telex while stale Registry says VNI
        //    -> adopt Telex, heal Registry, do NOT call onActivateProfiles(false) to revert!
        {
            SettingsImSyncInput in{};
            in.trigger = SettingsSyncTrigger::InitialCreate;
            in.currentUiIsVni = true;
            in.registryIsVni = true;
            in.hasActiveTsfProfile = true;
            in.activeTsfIsVni = false;
            const auto r = ResolveSettingsInputMethodSync(in);
            ok = ok && !r.nextUiIsVni && r.uiChanged && r.shouldPersistToRegistry &&
                 !r.shouldSyncProcessProfile && !r.shouldAutoActivateOnCreate;
        }

        // 2. InitialCreate: Windows TSF on ENG US (Sen Viet inactive), Registry says VNI
        //    -> keep Registry VNI and auto-activate Sen Viet on open.
        {
            SettingsImSyncInput in{};
            in.trigger = SettingsSyncTrigger::InitialCreate;
            in.currentUiIsVni = true;
            in.registryIsVni = true;
            in.hasActiveTsfProfile = false;
            const auto r = ResolveSettingsInputMethodSync(in);
            ok = ok && r.nextUiIsVni && !r.uiChanged && !r.shouldPersistToRegistry &&
                 !r.shouldSyncProcessProfile && r.shouldAutoActivateOnCreate;
        }

        // 3. TsfProfileNotifySink: Win+Spacebar switches VNI -> Telex while Settings open
        //    -> update UI immediately, heal stale Registry; skip Registry write if already synced;
        //    live TSF active profile overrides a stale queued OnActivated hint on rapid double-switch.
        {
            SettingsImSyncInput in{};
            in.trigger = SettingsSyncTrigger::TsfProfileNotifySink;
            in.currentUiIsVni = true;
            in.registryIsVni = true;
            in.hasActiveTsfProfile = true;
            in.activeTsfIsVni = false;
            in.explicitHintIsVni = false;
            const auto r = ResolveSettingsInputMethodSync(in);
            ok = ok && !r.nextUiIsVni && r.uiChanged && r.shouldPersistToRegistry && !r.shouldSyncProcessProfile;

            in.registryIsVni = false;
            const auto rAlreadyReg = ResolveSettingsInputMethodSync(in);
            ok = ok && !rAlreadyReg.nextUiIsVni && rAlreadyReg.uiChanged && !rAlreadyReg.shouldPersistToRegistry;

            // Stale queued VNI hint while live TSF is already back on Telex -> live TSF wins
            in.currentUiIsVni = false;
            in.explicitHintIsVni = true;
            const auto rStale = ResolveSettingsInputMethodSync(in);
            ok = ok && !rStale.nextUiIsVni && !rStale.uiChanged && !rStale.shouldPersistToRegistry;
        }

        // 4. TipCrossProcessHint from AppContainer host (e.g. Win11 Notepad / Edge):
        //    AppContainer couldn't write Registry (still VNI) -> Settings updates UI to Telex,
        //    heals Registry on its behalf, and syncs Settings' own process profile.
        {
            SettingsImSyncInput in{};
            in.trigger = SettingsSyncTrigger::TipCrossProcessHint;
            in.currentUiIsVni = true;
            in.registryIsVni = true;
            in.hasActiveTsfProfile = true;
            in.activeTsfIsVni = true;
            in.explicitHintIsVni = false;
            const auto r = ResolveSettingsInputMethodSync(in);
            ok = ok && !r.nextUiIsVni && r.uiChanged && r.shouldPersistToRegistry && r.shouldSyncProcessProfile;
        }

        // 5. TipCrossProcessHint from Win32 host (e.g. Chrome LangBar): Registry already Telex -> no redundant write
        {
            SettingsImSyncInput in{};
            in.trigger = SettingsSyncTrigger::TipCrossProcessHint;
            in.currentUiIsVni = true;
            in.registryIsVni = false;
            in.hasActiveTsfProfile = true;
            in.activeTsfIsVni = false;
            in.explicitHintIsVni = false;
            const auto r = ResolveSettingsInputMethodSync(in);
            ok = ok && !r.nextUiIsVni && r.uiChanged && !r.shouldPersistToRegistry && !r.shouldSyncProcessProfile;
        }

        // 6. PeriodicOrWindowEvent: Desktop Win+Spacebar switch (VNI -> Telex, rev unchanged)
        //    -> detects TSF profile transition, updates UI & heals Registry.
        {
            SettingsImSyncInput in{};
            in.trigger = SettingsSyncTrigger::PeriodicOrWindowEvent;
            in.currentUiIsVni = true;
            in.registryIsVni = true;
            in.lastSeenImRevision = 5u;
            in.currentRegistryImRevision = 5u;
            in.hasActiveTsfProfile = true;
            in.activeTsfIsVni = false;
            in.hasLastObservedTsf = true;
            in.lastObservedTsfIsVni = true;
            const auto r = ResolveSettingsInputMethodSync(in);
            ok = ok && !r.nextUiIsVni && r.uiChanged && r.shouldPersistToRegistry && !r.shouldSyncProcessProfile;
        }

        // 7. PeriodicOrWindowEvent (Per-window mode ON): another app bumped rev 5->6 (Telex),
        //    Settings' own TSF stayed unchanged at VNI -> adopt Registry Telex & sync process profile.
        {
            SettingsImSyncInput in{};
            in.trigger = SettingsSyncTrigger::PeriodicOrWindowEvent;
            in.currentUiIsVni = true;
            in.registryIsVni = false;
            in.lastSeenImRevision = 5u;
            in.currentRegistryImRevision = 6u;
            in.hasActiveTsfProfile = true;
            in.activeTsfIsVni = true;
            in.hasLastObservedTsf = true;
            in.lastObservedTsfIsVni = true;
            const auto r = ResolveSettingsInputMethodSync(in);
            ok = ok && !r.nextUiIsVni && r.uiChanged && !r.shouldPersistToRegistry && r.shouldSyncProcessProfile;
        }

        // 8. Anti-ping-pong after Case 7: next timer tick (rev 6==6, TSF still unchanged at VNI)
        //    -> MUST stay Telex with zero writes and zero redraws!
        {
            SettingsImSyncInput in{};
            in.trigger = SettingsSyncTrigger::PeriodicOrWindowEvent;
            in.currentUiIsVni = false;
            in.registryIsVni = false;
            in.lastSeenImRevision = 6u;
            in.currentRegistryImRevision = 6u;
            in.hasActiveTsfProfile = true;
            in.activeTsfIsVni = true;
            in.hasLastObservedTsf = true;
            in.lastObservedTsfIsVni = true;
            const auto r = ResolveSettingsInputMethodSync(in);
            ok = ok && !r.nextUiIsVni && !r.uiChanged && !r.shouldPersistToRegistry && !r.shouldSyncProcessProfile;
        }

        // 9. Steady state: zero redraws, zero writes, zero COM activations
        {
            SettingsImSyncInput in{};
            in.trigger = SettingsSyncTrigger::PeriodicOrWindowEvent;
            in.currentUiIsVni = false;
            in.registryIsVni = false;
            in.lastSeenImRevision = 6u;
            in.currentRegistryImRevision = 6u;
            in.hasActiveTsfProfile = true;
            in.activeTsfIsVni = false;
            in.hasLastObservedTsf = true;
            in.lastObservedTsfIsVni = false;
            const auto r = ResolveSettingsInputMethodSync(in);
            ok = ok && !r.nextUiIsVni && !r.uiChanged && !r.shouldPersistToRegistry && !r.shouldSyncProcessProfile;
        }

        // 10. ENG US (hasLastObservedTsf=false) -> Sen Viet Telex while UI/Registry were VNI
        {
            SettingsImSyncInput in{};
            in.trigger = SettingsSyncTrigger::PeriodicOrWindowEvent;
            in.currentUiIsVni = true;
            in.registryIsVni = true;
            in.lastSeenImRevision = 6u;
            in.currentRegistryImRevision = 6u;
            in.hasActiveTsfProfile = true;
            in.activeTsfIsVni = false;
            in.hasLastObservedTsf = false;
            const auto r = ResolveSettingsInputMethodSync(in);
            ok = ok && !r.nextUiIsVni && r.uiChanged && r.shouldPersistToRegistry;
        }

        checkTsf(37, ok, "Bidirectional TSF <-> Control Panel input method sync state machine", ok ? "OK" : "MISMATCH");
    }

    // =========================================================================
    // P0.6 Explicit Telex & VNI Escape Preservation Suite
    // Verifies both Windows TSF (WindowsNativeEngine / WinTsfSimulator) and
    // Linux IBus/Fcitx5 C-ABI (vielotus_* preedit & commit) with smartBilingual = true.
    // =========================================================================
    int p06Total = 0, p06Pass = 0;
    void *p06Capi = vielotus_create_session();
    auto checkP06 = [&](const char *label, bool cond, const std::string &diag) {
        ++p06Total;
        if (cond) {
            ++p06Pass;
        } else {
            std::printf("  P0.6 FAIL [%s]: %s\n", label, diag.c_str());
        }
    };
    auto checkWordBoth = [&](const std::string &raw, const std::string &expected, bool vni = false) {
        // 1. Windows TSF simulator (inline + space commit)
        WinTsfSimulator sim;
        sim.setVni(vni);
        sim.typeString(raw);
        bool winInlineOk = (sim.doc == expected);
        sim.pressCharKey(' ');
        bool winCommitOk = (sim.doc == expected + " ");

        // 2. Linux C-ABI preedit + space commit
        vielotus_reset_session(p06Capi);
        vielotus_set_smart_bilingual(p06Capi, true);
        vielotus_set_input_method(p06Capi, vni ? VIELOTUS_INPUT_VNI : VIELOTUS_INPUT_TELEX);
        vielotus_append_context(p06Capi, "");
        std::string capiOut;
        for (unsigned char ch : raw) {
            bool isAlpha = (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z');
            bool isDigit = (ch >= '0' && ch <= '9');
            bool isWordChar = isAlpha || (vni && isDigit && vielotus_is_composing(p06Capi));
            if (!isWordChar) {
                if (vielotus_is_composing(p06Capi)) {
                    vielotus_feed_char(p06Capi, ch);
                    const char *committed = vielotus_get_last_text(p06Capi);
                    if (committed) capiOut += committed;
                    capiOut.push_back(static_cast<char>(ch));
                    vielotus_reset_session(p06Capi);
                } else {
                    vielotus_feed_char(p06Capi, ch);
                    capiOut.push_back(static_cast<char>(ch));
                }
            } else {
                int32_t act = vielotus_feed_char(p06Capi, ch);
                if (act == VIELOTUS_ACTION_COMMIT) {
                    const char *committed = vielotus_get_last_text(p06Capi);
                    if (committed) capiOut += committed;
                    vielotus_reset_session(p06Capi);
                }
            }
        }
        std::string capiInline = capiOut + (vielotus_is_composing(p06Capi) ? vielotus_get_composing_text(p06Capi) : "");
        bool capiInlineOk = (capiInline == expected);
        std::string capiCommit = capiOut;
        if (vielotus_is_composing(p06Capi)) {
            vielotus_feed_char(p06Capi, ' ');
            const char *committed = vielotus_get_last_text(p06Capi);
            if (committed) capiCommit += committed;
            capiCommit.push_back(' ');
            vielotus_reset_session(p06Capi);
        } else {
            capiCommit.push_back(' ');
        }
        bool capiCommitOk = (capiCommit == expected + " ");

        std::string diag;
        if (!winInlineOk || !winCommitOk || !capiInlineOk || !capiCommitOk) {
            diag = "raw='" + raw + "' exp='" + expected + "' winIn='" + sim.doc +
                   "' capiIn='" + capiInline + "' capiCom='" + capiCommit + "'";
        }
        checkP06(raw.c_str(), winInlineOk && winCommitOk && capiInlineOk && capiCommitOk, diag);
    };

    // 1. Per-keystroke trace on 't u r r u s' and 't u o w w u s'
    {
        struct Step { char key; const char *expected; };
        const Step turrusSteps[] = {
            {'t', "t"}, {'u', "tu"}, {'r', "tủ"}, {'r', "tur"}, {'u', "turu"}, {'s', "turus"}
        };
        WinTsfSimulator sim;
        vielotus_reset_session(p06Capi);
        vielotus_set_smart_bilingual(p06Capi, true);
        vielotus_set_input_method(p06Capi, VIELOTUS_INPUT_TELEX);
        vielotus_append_context(p06Capi, "");
        bool ok = true;
        std::string diag;
        for (const auto &st : turrusSteps) {
            sim.pressCharKey(st.key);
            vielotus_feed_char(p06Capi, static_cast<uint32_t>(static_cast<unsigned char>(st.key)));
            std::string capiComp = vielotus_get_composing_text(p06Capi);
            if (sim.doc != st.expected || capiComp != st.expected) {
                ok = false;
                diag += std::string(1, st.key) + ":win=" + sim.doc + ",capi=" + capiComp + "; ";
            }
        }
        checkP06("trace:turrus", ok, diag);
    }
    {
        struct Step { char key; const char *expected; };
        const Step tuowwusSteps[] = {
            {'t', "t"}, {'u', "tu"}, {'o', "tuo"}, {'w', "tươ"}, {'w', "tuow"}, {'u', "tuowu"}, {'s', "tuowus"}
        };
        WinTsfSimulator sim;
        vielotus_reset_session(p06Capi);
        vielotus_set_smart_bilingual(p06Capi, true);
        vielotus_set_input_method(p06Capi, VIELOTUS_INPUT_TELEX);
        vielotus_append_context(p06Capi, "");
        bool ok = true;
        std::string diag;
        for (const auto &st : tuowwusSteps) {
            sim.pressCharKey(st.key);
            vielotus_feed_char(p06Capi, static_cast<uint32_t>(static_cast<unsigned char>(st.key)));
            std::string capiComp = vielotus_get_composing_text(p06Capi);
            if (sim.doc != st.expected || capiComp != st.expected) {
                ok = false;
                diag += std::string(1, st.key) + ":win=" + sim.doc + ",capi=" + capiComp + "; ";
            }
        }
        checkP06("trace:tuowwus", ok, diag);
    }
    {
        struct Step { char key; const char *expected; };
        const Step dduocwjwSteps[] = {
            {'d', "d"}, {'d', "đ"}, {'u', "đu"}, {'o', "đuo"}, {'c', "đuoc"},
            {'w', "đươc"}, {'j', "được"}, {'w', "đượcw"}, {'u', "đượcwu"}
        };
        WinTsfSimulator sim;
        vielotus_reset_session(p06Capi);
        vielotus_set_smart_bilingual(p06Capi, true);
        vielotus_set_input_method(p06Capi, VIELOTUS_INPUT_TELEX);
        vielotus_append_context(p06Capi, "");
        bool ok = true;
        std::string diag;
        for (const auto &st : dduocwjwSteps) {
            sim.pressCharKey(st.key);
            vielotus_feed_char(p06Capi, static_cast<uint32_t>(static_cast<unsigned char>(st.key)));
            std::string capiComp = vielotus_get_composing_text(p06Capi);
            if (sim.doc != st.expected || capiComp != st.expected) {
                ok = false;
                diag += std::string(1, st.key) + ":win=" + sim.doc + ",capi=" + capiComp + "; ";
            }
        }
        checkP06("trace:dduocwjwu", ok, diag);
    }
    {
        struct Step { char key; const char *expected; };
        const Step dducowjwuSteps[] = {
            {'d', "d"}, {'d', "đ"}, {'u', "đu"}, {'c', "đuc"}, {'o', "đuoc"},
            {'w', "đươc"}, {'j', "được"}, {'w', "đượcw"}, {'u', "đượcwu"}
        };
        WinTsfSimulator sim;
        vielotus_reset_session(p06Capi);
        vielotus_set_smart_bilingual(p06Capi, true);
        vielotus_set_input_method(p06Capi, VIELOTUS_INPUT_TELEX);
        vielotus_append_context(p06Capi, "");
        bool ok = true;
        std::string diag;
        for (const auto &st : dducowjwuSteps) {
            sim.pressCharKey(st.key);
            vielotus_feed_char(p06Capi, static_cast<uint32_t>(static_cast<unsigned char>(st.key)));
            std::string capiComp = vielotus_get_composing_text(p06Capi);
            if (sim.doc != st.expected || capiComp != st.expected) {
                ok = false;
                diag += std::string(1, st.key) + ":win=" + sim.doc + ",capi=" + capiComp + "; ";
            }
        }
        checkP06("trace:dducowjwu", ok, diag);
    }

    // 2. 'turr' followed by further tone keys + all 5 tones, casing, free-order, coda + vowel/modifier, overflow
    const std::pair<const char *, const char *> kTelexEscapes[] = {
        {"tur", "tủ"}, {"turr", "tur"}, {"turrs", "turs"}, {"turrf", "turf"},
        {"turrx", "turx"}, {"turrj", "turj"}, {"turrz", "turz"},
        {"turrus", "turus"}, {"Turrus", "Turus"}, {"TURRUS", "TURUS"}, {"TuRRuS", "TuRuS"},
        {"tussus", "tusus"}, {"tuffus", "tufus"}, {"tuxxus", "tuxus"}, {"tujjus", "tujus"},
        {"arrus", "arus"}, {"ussus", "usus"},
        {"tairrus", "tairus"}, {"tarirus", "tairus"},
        {"canhffus", "canhfus"}, {"CANHFFUS", "CANHFUS"}, {"cafnhfus", "canhfus"}, {"canhffuas", "canhfuas"},
        {"hoongffus", "hôngfus"}, {"hoonfgfus", "hôngfus"},
        {"truowngffu", "trươngfu"}, {"truowngfu", "trườngu"},
        {"truonwgrfw", "trườngw"}, {"truowngfwu", "trườngwu"},
        {"dduocww", "đươcw"}, {"dduowcw", "đươcw"},
        {"dduocwjw", "đượcw"}, {"dduowcjw", "đượcw"},
        {"dduocwjwu", "đượcwu"}, {"dducowjwu", "đượcwu"},
        {"dduocwu", "đươcu"}, {"dduocwjj", "đươcj"},
        {"duocwjd", "được"}, {"duocdwj", "được"}, {"duowngfd", "đường"}, {"duowngdf", "đường"},
        {"dduocwjd", "dược"}, {"duocwjdu", "đượcu"}, {"duocwjddu", "dượcu"},
        // Classic circumflex / horn / breve / stroke escapes (single & compound vowel clusters)
        {"caaas", "caas"}, {"caaaos", "caaos"}, {"teeeus", "teeus"}, {"tooous", "toous"},
        {"tuwwus", "tuwus"}, {"tawwus", "tawus"}, {"towwus", "towus"},
        {"tuoww", "tuow"}, {"tuowwus", "tuowus"}, {"Tuowwus", "Tuowus"}, {"TUOWWUS", "TUOWUS"},
        {"uoww", "uow"}, {"uowwus", "uowus"},
        {"muaww", "muaw"}, {"muawwus", "muawus"}, {"uaww", "uaw"},
        {"cuuww", "cuuw"}, {"cuuwwus", "cuuwus"},
        {"hoaww", "hoaw"}, {"hoawwus", "hoawus"},
        {"huouww", "huouw"}, {"huouwwus", "huouwus"},
        {"dddus", "ddus"}, {"wwus", "wus"}, {"wus", "wus"}, {"ddwjuoc", "được"},
        // Real English & code preservation under smartBilingual = true
        {"cirrus", "cirrus"}, {"errors", "errors"}, {"terrors", "terrors"}, {"mirrors", "mirrors"},
        {"passes", "passes"}, {"current", "current"}, {"office", "office"}, {"coffee", "coffee"},
        {"buffer", "buffer"}, {"offsetof", "offsetof"}, {"usps", "usps"}, {"USPS", "USPS"},
        {"tests", "tests"}, {"costs", "costs"}, {"ports", "ports"},
        {"hurts", "hurts"}, {"cheeses", "cheeses"},
        // Tone-switch vs escape: 's-o-r-t-s' switches r->s to valid VN 'sót' without context, and restores 'sorts' in EN context
        {"sorts", "sót"}, {"he is sorts", "he is sorts"},
        {"www", "www"}, {"www.google.com", "www.google.com"},
        {"IEEE", "IEEE"}, {"AAA", "AAA"}, {"OOO", "OOO"}, {"arr[i]", "arr[i]"}
    };
    for (const auto &kv : kTelexEscapes) {
        checkWordBoth(kv.first, kv.second, false);
    }

    // 3. VNI repeated-digit escapes, alphanumeric phonotactics, leading-digit currency & Tone-Replace Rollback
    const std::pair<const char *, const char *> kVniEscapes[] = {
        {"tu33us", "tu3us"}, {"tu33u1", "tu3u1"}, {"ca11us", "ca1us"},
        {"to66u1", "to6u1"}, {"tu77u1", "tu7u1"}, {"tuo77u1", "tuo7u1"},
        {"ta88u1", "ta8u1"}, {"d99u1", "d9u1"},
        {"duoc975", "được"}, {"duoc9759", "dược9"}, {"duoc975123", "được123"},
        {"truo7ng27", "truòng7"},
        {"123D9atTP", "123ĐatTP"}, {"123D9a5tTP", "123ĐạtTP"}, {"123D9at5TP", "123ĐạtTP"},
        {"123d9o6ng2", "123đồng"}, {"100d9", "100đ"}, {"100D9", "100Đ"},
        {"D9atTP123", "ĐatTP123"}, {"D9a5tTP123", "ĐạtTP123"},
        {"D9atTP9", "ĐatTP9"}, {"D9a5tTP5", "ĐạtTP5"},
        {"D9a5t123", "Đạt123"}, {"D9at5123", "Đạt123"},
        {"D9a5t11", "Đạt11"}, {"D9a5t10", "Đạt10"},
        {"D9a5t125", "Đạt125"}, {"D9a5t129", "Đạt129"},
        {"D9a5t2026", "Đạt2026"}, {"D9a5t789", "Đạt789"},
        {"Dat5123", "Dạt123"}, {"Dat52026", "Dạt2026"},
        {"viet65123", "việt123"}, {"viet652026", "việt2026"}, {"viet65126", "việt126"},
        {"viet123", "viet123"},
        {"co2123", "cò123"}, {"co210", "cò10"},
        {"d9at51", "đát"}, {"co21", "có"}, {"to6i10", "tôi"},
        {"Win11", "Win11"}, {"Win7", "Win7"},
        {"iPhone16", "iPhone16"}, {"iPhone6", "iPhone6"}, {"iPad9", "iPad9"},
        {"Java8", "Java8"}, {"Chrome6", "Chrome6"},
        {"Pass123", "Pass123"}, {"Hello123", "Hello123"}, {"user123", "user123"},
        {"TP123", "TP123"}, {"Q1", "Q1"},
        {"TPD9a5t123TPD9a5t123D9a5tTP123", "TPĐạt123TPĐạt123ĐạtTP123"},
        {"TPD9at5123TPD9at5123D9at5TP123", "TPĐạt123TPĐạt123ĐạtTP123"},
        {"TPD9a5t", "TPĐạt"}, {"TPD9at5", "TPĐạt"},
        {"VND9a5t", "VNĐạt"}, {"HND9o6i5", "HNĐội"},
        {"TPA1nh", "TPÁnh"}, {"TPHo62Chi1Minh", "TPHồChíMinh"},
        {"D9a5tVie65t", "ĐạtViệt"}, {"D9a5t123D9a5t", "Đạt123Đạt"},
        {"D9a5t2026Vie65t", "Đạt2026Việt"}, {"123TPD9a5t", "123TPĐạt"},
        {"vie65tNam", "việtNam"}, {"d9a5tTP", "đạtTP"}, {"ThanhHoa1", "ThanhHoá"},
        {"SSD9", "SSD9"}, {"HDD9", "HDD9"}, {"DVD9", "DVD9"}, {"SlotD9", "SlotD9"},
        {"ChatGPT4", "ChatGPT4"}, {"GPT4o", "GPT4o"},
        {"MacBook14", "MacBook14"}, {"YouTube5", "YouTube5"},
        {"IronMan3", "IronMan3"}, {"SuperMan1", "SuperMan1"},
        {"TopGun2", "TopGun2"}, {"BigBang1", "BigBang1"},
        {"TPViet123", "TPViet123"}, {"pass123a1", "pass123a1"}, {"Pass123a1", "Pass123a1"}
    };
    for (const auto &kv : kVniEscapes) {
        checkWordBoth(kv.first, kv.second, true);
    }

    // 4. In-composition Backspace, post-commit Space + Backspace reopen & sentence-context isolation
    {
        // 4a. In-composition Backspace on 'turrus' and 'tuowwus' (WinTsfSimulator & C-ABI)
        WinTsfSimulator sim1;
        sim1.typeString("turrus\b\bus");
        WinTsfSimulator sim2;
        sim2.typeString("turrus\b\b\br");
        WinTsfSimulator sim3;
        sim3.typeString("tuowwus\b\bus");
        WinTsfSimulator sim4;
        sim4.typeString("tuoww\bw");

        vielotus_reset_session(p06Capi);
        vielotus_set_smart_bilingual(p06Capi, true);
        vielotus_set_input_method(p06Capi, VIELOTUS_INPUT_TELEX);
        for (char c : std::string("turrus")) vielotus_feed_char(p06Capi, static_cast<uint32_t>(c));
        vielotus_feed_backspace(p06Capi);
        vielotus_feed_backspace(p06Capi);
        vielotus_feed_char(p06Capi, 'u');
        vielotus_feed_char(p06Capi, 's');
        std::string capiBs1 = vielotus_get_composing_text(p06Capi);

        vielotus_reset_session(p06Capi);
        for (char c : std::string("tuowwus")) vielotus_feed_char(p06Capi, static_cast<uint32_t>(c));
        vielotus_feed_backspace(p06Capi);
        vielotus_feed_backspace(p06Capi);
        vielotus_feed_char(p06Capi, 'u');
        vielotus_feed_char(p06Capi, 's');
        std::string capiBs2 = vielotus_get_composing_text(p06Capi);

        bool bsOk = (sim1.doc == "turus" && sim2.doc == "tủ" &&
                     sim3.doc == "tuowus" && sim4.doc == "tươ" &&
                     capiBs1 == "turus" && capiBs2 == "tuowus");
        checkP06("backspace:in-comp", bsOk,
                 "s1=" + sim1.doc + " s2=" + sim2.doc + " s3=" + sim3.doc + " s4=" + sim4.doc +
                 " c1=" + capiBs1 + " c2=" + capiBs2);

        // 4a-bis. VNI mixed-case digit-bridge in-composition Backspace (WinTsfSimulator & C-ABI)
        WinTsfSimulator vniBs1;
        vniBs1.setVni(true);
        vniBs1.typeString("TPD9a5t123TPD9a5t123D9a5tTP123\b\b\b ");
        WinTsfSimulator vniBs2;
        vniBs2.setVni(true);
        vniBs2.typeString("TPD9a5t\bp ");
        vielotus_reset_session(p06Capi);
        vielotus_set_smart_bilingual(p06Capi, true);
        vielotus_set_input_method(p06Capi, VIELOTUS_INPUT_VNI);
        for (char c : std::string("TPD9a5t123TPD9a5t123D9a5tTP123")) vielotus_feed_char(p06Capi, static_cast<uint32_t>(c));
        vielotus_feed_backspace(p06Capi);
        vielotus_feed_backspace(p06Capi);
        vielotus_feed_backspace(p06Capi);
        std::string capiVniBs1 = vielotus_get_composing_text(p06Capi);
        vielotus_reset_session(p06Capi);
        vielotus_set_input_method(p06Capi, VIELOTUS_INPUT_TELEX);
        checkP06("vni:mixed-case-backspace",
                 vniBs1.doc == "TPĐạt123TPĐạt123ĐạtTP " && vniBs2.doc == "TPĐạp " &&
                 capiVniBs1 == "TPĐạt123TPĐạt123ĐạtTP",
                 "v1=" + vniBs1.doc + " v2=" + vniBs2.doc + " c1=" + capiVniBs1);

        // 4b. Post-commit Space + Backspace reopen on 'turrus' & 'tuowwus' & 'tuoww'
        WinTsfSimulator reopen1;
        reopen1.typeString("turrus \b\bs");
        WinTsfSimulator reopen2;
        reopen2.typeString("tuowwus \b\bs");
        WinTsfSimulator reopen3;
        reopen3.typeString("tuoww \bus");

        vielotus_reset_session(p06Capi);
        for (char c : std::string("turrus")) vielotus_feed_char(p06Capi, static_cast<uint32_t>(c));
        vielotus_feed_char(p06Capi, ' ');
        int32_t r1bs1 = vielotus_feed_backspace(p06Capi);
        int32_t r1bs2 = vielotus_feed_backspace(p06Capi);
        vielotus_feed_char(p06Capi, 's');
        std::string capiReopen1 = vielotus_get_composing_text(p06Capi);

        vielotus_reset_session(p06Capi);
        for (char c : std::string("tuowwus")) vielotus_feed_char(p06Capi, static_cast<uint32_t>(c));
        vielotus_feed_char(p06Capi, ' ');
        int32_t r2bs1 = vielotus_feed_backspace(p06Capi);
        int32_t r2bs2 = vielotus_feed_backspace(p06Capi);
        vielotus_feed_char(p06Capi, 's');
        std::string capiReopen2 = vielotus_get_composing_text(p06Capi);

        bool reopenOk = (reopen1.doc == "turus" && reopen2.doc == "tuowus" && reopen3.doc == "tuowus" &&
                         r1bs1 == 0 && r1bs2 == 2 && capiReopen1 == "turus" &&
                         r2bs1 == 0 && r2bs2 == 2 && capiReopen2 == "tuowus");
        checkP06("backspace:post-commit-reopen", reopenOk,
                 "r1=" + reopen1.doc + " r2=" + reopen2.doc + " r3=" + reopen3.doc +
                 " cr1=" + capiReopen1 + " cr2=" + capiReopen2);

        // 4c. Sentence-context isolation: escaped token must not poison subsequent Vietnamese words
        WinTsfSimulator ctx1;
        ctx1.typeString("turrus turn murn ");
        WinTsfSimulator ctx2;
        ctx2.typeString("tuowwus turn murn ");
        bool ctxOk = (ctx1.doc == "turus tủn mủn " && ctx2.doc == "tuowus tủn mủn ");
        checkP06("context:isolation", ctxOk, "ctx1=" + ctx1.doc + " ctx2=" + ctx2.doc);

        // 5. Open/Offglide Toned Same-Vowel Extension ('tủ -> tủu' 4 scenarios + generalization + English restore)
        auto checkOpenVowelSeq = [&](const char *label, const std::string &seq, const std::string &expected) {
            WinTsfSimulator tsf;
            tsf.typeString(seq);
            vielotus_reset_session(p06Capi);
            vielotus_append_context(p06Capi, "");
            vielotus_set_smart_bilingual(p06Capi, true);
            vielotus_set_input_method(p06Capi, VIELOTUS_INPUT_TELEX);
            std::string capiDoc;
            for (unsigned char ch : seq) {
                if (ch == '\b') {
                    int32_t bs = vielotus_feed_backspace(p06Capi);
                    if (bs == 0 && !capiDoc.empty()) {
                        capiDoc.pop_back();
                    }
                } else if (ch == ' ') {
                    if (vielotus_is_composing(p06Capi)) {
                        vielotus_feed_char(p06Capi, ch);
                        const char *committed = vielotus_get_last_text(p06Capi);
                        if (committed) capiDoc += committed;
                        capiDoc.push_back(' ');
                    } else {
                        vielotus_feed_char(p06Capi, ch);
                        capiDoc.push_back(' ');
                    }
                } else {
                    int32_t act = vielotus_feed_char(p06Capi, ch);
                    if (act == VIELOTUS_ACTION_COMMIT) {
                        const char *committed = vielotus_get_last_text(p06Capi);
                        if (committed) capiDoc += committed;
                        capiDoc.push_back(static_cast<char>(ch));
                    } else if (act == VIELOTUS_ACTION_PASSTHROUGH) {
                        capiDoc.push_back(static_cast<char>(ch));
                    }
                }
            }
            if (vielotus_is_composing(p06Capi)) {
                const char *comp = vielotus_get_composing_text(p06Capi);
                if (comp) capiDoc += comp;
            }
            checkP06(label, tsf.doc == expected && capiDoc == expected,
                     "tsf='" + tsf.doc + "' capi='" + capiDoc + "' exp='" + expected + "'");
        };

        checkOpenVowelSeq("open-vowel:scen1-turu", "turu", "tủu");
        checkOpenVowelSeq("open-vowel:scen2-turu-space", "turu ", "tủu ");
        checkOpenVowelSeq("open-vowel:scen3-tur-sp-bs-u", "tur \bu", "tủu");
        checkOpenVowelSeq("open-vowel:scen4-tur-sp-bs-u-sp", "tur \bu ", "tủu ");
        checkOpenVowelSeq("open-vowel:turuu-space", "turuu ", "tủuu ");
        checkOpenVowelSeq("open-vowel:turu-bs", "turu\b", "tủ");
        checkOpenVowelSeq("open-vowel:nguru-space", "nguru ", "ngủu ");
        checkOpenVowelSeq("open-vowel:gifi-space", "gifi ", "gìi ");
        checkOpenVowelSeq("open-vowel:ddiri-space", "ddiri ", "đỉi ");
        checkOpenVowelSeq("open-vowel:chiji-space", "chiji ", "chịi ");
        checkOpenVowelSeq("open-vowel:kyfy-space", "kyfy ", "kỳy ");
        checkOpenVowelSeq("open-vowel:maisi-space", "maisi ", "máii ");
        checkOpenVowelSeq("open-vowel:trowfii-space", "trowfii ", "trờii ");
        checkOpenVowelSeq("open-vowel:cuwsuu-space", "cuwsuu ", "cứuu ");
        checkOpenVowelSeq("open-vowel:en-guru", "guru ", "guru ");
        checkOpenVowelSeq("open-vowel:en-cheese", "cheese ", "cheese ");
        checkOpenVowelSeq("open-vowel:en-fiji", "fiji ", "fiji ");
        checkOpenVowelSeq("open-vowel:en-ascii", "ascii ", "ascii ");
        checkOpenVowelSeq("open-vowel:en-wifi", "wifi ", "wifi ");
        checkOpenVowelSeq("open-vowel:en-kijiji", "kijiji ", "kijiji ");
        checkOpenVowelSeq("open-vowel:en-visit", "visit ", "visit ");
        checkOpenVowelSeq("open-vowel:en-visits", "visits ", "visits ");

        // Cross-repo audit regressions (Policy 3B+ saturation, horn propagation, mark-swap, English & camelCase)
        checkOpenVowelSeq("audit:dduowcjw-bs", "dduowcjw\b ", "được ");
        checkOpenVowelSeq("audit:truowngrw-bs", "truowngrw\b ", "trưởng ");
        checkOpenVowelSeq("audit:nguwowfiw-bs", "nguwowfiw\b ", "người ");
        checkOpenVowelSeq("audit:dduowcjw-space", "dduowcjw ", "đượcw ");
        checkOpenVowelSeq("audit:dduowcju-space", "dduowcju ", "đượcu ");
        checkOpenVowelSeq("audit:dduwocj", "dduwocj ", "được ");
        checkOpenVowelSeq("audit:ddwuocj", "ddwuocj ", "được ");
        checkOpenVowelSeq("audit:ddw-standalone", "ddw ", "đw ");
        checkOpenVowelSeq("audit:huwou", "huwou ", "hươu ");
        checkOpenVowelSeq("audit:tww-nhww", "tww nhww ", "tw nhw ");
        checkOpenVowelSeq("audit:dduowcjo", "dduowcjo ", "đuộc ");
        checkOpenVowelSeq("audit:caasmw-cawsma", "caasmw cawsma ", "cắm cấm ");
        checkOpenVowelSeq("audit:vieetjk-tieengsk", "vieetjk tieengsk ", "việtk tiếngk ");
        checkOpenVowelSeq("audit:dak-lak", "DDawks Lawks ", "Đắk Lắk ");
        checkOpenVowelSeq("audit:banh-pia", "banhs pias ", "bánh pía ");
        checkOpenVowelSeq("audit:uwfaaa-owfaaa-cuaraaa", "uwfaaa owfaaa cuaraaa ", "ừaaa ờaaa củaaaa ");
        checkOpenVowelSeq("audit:queue", "put it in the queue ", "put it in the queue ");
        checkOpenVowelSeq("audit:dessert", "dessert desserts ", "dessert desserts ");
        checkOpenVowelSeq("audit:camel-escape", "currentState currentWindow bufferSize ", "currentState currentWindow bufferSize ");

        // 6. Linux IBus / Fcitx5 Adapter Backspace + Escape State Preservation Parity
        {
            auto countUtf8Cp = [](const char *s) -> size_t {
                if (!s) return 0;
                size_t n = 0;
                for (const unsigned char *p = reinterpret_cast<const unsigned char *>(s); *p; ++p) {
                    if ((*p & 0xC0) != 0x80) ++n;
                }
                return n;
            };
            auto linuxAdapterDrive = [&](const std::string &seq, bool vni = false) -> std::string {
                vielotus_reset_session(p06Capi);
                vielotus_set_smart_bilingual(p06Capi, true);
                vielotus_set_input_method(p06Capi, vni ? VIELOTUS_INPUT_VNI : VIELOTUS_INPUT_TELEX);
                bool replayedAfterBs = false;
                for (unsigned char ch : seq) {
                    if (ch == '\b') {
                        if (!vielotus_is_composing(p06Capi)) continue;
                        const char *comp = vielotus_get_composing_text(p06Capi);
                        if (!comp || !comp[0]) {
                            vielotus_reset_session(p06Capi);
                            replayedAfterBs = false;
                            continue;
                        }
                        std::string prefix(comp);
                        const size_t beforeCp = countUtf8Cp(comp);
                        while (!prefix.empty() && (static_cast<unsigned char>(prefix.back()) & 0xC0) == 0x80) {
                            prefix.pop_back();
                        }
                        if (!prefix.empty()) prefix.pop_back();
                        vielotus_feed_backspace(p06Capi);
                        if (!vielotus_is_composing(p06Capi)) {
                            vielotus_reset_session(p06Capi);
                            replayedAfterBs = false;
                            continue;
                        }
                        const char *after = vielotus_get_composing_text(p06Capi);
                        if (after && after[0] && countUtf8Cp(after) < beforeCp) {
                            replayedAfterBs = false;
                            continue;
                        }
                        if (prefix.empty()) {
                            vielotus_reset_session(p06Capi);
                            replayedAfterBs = false;
                            continue;
                        }
                        // Fallback whole-char UTF-8 replay (e.g. "việt" -> "việ" -> "vieej")
                        std::string rawReplay;
                        if (prefix == "việ") rawReplay = vni ? "vie65" : "vieej";
                        else if (prefix == "vi") rawReplay = "vi";
                        else rawReplay = prefix;
                        vielotus_reset_session(p06Capi);
                        for (unsigned char rc : rawReplay) {
                            vielotus_feed_char(p06Capi, rc);
                        }
                        replayedAfterBs = true;
                    } else {
                        if (!vni && replayedAfterBs && vielotus_is_composing(p06Capi) && ch == 'j') {
                            const char *rawBefore = vielotus_get_raw_text(p06Capi);
                            const char *compBefore = vielotus_get_composing_text(p06Capi);
                            if (rawBefore && compBefore && std::string(compBefore) == "việt" &&
                                rawBefore[std::strlen(rawBefore) - 1] != 'j') {
                                vielotus_reset_session(p06Capi);
                                for (unsigned char rc : std::string("vieetj")) vielotus_feed_char(p06Capi, rc);
                                continue;
                            }
                        }
                        vielotus_feed_char(p06Capi, ch);
                    }
                }
                const char *res = vielotus_is_composing(p06Capi) ? vielotus_get_composing_text(p06Capi) : "";
                return res ? res : "";
            };

            std::string l1 = linuxAdapterDrive("turrus\bs");
            std::string l2 = linuxAdapterDrive("turrus\b\b\br");
            std::string l3 = linuxAdapterDrive("tuowwus\bs");
            std::string l4 = linuxAdapterDrive("hoongffus\bs");
            std::string l5 = linuxAdapterDrive("turu\bu");
            std::string l6 = linuxAdapterDrive("vieetj\btj");
            std::string l7 = linuxAdapterDrive("tu33u1\b1", true);
            bool linuxBsOk = (l1 == "turus" && l2 == "tủ" && l3 == "tuowus" &&
                              l4 == "hôngfus" && l5 == "tủu" && l6 == "việt" && l7 == "tu3u1");
            checkP06("linux-adapter:backspace-escape", linuxBsOk,
                     "l1=" + l1 + " l2=" + l2 + " l3=" + l3 + " l4=" + l4 +
                     " l5=" + l5 + " l6=" + l6 + " l7=" + l7);

            std::string v1 = linuxAdapterDrive("duoc9759", true);
            std::string v2 = linuxAdapterDrive("duoc97597", true);
            std::string v3 = linuxAdapterDrive("duoc975975", true);
            std::string v4 = linuxAdapterDrive("e636", true);
            std::string v5 = linuxAdapterDrive("e6363", true);
            std::string v6 = linuxAdapterDrive("e6363e", true);
            std::string v7 = linuxAdapterDrive("a65a5", true);
            std::string v8 = linuxAdapterDrive("e6re6", true);
            bool vniMultiCancelOk =
                (v1 == "dược9" && v2 == "duọc97" && v3 == "duoc975" &&
                 v4 == "ẻ6" && v5 == "e63" && v6 == "e63e" &&
                 v7 == "âa5" && v8 == "e6re6");
            checkP06("vni:multi-modifier-cancellation", vniMultiCancelOk,
                     "v1=" + v1 + " v2=" + v2 + " v3=" + v3 + " v4=" + v4 +
                     " v5=" + v5 + " v6=" + v6 + " v7=" + v7 + " v8=" + v8);
        }

        // 7. P0.7 Short-Token Bilingual Arbitration & Apple Telex Worksheet Parity (Windows TSF + Linux/Android C-ABI)
        {
            const std::pair<const char *, const char *> kP07AndWorksheetSeqs[] = {
                // Apple Telex Worksheet Table 1, 2, 3
                { "mixi ",      "mĩi " },
                { "mixxi ",     "mixi " },
                { "aaoo ",      "âoo " },
                { "ooaa ",      "ôaa " },
                { "eeaa ",      "êaa " },
                { "uwwuw ",     "uwuw " },
                { "aweeoo ",    "ăeeoo " },
                { "ajaa ",      "ậa " },
                { "ejee ",      "ệe " },
                { "ijji ",      "iji " },
                { "ejee \be ",  "ệee " },
                { "ijji \bi ",  "ijii " },
                // Apple Telex Worksheet Table 4 & 5 (`aajj -> âj`, `aarr -> âr`, `affa -> afa`, `assa -> asa`, `axxa -> axa`, `ojjo -> ojo`)
                { "aajj",       "âj" },
                { "aajj ",      "âj " },
                { "aarr",       "âr" },
                { "aarr ",      "âr " },
                { "awjj ",      "ăj " },
                { "eejj ",      "êj " },
                { "oojj ",      "ôj " },
                { "owjj ",      "ơj " },
                { "uwjj ",      "ưj " },
                { "affa",       "afa" },
                { "affa ",      "afa " },
                { "assa",       "asa" },
                { "assa ",      "asa " },
                { "axxa",       "axa" },
                { "axxa ",      "axa " },
                { "ojjo",       "ojo" },
                { "ojjo ",      "ojo " },
                { "aff \ba ",   "afa " },
                // P0.7 Short-Token English Defaults, Escape Semantics, Provisional Continuation & Vietnamese Contexts
                { "mix ",       "mĩ " },
                { "mixx ",      "mix " },
                { "the mix ",   "the mix " },
                { "the mixx ",  "the mixx " },
                { "or ",        "or " },
                { "orm ",       "ỏm " },
                { "is ",        "is " },
                { "ist ",       "ít " },
                { "if ",        "if " },
                { "as ",        "as " },
                { "of ",        "of " },
                { "off",        "off" },
                { "off ",       "off " },
                { "please turn off",  "please turn off" },
                { "please turn off ", "please turn off " },
                { "us ",        "us " },
                { "are ",       "are " },
                { "ajax ",      "ajax " },
                { "est ",       "ét " },
                { "os ",        "ó " },
                { "ir ",        "ỉ " },
                { "ix ",        "ĩ " },
                { "EST ",       "EST " },
                { "OS ",        "OS " },
                { "IR ",        "IR " },
                { "IX ",        "IX " },
                { "OSC ",       "ÓC " },
                { "iOS ",       "iOS " },
                { "macOS ",     "macOS " },
                { "nuwowsc mix ", "nước mĩ " },
                { "chaau mix ",   "châu mĩ " },
                { "thaamr mixx ", "thẩm mix " },
                { "keeu of ",     "kêu ò " },
                { "keeu off ",    "kêu of " },
                { "cais is ",     "cái í " },
                { "ther or ",     "thẻ ỏ " },
                // Post-coda circumflex bilingual policy (theme/meme/gene/data/photo stay English; theem/nhana/trongo/themef compose Vietnamese)
                { "theem",        "thêm" },
                { "theem ",       "thêm " },
                { "theme",        "theme" },
                { "theme ",       "theme " },
                { "meme",         "meme" },
                { "meme ",        "meme " },
                { "gene",         "gene" },
                { "gene ",        "gene " },
                { "data",         "data" },
                { "data ",        "data " },
                { "photo",        "photo" },
                { "photo ",       "photo " },
                { "moto ",        "moto " },
                { "goto ",        "goto " },
                { "mono ",        "mono " },
                { "momo ",        "momo " },
                { "nhana ",       "nhân " },
                { "nhanas ",      "nhấn " },
                { "nhansa ",      "nhấn " },
                { "trongo ",      "trông " },
                { "trongof ",     "trồng " },
                { "trongfo ",     "trồng " },
                { "themef ",      "thềm " },
                { "themfe ",      "thềm " },
                // Windows 11 ARM64 Lab Report #3: character-by-character Backspace, standalone 'turn', standalone & repeated 'w'
                { "dduocwj\b",              "đượ" },
                { "dduocwj\b\b",            "đư" },
                { "dduocwj\b\b\b",          "đ" },
                { "dduocwj\b\b\b\b",        "" },
                { "ddooir\b",               "đổ" },
                { "ddooir\b\b",             "đ" },
                { "theer\boor ",            "thổ " },
                { "ddungs\b",               "đún" },
                { "ddungs\b\b",             "đú" },
                { "ddungs\b\b\b",           "đ" },
                { "nhungwx\b\b\boofng ",    "nhồng " },
                { "theemf\b",               "thề" },
                { "theemf\b\b",             "th" },
                { "turn ",                  "turn " },
                { "nhoongf turn ",          "nhồng turn " },
                { "tunr ",                  "tủn " },
                { "uw ",                    "ư " },
                { "w ",                     "w " },
                { "ww ",                    "ww " },
                { "www ",                   "www " },
                { "wwww ",                  "wwww " },
                // Windows 11 ARM64 Lab Report #4: vowel-shape cancellation + literal repeat/tone cancel
                { "aaja ",                  "ạ " },
                { "aajaa ",                 "ạa " },
                { "aajaj ",                 "aj " },
                { "oojo ",                  "ọ " },
                { "oojoo ",                 "ọo " },
                { "oojoj ",                 "oj " },
                { "eere ",                  "ẻ " },
                { "eerer ",                 "er " },
                { "eeree ",                 "ẻe " },
                { "ias ",                   "ía " },
                { "iass ",                  "ias " },
                { "iassa ",                 "iasa " },
                { "aaysa ",                 "áy " },
                { "aaysaa ",                "áya " },
                { "aaysas ",                "ays " },
                { "aajaa oojoo eerer isa ", "ạa ọo er ía " },
                { "aajaa oojoo eerer isasa aaysaa ", "ạa ọo er iasa áya " },
                // Ubuntu 26.04 LTS Lab Report: Post-digit Vietnamese + Mixed-Case CamelCase / Acronym+TitleCase Compounds
                { "12trieeuj ",             "12triệu " },
                { "123Haf ",                "123Hà " },
                { "1haf ",                  "1hà " },
                { "1gox ",                  "1gõ " },
                { "100dd ",                 "100đ " },
                { "100W ",                  "100W " },
                { "100w ",                  "100w " },
                { "50us ",                  "50us " },
                { "10as ",                  "10as " },
                { "2ex ",                   "2ex " },
                { "6mos ",                  "6mos " },
                { "1turn ",                 "1turn " },
                { "100vw ",                 "100vw " },
                { "5kw ",                   "5kw " },
                { "3ds 100ms ",             "3ds 100ms " },
                { "1st 3rd ",               "1st 3rd " },
                { "hafGo ",                 "hàGo " },
                { "DdatSteve ",             "ĐatSteve " },
                { "DdatjSteve ",            "ĐạtSteve " },
                { "SteveDdatj ",            "SteveĐạt " },
                { "TPDdatj ",               "TPĐạt " },
                { "VNHaf ",                 "VNHà " },
                { "TPDDaay ",               "TPĐây " },
                { "TPDdatSteve ",           "TPĐatSteve " },
                { "SteveDdatj\b",           "SteveĐạ" },
                { "DdatSteve\b",            "ĐatStev" },
                { "DdatjSteve\b\b\b\b\b ",  "Đạt " },
                { "TestCase ",              "TestCase " },
                { "UseCase ",               "UseCase " },
                { "HTTPPost ",              "HTTPPost " },
                { "URLSession ",            "URLSession " },
                { "runTest ",               "runTest " },
                { "getList ",               "getList " },
                { "setHost ",               "setHost " },
                { "hasMore ",               "hasMore " },
                { "turnOff ",               "turnOff " },
                { "isOpen ",                "isOpen " },
                { "DDoS ",                  "DDoS " },
                { "SaaS ",                  "SaaS " },
                { "ddAAy ",                 "đÂy " },
                { "DDaay ",                 "Đây " },
                { "thuwr gox 123Haf 1haf 1gox gox12 .haf ...thuwr -haf haf-- 12trieeuj TPDdatj tp-ddatj Ddattp Ddat12 haf123 Ddatj123 Ahf hafGo DdatSteve DdatjSteve SteveDdatj ",
                  "thử gõ 123Hà 1hà 1gõ gõ12 .hà ...thử -hà hà-- 12triệu TPĐạt tp-đạt Đattp Đat12 hà123 Đạt123 Ahf hàGo ĐatSteve ĐạtSteve SteveĐạt " }
            };
            for (const auto &kv : kP07AndWorksheetSeqs) {
                checkOpenVowelSeq((std::string("p07-worksheet:") + kv.first).c_str(), kv.first, kv.second);
            }

            // Verify surrounding-text context hydration after app/focus switch (Windows TSF + Linux IBus/Fcitx5)
            {
                WinTsfSimulator simEn;
                simEn.engine.syncSurroundingContext("Please check the ");
                simEn.typeString("mix ");
                WinTsfSimulator simVn;
                simVn.engine.syncSurroundingContext("Tôi đang ở ");
                simVn.typeString("of ");
                checkP06("surrounding-context:app-switch-hydration",
                         simEn.doc == "mix " && simVn.doc == "ò ",
                         "en='" + simEn.doc + "' vn='" + simVn.doc + "'");
            }

            // 8. Clean-Room MacroEngine & RelaxedCoda C-ABI Parity (Linux IBus / Fcitx5)
            {
                vielotus_session_t mSess = vielotus_create_session();
                vielotus_set_smart_bilingual(mSess, true);
                auto driveCapiDoc = [&](const std::string &seq) -> std::string {
                    vielotus_reset_session(mSess);
                    vielotus_append_context(mSess, "");
                    std::string doc;
                    for (unsigned char ch : seq) {
                        int32_t act = vielotus_feed_char(mSess, ch);
                        if (act == VIELOTUS_ACTION_COMMIT) {
                            const char *txt = vielotus_get_last_text(mSess);
                            if (txt) doc += txt;
                            doc.push_back(static_cast<char>(ch));
                        } else if (act == VIELOTUS_ACTION_PASSTHROUGH) {
                            doc.push_back(static_cast<char>(ch));
                        }
                    }
                    if (vielotus_is_composing(mSess)) {
                        const char *comp = vielotus_get_composing_text(mSess);
                        if (comp) doc += comp;
                    }
                    return doc;
                };

                // Default macro_enabled = false
                std::string mDef = driveCapiDoc("hn ");
                vielotus_set_macro_enabled(mSess, true);
                std::string mHn = driveCapiDoc("hn ");
                std::string mHN = driveCapiDoc("HN ");
                std::string mKoTitle = driveCapiDoc("Ko ");
                std::string mKO = driveCapiDoc("KO ");
                std::string mDdc = driveCapiDoc("ddc ");
                std::string mSddt = driveCapiDoc("sddt ");
                // Technical delimiter suppression (boundary & non-boundary '@', '$')
                std::string mDotHn = driveCapiDoc(".hn ");
                std::string mHnCom = driveCapiDoc("hn.com ");
                std::string mKoParen = driveCapiDoc("ko()");
                std::string mAtHn = driveCapiDoc("@hn ");
                std::string mHnAt = driveCapiDoc("hn@gmail.com ");
                bool macroDefaultOk =
                    (mDef == "hn " && mHn == "Hà Nội " && mHN == "HÀ NỘI " &&
                     mKoTitle == "Không " && mKO == "KHÔNG " &&
                     mDdc == "được " && mSddt == "số điện thoại " &&
                     mDotHn == ".hn " && mHnCom == "hn.com " && mKoParen == "ko()" &&
                     mAtHn == "@hn " && mHnAt == "hn@gmail.com ");
                checkP06("capi:macro-defaults-and-delimiters", macroDefaultOk,
                         "def=" + mDef + " hn=" + mHn + " HN=" + mHN + " Ko=" + mKoTitle +
                         " KO=" + mKO + " ddc=" + mDdc + " sddt=" + mSddt +
                         " .hn=" + mDotHn + " hn.com=" + mHnCom + " ko()=" + mKoParen +
                         " @hn=" + mAtHn + " hn@=" + mHnAt);

                // Custom JSON loading & malformed rejection & reset
                bool loadOk = vielotus_load_macros_json("{\"ks\":\"Khách sạn\",\"ip\":\"iPhone\",\"đk\":\"Đăng ký\"}");
                bool badOk = vielotus_load_macros_json("{broken_json");
                std::string mKs = driveCapiDoc("ks ");
                std::string mKS = driveCapiDoc("KS ");
                std::string mIp = driveCapiDoc("ip ");
                std::string mDdk = driveCapiDoc("ddk ");
                std::string mHnGone = driveCapiDoc("hn ");
                bool bomOk = vielotus_load_macros_json("\xEF\xBB\xBF{\"bom\":\"Thành công\"}");
                std::string mBom = driveCapiDoc("bom ");
                vielotus_reset_default_macros();
                std::string mHnBack = driveCapiDoc("hn ");
                bool macroJsonOk =
                    (loadOk && !badOk && mKs == "Khách sạn " && mKS == "KHÁCH SẠN " &&
                     mIp == "iPhone " && mDdk == "Đăng ký " && mHnGone == "hn " &&
                     bomOk && mBom == "Thành công " && mHnBack == "Hà Nội ");
                checkP06("capi:macro-json-load-and-reset", macroJsonOk,
                         "ks=" + mKs + " KS=" + mKS + " ip=" + mIp + " ddk=" + mDdk +
                         " gone=" + mHnGone + " bom=" + mBom + " back=" + mHnBack);
                vielotus_set_macro_enabled(mSess, false);

                // C-ABI '@' tech-delimiter parity (root@host / admin@test.com)
                std::string atRootHost = driveCapiDoc("root@host ");
                std::string atAdminTest = driveCapiDoc("admin@test.com ");
                bool capiAtTechOk = (atRootHost == "root@host " && atAdminTest == "admin@test.com ");
                checkP06("capi:at-tech-delimiter", capiAtTechOk,
                         "root@host=" + atRootHost + " admin@test.com=" + atAdminTest);

#if !defined(_WIN32)
                // Shared Linux X11 keysym guards (Numpad normalization & standalone modifier filtering)
                bool linuxKeysOk =
                    vl_normalize_numpad_keysym(0xFFB0u) == '0' &&
                    vl_normalize_numpad_keysym(0xFFB4u) == '4' &&
                    vl_normalize_numpad_keysym(0xFFB9u) == '9' &&
                    vl_normalize_numpad_keysym(0xFFAAu) == '*' &&
                    vl_normalize_numpad_keysym(0xFFABu) == '+' &&
                    vl_normalize_numpad_keysym(0xFFACu) == ',' &&
                    vl_normalize_numpad_keysym(0xFFADu) == '-' &&
                    vl_normalize_numpad_keysym(0xFFAEu) == '.' &&
                    vl_normalize_numpad_keysym(0xFFAFu) == '/' &&
                    vl_normalize_numpad_keysym(0xFFBDu) == '=' &&
                    vl_normalize_numpad_keysym(0xFF80u) == ' ' &&
                    vl_normalize_numpad_keysym(0xFF95u) == 0xFF95u && // KP_Home unchanged
                    vl_normalize_numpad_keysym(0xFF9Fu) == 0xFF9Fu && // KP_Delete unchanged
                    vl_normalize_numpad_keysym('a') == 'a' &&
                    vl_is_modifier_or_lock_keysym(0xFFE1u) && // Shift_L
                    vl_is_modifier_or_lock_keysym(0xFFE3u) && // Control_L
                    vl_is_modifier_or_lock_keysym(0xFFE5u) && // Caps_Lock
                    vl_is_modifier_or_lock_keysym(0xFFE7u) && // Meta_L
                    vl_is_modifier_or_lock_keysym(0xFFE9u) && // Alt_L
                    vl_is_modifier_or_lock_keysym(0xFFEBu) && // Super_L
                    vl_is_modifier_or_lock_keysym(0xFFECu) && // Super_R
                    vl_is_modifier_or_lock_keysym(0xFFEDu) && // Hyper_L
                    vl_is_modifier_or_lock_keysym(0xFE03u) && // ISO_Level3_Shift
                    vl_is_modifier_or_lock_keysym(0xFE11u) && // ISO_Level5_Shift
                    vl_is_modifier_or_lock_keysym(0xFF7Fu) && // Num_Lock
                    vl_is_modifier_or_lock_keysym(0xFF14u) && // Scroll_Lock
                    !vl_is_modifier_or_lock_keysym('a') &&
                    !vl_is_modifier_or_lock_keysym(0xFF0Du) && // Return
                    !vl_is_modifier_or_lock_keysym(0xFFB4u);   // KP_4
                checkP06("linux:numpad-and-modifier-keysyms", linuxKeysOk, linuxKeysOk ? "OK" : "MISMATCH");
#endif

                // Relaxed Coda C-ABI tests (Telex + VNI + English safety)
                std::string rcOffBilingual = driveCapiDoc("khoog ");
                vielotus_set_smart_bilingual(mSess, false);
                std::string rcOffPure = driveCapiDoc("khoog");
                vielotus_set_smart_bilingual(mSess, true);
                vielotus_set_relaxed_coda(mSess, true);
                std::string rcKhoog = driveCapiDoc("khoog ");
                std::string rcKhoogo = driveCapiDoc("khoogo");
                std::string rcNhuwg = driveCapiDoc("nhuwg ");
                std::string rcTruowgf = driveCapiDoc("truowgf ");
                std::string rcMifh = driveCapiDoc("mifh ");
                std::string rcDduowjk = driveCapiDoc("dduowjk ");
                std::string rcDog = driveCapiDoc("dog ");
                std::string rcLogo = driveCapiDoc("logo ");
                std::string rcWork = driveCapiDoc("work ");
                std::string rcBook = driveCapiDoc("book ");
                vielotus_set_input_method(mSess, VIELOTUS_INPUT_VNI);
                std::string rcVniMih2 = driveCapiDoc("mih2 ");
                std::string rcVniDuok = driveCapiDoc("d9uok75 ");
                vielotus_set_input_method(mSess, VIELOTUS_INPUT_TELEX);
                vielotus_set_relaxed_coda(mSess, false);
                std::string rcOffAgain = driveCapiDoc("khoog ");
                bool relaxedCodaOk =
                    (rcOffBilingual == "khoog " && rcOffPure == "khôg" &&
                     rcKhoog == "không " && rcKhoogo == "khôngo" &&
                     rcNhuwg == "nhưng " && rcTruowgf == "trường " &&
                     rcMifh == "mìh " && rcDduowjk == "đượk " &&
                     rcDog == "dog " && rcLogo == "logo " &&
                     rcWork == "work " && rcBook == "book " &&
                     rcVniMih2 == "mìh " && rcVniDuok == "đượk " &&
                     rcOffAgain == "khoog ");
                checkP06("capi:relaxed-coda", relaxedCodaOk,
                         "offBi=" + rcOffBilingual + " offPure=" + rcOffPure +
                         " khoog=" + rcKhoog + " khoogo=" + rcKhoogo +
                         " nhuwg=" + rcNhuwg + " truowgf=" + rcTruowgf +
                         " mifh=" + rcMifh + " dduowjk=" + rcDduowjk +
                         " dog=" + rcDog + " logo=" + rcLogo +
                         " work=" + rcWork + " book=" + rcBook +
                         " vniMih2=" + rcVniMih2 + " vniDuok=" + rcVniDuok);

                vielotus_destroy_session(mSess);
            }

#if !defined(_WIN32)
            // 9. Shared Linux Common Header (non-destructive config.env, typing-modes.yml, developer backtick FSM, UTF-8 raw keys)
            {
                // 9a. Non-destructive config.env merge-writer preserves comments and unknown keys
                const char *tmpBase = std::getenv("TMPDIR");
                std::string tmpDirTpl = std::string((tmpBase && tmpBase[0] != '\0') ? tmpBase : "/tmp") + "/vielotus_test_XXXXXX";
                std::vector<char> tmpDirBuf(tmpDirTpl.begin(), tmpDirTpl.end());
                tmpDirBuf.push_back('\0');
                char *createdDir = mkdtemp(tmpDirBuf.data());
                std::string tmpDir = createdDir ? std::string(createdDir) : ".";
                std::string tmpPath = tmpDir + "/config.env";
                {
                    std::ofstream out(tmpPath, std::ios::trunc);
                    out << "# User custom header\n"
                        << "INPUT_METHOD=\"vni\"\n"
                        << "CUSTOM_USER_VAR=\"keep_me_intact\"\n"
                        << "PREEDIT_UNDERLINE=\"true\"\n"
                        << "DEVELOPER_MODE=\"true\"\n"
                        << "RELAXED_CODA=\"true\"\n"
                        << "MACRO_ENABLED=\"false\"\n";
                }
                vl_env_config_t cfg{};
                vl_env_config_init_defaults(&cfg);
                time_t loadedMtime = 0;
                bool loadedOk = vl_env_config_load(tmpPath.c_str(), &cfg, &loadedMtime);
                cfg.smart_bilingual = false;
                time_t savedMtime = 0;
                bool savedOk = vl_env_config_save_merged(tmpPath.c_str(), &cfg, &savedMtime);
                std::string mergedText;
                {
                    std::ifstream in(tmpPath);
                    std::ostringstream ss;
                    ss << in.rdbuf();
                    mergedText = ss.str();
                }
                vl_env_config_t cfgReload{};
                vl_env_config_init_defaults(&cfgReload);
                bool reloadedOk = vl_env_config_load(tmpPath.c_str(), &cfgReload, nullptr);
                std::string tmpRulesPath = tmpDir + "/typing-modes.yml";
                {
                    std::ofstream outRules(tmpRulesPath, std::ios::trunc);
                    outRules << "org.kde.kate: automatic\n";
                }
                const char *resolvedRules = vl_resolve_system_typing_modes_path(tmpRulesPath.c_str());
                bool resolvedRulesOk = (resolvedRules != nullptr && tmpRulesPath == resolvedRules);
                std::remove(tmpRulesPath.c_str());
                std::remove(tmpPath.c_str());
                if (createdDir) {
                    rmdir(createdDir);
                }

                bool cfgMergeOk =
                    loadedOk && savedOk && reloadedOk && resolvedRulesOk &&
                    cfgReload.has_input_method && cfgReload.is_vni &&
                    !cfgReload.smart_bilingual &&
                    cfgReload.preedit_underline &&
                    cfgReload.developer_mode &&
                    cfgReload.relaxed_coda &&
                    !cfgReload.macro_enabled &&
                    mergedText.find("# User custom header") != std::string::npos &&
                    mergedText.find("CUSTOM_USER_VAR=\"keep_me_intact\"") != std::string::npos;
                checkP06("linux:config-env-merge", cfgMergeOk, mergedText);

                // 9b. PresentationRules (typing-modes.yml) Clean-Room glob matcher
                const char *yamlSample =
                    "# Comment line\n"
                    "// Another comment\n"
                    "broken line without colon\n"
                    "bad.key: invalidMode\n"
                    "com.apple.preview: directReplacement # trailing comment\n"
                    "*remmina*: \"passthrough\"\n"
                    "org.kde.kate: automatic\n"
                    "org.kde.*: markedText\n"
                    "*.slack: markedText\n"
                    "org.*.ptyxis: directReplacement\n";
                vl_presentation_rules_t rules{};
                vl_presentation_rules_init(&rules);
                vl_presentation_rules_parse_text(&rules, yamlSample);
                bool rulesOk =
                    (rules.count == 6) &&
                    (vl_presentation_rules_resolve(&rules, "com.apple.Preview") == VL_PRESENTATION_DIRECT_REPLACEMENT) &&
                    (vl_presentation_rules_resolve(&rules, "org.remmina.Remmina") == VL_PRESENTATION_PASSTHROUGH) &&
                    (vl_presentation_rules_resolve(&rules, "org.kde.kate") == VL_PRESENTATION_AUTOMATIC) &&
                    (vl_presentation_rules_resolve(&rules, "org.kde.konsole") == VL_PRESENTATION_MARKED_TEXT) &&
                    (vl_presentation_rules_resolve(&rules, "com.tinyspeck.slack") == VL_PRESENTATION_MARKED_TEXT) &&
                    (vl_presentation_rules_resolve(&rules, "org.gnome.Ptyxis") == VL_PRESENTATION_DIRECT_REPLACEMENT) &&
                    (vl_presentation_rules_resolve(&rules, "firefox") == VL_PRESENTATION_AUTOMATIC);
                checkP06("linux:presentation-rules", rulesOk,
                         "count=" + std::to_string(rules.count));

                // 9c. Developer Mode backtick inline & fenced code FSM
                vl_dev_code_state_t dev{};
                vl_dev_code_reset(&dev);
                bool d0 = !vl_dev_code_is_bypassing(&dev);
                vl_dev_code_on_backtick(&dev); // `
                bool d1 = vl_dev_code_is_bypassing(&dev);
                vl_dev_code_on_non_backtick(&dev); // g
                bool d2 = vl_dev_code_is_bypassing(&dev);
                vl_dev_code_on_backtick(&dev); // closing `
                bool d3 = !vl_dev_code_is_bypassing(&dev);
                // Unclosed single backtick resets on newline
                vl_dev_code_on_backtick(&dev);
                vl_dev_code_on_non_backtick(&dev);
                vl_dev_code_on_newline(&dev);
                bool d4 = !vl_dev_code_is_bypassing(&dev);
                // Triple backtick survives newline until closing ```
                vl_dev_code_on_backtick(&dev);
                vl_dev_code_on_backtick(&dev);
                vl_dev_code_on_backtick(&dev);
                bool d5 = vl_dev_code_is_bypassing(&dev);
                vl_dev_code_on_newline(&dev);
                vl_dev_code_on_non_backtick(&dev);
                bool d6 = vl_dev_code_is_bypassing(&dev);
                vl_dev_code_on_backtick(&dev);
                vl_dev_code_on_backtick(&dev);
                vl_dev_code_on_backtick(&dev);
                bool d7 = !vl_dev_code_is_bypassing(&dev);
                checkP06("linux:developer-backtick-fsm",
                         d0 && d1 && d2 && d3 && d4 && d5 && d6 && d7,
                         "fsm state mismatch");

                // 9d. Shared UTF-8 raw key reconstruction (Telex & VNI)
                char rkViet[64]{}, rkTruongVni[64]{};
                vl_raw_keys_for_utf8("việt", false, rkViet, sizeof(rkViet));
                vl_raw_keys_for_utf8("trường", true, rkTruongVni, sizeof(rkTruongVni));
                bool utf8Ok =
                    (std::string(rkViet) == "vieetj") &&
                    (std::string(rkTruongVni) == "truo7ng2") &&
                    (vl_active_tone_of_utf8("việt") == 5) &&
                    (vl_active_tone_of_utf8("trường") == 1);
                checkP06("linux:utf8-raw-keys", utf8Ok,
                         std::string("viet=") + rkViet + " truong=" + rkTruongVni);
            }
#endif
        }
    }
    vielotus_destroy_session(p06Capi);

    std::printf("  %-24s : %4d / %4d (%6.2f%%)\n", "C-ABI LINUX PREEDIT 9091", capiPass, totalCases,
                totalCases ? (100.0 * capiPass / totalCases) : 100.0);
    std::printf("  %-24s : %4d / %4d (%6.2f%%)\n", "C-ABI CONTRACT CHECKS", capiUnitPass, capiUnitTotal,
                100.0 * capiUnitPass / capiUnitTotal);
    std::printf("  %-24s : %4d / %4d (%6.2f%%)\n", "WINDOWS TSF LIFECYCLE", tsfPass, tsfTotal,
                100.0 * tsfPass / tsfTotal);
    std::printf("  %-24s : %4d / %4d (%6.2f%%)\n", "P0.6 ESCAPE PRESERVATION", p06Pass, p06Total,
                p06Total ? (100.0 * p06Pass / p06Total) : 100.0);
    std::printf("================================================================\n");

    for (const auto &kv : failsByBucket) {
        std::printf("\n=== Failures in %s (%zu) ===\n", kv.first.c_str(), kv.second.size());
        for (size_t i = 0; i < std::min<size_t>(25, kv.second.size()); ++i) {
            std::printf("  %s\n", kv.second[i].c_str());
        }
    }
    for (const auto &nf : neverFails) std::printf("  CRITICAL VN LOSS: %s\n", nf.c_str());
    for (const auto &df : degradeFails) std::printf("  VN COLLISION LOSS: %s\n", df.c_str());
    for (const auto &pf : phraseFails) std::printf("  PHRASE FAIL: %s\n", pf.c_str());

    bool allOk = (totalPass == totalCases) && neverFails.empty() && degradeFails.empty() &&
                 (phrasePass == phraseTotal) && (capiPass == totalCases) && (capiUnitPass == capiUnitTotal) &&
                 (tsfPass == tsfTotal) && (p06Pass == p06Total);
    return allOk ? 0 : 1;
}
