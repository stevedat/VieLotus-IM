#pragma once

#include <stdint.h>
#include <stddef.h>

namespace vielotus_win {

enum class InputMethod : int32_t {
    Telex = 0,
    VNI = 1
};

enum class Action : int32_t {
    PassThrough = 0,
    Consumed = 1,
    Replace = 2,
    Commit = 3,
    Reset = 4
};

class WindowsNativeEngine {
public:
    static constexpr int kMaxWordTokens = 64;
    static constexpr int kMaxUtf8Bytes = 256;

    WindowsNativeEngine();

    void reset();
    void clearWordState();

    void setInputMethod(InputMethod method);
    InputMethod getInputMethod() const { return m_inputMethod; }

    void setSmartBilingual(bool enabled) { m_smartBilingual = enabled; }
    bool getSmartBilingual() const { return m_smartBilingual; }

    void setModernOrthography(bool enabled) { m_modernOrthography = enabled; }
    bool getModernOrthography() const { return m_modernOrthography; }

    void setGrammarProfile(int32_t profile) { m_grammarProfile = (profile == 0) ? 0 : 1; }
    int32_t getGrammarProfile() const { return m_grammarProfile; }

    void setQuickTelex(bool enabled) { m_quickTelex = enabled; }
    bool getQuickTelex() const { return m_quickTelex; }

    int32_t feedChar(uint32_t codepoint);
    int32_t feedBackspace();
    int32_t commitWord();
    void syncSurroundingContext(const char *beforeContextUtf8);

    int32_t getLastBackspaces() const { return m_lastBackspaces; }
    const char *getLastTextUtf8() const { return m_lastTextUtf8; }
    bool isComposing() const { return m_composingFlag; }

private:
    InputMethod m_inputMethod{InputMethod::Telex};
    bool m_smartBilingual{true};
    bool m_modernOrthography{true};
    int32_t m_grammarProfile{1};
    bool m_quickTelex{false};
    bool m_composingFlag{false};
    int32_t m_lastBackspaces{0};
    char m_lastTextUtf8[kMaxUtf8Bytes]{};
    alignas(8) uint8_t m_opaqueState[4096]{};
};

} // namespace vielotus_win
