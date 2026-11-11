#include "vielotus_engine.h"
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <fcitx-utils/capabilityflags.h>
#include <fcitx-utils/keysym.h>
#include <fcitx-utils/misc.h>
#include <fcitx-utils/textformatflags.h>
#include <fcitx-utils/utf8.h>
#include <fcitx/addonmanager.h>
#include <fcitx/inputcontextmanager.h>
#include <fcitx/inputpanel.h>
#include <fcitx/statusarea.h>
#include <fcitx/userinterfacemanager.h>

namespace fcitx {

namespace {

constexpr const char* kSystemTypingModesPath =
    "/usr/share/vielotus/VietLotusIM_VieLotusCore.resources/typing-modes.yml";

void replayRawKeys(vielotus_session_t session, const char* rawKeys) {
    vielotus_reset_session(session);
    for (size_t i = 0; rawKeys[i] != '\0'; i++) {
        vielotus_feed_char(session, static_cast<uint32_t>(static_cast<unsigned char>(rawKeys[i])));
    }
}

bool isModifierKeyForMethod(bool isVni, uint32_t sym) {
    if (isVni) {
        return sym >= '0' && sym <= '9';
    }
    char lower = vl_ascii_tolower(static_cast<char>(sym));
    return lower == 's' || lower == 'f' || lower == 'r' || lower == 'x' || lower == 'j' ||
           lower == 'w' || lower == 'a' || lower == 'e' || lower == 'o' || lower == 'd' || lower == 'z';
}

uint32_t decodeUtf8At(const std::string& s, size_t pos, size_t* outLen) {
    if (pos >= s.size()) {
        if (outLen) *outLen = 0;
        return 0;
    }
    const unsigned char b0 = static_cast<unsigned char>(s[pos]);
    if (b0 < 0x80) {
        if (outLen) *outLen = 1;
        return b0;
    }
    if ((b0 & 0xE0) == 0xC0 && pos + 1 < s.size()) {
        if (outLen) *outLen = 2;
        return ((static_cast<uint32_t>(b0 & 0x1F) << 6) |
                static_cast<uint32_t>(static_cast<unsigned char>(s[pos + 1]) & 0x3F));
    }
    if ((b0 & 0xF0) == 0xE0 && pos + 2 < s.size()) {
        if (outLen) *outLen = 3;
        return ((static_cast<uint32_t>(b0 & 0x0F) << 12) |
                (static_cast<uint32_t>(static_cast<unsigned char>(s[pos + 1]) & 0x3F) << 6) |
                static_cast<uint32_t>(static_cast<unsigned char>(s[pos + 2]) & 0x3F));
    }
    if ((b0 & 0xF8) == 0xF0 && pos + 3 < s.size()) {
        if (outLen) *outLen = 4;
        return ((static_cast<uint32_t>(b0 & 0x07) << 18) |
                (static_cast<uint32_t>(static_cast<unsigned char>(s[pos + 1]) & 0x3F) << 12) |
                (static_cast<uint32_t>(static_cast<unsigned char>(s[pos + 2]) & 0x3F) << 6) |
                static_cast<uint32_t>(static_cast<unsigned char>(s[pos + 3]) & 0x3F));
    }
    if (outLen) *outLen = 1;
    return b0;
}

size_t prevUtf8Pos(const std::string& s, size_t pos) {
    if (pos == 0) return 0;
    size_t p = pos - 1;
    while (p > 0 && (static_cast<unsigned char>(s[p]) & 0xC0) == 0x80) {
        --p;
    }
    return p;
}

bool isWordLetterCodepoint(uint32_t cp) {
    if ((cp >= 'a' && cp <= 'z') || (cp >= 'A' && cp <= 'Z')) return true;
    if (cp >= 0x00C0 && cp <= 0x024F && cp != 0x00D7 && cp != 0x00F7) return true;
    if (cp >= 0x1E00 && cp <= 0x1EFF) return true;
    return false;
}

} // namespace

VieLotusState::VieLotusState(VieLotusEngine* engine, InputContext* ic)
    : engine_(engine), ic_(ic) {
    vl_dev_code_reset(&devCodeState_);
    session_ = vielotus_create_session();
    vielotus_set_input_method(session_, VIELOTUS_INPUT_TELEX);
    if (engine_) {
        applyConfig(engine_->config());
    } else {
        vielotus_set_grammar_profile(session_, VIELOTUS_GRAMMAR_CLASSIC);
        vielotus_set_smart_bilingual(session_, true);
        vielotus_set_modern_orthography(session_, true);
        vielotus_set_quick_telex(session_, false);
        vielotus_set_relaxed_coda(session_, false);
        vielotus_set_macro_enabled(session_, false);
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
    vielotus_set_relaxed_coda(session_, *config.relaxedCoda);
    vielotus_set_macro_enabled(session_, *config.macroEnabled);
    if (!*config.developerMode) {
        vl_dev_code_reset(&devCodeState_);
    }
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

    if (session_ && vielotus_is_composing(session_)) {
        const char* composing = vielotus_get_composing_text(session_);
        std::string preeditStr = composing ? composing : "";
        if (!preeditStr.empty()) {
            preeditVisible_ = true;
            inputPanel.reset();
            const bool useClientPreedit =
                ic_->capabilityFlags().test(CapabilityFlag::Preedit);

            bool showUnderline = engine_ ? *engine_->config().preeditUnderline : false;
            if (engine_) {
                const vl_presentation_mode_t pmode = engine_->resolvePresentationMode(ic_);
                if (pmode == VL_PRESENTATION_MARKED_TEXT) {
                    showUnderline = true;
                } else if (pmode == VL_PRESENTATION_DIRECT_REPLACEMENT) {
                    showUnderline = false;
                }
            }
            TextFormatFlags formatFlags =
                showUnderline ? TextFormatFlag::Underline : TextFormatFlag::NoFlag;
            Text preedit(preeditStr, formatFlags);
            preedit.setCursor(static_cast<int>(preeditStr.size()));
            if (useClientPreedit) {
                inputPanel.setClientPreedit(preedit);
            } else {
                inputPanel.setPreedit(preedit);
            }
            ic_->updatePreedit();
            ic_->updateUserInterface(UserInterfaceComponent::InputPanel);
            return;
        }
    }
    if (preeditVisible_) {
        preeditVisible_ = false;
        inputPanel.reset();
        ic_->updatePreedit();
        ic_->updateUserInterface(UserInterfaceComponent::InputPanel);
    }
}

void VieLotusState::commitComposing(const char* trailingAscii) {
    size_t compCpBefore = 0;
    int32_t surrDel = 0;
    if (session_ && vielotus_is_composing(session_)) {
        compCpBefore = vl_utf8_codepoint_count(vielotus_get_composing_text(session_));
    }
    std::string out;
    if (session_ && vielotus_is_composing(session_)) {
        if (trailingAscii && trailingAscii[0] != '\0' && trailingAscii[1] == '\0') {
            uint32_t cp = static_cast<uint32_t>(static_cast<unsigned char>(trailingAscii[0]));
            vielotus_feed_char(session_, cp);
        } else {
            vielotus_commit_word(session_);
        }
        int32_t totalBs = vielotus_get_last_backspaces(session_);
        const bool isOverride = vielotus_get_last_is_override(session_);
        /* Only delete surrounding text when totalBs > compCpBefore from a multi-word collocation
         * (where committed contains a space). Single-word macro expansions keep totalBs == compCpBefore. */
        if (totalBs > static_cast<int32_t>(compCpBefore) && compCpBefore > 0) {
            surrDel = totalBs - static_cast<int32_t>(compCpBefore);
        }
        (void)isOverride;
        const char* committed = vielotus_get_last_text(session_);
        if (committed && committed[0] != '\0') {
            const bool canDeleteSurrounding =
                ic_ && ic_->capabilityFlags().test(CapabilityFlag::SurroundingText);
            if (surrDel > 0 && !canDeleteSurrounding) {
                committed = vl_utf8_after_first_space(committed);
            }
            if (committed && committed[0] != '\0') {
                out.append(committed);
            }
        }
    }
    if (trailingAscii && trailingAscii[0] != '\0') {
        out.append(trailingAscii);
    }

    if (!out.empty()) {
        if (surrDel > 0 && ic_ && ic_->capabilityFlags().test(CapabilityFlag::SurroundingText)) {
            if (preeditVisible_) {
                preeditVisible_ = false;
                ic_->inputPanel().reset();
                ic_->updatePreedit();
                ic_->updateUserInterface(UserInterfaceComponent::InputPanel);
            }
            ic_->deleteSurroundingText(-surrDel, static_cast<unsigned int>(surrDel));
        }
        ic_->commitString(out);
    }

    replayedAfterBackspace_ = false;
    if (session_ && vielotus_is_composing(session_)) {
        vielotus_reset_session(session_);
    }
    if (preeditVisible_) {
        preeditVisible_ = false;
        ic_->inputPanel().reset();
        ic_->updatePreedit();
        ic_->updateUserInterface(UserInterfaceComponent::InputPanel);
    }
}

void VieLotusState::resetWord() {
    replayedAfterBackspace_ = false;
    if (session_) {
        vielotus_reset_session(session_);
    }
    if (preeditVisible_) {
        preeditVisible_ = false;
        ic_->inputPanel().reset();
        ic_->updatePreedit();
        ic_->updateUserInterface(UserInterfaceComponent::InputPanel);
    }
}

void VieLotusState::reset() {
    vl_dev_code_reset(&devCodeState_);
    resetWord();
    if (session_) {
        vielotus_append_context(session_, "");
    }
}

void VieLotusState::syncArmedWordFromText(
    const std::string& textStr,
    size_t cursorCp,
    size_t anchorCp
) {
    (void)anchorCp;
    if (!session_ || !ic_ || ic_->capabilityFlags().test(CapabilityFlag::Password)) {
        return;
    }
    if (textStr.empty() || cursorCp == 0) {
        vielotus_append_context(session_, "");
        return;
    }
    const size_t bytePos = fcitx::utf8::ncharByteLength(textStr.begin(), cursorCp);
    if (bytePos > textStr.size()) {
        return;
    }
    size_t winStart = 0;
    if (bytePos > 256) {
        winStart = bytePos - 256;
        while (winStart < bytePos &&
               (static_cast<unsigned char>(textStr[winStart]) & 0xC0) == 0x80) {
            ++winStart;
        }
    }
    std::string prefix = textStr.substr(winStart, bytePos - winStart);
    vielotus_sync_armed_word(session_, prefix.c_str());
}

bool VieLotusState::prepareWordStartFromSurrounding(uint32_t sym, uint64_t t0Us) {
    (void)t0Us;
    if (!session_ || !ic_ ||
        ic_->capabilityFlags().test(CapabilityFlag::Password) ||
        !ic_->capabilityFlags().test(CapabilityFlag::SurroundingText) ||
        !ic_->surroundingText().isValid()) {
        return false;
    }

    const std::string& textStr = ic_->surroundingText().text();
    if (textStr.empty()) {
        return false;
    }
    const size_t totalChars = vl_utf8_codepoint_count(textStr.c_str());
    size_t cursorPos = ic_->surroundingText().cursor();
    size_t anchorPos = ic_->surroundingText().anchor();
    if (cursorPos > totalChars) cursorPos = totalChars;
    if (anchorPos > totalChars) anchorPos = totalChars;

    // Case 1: Active selection [selStart .. selEnd) — delete immediately before preedit starts
    if (cursorPos != anchorPos) {
        const size_t selStart = (cursorPos < anchorPos) ? cursorPos : anchorPos;
        const size_t selEnd = (cursorPos > anchorPos) ? cursorPos : anchorPos;
        const unsigned int selLen = static_cast<unsigned int>(selEnd - selStart);
        const int relOffset = static_cast<int>(selStart) - static_cast<int>(cursorPos);

        const size_t startByte = fcitx::utf8::ncharByteLength(textStr.begin(), selStart);
        const size_t endByte = fcitx::utf8::ncharByteLength(textStr.begin(), selEnd);
        bool adjWordChar = false;
        if (startByte > 0 && startByte <= textStr.size()) {
            size_t prevB = prevUtf8Pos(textStr, startByte);
            if (isWordLetterCodepoint(decodeUtf8At(textStr, prevB, nullptr))) {
                adjWordChar = true;
            }
        }
        if (endByte < textStr.size()) {
            if (isWordLetterCodepoint(decodeUtf8At(textStr, endByte, nullptr))) {
                adjWordChar = true;
            }
        }
        ic_->deleteSurroundingText(relOffset, selLen);
        syncArmedWordFromText(textStr, selStart, selStart);
        if (adjWordChar || vl_has_non_ascii(textStr.c_str())) {
            vielotus_append_context(session_, "ự");
        }
        return false;
    }

    // Sync preceding sentence context once at the start of a word
    syncArmedWordFromText(textStr, cursorPos, anchorPos);

    // Case 2: No selection — inspect contiguous word letters around cursorPos
    const size_t cursorByte = fcitx::utf8::ncharByteLength(textStr.begin(), cursorPos);
    if (cursorByte > textStr.size()) {
        return false;
    }
    size_t wordStartByte = cursorByte;
    size_t leftChars = 0;
    while (wordStartByte > 0 && leftChars < 20) {
        const size_t prevB = prevUtf8Pos(textStr, wordStartByte);
        if (!isWordLetterCodepoint(decodeUtf8At(textStr, prevB, nullptr))) {
            break;
        }
        wordStartByte = prevB;
        ++leftChars;
    }
    size_t wordEndByte = cursorByte;
    size_t rightChars = 0;
    while (wordEndByte < textStr.size() && rightChars < 20) {
        size_t clen = 0;
        const uint32_t cp = decodeUtf8At(textStr, wordEndByte, &clen);
        if (clen == 0 || !isWordLetterCodepoint(cp)) {
            break;
        }
        wordEndByte += clen;
        ++rightChars;
    }

    const size_t totalWordCp = leftChars + rightChars;
    const size_t wordBytes = wordEndByte - wordStartByte;
    if (totalWordCp >= 1 && totalWordCp <= 15 && wordBytes > 0 && wordBytes < 128) {
        std::string fullWord = textStr.substr(wordStartByte, wordBytes);
        const bool isVni = (inputMethod_ == VIELOTUS_INPUT_VNI);
        if (!isModifierKeyForMethod(isVni, sym)) {
            if (vl_has_non_ascii(fullWord.c_str()) || vl_has_non_ascii(textStr.c_str())) {
                vielotus_append_context(session_, "ự");
            }
            return false;
        }

        char canonRaw[256] = {0};
        vl_raw_keys_for_utf8(fullWord.c_str(), isVni, canonRaw, sizeof(canonRaw));
        if (canonRaw[0] != '\0') {
            vielotus_reset_session(session_);
            if (vl_has_non_ascii(fullWord.c_str()) || vl_has_non_ascii(textStr.c_str())) {
                vielotus_append_context(session_, "ự");
            }
            for (size_t i = 0; canonRaw[i] != '\0'; i++) {
                vielotus_feed_char(session_, static_cast<uint32_t>(static_cast<unsigned char>(canonRaw[i])));
            }
            const char* reconstructed = vielotus_get_composing_text(session_);
            if (vielotus_is_composing(session_) &&
                reconstructed && fullWord == reconstructed) {
                vielotus_feed_char(session_, sym);
                const char* afterComp = vielotus_get_composing_text(session_);
                if (vielotus_is_composing(session_) &&
                    afterComp &&
                    vl_utf8_codepoint_count(afterComp) == totalWordCp &&
                    fullWord != afterComp &&
                    vl_has_non_ascii(afterComp)) {
                    ic_->deleteSurroundingText(-static_cast<int>(leftChars),
                                               static_cast<unsigned int>(totalWordCp));
                    updatePreedit();
                    return true;
                }
            }
            vielotus_reset_session(session_);
            syncArmedWordFromText(textStr, cursorPos, anchorPos);
            if (vl_has_non_ascii(fullWord.c_str()) || vl_has_non_ascii(textStr.c_str())) {
                vielotus_append_context(session_, "ự");
            }
        }
    }
    return false;
}

void VieLotusState::keyEvent(KeyEvent& keyEvent) {
    if (keyEvent.isRelease()) {
        return;
    }

    // Per-app passthrough rule from typing-modes.yml (e.g. Remote Desktop / VM clients)
    if (engine_ && engine_->resolvePresentationMode(ic_) == VL_PRESENTATION_PASSTHROUGH) {
        if (vielotus_is_composing(session_)) {
            reset();
        }
        return;
    }

    // Password / PIN / sensitive field protection
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

    // Navigation & action keys (Enter, Tab, Delete, Escape, Arrows, Home/End/PgUp/PgDn)
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
        if (sym == FcitxKey_Escape || sym == 0x1b) {
            vl_dev_code_reset(&devCodeState_);
        } else if (sym == FcitxKey_Return || sym == FcitxKey_KP_Enter ||
                   sym == FcitxKey_Linefeed || sym == '\r' || sym == '\n') {
            vl_dev_code_on_newline(&devCodeState_);
        }
        if (session_) {
            vielotus_append_context(session_, "");
        }
        return;
    }

    // Developer Mode (`inline code` & ```fenced code``` bypass)
    const bool devModeOn = engine_ && *engine_->config().developerMode;
    if (devModeOn) {
        if (sym == '`') {
            if (vielotus_is_composing(session_)) {
                char trail[2] = {'`', '\0'};
                commitComposing(trail);
                vl_dev_code_on_backtick(&devCodeState_);
                keyEvent.filterAndAccept();
                return;
            }
            vl_dev_code_on_backtick(&devCodeState_);
            vielotus_feed_char(session_, '`');
            return;
        }
        if (vl_dev_code_is_bypassing(&devCodeState_)) {
            vl_dev_code_on_non_backtick(&devCodeState_);
            return;
        }
    }

    // Handle BackSpace
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
            const size_t beforeCp = vl_utf8_codepoint_count(composing);
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

            vielotus_feed_backspace(session_);
            if (!vielotus_is_composing(session_)) {
                resetWord();
                keyEvent.filterAndAccept();
                return;
            }
            const char* after = vielotus_get_composing_text(session_);
            if (after && after[0] != '\0' && vl_utf8_codepoint_count(after) < beforeCp) {
                replayedAfterBackspace_ = false;
                updatePreedit();
                keyEvent.filterAndAccept();
                return;
            }

            if (cut == 0) {
                resetWord();
                keyEvent.filterAndAccept();
                return;
            }
            char rawKeys[1024];
            vl_raw_keys_for_utf8(prefix, inputMethod_ == VIELOTUS_INPUT_VNI, rawKeys, sizeof(rawKeys));
            replayRawKeys(session_, rawKeys);
            replayedAfterBackspace_ = true;
            if (!vielotus_is_composing(session_)) {
                resetWord();
            } else {
                updatePreedit();
            }
            keyEvent.filterAndAccept();
            return;
        }
        replayedAfterBackspace_ = false;
        vielotus_reset_session(session_);
        return;
    }

    // Handle printable ASCII characters (32..126)
    if (sym >= 32 && sym < 127) {
        uint64_t t0Us = 0;
        const bool isAlpha =
            (sym >= 'a' && sym <= 'z') || (sym >= 'A' && sym <= 'Z');
        const bool isDigit = (sym >= '0' && sym <= '9');
        const bool isWordChar =
            isAlpha || (inputMethod_ == VIELOTUS_INPUT_VNI && isDigit &&
                        vielotus_is_composing(session_));

        if (!isWordChar) {
            if (vielotus_is_composing(session_)) {
                if (sym == '(' || sym == '[' || sym == '{') {
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
                vielotus_feed_char(session_, sym);
                return;
            }
        }

        // Auto-flush preedit before internal 64-token buffer limit, or prepare word from surrounding text
        if (vielotus_is_composing(session_)) {
            const char* rawCheck = vielotus_get_raw_text(session_);
            const char* compCheck = vielotus_get_composing_text(session_);
            if ((rawCheck && std::strlen(rawCheck) >= 48) ||
                (compCheck && std::strlen(compCheck) >= 48)) {
                commitComposing(nullptr);
            }
        } else {
            if (prepareWordStartFromSurrounding(sym, t0Us)) {
                keyEvent.filterAndAccept();
                return;
            }
        }

        if (inputMethod_ != VIELOTUS_INPUT_VNI && vielotus_is_composing(session_)) {
            char lowerKey = vl_ascii_tolower(static_cast<char>(sym));
            uint8_t keyTone = vl_telex_tone_for_key(lowerKey);
            const char* rawBefore = vielotus_get_raw_text(session_);
            const char* compBefore = vielotus_get_composing_text(session_);
            if (keyTone > 0 && rawBefore && compBefore && vl_has_non_ascii(compBefore)) {
                size_t rlen = std::strlen(rawBefore);
                size_t clen = std::strlen(compBefore);
                uint8_t activeTone = vl_active_tone_of_utf8(compBefore);
                if (replayedAfterBackspace_ &&
                    activeTone == keyTone && rlen > 0 && vl_ascii_tolower(rawBefore[rlen - 1]) != lowerKey) {
                    char canonRaw[1024];
                    vl_raw_keys_for_utf8(compBefore, false, canonRaw, sizeof(canonRaw));
                    replayRawKeys(session_, canonRaw);
                    updatePreedit();
                    keyEvent.filterAndAccept();
                    return;
                }
                if ((keyTone == 2 || keyTone == 5) && activeTone == 0 && rlen >= 3 && clen >= 3 && rlen < 512) {
                    char lastR = vl_ascii_tolower(rawBefore[rlen - 1]);
                    char prevC = vl_ascii_tolower(compBefore[clen - 2]);
                    if ((lastR == 'f' || lastR == 'r' || lastR == 'x') &&
                        vl_ascii_tolower(compBefore[clen - 1]) == lastR &&
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
            char lowerKey = vl_ascii_tolower(static_cast<char>(sym));
            if (lowerKey == 'a' || lowerKey == 'e' || lowerKey == 'o') {
                const char* rawAfter = vielotus_get_raw_text(session_);
                const char* compAfter = vielotus_get_composing_text(session_);
                if (rawAfter && compAfter) {
                    size_t rlen = std::strlen(rawAfter);
                    size_t clen = std::strlen(compAfter);
                    if (rlen >= 3 && rlen < 512 && clen >= 2 &&
                        vl_ascii_tolower(rawAfter[rlen - 1]) == lowerKey &&
                        vl_ascii_tolower(rawAfter[rlen - 3]) == lowerKey &&
                        vl_ascii_tolower(compAfter[clen - 1]) == lowerKey) {
                        uint8_t midTone = vl_telex_tone_for_key(vl_ascii_tolower(rawAfter[rlen - 2]));
                        bool allowSwap = (midTone == 5) ||
                            (midTone > 0 && lowerKey == 'e' && rlen >= 4 &&
                             (vl_ascii_tolower(rawAfter[rlen - 4]) == 'i' || vl_ascii_tolower(rawAfter[rlen - 4]) == 'y') &&
                             vl_ascii_tolower(rawAfter[0]) != 'p') ||
                            (midTone > 0 && lowerKey == 'o' && rlen >= 4 &&
                             vl_ascii_tolower(rawAfter[rlen - 4]) == 'u');
                        if (allowSwap && vl_active_tone_of_utf8(compAfter) == midTone) {
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
            replayedAfterBackspace_ = false;
            if (vielotus_is_composing(session_)) {
                vielotus_reset_session(session_);
            }
            if (preeditVisible_) {
                preeditVisible_ = false;
                ic_->inputPanel().reset();
                ic_->updatePreedit();
                ic_->updateUserInterface(UserInterfaceComponent::InputPanel);
            }
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

    // Normalize non-ASCII XKB `vn` / VM-forwarded Unicode keysyms & combining marks (U+0309 etc.) to NFC
    if (sym >= 128) {
        uint32_t uniCp = Key::keySymToUnicode(sym);
        char mappedSeq[16];
        if (vl_keysym_to_raw_seq(sym, uniCp, inputMethod_ == VIELOTUS_INPUT_VNI, mappedSeq, sizeof(mappedSeq))) {
            bool anyAccepted = false;
            for (size_t i = 0; mappedSeq[i] != '\0'; i++) {
                Key subKey(static_cast<KeySym>(static_cast<unsigned char>(mappedSeq[i])));
                KeyEvent subEvent(ic_, subKey, false);
                this->keyEvent(subEvent);
                if (subEvent.filtered()) {
                    anyAccepted = true;
                }
            }
            if (anyAccepted) {
                keyEvent.filterAndAccept();
                return;
            }
        }
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
    vl_presentation_rules_init(&presentationRules_);
    ensureConfigPaths();
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

void VieLotusEngine::ensureConfigPaths() {
    if (!cachedConfigDir_.empty()) {
        return;
    }
    char dirBuf[1024] = {0};
    if (vl_resolve_config_dir(dirBuf, sizeof(dirBuf))) {
        cachedConfigDir_ = dirBuf;
        cachedEnvPath_ = cachedConfigDir_ + "/config.env";
        cachedMacrosPath_ = cachedConfigDir_ + "/macros.json";
        cachedRulesPath_ = cachedConfigDir_ + "/typing-modes.yml";
    }
}

vl_presentation_mode_t VieLotusEngine::resolvePresentationMode(InputContext* ic) const {
    if (presentationRules_.count == 0) {
        return VL_PRESENTATION_AUTOMATIC;
    }
    std::string appId = ic ? ic->program() : "";
    if (appId.empty()) {
        const char* envId = std::getenv("VIELOTUS_APP_ID");
        if (envId) appId = envId;
    }
    return vl_presentation_rules_resolve(&presentationRules_, appId.c_str());
}

void VieLotusEngine::setConfig(const RawConfig& config) {
    config_.load(config, true);
    safeSaveAsIni(config_, "conf/vielotus.conf");
    saveUserEnvConfig();
    applyConfigToAllContexts();
}

void VieLotusEngine::loadUserEnvConfig() {
    ensureConfigPaths();
    if (cachedEnvPath_.empty()) {
        return;
    }
    vl_env_config_t env{};
    vl_env_config_init_defaults(&env);
    env.sen_flex = (*config_.grammarProfile != VieLotusGrammarMode::Classic);
    env.smart_bilingual = *config_.smartBilingual;
    env.modern_orthography = *config_.modernOrthography;
    env.quick_telex = *config_.quickTelex;
    env.relaxed_coda = *config_.relaxedCoda;
    env.macro_enabled = *config_.macroEnabled;
    env.developer_mode = *config_.developerMode;
    env.preedit_underline = *config_.preeditUnderline;

    if (!vl_env_config_load(cachedEnvPath_.c_str(), &env, &envConfigMtime_)) {
        return;
    }
    if (env.has_input_method) {
        hasEnvInputMethod_ = true;
        envInputMethod_ = env.is_vni ? VIELOTUS_INPUT_VNI : VIELOTUS_INPUT_TELEX;
    }
    config_.grammarProfile.setValue(
        env.sen_flex ? VieLotusGrammarMode::SenFlex : VieLotusGrammarMode::Classic);
    config_.smartBilingual.setValue(env.smart_bilingual);
    config_.modernOrthography.setValue(env.modern_orthography);
    config_.quickTelex.setValue(env.quick_telex);
    config_.relaxedCoda.setValue(env.relaxed_coda);
    config_.macroEnabled.setValue(env.macro_enabled);
    config_.developerMode.setValue(env.developer_mode);
    config_.preeditUnderline.setValue(env.preedit_underline);
}

bool VieLotusEngine::reloadUserEnvConfigIfChanged() {
    ensureConfigPaths();
    if (cachedEnvPath_.empty()) {
        return false;
    }
    struct stat st;
    if (stat(cachedEnvPath_.c_str(), &st) == 0 && st.st_mtime != envConfigMtime_) {
        loadUserEnvConfig();
        return true;
    }
    return false;
}

void VieLotusEngine::reloadAuxiliaryDataIfChanged() {
    ensureConfigPaths();
    vl_macros_reload_if_changed(
        cachedMacrosPath_.empty() ? nullptr : cachedMacrosPath_.c_str(),
        &macrosMtime_,
        &macrosHadFile_);
    vl_presentation_rules_reload_if_changed(
        &presentationRules_,
        cachedRulesPath_.empty() ? nullptr : cachedRulesPath_.c_str(),
        kSystemTypingModesPath);
}

void VieLotusEngine::saveUserEnvConfig() const {
    char dirBuf[1024] = {0};
    if (!vl_resolve_config_dir(dirBuf, sizeof(dirBuf))) {
        return;
    }
    std::string envPath = std::string(dirBuf) + "/config.env";
    vl_env_config_t existing{};
    vl_env_config_init_defaults(&existing);
    (void)vl_env_config_load(envPath.c_str(), &existing, nullptr);

    existing.sen_flex = (*config_.grammarProfile != VieLotusGrammarMode::Classic);
    existing.smart_bilingual = *config_.smartBilingual;
    existing.modern_orthography = *config_.modernOrthography;
    existing.quick_telex = *config_.quickTelex;
    existing.relaxed_coda = *config_.relaxedCoda;
    existing.macro_enabled = *config_.macroEnabled;
    existing.developer_mode = *config_.developerMode;
    existing.preedit_underline = *config_.preeditUnderline;
    if (!existing.has_input_method && hasEnvInputMethod_) {
        existing.is_vni = (envInputMethod_ == VIELOTUS_INPUT_VNI);
    }

    time_t newMtime = 0;
    if (vl_env_config_save_merged(envPath.c_str(), &existing, &newMtime)) {
        const_cast<VieLotusEngine*>(this)->envConfigMtime_ = newMtime;
    }
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
    reloadAuxiliaryDataIfChanged();
    applyConfigToAllContexts();
}

void VieLotusEngine::activate(const InputMethodEntry& entry,
                              InputContextEvent& event) {
    FCITX_UNUSED(entry);
    reloadUserEnvConfigIfChanged();
    reloadAuxiliaryDataIfChanged();
    auto* ic = event.inputContext();
    auto& statusArea = ic->statusArea();
    statusArea.addAction(StatusGroup::InputMethod, settingsAction_.get());
    auto* state = ic->propertyFor(&factory_);
    if (state) {
        state->applyConfig(config_);
        if (state->session()) {
            vielotus_append_context(state->session(), "");
            if (!ic->capabilityFlags().test(CapabilityFlag::Password) &&
                ic->capabilityFlags().test(CapabilityFlag::SurroundingText) &&
                ic->surroundingText().isValid()) {
                const auto& text = ic->surroundingText().text();
                const auto cursor = ic->surroundingText().cursor();
                if (!text.empty() && cursor > 0) {
                    const size_t bytePos = fcitx::utf8::ncharByteLength(text.begin(), cursor);
                    if (bytePos <= text.size()) {
                        std::string prefix = text.substr(0, bytePos);
                        if (prefix.size() > 256) {
                            size_t cut = prefix.size() - 256;
                            while (cut < prefix.size() &&
                                   (static_cast<unsigned char>(prefix[cut]) & 0xC0) == 0x80) {
                                ++cut;
                            }
                            prefix = prefix.substr(cut);
                        }
                        vielotus_sync_armed_word(state->session(), prefix.c_str());
                    }
                }
            }
        }
    }
}

void VieLotusEngine::deactivate(const InputMethodEntry& entry,
                                InputContextEvent& event) {
    FCITX_UNUSED(entry);
    auto* state = event.inputContext()->propertyFor(&factory_);
    if (state) {
        if (state->session() && vielotus_is_composing(state->session())) {
            state->commitComposing(nullptr);
        } else {
            state->resetWord();
        }
        state->reset();
    }
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
