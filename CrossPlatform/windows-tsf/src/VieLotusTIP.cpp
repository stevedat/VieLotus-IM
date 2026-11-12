#include "VieLotusTIP.h"
#include "EditSession.h"
#include "Register.h"
#include <shellapi.h>
#include <vector>

#define VI_LANGID 0x042A
#define EN_US_LANGID 0x0409

#ifndef TF_PROFILETYPE_INPUTPROCESSOR
#define TF_PROFILETYPE_INPUTPROCESSOR 1
#endif
#ifndef TF_IPPMF_FORPROCESS
#define TF_IPPMF_FORPROCESS 0x10000000
#endif
#ifndef TF_IPPMF_FORSESSION
#define TF_IPPMF_FORSESSION 0x20000000
#endif
#ifndef TF_IPPMF_ENABLEPROFILE
#define TF_IPPMF_ENABLEPROFILE 0x00000002
#endif
#ifndef TF_ES_SYNC
#define TF_ES_SYNC 0x00000001
#endif
#ifndef TF_ES_READ
#define TF_ES_READ 0x00000002
#endif

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
    void (*append_context)(vielotus_session_t, const char *){nullptr};
    void (*sync_armed_word)(vielotus_session_t, const char *){nullptr};

    VieLotusCApi() {
#if defined(VIELOTUS_EMBEDDED_ENGINE)
        // Always use the statically embedded WindowsNativeEngine so a stale VieLotusCAPI.dll on disk can never override it.
        return;
#else
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
        append_context = reinterpret_cast<decltype(append_context)>(GetProcAddress(hModule, "vielotus_append_context"));
        sync_armed_word = reinterpret_cast<decltype(sync_armed_word)>(GetProcAddress(hModule, "vielotus_sync_armed_word"));

        isValid = create_session && destroy_session && reset_session &&
                  set_input_method && set_grammar_profile && set_smart_bilingual &&
                  set_modern_orthography && feed_char && feed_backspace &&
                  commit_word && get_last_backspaces && get_last_text && is_composing;
#endif
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

static std::wstring GetCurrentHostExeLowerName() {
    WCHAR exePath[MAX_PATH] = {0};
    if (GetModuleFileNameW(nullptr, exePath, MAX_PATH) == 0) {
        return L"";
    }
    const WCHAR *base = exePath;
    for (const WCHAR *p = exePath; *p; ++p) {
        if (*p == L'\\' || *p == L'/') {
            base = p + 1;
        }
    }
    std::wstring lowerName(base);
    for (WCHAR &ch : lowerName) {
        if (ch >= L'A' && ch <= L'Z') {
            ch = static_cast<WCHAR>(ch + (L'a' - L'A'));
        }
    }
    return lowerName;
}

static bool IsKnownRemoteDesktopExecutable(const std::wstring &lowerExe) {
    static const LPCWSTR kRemoteExes[] = {
        L"mstsc.exe",
        L"msrdc.exe",
        L"anydesk.exe",
        L"teamviewer.exe",
        L"rustdesk.exe",
        L"vmware-remotemks.exe",
        L"vmware-view.exe",
        L"parsec.exe",
        L"wfica32.exe"
    };
    for (LPCWSTR item : kRemoteExes) {
        if (lowerExe == item) {
            return true;
        }
    }
    return false;
}

static bool IsBareModifierOrToggleKey(WPARAM wParam) {
    switch (wParam) {
    case VK_SHIFT:
    case VK_LSHIFT:
    case VK_RSHIFT:
    case VK_CONTROL:
    case VK_LCONTROL:
    case VK_RCONTROL:
    case VK_MENU:
    case VK_LMENU:
    case VK_RMENU:
    case VK_LWIN:
    case VK_RWIN:
    case VK_CAPITAL:
    case VK_NUMLOCK:
    case VK_SCROLL:
        return true;
    default:
        return false;
    }
}

static bool IsNavigationOrLineBreakKey(WPARAM wParam) {
    if (wParam == VK_RETURN || wParam == VK_TAB || wParam == VK_ESCAPE ||
        wParam == VK_CLEAR || wParam == VK_INSERT || wParam == VK_DELETE) {
        return true;
    }
    if (wParam >= VK_PRIOR && wParam <= VK_DOWN) {
        return true;
    }
    if (wParam >= VK_F1 && wParam <= VK_F24) {
        return true;
    }
    return false;
}

static bool IsEngineBoundaryPunctuation(WCHAR ch) {
    if (ch == L' ' || ch == L'\t' || ch == L'\r' || ch == L'\n') {
        return true;
    }
    switch (ch) {
    case L',': case L';': case L':': case L'!': case L'?':
    case L'"': case L'\'': case L'(': case L')': case L'[':
    case L']': case L'{': case L'}': case L'<': case L'>':
    case L'-': case L'/': case L'\\': case L'.': case L'_':
        return true;
    default:
        return false;
    }
}

static bool IsPrintableNonAlphaVk(WPARAM wParam) {
    return wParam == VK_SPACE ||
           (wParam >= '0' && wParam <= '9') ||
           (wParam >= VK_NUMPAD0 && wParam <= VK_DIVIDE) ||
           (wParam >= VK_OEM_1 && wParam <= VK_OEM_3) ||
           (wParam >= VK_OEM_4 && wParam <= VK_OEM_8) ||
           wParam == VK_OEM_102;
}

enum class PassiveKeyKind {
    None,
    AsciiPrintable,
    NonAsciiOrDeadKey
};

static HKL GetUsQwertyHkl() {
    static HKL s_hklUs = nullptr;
    if (!s_hklUs) {
        s_hklUs = LoadKeyboardLayoutW(L"00000409", KLF_NOTELLSHELL);
        if (!s_hklUs) {
            s_hklUs = reinterpret_cast<HKL>(static_cast<ULONG_PTR>(0x04090409));
        }
    }
    return s_hklUs;
}

static bool IsCurrentThreadLegacyVntcHkl() {
    const uintptr_t hkl = reinterpret_cast<uintptr_t>(GetKeyboardLayout(0));
    return (((hkl >> 16) & 0xFFFFu) == 0x042Au);
}

static PassiveKeyKind TranslatePassiveKey(WPARAM wParam, LPARAM lParam, WCHAR &outCh) {
    outCh = 0;
    if (wParam == VK_SPACE) {
        outCh = L' ';
        return PassiveKeyKind::AsciiPrintable;
    }
    BYTE keyState[256];
    if (!GetKeyboardState(keyState)) {
        return PassiveKeyKind::None;
    }
    WCHAR chBuf[4] = {0};
    // Flag 0x04 (Windows 10 1607+): inspect character using US QWERTY layout (00000409)
    // so legacy KBDVNTC.DLL (0x042A042A) never maps '1'..'0' or '['/']' to 'ă','â','ê','đ','ư','ơ'.
    int res = ToUnicodeEx(static_cast<UINT>(wParam), (HIWORD(lParam) & 0xFF), keyState, chBuf, 4, 0x04, GetUsQwertyHkl());
    if (res == 1 && chBuf[0] >= 32 && chBuf[0] <= 126) {
        outCh = chBuf[0];
        return PassiveKeyKind::AsciiPrintable;
    }
    if (res < 0 || (res >= 1 && chBuf[0] > 126)) {
        return PassiveKeyKind::NonAsciiOrDeadKey;
    }
    return PassiveKeyKind::None;
}

CVieLotusTIP::CVieLotusTIP() {
    DllAddRef();
    m_currentExeName = GetCurrentHostExeLowerName();
    m_isRemoteProcess = IsKnownRemoteDesktopExecutable(m_currentExeName);
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
    } else if (IsEqualIID(riid, IID_ITfActiveLanguageProfileNotifySink)) {
        *ppvObj = static_cast<ITfActiveLanguageProfileNotifySink *>(this);
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

void CVieLotusTIP::ApplyVniMode(bool isVni, bool persistToRegistry) {
    bool changed = (m_isVniMode != isVni);
    m_isVniMode = isVni;
    if (persistToRegistry) {
        SavePersistedVniPreference(m_isVniMode);
    }

#if defined(VIELOTUS_EMBEDDED_ENGINE)
    m_nativeEngine.setInputMethod(m_isVniMode ? vielotus_win::InputMethod::VNI : vielotus_win::InputMethod::Telex);
    if (changed) {
        m_nativeEngine.reset();
    }
#endif

    const auto &api = GetCApi();
    if (api.isValid && m_session) {
        api.set_input_method(m_session, m_isVniMode ? VIELOTUS_INPUT_VNI : VIELOTUS_INPUT_TELEX);
        if (changed) {
            api.reset_session(m_session);
            if (api.append_context) {
                api.append_context(m_session, "");
            }
        }
    }
}

void CVieLotusTIP::ReloadUserPreferences() {
    m_lastPrefsRevision = GetLocalPrefsRevision();
    VieLotusWindowsPrefs prefs{};
    LoadVieLotusPrefs(prefs);
    m_isVniMode = prefs.isVni;

    bool perAppBypass = false;
    bool hasPerAppPref = LoadPerAppBypassPreference(m_currentExeName.c_str(), perAppBypass);
    if (m_hasManualProcessOverride) {
        m_isVietnameseMode = m_manualProcessVietnameseMode;
    } else if (hasPerAppPref) {
        m_isVietnameseMode = perAppBypass ? false : prefs.vietnameseEnabled;
    } else if (m_isRemoteProcess && prefs.autoBypassRemoteApps) {
        m_isVietnameseMode = false;
    } else {
        m_isVietnameseMode = prefs.vietnameseEnabled;
    }

#if defined(VIELOTUS_EMBEDDED_ENGINE)
    m_nativeEngine.setInputMethod(m_isVniMode ? vielotus_win::InputMethod::VNI : vielotus_win::InputMethod::Telex);
    m_nativeEngine.setGrammarProfile(prefs.senFlex ? 1 : 0);
    m_nativeEngine.setSmartBilingual(prefs.smartBilingual);
    m_nativeEngine.setModernOrthography(prefs.modernOrthography);
    m_nativeEngine.setQuickTelex(prefs.quickTelex);
    m_nativeEngine.setRelaxedCoda(prefs.relaxedCoda);
    m_nativeEngine.setMacroEnabled(prefs.macroEnabled);
#endif

    const auto &api = GetCApi();
    if (api.isValid && m_session) {
        api.set_input_method(m_session, m_isVniMode ? VIELOTUS_INPUT_VNI : VIELOTUS_INPUT_TELEX);
        api.set_grammar_profile(m_session, prefs.senFlex ? VIELOTUS_GRAMMAR_SEN_FLEX : VIELOTUS_GRAMMAR_CLASSIC);
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
            api.set_grammar_profile(m_session, prefs.senFlex ? VIELOTUS_GRAMMAR_SEN_FLEX : VIELOTUS_GRAMMAR_CLASSIC);
            api.set_smart_bilingual(m_session, prefs.smartBilingual);
            api.set_modern_orthography(m_session, prefs.modernOrthography);
        }
    }
    SyncActiveLanguageProfile();
}

void CVieLotusTIP::SyncActiveLanguageProfile() {
    if (m_inProfileSync) {
        return;
    }
    m_inProfileSync = true;

    bool desiredVni = m_isVniMode;
    LoadPersistedVniPreference(desiredVni);
    if (m_isVniMode != desiredVni) {
        ApplyVniMode(desiredVni, false);
    }

    ITfInputProcessorProfiles *pProfiles = nullptr;
    if (FAILED(CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr, CLSCTX_INPROC_SERVER, IID_ITfInputProcessorProfiles, reinterpret_cast<void **>(&pProfiles))) || !pProfiles) {
        m_inProfileSync = false;
        return;
    }

    ITfInputProcessorProfileMgr *pProfileMgr = nullptr;
    pProfiles->QueryInterface(IID_ITfInputProcessorProfileMgr, reinterpret_cast<void **>(&pProfileMgr));

    // Consume legacy flag if set
    bool unusedOverride = false;
    ConsumeSettingsVniOverride(unusedOverride);

    // Check if the current thread's active TSF profile already matches the user's persisted preference
    bool activeMatchesDesired = false;
    if (pProfileMgr) {
        TF_INPUTPROCESSORPROFILE activeProfile{};
        if (SUCCEEDED(pProfileMgr->GetActiveProfile(GUID_TFCAT_TIP_KEYBOARD, &activeProfile)) &&
            IsEqualCLSID(activeProfile.clsid, CLSID_VieLotusTIP)) {
            const GUID &expectedGuid = desiredVni ? GUID_VieLotusProfileVNI : GUID_VieLotusProfile;
            if (IsEqualGUID(activeProfile.guidProfile, expectedGuid)) {
                activeMatchesDesired = true;
            }
        }
    }

    if (!activeMatchesDesired) {
        const GUID &targetGuid = desiredVni ? GUID_VieLotusProfileVNI : GUID_VieLotusProfile;
        pProfiles->SetDefaultLanguageProfile(VI_LANGID, CLSID_VieLotusTIP, targetGuid);
        pProfiles->ActivateLanguageProfile(CLSID_VieLotusTIP, VI_LANGID, targetGuid);
        if (pProfileMgr) {
            pProfileMgr->ActivateProfile(
                TF_PROFILETYPE_INPUTPROCESSOR,
                VI_LANGID,
                CLSID_VieLotusTIP,
                targetGuid,
                nullptr,
                TF_IPPMF_FORSESSION | TF_IPPMF_FORPROCESS | TF_IPPMF_ENABLEPROFILE | 0x00000004
            );
        }
    }

    if (pProfileMgr) {
        pProfileMgr->Release();
    }
    pProfiles->Release();
    m_inProfileSync = false;
}

void CVieLotusTIP::ResetComposingSession() {
    m_lastWin32EditHwnd = nullptr;
    m_lastWin32EditCaret = 0xFFFFFFFFu;
#if defined(VIELOTUS_EMBEDDED_ENGINE)
    m_nativeEngine.reset();
#endif
    const auto &api = GetCApi();
    if (m_session && api.isValid) {
        api.reset_session(m_session);
        if (api.append_context) {
            api.append_context(m_session, "");
        }
    }
}

void CVieLotusTIP::ClearWordStateSession() {
    m_lastWin32EditHwnd = nullptr;
    m_lastWin32EditCaret = 0xFFFFFFFFu;
#if defined(VIELOTUS_EMBEDDED_ENGINE)
    m_nativeEngine.clearWordState();
#endif
    const auto &api = GetCApi();
    if (m_session && api.isValid) {
        api.reset_session(m_session);
    }
}

void CVieLotusTIP::SyncSurroundingContextSession(const std::wstring &precedingText) {
    if (precedingText.empty()) {
        return;
    }
    int utf8Len = WideCharToMultiByte(CP_UTF8, 0, precedingText.data(), static_cast<int>(precedingText.size()), nullptr, 0, nullptr, nullptr);
    if (utf8Len <= 0) {
        return;
    }
    std::string utf8Buf(static_cast<size_t>(utf8Len), '\0');
    WideCharToMultiByte(CP_UTF8, 0, precedingText.data(), static_cast<int>(precedingText.size()), &utf8Buf[0], utf8Len, nullptr, nullptr);
#if defined(VIELOTUS_EMBEDDED_ENGINE)
    m_nativeEngine.syncSurroundingContext(utf8Buf.c_str());
#endif
    const auto &api = GetCApi();
    if (m_session && api.isValid && api.sync_armed_word) {
        api.sync_armed_word(m_session, utf8Buf.c_str());
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

bool CVieLotusTIP::HasActiveWordSession() const {
    const auto &api = GetCApi();
    if (m_session && api.isValid) {
        return api.is_composing(m_session);
    }
#if defined(VIELOTUS_EMBEDDED_ENGINE)
    return m_nativeEngine.hasActiveWord();
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

int32_t CVieLotusTIP::GetLastCommitDiffBackspacesSession() const {
    const auto &api = GetCApi();
    if (m_session && api.isValid) {
        return api.get_last_backspaces(m_session);
    }
#if defined(VIELOTUS_EMBEDDED_ENGINE)
    return m_nativeEngine.getLastCommitDiffBackspaces();
#else
    return 0;
#endif
}

const char *CVieLotusTIP::GetLastCommitDiffTextSession() const {
    const auto &api = GetCApi();
    if (m_session && api.isValid) {
        return api.get_last_text(m_session);
    }
#if defined(VIELOTUS_EMBEDDED_ENGINE)
    return m_nativeEngine.getLastCommitDiffTextUtf8();
#else
    return "";
#endif
}

void CVieLotusTIP::ReleaseCompositionRefs() {
    if (m_pComposition) {
        m_pComposition->Release();
        m_pComposition = nullptr;
    }
    if (m_pCompositionContext) {
        m_pCompositionContext->Release();
        m_pCompositionContext = nullptr;
    }
}

namespace {

bool IsClassicWin32EditControl(HWND hwnd) {
    if (!hwnd || !IsWindow(hwnd)) return false;
    WCHAR clsName[64] = {0};
    if (GetClassNameW(hwnd, clsName, 64) <= 0) return false;
    return _wcsicmp(clsName, L"edit") == 0;
}

} // namespace

void CVieLotusTIP::SyncWin32EditCaretBeforeKey() {
    if (!IsComposingSession() && !HasActiveWordSession()) {
        return;
    }
    HWND hFocus = GetFocus();
    if (!IsClassicWin32EditControl(hFocus)) {
        return;
    }
    DWORD dwStart = 0, dwEnd = 0;
    SendMessageW(hFocus, EM_GETSEL, reinterpret_cast<WPARAM>(&dwStart), reinterpret_cast<LPARAM>(&dwEnd));
    if (dwStart != dwEnd ||
        (m_lastWin32EditHwnd == hFocus &&
         m_lastWin32EditCaret != 0xFFFFFFFFu &&
         dwStart != m_lastWin32EditCaret)) {
        ResetComposingSession();
    }
}

bool CVieLotusTIP::TryRehydrateWin32EditBeforeFeed(uint32_t codePoint) {
#if defined(VIELOTUS_EMBEDDED_ENGINE)
    if (HasActiveWordSession() || m_session != nullptr) {
        return false;
    }
    HWND hFocus = GetFocus();
    if (!IsClassicWin32EditControl(hFocus)) {
        return false;
    }
    DWORD dwStart = 0, dwEnd = 0;
    SendMessageW(hFocus, EM_GETSEL, reinterpret_cast<WPARAM>(&dwStart), reinterpret_cast<LPARAM>(&dwEnd));
    if (dwStart != dwEnd || dwStart == 0 || dwStart > 2048) {
        return false;
    }

    WCHAR buf[2052] = {0};
    LRESULT copied = SendMessageW(hFocus, WM_GETTEXT, static_cast<WPARAM>(dwStart + 2), reinterpret_cast<LPARAM>(buf));
    if (copied < static_cast<LRESULT>(dwStart)) {
        return false;
    }

    const WCHAR prevImmediate = buf[dwStart - 1];
    if ((prevImmediate >= L'0' && prevImmediate <= L'9') ||
        prevImmediate == L'/' || prevImmediate == L'_' || prevImmediate == L'\\') {
        const DWORD sliceStart = (dwStart > 32) ? (dwStart - 32) : 0;
        std::wstring slice(buf + sliceStart, buf + dwStart);
        SyncSurroundingContextSession(slice);
        return false;
    }

    const WCHAR chAfter = buf[dwStart];
    const bool boundaryAfter =
        (chAfter == L'\0' || chAfter == L' ' || chAfter == L'\t' ||
         chAfter == L'\r' || chAfter == L'\n' || chAfter == L'.' ||
         chAfter == L',' || chAfter == L'!' || chAfter == L'?' ||
         chAfter == L';' || chAfter == L':' || chAfter == L')' ||
         chAfter == L']' || chAfter == L'}');
    if (!boundaryAfter) {
        return false;
    }

    DWORD tokStart = dwStart;
    while (tokStart > 0 && (dwStart - tokStart) < 8) {
        WCHAR c = buf[tokStart - 1];
        if ((c >= L'a' && c <= L'z') || (c >= L'A' && c <= L'Z') || c > 0x7F) {
            --tokStart;
        } else {
            break;
        }
    }
    const int wordLen = static_cast<int>(dwStart - tokStart);
    if (wordLen < 1 || wordLen > 6) {
        return false;
    }
    if (tokStart > 0) {
        const WCHAR prevCh = buf[tokStart - 1];
        const bool cleanBefore =
            (prevCh == L' ' || prevCh == L'\t' || prevCh == L'\r' || prevCh == L'\n' ||
             prevCh == L'(' || prevCh == L'[' || prevCh == L'{' || prevCh == L'"' ||
             (prevCh >= L'0' && prevCh <= L'9'));
        if (!cleanBefore) {
            return false;
        }
    }
    return m_nativeEngine.tryRehydrateAndFeed(buf + tokStart, wordLen, codePoint);
#else
    (void)codePoint;
    return false;
#endif
}

void CVieLotusTIP::EndActiveComposition(ITfContext *pic) {
    if (!m_pComposition) {
        ReleaseCompositionRefs();
        return;
    }
    ITfContext *targetCtx = pic ? pic : m_pCompositionContext;
    if (!targetCtx) {
        ReleaseCompositionRefs();
        return;
    }
    targetCtx->AddRef();
    CEditSession *pEdit = new (std::nothrow) CEditSession(
        targetCtx,
        0,
        L"",
        true,
        false,
        &m_pComposition,
        &m_pCompositionContext,
        static_cast<ITfCompositionSink *>(this)
    );
    if (pEdit) {
        HRESULT hrSession = S_OK;
        HRESULT hrReq = targetCtx->RequestEditSession(m_tfClientId, pEdit, TF_ES_ASYNCDONTCARE | TF_ES_READWRITE, &hrSession);
        if (FAILED(hrReq) || FAILED(hrSession)) {
            ReleaseCompositionRefs();
        }
        pEdit->Release();
    } else {
        ReleaseCompositionRefs();
    }
    targetCtx->Release();
}

void CVieLotusTIP::ExecuteEditSession(ITfContext *pic, int32_t backspaces, const std::wstring &text, bool bCommit) {
    m_lastEditShifted = 0;
    m_lastEditSetTextHr = S_OK;
    if (!pic) return;

    HWND hFocus = GetFocus();
    if (IsClassicWin32EditControl(hFocus)) {
        if (m_pComposition) {
            EndActiveComposition(pic);
        }
        DWORD dwStart = 0, dwEnd = 0;
        SendMessageW(hFocus, EM_GETSEL, reinterpret_cast<WPARAM>(&dwStart), reinterpret_cast<LPARAM>(&dwEnd));
        if (dwStart < dwEnd) {
            SendMessageW(hFocus, EM_REPLACESEL, TRUE, reinterpret_cast<LPARAM>(text.c_str()));
            m_lastEditShifted = 0;
            m_lastEditSetTextHr = S_OK;
        } else {
            const DWORD reqBs = (backspaces > 0) ? static_cast<DWORD>(backspaces) : 0;
            const DWORD bsToApply = (dwStart >= reqBs) ? reqBs : dwStart;
            if (bsToApply > 0) {
                SendMessageW(
                    hFocus,
                    EM_SETSEL,
                    static_cast<WPARAM>(dwStart - bsToApply),
                    static_cast<LPARAM>(dwEnd)
                );
            }
            if (bsToApply > 0 || !text.empty()) {
                SendMessageW(hFocus, EM_REPLACESEL, TRUE, reinterpret_cast<LPARAM>(text.c_str()));
            }
            m_lastEditShifted = -static_cast<LONG>(bsToApply);
            m_lastEditSetTextHr = S_OK;
        }
        DWORD afterStart = 0, afterEnd = 0;
        SendMessageW(hFocus, EM_GETSEL, reinterpret_cast<WPARAM>(&afterStart), reinterpret_cast<LPARAM>(&afterEnd));
        m_lastWin32EditHwnd = hFocus;
        m_lastWin32EditCaret = (afterStart == afterEnd) ? afterStart : 0xFFFFFFFFu;
        return;
    }

    const bool keepComposition = !bCommit && HasActiveWordSession();
    CEditSession *pEdit = new (std::nothrow) CEditSession(
        pic,
        backspaces,
        text,
        bCommit,
        keepComposition,
        &m_pComposition,
        &m_pCompositionContext,
        static_cast<ITfCompositionSink *>(this)
    );
    if (!pEdit) return;
    HRESULT hrSession = S_OK;
    HRESULT hrReq = pic->RequestEditSession(m_tfClientId, pEdit, TF_ES_ASYNCDONTCARE | TF_ES_READWRITE, &hrSession);
    if (SUCCEEDED(hrReq) && pEdit->WasExecuted()) {
        m_lastEditShifted = pEdit->GetActualShifted();
        m_lastEditSetTextHr = pEdit->GetSetTextHr();
    } else if (FAILED(hrReq)) {
        m_lastEditSetTextHr = hrReq;
    } else {
        m_lastEditSetTextHr = hrSession;
    }
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
    ReleaseCompositionRefs();
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

    // 2. Advise ThreadMgrEventSink & ActiveLanguageProfileNotifySink
    ITfSource *pSource = nullptr;
    if (SUCCEEDED(m_pThreadMgr->QueryInterface(IID_ITfSource, reinterpret_cast<void **>(&pSource)))) {
        pSource->AdviseSink(IID_ITfThreadMgrEventSink, static_cast<ITfThreadMgrEventSink *>(this), &m_dwThreadMgrEventSinkCookie);
        pSource->AdviseSink(IID_ITfActiveLanguageProfileNotifySink, static_cast<ITfActiveLanguageProfileNotifySink *>(this), &m_dwProfileNotifySinkCookie);
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

    // 2. Unadvise ThreadMgrEventSink & ActiveLanguageProfileNotifySink
    ITfSource *pSource = nullptr;
    if (SUCCEEDED(m_pThreadMgr->QueryInterface(IID_ITfSource, reinterpret_cast<void **>(&pSource)))) {
        if (m_dwThreadMgrEventSinkCookie != TF_INVALID_COOKIE) {
            pSource->UnadviseSink(m_dwThreadMgrEventSinkCookie);
            m_dwThreadMgrEventSinkCookie = TF_INVALID_COOKIE;
        }
        if (m_dwProfileNotifySinkCookie != TF_INVALID_COOKIE) {
            pSource->UnadviseSink(m_dwProfileNotifySinkCookie);
            m_dwProfileNotifySinkCookie = TF_INVALID_COOKIE;
        }
        pSource->Release();
    }

    CleanSession();

    m_pThreadMgr->Release();
    m_pThreadMgr = nullptr;
    m_tfClientId = TF_CLIENTID_NULL;

    return S_OK;
}

STDMETHODIMP CVieLotusTIP::OnSetFocus(BOOL fForeground) {
    if (fForeground) {
        ReloadUserPreferences();
        SyncActiveLanguageProfile();
    }
    ReleaseCompositionRefs();
    ResetComposingSession();
    return S_OK;
}

STDMETHODIMP CVieLotusTIP::OnTestKeyDown(ITfContext *pic, WPARAM wParam, LPARAM lParam, BOOL *pfEaten) {
    if (!pfEaten) return E_POINTER;
    *pfEaten = FALSE;

    const bool hasCtrl = (GetKeyState(VK_CONTROL) & 0x8000) != 0;
    const bool hasShift = (GetKeyState(VK_SHIFT) & 0x8000) != 0;
    const bool hasAlt = (GetKeyState(VK_MENU) & 0x8000) != 0;
    const bool hasWin = ((GetKeyState(VK_LWIN) & 0x8000) != 0) || ((GetKeyState(VK_RWIN) & 0x8000) != 0);

    // Hotkey: Ctrl + Shift + S -> Open Sen Viet Settings Window
    if (wParam == 'S' && hasCtrl && hasShift && !hasAlt && !hasWin) {
        *pfEaten = TRUE;
        return S_OK;
    }

    // Hotkey toggle: Ctrl + Space / Shift + Space (handled even when m_isVietnameseMode is false)
    if (wParam == VK_SPACE && (hasCtrl || hasShift) && !hasAlt && !hasWin) {
        *pfEaten = TRUE;
        return S_OK;
    }

    if (!m_isVietnameseMode) return S_OK;

    // Bare modifier / lock keys (Shift, Ctrl, Alt, Win, CapsLock, NumLock, ScrollLock) -> touch nothing
    if (IsBareModifierOrToggleKey(wParam)) {
        return S_OK;
    }

    // Modifier combinations (Ctrl, Alt, Win) -> never eat (avoid VK_PROCESSKEY), sync session/context
    if (hasCtrl || hasAlt || hasWin) {
        const bool isPlainCtrl = hasCtrl && !hasAlt && !hasWin;
        if (isPlainCtrl && (wParam == 'A' || wParam == 'V' || wParam == 'X' ||
                            wParam == 'Z' || wParam == 'Y' || wParam == 'L')) {
            ResetComposingSession();
        } else if (!isPlainCtrl && !hasCtrl) {
            ResetComposingSession();
        } else {
            // AltGr (Ctrl+Alt+<key>) or non-destructive Ctrl+<key> (e.g. Ctrl+C, Ctrl+S):
            // end current composing word while preserving sentence context.
            ClearWordStateSession();
        }
        EndActiveComposition(pic);
        return S_OK;
    }

    // Navigation / Enter / Tab / Escape / Delete / Insert / Function keys -> never eat, reset full session & context
    if (IsNavigationOrLineBreakKey(wParam)) {
        ResetComposingSession();
        EndActiveComposition(pic);
        return S_OK;
    }

    SyncWin32EditCaretBeforeKey();

    const bool isComposing = IsComposingSession();
    const bool hasActiveWord = HasActiveWordSession();

    // Backspace: eat when composing (including post-space re-arm); passively clear delimiter flags when idle
    if (wParam == VK_BACK) {
        if (isComposing) {
            *pfEaten = TRUE;
        } else {
            ClearWordStateSession();
            EndActiveComposition(pic);
            FeedCharSession(static_cast<uint32_t>(L' '));
        }
        return S_OK;
    }

    // Eat candidate alphabetic typing keys
    // Note: Profile synchronization runs on focus change (`OnSetFocus`) and taskbar switch (`OnActivated`),
    // never on the keystroke path (`OnTestKeyDown`), avoiding Registry and COM overhead during typing.
    if (wParam >= 'A' && wParam <= 'Z') {
        *pfEaten = TRUE;
        return S_OK;
    }

    // Printable non-alphabetic keys (Space, '0'..'9', shifted symbols '!'..')', OEM punctuation, Numpad)
    if (IsPrintableNonAlphaVk(wParam)) {
        WCHAR ch = 0;
        const PassiveKeyKind kind = TranslatePassiveKey(wParam, lParam, ch);
        if (kind == PassiveKeyKind::AsciiPrintable) {
            if ((ch >= L'a' && ch <= L'z') || (ch >= L'A' && ch <= L'Z')) {
                *pfEaten = TRUE;
                return S_OK;
            }
            // If the current thread's HKL still uses legacy KBDVNTC.DLL (0x042A042A),
            // eat all non-space printable ASCII keys so Windows TranslateMessage never maps
            // '1'..'0' or '['/']'/'=' to 'ă','â','ê','ô','̀','̉','̃','́','̣','đ','ư','ơ','₫'.
            if (wParam != VK_SPACE && IsCurrentThreadLegacyVntcHkl()) {
                *pfEaten = TRUE;
                return S_OK;
            }
            if (hasActiveWord) {
                const bool isVniDigit = m_isVniMode && (ch >= L'0' && ch <= L'9');
                const bool isBoundary = IsEngineBoundaryPunctuation(ch);
                if (isVniDigit || isBoundary || m_session != nullptr) {
                    *pfEaten = TRUE;
                    return S_OK;
                }
                // Non-boundary symbol/digit in Telex mode (e.g. '2' in "v2", '@' in "user@"):
                // passively clear word state & update m_afterDigit without eating the keystroke.
                FeedCharSession(static_cast<uint32_t>(ch));
                EndActiveComposition(pic);
                return S_OK;
            }
            // Idle (!hasActiveWord): if in VNI mode on a classic Win32 Edit control, eat VNI digits '0'..'9'
            // so OnKeyDown can attempt post-navigation word rehydration (or insert the literal digit).
            if (m_isVniMode && (ch >= L'0' && ch <= L'9') && IsClassicWin32EditControl(GetFocus())) {
                *pfEaten = TRUE;
                return S_OK;
            }
            // Otherwise passively track leading '/', digits '0'..'9', and tech delimiters '_', '\'
            // while leaving *pfEaten = FALSE so the host app receives the native key event untouched.
            FeedCharSession(static_cast<uint32_t>(ch));
            return S_OK;
        } else if (kind == PassiveKeyKind::NonAsciiOrDeadKey && hasActiveWord) {
            ClearWordStateSession();
            EndActiveComposition(pic);
            return S_OK;
        }
    }

    return S_OK;
}

STDMETHODIMP CVieLotusTIP::OnKeyDown(ITfContext *pic, WPARAM wParam, LPARAM lParam, BOOL *pfEaten) {
    if (!pfEaten) return E_POINTER;
    *pfEaten = FALSE;

    if (!pic) return S_OK;


    const bool hasCtrl = (GetKeyState(VK_CONTROL) & 0x8000) != 0;
    const bool hasShift = (GetKeyState(VK_SHIFT) & 0x8000) != 0;
    const bool hasAlt = (GetKeyState(VK_MENU) & 0x8000) != 0;
    const bool hasWin = ((GetKeyState(VK_LWIN) & 0x8000) != 0) || ((GetKeyState(VK_RWIN) & 0x8000) != 0);

    // Hotkey: Ctrl + Shift + S -> Open Sen Viet Settings Window
    if (wParam == 'S' && hasCtrl && hasShift && !hasAlt && !hasWin) {
        ResetComposingSession();
        EndActiveComposition(pic);
        HWND hExisting = FindWindowW(L"VieLotusBentoSettingsWndClass", nullptr);
        if (hExisting && IsWindow(hExisting)) {
            ShowWindow(hExisting, SW_SHOW);
            ShowWindow(hExisting, SW_RESTORE);
            SetForegroundWindow(hExisting);
            PostMessageW(hExisting, WM_USER + 101, 0, 0);
        } else {
            WCHAR settingsExe[MAX_PATH] = {};
            if (ExpandEnvironmentStringsW(L"%ProgramW6432%\\VieLotusIM\\VieLotusSettings.exe", settingsExe, MAX_PATH) > 0 &&
                GetFileAttributesW(settingsExe) != INVALID_FILE_ATTRIBUTES) {
                ShellExecuteW(nullptr, L"open", settingsExe, L"--settings", nullptr, SW_SHOWNORMAL);
            } else {
                ShowVieLotusSettingsDialog(GetForegroundWindow(), false);
            }
        }
        ReloadUserPreferences();
        *pfEaten = TRUE;
        return S_OK;
    }

    // Hotkey toggle: Ctrl + Space / Shift + Space
    if (wParam == VK_SPACE && (hasCtrl || hasShift) && !hasAlt && !hasWin) {
        m_isVietnameseMode = !m_isVietnameseMode;
        m_hasManualProcessOverride = true;
        m_manualProcessVietnameseMode = m_isVietnameseMode;
        VieLotusWindowsPrefs prefs{};
        LoadVieLotusPrefs(prefs);
        bool existingPerAppBypass = false;
        if (m_isRemoteProcess || LoadPerAppBypassPreference(m_currentExeName.c_str(), existingPerAppBypass)) {
            SavePerAppBypassPreference(m_currentExeName.c_str(), !m_isVietnameseMode);
        } else {
            prefs.vietnameseEnabled = m_isVietnameseMode;
            SaveVieLotusPrefs(prefs);
        }
        ResetComposingSession();
        EndActiveComposition(pic);
        *pfEaten = TRUE;
        return S_OK;
    }

    if (!m_isVietnameseMode) return S_OK;

    if (GetLocalPrefsRevision() != m_lastPrefsRevision) {
        ReloadUserPreferences();
        if (!m_isVietnameseMode) {
            EndActiveComposition(pic);
            return S_OK;
        }
    }

    if (IsBareModifierOrToggleKey(wParam)) {
        return S_OK;
    }

    // Modifiers -> sync session/context and pass through
    if (hasCtrl || hasAlt || hasWin) {
        const bool isPlainCtrl = hasCtrl && !hasAlt && !hasWin;
        if (isPlainCtrl && (wParam == 'A' || wParam == 'V' || wParam == 'X' ||
                            wParam == 'Z' || wParam == 'Y' || wParam == 'L')) {
            ResetComposingSession();
        } else if (!isPlainCtrl && !hasCtrl) {
            ResetComposingSession();
        } else {
            ClearWordStateSession();
        }
        EndActiveComposition(pic);
        return S_OK;
    }

    SyncWin32EditCaretBeforeKey();

    // Backspace handling
    if (wParam == VK_BACK) {
        if (IsComposingSession()) {
            int32_t action = FeedBackspaceSession();
            if (action == VIELOTUS_ACTION_RESET) {
                ClearWordStateSession();
                ExecuteEditSession(pic, 1, L"", false);
                *pfEaten = TRUE;
            } else {
                int32_t bs = GetLastBackspacesSession();
                const char *replacement = GetLastTextSession();
                std::wstring wText = Utf8ToWide(replacement);
                ExecuteEditSession(pic, bs, wText, false);
                if (bs > 0 && wText.empty() && m_lastEditShifted == 0) {
                    ClearWordStateSession();
                    *pfEaten = FALSE;
                } else {
                    *pfEaten = TRUE;
                }
            }
            return S_OK;
        }
        return S_OK;
    }

    // Navigation / Enter / Escape / Tab / Delete / Function keys -> reset full session and let host process key
    if (IsNavigationOrLineBreakKey(wParam)) {
        ResetComposingSession();
        EndActiveComposition(pic);
        return S_OK;
    }

    // Translate virtual key to character using standard US QWERTY (00000409)
    // so legacy KBDVNTC.DLL (0x042A042A) never turns '1'..'0' or '['/']' into 'ă','â','ê','đ','ư','ơ'.
    BYTE keyState[256];
    if (!GetKeyboardState(keyState)) {
        return S_OK;
    }
    WCHAR chBuf[4] = {0};
    int toAsciiRes = ToUnicodeEx(static_cast<UINT>(wParam), HIWORD(lParam) & 0xFF, keyState, chBuf, 4, 0, GetUsQwertyHkl());

    if (toAsciiRes == 1 && chBuf[0] >= 32 && chBuf[0] <= 126) {
        uint32_t codePoint = static_cast<uint32_t>(chBuf[0]);
        int32_t action = TryRehydrateWin32EditBeforeFeed(codePoint)
            ? VIELOTUS_ACTION_REPLACE
            : FeedCharSession(codePoint);

        if (action == VIELOTUS_ACTION_COMMIT) {
            const char *committed = GetLastCommitDiffTextSession();
            int32_t bs = GetLastCommitDiffBackspacesSession();
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
            ExecuteEditSession(pic, 0, wText, !IsComposingSession());
            *pfEaten = TRUE;
            return S_OK;
        }
    } else if (toAsciiRes > 0) {
        // Non-ASCII character produced by an eaten key (e.g. non-Latin keyboard layout on 'A'..'Z'):
        // clear Vietnamese word state and insert the translated UTF-16 sequence so the character is never swallowed.
        ClearWordStateSession();
        std::wstring wText(chBuf, static_cast<size_t>(toAsciiRes));
        ExecuteEditSession(pic, 0, wText, true);
        *pfEaten = TRUE;
        return S_OK;
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
    if (pdimFocus != nullptr && pdimFocus == pdimPrevFocus) {
        return S_OK;
    }
    if (pdimFocus != nullptr && GetLocalPrefsRevision() != m_lastPrefsRevision) {
        ReloadUserPreferences();
        SyncActiveLanguageProfile();
    }
    ReleaseCompositionRefs();
    ResetComposingSession();
    return S_OK;
}

STDMETHODIMP CVieLotusTIP::OnPushContext(ITfContext *pic) {
    (void)pic;
    ReleaseCompositionRefs();
    ResetComposingSession();
    return S_OK;
}

STDMETHODIMP CVieLotusTIP::OnPopContext(ITfContext *pic) {
    (void)pic;
    ReleaseCompositionRefs();
    ResetComposingSession();
    return S_OK;
}

STDMETHODIMP CVieLotusTIP::OnActivated(REFCLSID clsid, REFGUID guidProfile, BOOL fActivated) {
    if (fActivated && IsEqualCLSID(clsid, CLSID_VieLotusTIP)) {
        const bool persistChoice = !m_inProfileSync;
        if (IsEqualGUID(guidProfile, GUID_VieLotusProfileVNI)) {
            ApplyVniMode(true, persistChoice);
        } else if (IsEqualGUID(guidProfile, GUID_VieLotusProfile)) {
            ApplyVniMode(false, persistChoice);
        }
    }
    return S_OK;
}

STDMETHODIMP CVieLotusTIP::OnCompositionTerminated(TfEditCookie ecWrite, ITfComposition *pComposition) {
    (void)ecWrite;
    if (m_pComposition && (!pComposition || m_pComposition == pComposition)) {
        ReleaseCompositionRefs();
        ClearWordStateSession();
    }
    return S_OK;
}
