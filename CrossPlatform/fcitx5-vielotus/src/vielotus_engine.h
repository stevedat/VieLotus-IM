#ifndef VIELOTUS_ENGINE_H
#define VIELOTUS_ENGINE_H

#include <fcitx/inputmethodengine.h>
#include <fcitx/inputcontext.h>
#include <fcitx/inputcontextproperty.h>
#include <fcitx/instance.h>
#include <fcitx/addonfactory.h>
#include <fcitx-utils/key.h>
#include "vielotus.h"

namespace fcitx {

class VieLotusState : public InputContextProperty {
public:
    VieLotusState(InputContext* ic);
    ~VieLotusState();

    void keyEvent(KeyEvent& keyEvent);
    void setInputMethod(int32_t method);
    void reset();

    vielotus_session_t session() const { return session_; }

private:
    InputContext* ic_;
    vielotus_session_t session_;
    int32_t inputMethod_{VIELOTUS_INPUT_TELEX};
};

class VieLotusEngine : public InputMethodEngineV2 {
public:
    VieLotusEngine(Instance* instance);
    ~VieLotusEngine() override;

    void keyEvent(const InputMethodEntry& entry, KeyEvent& keyEvent) override;
    void reset(const InputMethodEntry& entry, InputContextEvent& event) override;

    Instance* instance() const { return instance_; }

private:
    Instance* instance_;
    FactoryFor<VieLotusState> factory_;
};

class VieLotusEngineFactory : public AddonFactory {
public:
    AddonInstance* create(AddonManager* manager) override;
};

} // namespace fcitx

#endif // VIELOTUS_ENGINE_H
