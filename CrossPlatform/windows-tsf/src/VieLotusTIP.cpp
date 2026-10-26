#include "VieLotusTIP.h"
#include "EditSession.h"
#include "Register.h"
#include <vector>

#define VI_LANGID 0x042A

namespace {

struct VieLotusCApi {
    HMODULE hModule{nullptr};
    bool isValid{false};

    vielotus_session_t (*create_session)(void){nullptr};
    void (*destroy_session)(vielotus_session_t){nullptr};
    void (*reset_session)(vielotus_session_t){nullptr};
    void (*set_input_method)(vielotus_session_t, vielotus_input_method_t){nullptr};
    void (*set_grammar_profile)(vielotus_session_t, int32_t){nullptr};
    void (*set_smart_bilingual)(vielotus_session_t, bool){nullptr};
    void (*set_modern_orthography)(vielotus_session_t, bool){nullptr};
    int32_t (*feed_char)(vielotus_session_t, uint32_t){nullptr};
    int32_t (*feed_backspace)(vielotus_session_t){nullptr};
    int32_t (*commit_word)(vielotus_session_t){nullptr};
    int32_t (*get_last_backspaces)(vielotus_session_t){nullptr};
    const char *(*get_last_text)(vielotus_session_t){nullptr};
    bool (*is_composing)(vielotus_session_t){nullptr};

    VieLotusCApi() {
        WCHAR dllPath[MAX_PATH] = {0};
        if (GetModuleFileNameW(g_hInst, dllPath, MAX_PATH) == 0) {
            return;
        }
        std::wstring dirPath(dllPath);
        size_t lastSlash = dirPath.find_last_of(L"\\/");
        if (lastSlash != std::wstring::npos) {
            dirPath.resize(lastSlash + 1);
        } else {
            dirPath.clear();
        }
        std::wstring capiPath = dirPath + L"VieLotusCAPI.dll";
        std::wstring swiftCorePath = dirPath + L"swiftCore.dll";

        if (GetFileAttributesW(capiPath.c_str()) == INVALID_FILE_ATTRIBUTES ||
            GetFileAttributesW(swiftCorePath.c_str()) == INVALID_FILE_ATTRIBUTES) {
            return;
        }

        hModule = LoadLibraryExW(
            capiPath.c_str(),
            nullptr,
            LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_DEFAULT_DIRS
        );
        if (!hModule) {
            return;
        }

        create_session = reinterpret_cast<decltype(create_session)>(GetProcAddress(hModule, "vielotus_create_session"));
        destroy_session = reinterpret_cast<decltype(destroy_session)>(GetProcAddress(hModule, "vielotus_destroy_session"));
        reset_session = reinterpret_cast<decltype(reset_session)>(GetProcAddress(hModule, "vielotus_reset_session"));
        set_input_method = reinterpret_cast<decltype(set_input_method)>(GetProcAddress(hModule, "vielotus_set_input_method"));
        set_grammar_profile = reinterpret_cast<decltype(set_grammar_profile)>(GetProcAddress(hModule, "vielotus_set_grammar_profile"));
        set_smart_bilingual = reinterpret_cast<decltype(set_smart_bilingual)>(GetProcAddress(hModule, "vielotus_set_smart_bilingual"));
        set_modern_orthography = reinterpret_cast<decltype(set_modern_orthography)>(GetProcAddress(hModule, "vielotus_set_modern_orthography"));
        feed_char = reinterpret_cast<decltype(feed_char)>(GetProcAddress(hModule, "vielotus_feed_char"));
        feed_backspace = reinterpret_cast<decltype(feed_backspace)>(GetProcAddress(hModule, "vielotus_feed_backspace"));
        commit_word = reinterpret_cast<decltype(commit_word)>(GetProcAddress(hModule, "vielotus_commit_word"));
        get_last_backspaces = reinterpret_cast<decltype(get_last_backspaces)>(GetProcAddress(hModule, "vielotus_get_last_backspaces"));
        get_last_text = reinterpret_cast<decltype(get_last_text)>(GetProcAddress(hModule, "vielotus_get_last_text"));
        is_composing = reinterpret_cast<decltype(is_composing)>(GetProcAddress(hModule, "vielotus_is_composing"));

        isValid = create_session && destroy_session && reset_session &&
                  set_input_method && set_grammar_profile && set_smart_bilingual &&
                  set_modern_orthography && feed_char && feed_backspace &&
                  commit_word && get_last_backspaces && get_last_text && is_composing;
    }
};

const VieLotusCApi &GetCApi() {
    static VieLotusCApi s_api;
    return s_api;
}

} // namespace

static std::wstring Utf8ToWide(const char *utf8Str) {
    if (!utf8Str || utf8Str[0] == '\0') return L"";
    int numChars = MultiByteToWideChar(CP_UTF8, 0, utf8Str, -1, nullptr, 0);
    if (numChars <= 0) return L"";
    std::wstring result(numChars - 1, L'\0');
    MultiByteToWideChar(CP_UTF8, 0, utf8Str, -1, &result[0], numChars);
    return result;
}

CVieLotusTIP::CVieLotusTIP() {
    DllAddRef();
}

CVieLotusTIP::~CVieLotusTIP() {
    CleanSession();
    DllRelease();
}

STDMETHODIMP CVieLotusTIP::QueryInterface(REFIID riid, void **ppvObj) {
    if (!ppvObj) return E_POINTER;
    *ppvObj = nullptr;

    if (IsEqualIID(riid, IID_IUnknown) ||
        IsEqualIID(riid, IID_ITfTextInputProcessor) ||
        IsEqualIID(riid, IID_ITfTextInputProcessorEx_Compat)) {
        *ppvObj = static_cast<ITfTextInputProcessorEx *>(this);
    } else if (IsEqualIID(riid, IID_ITfKeyEventSink)) {
        *ppvObj = static_cast<ITfKeyEventSink *>(this);
    } else if (IsEqualIID(riid, IID_ITfThreadMgrEventSink)) {
        *ppvObj = static_cast<ITfThreadMgrEventSink *>(this);
    } else if (IsEqualIID(riid, IID_ITfCompositionSink)) {
        *ppvObj = static_cast<ITfCompositionSink *>(this);
    }

    if (*ppvObj) {
        AddRef();
        return S_OK;
    }
    return E_NOINTERFACE;
}

STDMETHODIMP_(ULONG) CVieLotusTIP::AddRef() {
    return m_cRef.fetch_add(1, std::memory_order_relaxed) + 1;
}

STDMETHODIMP_(ULONG) CVieLotusTIP::Release() {
    LONG cRef = m_cRef.fetch_sub(1, std::memory_order_relaxed) - 1;
    if (cRef == 0) {
        delete this;
    }
    return cRef;
}

void CVieLotusTIP::ReloadUserPreferences() {
    VieLotusWindowsPrefs prefs{};
    LoadVieLotusPrefs(prefs);
    m_isVniMode = prefs.isVni;
    m_isVietnameseMode = prefs.vietnameseEnabled;

#if defined(VIELOTUS_EMBEDDED_ENGINE)
    m_nativeEngine.setInputMethod(m_isVniMode ? vielotus_win::InputMethod::VNI : vielotus_win::InputMethod::Telex);
    m_nativeEngine.setSmartBilingual(prefs.smartBilingual);
    m_nativeEngine.setModernOrthography(prefs.modernOrthography);
#endif

    const auto &api = GetCApi();
    if (api.isValid && m_session) {
        api.set_input_method(m_session, m_isVniMode ? VIELOTUS_INPUT_VNI : VIELOTUS_INPUT_TELEX);
        api.set_smart_bilingual(m_session, prefs.smartBilingual);
        api.set_modern_orthography(m_session, prefs.modernOrthography);
    }
}

void CVieLotusTIP::InitSession() {
    ReloadUserPreferences();

    const auto &api = GetCApi();
    if (api.isValid && !m_session) {
        m_session = api.create_session();
        if (m_session) {
            VieLotusWindowsPrefs prefs{};
            LoadVieLotusPrefs(prefs);
            api.set_input_method(m_session, m_isVniMode ? VIELOTUS_INPUT_VNI : VIELOTUS_INPUT_TELEX);
            api.set_grammar_profile(m_session, VIELOTUS_GRAMMAR_SEN_FLEX);
            api.set_smart_bilingual(m_session, prefs.smartBilingual);
            api.set_modern_orthography(m_session, prefs.modernOrthography);
        }
    }
    SyncActiveLanguageProfile();
}

void CVieLotusTIP::SyncActiveLanguageProfile() {
    ITfInputProcessorProfileMgr *pProfileMgr = nullptr;
    if (m_pThreadMgr && SUCCEEDED(m_pThreadMgr->QueryInterface(IID_ITfInputProcessorProfileMgr, reinterpret_cast<void **>(&pProfileMgr)))) {
        TF_INPUTPROCESSORPROFILE activeProfile{};
        if (SUCCEEDED(pProfileMgr->GetActiveProfile(GUID_TFCAT_TIP_KEYBOARD, &activeProfile)) &&
            IsEqualCLSID(activeProfile.clsid, CLSID_VieLotusTIP)) {
            bool isVni = IsEqualGUID(activeProfile.guidProfile, GUID_VieLotusProfileVNI) != FALSE;
            if (m_isVniMode != isVni) {
                m_isVniMode = isVni;
                SavePersistedVniPreference(m_isVniMode);

                // Persist as Windows default profile for Vietnamese so reboot/restart keeps VNI/Telex
                ITfInputProcessorProfiles *pProfiles = nullptr;
                if (SUCCEEDED(CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr, CLSCTX_INPROC_SERVER, IID_ITfInputProcessorProfiles, (void **)&pProfiles)) && pProfiles) {
                    pProfiles->SetDefaultLanguageProfile(VI_LANGID, CLSID_VieLotusTIP, activeProfile.guidProfile);
                    pProfiles->Release();
                }

#if defined(VIELOTUS_EMBEDDED_ENGINE)
                m_nativeEngine.setInputMethod(m_isVniMode ? vielotus_win::InputMethod::VNI : vielotus_win::InputMethod::Telex);
#endif
                const auto &api = GetCApi();
                if (api.isValid && m_session) {
                    api.set_input_method(m_session, m_isVniMode ? VIELOTUS_INPUT_VNI : VIELOTUS_INPUT_TELEX);
                    api.reset_session(m_session);
                }
            }
        }
        pProfileMgr->Release();
    }
}

void CVieLotusTIP::ResetComposingSession() {
#if defined(VIELOTUS_EMBEDDED_ENGINE)
    m_nativeEngine.reset();
#endif
    const auto &api = GetCApi();
    if (m_session && api.isValid) {
        api.reset_session(m_session);
    }
}

bool CVieLotusTIP::IsComposingSession() const {
    const auto &api = GetCApi();
    if (m_session && api.isValid) {
        return api.is_composing(m_session);
    }
#if defined(VIELOTUS_EMBEDDED_ENGINE)
    return m_nativeEngine.isComposing();
#else
    return false;
#endif
}

int32_t CVieLotusTIP::FeedCharSession(uint32_t codePoint) {
    const auto &api = GetCApi();
    if (m_session && api.isValid) {
        return api.feed_char(m_session, codePoint);
    }
#if defined(VIELOTUS_EMBEDDED_ENGINE)
    return m_nativeEngine.feedChar(codePoint);
#else
    return VIELOTUS_ACTION_PASSTHROUGH;
#endif
}

int32_t CVieLotusTIP::FeedBackspaceSession() {
    const auto &api = GetCApi();
    if (m_session && api.isValid) {
        return api.feed_backspace(m_session);
    }
#if defined(VIELOTUS_EMBEDDED_ENGINE)
    return m_nativeEngine.feedBackspace();
#else
    return VIELOTUS_ACTION_PASSTHROUGH;
#endif
}

int32_t CVieLotusTIP::CommitWordSession() {
    const auto &api = GetCApi();
    if (m_session && api.isValid) {
        return api.commit_word(m_session);
    }
#if defined(VIELOTUS_EMBEDDED_ENGINE)
    return m_nativeEngine.commitWord();
#else
    return VIELOTUS_ACTION_PASSTHROUGH;
#endif
}

int32_t CVieLotusTIP::GetLastBackspacesSession() const {
    const auto &api = GetCApi();
    if (m_session && api.isValid) {
        return api.get_last_backspaces(m_session);
    }
#if defined(VIELOTUS_EMBEDDED_ENGINE)
    return m_nativeEngine.getLastBackspaces();
#else
    return 0;
#endif
}

const char *CVieLotusTIP::GetLastTextSession() const {
    const auto &api = GetCApi();
    if (m_session && api.isValid) {
        return api.get_last_text(m_session);
    }
#if defined(VIELOTUS_EMBEDDED_ENGINE)
    return m_nativeEngine.getLastTextUtf8();
#else
    return "";
#endif
}

void CVieLotusTIP::ExecuteEditSession(ITfContext *pic, int32_t backspaces, const std::wstring &text, bool bCommit) {
    if (!pic) return;
    CEditSession *pEdit = new (std::nothrow) CEditSession(pic, backspaces, text, bCommit);
    if (!pEdit) return;
    HRESULT hrSession = S_OK;
    pic->RequestEditSession(m_tfClientId, pEdit, TF_ES_ASYNCDONTCARE | TF_ES_READWRITE, &hrSession);
    pEdit->Release();
}

void CVieLotusTIP::CleanSession() {
#if defined(VIELOTUS_EMBEDDED_ENGINE)
    m_nativeEngine.reset();
#endif
    const auto &api = GetCApi();
    if (m_session && api.isValid) {
        api.destroy_session(m_session);
        m_session = nullptr;
    }
    if (m_pComposition) {
        m_pComposition->Release();
        m_pComposition = nullptr;
    }
}

STDMETHODIMP CVieLotusTIP::Activate(ITfThreadMgr *ptim, TfClientId tid) {
    return ActivateEx(ptim, tid, 0);
}

STDMETHODIMP CVieLotusTIP::ActivateEx(ITfThreadMgr *ptim, TfClientId tid, DWORD dwFlags) {
    (void)dwFlags;
    if (!ptim) return E_INVALIDARG;

    m_pThreadMgr = ptim;
    m_pThreadMgr->AddRef();
    m_tfClientId = tid;

    InitSession();

    // 1. Advise KeyEventSink
    ITfKeystrokeMgr *pKeystrokeMgr = nullptr;
    if (SUCCEEDED(m_pThreadMgr->QueryInterface(IID_ITfKeystrokeMgr, reinterpret_cast<void **>(&pKeystrokeMgr)))) {
        pKeystrokeMgr->AdviseKeyEventSink(m_tfClientId, static_cast<ITfKeyEventSink *>(this), TRUE);
        pKeystrokeMgr->Release();
    }

    // 2. Advise ThreadMgrEventSink
    ITfSource *pSource = nullptr;
    if (SUCCEEDED(m_pThreadMgr->QueryInterface(IID_ITfSource, reinterpret_cast<void **>(&pSource)))) {
        pSource->AdviseSink(IID_ITfThreadMgrEventSink, static_cast<ITfThreadMgrEventSink *>(this), &m_dwThreadMgrEventSinkCookie);
        pSource->Release();
    }

    return S_OK;
}

STDMETHODIMP CVieLotusTIP::Deactivate() {
    if (!m_pThreadMgr) return S_OK;

    // 1. Unadvise KeyEventSink
    ITfKeystrokeMgr *pKeystrokeMgr = nullptr;
    if (SUCCEEDED(m_pThreadMgr->QueryInterface(IID_ITfKeystrokeMgr, reinterpret_cast<void **>(&pKeystrokeMgr)))) {
        pKeystrokeMgr->UnadviseKeyEventSink(m_tfClientId);
        pKeystrokeMgr->Release();
    }

    // 2. Unadvise ThreadMgrEventSink
    if (m_dwThreadMgrEventSinkCookie != TF_INVALID_COOKIE) {
        ITfSource *pSource = nullptr;
        if (SUCCEEDED(m_pThreadMgr->QueryInterface(IID_ITfSource, reinterpret_cast<void **>(&pSource)))) {
            pSource->UnadviseSink(m_dwThreadMgrEventSinkCookie);
            pSource->Release();
        }
        m_dwThreadMgrEventSinkCookie = TF_INVALID_COOKIE;
    }

    CleanSession();

    m_pThreadMgr->Release();
    m_pThreadMgr = nullptr;
    m_tfClientId = TF_CLIENTID_NULL;

    return S_OK;
}

STDMETHODIMP CVieLotusTIP::OnSetFocus(BOOL fForeground) {
    (void)fForeground;
    ReloadUserPreferences();
    SyncActiveLanguageProfile();
    return S_OK;
}

STDMETHODIMP CVieLotusTIP::OnTestKeyDown(ITfContext *pic, WPARAM wParam, LPARAM lParam, BOOL *pfEaten) {
    (void)pic;
    (void)lParam;
    if (!pfEaten) return E_POINTER;
    *pfEaten = FALSE;

    // Hotkey: Ctrl + Shift + S -> Open Sen Viet Settings Window
    if (wParam == 'S' && (GetKeyState(VK_CONTROL) & 0x8000) && (GetKeyState(VK_SHIFT) & 0x8000) && !(GetKeyState(VK_MENU) & 0x8000)) {
        *pfEaten = TRUE;
        return S_OK;
    }

    // Hotkey toggle: Ctrl + Space / Shift + Space (handled even when m_isVietnameseMode is false)
    if (wParam == VK_SPACE && ((GetKeyState(VK_CONTROL) & 0x8000) || (GetKeyState(VK_SHIFT) & 0x8000))) {
        *pfEaten = TRUE;
        return S_OK;
    }

    if (!m_isVietnameseMode) return S_OK;

    // Modifier combinations (Ctrl, Alt, Win) -> do not eat
    if ((GetKeyState(VK_CONTROL) & 0x8000) || (GetKeyState(VK_MENU) & 0x8000) ||
        (GetKeyState(VK_LWIN) & 0x8000) || (GetKeyState(VK_RWIN) & 0x8000)) {
        return S_OK;
    }

    bool isComposing = IsComposingSession();

    // Eat BackSpace if currently composing
    if (wParam == VK_BACK && isComposing) {
        *pfEaten = TRUE;
        return S_OK;
    }

    // Eat candidate alphabetic typing keys
    if (wParam >= 'A' && wParam <= 'Z') {
        *pfEaten = TRUE;
        return S_OK;
    }

    // Eat numeric keys when in VNI mode and composing a word
    if (wParam >= '0' && wParam <= '9' && m_isVniMode && isComposing) {
        *pfEaten = TRUE;
        return S_OK;
    }

    // Eat Space and punctuation boundary keys while composing so OnKeyDown commits and triggers Smart Bilingual
    if (isComposing && (
        wParam == VK_SPACE ||
        (wParam >= VK_OEM_1 && wParam <= VK_OEM_3) ||
        (wParam >= VK_OEM_4 && wParam <= VK_OEM_8)
    )) {
        *pfEaten = TRUE;
        return S_OK;
    }

    return S_OK;
}

STDMETHODIMP CVieLotusTIP::OnKeyDown(ITfContext *pic, WPARAM wParam, LPARAM lParam, BOOL *pfEaten) {
    if (!pfEaten) return E_POINTER;
    *pfEaten = FALSE;

    if (!pic) return S_OK;

    // Hotkey: Ctrl + Shift + S -> Open Sen Viet Settings Window
    if (wParam == 'S' && (GetKeyState(VK_CONTROL) & 0x8000) && (GetKeyState(VK_SHIFT) & 0x8000) && !(GetKeyState(VK_MENU) & 0x8000)) {
        ResetComposingSession();
        ShowVieLotusSettingsDialog(GetForegroundWindow());
        ReloadUserPreferences();
        *pfEaten = TRUE;
        return S_OK;
    }

    // Hotkey toggle: Ctrl + Space / Shift + Space
    if (wParam == VK_SPACE && ((GetKeyState(VK_CONTROL) & 0x8000) || (GetKeyState(VK_SHIFT) & 0x8000))) {
        m_isVietnameseMode = !m_isVietnameseMode;
        VieLotusWindowsPrefs prefs{};
        LoadVieLotusPrefs(prefs);
        prefs.vietnameseEnabled = m_isVietnameseMode;
        SaveVieLotusPrefs(prefs);
        ResetComposingSession();
        *pfEaten = TRUE;
        return S_OK;
    }

    if (!m_isVietnameseMode) return S_OK;

    // Modifiers -> commit composing buffer and pass through
    if ((GetKeyState(VK_CONTROL) & 0x8000) || (GetKeyState(VK_MENU) & 0x8000) ||
        (GetKeyState(VK_LWIN) & 0x8000) || (GetKeyState(VK_RWIN) & 0x8000)) {
        if (IsComposingSession()) {
            CommitWordSession();
            ResetComposingSession();
        }
        return S_OK;
    }

    // Backspace handling
    if (wParam == VK_BACK) {
        if (IsComposingSession()) {
            int32_t action = FeedBackspaceSession();
            if (action == VIELOTUS_ACTION_RESET) {
                ResetComposingSession();
                ExecuteEditSession(pic, 1, L"", false);
                *pfEaten = TRUE;
            } else {
                int32_t bs = GetLastBackspacesSession();
                const char *replacement = GetLastTextSession();
                std::wstring wText = Utf8ToWide(replacement);
                ExecuteEditSession(pic, bs, wText, false);
                *pfEaten = TRUE;
            }
            return S_OK;
        }
        return S_OK;
    }

    // Navigation / Enter / Escape / Tab -> reset active composition and let host process key
    if (wParam == VK_RETURN || wParam == VK_TAB || wParam == VK_ESCAPE ||
        (wParam >= VK_PRIOR && wParam <= VK_DOWN)) {
        if (IsComposingSession()) {
            ResetComposingSession();
        }
        return S_OK;
    }

    // Translate virtual key to character
    BYTE keyState[256];
    GetKeyboardState(keyState);
    WCHAR chBuf[4] = {0};
    int toAsciiRes = ToUnicode(static_cast<UINT>(wParam), HIWORD(lParam) & 0xFF, keyState, chBuf, 4, 0);

    if (toAsciiRes > 0 && chBuf[0] >= 32 && chBuf[0] <= 126) {
        uint32_t codePoint = static_cast<uint32_t>(chBuf[0]);
        int32_t action = FeedCharSession(codePoint);

        if (action == VIELOTUS_ACTION_COMMIT) {
            const char *committed = GetLastTextSession();
            int32_t bs = GetLastBackspacesSession();
            std::wstring wCommitted = Utf8ToWide(committed);
            wCommitted += chBuf[0]; // Append boundary key
            ExecuteEditSession(pic, bs, wCommitted, true);
            *pfEaten = TRUE;
            return S_OK;
        } else if (action == VIELOTUS_ACTION_REPLACE) {
            int32_t bs = GetLastBackspacesSession();
            const char *replacement = GetLastTextSession();
            std::wstring wText = Utf8ToWide(replacement);
            ExecuteEditSession(pic, bs, wText, false);
            *pfEaten = TRUE;
            return S_OK;
        } else {
            // CONSUMED or PASS_THROUGH after OnTestKeyDown ate the key: insert character directly
            std::wstring wText(1, chBuf[0]);
            ExecuteEditSession(pic, 0, wText, false);
            *pfEaten = TRUE;
            return S_OK;
        }
    }

    return S_OK;
}

STDMETHODIMP CVieLotusTIP::OnTestKeyUp(ITfContext *pic, WPARAM wParam, LPARAM lParam, BOOL *pfEaten) {
    (void)pic;
    (void)wParam;
    (void)lParam;
    if (pfEaten) *pfEaten = FALSE;
    return S_OK;
}

STDMETHODIMP CVieLotusTIP::OnKeyUp(ITfContext *pic, WPARAM wParam, LPARAM lParam, BOOL *pfEaten) {
    (void)pic;
    (void)wParam;
    (void)lParam;
    if (pfEaten) *pfEaten = FALSE;
    return S_OK;
}

STDMETHODIMP CVieLotusTIP::OnPreservedKey(ITfContext *pic, REFGUID rguid, BOOL *pfEaten) {
    (void)pic;
    (void)rguid;
    if (pfEaten) *pfEaten = FALSE;
    return S_OK;
}

STDMETHODIMP CVieLotusTIP::OnInitDocumentMgr(ITfDocumentMgr *pdim) {
    (void)pdim;
    return S_OK;
}

STDMETHODIMP CVieLotusTIP::OnUninitDocumentMgr(ITfDocumentMgr *pdim) {
    (void)pdim;
    return S_OK;
}

STDMETHODIMP CVieLotusTIP::OnSetFocus(ITfDocumentMgr *pdimFocus, ITfDocumentMgr *pdimPrevFocus) {
    (void)pdimFocus;
    (void)pdimPrevFocus;
    ReloadUserPreferences();
    SyncActiveLanguageProfile();
    ResetComposingSession();
    return S_OK;
}

STDMETHODIMP CVieLotusTIP::OnPushContext(ITfContext *pic) {
    (void)pic;
    return S_OK;
}

STDMETHODIMP CVieLotusTIP::OnPopContext(ITfContext *pic) {
    (void)pic;
    return S_OK;
}

STDMETHODIMP CVieLotusTIP::OnCompositionTerminated(TfEditCookie ecWrite, ITfComposition *pComposition) {
    (void)ecWrite;
    if (m_pComposition == pComposition) {
        m_pComposition->Release();
        m_pComposition = nullptr;
    }
    return S_OK;
}
