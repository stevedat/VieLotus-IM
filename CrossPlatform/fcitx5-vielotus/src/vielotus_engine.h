#ifndef VIELOTUS_ENGINE_H
#define VIELOTUS_ENGINE_H

#include <fcitx-config/configuration.h>
#include <fcitx-config/enum.h>
#include <fcitx-config/iniparser.h>
#include <fcitx-config/option.h>
#include <fcitx-config/rawconfig.h>
#include <fcitx-utils/i18n.h>
#include <fcitx-utils/key.h>
#include <fcitx/action.h>
#include <fcitx/addonfactory.h>
#include <fcitx/addoninstance.h>
#include <fcitx/addonmanager.h>
#include <fcitx/inputcontext.h>
#include <fcitx/inputcontextproperty.h>
#include <fcitx/inputmethodengine.h>
#include <fcitx/instance.h>
#include <fcitx/menu.h>
#include <memory>
#include <string>
#include "vielotus.h"

namespace fcitx {

enum class VieLotusInputMode { Telex, VNI };
FCITX_CONFIG_ENUM_NAME_WITH_I18N(VieLotusInputMode,
                                 N_("Telex (Gõ dấu tự do)"),
                                 N_("VNI (Phím số 1-9)"));

enum class VieLotusGrammarMode { SenFlex, Classic };
FCITX_CONFIG_ENUM_NAME_WITH_I18N(VieLotusGrammarMode,
                                 N_("SEN Flex (Gõ dấu tự do)"),
                                 N_("Classic (Chuẩn truyền thống)"));

FCITX_CONFIGURATION(
    VieLotusConfig,
    OptionWithAnnotation<VieLotusGrammarMode, VieLotusGrammarModeI18NAnnotation>
        grammarProfile{this, "GrammarProfile",
                       _("Chế độ đặt dấu (Grammar Profile)"),
                       VieLotusGrammarMode::SenFlex};
    Option<bool> smartBilingual{
        this, "SmartBilingual",
        _("Song ngữ thông minh Anh-Việt (Smart Bilingual)"), true};
    Option<bool> modernOrthography{
        this, "ModernOrthography",
        _("Chính tả hiện đại: oà, uý (thay vì òa, úy)"), true};
    Option<bool> quickTelex{
        this, "QuickTelex",
        _("Gõ tắt phụ âm (Quick Telex: cc=ch, gg=gi, kk=kh...)"), false};
);

class VieLotusEngine;

class VieLotusState : public InputContextProperty {
public:
    VieLotusState(VieLotusEngine* engine, InputContext* ic);
    ~VieLotusState();

    void keyEvent(KeyEvent& keyEvent);
    void setInputMethod(int32_t method);
    void applyConfig(const VieLotusConfig& config);
    void updatePreedit();
    void commitComposing(const char* trailingAscii = nullptr);
    void resetWord();
    void reset();

    vielotus_session_t session() const { return session_; }

private:
    VieLotusEngine* engine_;
    InputContext* ic_;
    vielotus_session_t session_;
    int32_t inputMethod_{VIELOTUS_INPUT_TELEX};
};

class VieLotusEngine : public InputMethodEngineV2 {
public:
    VieLotusEngine(Instance* instance);
    ~VieLotusEngine() override;

    const Configuration* getConfig() const override { return &config_; }
    void setConfig(const RawConfig& config) override;
    const Configuration* getConfigForInputMethod(
        const InputMethodEntry& entry) const override {
        FCITX_UNUSED(entry);
        return &config_;
    }
    void setConfigForInputMethod(const InputMethodEntry& entry,
                                 const RawConfig& config) override {
        FCITX_UNUSED(entry);
        setConfig(config);
    }
    void reloadConfig() override;

    void activate(const InputMethodEntry& entry,
                  InputContextEvent& event) override;
    void deactivate(const InputMethodEntry& entry,
                    InputContextEvent& event) override;
    void keyEvent(const InputMethodEntry& entry, KeyEvent& keyEvent) override;
    void reset(const InputMethodEntry& entry,
               InputContextEvent& event) override;

    Instance* instance() const { return instance_; }
    const VieLotusConfig& config() const { return config_; }

private:
    void loadUserEnvConfig();
    void saveUserEnvConfig() const;
    void applyConfigToAllContexts();

    Instance* instance_;
    VieLotusConfig config_;
    int32_t envInputMethod_{VIELOTUS_INPUT_TELEX};
    bool hasEnvInputMethod_{false};
    FactoryFor<VieLotusState> factory_;
    std::unique_ptr<SimpleAction> settingsAction_;
    std::vector<ScopedConnection> connections_;
};

class VieLotusEngineFactory : public AddonFactory {
public:
    AddonInstance* create(AddonManager* manager) override;
};

} // namespace fcitx

#endif // VIELOTUS_ENGINE_H
