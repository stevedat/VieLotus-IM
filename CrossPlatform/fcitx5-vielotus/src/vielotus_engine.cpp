#include "vielotus_engine.h"
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <fcitx-utils/capabilityflags.h>
#include <fcitx-utils/keysym.h>
#include <fcitx-utils/misc.h>
#include <fcitx-utils/textformatflags.h>
#include <fcitx/addonmanager.h>
#include <fcitx/inputcontextmanager.h>
#include <fcitx/inputpanel.h>
#include <fcitx/statusarea.h>
#include <fcitx/userinterfacemanager.h>

namespace fcitx {

namespace {

struct VieLotusUtf8CharMap {
    const char* lower_utf8;
    const char* upper_utf8;
    char lower_base;
    char upper_base;
    uint8_t mod;  // 0=none, 1=d-stroke, 2=circumflex(^), 3=breve(ă), 4=horn(ư/ơ)
    uint8_t tone; // 0=none, 1=grave(f/2), 2=acute(s/1), 3=hook(r/3), 4=tilde(x/4), 5=dot(j/5)
};

constexpr VieLotusUtf8CharMap kVnUtf8Map[] = {
    { "đ", "Đ", 'd', 'D', 1, 0 },
    { "à", "À", 'a', 'A', 0, 1 }, { "á", "Á", 'a', 'A', 0, 2 }, { "ả", "Ả", 'a', 'A', 0, 3 }, { "ã", "Ã", 'a', 'A', 0, 4 }, { "ạ", "Ạ", 'a', 'A', 0, 5 },
    { "ă", "Ă", 'a', 'A', 3, 0 }, { "ằ", "Ằ", 'a', 'A', 3, 1 }, { "ắ", "Ắ", 'a', 'A', 3, 2 }, { "ẳ", "Ẳ", 'a', 'A', 3, 3 }, { "ẵ", "Ẵ", 'a', 'A', 3, 4 }, { "ặ", "Ặ", 'a', 'A', 3, 5 },
    { "â", "Â", 'a', 'A', 2, 0 }, { "ầ", "Ầ", 'a', 'A', 2, 1 }, { "ấ", "Ấ", 'a', 'A', 2, 2 }, { "ẩ", "Ẩ", 'a', 'A', 2, 3 }, { "ẫ", "Ẫ", 'a', 'A', 2, 4 }, { "ậ", "Ậ", 'a', 'A', 2, 5 },
    { "è", "È", 'e', 'E', 0, 1 }, { "é", "É", 'e', 'E', 0, 2 }, { "ẻ", "Ẻ", 'e', 'E', 0, 3 }, { "ẽ", "Ẽ", 'e', 'E', 0, 4 }, { "ẹ", "Ẹ", 'e', 'E', 0, 5 },
    { "ê", "Ê", 'e', 'E', 2, 0 }, { "ề", "Ề", 'e', 'E', 2, 1 }, { "ế", "Ế", 'e', 'E', 2, 2 }, { "ể", "Ể", 'e', 'E', 2, 3 }, { "ễ", "Ễ", 'e', 'E', 2, 4 }, { "ệ", "Ệ", 'e', 'E', 2, 5 },
    { "ì", "Ì", 'i', 'I', 0, 1 }, { "í", "Í", 'i', 'I', 0, 2 }, { "ỉ", "Ỉ", 'i', 'I', 0, 3 }, { "ĩ", "Ĩ", 'i', 'I', 0, 4 }, { "ị", "Ị", 'i', 'I', 0, 5 },
    { "ò", "Ò", 'o', 'O', 0, 1 }, { "ó", "Ó", 'o', 'O', 0, 2 }, { "ỏ", "Ỏ", 'o', 'O', 0, 3 }, { "õ", "Õ", 'o', 'O', 0, 4 }, { "ọ", "Ọ", 'o', 'O', 0, 5 },
    { "ô", "Ô", 'o', 'O', 2, 0 }, { "ồ", "Ồ", 'o', 'O', 2, 1 }, { "ố", "Ố", 'o', 'O', 2, 2 }, { "ổ", "Ổ", 'o', 'O', 2, 3 }, { "ỗ", "Ỗ", 'o', 'O', 2, 4 }, { "ộ", "Ộ", 'o', 'O', 2, 5 },
    { "ơ", "Ơ", 'o', 'O', 4, 0 }, { "ờ", "Ờ", 'o', 'O', 4, 1 }, { "ớ", "Ớ", 'o', 'O', 4, 2 }, { "ở", "Ở", 'o', 'O', 4, 3 }, { "ỡ", "Ỡ", 'o', 'O', 4, 4 }, { "ợ", "Ợ", 'o', 'O', 4, 5 },
    { "ù", "Ù", 'u', 'U', 0, 1 }, { "ú", "Ú", 'u', 'U', 0, 2 }, { "ủ", "Ủ", 'u', 'U', 0, 3 }, { "ũ", "Ũ", 'u', 'U', 0, 4 }, { "ụ", "Ụ", 'u', 'U', 0, 5 },
    { "ư", "Ư", 'u', 'U', 4, 0 }, { "ừ", "Ừ", 'u', 'U', 4, 1 }, { "ứ", "Ứ", 'u', 'U', 4, 2 }, { "ử", "Ử", 'u', 'U', 4, 3 }, { "ữ", "Ữ", 'u', 'U', 4, 4 }, { "ự", "Ự", 'u', 'U', 4, 5 },
    { "ỳ", "Ỳ", 'y', 'Y', 0, 1 }, { "ý", "Ý", 'y', 'Y', 0, 2 }, { "ỷ", "Ỷ", 'y', 'Y', 0, 3 }, { "ỹ", "Ỹ", 'y', 'Y', 0, 4 }, { "ỵ", "Ỵ", 'y', 'Y', 0, 5 },
};

inline size_t utf8CharLen(unsigned char b) {
    if ((b & 0x80) == 0) return 1;
    if ((b & 0xE0) == 0xC0) return 2;
    if ((b & 0xF0) == 0xE0) return 3;
    if ((b & 0xF8) == 0xF0) return 4;
    return 1;
}

inline char vlToLower(char c) {
    return (c >= 'A' && c <= 'Z') ? static_cast<char>(c + ('a' - 'A')) : c;
}

inline uint8_t telexToneForKey(char lowerKey) {
    switch (lowerKey) {
        case 'f': return 1;
        case 's': return 2;
        case 'r': return 3;
        case 'x': return 4;
        case 'j': return 5;
        default: return 0;
    }
}

inline bool hasNonAscii(const char* utf8Str) {
    if (!utf8Str) return false;
    for (const unsigned char* p = reinterpret_cast<const unsigned char*>(utf8Str); *p; p++) {
        if (*p >= 0x80) return true;
    }
    return false;
}

uint8_t activeToneOfUtf8(const char* utf8Str) {
    if (!utf8Str) return 0;
    const char* p = utf8Str;
    while (*p) {
        size_t clen = utf8CharLen(static_cast<unsigned char>(*p));
        if (clen > 1) {
            for (const auto& entry : kVnUtf8Map) {
                if ((std::strlen(entry.lower_utf8) == clen && std::strncmp(p, entry.lower_utf8, clen) == 0) ||
                    (std::strlen(entry.upper_utf8) == clen && std::strncmp(p, entry.upper_utf8, clen) == 0)) {
                    if (entry.tone > 0) {
                        return entry.tone;
                    }
                }
            }
        }
        p += clen;
    }
    return 0;
}

void rawKeysForUtf8(const char* utf8Str, bool isVni, char* out, size_t outCap) {
    size_t len = 0;
    char toneChar = 0;
    const char* p = utf8Str;
    while (*p && len + 4 < outCap) {
        size_t clen = utf8CharLen(static_cast<unsigned char>(*p));
        if (clen == 1) {
            out[len++] = *p;
            p++;
            continue;
        }
        bool matched = false;
        for (const auto& entry : kVnUtf8Map) {
            bool isLower = (std::strlen(entry.lower_utf8) == clen && std::strncmp(p, entry.lower_utf8, clen) == 0);
            bool isUpper = !isLower && (std::strlen(entry.upper_utf8) == clen && std::strncmp(p, entry.upper_utf8, clen) == 0);
            if (isLower || isUpper) {
                char base = isUpper ? entry.upper_base : entry.lower_base;
                out[len++] = base;
                switch (entry.mod) {
                    case 1:
                        out[len++] = isVni ? '9' : (isUpper ? 'D' : 'd');
                        break;
                    case 2:
                        out[len++] = isVni ? '6' : entry.lower_base;
                        break;
                    case 3:
                        out[len++] = isVni ? '8' : 'w';
                        break;
                    case 4:
                        if ((base == 'o' || base == 'O') && len >= 3 &&
                            (out[len - 3] == 'u' || out[len - 3] == 'U') &&
                            (out[len - 2] == 'w' || out[len - 2] == '7')) {
                            out[len - 2] = base;
                            out[len - 1] = isVni ? '7' : 'w';
                        } else {
                            out[len++] = isVni ? '7' : 'w';
                        }
                        break;
                    default:
                        break;
                }
                if (entry.tone > 0 && entry.tone <= 5) {
                    toneChar = isVni ? "021345"[entry.tone] : "0fsrxj"[entry.tone];
                }
                matched = true;
                break;
            }
        }
        if (!matched) {
            for (size_t k = 0; k < clen && p[k] && len + 1 < outCap; k++) {
                out[len++] = p[k];
            }
        }
        p += clen;
    }
    if (toneChar != 0 && len + 1 < outCap) {
        out[len++] = toneChar;
    }
    out[len] = '\0';
}

void replayRawKeys(vielotus_session_t session, const char* rawKeys) {
    vielotus_reset_session(session);
    for (size_t i = 0; rawKeys[i] != '\0'; i++) {
        vielotus_feed_char(session, static_cast<uint32_t>(static_cast<unsigned char>(rawKeys[i])));
    }
}

} // namespace

VieLotusState::VieLotusState(VieLotusEngine* engine, InputContext* ic)
    : engine_(engine), ic_(ic) {
    session_ = vielotus_create_session();
    vielotus_set_input_method(session_, VIELOTUS_INPUT_TELEX);
    if (engine_) {
        applyConfig(engine_->config());
    } else {
        vielotus_set_grammar_profile(session_, VIELOTUS_GRAMMAR_SEN_FLEX);
        vielotus_set_smart_bilingual(session_, true);
        vielotus_set_modern_orthography(session_, true);
        vielotus_set_quick_telex(session_, false);
    }
}

VieLotusState::~VieLotusState() {
    if (session_) {
        vielotus_destroy_session(session_);
        session_ = nullptr;
    }
}

void VieLotusState::applyConfig(const VieLotusConfig& config) {
    if (!session_) {
        return;
    }
    vielotus_set_grammar_profile(
        session_,
        *config.grammarProfile == VieLotusGrammarMode::Classic
            ? VIELOTUS_GRAMMAR_CLASSIC
            : VIELOTUS_GRAMMAR_SEN_FLEX);
    vielotus_set_smart_bilingual(session_, *config.smartBilingual);
    vielotus_set_modern_orthography(session_, *config.modernOrthography);
    vielotus_set_quick_telex(session_, *config.quickTelex);
}

void VieLotusState::setInputMethod(int32_t method) {
    if (session_ && inputMethod_ != method) {
        if (vielotus_is_composing(session_)) {
            commitComposing(nullptr);
        }
        inputMethod_ = method;
        vielotus_set_input_method(session_,
                                  static_cast<vielotus_input_method_t>(method));
        reset();
    }
}

void VieLotusState::updatePreedit() {
    auto& inputPanel = ic_->inputPanel();
    inputPanel.reset();

    if (session_ && vielotus_is_composing(session_)) {
        const char* composing = vielotus_get_composing_text(session_);
        std::string preeditStr = composing ? composing : "";
        if (!preeditStr.empty()) {
            const bool useClientPreedit =
                ic_->capabilityFlags().test(CapabilityFlag::Preedit);
            TextFormatFlags formatFlags = TextFormatFlag::NoFlag;
            Text preedit(preeditStr, formatFlags);
            preedit.setCursor(static_cast<int>(preeditStr.size()));
            if (useClientPreedit) {
                inputPanel.setClientPreedit(preedit);
            } else {
                inputPanel.setPreedit(preedit);
            }
        }
    }
    ic_->updatePreedit();
    ic_->updateUserInterface(UserInterfaceComponent::InputPanel);
}

void VieLotusState::commitComposing(const char* trailingAscii) {
    std::string out;
    if (session_ && vielotus_is_composing(session_)) {
        if (trailingAscii && trailingAscii[0] != '\0' && trailingAscii[1] == '\0') {
            uint32_t cp = static_cast<uint32_t>(static_cast<unsigned char>(trailingAscii[0]));
            vielotus_feed_char(session_, cp);
        } else {
            vielotus_commit_word(session_);
        }
        const char* committed = vielotus_get_last_text(session_);
        if (committed && committed[0] != '\0') {
            out.append(committed);
        }
    }
    if (trailingAscii && trailingAscii[0] != '\0') {
        out.append(trailingAscii);
    }

    if (!out.empty()) {
        ic_->commitString(out);
    }

    resetWord();
}

void VieLotusState::resetWord() {
    if (session_) {
        vielotus_reset_session(session_);
    }
    ic_->inputPanel().reset();
    ic_->updatePreedit();
    ic_->updateUserInterface(UserInterfaceComponent::InputPanel);
}

void VieLotusState::reset() {
    resetWord();
    if (session_) {
        vielotus_append_context(session_, "");
    }
}

void VieLotusState::keyEvent(KeyEvent& keyEvent) {
    if (keyEvent.isRelease()) {
        return;
    }

    // Password / PIN / sensitive field protection: deterministically clear active composition and pass through raw keystrokes
    if (ic_ && ic_->capabilityFlags().test(CapabilityFlag::Password)) {
        if (vielotus_is_composing(session_)) {
            reset();
        }
        return;
    }

    auto sym = keyEvent.key().sym();
    auto states = keyEvent.key().states();

    // Ignore pure modifier presses (Shift, CapsLock, etc.) so uppercase typing works mid-word
    if (sym == FcitxKey_Shift_L || sym == FcitxKey_Shift_R ||
        sym == FcitxKey_Caps_Lock || sym == FcitxKey_Shift_Lock ||
        sym == FcitxKey_ISO_Level3_Shift) {
        return;
    }

    // Shortcuts with Ctrl / Alt / Super: commit current word first, then pass key through
    if (states.test(KeyState::Ctrl) || states.test(KeyState::Alt) ||
        states.test(KeyState::Super)) {
        if (vielotus_is_composing(session_)) {
            commitComposing(nullptr);
        }
        return;
    }

    // Navigation & action keys (Enter, Tab, Delete, Escape, Arrows, Home/End/PgUp/PgDn):
    // commit active word first so it never disappears, clear sentence context, then let the app handle the key
    if (sym == FcitxKey_Return || sym == FcitxKey_KP_Enter || sym == FcitxKey_Linefeed ||
        sym == FcitxKey_Tab || sym == FcitxKey_ISO_Left_Tab || sym == FcitxKey_KP_Tab ||
        sym == FcitxKey_Delete || sym == FcitxKey_KP_Delete ||
        sym == FcitxKey_Escape ||
        sym == '\r' || sym == '\n' || sym == '\t' || sym == 0x1b ||
        (sym >= FcitxKey_Home && sym <= FcitxKey_Insert) ||
        (sym >= FcitxKey_KP_Home && sym <= FcitxKey_KP_Delete)) {
        if (vielotus_is_composing(session_)) {
            commitComposing(nullptr);
        }
        if (session_) {
            vielotus_append_context(session_, "");
        }
        return;
    }

    // Handle BackSpace: whole-character UTF-8 deletion with canonical raw-key replay
    // so deleting inside "việt" -> "việ" -> "vi" -> "v" never reverts to raw ASCII "vieet".
    if (keyEvent.key().check(FcitxKey_BackSpace)) {
        if (vielotus_is_composing(session_)) {
            const char* composing = vielotus_get_composing_text(session_);
            if (!composing || composing[0] == '\0') {
                resetWord();
                keyEvent.filterAndAccept();
                return;
            }
            size_t len = std::strlen(composing);
            if (len >= 512) {
                resetWord();
                keyEvent.filterAndAccept();
                return;
            }
            char prefix[512];
            std::memcpy(prefix, composing, len + 1);
            size_t cut = len;
            while (cut > 0 && (static_cast<unsigned char>(prefix[cut - 1]) & 0xC0) == 0x80) {
                cut--;
            }
            if (cut > 0) {
                cut--;
            }
            prefix[cut] = '\0';
            if (cut == 0) {
                resetWord();
                keyEvent.filterAndAccept();
                return;
            }
            char rawKeys[1024];
            rawKeysForUtf8(prefix, inputMethod_ == VIELOTUS_INPUT_VNI, rawKeys, sizeof(rawKeys));
            replayRawKeys(session_, rawKeys);
            if (!vielotus_is_composing(session_)) {
                resetWord();
            } else {
                updatePreedit();
            }
            keyEvent.filterAndAccept();
            return;
        }
        vielotus_reset_session(session_);
        return;
    }

    // Handle printable ASCII characters (32..126)
    if (sym >= 32 && sym < 127) {
        const bool isAlpha =
            (sym >= 'a' && sym <= 'z') || (sym >= 'A' && sym <= 'Z');
        const bool isDigit = (sym >= '0' && sym <= '9');
        const bool isWordChar =
            isAlpha || (inputMethod_ == VIELOTUS_INPUT_VNI && isDigit &&
                        vielotus_is_composing(session_));

        if (!isWordChar) {
            if (vielotus_is_composing(session_)) {
                if (sym == '(' || sym == '[' || sym == '{') {
                    // Trigger code-delimiter raw restoration in core
                    vielotus_feed_char(session_, sym);
                    const char* committed = vielotus_get_last_text(session_);
                    std::string out = committed ? committed : "";
                    out.push_back(static_cast<char>(sym));
                    ic_->commitString(out);
                    resetWord();
                    keyEvent.filterAndAccept();
                    return;
                }
                char trail[2] = {static_cast<char>(sym), '\0'};
                commitComposing(trail);
                keyEvent.filterAndAccept();
                return;
            } else {
                // Not composing: reset post-commit caret state and pass key through
                vielotus_feed_char(session_, sym);
                return;
            }
        }

        // Auto-flush preedit before internal 64-token buffer limit (e.g. holding a key for 80+ characters)
        if (vielotus_is_composing(session_)) {
            const char* rawCheck = vielotus_get_raw_text(session_);
            const char* compCheck = vielotus_get_composing_text(session_);
            if ((rawCheck && std::strlen(rawCheck) >= 48) ||
                (compCheck && std::strlen(compCheck) >= 48)) {
                commitComposing(nullptr);
            }
        }

        if (inputMethod_ != VIELOTUS_INPUT_VNI && vielotus_is_composing(session_)) {
            char lowerKey = vlToLower(static_cast<char>(sym));
            uint8_t keyTone = telexToneForKey(lowerKey);
            const char* rawBefore = vielotus_get_raw_text(session_);
            const char* compBefore = vielotus_get_composing_text(session_);
            if (keyTone > 0 && rawBefore && compBefore && hasNonAscii(compBefore)) {
                size_t rlen = std::strlen(rawBefore);
                size_t clen = std::strlen(compBefore);
                uint8_t activeTone = activeToneOfUtf8(compBefore);
                if (activeTone == keyTone && rlen > 0 && vlToLower(rawBefore[rlen - 1]) != lowerKey) {
                    char canonRaw[1024];
                    rawKeysForUtf8(compBefore, false, canonRaw, sizeof(canonRaw));
                    replayRawKeys(session_, canonRaw);
                    updatePreedit();
                    keyEvent.filterAndAccept();
                    return;
                }
                if ((keyTone == 2 || keyTone == 5) && activeTone == 0 && rlen >= 3 && clen >= 3 && rlen < 512) {
                    char lastR = vlToLower(rawBefore[rlen - 1]);
                    char prevC = vlToLower(compBefore[clen - 2]);
                    if ((lastR == 'f' || lastR == 'r' || lastR == 'x') &&
                        vlToLower(compBefore[clen - 1]) == lastR &&
                        (prevC == 't' || prevC == 'c' || prevC == 'p' || prevC == 'h')) {
                        char fixedRaw[512];
                        std::memcpy(fixedRaw, rawBefore, rlen);
                        fixedRaw[rlen - 1] = static_cast<char>(sym);
                        fixedRaw[rlen] = '\0';
                        replayRawKeys(session_, fixedRaw);
                        updatePreedit();
                        keyEvent.filterAndAccept();
                        return;
                    }
                }
            }
        }

        // Feed word character (letter or VNI tone digit)
        int32_t action = vielotus_feed_char(session_, sym);
        if (inputMethod_ != VIELOTUS_INPUT_VNI && vielotus_is_composing(session_)) {
            char lowerKey = vlToLower(static_cast<char>(sym));
            if (lowerKey == 'a' || lowerKey == 'e' || lowerKey == 'o') {
                const char* rawAfter = vielotus_get_raw_text(session_);
                const char* compAfter = vielotus_get_composing_text(session_);
                if (rawAfter && compAfter) {
                    size_t rlen = std::strlen(rawAfter);
                    size_t clen = std::strlen(compAfter);
                    if (rlen >= 3 && rlen < 512 && clen >= 2 &&
                        vlToLower(rawAfter[rlen - 1]) == lowerKey &&
                        vlToLower(rawAfter[rlen - 3]) == lowerKey &&
                        vlToLower(compAfter[clen - 1]) == lowerKey) {
                        uint8_t midTone = telexToneForKey(vlToLower(rawAfter[rlen - 2]));
                        bool allowSwap = (midTone == 5) ||
                            (midTone > 0 && lowerKey == 'e' && rlen >= 4 &&
                             (vlToLower(rawAfter[rlen - 4]) == 'i' || vlToLower(rawAfter[rlen - 4]) == 'y') &&
                             vlToLower(rawAfter[0]) != 'p') ||
                            (midTone > 0 && lowerKey == 'o' && rlen >= 4 &&
                             vlToLower(rawAfter[rlen - 4]) == 'u');
                        if (allowSwap && activeToneOfUtf8(compAfter) == midTone) {
                            char swappedRaw[512];
                            std::memcpy(swappedRaw, rawAfter, rlen + 1);
                            char tmp = swappedRaw[rlen - 2];
                            swappedRaw[rlen - 2] = swappedRaw[rlen - 1];
                            swappedRaw[rlen - 1] = tmp;
                            replayRawKeys(session_, swappedRaw);
                        }
                    }
                }
            }
        }
        if (action == VIELOTUS_ACTION_COMMIT) {
            const char* committed = vielotus_get_last_text(session_);
            std::string out = committed ? committed : "";
            if (!out.empty()) {
                ic_->commitString(out);
            }
            resetWord();
            keyEvent.filterAndAccept();
            return;
        } else if (vielotus_is_composing(session_) ||
                   action == VIELOTUS_ACTION_REPLACE ||
                   action == VIELOTUS_ACTION_CONSUMED) {
            updatePreedit();
            keyEvent.filterAndAccept();
            return;
        }
        return;
    }

    // Any other non-ASCII or function key: commit active composition before passing through
    if (vielotus_is_composing(session_)) {
        commitComposing(nullptr);
    }
}

// ============================================================================
// VieLotusEngine Implementation
// ============================================================================

VieLotusEngine::VieLotusEngine(Instance* instance)
    : instance_(instance),
      factory_([this](InputContext& ic) { return new VieLotusState(this, &ic); }) {
    instance_->inputContextManager().registerProperty("vielotusState", &factory_);

    auto& uiManager = instance_->userInterfaceManager();
    settingsAction_ = std::make_unique<SimpleAction>();
    settingsAction_->setIcon("preferences-system");
    settingsAction_->setShortText(_("Bảng cài đặt Sen Việt (Settings)..."));
    settingsAction_->setLongText(_("Mở bảng điều khiển và cài đặt bộ gõ Sen Việt"));
    connections_.emplace_back(settingsAction_->connect<SimpleAction::Activated>(
        [](InputContext*) {
            if (std::filesystem::exists("/usr/bin/vielotus-settings")) {
                startProcess({"/usr/bin/vielotus-settings"});
            } else {
                startProcess({"fcitx5-configtool"});
            }
        }));
    uiManager.registerAction("vielotus-settings", settingsAction_.get());

    reloadConfig();
}

VieLotusEngine::~VieLotusEngine() {}

static std::string resolveUserEnvConfigPath() {
    const char* xdg = std::getenv("XDG_CONFIG_HOME");
    if (xdg && xdg[0] != '\0') {
        return std::string(xdg) + "/vielotus/config.env";
    }
    const char* home = std::getenv("HOME");
    if (home && home[0] != '\0') {
        return std::string(home) + "/.config/vielotus/config.env";
    }
    return {};
}

void VieLotusEngine::setConfig(const RawConfig& config) {
    config_.load(config, true);
    safeSaveAsIni(config_, "conf/vielotus.conf");
    saveUserEnvConfig();
    applyConfigToAllContexts();
}

void VieLotusEngine::loadUserEnvConfig() {
    std::string envPath = resolveUserEnvConfigPath();
    if (envPath.empty()) {
        return;
    }
    std::ifstream in(envPath);
    if (!in.is_open()) {
        return;
    }
    std::string line;
    while (std::getline(in, line)) {
        if (line.rfind("INPUT_METHOD=", 0) == 0) {
            hasEnvInputMethod_ = true;
            envInputMethod_ =
                (line.find("vni") != std::string::npos ||
                 line.find("VNI") != std::string::npos)
                    ? VIELOTUS_INPUT_VNI
                    : VIELOTUS_INPUT_TELEX;
        } else if (line.rfind("GRAMMAR_PROFILE=", 0) == 0) {
            if (line.find("classic") != std::string::npos) {
                config_.grammarProfile.setValue(VieLotusGrammarMode::Classic);
            } else {
                config_.grammarProfile.setValue(VieLotusGrammarMode::SenFlex);
            }
        } else if (line.rfind("SMART_BILINGUAL=", 0) == 0) {
            config_.smartBilingual.setValue(line.find("false") == std::string::npos &&
                                            line.find("0") == std::string::npos);
        } else if (line.rfind("MODERN_ORTHOGRAPHY=", 0) == 0) {
            config_.modernOrthography.setValue(line.find("false") == std::string::npos &&
                                               line.find("0") == std::string::npos);
        } else if (line.rfind("QUICK_TELEX=", 0) == 0) {
            config_.quickTelex.setValue(line.find("true") != std::string::npos ||
                                        line.find("1") != std::string::npos);
        }
    }
}

void VieLotusEngine::saveUserEnvConfig() const {
    std::string envPath = resolveUserEnvConfigPath();
    if (envPath.empty()) {
        return;
    }
    std::string inputMethod = "telex";
    {
        std::ifstream in(envPath);
        std::string line;
        while (std::getline(in, line)) {
            if (line.rfind("INPUT_METHOD=", 0) == 0 &&
                line.find("vni") != std::string::npos) {
                inputMethod = "vni";
            }
        }
    }
    std::error_code ec;
    std::filesystem::create_directories(
        std::filesystem::path(envPath).parent_path(), ec);
    std::ofstream out(envPath, std::ios::trunc);
    if (!out.is_open()) {
        return;
    }
    out << "INPUT_METHOD=\"" << inputMethod << "\"\n"
        << "GRAMMAR_PROFILE=\""
        << (*config_.grammarProfile == VieLotusGrammarMode::Classic ? "classic"
                                                                    : "sen_flex")
        << "\"\n"
        << "SMART_BILINGUAL=\"" << (*config_.smartBilingual ? "true" : "false")
        << "\"\n"
        << "MODERN_ORTHOGRAPHY=\""
        << (*config_.modernOrthography ? "true" : "false") << "\"\n"
        << "QUICK_TELEX=\"" << (*config_.quickTelex ? "true" : "false")
        << "\"\n";
}

void VieLotusEngine::applyConfigToAllContexts() {
    instance_->inputContextManager().foreach([this](InputContext* ic) {
        auto* state = ic->propertyFor(&factory_);
        if (state) {
            state->applyConfig(config_);
        }
        return true;
    });
}

void VieLotusEngine::reloadConfig() {
    readAsIni(config_, "conf/vielotus.conf");
    loadUserEnvConfig();
    applyConfigToAllContexts();
}

void VieLotusEngine::activate(const InputMethodEntry& entry,
                              InputContextEvent& event) {
    FCITX_UNUSED(entry);
    loadUserEnvConfig();
    auto* ic = event.inputContext();
    auto& statusArea = ic->statusArea();
    statusArea.addAction(StatusGroup::InputMethod, settingsAction_.get());
    auto* state = ic->propertyFor(&factory_);
    if (state) {
        state->applyConfig(config_);
        if (state->session()) {
            vielotus_append_context(state->session(), "");
        }
    }
}

void VieLotusEngine::deactivate(const InputMethodEntry& entry,
                                InputContextEvent& event) {
    auto* state = event.inputContext()->propertyFor(&factory_);
    if (state) {
        state->commitComposing(nullptr);
    }
    reset(entry, event);
}

void VieLotusEngine::keyEvent(const InputMethodEntry& entry,
                              KeyEvent& keyEvent) {
    auto* state = keyEvent.inputContext()->propertyFor(&factory_);
    if (state) {
        int32_t method = (entry.uniqueName() == "vielotus-vni")
            ? VIELOTUS_INPUT_VNI
            : (hasEnvInputMethod_ ? envInputMethod_ : VIELOTUS_INPUT_TELEX);
        state->setInputMethod(method);
        state->keyEvent(keyEvent);
    }
}

void VieLotusEngine::reset(const InputMethodEntry& entry,
                           InputContextEvent& event) {
    FCITX_UNUSED(entry);
    auto* state = event.inputContext()->propertyFor(&factory_);
    if (state) {
        state->reset();
    }
}

AddonInstance* VieLotusEngineFactory::create(AddonManager* manager) {
    return new VieLotusEngine(manager->instance());
}

} // namespace fcitx

FCITX_ADDON_FACTORY(fcitx::VieLotusEngineFactory);
