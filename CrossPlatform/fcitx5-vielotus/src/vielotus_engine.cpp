#include "vielotus_engine.h"
#include <fcitx/inputpanel.h>
#include <fcitx/addonmanager.h>
#include <fcitx-utils/keysym.h>

namespace fcitx {

VieLotusState::VieLotusState(InputContext* ic) : ic_(ic) {
    session_ = vielotus_create_session();
    vielotus_set_input_method(session_, VIELOTUS_INPUT_TELEX);
    vielotus_set_grammar_profile(session_, VIELOTUS_GRAMMAR_SEN_FLEX);
    vielotus_set_smart_bilingual(session_, true);
    vielotus_set_modern_orthography(session_, true);
}

VieLotusState::~VieLotusState() {
    if (session_) {
        vielotus_destroy_session(session_);
        session_ = nullptr;
    }
}

void VieLotusState::setInputMethod(int32_t method) {
    if (session_ && inputMethod_ != method) {
        inputMethod_ = method;
        vielotus_set_input_method(session_, static_cast<vielotus_input_method_t>(method));
        reset();
    }
}

void VieLotusState::reset() {
    if (session_) {
        vielotus_reset_session(session_);
    }
    ic_->inputPanel().reset();
    ic_->updatePreedit();
    ic_->updateUserInterface(UserInterfaceComponent::InputPanel);
}

void VieLotusState::keyEvent(KeyEvent& keyEvent) {
    // Only handle KeyPress events, ignore KeyRelease
    if (keyEvent.isRelease()) {
        return;
    }

    // Ignore events with Ctrl / Alt / Super modifier keys
    auto states = keyEvent.key().states();
    if (states.test(KeyState::Ctrl) || states.test(KeyState::Alt) || states.test(KeyState::Super)) {
        if (vielotus_is_composing(session_)) {
            vielotus_commit_word(session_);
            reset();
        }
        return;
    }

    // Check backspace
    if (keyEvent.key().check(FcitxKey_BackSpace)) {
        if (vielotus_is_composing(session_)) {
            bool hasSurrounding = ic_->capabilityFlags().test(CapabilityFlag::SurroundingText);
            int32_t action = vielotus_feed_backspace(session_);
            if (action == VIELOTUS_ACTION_RESET || !vielotus_is_composing(session_)) {
                reset();
                if (!hasSurrounding) {
                    keyEvent.filterAndAccept();
                }
                return;
            } else if (hasSurrounding) {
                int32_t bs = vielotus_get_last_backspaces(session_);
                const char* replacement = vielotus_get_last_text(session_);
                if (bs > 0) {
                    ic_->deleteSurroundingText(-bs, bs);
                }
                if (replacement && replacement[0] != '\0') {
                    ic_->commitString(replacement);
                }
                ic_->inputPanel().reset();
                ic_->updatePreedit();
                ic_->updateUserInterface(UserInterfaceComponent::InputPanel);
                keyEvent.filterAndAccept();
                return;
            } else {
                const char* composing = vielotus_get_composing_text(session_);
                Text preeditText;
                preeditText.append(composing ? composing : "");
                ic_->inputPanel().setPreedit(preeditText);
                ic_->updatePreedit();
                ic_->updateUserInterface(UserInterfaceComponent::InputPanel);
                keyEvent.filterAndAccept();
                return;
            }
        }
        return;
    }

    // Handle printable character input
    uint32_t sym = keyEvent.key().sym();
    if (sym >= 32 && sym < 127) {
        bool hasSurrounding = ic_->capabilityFlags().test(CapabilityFlag::SurroundingText);
        int32_t action = vielotus_feed_char(session_, sym);

        if (action == VIELOTUS_ACTION_COMMIT) {
            // Word committed (e.g. space or punctuation)
            const char* committedText = vielotus_get_last_text(session_);
            if (committedText && committedText[0] != '\0') {
                if (!hasSurrounding) {
                    // In preedit fallback mode, commit the resolved word
                    ic_->commitString(committedText);
                } else {
                    int32_t bs = vielotus_get_last_backspaces(session_);
                    if (bs > 0) {
                        ic_->deleteSurroundingText(-bs, bs);
                    }
                    ic_->commitString(committedText);
                }
            }
            // Append trailing boundary character
            char boundary[2] = { static_cast<char>(sym), '\0' };
            ic_->commitString(boundary);

            reset();
            keyEvent.filterAndAccept();
            return;
        } else if (action == VIELOTUS_ACTION_REPLACE) {
            if (hasSurrounding) {
                // Client supports surrounding text: delete backwards and commit updated syllable
                int32_t bs = vielotus_get_last_backspaces(session_);
                const char* replacement = vielotus_get_last_text(session_);
                if (bs > 0) {
                    ic_->deleteSurroundingText(-bs, bs);
                }
                if (replacement && replacement[0] != '\0') {
                    ic_->commitString(replacement);
                }
                // Clear any preedit artifact
                ic_->inputPanel().reset();
                ic_->updatePreedit();
                ic_->updateUserInterface(UserInterfaceComponent::InputPanel);
                keyEvent.filterAndAccept();
                return;
            } else {
                // Fallback to Preedit display
                const char* composing = vielotus_get_composing_text(session_);
                Text preeditText;
                preeditText.append(composing ? composing : "");
                ic_->inputPanel().setPreedit(preeditText);
                ic_->updatePreedit();
                ic_->updateUserInterface(UserInterfaceComponent::InputPanel);
                keyEvent.filterAndAccept();
                return;
            }
        } else if (action == VIELOTUS_ACTION_CONSUMED || vielotus_is_composing(session_)) {
            if (hasSurrounding) {
                // First or intermediate character: commit directly to screen
                char ch[2] = { static_cast<char>(sym), '\0' };
                ic_->commitString(ch);
                keyEvent.filterAndAccept();
                return;
            } else {
                // Fallback to Preedit display
                const char* composing = vielotus_get_composing_text(session_);
                Text preeditText;
                preeditText.append(composing ? composing : "");
                ic_->inputPanel().setPreedit(preeditText);
                ic_->updatePreedit();
                ic_->updateUserInterface(UserInterfaceComponent::InputPanel);
                keyEvent.filterAndAccept();
                return;
            }
        }
    }
}

// ============================================================================
// VieLotusEngine Implementation
// ============================================================================

VieLotusEngine::VieLotusEngine(Instance* instance)
    : instance_(instance),
      factory_([this](InputContext& ic) { return new VieLotusState(&ic); }) {
    instance_->inputContextManager().registerProperty("vielotusState", &factory_);
    const char* bridgeOptIn = std::getenv("VIELOTUS_ENABLE_LOOPBACK_BRIDGE");
    if (bridgeOptIn && std::string(bridgeOptIn) == "1") {
        vielotus_start_loopback_bridge(2811);
    }
}

VieLotusEngine::~VieLotusEngine() {
    vielotus_stop_loopback_bridge();
}

void VieLotusEngine::keyEvent(const InputMethodEntry& entry, KeyEvent& keyEvent) {
    auto* state = keyEvent.inputContext()->propertyFor(&factory_);
    if (state) {
        int32_t method = (entry.uniqueName() == "vielotus-vni")
            ? VIELOTUS_INPUT_VNI
            : VIELOTUS_INPUT_TELEX;
        state->setInputMethod(method);
        state->keyEvent(keyEvent);
    }
}

void VieLotusEngine::reset(const InputMethodEntry& entry, InputContextEvent& event) {
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
