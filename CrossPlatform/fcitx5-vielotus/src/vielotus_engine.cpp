#include "vielotus_engine.h"
#include <cstdlib>
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
            TextFormatFlags formatFlags = useClientPreedit
                ? TextFormatFlag::Underline
                : TextFormatFlag::NoFlag;
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

    if (session_) {
        vielotus_reset_session(session_);
    }
    ic_->inputPanel().reset();
    ic_->updatePreedit();
    ic_->updateUserInterface(UserInterfaceComponent::InputPanel);
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
    if (keyEvent.isRelease()) {
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
    // commit active word first so it never disappears, then let the app handle the key
    if (sym == FcitxKey_Return || sym == FcitxKey_KP_Enter ||
        sym == FcitxKey_Tab || sym == FcitxKey_ISO_Left_Tab ||
        sym == FcitxKey_Delete || sym == FcitxKey_KP_Delete ||
        sym == FcitxKey_Escape ||
        (sym >= FcitxKey_Home && sym <= FcitxKey_Insert) ||
        (sym >= FcitxKey_KP_Home && sym <= FcitxKey_KP_Delete)) {
        if (vielotus_is_composing(session_)) {
            commitComposing(nullptr);
        }
        return;
    }

    // Handle BackSpace
    if (keyEvent.key().check(FcitxKey_BackSpace)) {
        if (vielotus_is_composing(session_)) {
            int32_t action = vielotus_feed_backspace(session_);
            if (action == VIELOTUS_ACTION_RESET ||
                !vielotus_is_composing(session_)) {
                reset();
            } else {
                updatePreedit();
            }
            keyEvent.filterAndAccept();
            return;
        }
        vielotus_feed_backspace(session_);
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
                    reset();
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

        // Feed word character (letter or VNI tone digit)
        int32_t action = vielotus_feed_char(session_, sym);
        if (action == VIELOTUS_ACTION_COMMIT) {
            const char* committed = vielotus_get_last_text(session_);
            std::string out = committed ? committed : "";
            if (!out.empty()) {
                ic_->commitString(out);
            }
            reset();
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
            startProcess({"/usr/bin/vielotus-settings"});
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
