#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0A00
#endif

#include <windows.h>
#include <objidl.h>
#include <msctf.h>
#include <gdiplus.h>
#include <dwmapi.h>
#include <shellapi.h>
#include <sddl.h>
#include <strsafe.h>
#include <cstring>
#include <string>
#include <vector>

#include "SettingsUI.h"
#include "TsfGameGuardLogic.h"
#include "WinL10n.h"
#include "vielotus_win_installer.h"

#ifndef DWMWA_WINDOW_CORNER_PREFERENCE
#define DWMWA_WINDOW_CORNER_PREFERENCE 33
#endif

#ifndef PIPE_REJECT_REMOTE_CLIENTS
#define PIPE_REJECT_REMOTE_CLIENTS 0x00000008
#endif

#ifndef TF_PROFILETYPE_INPUTPROCESSOR
#define TF_PROFILETYPE_INPUTPROCESSOR 1
#endif
#ifndef TF_INVALID_COOKIE
#define TF_INVALID_COOKIE ((DWORD)(-1))
#endif

namespace {

using namespace Gdiplus;

static constexpr LANGID kViLangId = 0x042A;
static constexpr UINT_PTR kTimerIdSyncPrefs = 101;

// Must stay bit-for-bit identical to Globals.cpp CLSID_VieLotusTIP / GUID_VieLotusProfile*
static const GUID kClsidVieLotusTip = {
    0xc7b08e9d, 0x4762, 0x4c97, { 0x8b, 0x1f, 0x52, 0x21, 0x97, 0xa5, 0x98, 0xde }
};
static const GUID kGuidVieLotusProfileTelex = {
    0x8e2a7b44, 0x5a1f, 0x4b82, { 0x9b, 0x7c, 0x12, 0x34, 0x56, 0x78, 0x9a, 0xbc }
};
static const GUID kGuidVieLotusProfileVni = {
    0x8e2a7b45, 0x5a1f, 0x4b82, { 0x9b, 0x7c, 0x12, 0x34, 0x56, 0x78, 0x9a, 0xbc }
};

static HINSTANCE g_settingsInst{nullptr};

static const WCHAR c_szRunSubKey[] = L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
static const WCHAR c_szRunValueName[] = L"VieLotusIM";

static HINSTANCE ResolveSettingsInstance(HINSTANCE hInst) {
    if (hInst) return hInst;
    if (g_settingsInst) return g_settingsInst;
    return GetModuleHandleW(nullptr);
}

// ============================================================================
// Named Pipe Wake Server (allows AppContainer / LPAC TIP hosts to wake UI)
// ============================================================================

struct SettingsWakePipeServer {
    HWND targetHwnd{nullptr};
    HANDLE hStopEvent{nullptr};
    HANDLE hThread{nullptr};
};

static bool CreateSettingsWakeSecurityDescriptor(PSECURITY_DESCRIPTOR *outSd) {
    if (!outSd) return false;
    *outSd = nullptr;

    std::wstring userSidStr;
    HANDLE hToken = nullptr;
    if (OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &hToken) && hToken) {
        DWORD needed = 0;
        GetTokenInformation(hToken, TokenUser, nullptr, 0, &needed);
        if (needed > 0) {
            std::vector<BYTE> buf(needed);
            if (GetTokenInformation(hToken, TokenUser, buf.data(), needed, &needed)) {
                const TOKEN_USER *tu = reinterpret_cast<const TOKEN_USER *>(buf.data());
                LPWSTR rawSid = nullptr;
                if (tu->User.Sid && ConvertSidToStringSidW(tu->User.Sid, &rawSid) && rawSid) {
                    userSidStr = rawSid;
                    LocalFree(rawSid);
                }
            }
        }
        CloseHandle(hToken);
    }

    // DACL:
    //  - SY (LocalSystem), BA (Built-in Admins), and current User SID get Generic All (GA).
    //  - AC (S-1-15-2-1 ALL APPLICATION PACKAGES) and S-1-15-2-2 (ALL RESTRICTED APPLICATION PACKAGES)
    //    get write+read_attrs+read_control+synchronize ONLY (0x120082 — strictly omitting 0x0004
    //    FILE_CREATE_PIPE_INSTANCE so sandboxed clients cannot squat or spawn pipe instances).
    // SACL:
    //  - Low Mandatory Label (S:(ML;;NW;;;LW)) so Low-IL / AppContainer clients can open the pipe.
    std::wstring sddl = L"D:(A;;GA;;;SY)(A;;GA;;;BA)";
    if (!userSidStr.empty()) {
        sddl += L"(A;;GA;;;";
        sddl += userSidStr;
        sddl += L")";
    }
    std::wstring sddlFull = sddl + L"(A;;0x120082;;;AC)(A;;0x120082;;;S-1-15-2-2)S:(ML;;NW;;;LW)";

    if (ConvertStringSecurityDescriptorToSecurityDescriptorW(
            sddlFull.c_str(), SDDL_REVISION_1, outSd, nullptr)) {
        return true;
    }
    std::wstring sddlCompat = sddl + L"(A;;0x120082;;;AC)S:(ML;;NW;;;LW)";
    return ConvertStringSecurityDescriptorToSecurityDescriptorW(
        sddlCompat.c_str(), SDDL_REVISION_1, outSd, nullptr) != FALSE;
}

static DWORD WINAPI SettingsWakePipeThreadProc(LPVOID param) {
    auto *srv = reinterpret_cast<SettingsWakePipeServer *>(param);
    if (!srv || !srv->targetHwnd || !srv->hStopEvent) {
        return 0;
    }

    PSECURITY_DESCRIPTOR pSd = nullptr;
    CreateSettingsWakeSecurityDescriptor(&pSd);

    SECURITY_ATTRIBUTES sa{};
    sa.nLength = sizeof(sa);
    sa.lpSecurityDescriptor = pSd;
    sa.bInheritHandle = FALSE;

    HANDLE hOvEvent = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    if (!hOvEvent) {
        if (pSd) LocalFree(pSd);
        return 0;
    }

    const std::wstring pipeName = GetSettingsWakePipeName();
    while (WaitForSingleObject(srv->hStopEvent, 0) == WAIT_TIMEOUT) {
        HANDLE hPipe = CreateNamedPipeW(
            pipeName.c_str(),
            PIPE_ACCESS_INBOUND | FILE_FLAG_OVERLAPPED,
            PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT | PIPE_REJECT_REMOTE_CLIENTS,
            4,
            0,
            64,
            0,
            pSd ? &sa : nullptr
        );
        if (hPipe == INVALID_HANDLE_VALUE) {
            if (WaitForSingleObject(srv->hStopEvent, 250) == WAIT_OBJECT_0) {
                break;
            }
            continue;
        }

        ResetEvent(hOvEvent);
        OVERLAPPED ov{};
        ov.hEvent = hOvEvent;
        BOOL connected = ConnectNamedPipe(hPipe, &ov);
        if (!connected) {
            DWORD err = GetLastError();
            if (err == ERROR_IO_PENDING) {
                HANDLE waits[2] = { srv->hStopEvent, hOvEvent };
                DWORD wr = WaitForMultipleObjects(2, waits, FALSE, INFINITE);
                if (wr == WAIT_OBJECT_0) {
                    CancelIoEx(hPipe, &ov);
                    DWORD canceled = 0;
                    GetOverlappedResult(hPipe, &ov, &canceled, TRUE);
                    CloseHandle(hPipe);
                    break;
                }
                DWORD transferred = 0;
                connected = (wr == WAIT_OBJECT_0 + 1) && GetOverlappedResult(hPipe, &ov, &transferred, FALSE);
            } else if (err == ERROR_PIPE_CONNECTED) {
                connected = TRUE;
            }
        }

        if (connected) {
            char buf[16] = {};
            DWORD bytesRead = 0;
            ResetEvent(hOvEvent);
            OVERLAPPED ovRead{};
            ovRead.hEvent = hOvEvent;
            BOOL readOk = ReadFile(hPipe, buf, sizeof(buf), &bytesRead, &ovRead);
            if (!readOk && GetLastError() == ERROR_IO_PENDING) {
                HANDLE waits[2] = { srv->hStopEvent, hOvEvent };
                DWORD wr = WaitForMultipleObjects(2, waits, FALSE, 250);
                if (wr == WAIT_OBJECT_0 + 1) {
                    readOk = GetOverlappedResult(hPipe, &ovRead, &bytesRead, FALSE);
                } else {
                    CancelIoEx(hPipe, &ovRead);
                    DWORD canceled = 0;
                    GetOverlappedResult(hPipe, &ovRead, &canceled, TRUE);
                }
            }
            if (readOk && IsWindow(srv->targetHwnd)) {
                using vielotus_tsf_guard::SettingsPipeCommand;
                switch (vielotus_tsf_guard::ParseSettingsPipeCommand(buf, static_cast<size_t>(bytesRead))) {
                case SettingsPipeCommand::ShowWindow:
                    PostMessageW(srv->targetHwnd, kWmVieLotusShowSettings, 0, 0);
                    break;
                case SettingsPipeCommand::SyncPrefsOnly:
                    PostMessageW(
                        srv->targetHwnd,
                        kWmVieLotusSyncPrefs,
                        static_cast<WPARAM>(vielotus_tsf_guard::kSettingsSyncHintReload),
                        0
                    );
                    break;
                case SettingsPipeCommand::SyncTelex:
                    PostMessageW(
                        srv->targetHwnd,
                        kWmVieLotusSyncPrefs,
                        static_cast<WPARAM>(vielotus_tsf_guard::kSettingsSyncHintTipTelex),
                        0
                    );
                    break;
                case SettingsPipeCommand::SyncVni:
                    PostMessageW(
                        srv->targetHwnd,
                        kWmVieLotusSyncPrefs,
                        static_cast<WPARAM>(vielotus_tsf_guard::kSettingsSyncHintTipVni),
                        0
                    );
                    break;
                case SettingsPipeCommand::None:
                    break;
                }
            }
            DisconnectNamedPipe(hPipe);
        }

        CloseHandle(hPipe);
    }

    CloseHandle(hOvEvent);
    if (pSd) LocalFree(pSd);
    return 0;
}

// ============================================================================
// Bento Settings UI & State
// ============================================================================

enum class HitRegion : int {
    None = 0,
    TabSettings,
    TabAbout,
    BtnCheckUpdate,
    BadgeImeConflict,
    CardTelex,
    CardVni,
    BarSenFlex,
    TileMacroToggle,
    BtnMacroManage,
    TileDevMode,
    ChipQuickTelex,
    ChipRelaxedCoda,
    TileStartWithWindows,
    BtnClearTestEdit,
    RowFeedback,
    RowZalo,
    RowGitHub,
    FooterLanguage,
    FooterGitHub,
    FooterFeedback
};

struct SettingsDialogInitParams {
    VieLotusActivateProfilesFn onActivateProfiles{nullptr};
};

class SettingsProfileNotifySink final : public ITfActiveLanguageProfileNotifySink {
public:
    explicit SettingsProfileNotifySink(HWND hwndTarget) : m_hwndTarget(hwndTarget) {}

    void Detach() {
        m_hwndTarget = nullptr;
    }

    STDMETHODIMP QueryInterface(REFIID riid, void **ppvObj) override {
        if (!ppvObj) return E_POINTER;
        *ppvObj = nullptr;
        if (IsEqualIID(riid, IID_IUnknown) || IsEqualIID(riid, IID_ITfActiveLanguageProfileNotifySink)) {
            *ppvObj = static_cast<ITfActiveLanguageProfileNotifySink *>(this);
            AddRef();
            return S_OK;
        }
        return E_NOINTERFACE;
    }

    STDMETHODIMP_(ULONG) AddRef() override {
        return static_cast<ULONG>(InterlockedIncrement(&m_cRef));
    }

    STDMETHODIMP_(ULONG) Release() override {
        LONG c = InterlockedDecrement(&m_cRef);
        if (c == 0) {
            delete this;
        }
        return static_cast<ULONG>(c);
    }

    STDMETHODIMP OnActivated(REFCLSID clsid, REFGUID guidProfile, BOOL fActivated) override {
        if (fActivated && m_hwndTarget && IsWindow(m_hwndTarget) && IsEqualCLSID(clsid, kClsidVieLotusTip)) {
            WPARAM hint = 0;
            if (IsEqualGUID(guidProfile, kGuidVieLotusProfileTelex)) {
                hint = static_cast<WPARAM>(vielotus_tsf_guard::kSettingsSyncHintTsfTelex);
            } else if (IsEqualGUID(guidProfile, kGuidVieLotusProfileVni)) {
                hint = static_cast<WPARAM>(vielotus_tsf_guard::kSettingsSyncHintTsfVni);
            }
            if (hint != 0) {
                PostMessageW(m_hwndTarget, kWmVieLotusSyncPrefs, hint, 0);
            }
        }
        return S_OK;
    }

private:
    LONG m_cRef{1};
    HWND m_hwndTarget{nullptr};
};

struct BentoSettingsState {
    VieLotusWindowsPrefs prefs{};
    int selectedTab{0}; // 0 = Cài đặt, 1 = Thông tin
    HitRegion hoveredRegion{HitRegion::None};
    float dpiScale{1.0f};
    bool isDark{false};
    Image *pAppIcon{nullptr};
    HICON hWndIconBig{nullptr};
    HICON hWndIconSmall{nullptr};
    HWND hTestEdit{nullptr};
    HFONT hEditFont{nullptr};
    HBRUSH hEditBgBrush{nullptr};
    std::wstring conflictImeSummary{};
    ULONGLONG lastConflictScanMs{0};
    uint32_t lastImRevision{0};
    bool hasLastObservedTsf{false};
    bool lastObservedTsfIsVni{false};
    ITfThreadMgr *pThreadMgr{nullptr};
    DWORD profileNotifyCookie{TF_INVALID_COOKIE};
    SettingsProfileNotifySink *profileNotifySink{nullptr};
    VieLotusActivateProfilesFn onActivateProfiles{nullptr};
    SettingsWakePipeServer *wakePipeServer{nullptr};
};

static bool QueryActiveSenVietTsfProfile(bool &outIsVni) {
    outIsVni = false;
    ITfInputProcessorProfiles *pProfiles = nullptr;
    if (FAILED(CoCreateInstance(
            CLSID_TF_InputProcessorProfiles,
            nullptr,
            CLSCTX_INPROC_SERVER,
            IID_ITfInputProcessorProfiles,
            reinterpret_cast<void **>(&pProfiles)
        )) || !pProfiles) {
        return false;
    }

    bool matched = false;
    ITfInputProcessorProfileMgr *pProfileMgr = nullptr;
    if (SUCCEEDED(pProfiles->QueryInterface(
            IID_ITfInputProcessorProfileMgr,
            reinterpret_cast<void **>(&pProfileMgr)
        )) && pProfileMgr) {
        TF_INPUTPROCESSORPROFILE activeProfile{};
        if (SUCCEEDED(pProfileMgr->GetActiveProfile(GUID_TFCAT_TIP_KEYBOARD, &activeProfile)) &&
            IsEqualCLSID(activeProfile.clsid, kClsidVieLotusTip)) {
            if (IsEqualGUID(activeProfile.guidProfile, kGuidVieLotusProfileVni)) {
                outIsVni = true;
                matched = true;
            } else if (IsEqualGUID(activeProfile.guidProfile, kGuidVieLotusProfileTelex)) {
                outIsVni = false;
                matched = true;
            }
        }
        pProfileMgr->Release();
    }
    pProfiles->Release();
    return matched;
}

static void ActivateSettingsProcessProfile(bool isVni) {
    ITfInputProcessorProfiles *pProfiles = nullptr;
    if (FAILED(CoCreateInstance(
            CLSID_TF_InputProcessorProfiles,
            nullptr,
            CLSCTX_INPROC_SERVER,
            IID_ITfInputProcessorProfiles,
            reinterpret_cast<void **>(&pProfiles)
        )) || !pProfiles) {
        return;
    }

    const GUID &targetGuid = isVni ? kGuidVieLotusProfileVni : kGuidVieLotusProfileTelex;
    ITfInputProcessorProfileMgr *pProfileMgr = nullptr;
    if (SUCCEEDED(pProfiles->QueryInterface(
            IID_ITfInputProcessorProfileMgr,
            reinterpret_cast<void **>(&pProfileMgr)
        )) && pProfileMgr) {
        pProfileMgr->ActivateProfile(
            TF_PROFILETYPE_INPUTPROCESSOR,
            kViLangId,
            kClsidVieLotusTip,
            targetGuid,
            nullptr,
            static_cast<DWORD>(vielotus_tsf_guard::kActivateProfileProcessFlags)
        );
        pProfileMgr->Release();
    }
    pProfiles->Release();
}

static void DisableStartWithWindowsTsfAutostart() {
    SyncStartWithWindowsRegistry(false);

    ITfInputProcessorProfiles *pProfiles = nullptr;
    if (SUCCEEDED(CoCreateInstance(
            CLSID_TF_InputProcessorProfiles,
            nullptr,
            CLSCTX_INPROC_SERVER,
            IID_ITfInputProcessorProfiles,
            reinterpret_cast<void **>(&pProfiles)
        )) && pProfiles) {
        // Keep both profiles enabled for manual Win+Spacebar switching,
        // while disabling automatic sign-in default activation.
        pProfiles->EnableLanguageProfileByDefault(kClsidVieLotusTip, kViLangId, kGuidVieLotusProfileTelex, FALSE);
        pProfiles->EnableLanguageProfileByDefault(kClsidVieLotusTip, kViLangId, kGuidVieLotusProfileVni, FALSE);
        pProfiles->Release();
    }

    HKEY hUserProfile = nullptr;
    if (RegOpenKeyExW(
            HKEY_CURRENT_USER,
            L"Control Panel\\International\\User Profile",
            0,
            KEY_READ | KEY_SET_VALUE,
            &hUserProfile
        ) == ERROR_SUCCESS && hUserProfile) {
        RegDeleteValueW(hUserProfile, L"InputMethodOverride");

        DWORD dwType = 0;
        DWORD cbData = 0;
        if (RegQueryValueExW(hUserProfile, L"Languages", nullptr, &dwType, nullptr, &cbData) == ERROR_SUCCESS &&
            dwType == REG_MULTI_SZ && cbData > sizeof(WCHAR) * 2) {
            std::vector<WCHAR> buf(cbData / sizeof(WCHAR) + 2, L'\0');
            if (RegQueryValueExW(
                    hUserProfile,
                    L"Languages",
                    nullptr,
                    &dwType,
                    reinterpret_cast<LPBYTE>(buf.data()),
                    &cbData
                ) == ERROR_SUCCESS) {
                std::vector<std::wstring> otherLangs;
                std::vector<std::wstring> viLangs;
                const WCHAR *p = buf.data();
                while (*p) {
                    std::wstring lang(p);
                    if (_wcsicmp(lang.c_str(), L"vi-VN") == 0 || _wcsicmp(lang.c_str(), L"vi") == 0) {
                        viLangs.push_back(lang);
                    } else {
                        otherLangs.push_back(lang);
                    }
                    p += lang.size() + 1;
                }
                if (!otherLangs.empty() && !viLangs.empty()) {
                    std::vector<WCHAR> multiSz;
                    for (const auto &s : otherLangs) {
                        multiSz.insert(multiSz.end(), s.begin(), s.end());
                        multiSz.push_back(L'\0');
                    }
                    for (const auto &s : viLangs) {
                        multiSz.insert(multiSz.end(), s.begin(), s.end());
                        multiSz.push_back(L'\0');
                    }
                    multiSz.push_back(L'\0');
                    RegSetValueExW(
                        hUserProfile,
                        L"Languages",
                        0,
                        REG_MULTI_SZ,
                        reinterpret_cast<const BYTE *>(multiSz.data()),
                        static_cast<DWORD>(multiSz.size() * sizeof(WCHAR))
                    );
                }
            }
        }
        RegCloseKey(hUserProfile);
    }

    DWORD_PTR dwRes = 0;
    SendMessageTimeoutW(
        HWND_BROADCAST,
        WM_SETTINGCHANGE,
        0,
        reinterpret_cast<LPARAM>(L"intl"),
        SMTO_ABORTIFHUNG | SMTO_NOTIMEOUTIFNOTHUNG,
        150,
        &dwRes
    );
}

static void StartSettingsProfileNotifySink(BentoSettingsState *st, HWND hwnd) {
    if (!st || !hwnd || st->profileNotifySink) return;
    ITfThreadMgr *pThreadMgr = nullptr;
    if (FAILED(CoCreateInstance(
            CLSID_TF_ThreadMgr,
            nullptr,
            CLSCTX_INPROC_SERVER,
            IID_ITfThreadMgr,
            reinterpret_cast<void **>(&pThreadMgr)
        )) || !pThreadMgr) {
        return;
    }

    ITfSource *pSource = nullptr;
    if (SUCCEEDED(pThreadMgr->QueryInterface(IID_ITfSource, reinterpret_cast<void **>(&pSource))) && pSource) {
        auto *sink = new (std::nothrow) SettingsProfileNotifySink(hwnd);
        if (sink) {
            DWORD cookie = TF_INVALID_COOKIE;
            if (SUCCEEDED(pSource->AdviseSink(
                    IID_ITfActiveLanguageProfileNotifySink,
                    static_cast<ITfActiveLanguageProfileNotifySink *>(sink),
                    &cookie
                ))) {
                st->pThreadMgr = pThreadMgr;
                st->profileNotifySink = sink;
                st->profileNotifyCookie = cookie;
                pSource->Release();
                return;
            }
            sink->Detach();
            sink->Release();
        }
        pSource->Release();
    }
    pThreadMgr->Release();
}

static void StopSettingsProfileNotifySink(BentoSettingsState *st) {
    if (!st) return;
    if (st->profileNotifySink) {
        st->profileNotifySink->Detach();
    }
    if (st->pThreadMgr) {
        if (st->profileNotifyCookie != TF_INVALID_COOKIE) {
            ITfSource *pSource = nullptr;
            if (SUCCEEDED(st->pThreadMgr->QueryInterface(IID_ITfSource, reinterpret_cast<void **>(&pSource))) && pSource) {
                pSource->UnadviseSink(st->profileNotifyCookie);
                pSource->Release();
            }
            st->profileNotifyCookie = TF_INVALID_COOKIE;
        }
        st->pThreadMgr->Release();
        st->pThreadMgr = nullptr;
    }
    if (st->profileNotifySink) {
        st->profileNotifySink->Release();
        st->profileNotifySink = nullptr;
    }
}

static void UpdateTestEditCueBanner(BentoSettingsState *st) {
    if (!st || !st->hTestEdit) return;
    const bool isEn = win_l10n::ResolveWindowsIsEnglish(st->prefs.uiLanguage);
    const wchar_t *cue = st->prefs.isVni
        ? win_l10n::Tr(
            isEn,
            L"G\u00F5 th\u1EED (VNI): tru7o7ng3 \u2192 tr\u01B0\u1EDFng \u2022 12ha2 \u2192 12h\u00E0 \u2022 window user...",
            L"Test typing (VNI): tru7o7ng3 \u2192 tr\u01B0\u1EDFng \u2022 12ha2 \u2192 12h\u00E0 \u2022 window user..."
        )
        : win_l10n::Tr(
            isEn,
            L"G\u00F5 th\u1EED (Telex): truowngr \u2192 tr\u01B0\u1EDFng \u2022 12haf \u2192 12h\u00E0 \u2022 window user...",
            L"Test typing (Telex): truowngr \u2192 tr\u01B0\u1EDFng \u2022 12haf \u2192 12h\u00E0 \u2022 window user..."
        );
    SendMessageW(st->hTestEdit, 0x1501, TRUE, reinterpret_cast<LPARAM>(cue));
}

static vielotus_tsf_guard::SettingsImSyncResult SyncSettingsWithSystemInputMethod(
    HWND hwnd,
    BentoSettingsState *st,
    vielotus_tsf_guard::SettingsSyncTrigger trigger,
    bool explicitHintIsVni = false,
    bool reloadAllPrefs = false
) {
    vielotus_tsf_guard::SettingsImSyncResult result{};
    if (!st) return result;

    const bool oldUiVni = st->prefs.isVni;
    VieLotusWindowsPrefs regPrefs{};
    LoadVieLotusPrefs(regPrefs);
    const uint32_t currentImRev = LoadInputMethodRevision();

    bool otherPrefsChanged = false;
    if (reloadAllPrefs) {
        otherPrefsChanged =
            (regPrefs.vietnameseEnabled != st->prefs.vietnameseEnabled) ||
            (regPrefs.smartBilingual != st->prefs.smartBilingual) ||
            (regPrefs.modernOrthography != st->prefs.modernOrthography) ||
            (regPrefs.senFlex != st->prefs.senFlex) ||
            (regPrefs.macroEnabled != st->prefs.macroEnabled) ||
            (regPrefs.developerMode != st->prefs.developerMode) ||
            (regPrefs.quickTelex != st->prefs.quickTelex) ||
            (regPrefs.relaxedCoda != st->prefs.relaxedCoda) ||
            (regPrefs.autoBypassRemoteApps != st->prefs.autoBypassRemoteApps) ||
            (regPrefs.startWithWindows != st->prefs.startWithWindows) ||
            (regPrefs.uiLanguage != st->prefs.uiLanguage);
        const bool oldIsEn = win_l10n::ResolveWindowsIsEnglish(st->prefs.uiLanguage);
        const bool newIsEn = win_l10n::ResolveWindowsIsEnglish(regPrefs.uiLanguage);
        const bool keepUiVni = st->prefs.isVni;
        st->prefs = regPrefs;
        st->prefs.isVni = keepUiVni;
        if (oldIsEn != newIsEn) {
            UpdateTestEditCueBanner(st);
        }
    }

    bool activeTsfIsVni = false;
    const bool hasActiveTsf = QueryActiveSenVietTsfProfile(activeTsfIsVni);

    vielotus_tsf_guard::SettingsImSyncInput in{};
    in.trigger = trigger;
    in.currentUiIsVni = oldUiVni;
    in.registryIsVni = regPrefs.isVni;
    in.lastSeenImRevision = st->lastImRevision;
    in.currentRegistryImRevision = currentImRev;
    in.hasActiveTsfProfile = hasActiveTsf;
    in.activeTsfIsVni = activeTsfIsVni;
    in.hasLastObservedTsf = st->hasLastObservedTsf;
    in.lastObservedTsfIsVni = st->lastObservedTsfIsVni;
    in.explicitHintIsVni = explicitHintIsVni;

    result = vielotus_tsf_guard::ResolveSettingsInputMethodSync(in);

    st->prefs.isVni = result.nextUiIsVni;
    if (result.shouldPersistToRegistry) {
        SavePersistedVniPreference(st->prefs.isVni);
        st->lastImRevision = LoadInputMethodRevision();
    } else {
        st->lastImRevision = currentImRev;
    }

    if (result.shouldSyncProcessProfile) {
        ActivateSettingsProcessProfile(st->prefs.isVni);
        bool refreshedVni = st->prefs.isVni;
        st->hasLastObservedTsf = QueryActiveSenVietTsfProfile(refreshedVni);
        st->lastObservedTsfIsVni = st->hasLastObservedTsf ? refreshedVni : st->prefs.isVni;
    } else {
        st->hasLastObservedTsf = hasActiveTsf;
        st->lastObservedTsfIsVni = activeTsfIsVni;
    }

    if (result.uiChanged) {
        UpdateTestEditCueBanner(st);
    }
    if ((result.uiChanged || otherPrefsChanged) && hwnd && IsWindow(hwnd)) {
        InvalidateRect(hwnd, nullptr, FALSE);
    }
    return result;
}

static void RefreshConflictSummaryThrottled(BentoSettingsState *st, bool force = false) {
    if (!st) return;
    const ULONGLONG now = GetTickCount64();
    if (!force && st->lastConflictScanMs != 0ULL && (now - st->lastConflictScanMs) < 5000ULL) {
        return;
    }
    st->lastConflictScanMs = now;
    st->conflictImeSummary = vielotus_win_installer::FormatConflictingImeNames(
        vielotus_win_installer::DetectConflictingHookImes()
    );
}

static void StartSettingsWakePipeServer(BentoSettingsState *st, HWND hwnd) {
    if (!st || !hwnd || st->wakePipeServer) return;
    auto *srv = new SettingsWakePipeServer();
    srv->targetHwnd = hwnd;
    srv->hStopEvent = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    if (!srv->hStopEvent) {
        delete srv;
        return;
    }
    srv->hThread = CreateThread(nullptr, 0, &SettingsWakePipeThreadProc, srv, 0, nullptr);
    if (!srv->hThread) {
        CloseHandle(srv->hStopEvent);
        delete srv;
        return;
    }
    st->wakePipeServer = srv;
}

static void StopSettingsWakePipeServer(BentoSettingsState *st) {
    if (!st || !st->wakePipeServer) return;
    SettingsWakePipeServer *srv = st->wakePipeServer;
    st->wakePipeServer = nullptr;
    if (srv->hStopEvent) {
        SetEvent(srv->hStopEvent);
    }
    DWORD waitRes = WAIT_OBJECT_0;
    if (srv->hThread) {
        waitRes = WaitForSingleObject(srv->hThread, 5000);
        CloseHandle(srv->hThread);
        srv->hThread = nullptr;
    }
    if (waitRes == WAIT_OBJECT_0) {
        if (srv->hStopEvent) {
            CloseHandle(srv->hStopEvent);
        }
        delete srv;
    }
}

static HICON LoadEmbeddedAppIcon(int cx, int cy) {
    HINSTANCE inst = ResolveSettingsInstance(nullptr);
    HICON hIco = static_cast<HICON>(LoadImageW(inst, MAKEINTRESOURCEW(101), IMAGE_ICON, cx, cy, LR_DEFAULTCOLOR));
    if (!hIco) {
        hIco = static_cast<HICON>(LoadImageW(GetModuleHandleW(nullptr), MAKEINTRESOURCEW(101), IMAGE_ICON, cx, cy, LR_DEFAULTCOLOR));
    }
    return hIco;
}

static Image *LoadEmbeddedPngImage(int resourceId) {
    HMODULE hMain = GetModuleHandleW(nullptr);
    HMODULE hInst = ResolveSettingsInstance(nullptr);
    HMODULE hMods[2] = { hInst, hMain };
    for (int i = 0; i < 2; ++i) {
        HMODULE hMod = hMods[i];
        if (!hMod || (i == 1 && hMod == hMods[0])) continue;
        HRSRC hRes = FindResourceW(hMod, MAKEINTRESOURCEW(resourceId), MAKEINTRESOURCEW(10) /* RT_RCDATA */);
        if (!hRes) continue;
        DWORD sz = SizeofResource(hMod, hRes);
        if (sz == 0) continue;
        HGLOBAL hLoad = LoadResource(hMod, hRes);
        if (!hLoad) continue;
        const void *pData = LockResource(hLoad);
        if (!pData) continue;
        HGLOBAL hMem = GlobalAlloc(GMEM_MOVEABLE, sz);
        if (!hMem) continue;
        void *pDst = GlobalLock(hMem);
        if (pDst) {
            memcpy(pDst, pData, sz);
            GlobalUnlock(hMem);
            IStream *pStream = nullptr;
            if (SUCCEEDED(CreateStreamOnHGlobal(hMem, TRUE, &pStream)) && pStream) {
                Image *img = Image::FromStream(pStream);
                pStream->Release();
                if (img && img->GetLastStatus() == Ok) {
                    return img;
                }
                delete img;
            }
        } else {
            GlobalFree(hMem);
        }
    }
    return nullptr;
}

static bool IsWindowsDarkMode() {
    HKEY hKey = nullptr;
    DWORD useLight = 1;
    DWORD cb = sizeof(useLight);
    if (RegOpenKeyExW(
            HKEY_CURRENT_USER,
            L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
            0,
            KEY_READ,
            &hKey
        ) == ERROR_SUCCESS && hKey) {
        RegQueryValueExW(hKey, L"AppsUseLightTheme", nullptr, nullptr, reinterpret_cast<LPBYTE>(&useLight), &cb);
        RegCloseKey(hKey);
    }
    return (useLight == 0);
}

static std::wstring GetAppDirPath() {
    WCHAR path[MAX_PATH] = {0};
    if (GetModuleFileNameW(ResolveSettingsInstance(nullptr), path, MAX_PATH) == 0) return L"";
    std::wstring s(path);
    size_t pos = s.find_last_of(L"\\/");
    return (pos != std::wstring::npos) ? s.substr(0, pos + 1) : L"";
}

static void AddRoundRectPath(GraphicsPath &path, RectF r, float radius) {
    if (radius <= 0.5f) {
        path.AddRectangle(r);
        return;
    }
    float d = radius * 2.0f;
    if (d > r.Width) d = r.Width;
    if (d > r.Height) d = r.Height;
    path.AddArc(r.X, r.Y, d, d, 180.0f, 90.0f);
    path.AddArc(r.X + r.Width - d, r.Y, d, d, 270.0f, 90.0f);
    path.AddArc(r.X + r.Width - d, r.Y + r.Height - d, d, d, 0.0f, 90.0f);
    path.AddArc(r.X, r.Y + r.Height - d, d, d, 90.0f, 90.0f);
    path.CloseFigure();
}

static void FillRoundRect(Graphics &g, RectF r, float radius, const Color &fill) {
    GraphicsPath path;
    AddRoundRectPath(path, r, radius);
    SolidBrush brush(fill);
    g.FillPath(&brush, &path);
}

static void DrawRoundRect(Graphics &g, RectF r, float radius, const Color &stroke, float width = 1.0f) {
    GraphicsPath path;
    AddRoundRectPath(path, r, radius);
    Pen pen(stroke, width);
    g.DrawPath(&pen, &path);
}

static void DrawCard(Graphics &g, RectF r, float radius, const Color &fill, const Color &border, float borderWidth = 1.0f) {
    RectF shadowRect(r.X, r.Y + 1.2f, r.Width, r.Height);
    FillRoundRect(g, shadowRect, radius, Color(12, 0, 0, 0));
    FillRoundRect(g, r, radius, fill);
    DrawRoundRect(g, r, radius, border, borderWidth);
}

static bool PtInDipRect(float xDip, float yDip, float rx, float ry, float rw, float rh) {
    return (xDip >= rx && xDip <= (rx + rw) && yDip >= ry && yDip <= (ry + rh));
}

static HitRegion HitTestBentoUI(const BentoSettingsState *st, float xDip, float yDip) {
    if (!st) return HitRegion::None;

    if (PtInDipRect(xDip, yDip, 330.0f, 8.0f, 118.0f, 22.0f)) return HitRegion::BtnCheckUpdate;
    if (PtInDipRect(xDip, yDip, 456.0f, 11.0f, 102.0f, 32.0f)) return HitRegion::TabSettings;
    if (PtInDipRect(xDip, yDip, 558.0f, 11.0f, 102.0f, 32.0f)) return HitRegion::TabAbout;

    if (PtInDipRect(xDip, yDip, 404.0f, 388.0f, 68.0f, 32.0f)) return HitRegion::FooterLanguage;
    if (PtInDipRect(xDip, yDip, 476.0f, 388.0f, 122.0f, 32.0f)) return HitRegion::FooterFeedback;
    if (PtInDipRect(xDip, yDip, 608.0f, 388.0f, 54.0f, 32.0f)) return HitRegion::FooterGitHub;

    if (st->selectedTab == 0) {
        if (!st->conflictImeSummary.empty() && PtInDipRect(xDip, yDip, 340.0f, 59.0f, 320.0f, 20.0f)) {
            return HitRegion::BadgeImeConflict;
        }
        if (PtInDipRect(xDip, yDip, 20.0f, 82.0f, 204.0f, 72.0f)) return HitRegion::CardTelex;
        if (PtInDipRect(xDip, yDip, 238.0f, 82.0f, 204.0f, 72.0f)) return HitRegion::CardVni;
        if (PtInDipRect(xDip, yDip, 456.0f, 82.0f, 204.0f, 72.0f)) return HitRegion::BarSenFlex;

        if (PtInDipRect(xDip, yDip, 202.0f, 188.0f, 68.0f, 24.0f)) return HitRegion::BtnMacroManage;
        if (PtInDipRect(xDip, yDip, 20.0f, 180.0f, 314.0f, 66.0f)) return HitRegion::TileMacroToggle;
        if (PtInDipRect(xDip, yDip, 346.0f, 180.0f, 314.0f, 66.0f)) return HitRegion::TileDevMode;

        if (PtInDipRect(xDip, yDip, 32.0f, 290.0f, 138.0f, 24.0f)) return HitRegion::ChipQuickTelex;
        if (PtInDipRect(xDip, yDip, 182.0f, 290.0f, 138.0f, 24.0f)) return HitRegion::ChipRelaxedCoda;
        if (PtInDipRect(xDip, yDip, 20.0f, 256.0f, 157.0f, 66.0f)) return HitRegion::ChipQuickTelex;
        if (PtInDipRect(xDip, yDip, 177.0f, 256.0f, 157.0f, 66.0f)) return HitRegion::ChipRelaxedCoda;

        if (PtInDipRect(xDip, yDip, 346.0f, 256.0f, 314.0f, 66.0f)) return HitRegion::TileStartWithWindows;

        if (PtInDipRect(xDip, yDip, 594.0f, 338.0f, 58.0f, 28.0f)) return HitRegion::BtnClearTestEdit;
    } else {
        if (PtInDipRect(xDip, yDip, 32.0f, 298.0f, 197.0f, 36.0f)) return HitRegion::RowFeedback;
        if (PtInDipRect(xDip, yDip, 241.0f, 298.0f, 197.0f, 36.0f)) return HitRegion::RowZalo;
        if (PtInDipRect(xDip, yDip, 450.0f, 298.0f, 198.0f, 36.0f)) return HitRegion::RowGitHub;
    }

    return HitRegion::None;
}

static void DrawHeroInputCard(
    Graphics &g,
    float s,
    bool isDark,
    float x, float y, float w, float h,
    bool isSelected,
    bool isHovered,
    const WCHAR *iconText,
    const WCHAR *title,
    const WCHAR *badge,
    const WCHAR *subtitle,
    Font &fTitle,
    Font &fBadge,
    Font &fSub,
    StringFormat &sfLeft,
    StringFormat &sfCenter
) {
    Color accent = isDark ? Color(255, 77, 163, 255) : Color(255, 0, 122, 255);
    Color fill = isSelected
        ? (isDark ? Color(255, 29, 44, 72) : Color(255, 236, 245, 255))
        : (isHovered
            ? (isDark ? Color(255, 44, 44, 58) : Color(255, 250, 250, 253))
            : (isDark ? Color(255, 35, 35, 46) : Color(255, 255, 255, 255)));
    Color border = isSelected
        ? accent
        : (isHovered
            ? (isDark ? Color(255, 82, 82, 104) : Color(255, 195, 200, 210))
            : (isDark ? Color(255, 56, 56, 72) : Color(255, 226, 226, 232)));
    float borderW = isSelected ? (1.8f * s) : (1.0f * s);

    DrawCard(g, RectF(x * s, y * s, w * s, h * s), 12.0f * s, fill, border, borderW);

    RectF iconBox((x + 12.0f) * s, (y + 10.0f) * s, 24.0f * s, 24.0f * s);
    FillRoundRect(
        g, iconBox, 6.5f * s,
        isSelected ? accent : (isDark ? Color(255, 50, 50, 64) : Color(255, 236, 236, 241))
    );
    SolidBrush iconTextBrush(
        isSelected ? Color(255, 255, 255, 255) : (isDark ? Color(255, 175, 175, 188) : Color(255, 100, 100, 108))
    );
    g.DrawString(iconText, -1, &fBadge, iconBox, &sfCenter, &iconTextBrush);

    SolidBrush primaryBrush(isDark ? Color(255, 245, 245, 247) : Color(255, 28, 28, 30));
    RectF titleRect((x + 42.0f) * s, (y + 10.0f) * s, (w - 72.0f) * s, 24.0f * s);
    g.DrawString(title, -1, &fTitle, titleRect, &sfLeft, &primaryBrush);

    RectF chkRect((x + w - 28.0f) * s, (y + 14.0f) * s, 16.0f * s, 16.0f * s);
    if (isSelected) {
        SolidBrush accBrush(accent);
        g.FillEllipse(&accBrush, chkRect);
        Pen chkPen(Color(255, 255, 255, 255), 1.8f * s);
        chkPen.SetStartCap(LineCapRound);
        chkPen.SetEndCap(LineCapRound);
        g.DrawLine(&chkPen, (x + w - 24.0f) * s, (y + 22.0f) * s, (x + w - 21.0f) * s, (y + 25.0f) * s);
        g.DrawLine(&chkPen, (x + w - 21.0f) * s, (y + 25.0f) * s, (x + w - 16.0f) * s, (y + 19.0f) * s);
    } else {
        Pen circlePen(isDark ? Color(255, 92, 92, 110) : Color(255, 195, 195, 204), 1.4f * s);
        g.DrawEllipse(&circlePen, chkRect);
    }

    float badgeW = 86.0f;
    RectF badgeRect((x + 12.0f) * s, (y + 42.0f) * s, badgeW * s, 21.0f * s);
    FillRoundRect(
        g, badgeRect, 5.5f * s,
        isSelected ? Color(52, accent.GetR(), accent.GetG(), accent.GetB()) : (isDark ? Color(255, 48, 48, 62) : Color(255, 240, 240, 245))
    );
    SolidBrush badgeBrush(isSelected ? accent : (isDark ? Color(255, 175, 175, 188) : Color(255, 95, 95, 102)));
    g.DrawString(badge, -1, &fBadge, badgeRect, &sfCenter, &badgeBrush);

    SolidBrush secBrush(isDark ? Color(255, 162, 162, 174) : Color(255, 110, 110, 115));
    RectF subRect((x + 104.0f) * s, (y + 42.0f) * s, (w - 112.0f) * s, 21.0f * s);
    g.DrawString(subtitle, -1, &fSub, subRect, &sfLeft, &secBrush);
}

static void DrawBentoFeatureTile(
    Graphics &g,
    float s,
    bool isDark,
    float x, float y, float w, float h,
    bool isActive,
    bool isHovered,
    const Color &accent,
    const WCHAR *iconGlyph,
    const WCHAR *title,
    const WCHAR *subtitle,
    const WCHAR *actionPillText,
    bool showToggleSwitch,
    Font &fTitle,
    Font &fSub,
    Font &fPill,
    StringFormat &sfLeft,
    StringFormat &sfCenter
) {
    Color fill = isHovered
        ? (isDark ? Color(255, 44, 44, 58) : Color(255, 250, 250, 253))
        : (isDark ? Color(255, 35, 35, 46) : Color(255, 255, 255, 255));
    Color border = isActive
        ? Color(isDark ? 165 : 130, accent.GetR(), accent.GetG(), accent.GetB())
        : (isDark ? Color(255, 56, 56, 72) : Color(255, 226, 226, 232));
    DrawCard(g, RectF(x * s, y * s, w * s, h * s), 12.0f * s, fill, border, 1.1f * s);

    RectF iconBox((x + 12.0f) * s, (y + 10.0f) * s, 24.0f * s, 24.0f * s);
    Color iconBg = isActive
        ? Color(isDark ? 55 : 38, accent.GetR(), accent.GetG(), accent.GetB())
        : (isDark ? Color(255, 48, 48, 62) : Color(255, 238, 238, 243));
    FillRoundRect(g, iconBox, 6.5f * s, iconBg);
    SolidBrush iconBrush(isActive ? accent : (isDark ? Color(255, 165, 165, 178) : Color(255, 120, 120, 128)));
    g.DrawString(iconGlyph, -1, &fPill, iconBox, &sfCenter, &iconBrush);

    const float pillW = (actionPillText && wcslen(actionPillText) <= 4) ? 44.0f : 68.0f;
    float rightControlsW = showToggleSwitch ? (actionPillText ? (pillW + 58.0f) : 56.0f) : (pillW + 10.0f);
    SolidBrush primaryBrush(isDark ? Color(255, 245, 245, 247) : Color(255, 28, 28, 30));
    RectF titleRect((x + 42.0f) * s, (y + 10.0f) * s, (w - 48.0f - rightControlsW) * s, 22.0f * s);
    g.DrawString(title, -1, &fTitle, titleRect, &sfLeft, &primaryBrush);

    if (actionPillText && actionPillText[0] != L'\0') {
        float pillX = showToggleSwitch ? (x + w - pillW - 56.0f) : (x + w - pillW - 12.0f);
        RectF pillRect(pillX * s, (y + 11.0f) * s, pillW * s, 21.0f * s);
        Color pillBg = isDark ? Color(255, 48, 48, 62) : Color(255, 238, 238, 244);
        FillRoundRect(g, pillRect, 6.5f * s, pillBg);
        DrawRoundRect(g, pillRect, 6.5f * s, isDark ? Color(255, 72, 72, 92) : Color(255, 216, 216, 226), 1.0f * s);
        SolidBrush pillTextBrush(isActive ? accent : (isDark ? Color(255, 195, 195, 210) : Color(255, 80, 80, 92)));
        g.DrawString(actionPillText, -1, &fPill, pillRect, &sfCenter, &pillTextBrush);
    }

    if (showToggleSwitch) {
        float swW = 36.0f;
        float swH = 20.0f;
        float swX = x + w - swW - 12.0f;
        float swY = y + 11.5f;
        RectF swTrack(swX * s, swY * s, swW * s, swH * s);
        Color trackCol = isActive
            ? accent
            : (isDark ? Color(255, 68, 68, 84) : Color(255, 212, 212, 220));
        FillRoundRect(g, swTrack, 10.0f * s, trackCol);
        float knobD = 16.0f;
        float knobX = isActive ? (swX + swW - knobD - 2.0f) : (swX + 2.0f);
        RectF knobRect(knobX * s, (swY + 2.0f) * s, knobD * s, knobD * s);
        SolidBrush knobBrush(Color(255, 255, 255, 255));
        g.FillEllipse(&knobBrush, knobRect);
    }

    SolidBrush secBrush(isDark ? Color(255, 162, 162, 174) : Color(255, 110, 110, 115));
    RectF subRect((x + 12.0f) * s, (y + 39.0f) * s, (w - 24.0f) * s, 20.0f * s);
    g.DrawString(subtitle, -1, &fSub, subRect, &sfLeft, &secBrush);
}

static void RenderBentoSettingsUI(HWND hwnd, HDC hdc, BentoSettingsState *st) {
    if (!st) return;

    RECT rcClient{};
    GetClientRect(hwnd, &rcClient);
    int width = rcClient.right - rcClient.left;
    int height = rcClient.bottom - rcClient.top;
    if (width <= 0 || height <= 0) return;

    HDC memDC = CreateCompatibleDC(hdc);
    HBITMAP memBmp = CreateCompatibleBitmap(hdc, width, height);
    HBITMAP oldBmp = static_cast<HBITMAP>(SelectObject(memDC, memBmp));

    {
        Graphics g(memDC);
        g.SetSmoothingMode(SmoothingModeAntiAlias);
        g.SetPixelOffsetMode(PixelOffsetModeHighQuality);
        g.SetTextRenderingHint(TextRenderingHintClearTypeGridFit);

        float s = st->dpiScale;
        bool isDark = st->isDark;
        const bool isEn = win_l10n::ResolveWindowsIsEnglish(st->prefs.uiLanguage);

        FontFamily ffSans(L"Segoe UI");
        FontFamily ffMono(L"Consolas");

        Font fBrand(&ffSans, 14.0f * s, FontStyleBold, UnitPixel);
        Font fVersion(&ffSans, 9.5f * s, FontStyleBold, UnitPixel);
        Font fHeaderSub(&ffSans, 10.5f * s, FontStyleRegular, UnitPixel);
        Font fTab(&ffSans, 11.5f * s, FontStyleBold, UnitPixel);
        Font fSecHdr(&ffSans, 10.0f * s, FontStyleBold, UnitPixel);
        Font fSecRight(&ffSans, 10.5f * s, FontStyleBold, UnitPixel);
        Font fCardTitle(&ffSans, 12.0f * s, FontStyleBold, UnitPixel);
        Font fTileTitle(&ffSans, 11.5f * s, FontStyleBold, UnitPixel);
        Font fBodyBold(&ffSans, 11.5f * s, FontStyleBold, UnitPixel);
        Font fSub(&ffSans, 10.5f * s, FontStyleRegular, UnitPixel);
        Font fPill(&ffSans, 9.5f * s, FontStyleBold, UnitPixel);
        Font fMonoBadge(&ffMono, 9.5f * s, FontStyleBold, UnitPixel);
        Font fFooter(&ffSans, 10.0f * s, FontStyleRegular, UnitPixel);
        Font fFooterBold(&ffSans, 10.0f * s, FontStyleBold, UnitPixel);

        StringFormat sfLeft;
        sfLeft.SetAlignment(StringAlignmentNear);
        sfLeft.SetLineAlignment(StringAlignmentCenter);
        sfLeft.SetFormatFlags(StringFormatFlagsNoWrap);
        sfLeft.SetTrimming(StringTrimmingEllipsisCharacter);

        StringFormat sfWrap;
        sfWrap.SetAlignment(StringAlignmentNear);
        sfWrap.SetLineAlignment(StringAlignmentNear);

        StringFormat sfRight;
        sfRight.SetAlignment(StringAlignmentFar);
        sfRight.SetLineAlignment(StringAlignmentCenter);
        sfRight.SetFormatFlags(StringFormatFlagsNoWrap);
        sfRight.SetTrimming(StringTrimmingEllipsisCharacter);

        StringFormat sfCenter;
        sfCenter.SetAlignment(StringAlignmentCenter);
        sfCenter.SetLineAlignment(StringAlignmentCenter);
        sfCenter.SetFormatFlags(StringFormatFlagsNoWrap);
        sfCenter.SetTrimming(StringTrimmingEllipsisCharacter);

        Color canvasCol = isDark ? Color(255, 20, 20, 25) : Color(255, 245, 245, 247);
        Color barCol = isDark ? Color(255, 28, 28, 36) : Color(255, 255, 255, 255);
        Color cardCol = isDark ? Color(255, 35, 35, 46) : Color(255, 255, 255, 255);
        Color cardBorderCol = isDark ? Color(255, 56, 56, 72) : Color(255, 226, 226, 232);
        Color divCol = isDark ? Color(255, 46, 46, 58) : Color(255, 229, 229, 234);
        Color fgPrimary = isDark ? Color(255, 245, 245, 247) : Color(255, 28, 28, 30);
        Color fgSecondary = isDark ? Color(255, 162, 162, 174) : Color(255, 110, 110, 115);
        Color blueCol = isDark ? Color(255, 77, 163, 255) : Color(255, 0, 122, 255);
        Color indigoCol = isDark ? Color(255, 129, 140, 248) : Color(255, 88, 86, 214);
        Color tealCol = isDark ? Color(255, 45, 212, 191) : Color(255, 13, 148, 136);

        SolidBrush bgBrush(canvasCol);
        g.FillRectangle(&bgBrush, 0, 0, width, height);

        SolidBrush barBrush(barCol);
        g.FillRectangle(&barBrush, 0.0f, 0.0f, static_cast<float>(width), 54.0f * s);
        Pen divPen(divCol, 1.0f * s);
        g.DrawLine(&divPen, 0.0f, 54.0f * s, static_cast<float>(width), 54.0f * s);

        RectF iconRect(20.0f * s, 9.0f * s, 36.0f * s, 36.0f * s);
        if (st->pAppIcon && st->pAppIcon->GetLastStatus() == Ok) {
            g.DrawImage(st->pAppIcon, iconRect);
        } else if (st->hWndIconBig) {
            HDC hIconDc = g.GetHDC();
            DrawIconEx(
                hIconDc,
                static_cast<int>(20.0f * s),
                static_cast<int>(9.0f * s),
                st->hWndIconBig,
                static_cast<int>(36.0f * s),
                static_cast<int>(36.0f * s),
                0,
                nullptr,
                DI_NORMAL
            );
            g.ReleaseHDC(hIconDc);
        } else {
            FillRoundRect(g, iconRect, 8.0f * s, Color(255, 219, 39, 119));
            SolidBrush wBr(Color(255, 255, 255, 255));
            g.DrawString(L"SV", -1, &fBrand, iconRect, &sfCenter, &wBr);
        }

        SolidBrush primaryBrush(fgPrimary);
        SolidBrush secondaryBrush(fgSecondary);
        SolidBrush blueBrush(blueCol);

        RectF brandRect(64.0f * s, 8.0f * s, 78.0f * s, 20.0f * s);
        g.DrawString(L"Sen Vi\u1EC7t", -1, &fBrand, brandRect, &sfLeft, &primaryBrush);

        RectF verPill(142.0f * s, 10.0f * s, 48.0f * s, 17.0f * s);
        FillRoundRect(g, verPill, 8.5f * s, Color(isDark ? 55 : 36, blueCol.GetR(), blueCol.GetG(), blueCol.GetB()));
        g.DrawString(L"v2.0.10", -1, &fVersion, verPill, &sfCenter, &blueBrush);

        RectF modePill(195.0f * s, 10.0f * s, 132.0f * s, 17.0f * s);
        FillRoundRect(g, modePill, 8.5f * s, isDark ? Color(255, 28, 54, 42) : Color(255, 232, 250, 238));
        SolidBrush greenTextBrush(isDark ? Color(255, 74, 222, 128) : Color(255, 22, 163, 74));
        g.DrawString(
            st->prefs.isVni
                ? win_l10n::Tr(isEn, L"\u25CF \u0110ang b\u1EADt: Chu\u1EA9n VNI", L"\u25CF Active: VNI")
                : win_l10n::Tr(isEn, L"\u25CF \u0110ang b\u1EADt: Chu\u1EA9n Telex", L"\u25CF Active: Telex"),
            -1, &fVersion, modePill, &sfCenter, &greenTextBrush
        );

        {
            RectF updPill(332.0f * s, 10.0f * s, 114.0f * s, 17.0f * s);
            bool updHovered = (st->hoveredRegion == HitRegion::BtnCheckUpdate);
            Color updFill = updHovered
                ? (isDark ? Color(255, 54, 54, 70) : Color(255, 228, 230, 238))
                : (isDark ? Color(255, 42, 42, 54) : Color(255, 236, 236, 242));
            FillRoundRect(g, updPill, 8.5f * s, updFill);
            SolidBrush updBrush(fgSecondary);
            g.DrawString(L"Microsoft Store \u2197", -1, &fVersion, updPill, &sfCenter, &updBrush);
        }

        RectF subBrandRect(64.0f * s, 29.0f * s, 380.0f * s, 17.0f * s);
        g.DrawString(
            win_l10n::Tr(
                isEn,
                L"B\u1ED9 g\u00F5 ti\u1EBFng Vi\u1EC7t thu\u1EA7n chu\u1EA9n Native TSF \u2022 100% Offline",
                L"Native Windows TSF Vietnamese IME \u2022 100% Offline"
            ),
            -1, &fHeaderSub, subBrandRect, &sfLeft, &secondaryBrush
        );

        RectF segBg(456.0f * s, 11.0f * s, 204.0f * s, 32.0f * s);
        FillRoundRect(g, segBg, 8.5f * s, isDark ? Color(255, 42, 42, 54) : Color(255, 235, 235, 240));

        RectF tab0Rect(459.0f * s, 14.0f * s, 98.0f * s, 26.0f * s);
        RectF tab1Rect(559.0f * s, 14.0f * s, 98.0f * s, 26.0f * s);
        RectF activeTabRect = (st->selectedTab == 0) ? tab0Rect : tab1Rect;
        DrawCard(
            g, activeTabRect, 6.5f * s,
            isDark ? Color(255, 58, 58, 74) : Color(255, 255, 255, 255),
            isDark ? Color(255, 82, 82, 104) : Color(35, 0, 0, 0),
            0.8f * s
        );

        SolidBrush tab0Brush(st->selectedTab == 0 ? blueCol : fgSecondary);
        SolidBrush tab1Brush(st->selectedTab == 1 ? blueCol : fgSecondary);
        g.DrawString(win_l10n::Tr(isEn, L"C\u00E0i \u0111\u1EB7t", L"Settings"), -1, &fTab, tab0Rect, &sfCenter, &tab0Brush);
        g.DrawString(win_l10n::Tr(isEn, L"Th\u00F4ng tin", L"About"), -1, &fTab, tab1Rect, &sfCenter, &tab1Brush);

        if (st->selectedTab == 0) {
            g.DrawString(
                win_l10n::Tr(isEn, L"KI\u1EC2U G\u00D5 TI\u1EBENG VI\u1EC6T", L"VIETNAMESE INPUT METHOD"),
                -1, &fSecHdr, RectF(20.0f * s, 61.0f * s, 240.0f * s, 17.0f * s), &sfLeft, &secondaryBrush
            );
            if (!st->conflictImeSummary.empty() && st->prefs.vietnameseEnabled) {
                bool hov = (st->hoveredRegion == HitRegion::BadgeImeConflict);
                Color warnBg = st->isDark
                    ? (hov ? Color(90, 255, 180, 0) : Color(60, 255, 165, 0))
                    : (hov ? Color(255, 238, 198) : Color(255, 246, 224));
                Color warnBorder = st->isDark ? Color(200, 255, 185, 45) : Color(217, 119, 6);
                Color warnText = st->isDark ? Color(255, 214, 92) : Color(161, 78, 0);
                RectF badgeRect(340.0f * s, 59.0f * s, 320.0f * s, 20.0f * s);
                FillRoundRect(g, badgeRect, 6.0f * s, warnBg);
                DrawRoundRect(g, badgeRect, 6.0f * s, warnBorder, 1.0f);
                SolidBrush warnBrush(warnText);
                StringFormat sfWarn;
                sfWarn.SetAlignment(StringAlignmentCenter);
                sfWarn.SetLineAlignment(StringAlignmentCenter);
                sfWarn.SetTrimming(StringTrimmingEllipsisCharacter);
                sfWarn.SetFormatFlags(StringFormatFlagsNoWrap);
                std::wstring warnMsg = isEn
                    ? (L"\u26A0 " + st->conflictImeSummary + L" running \u2014 Click to close")
                    : (L"\u26A0 \u0110ang ch\u1EA1y " + st->conflictImeSummary + L" \u2014 B\u1EA5m \u0111\u1EC3 t\u1EAFt");
                g.DrawString(
                    warnMsg.c_str(), -1, &fSecRight,
                    RectF(346.0f * s, 59.0f * s, 308.0f * s, 20.0f * s), &sfWarn, &warnBrush
                );
            } else {
                g.DrawString(
                    win_l10n::Tr(isEn, L"B\u1ECF d\u1EA5u t\u1EF1 do \u2022 Ph\u00EDm Z xo\u00E1 d\u1EA5u", L"Free-tone typing \u2022 Z removes tone"),
                    -1, &fSecRight, RectF(380.0f * s, 61.0f * s, 280.0f * s, 17.0f * s), &sfRight, &blueBrush
                );
            }

            DrawHeroInputCard(
                g, s, isDark, 20.0f, 82.0f, 204.0f, 72.0f,
                !st->prefs.isVni,
                st->hoveredRegion == HitRegion::CardTelex,
                L"TX",
                win_l10n::Tr(isEn, L"Chu\u1EA9n Telex", L"Telex"),
                L"s f r x j w",
                L"vieetj \u2192 vi\u1EC7t",
                fCardTitle, fMonoBadge, fSub, sfLeft, sfCenter
            );

            DrawHeroInputCard(
                g, s, isDark, 238.0f, 82.0f, 204.0f, 72.0f,
                st->prefs.isVni,
                st->hoveredRegion == HitRegion::CardVni,
                L"19",
                win_l10n::Tr(isEn, L"Chu\u1EA9n VNI", L"VNI"),
                L"1\u20135 \u2022 6\u20139",
                L"viet65 \u2192 vi\u1EC7t",
                fCardTitle, fMonoBadge, fSub, sfLeft, sfCenter
            );

            DrawHeroInputCard(
                g, s, isDark, 456.0f, 82.0f, 204.0f, 72.0f,
                st->prefs.senFlex,
                st->hoveredRegion == HitRegion::BarSenFlex,
                L"\u2726",
                win_l10n::Tr(isEn, L"D\u1EA5u tr\u01B0\u1EDBc \u00E2m", L"Tone-First"),
                L"rrung \u2192 r\u1EE7ng",
                st->prefs.senFlex
                    ? win_l10n::Tr(isEn, L"\u0110ang b\u1EADt", L"On")
                    : win_l10n::Tr(isEn, L"\u0110ang t\u1EAFt", L"Off"),
                fCardTitle, fMonoBadge, fSub, sfLeft, sfCenter
            );

            g.DrawString(
                win_l10n::Tr(isEn, L"TI\u1EC6N \u00CDCH, T\u01AF\u01A0NG TH\u00CDCH & H\u1EC6 TH\u1ED0NG", L"UTILITIES, COMPATIBILITY & SYSTEM"),
                -1, &fSecHdr, RectF(20.0f * s, 160.0f * s, 360.0f * s, 17.0f * s), &sfLeft, &secondaryBrush
            );

            DrawBentoFeatureTile(
                g, s, isDark, 20.0f, 180.0f, 314.0f, 66.0f,
                st->prefs.macroEnabled,
                st->hoveredRegion == HitRegion::TileMacroToggle || st->hoveredRegion == HitRegion::BtnMacroManage,
                indigoCol,
                L"GT",
                win_l10n::Tr(isEn, L"B\u1EA3ng g\u00F5 t\u1EAFt (Macro)", L"Text Shortcuts"),
                st->prefs.macroEnabled
                    ? win_l10n::Tr(isEn, L"\u0110ang b\u1EADt \u2022 T\u1EF1 bung c\u1EE5m t\u1EEB vi\u1EBFt t\u1EAFt", L"On \u2022 Auto-expand abbreviations")
                    : win_l10n::Tr(isEn, L"\u0110ang t\u1EAFt \u2022 B\u1EA5m c\u00F4ng t\u1EAFc \u0111\u1EC3 b\u1EADt", L"Off \u2022 Click switch to enable"),
                win_l10n::Tr(isEn, L"Qu\u1EA3n l\u00FD \u2197", L"Manage \u2197"),
                true,
                fTileTitle, fSub, fPill, sfLeft, sfCenter
            );

            DrawBentoFeatureTile(
                g, s, isDark, 346.0f, 180.0f, 314.0f, 66.0f,
                st->prefs.developerMode,
                st->hoveredRegion == HitRegion::TileDevMode,
                tealCol,
                L"<>",
                win_l10n::Tr(isEn, L"Ch\u1EBF \u0111\u1ED9 Code / IDE", L"Code / IDE Mode"),
                st->prefs.developerMode
                    ? win_l10n::Tr(isEn, L"T\u1EF1 ng\u1EAFt d\u1EA5u trong c\u1EB7p `code` & CLI", L"Auto-pause tones in `code` & CLI")
                    : win_l10n::Tr(isEn, L"Song ng\u1EEF th\u00F4ng minh ti\u00EAu chu\u1EA9n", L"Standard Smart Bilingual typing"),
                nullptr,
                true,
                fTileTitle, fSub, fPill, sfLeft, sfCenter
            );

            {
                bool anyChipActive = st->prefs.quickTelex || st->prefs.relaxedCoda;
                bool tileHovered = (st->hoveredRegion == HitRegion::ChipQuickTelex || st->hoveredRegion == HitRegion::ChipRelaxedCoda);
                Color orangeAcc = isDark ? Color(255, 251, 146, 60) : Color(255, 234, 88, 12);
                Color tileFill = tileHovered
                    ? (isDark ? Color(255, 44, 44, 58) : Color(255, 250, 250, 253))
                    : cardCol;
                Color tileBorder = anyChipActive
                    ? Color(isDark ? 165 : 130, orangeAcc.GetR(), orangeAcc.GetG(), orangeAcc.GetB())
                    : cardBorderCol;
                DrawCard(g, RectF(20.0f * s, 256.0f * s, 314.0f * s, 66.0f * s), 12.0f * s, tileFill, tileBorder, 1.1f * s);

                RectF iconBox(32.0f * s, 265.0f * s, 24.0f * s, 24.0f * s);
                FillRoundRect(
                    g, iconBox, 6.5f * s,
                    anyChipActive ? Color(isDark ? 55 : 38, orangeAcc.GetR(), orangeAcc.GetG(), orangeAcc.GetB()) : (isDark ? Color(255, 48, 48, 62) : Color(255, 238, 238, 243))
                );
                SolidBrush iconBr(anyChipActive ? orangeAcc : fgSecondary);
                g.DrawString(L"\u26A1", -1, &fPill, iconBox, &sfCenter, &iconBr);

                g.DrawString(
                    win_l10n::Tr(isEn, L"T\u1ED1c g\u00F5 ph\u1EE5 \u00E2m nhanh", L"Quick Consonants"),
                    -1, &fTileTitle, RectF(62.0f * s, 266.0f * s, 250.0f * s, 20.0f * s), &sfLeft, &primaryBrush
                );

                auto drawConsonantChip = [&](float cx, const WCHAR *label, bool active, bool hovered) {
                    RectF chipRect(cx * s, 291.0f * s, 140.0f * s, 23.0f * s);
                    Color cFill = active
                        ? Color(isDark ? 58 : 38, orangeAcc.GetR(), orangeAcc.GetG(), orangeAcc.GetB())
                        : (hovered
                            ? (isDark ? Color(255, 56, 56, 72) : Color(255, 234, 234, 240))
                            : (isDark ? Color(255, 46, 46, 60) : Color(255, 242, 242, 247)));
                    Color cBorder = active
                        ? Color(190, orangeAcc.GetR(), orangeAcc.GetG(), orangeAcc.GetB())
                        : (isDark ? Color(255, 70, 70, 88) : Color(255, 222, 222, 228));
                    FillRoundRect(g, chipRect, 6.5f * s, cFill);
                    DrawRoundRect(g, chipRect, 6.5f * s, cBorder, 1.0f * s);
                    SolidBrush cText(active ? orangeAcc : fgSecondary);
                    g.DrawString(label, -1, &fPill, chipRect, &sfCenter, &cText);
                };

                drawConsonantChip(32.0f, win_l10n::Tr(isEn, L"\u0110\u1EA7u (cc/gg/qq)", L"Initial (cc/gg/qq)"), st->prefs.quickTelex, st->hoveredRegion == HitRegion::ChipQuickTelex);
                drawConsonantChip(182.0f, win_l10n::Tr(isEn, L"Cu\u1ED1i (-g/-h/-k)", L"Final (-g/-h/-k)"), st->prefs.relaxedCoda, st->hoveredRegion == HitRegion::ChipRelaxedCoda);
            }

            Color greenAcc = isDark ? Color(255, 74, 222, 128) : Color(255, 22, 163, 74);
            DrawBentoFeatureTile(
                g, s, isDark, 346.0f, 256.0f, 314.0f, 66.0f,
                st->prefs.startWithWindows,
                st->hoveredRegion == HitRegion::TileStartWithWindows,
                greenAcc,
                L"SV",
                win_l10n::Tr(isEn, L"Kh\u1EDFi \u0111\u1ED9ng c\u00F9ng h\u1EC7 th\u1ED1ng", L"Start with Windows"),
                st->prefs.startWithWindows
                    ? win_l10n::Tr(isEn, L"T\u1EF1 \u0111\u1ED9ng b\u1EADt khi m\u1EDF m\u00E1y (Auto) \u2022 Thu\u1EA7n TSF", L"Auto-enable on sign-in (Auto) \u2022 Pure TSF")
                    : win_l10n::Tr(isEn, L"\u0110ang t\u1EAFt \u2022 B\u1EA5m c\u00F4ng t\u1EAFc \u0111\u1EC3 b\u1EADt t\u1EF1 \u0111\u1ED9ng", L"Off \u2022 Click switch to enable"),
                st->prefs.startWithWindows ? L"AUTO" : win_l10n::Tr(isEn, L"T\u1EAE" L"T", L"OFF"),
                true,
                fTileTitle, fSub, fPill, sfLeft, sfCenter
            );

            RectF stripRect(20.0f * s, 332.0f * s, 640.0f * s, 40.0f * s);
            DrawCard(
                g, stripRect, 10.0f * s,
                cardCol,
                isDark ? Color(255, 72, 76, 130) : Color(255, 198, 202, 248),
                1.1f * s
            );

            SolidBrush indigoBrush(indigoCol);
            g.DrawString(
                win_l10n::Tr(isEn, L"\u2726 Th\u1EED g\u00F5:", L"\u2726 Test:"),
                -1, &fBodyBold, RectF(32.0f * s, 332.0f * s, 76.0f * s, 40.0f * s), &sfLeft, &indigoBrush
            );
            if (!st->hTestEdit) {
                g.DrawString(
                    st->prefs.isVni
                        ? L"tru7o7ng3 \u2192 tr\u01B0\u1EDFng \u2022 12ha2 \u2192 12h\u00E0 \u2022 window user"
                        : L"truowngr \u2192 tr\u01B0\u1EDFng \u2022 12haf \u2192 12h\u00E0 \u2022 window user",
                    -1, &fSub, RectF(110.0f * s, 332.0f * s, 476.0f * s, 40.0f * s), &sfLeft, &secondaryBrush
                );
            }

            RectF clearBtn(594.0f * s, 339.0f * s, 56.0f * s, 26.0f * s);
            FillRoundRect(
                g, clearBtn, 6.5f * s,
                st->hoveredRegion == HitRegion::BtnClearTestEdit
                    ? (isDark ? Color(255, 58, 58, 76) : Color(255, 232, 234, 244))
                    : (isDark ? Color(255, 46, 46, 60) : Color(255, 242, 242, 247))
            );
            DrawRoundRect(g, clearBtn, 6.5f * s, isDark ? Color(255, 70, 70, 88) : Color(255, 220, 220, 228), 1.0f * s);
            g.DrawString(win_l10n::Tr(isEn, L"Xo\u00E1 th\u1EED", L"Clear"), -1, &fPill, clearBtn, &sfCenter, &secondaryBrush);
        } else {
            SolidBrush indigoBrush(indigoCol);
            Color greenCol = isDark ? Color(255, 74, 222, 128) : Color(255, 22, 163, 74);
            SolidBrush greenBrush(greenCol);
            SolidBrush whiteTextBrush(Color(255, 255, 255, 255));

            DrawCard(g, RectF(20.0f * s, 68.0f * s, 640.0f * s, 88.0f * s), 10.0f * s, cardCol, cardBorderCol);
            g.DrawString(
                win_l10n::Tr(isEn, L"\u2726 S\u1EE8 M\u1EC6NH SEN VI\u1EC6T", L"\u2726 SEN VI\u1EC6T MISSION"),
                -1, &fSecHdr, RectF(34.0f * s, 77.0f * s, 220.0f * s, 18.0f * s), &sfLeft, &indigoBrush
            );
            g.DrawString(
                win_l10n::Tr(
                    isEn,
                    L"Windows TSF Native \u2022 100% Offline \u2022 An to\u00E0n tuy\u1EC7t \u0111\u1ED1i",
                    L"Windows TSF Native \u2022 100% Offline \u2022 Private"
                ),
                -1, &fSub, RectF(280.0f * s, 77.0f * s, 366.0f * s, 18.0f * s), &sfRight, &secondaryBrush
            );
            g.DrawString(
                win_l10n::Tr(
                    isEn,
                    L"\"H\u00E3y \u0111\u1EC3 vi\u1EC7c g\u00F5 l\u00E0 g\u00F5 \u2014 d\u00F9 b\u1EA1n g\u00F5 ti\u1EBFng Vi\u1EC7t hay ti\u1EBFng Anh; nhanh hay ch\u1EADm; g\u00F5 l\u00E0 Sen Vi\u1EC7t.\"",
                    L"\"Just type naturally \u2014 Vietnamese or English, fast or slow; Sen Vi\u1EC7t handles the rest seamlessly.\""
                ),
                -1, &fTileTitle, RectF(34.0f * s, 102.0f * s, 612.0f * s, 44.0f * s), &sfWrap, &primaryBrush
            );

            DrawCard(
                g, RectF(20.0f * s, 168.0f * s, 314.0f * s, 104.0f * s), 10.0f * s,
                cardCol,
                Color(120, greenCol.GetR(), greenCol.GetG(), greenCol.GetB()), 1.1f * s
            );
            g.DrawString(
                win_l10n::Tr(isEn, L"Quy\u1EC1n ri\u00EAng t\u01B0 & An to\u00E0n", L"Privacy & Security"),
                -1, &fTileTitle, RectF(34.0f * s, 180.0f * s, 180.0f * s, 20.0f * s), &sfLeft, &primaryBrush
            );
            RectF privacyBadge(220.0f * s, 181.0f * s, 100.0f * s, 18.0f * s);
            FillRoundRect(g, privacyBadge, 9.0f * s, Color(isDark ? 55 : 36, greenCol.GetR(), greenCol.GetG(), greenCol.GetB()));
            g.DrawString(L"100% OFFLINE", -1, &fPill, privacyBadge, &sfCenter, &greenBrush);
            g.DrawString(
                win_l10n::Tr(
                    isEn,
                    L"Thu\u1EA7n chu\u1EA9n Windows TSF, kh\u00F4ng ch\u1EA1y ti\u1EBFn tr\u00ECnh n\u1EC1n, kh\u00F4ng thu th\u1EADp ph\u00EDm b\u1EA5m hay g\u1EEDi d\u1EEF li\u1EC7u ra m\u1EA1ng.",
                    L"Pure Windows TSF with no background daemon, zero keylogging, and no network telemetry."
                ),
                -1, &fSub, RectF(34.0f * s, 209.0f * s, 286.0f * s, 54.0f * s), &sfWrap, &secondaryBrush
            );

            DrawCard(
                g, RectF(346.0f * s, 168.0f * s, 314.0f * s, 104.0f * s), 10.0f * s,
                cardCol,
                Color(120, blueCol.GetR(), blueCol.GetG(), blueCol.GetB()), 1.1f * s
            );
            g.DrawString(
                win_l10n::Tr(isEn, L"M\u00E3 ngu\u1ED3n m\u1EDF", L"Open Source"),
                -1, &fTileTitle, RectF(360.0f * s, 180.0f * s, 178.0f * s, 20.0f * s), &sfLeft, &primaryBrush
            );
            RectF ossBadge(548.0f * s, 181.0f * s, 98.0f * s, 18.0f * s);
            FillRoundRect(g, ossBadge, 9.0f * s, Color(isDark ? 55 : 36, blueCol.GetR(), blueCol.GetG(), blueCol.GetB()));
            g.DrawString(L"MIT LICENSE", -1, &fPill, ossBadge, &sfCenter, &blueBrush);
            g.DrawString(
                win_l10n::Tr(
                    isEn,
                    L"Ph\u00E1t tri\u1EC3n minh b\u1EA1ch b\u1EB1ng C++20, m\u1ECDi ng\u01B0\u1EDDi c\u00F3 th\u1EC3 ki\u1EC3m tra m\u00E3 ngu\u1ED3n v\u00E0 \u0111\u00F3ng g\u00F3p tr\u00EAn GitHub.",
                    L"Built transparently in modern C++20. Anyone can inspect the code and contribute on GitHub."
                ),
                -1, &fSub, RectF(360.0f * s, 209.0f * s, 286.0f * s, 54.0f * s), &sfWrap, &secondaryBrush
            );

            DrawCard(g, RectF(20.0f * s, 284.0f * s, 640.0f * s, 64.0f * s), 10.0f * s, cardCol, cardBorderCol);

            auto drawLinkBtn = [&](float bx, float bw, const WCHAR *label, bool hovered, bool primaryCta) {
                RectF btnR(bx * s, 298.0f * s, bw * s, 36.0f * s);
                if (primaryCta) {
                    FillRoundRect(g, btnR, 8.0f * s, hovered ? Color(255, 0, 108, 230) : blueCol);
                    g.DrawString(label, -1, &fBodyBold, btnR, &sfCenter, &whiteTextBrush);
                } else {
                    FillRoundRect(
                        g, btnR, 8.0f * s,
                        hovered
                            ? (isDark ? Color(255, 58, 58, 76) : Color(255, 236, 238, 248))
                            : (isDark ? Color(255, 46, 46, 60) : Color(255, 245, 245, 249))
                    );
                    DrawRoundRect(g, btnR, 8.0f * s, isDark ? Color(255, 72, 72, 92) : Color(255, 222, 222, 228), 1.0f * s);
                    g.DrawString(label, -1, &fSub, btnR, &sfCenter, &primaryBrush);
                }
            };

            drawLinkBtn(32.0f, 197.0f, win_l10n::Tr(isEn, L"G\u00F3p \u00FD & B\u00E1o l\u1ED7i", L"Feedback & Bugs"), st->hoveredRegion == HitRegion::RowFeedback, true);
            drawLinkBtn(241.0f, 197.0f, win_l10n::Tr(isEn, L"C\u1ED9ng \u0111\u1ED3ng Zalo \u2197", L"Zalo Community \u2197"), st->hoveredRegion == HitRegion::RowZalo, false);
            drawLinkBtn(450.0f, 198.0f, win_l10n::Tr(isEn, L"M\u00E3 ngu\u1ED3n GitHub \u2197", L"GitHub Source \u2197"), st->hoveredRegion == HitRegion::RowGitHub, false);
        }

        g.FillRectangle(&barBrush, 0.0f, 384.0f * s, static_cast<float>(width), 40.0f * s);
        g.DrawLine(&divPen, 0.0f, 384.0f * s, static_cast<float>(width), 384.0f * s);

        SolidBrush greenDotBrush(Color(255, 34, 197, 94));
        g.FillEllipse(&greenDotBrush, RectF(20.0f * s, 401.0f * s, 6.5f * s, 6.5f * s));
        g.DrawString(
            win_l10n::Tr(
                isEn,
                L"Song ng\u1EEF Anh\u2013Vi\u1EC7t \u2022 Ch\u00EDnh t\u1EA3 chu\u1EA9n m\u1EDBi t\u1EF1 \u0111\u1ED9ng",
                L"Smart Bilingual EN\u2013VI \u2022 Modern Orthography"
            ),
            -1, &fFooter, RectF(32.0f * s, 384.0f * s, 366.0f * s, 40.0f * s), &sfLeft, &secondaryBrush
        );

        RectF langPill(406.0f * s, 391.0f * s, 64.0f * s, 26.0f * s);
        FillRoundRect(
            g, langPill, 13.0f * s,
            st->hoveredRegion == HitRegion::FooterLanguage
                ? (isDark ? Color(255, 58, 58, 76) : Color(255, 232, 234, 244))
                : (isDark ? Color(255, 42, 42, 54) : Color(255, 242, 242, 247))
        );
        DrawRoundRect(g, langPill, 13.0f * s, isDark ? Color(255, 70, 70, 88) : Color(255, 214, 214, 224), 1.0f * s);
        std::wstring langLabel = std::wstring(win_l10n::LanguageShortLabel(st->prefs.uiLanguage)) + L" \u25BE";
        g.DrawString(langLabel.c_str(), -1, &fFooterBold, langPill, &sfCenter, &primaryBrush);

        RectF fbPill(478.0f * s, 391.0f * s, 118.0f * s, 26.0f * s);
        FillRoundRect(
            g, fbPill, 13.0f * s,
            st->hoveredRegion == HitRegion::FooterFeedback
                ? Color(isDark ? 85 : 55, blueCol.GetR(), blueCol.GetG(), blueCol.GetB())
                : Color(isDark ? 55 : 32, blueCol.GetR(), blueCol.GetG(), blueCol.GetB())
        );
        DrawRoundRect(g, fbPill, 13.0f * s, Color(140, blueCol.GetR(), blueCol.GetG(), blueCol.GetB()), 1.0f * s);
        g.DrawString(win_l10n::Tr(isEn, L"G\u00F3p \u00FD & B\u00E1o l\u1ED7i", L"Feedback & Bugs"), -1, &fFooterBold, fbPill, &sfCenter, &blueBrush);

        g.DrawString(L"\u2022", -1, &fFooter, RectF(598.0f * s, 384.0f * s, 12.0f * s, 40.0f * s), &sfCenter, &secondaryBrush);
        g.DrawString(L"GitHub", -1, &fFooter, RectF(610.0f * s, 384.0f * s, 50.0f * s, 40.0f * s), &sfCenter, &secondaryBrush);
    }

    BitBlt(hdc, 0, 0, width, height, memDC, 0, 0, SRCCOPY);
    SelectObject(memDC, oldBmp);
    DeleteObject(memBmp);
    DeleteDC(memDC);
}

static void OpenMicrosoftStorePage(HWND hwnd) {
    HINSTANCE res = ShellExecuteW(
        hwnd,
        L"open",
        L"ms-windows-store://pdp/?productid=9PF5K64GXXSH",
        nullptr,
        nullptr,
        SW_SHOWNORMAL
    );
    if (reinterpret_cast<INT_PTR>(res) <= 32) {
        ShellExecuteW(
            hwnd,
            L"open",
            L"https://apps.microsoft.com/detail/9PF5K64GXXSH",
            nullptr,
            nullptr,
            SW_SHOWNORMAL
        );
    }
}

static void OpenMacroJsonInNotepad(HWND hwnd) {
    WCHAR appData[MAX_PATH] = {};
    if (ExpandEnvironmentStringsW(L"%APPDATA%\\VieLotusIM", appData, MAX_PATH) > 0) {
        CreateDirectoryW(appData, nullptr);
        vielotus_win_installer::GrantAppContainerReadExecuteAcl(appData);
        std::wstring macroPath = std::wstring(appData) + L"\\macros.json";
        if (GetFileAttributesW(macroPath.c_str()) == INVALID_FILE_ATTRIBUTES) {
            HANDLE hFile = CreateFileW(macroPath.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr);
            if (hFile != INVALID_HANDLE_VALUE) {
                const char *defaultJson = "{\r\n  \"ks\": \"Kh\xC3\xA1" "ch s\xE1\xBA\xA1n\",\r\n  \"vn\": \"Vi\xE1\xBB\x87t Nam\",\r\n  \"tphcm\": \"TP. H\xE1\xBB\x93 Ch\xC3\xAD Minh\",\r\n  \"ko\": \"kh\xC3\xB4ng\",\r\n  \"dc\": \"\xC4\x91\xC6\xB0\xE1\xBB\xA3" "c\"\r\n}\r\n";
                DWORD written = 0;
                WriteFile(hFile, defaultJson, static_cast<DWORD>(strlen(defaultJson)), &written, nullptr);
                CloseHandle(hFile);
            }
        }
        vielotus_win_installer::GrantAppContainerReadExecuteAcl(macroPath);
        ShellExecuteW(hwnd, L"open", L"notepad.exe", macroPath.c_str(), nullptr, SW_SHOWNORMAL);
    }
}

// ============================================================================
// Native Win32/GDI+ Feedback & Bug Report Dialog (Out-of-process safe)
// ============================================================================

enum class FeedbackHit {
    None = 0,
    BtnClose,
    CatWordBug,
    CatAppCompat,
    CatFeatureReq,
    CatGeneral,
    BarDiagToggle,
    BtnCopyReport,
    BtnOpenZalo,
    BtnSendEmail,
    BtnCreateIssue
};

struct FeedbackDialogState {
    VieLotusWindowsPrefs prefs{};
    std::wstring cachedDiagnostics{};
    bool isDark{false};
    float dpiScale{1.0f};
    int category{0}; // 0=WordBug, 1=AppCompat, 2=FeatureReq, 3=General
    bool includeDiagnostics{true};
    bool copiedBanner{false};
    FeedbackHit hovered{FeedbackHit::None};
    Image *pAppIcon{nullptr};
    HFONT hEditFont{nullptr};
    HBRUSH hEditBgBrush{nullptr};
    HWND hEditRaw{nullptr};
    HWND hEditActual{nullptr};
    HWND hEditExpected{nullptr};
    HWND hEditApp{nullptr};
    HWND hEditContact{nullptr};
    HWND hEditNotes{nullptr};
};

static std::wstring GetEditControlText(HWND hEdit) {
    if (!hEdit) return L"";
    int len = GetWindowTextLengthW(hEdit);
    if (len <= 0) return L"";
    std::wstring buf(static_cast<size_t>(len) + 1, L'\0');
    GetWindowTextW(hEdit, &buf[0], len + 1);
    buf.resize(static_cast<size_t>(len));
    return buf;
}

static std::wstring GetWindowsDiagnosticsSummary(const VieLotusWindowsPrefs &prefs) {
    const bool isEn = win_l10n::ResolveWindowsIsEnglish(prefs.uiLanguage);
    SYSTEM_INFO si{};
    GetNativeSystemInfo(&si);
    const wchar_t *arch = L"x64";
    if (si.wProcessorArchitecture == PROCESSOR_ARCHITECTURE_ARM64) {
        arch = L"ARM64";
    } else if (si.wProcessorArchitecture == PROCESSOR_ARCHITECTURE_INTEL) {
        arch = L"x86";
    }

    DWORD buildNum = 0;
    HKEY hVer = nullptr;
    if (RegOpenKeyExW(HKEY_LOCAL_MACHINE, L"SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion", 0, KEY_READ | KEY_WOW64_64KEY, &hVer) == ERROR_SUCCESS && hVer) {
        WCHAR buildStr[32] = {};
        DWORD cb = sizeof(buildStr);
        if (RegQueryValueExW(hVer, L"CurrentBuildNumber", nullptr, nullptr, reinterpret_cast<LPBYTE>(buildStr), &cb) == ERROR_SUCCESS) {
            buildNum = static_cast<DWORD>(_wtoi(buildStr));
        }
        RegCloseKey(hVer);
    }

    WCHAR summary[256] = {};
    StringCchPrintfW(
        summary,
        ARRAYSIZE(summary),
        win_l10n::Tr(
            isEn,
            L"Sen Vi\u1EC7t v2.0.10 \u2022 Windows %s (Build %lu, %s) \u2022 %s \u2022 D\u1EA5u tr\u01B0\u1EDBc \u00E2m: %s \u2022 G\u00F5 t\u1EAFt: %s",
            L"Sen Vi\u1EC7t v2.0.10 \u2022 Windows %s (Build %lu, %s) \u2022 %s \u2022 Tone-First: %s \u2022 Macros: %s"
        ),
        (buildNum >= 22000) ? L"11" : L"10",
        static_cast<unsigned long>(buildNum),
        arch,
        prefs.isVni
            ? win_l10n::Tr(isEn, L"Chu\u1EA9n VNI", L"VNI")
            : win_l10n::Tr(isEn, L"Chu\u1EA9n Telex", L"Telex"),
        prefs.senFlex
            ? win_l10n::Tr(isEn, L"B\u1EACT", L"ON")
            : win_l10n::Tr(isEn, L"T\u1EAET", L"OFF"),
        prefs.macroEnabled
            ? win_l10n::Tr(isEn, L"B\u1EACT", L"ON")
            : win_l10n::Tr(isEn, L"T\u1EAET", L"OFF")
    );
    std::wstring out(summary);
    auto conflicts = vielotus_win_installer::DetectConflictingHookImes();
    if (!conflicts.empty()) {
        out += win_l10n::Tr(isEn, L" \u2022 C\u1EA3nh b\u00E1o xung \u0111\u1ED9t: ", L" \u2022 Conflict: ");
        out += vielotus_win_installer::FormatConflictingImeNames(conflicts);
    }
    return out;
}

static std::wstring BuildFeedbackReportMarkdown(FeedbackDialogState *st, bool includeContact) {
    if (!st) return L"";
    const bool isEn = win_l10n::ResolveWindowsIsEnglish(st->prefs.uiLanguage);
    const wchar_t *catNamesVi[4] = {
        L"L\u1ED7i g\u00F5 t\u1EEB / Song ng\u1EEF",
        L"T\u01B0\u01A1ng th\u00EDch App / Web",
        L"\u0110\u1EC1 xu\u1EA5t t\u00EDnh n\u0103ng",
        L"G\u00F3p \u00FD chung"
    };
    const wchar_t *catNamesEn[4] = {
        L"Word / Bilingual Bug",
        L"App / Web Compat",
        L"Feature Request",
        L"General Feedback"
    };
    int catIdx = (st->category >= 0 && st->category < 4) ? st->category : 0;

    std::wstring raw = GetEditControlText(st->hEditRaw);
    std::wstring actual = GetEditControlText(st->hEditActual);
    std::wstring expected = GetEditControlText(st->hEditExpected);
    std::wstring app = GetEditControlText(st->hEditApp);
    std::wstring contact = includeContact ? GetEditControlText(st->hEditContact) : L"";
    std::wstring notes = GetEditControlText(st->hEditNotes);

    std::wstring md = L"### [Sen Vi\u1EC7t Windows] ";
    md += isEn ? catNamesEn[catIdx] : catNamesVi[catIdx];
    md += L"\r\n\r\n";

    if (!raw.empty() || !actual.empty() || !expected.empty()) {
        const wchar_t *emptyVal = win_l10n::Tr(isEn, L"(tr\u1ED1ng)", L"(empty)");
        md += win_l10n::Tr(isEn, L"- **Ph\u00EDm \u0111\u00E3 g\u00F5 (Raw):** `", L"- **Typed Keys (Raw):** `") + (raw.empty() ? emptyVal : raw) + L"`\r\n";
        md += win_l10n::Tr(isEn, L"- **Sen Vi\u1EC7t hi\u1EC7n ra:** `", L"- **Actual Output:** `") + (actual.empty() ? emptyVal : actual) + L"`\r\n";
        md += win_l10n::Tr(isEn, L"- **Mong mu\u1ED1n \u0111\u00FAng:** `", L"- **Expected Output:** `") + (expected.empty() ? emptyVal : expected) + L"`\r\n";
    }
    if (!app.empty()) {
        md += win_l10n::Tr(isEn, L"- **\u1EE8ng d\u1EE5ng / Ch\u1EE7 \u0111\u1EC1:** ", L"- **App / Topic:** ") + app + L"\r\n";
    }
    if (includeContact && !contact.empty()) {
        md += win_l10n::Tr(isEn, L"- **Li\u00EAn h\u1EC7 ph\u1EA3n h\u1ED3i:** ", L"- **Contact:** ") + contact + L"\r\n";
    }
    if (!notes.empty()) {
        md += win_l10n::Tr(isEn, L"\r\n**M\u00F4 t\u1EA3 chi ti\u1EBFt:**\r\n", L"\r\n**Details:**\r\n") + notes + L"\r\n";
    }
    if (st->includeDiagnostics) {
        const std::wstring &diag = st->cachedDiagnostics.empty()
            ? GetWindowsDiagnosticsSummary(st->prefs)
            : st->cachedDiagnostics;
        md += win_l10n::Tr(isEn, L"\r\n---\r\n**C\u1EA5u h\u00ECnh k\u1EF9 thu\u1EADt:** `", L"\r\n---\r\n**Diagnostics:** `") + diag + L"`\r\n";
    }
    return md;
}

static std::wstring BuildFeedbackIssueTitle(FeedbackDialogState *st) {
    if (!st) return L"[Windows] Sen Vi\u1EC7t Feedback";
    const bool isEn = win_l10n::ResolveWindowsIsEnglish(st->prefs.uiLanguage);
    const wchar_t *catShortVi[4] = {
        L"[Windows][L\u1ED7i g\u00F5 t\u1EEB] ",
        L"[Windows][T\u01B0\u01A1ng th\u00EDch App] ",
        L"[Windows][\u0110\u1EC1 xu\u1EA5t] ",
        L"[Windows][G\u00F3p \u00FD] "
    };
    const wchar_t *catShortEn[4] = {
        L"[Windows][Word Bug] ",
        L"[Windows][App Compat] ",
        L"[Windows][Feature Request] ",
        L"[Windows][Feedback] "
    };
    int catIdx = (st->category >= 0 && st->category < 4) ? st->category : 0;
    std::wstring raw = GetEditControlText(st->hEditRaw);
    std::wstring expected = GetEditControlText(st->hEditExpected);
    std::wstring app = GetEditControlText(st->hEditApp);

    std::wstring title = isEn ? catShortEn[catIdx] : catShortVi[catIdx];
    if (!raw.empty() && !expected.empty()) {
        title += isEn
            ? (L"Typed '" + raw + L"' expected '" + expected + L"'")
            : (L"G\u00F5 '" + raw + L"' mong mu\u1ED1n '" + expected + L"'");
    } else if (!app.empty()) {
        title += app;
    } else {
        title += win_l10n::Tr(
            isEn,
            L"B\u00E1o c\u00E1o t\u1EEB ng\u01B0\u1EDDi d\u00F9ng Sen Vi\u1EC7t v2.0.10",
            L"User report from Sen Vi\u1EC7t v2.0.10"
        );
    }
    return title;
}

static bool CopyWideTextToClipboard(HWND hwnd, const std::wstring &text) {
    if (!OpenClipboard(hwnd)) return false;
    EmptyClipboard();
    size_t bytes = (text.size() + 1) * sizeof(WCHAR);
    HGLOBAL hMem = GlobalAlloc(GMEM_MOVEABLE, bytes);
    if (!hMem) {
        CloseClipboard();
        return false;
    }
    void *ptr = GlobalLock(hMem);
    if (ptr) {
        memcpy(ptr, text.c_str(), bytes);
        GlobalUnlock(hMem);
    }
    SetClipboardData(CF_UNICODETEXT, hMem);
    CloseClipboard();
    return true;
}

static std::wstring UrlEncodeWideToUtf8W(const std::wstring &input) {
    if (input.empty()) return L"";
    int utf8Len = WideCharToMultiByte(CP_UTF8, 0, input.c_str(), static_cast<int>(input.size()), nullptr, 0, nullptr, nullptr);
    if (utf8Len <= 0) return L"";
    std::string utf8(static_cast<size_t>(utf8Len), '\0');
    WideCharToMultiByte(CP_UTF8, 0, input.c_str(), static_cast<int>(input.size()), &utf8[0], utf8Len, nullptr, nullptr);

    static const wchar_t kHex[] = L"0123456789ABCDEF";
    std::wstring out;
    out.reserve(utf8.size() * 3);
    for (unsigned char c : utf8) {
        if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') ||
            c == '-' || c == '_' || c == '.' || c == '~') {
            out.push_back(static_cast<wchar_t>(c));
        } else {
            out.push_back(L'%');
            out.push_back(kHex[(c >> 4) & 0x0F]);
            out.push_back(kHex[c & 0x0F]);
        }
    }
    return out;
}

static void LaunchBoundedReportUrl(
    HWND hwnd,
    bool isEn,
    const std::wstring &urlPrefixWithTitle,
    const std::wstring &encodedTitle,
    const std::wstring &markdownBody
) {
    static constexpr size_t kMaxShellUrlChars = 1800u;
    std::wstring url = urlPrefixWithTitle + encodedTitle + L"&body=" + UrlEncodeWideToUtf8W(markdownBody);
    if (url.size() > kMaxShellUrlChars) {
        const wchar_t *kFallbackNote = win_l10n::Tr(
            isEn,
            L"N\u1ED9i dung b\u00E1o c\u00E1o \u0111\u1EA7y \u0111\u1EE7 \u0111\u00E3 \u0111\u01B0\u1EE3c sao ch\u00E9p v\u00E0o Clipboard. Vui l\u00F2ng d\u00E1n (Ctrl+V) v\u00E0o \u0111\u00E2y.",
            L"Full report copied to Clipboard. Please paste (Ctrl+V) here."
        );
        const std::wstring fallbackSuffix = L"&body=" + UrlEncodeWideToUtf8W(kFallbackNote);
        std::wstring boundedTitle = encodedTitle;
        const size_t overhead = urlPrefixWithTitle.size() + fallbackSuffix.size();
        if (overhead < kMaxShellUrlChars && boundedTitle.size() > (kMaxShellUrlChars - overhead)) {
            size_t cut = kMaxShellUrlChars - overhead;
            // Never split a percent-encoded triplet (%XX) at the truncation boundary.
            if (cut >= 1 && boundedTitle[cut - 1] == L'%') {
                cut -= 1;
            } else if (cut >= 2 && boundedTitle[cut - 2] == L'%') {
                cut -= 2;
            }
            boundedTitle.resize(cut);
        } else if (overhead >= kMaxShellUrlChars) {
            boundedTitle.clear();
        }
        url = urlPrefixWithTitle + boundedTitle + fallbackSuffix;
    }
    ShellExecuteW(hwnd, L"open", url.c_str(), nullptr, nullptr, SW_SHOWNORMAL);
}

static FeedbackHit HitTestFeedbackUI(float x, float y) {
    if (PtInDipRect(x, y, 560.0f, 16.0f, 60.0f, 28.0f)) return FeedbackHit::BtnClose;
    if (PtInDipRect(x, y, 20.0f, 60.0f, 144.0f, 46.0f)) return FeedbackHit::CatWordBug;
    if (PtInDipRect(x, y, 172.0f, 60.0f, 144.0f, 46.0f)) return FeedbackHit::CatAppCompat;
    if (PtInDipRect(x, y, 324.0f, 60.0f, 144.0f, 46.0f)) return FeedbackHit::CatFeatureReq;
    if (PtInDipRect(x, y, 476.0f, 60.0f, 144.0f, 46.0f)) return FeedbackHit::CatGeneral;
    if (PtInDipRect(x, y, 20.0f, 354.0f, 600.0f, 40.0f)) return FeedbackHit::BarDiagToggle;
    if (PtInDipRect(x, y, 20.0f, 422.0f, 138.0f, 34.0f)) return FeedbackHit::BtnCopyReport;
    if (PtInDipRect(x, y, 166.0f, 422.0f, 144.0f, 34.0f)) return FeedbackHit::BtnOpenZalo;
    if (PtInDipRect(x, y, 318.0f, 422.0f, 138.0f, 34.0f)) return FeedbackHit::BtnSendEmail;
    if (PtInDipRect(x, y, 464.0f, 422.0f, 156.0f, 34.0f)) return FeedbackHit::BtnCreateIssue;
    return FeedbackHit::None;
}

static void RenderFeedbackDialogUI(HWND hwnd, HDC hdc, FeedbackDialogState *st) {
    if (!st) return;
    RECT rcClient{};
    GetClientRect(hwnd, &rcClient);
    int width = rcClient.right - rcClient.left;
    int height = rcClient.bottom - rcClient.top;
    if (width <= 0 || height <= 0) return;

    HDC memDC = CreateCompatibleDC(hdc);
    HBITMAP memBmp = CreateCompatibleBitmap(hdc, width, height);
    HBITMAP oldBmp = static_cast<HBITMAP>(SelectObject(memDC, memBmp));

    {
        Graphics g(memDC);
        g.SetSmoothingMode(SmoothingModeAntiAlias);
        g.SetTextRenderingHint(TextRenderingHintClearTypeGridFit);

        float s = st->dpiScale;
        bool isDark = st->isDark;
        const bool isEn = win_l10n::ResolveWindowsIsEnglish(st->prefs.uiLanguage);

        Color bgColor       = isDark ? Color(255, 22, 22, 29)    : Color(255, 245, 246, 250);
        Color cardBg        = isDark ? Color(255, 34, 34, 44)    : Color(255, 255, 255, 255);
        Color cardHoverBg   = isDark ? Color(255, 42, 42, 54)    : Color(255, 249, 250, 253);
        Color cardBorder    = isDark ? Color(255, 58, 58, 74)    : Color(255, 224, 226, 234);
        Color primaryText   = isDark ? Color(255, 245, 245, 247) : Color(255, 26, 26, 30);
        Color secondaryText = isDark ? Color(255, 162, 162, 174) : Color(255, 108, 108, 118);
        Color blueCol       = Color(255, 10, 132, 255);
        Color greenCol      = Color(255, 48, 209, 88);

        SolidBrush bgBrush(bgColor);
        g.FillRectangle(&bgBrush, 0, 0, width, height);

        FontFamily fontFamily(L"Segoe UI");
        Font fTitle(&fontFamily, 14.0f * s, FontStyleBold, UnitPixel);
        Font fSub(&fontFamily, 11.0f * s, FontStyleRegular, UnitPixel);
        Font fCatTitle(&fontFamily, 11.5f * s, FontStyleBold, UnitPixel);
        Font fCatSub(&fontFamily, 10.0f * s, FontStyleRegular, UnitPixel);
        Font fLabel(&fontFamily, 11.0f * s, FontStyleBold, UnitPixel);
        Font fBtn(&fontFamily, 11.5f * s, FontStyleBold, UnitPixel);

        SolidBrush primaryBrush(primaryText);
        SolidBrush secondaryBrush(secondaryText);
        SolidBrush blueBrush(blueCol);
        SolidBrush greenBrush(greenCol);
        SolidBrush whiteBrush(Color(255, 255, 255, 255));

        StringFormat sfLeft;
        sfLeft.SetAlignment(StringAlignmentNear);
        sfLeft.SetLineAlignment(StringAlignmentCenter);
        sfLeft.SetFormatFlags(StringFormatFlagsNoWrap);

        StringFormat sfCenter;
        sfCenter.SetAlignment(StringAlignmentCenter);
        sfCenter.SetLineAlignment(StringAlignmentCenter);
        sfCenter.SetFormatFlags(StringFormatFlagsNoWrap);

        RectF iconRect(20.0f * s, 14.0f * s, 34.0f * s, 34.0f * s);
        if (st->pAppIcon && st->pAppIcon->GetLastStatus() == Ok) {
            g.SetInterpolationMode(InterpolationModeHighQualityBicubic);
            g.DrawImage(st->pAppIcon, iconRect);
        } else {
            FillRoundRect(g, iconRect, 8.0f * s, Color(255, 232, 93, 117));
            g.DrawString(L"SV", -1, &fCatTitle, iconRect, &sfCenter, &whiteBrush);
        }

        g.DrawString(win_l10n::Tr(isEn, L"G\u00F3p \u00FD & B\u00E1o l\u1ED7i nhanh", L"Quick Feedback & Bug Report"), -1, &fTitle, RectF(62.0f * s, 12.0f * s, 480.0f * s, 20.0f * s), &sfLeft, &primaryBrush);
        g.DrawString(
            win_l10n::Tr(
                isEn,
                L"\u00DD ki\u1EBFn c\u1EE7a b\u1EA1n gi\u00FAp Sen Vi\u1EC7t ho\u00E0n thi\u1EC7n m\u1ED7i ng\u00E0y \u2014 g\u1EEDi b\u00E1o c\u00E1o trong 10 gi\u00E2y.",
                L"Your feedback helps Sen Vi\u1EC7t improve every day \u2014 submit a report in seconds."
            ),
            -1, &fSub, RectF(62.0f * s, 32.0f * s, 490.0f * s, 18.0f * s), &sfLeft, &secondaryBrush
        );

        RectF closeRect(560.0f * s, 16.0f * s, 60.0f * s, 28.0f * s);
        FillRoundRect(g, closeRect, 8.0f * s, st->hovered == FeedbackHit::BtnClose ? cardHoverBg : cardBg);
        DrawRoundRect(g, closeRect, 8.0f * s, cardBorder, 1.0f * s);
        g.DrawString(win_l10n::Tr(isEn, L"\u0110\u00F3ng", L"Close"), -1, &fLabel, closeRect, &sfCenter, &primaryBrush);

        const wchar_t *catTitlesVi[4] = {
            L"L\u1ED7i g\u00F5 t\u1EEB / Song ng\u1EEF",
            L"T\u01B0\u01A1ng th\u00EDch App / Web",
            L"\u0110\u1EC1 xu\u1EA5t t\u00EDnh n\u0103ng",
            L"G\u00F3p \u00FD chung"
        };
        const wchar_t *catTitlesEn[4] = {
            L"Word / Bilingual Bug",
            L"App / Web Compat",
            L"Feature Request",
            L"General Feedback"
        };
        const wchar_t *catSubsVi[4] = {
            L"Sai d\u1EA5u, kh\u00F4i ph\u1EE5c t\u1EEB",
            L"Nh\u1EA3y con tr\u1ECF, l\u1EB7p ch\u1EEF",
            L"\u00DD t\u01B0\u1EDFng, ph\u00EDm t\u1EAFt, t\u1EEB \u0111i\u1EC3n",
            L"C\u1EA3m nh\u1EADn & h\u1ED7 tr\u1EE3"
        };
        const wchar_t *catSubsEn[4] = {
            L"Wrong tone, auto-restore",
            L"Cursor jump, doubled keys",
            L"Ideas, shortcuts, dictionary",
            L"Thoughts & support"
        };
        FeedbackHit catHits[4] = {
            FeedbackHit::CatWordBug,
            FeedbackHit::CatAppCompat,
            FeedbackHit::CatFeatureReq,
            FeedbackHit::CatGeneral
        };
        for (int i = 0; i < 4; ++i) {
            float cx = (20.0f + i * 152.0f) * s;
            RectF cRect(cx, 60.0f * s, 144.0f * s, 46.0f * s);
            bool sel = (st->category == i);
            bool hov = (st->hovered == catHits[i]);
            Color fill = sel ? (isDark ? Color(255, 22, 46, 82) : Color(255, 232, 244, 255))
                             : (hov ? cardHoverBg : cardBg);
            FillRoundRect(g, cRect, 9.0f * s, fill);
            DrawRoundRect(g, cRect, 9.0f * s, sel ? blueCol : cardBorder, (sel ? 1.8f : 1.0f) * s);
            g.DrawString(isEn ? catTitlesEn[i] : catTitlesVi[i], -1, &fCatTitle, RectF(cx + 8.0f * s, 65.0f * s, 128.0f * s, 18.0f * s), &sfLeft, sel ? &blueBrush : &primaryBrush);
            g.DrawString(isEn ? catSubsEn[i] : catSubsVi[i], -1, &fCatSub, RectF(cx + 8.0f * s, 84.0f * s, 128.0f * s, 16.0f * s), &sfLeft, &secondaryBrush);
        }

        g.DrawString(win_l10n::Tr(isEn, L"1. Ph\u00EDm \u0111\u00E3 g\u00F5 (Raw):", L"1. Typed Keys (Raw):"), -1, &fLabel, RectF(20.0f * s, 114.0f * s, 194.0f * s, 18.0f * s), &sfLeft, &primaryBrush);
        FillRoundRect(g, RectF(20.0f * s, 134.0f * s, 194.0f * s, 32.0f * s), 7.0f * s, cardBg);
        DrawRoundRect(g, RectF(20.0f * s, 134.0f * s, 194.0f * s, 32.0f * s), 7.0f * s, cardBorder, 1.0f * s);

        g.DrawString(win_l10n::Tr(isEn, L"2. Sen Vi\u1EC7t hi\u1EC7n ra:", L"2. Actual Output:"), -1, &fLabel, RectF(223.0f * s, 114.0f * s, 194.0f * s, 18.0f * s), &sfLeft, &primaryBrush);
        FillRoundRect(g, RectF(223.0f * s, 134.0f * s, 194.0f * s, 32.0f * s), 7.0f * s, cardBg);
        DrawRoundRect(g, RectF(223.0f * s, 134.0f * s, 194.0f * s, 32.0f * s), 7.0f * s, cardBorder, 1.0f * s);

        g.DrawString(win_l10n::Tr(isEn, L"3. Mong mu\u1ED1n \u0111\u00FAng:", L"3. Expected Output:"), -1, &fLabel, RectF(426.0f * s, 114.0f * s, 194.0f * s, 18.0f * s), &sfLeft, &primaryBrush);
        FillRoundRect(g, RectF(426.0f * s, 134.0f * s, 194.0f * s, 32.0f * s), 7.0f * s, cardBg);
        DrawRoundRect(g, RectF(426.0f * s, 134.0f * s, 194.0f * s, 32.0f * s), 7.0f * s, cardBorder, 1.0f * s);

        g.DrawString(win_l10n::Tr(isEn, L"\u1EE8ng d\u1EE5ng / Tr\u00ECnh duy\u1EC7t g\u1EB7p l\u1ED7i (ho\u1EB7c Ch\u1EE7 \u0111\u1EC1):", L"App / Browser or Topic (Optional):"), -1, &fLabel, RectF(20.0f * s, 174.0f * s, 295.0f * s, 18.0f * s), &sfLeft, &primaryBrush);
        FillRoundRect(g, RectF(20.0f * s, 194.0f * s, 295.0f * s, 32.0f * s), 7.0f * s, cardBg);
        DrawRoundRect(g, RectF(20.0f * s, 194.0f * s, 295.0f * s, 32.0f * s), 7.0f * s, cardBorder, 1.0f * s);

        g.DrawString(win_l10n::Tr(isEn, L"Email / S\u0110T Zalo li\u00EAn h\u1EC7 (Tu\u1EF3 ch\u1ECDn \u2014 kh\u00F4ng \u0111\u01B0a l\u00EAn GitHub):", L"Contact Email / Zalo (Optional \u2014 omitted from GitHub):"), -1, &fLabel, RectF(325.0f * s, 174.0f * s, 295.0f * s, 18.0f * s), &sfLeft, &primaryBrush);
        FillRoundRect(g, RectF(325.0f * s, 194.0f * s, 295.0f * s, 32.0f * s), 7.0f * s, cardBg);
        DrawRoundRect(g, RectF(325.0f * s, 194.0f * s, 295.0f * s, 32.0f * s), 7.0f * s, cardBorder, 1.0f * s);

        g.DrawString(win_l10n::Tr(isEn, L"M\u00F4 t\u1EA3 chi ti\u1EBFt / C\u00E1c b\u01B0\u1EDBc t\u00E1i hi\u1EC7n:", L"Details / Steps to Reproduce:"), -1, &fLabel, RectF(20.0f * s, 232.0f * s, 600.0f * s, 18.0f * s), &sfLeft, &primaryBrush);
        FillRoundRect(g, RectF(20.0f * s, 252.0f * s, 600.0f * s, 94.0f * s), 7.0f * s, cardBg);
        DrawRoundRect(g, RectF(20.0f * s, 252.0f * s, 600.0f * s, 94.0f * s), 7.0f * s, cardBorder, 1.0f * s);

        RectF diagRect(20.0f * s, 354.0f * s, 600.0f * s, 40.0f * s);
        FillRoundRect(g, diagRect, 8.0f * s, st->hovered == FeedbackHit::BarDiagToggle ? cardHoverBg : cardBg);
        DrawRoundRect(g, diagRect, 8.0f * s, cardBorder, 1.0f * s);
        g.DrawString(
            win_l10n::Tr(
                isEn,
                L"\u0110\u00EDnh k\u00E8m c\u1EA5u h\u00ECnh k\u1EF9 thu\u1EADt (phi\u00EAn b\u1EA3n Windows, CPU, ki\u1EC3u g\u00F5 \u2014 kh\u00F4ng ch\u1EE9a d\u1EEF li\u1EC7u c\u00E1 nh\u00E2n)",
                L"Attach anonymous diagnostics (Windows version, CPU, IME settings \u2014 no personal data)"
            ),
            -1, &fLabel, RectF(32.0f * s, 356.0f * s, 520.0f * s, 18.0f * s), &sfLeft, &primaryBrush
        );
        // Use cached summary computed once in WM_CREATE — never call process enumeration inside WM_PAINT.
        g.DrawString(st->cachedDiagnostics.c_str(), -1, &fCatSub, RectF(32.0f * s, 374.0f * s, 520.0f * s, 16.0f * s), &sfLeft, &secondaryBrush);
        {
            float swW = 36.0f, swH = 20.0f, swX = 568.0f, swY = 364.0f;
            RectF swTrack(swX * s, swY * s, swW * s, swH * s);
            Color trackCol = st->includeDiagnostics ? greenCol : (isDark ? Color(255, 68, 68, 84) : Color(255, 212, 212, 220));
            FillRoundRect(g, swTrack, 10.0f * s, trackCol);
            float knobD = 16.0f;
            float knobX = st->includeDiagnostics ? (swX + swW - knobD - 2.0f) : (swX + 2.0f);
            g.FillEllipse(&whiteBrush, RectF(knobX * s, (swY + 2.0f) * s, knobD * s, knobD * s));
        }

        if (st->copiedBanner) {
            g.DrawString(
                win_l10n::Tr(
                    isEn,
                    L"\u2713 \u0110\u00E3 sao ch\u00E9p b\u00E1o c\u00E1o v\u00E0o Clipboard! B\u1EA1n c\u00F3 th\u1EC3 d\u00E1n (Ctrl+V) ngay v\u00E0o Zalo / Email / GitHub.",
                    L"\u2713 Report copied to Clipboard! Paste (Ctrl+V) directly into Zalo / Email / GitHub."
                ),
                -1, &fLabel, RectF(20.0f * s, 398.0f * s, 600.0f * s, 20.0f * s), &sfLeft, &greenBrush
            );
        } else {
            g.DrawString(
                win_l10n::Tr(
                    isEn,
                    L"M\u1EB9o: Khi b\u1EA5m Zalo / Email / GitHub, n\u1ED9i dung b\u00E1o c\u00E1o c\u0169ng t\u1EF1 \u0111\u1ED9ng \u0111\u01B0\u1EE3c sao ch\u00E9p v\u00E0o Clipboard.",
                    L"Tip: Clicking Zalo / Email / GitHub also copies your formatted report to the Clipboard."
                ),
                -1, &fCatSub, RectF(20.0f * s, 398.0f * s, 600.0f * s, 20.0f * s), &sfLeft, &secondaryBrush
            );
        }

        RectF bCopy(20.0f * s, 422.0f * s, 138.0f * s, 34.0f * s);
        FillRoundRect(g, bCopy, 8.0f * s, st->hovered == FeedbackHit::BtnCopyReport ? cardHoverBg : cardBg);
        DrawRoundRect(g, bCopy, 8.0f * s, cardBorder, 1.0f * s);
        g.DrawString(win_l10n::Tr(isEn, L"Sao ch\u00E9p B\u00E1o c\u00E1o", L"Copy Report"), -1, &fBtn, bCopy, &sfCenter, &primaryBrush);

        RectF bZalo(166.0f * s, 422.0f * s, 144.0f * s, 34.0f * s);
        FillRoundRect(g, bZalo, 8.0f * s, st->hovered == FeedbackHit::BtnOpenZalo ? cardHoverBg : cardBg);
        DrawRoundRect(g, bZalo, 8.0f * s, Color(140, blueCol.GetR(), blueCol.GetG(), blueCol.GetB()), 1.0f * s);
        g.DrawString(win_l10n::Tr(isEn, L"Nh\u00F3m Zalo H\u1ED7 tr\u1EE3 \u2197", L"Zalo Support \u2197"), -1, &fBtn, bZalo, &sfCenter, &blueBrush);

        RectF bEmail(318.0f * s, 422.0f * s, 138.0f * s, 34.0f * s);
        FillRoundRect(g, bEmail, 8.0f * s, st->hovered == FeedbackHit::BtnSendEmail ? cardHoverBg : cardBg);
        DrawRoundRect(g, bEmail, 8.0f * s, cardBorder, 1.0f * s);
        g.DrawString(win_l10n::Tr(isEn, L"G\u1EEDi qua Email \u2197", L"Send Email \u2197"), -1, &fBtn, bEmail, &sfCenter, &primaryBrush);

        RectF bIssue(464.0f * s, 422.0f * s, 156.0f * s, 34.0f * s);
        FillRoundRect(
            g, bIssue, 8.0f * s,
            st->hovered == FeedbackHit::BtnCreateIssue ? Color(255, 0, 112, 235) : blueCol
        );
        g.DrawString(win_l10n::Tr(isEn, L"T\u1EA1o GitHub Issue \u2197", L"Create GitHub Issue \u2197"), -1, &fBtn, bIssue, &sfCenter, &whiteBrush);
    }

    BitBlt(hdc, 0, 0, width, height, memDC, 0, 0, SRCCOPY);
    SelectObject(memDC, oldBmp);
    DeleteObject(memBmp);
    DeleteDC(memDC);
}

static LRESULT CALLBACK VieLotusFeedbackWndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    auto *st = reinterpret_cast<FeedbackDialogState *>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
    switch (msg) {
    case WM_CREATE: {
        CREATESTRUCTW *cs = reinterpret_cast<CREATESTRUCTW *>(lParam);
        st = reinterpret_cast<FeedbackDialogState *>(cs->lpCreateParams);
        SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(st));

        HDC hdc = GetDC(hwnd);
        int dpiY = GetDeviceCaps(hdc, LOGPIXELSY);
        ReleaseDC(hwnd, hdc);
        st->dpiScale = (dpiY > 0) ? (static_cast<float>(dpiY) / 96.0f) : 1.0f;
        st->isDark = IsWindowsDarkMode();
        st->pAppIcon = LoadEmbeddedPngImage(102);
        st->cachedDiagnostics = GetWindowsDiagnosticsSummary(st->prefs);

        DWORD cornerPref = 2; // DWMWCP_ROUND
        DwmSetWindowAttribute(hwnd, DWMWA_WINDOW_CORNER_PREFERENCE, &cornerPref, sizeof(cornerPref));
        BOOL darkTitle = st->isDark ? TRUE : FALSE;
        DwmSetWindowAttribute(hwnd, 20, &darkTitle, sizeof(darkTitle));

        float s = st->dpiScale;
        HINSTANCE hAppInst = ResolveSettingsInstance(nullptr);
        st->hEditBgBrush = CreateSolidBrush(st->isDark ? RGB(34, 34, 44) : RGB(255, 255, 255));
        st->hEditFont = CreateFontW(
            -static_cast<int>(12.0f * s + 0.5f), 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
            DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
            DEFAULT_PITCH | FF_SWISS, L"Segoe UI"
        );

        auto createField = [&](int xDip, int yDip, int wDip, int hDip, int id, const wchar_t *cue, DWORD extraStyle = ES_AUTOHSCROLL) -> HWND {
            HWND hEd = CreateWindowExW(
                0, L"EDIT", L"",
                WS_CHILD | WS_VISIBLE | WS_TABSTOP | extraStyle,
                static_cast<int>(xDip * s), static_cast<int>(yDip * s),
                static_cast<int>(wDip * s), static_cast<int>(hDip * s),
                hwnd, reinterpret_cast<HMENU>(static_cast<INT_PTR>(id)), hAppInst, nullptr
            );
            if (hEd) {
                if (st->hEditFont) SendMessageW(hEd, WM_SETFONT, reinterpret_cast<WPARAM>(st->hEditFont), TRUE);
                if (cue && cue[0]) SendMessageW(hEd, 0x1501 /* EM_SETCUEBANNER */, TRUE, reinterpret_cast<LPARAM>(cue));
            }
            return hEd;
        };

        const bool fbEn = win_l10n::ResolveWindowsIsEnglish(st->prefs.uiLanguage);
        st->hEditRaw      = createField(26, 141, 182, 20, 2101, win_l10n::Tr(fbEn, L"VD: truowngr, 12haf...", L"e.g. truowngr, 12haf..."));
        st->hEditActual   = createField(229, 141, 182, 20, 2102, win_l10n::Tr(fbEn, L"VD: truowngr, 12haf...", L"e.g. truowngr, 12haf..."));
        st->hEditExpected = createField(432, 141, 182, 20, 2103, win_l10n::Tr(fbEn, L"VD: tr\u01B0\u1EDFng, 12h\u00E0...", L"e.g. tr\u01B0\u1EDFng, 12h\u00E0..."));
        st->hEditApp      = createField(26, 201, 283, 20, 2104, win_l10n::Tr(fbEn, L"VD: Chrome, Zalo PC, Word, VS Code...", L"e.g. Chrome, Zalo PC, Word, VS Code..."));
        st->hEditContact  = createField(331, 201, 283, 20, 2105, win_l10n::Tr(fbEn, L"Email ho\u1EB7c S\u0110T Zalo (\u0111\u1EC3 nh\u1EADn ph\u1EA3n h\u1ED3i)...", L"Email or Zalo number (for follow-up)..."));
        st->hEditNotes    = createField(
            26, 258, 588, 82, 2106,
            win_l10n::Tr(
                fbEn,
                L"M\u00F4 t\u1EA3 th\u00EAm t\u00ECnh hu\u1ED1ng g\u1EB7p l\u1ED7i ho\u1EB7c \u00FD t\u01B0\u1EDFng c\u1EA3i ti\u1EBFn c\u1EE7a b\u1EA1n...",
                L"Describe what happened or share your feature idea..."
            ),
            ES_MULTILINE | ES_AUTOVSCROLL | ES_WANTRETURN | WS_VSCROLL
        );

        if (st->hEditRaw) SetFocus(st->hEditRaw);
        return 0;
    }

    case WM_CTLCOLOREDIT: {
        if (st && st->hEditBgBrush) {
            HDC hdcEdit = reinterpret_cast<HDC>(wParam);
            SetTextColor(hdcEdit, st->isDark ? RGB(245, 245, 247) : RGB(26, 26, 30));
            SetBkColor(hdcEdit, st->isDark ? RGB(34, 34, 44) : RGB(255, 255, 255));
            return reinterpret_cast<LRESULT>(st->hEditBgBrush);
        }
        break;
    }

    case WM_ERASEBKGND:
        return 1;

    case WM_PAINT: {
        PAINTSTRUCT ps{};
        HDC hdc = BeginPaint(hwnd, &ps);
        RenderFeedbackDialogUI(hwnd, hdc, st);
        EndPaint(hwnd, &ps);
        return 0;
    }

    case WM_MOUSEMOVE: {
        if (!st) break;
        float xDip = static_cast<float>(static_cast<short>(LOWORD(lParam))) / st->dpiScale;
        float yDip = static_cast<float>(static_cast<short>(HIWORD(lParam))) / st->dpiScale;
        FeedbackHit hit = HitTestFeedbackUI(xDip, yDip);
        if (hit != st->hovered) {
            st->hovered = hit;
            InvalidateRect(hwnd, nullptr, FALSE);
        }
        return 0;
    }

    case WM_SETCURSOR: {
        if (st && LOWORD(lParam) == HTCLIENT && st->hovered != FeedbackHit::None) {
            SetCursor(LoadCursorW(nullptr, MAKEINTRESOURCEW(32649))); // IDC_HAND
            return TRUE;
        }
        break;
    }

    case WM_LBUTTONDOWN: {
        if (!st) break;
        float xDip = static_cast<float>(static_cast<short>(LOWORD(lParam))) / st->dpiScale;
        float yDip = static_cast<float>(static_cast<short>(HIWORD(lParam))) / st->dpiScale;
        FeedbackHit hit = HitTestFeedbackUI(xDip, yDip);

        switch (hit) {
        case FeedbackHit::BtnClose:
            DestroyWindow(hwnd);
            break;
        case FeedbackHit::CatWordBug:
            st->category = 0;
            InvalidateRect(hwnd, nullptr, FALSE);
            break;
        case FeedbackHit::CatAppCompat:
            st->category = 1;
            InvalidateRect(hwnd, nullptr, FALSE);
            break;
        case FeedbackHit::CatFeatureReq:
            st->category = 2;
            InvalidateRect(hwnd, nullptr, FALSE);
            break;
        case FeedbackHit::CatGeneral:
            st->category = 3;
            InvalidateRect(hwnd, nullptr, FALSE);
            break;
        case FeedbackHit::BarDiagToggle:
            st->includeDiagnostics = !st->includeDiagnostics;
            InvalidateRect(hwnd, nullptr, FALSE);
            break;
        case FeedbackHit::BtnCopyReport: {
            std::wstring md = BuildFeedbackReportMarkdown(st, true);
            CopyWideTextToClipboard(hwnd, md);
            st->copiedBanner = true;
            InvalidateRect(hwnd, nullptr, FALSE);
            break;
        }
        case FeedbackHit::BtnOpenZalo: {
            std::wstring md = BuildFeedbackReportMarkdown(st, true);
            CopyWideTextToClipboard(hwnd, md);
            st->copiedBanner = true;
            InvalidateRect(hwnd, nullptr, FALSE);
            ShellExecuteW(hwnd, L"open", L"https://zalo.me/g/6wwyvywyvhsb0n6rwkze", nullptr, nullptr, SW_SHOWNORMAL);
            break;
        }
        case FeedbackHit::BtnSendEmail: {
            const bool includeContact = vielotus_tsf_guard::ShouldIncludeContactInFeedbackChannel(false);
            const bool isEn = win_l10n::ResolveWindowsIsEnglish(st->prefs.uiLanguage);
            std::wstring md = BuildFeedbackReportMarkdown(st, includeContact);
            std::wstring title = BuildFeedbackIssueTitle(st);
            CopyWideTextToClipboard(hwnd, md);
            st->copiedBanner = true;
            InvalidateRect(hwnd, nullptr, FALSE);
            LaunchBoundedReportUrl(
                hwnd,
                isEn,
                L"mailto:support@vielotus.org?subject=",
                UrlEncodeWideToUtf8W(title),
                md
            );
            break;
        }
        case FeedbackHit::BtnCreateIssue: {
            // Strip personal phone/email contact from public GitHub Issue URL/clipboard report.
            const bool includeContact = vielotus_tsf_guard::ShouldIncludeContactInFeedbackChannel(true);
            const bool isEn = win_l10n::ResolveWindowsIsEnglish(st->prefs.uiLanguage);
            std::wstring md = BuildFeedbackReportMarkdown(st, includeContact);
            std::wstring title = BuildFeedbackIssueTitle(st);
            CopyWideTextToClipboard(hwnd, md);
            st->copiedBanner = true;
            InvalidateRect(hwnd, nullptr, FALSE);
            LaunchBoundedReportUrl(
                hwnd,
                isEn,
                L"https://github.com/stevedat/VieLotus-IM/issues/new?title=",
                UrlEncodeWideToUtf8W(title),
                md
            );
            break;
        }
        default:
            break;
        }
        return 0;
    }

    case WM_KEYDOWN:
        if (wParam == VK_ESCAPE) {
            DestroyWindow(hwnd);
            return 0;
        }
        break;

    case WM_CLOSE:
        DestroyWindow(hwnd);
        return 0;

    case WM_DESTROY:
        if (st) {
            delete st->pAppIcon;
            st->pAppIcon = nullptr;
            if (st->hEditFont) DeleteObject(st->hEditFont);
            if (st->hEditBgBrush) DeleteObject(st->hEditBgBrush);
        }
        return 0;
    }
    return DefWindowProcW(hwnd, msg, wParam, lParam);
}

static LRESULT CALLBACK VieLotusSettingsWndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    auto *st = reinterpret_cast<BentoSettingsState *>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));

    switch (msg) {
    case WM_CREATE: {
        CREATESTRUCTW *cs = reinterpret_cast<CREATESTRUCTW *>(lParam);
        st = new BentoSettingsState();
        if (cs && cs->lpCreateParams) {
            const auto *init = reinterpret_cast<const SettingsDialogInitParams *>(cs->lpCreateParams);
            st->onActivateProfiles = init->onActivateProfiles;
        }
        SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(st));

        HDC hdc = GetDC(hwnd);
        int dpiY = GetDeviceCaps(hdc, LOGPIXELSY);
        ReleaseDC(hwnd, hdc);
        st->dpiScale = (dpiY > 0) ? (static_cast<float>(dpiY) / 96.0f) : 1.0f;
        st->isDark = IsWindowsDarkMode();

        // Allow desktop TIP hosts running at lower integrity or compatible UIPI contexts
        // to wake this Settings window via PostMessageW. (AppContainer hosts also use the Named Pipe server.)
        if (HMODULE hUser32 = GetModuleHandleW(L"user32.dll")) {
            using PFN_ChangeWindowMessageFilterEx = BOOL(WINAPI *)(HWND, UINT, DWORD, PCHANGEFILTERSTRUCT);
            FARPROC rawFilter = GetProcAddress(hUser32, "ChangeWindowMessageFilterEx");
            auto pfnFilter = reinterpret_cast<PFN_ChangeWindowMessageFilterEx>(reinterpret_cast<void *>(rawFilter));
            if (pfnFilter) {
                constexpr DWORD kMsgFltAllow = 1; // MSGFLT_ALLOW
                pfnFilter(hwnd, kWmVieLotusShowSettings, kMsgFltAllow, nullptr);
                pfnFilter(hwnd, kWmVieLotusActivateProfiles, kMsgFltAllow, nullptr);
                pfnFilter(hwnd, kWmVieLotusSyncPrefs, kMsgFltAllow, nullptr);
            }
        }

        LoadVieLotusPrefs(st->prefs);
        // Zero-background-process UX: always clean up any legacy HKCU\...\Run\VieLotusIM autostart value.
        SyncStartWithWindowsRegistry(false);

        st->pAppIcon = LoadEmbeddedPngImage(102);
        st->hWndIconBig = LoadEmbeddedAppIcon(32, 32);
        st->hWndIconSmall = LoadEmbeddedAppIcon(16, 16);

        std::wstring dir = GetAppDirPath();
        if (!dir.empty()) {
            std::wstring iconPng = dir + L"assets\\app-icon-128x128.png";
            std::wstring icoFile = dir + L"VieLotusIM.ico";
            if (!st->pAppIcon || st->pAppIcon->GetLastStatus() != Ok) {
                delete st->pAppIcon;
                st->pAppIcon = nullptr;
                if (GetFileAttributesW(iconPng.c_str()) != INVALID_FILE_ATTRIBUTES) {
                    st->pAppIcon = Image::FromFile(iconPng.c_str());
                } else if (GetFileAttributesW(icoFile.c_str()) != INVALID_FILE_ATTRIBUTES) {
                    st->pAppIcon = Image::FromFile(icoFile.c_str());
                }
            }
            if (!st->hWndIconBig) {
                st->hWndIconBig = static_cast<HICON>(LoadImageW(nullptr, icoFile.c_str(), IMAGE_ICON, 32, 32, LR_LOADFROMFILE));
            }
            if (!st->hWndIconSmall) {
                st->hWndIconSmall = static_cast<HICON>(LoadImageW(nullptr, icoFile.c_str(), IMAGE_ICON, 16, 16, LR_LOADFROMFILE));
            }
        }
        if (st->hWndIconBig) SendMessageW(hwnd, WM_SETICON, ICON_BIG, reinterpret_cast<LPARAM>(st->hWndIconBig));
        if (st->hWndIconSmall) SendMessageW(hwnd, WM_SETICON, ICON_SMALL, reinterpret_cast<LPARAM>(st->hWndIconSmall));

        DWORD cornerPref = 2; // DWMWCP_ROUND
        DwmSetWindowAttribute(hwnd, DWMWA_WINDOW_CORNER_PREFERENCE, &cornerPref, sizeof(cornerPref));
        BOOL darkTitle = st->isDark ? TRUE : FALSE;
        DwmSetWindowAttribute(hwnd, 20 /* DWMWA_USE_IMMERSIVE_DARK_MODE */, &darkTitle, sizeof(darkTitle));

        float s = st->dpiScale;
        st->hEditBgBrush = CreateSolidBrush(st->isDark ? RGB(35, 35, 46) : RGB(255, 255, 255));
        st->hEditFont = CreateFontW(
            -static_cast<int>(13.0f * s + 0.5f), 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
            DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
            DEFAULT_PITCH | FF_SWISS, L"Segoe UI"
        );
        st->hTestEdit = CreateWindowExW(
            0, L"EDIT", L"",
            WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL,
            static_cast<int>(110.0f * s),
            static_cast<int>(343.0f * s),
            static_cast<int>(472.0f * s),
            static_cast<int>(20.0f * s),
            hwnd, reinterpret_cast<HMENU>(static_cast<INT_PTR>(1001)), ResolveSettingsInstance(nullptr), nullptr
        );
        if (st->hTestEdit) {
            if (st->hEditFont) {
                SendMessageW(st->hTestEdit, WM_SETFONT, reinterpret_cast<WPARAM>(st->hEditFont), TRUE);
            }
        }
        const auto initSync = SyncSettingsWithSystemInputMethod(
            hwnd,
            st,
            vielotus_tsf_guard::SettingsSyncTrigger::InitialCreate
        );
        UpdateTestEditCueBanner(st);
        RefreshConflictSummaryThrottled(st, true);
        StartSettingsProfileNotifySink(st, hwnd);
        if (vielotus_tsf_guard::ShouldAutoActivateOnSettingsCreate(
                initSync.shouldAutoActivateOnCreate,
                st->prefs.startWithWindows
            ) && st->onActivateProfiles) {
            st->onActivateProfiles(false);
            bool postActVni = st->prefs.isVni;
            st->hasLastObservedTsf = QueryActiveSenVietTsfProfile(postActVni);
            st->lastObservedTsfIsVni = st->hasLastObservedTsf ? postActVni : st->prefs.isVni;
        }
        StartSettingsWakePipeServer(st, hwnd);
        SetTimer(hwnd, kTimerIdSyncPrefs, 300, nullptr);
        if (st->hTestEdit && IsWindowVisible(hwnd)) {
            SetFocus(st->hTestEdit);
        }
        return 0;
    }

    case WM_CTLCOLOREDIT: {
        if (st && st->hEditBgBrush && reinterpret_cast<HWND>(lParam) == st->hTestEdit) {
            HDC hdcEdit = reinterpret_cast<HDC>(wParam);
            SetTextColor(hdcEdit, st->isDark ? RGB(245, 245, 247) : RGB(28, 28, 30));
            SetBkColor(hdcEdit, st->isDark ? RGB(35, 35, 46) : RGB(255, 255, 255));
            return reinterpret_cast<LRESULT>(st->hEditBgBrush);
        }
        break;
    }

    case kWmVieLotusActivateProfiles: {
        if (st) {
            SyncSettingsWithSystemInputMethod(
                hwnd,
                st,
                vielotus_tsf_guard::SettingsSyncTrigger::PeriodicOrWindowEvent,
                false,
                true
            );
            if (IsWindowVisible(hwnd)) {
                RefreshConflictSummaryThrottled(st, false);
            }
            InvalidateRect(hwnd, nullptr, FALSE);
            if (st->onActivateProfiles) st->onActivateProfiles(false);
            if (st->hTestEdit && st->selectedTab == 0 && IsWindowVisible(hwnd)) {
                SetFocus(st->hTestEdit);
            }
        }
        return 0;
    }

    case kWmVieLotusShowSettings: {
        BringSettingsWindowToFront(hwnd);
        if (st) {
            SyncSettingsWithSystemInputMethod(
                hwnd,
                st,
                vielotus_tsf_guard::SettingsSyncTrigger::PeriodicOrWindowEvent,
                false,
                true
            );
            RefreshConflictSummaryThrottled(st, false);
            InvalidateRect(hwnd, nullptr, FALSE);
            if (st->hTestEdit && st->selectedTab == 0) {
                SetFocus(st->hTestEdit);
            }
        }
        return 0;
    }

    case kWmVieLotusSyncPrefs: {
        if (st) {
            const uint32_t hint = static_cast<uint32_t>(wParam);
            if (hint == vielotus_tsf_guard::kSettingsSyncHintTipTelex) {
                SyncSettingsWithSystemInputMethod(
                    hwnd, st, vielotus_tsf_guard::SettingsSyncTrigger::TipCrossProcessHint, false, false
                );
            } else if (hint == vielotus_tsf_guard::kSettingsSyncHintTipVni) {
                SyncSettingsWithSystemInputMethod(
                    hwnd, st, vielotus_tsf_guard::SettingsSyncTrigger::TipCrossProcessHint, true, false
                );
            } else if (hint == vielotus_tsf_guard::kSettingsSyncHintTsfTelex) {
                SyncSettingsWithSystemInputMethod(
                    hwnd, st, vielotus_tsf_guard::SettingsSyncTrigger::TsfProfileNotifySink, false, false
                );
            } else if (hint == vielotus_tsf_guard::kSettingsSyncHintTsfVni) {
                SyncSettingsWithSystemInputMethod(
                    hwnd, st, vielotus_tsf_guard::SettingsSyncTrigger::TsfProfileNotifySink, true, false
                );
            } else {
                SyncSettingsWithSystemInputMethod(
                    hwnd, st, vielotus_tsf_guard::SettingsSyncTrigger::PeriodicOrWindowEvent, false, true
                );
            }
        }
        return 0;
    }

    case WM_TIMER: {
        if (wParam == kTimerIdSyncPrefs && st && IsWindowVisible(hwnd) && !IsIconic(hwnd)) {
            SyncSettingsWithSystemInputMethod(
                hwnd,
                st,
                vielotus_tsf_guard::SettingsSyncTrigger::PeriodicOrWindowEvent,
                false,
                false
            );
            return 0;
        }
        break;
    }

    case kWmVieLotusQuitTray: {
        DestroyWindow(hwnd);
        return 0;
    }

    case WM_ACTIVATE:
    case WM_INPUTLANGCHANGE:
    case WM_SETTINGCHANGE: {
        if (st) {
            bool oldDark = st->isDark;
            std::wstring oldConflicts = st->conflictImeSummary;
            SyncSettingsWithSystemInputMethod(
                hwnd,
                st,
                vielotus_tsf_guard::SettingsSyncTrigger::PeriodicOrWindowEvent,
                false,
                true
            );
            if (msg == WM_ACTIVATE && LOWORD(wParam) != WA_INACTIVE && IsWindowVisible(hwnd)) {
                RefreshConflictSummaryThrottled(st, false);
            }
            st->isDark = IsWindowsDarkMode();
            if (st->isDark != oldDark) {
                if (st->hEditBgBrush) DeleteObject(st->hEditBgBrush);
                st->hEditBgBrush = CreateSolidBrush(st->isDark ? RGB(35, 35, 46) : RGB(255, 255, 255));
                BOOL darkTitle = st->isDark ? TRUE : FALSE;
                DwmSetWindowAttribute(hwnd, 20, &darkTitle, sizeof(darkTitle));
            }
            if (st->isDark != oldDark || st->conflictImeSummary != oldConflicts) {
                InvalidateRect(hwnd, nullptr, FALSE);
            }
        }
        break;
    }

    case WM_ERASEBKGND:
        return 1;

    case WM_PAINT: {
        PAINTSTRUCT ps{};
        HDC hdc = BeginPaint(hwnd, &ps);
        RenderBentoSettingsUI(hwnd, hdc, st);
        EndPaint(hwnd, &ps);
        return 0;
    }

    case WM_MOUSEMOVE: {
        if (!st) break;
        float xDip = static_cast<float>(static_cast<short>(LOWORD(lParam))) / st->dpiScale;
        float yDip = static_cast<float>(static_cast<short>(HIWORD(lParam))) / st->dpiScale;
        HitRegion hit = HitTestBentoUI(st, xDip, yDip);
        if (hit != st->hoveredRegion) {
            st->hoveredRegion = hit;
            InvalidateRect(hwnd, nullptr, FALSE);
        }
        return 0;
    }

    case WM_SETCURSOR: {
        if (st && LOWORD(lParam) == HTCLIENT && st->hoveredRegion != HitRegion::None) {
            SetCursor(LoadCursorW(nullptr, MAKEINTRESOURCEW(32649))); // IDC_HAND
            return TRUE;
        }
        break;
    }

    case WM_LBUTTONDOWN: {
        if (!st) break;
        float xDip = static_cast<float>(static_cast<short>(LOWORD(lParam))) / st->dpiScale;
        float yDip = static_cast<float>(static_cast<short>(HIWORD(lParam))) / st->dpiScale;
        HitRegion hit = HitTestBentoUI(st, xDip, yDip);

        switch (hit) {
        case HitRegion::TabSettings:
            if (st->selectedTab != 0) {
                st->selectedTab = 0;
                if (st->hTestEdit) ShowWindow(st->hTestEdit, SW_SHOW);
                InvalidateRect(hwnd, nullptr, FALSE);
            }
            break;
        case HitRegion::TabAbout:
            if (st->selectedTab != 1) {
                st->selectedTab = 1;
                if (st->hTestEdit) ShowWindow(st->hTestEdit, SW_HIDE);
                InvalidateRect(hwnd, nullptr, FALSE);
            }
            break;
        case HitRegion::BtnCheckUpdate:
            OpenMicrosoftStorePage(hwnd);
            break;
        case HitRegion::BadgeImeConflict: {
            const bool isEn = win_l10n::ResolveWindowsIsEnglish(st->prefs.uiLanguage);
            auto conflicts = vielotus_win_installer::DetectConflictingHookImes();
            if (!conflicts.empty()) {
                std::wstring names = vielotus_win_installer::FormatConflictingImeNames(conflicts);
                std::wstring prompt = isEn
                    ? (L"Another IME (" + names +
                       L") is running in the background and may intercept keys or double characters while using Sen Vi\u1EC7t.\n\n"
                       L"Close " + names + L" now to avoid conflicts?")
                    : (L"Ph\u00E1t hi\u1EC7n b\u1ED9 g\u00F5 kh\u00E1c (" + names +
                       L") \u0111ang ch\u1EA1y n\u1EC1n c\u00F3 th\u1EC3 ch\u1EB7n ph\u00EDm v\u00E0 g\u00E2y l\u1ED7i l\u1EB7p ch\u1EEF khi d\u00F9ng Sen Vi\u1EC7t.\n\n"
                       L"B\u1EA1n c\u00F3 mu\u1ED1n \u0111\u00F3ng " + names + L" \u0111\u1EC3 tr\u00E1nh xung \u0111\u1ED9t kh\u00F4ng?");
                const wchar_t *msgTitle = win_l10n::Tr(
                    isEn,
                    L"Sen Vi\u1EC7t \u2014 Tr\u00E1nh xung \u0111\u1ED9t b\u1ED9 g\u00F5",
                    L"Sen Vi\u1EC7t \u2014 Resolve IME Conflict"
                );
                if (MessageBoxW(hwnd, prompt.c_str(), msgTitle, MB_YESNO | MB_ICONWARNING) == IDYES) {
                    if (!vielotus_win_installer::CloseConflictingHookImes(conflicts)) {
                        std::wstring info = isEn
                            ? (L"Could not close " + names +
                               L" automatically. Please right-click the " + names +
                               L" icon in the System Tray and choose Exit.")
                            : (L"Kh\u00F4ng th\u1EC3 t\u1EF1 \u0111\u1ED9ng \u0111\u00F3ng " + names +
                               L". Vui l\u00F2ng nh\u1EA5p chu\u1ED9t ph\u1EA3i v\u00E0o bi\u1EC3u t\u01B0\u1EE3ng " + names +
                               L" \u1EDF khay h\u1EC7 th\u1ED1ng (System Tray) v\u00E0 ch\u1ECDn Tho\u00E1t.");
                        MessageBoxW(hwnd, info.c_str(), msgTitle, MB_OK | MB_ICONINFORMATION);
                    }
                    if (st->onActivateProfiles) st->onActivateProfiles(true);
                }
            }
            RefreshConflictSummaryThrottled(st, true);
            InvalidateRect(hwnd, nullptr, FALSE);
            if (st->hTestEdit) SetFocus(st->hTestEdit);
            break;
        }
        case HitRegion::CardTelex:
            st->prefs.isVni = false;
            SaveVieLotusPrefs(st->prefs, true);
            if (st->onActivateProfiles) st->onActivateProfiles(true);
            st->lastImRevision = LoadInputMethodRevision();
            st->hasLastObservedTsf = true;
            st->lastObservedTsfIsVni = false;
            UpdateTestEditCueBanner(st);
            InvalidateRect(hwnd, nullptr, FALSE);
            if (st->hTestEdit) SetFocus(st->hTestEdit);
            break;
        case HitRegion::CardVni:
            st->prefs.isVni = true;
            SaveVieLotusPrefs(st->prefs, true);
            if (st->onActivateProfiles) st->onActivateProfiles(true);
            st->lastImRevision = LoadInputMethodRevision();
            st->hasLastObservedTsf = true;
            st->lastObservedTsfIsVni = true;
            UpdateTestEditCueBanner(st);
            InvalidateRect(hwnd, nullptr, FALSE);
            if (st->hTestEdit) SetFocus(st->hTestEdit);
            break;
        case HitRegion::BarSenFlex:
            st->prefs.senFlex = !st->prefs.senFlex;
            SaveVieLotusPrefs(st->prefs, true);
            InvalidateRect(hwnd, nullptr, FALSE);
            break;
        case HitRegion::TileMacroToggle:
            st->prefs.macroEnabled = !st->prefs.macroEnabled;
            SaveVieLotusPrefs(st->prefs, true);
            InvalidateRect(hwnd, nullptr, FALSE);
            break;
        case HitRegion::BtnMacroManage:
            OpenMacroJsonInNotepad(hwnd);
            break;
        case HitRegion::TileDevMode:
            st->prefs.developerMode = !st->prefs.developerMode;
            SaveVieLotusPrefs(st->prefs, true);
            InvalidateRect(hwnd, nullptr, FALSE);
            break;
        case HitRegion::ChipQuickTelex:
            st->prefs.quickTelex = !st->prefs.quickTelex;
            SaveVieLotusPrefs(st->prefs, true);
            InvalidateRect(hwnd, nullptr, FALSE);
            break;
        case HitRegion::ChipRelaxedCoda:
            st->prefs.relaxedCoda = !st->prefs.relaxedCoda;
            SaveVieLotusPrefs(st->prefs, true);
            InvalidateRect(hwnd, nullptr, FALSE);
            break;
        case HitRegion::TileStartWithWindows:
            st->prefs.startWithWindows = !st->prefs.startWithWindows;
            SaveVieLotusPrefs(st->prefs, true);
            if (st->prefs.startWithWindows) {
                SyncStartWithWindowsRegistry(false);
                if (st->onActivateProfiles) st->onActivateProfiles(true);
            } else {
                DisableStartWithWindowsTsfAutostart();
            }
            InvalidateRect(hwnd, nullptr, FALSE);
            break;
        case HitRegion::BtnClearTestEdit:
            if (st->hTestEdit) {
                SetWindowTextW(st->hTestEdit, L"");
                SetFocus(st->hTestEdit);
            }
            break;
        case HitRegion::RowZalo:
            ShellExecuteW(hwnd, L"open", L"https://zalo.me/g/6wwyvywyvhsb0n6rwkze", nullptr, nullptr, SW_SHOWNORMAL);
            break;
        case HitRegion::RowGitHub:
        case HitRegion::FooterGitHub:
            ShellExecuteW(hwnd, L"open", L"https://github.com/stevedat/VieLotus-IM", nullptr, nullptr, SW_SHOWNORMAL);
            break;
        case HitRegion::FooterLanguage: {
            if (HMENU hLangMenu = CreatePopupMenu()) {
                const bool isEn = win_l10n::ResolveWindowsIsEnglish(st->prefs.uiLanguage);
                const uint32_t cur = win_l10n::NormalizeUiLanguagePref(st->prefs.uiLanguage);
                AppendMenuW(
                    hLangMenu,
                    MF_STRING | (cur == 0u ? (MF_CHECKED | MFT_RADIOCHECK) : MF_UNCHECKED),
                    1u,
                    win_l10n::Tr(isEn, L"T\u1EF1 \u0111\u1ED9ng (Theo Windows)", L"Auto (System)")
                );
                AppendMenuW(
                    hLangMenu,
                    MF_STRING | (cur == 1u ? (MF_CHECKED | MFT_RADIOCHECK) : MF_UNCHECKED),
                    2u,
                    L"Ti\u1EBFng Vi\u1EC7t"
                );
                AppendMenuW(
                    hLangMenu,
                    MF_STRING | (cur == 2u ? (MF_CHECKED | MFT_RADIOCHECK) : MF_UNCHECKED),
                    3u,
                    L"English"
                );
                POINT ptScreen{
                    static_cast<LONG>(438.0f * st->dpiScale),
                    static_cast<LONG>(390.0f * st->dpiScale)
                };
                ClientToScreen(hwnd, &ptScreen);
                UINT cmd = static_cast<UINT>(TrackPopupMenuEx(
                    hLangMenu,
                    TPM_NONOTIFY | TPM_RETURNCMD | TPM_CENTERALIGN | TPM_BOTTOMALIGN,
                    ptScreen.x, ptScreen.y, hwnd, nullptr
                ));
                DestroyMenu(hLangMenu);
                if (cmd >= 1u && cmd <= 3u) {
                    st->prefs.uiLanguage = cmd - 1u;
                    SaveVieLotusPrefs(st->prefs, true);
                    UpdateTestEditCueBanner(st);
                    InvalidateRect(hwnd, nullptr, FALSE);
                }
            }
            break;
        }
        case HitRegion::RowFeedback:
        case HitRegion::FooterFeedback:
            ShowVieLotusFeedbackDialog(ResolveSettingsInstance(nullptr), hwnd, st->prefs);
            break;
        default:
            break;
        }
        return 0;
    }

    case WM_KEYDOWN:
        if (wParam == VK_ESCAPE) {
            DestroyWindow(hwnd);
            return 0;
        }
        break;

    case WM_CLOSE:
        DestroyWindow(hwnd);
        return 0;

    case WM_DESTROY:
        KillTimer(hwnd, kTimerIdSyncPrefs);
        if (st) {
            StopSettingsProfileNotifySink(st);
            StopSettingsWakePipeServer(st);
            delete st->pAppIcon;
            if (st->hWndIconBig) DestroyIcon(st->hWndIconBig);
            if (st->hWndIconSmall) DestroyIcon(st->hWndIconSmall);
            if (st->hEditFont) DeleteObject(st->hEditFont);
            if (st->hEditBgBrush) DeleteObject(st->hEditBgBrush);
            delete st;
            SetWindowLongPtrW(hwnd, GWLP_USERDATA, 0);
        }
        PostQuitMessage(0);
        return 0;
    }

    return DefWindowProcW(hwnd, msg, wParam, lParam);
}

} // namespace

void SyncStartWithWindowsRegistry(bool enable) {
    (void)enable;
    HKEY hRun = nullptr;
    if (RegOpenKeyExW(
            HKEY_CURRENT_USER,
            c_szRunSubKey,
            0,
            KEY_SET_VALUE,
            &hRun
        ) != ERROR_SUCCESS || !hRun) {
        return;
    }
    // Zero-background-process UX: always remove any legacy HKCU\...\Run\VieLotusIM startup entry.
    RegDeleteValueW(hRun, c_szRunValueName);
    RegCloseKey(hRun);
}

void BringSettingsWindowToFront(HWND hwnd) {
    if (!hwnd || !IsWindow(hwnd)) return;
    ShowWindow(hwnd, IsIconic(hwnd) ? SW_RESTORE : SW_SHOWNORMAL);
    BringWindowToTop(hwnd);
    SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);
    SetWindowPos(hwnd, HWND_NOTOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);
    SetForegroundWindow(hwnd);
}

bool WakeExistingSettingsWindow() {
    HWND hExisting = FindWindowW(kSettingsWndClassName, nullptr);
    if (!hExisting || !IsWindow(hExisting)) {
        return false;
    }
    DWORD targetPid = 0;
    if (GetWindowThreadProcessId(hExisting, &targetPid) != 0 && targetPid != 0) {
        AllowSetForegroundWindow(targetPid);
    }
    return (PostMessageW(hExisting, kWmVieLotusShowSettings, 0, 0) != FALSE);
}

void ShowVieLotusFeedbackDialog(HINSTANCE hInstance, HWND hwndParent, const VieLotusWindowsPrefs &prefs) {
    if (hInstance) {
        g_settingsInst = hInstance;
    }
    HINSTANCE appInst = ResolveSettingsInstance(hInstance);

    HWND hExisting = FindWindowW(kFeedbackWndClassName, nullptr);
    if (hExisting && IsWindow(hExisting)) {
        BringSettingsWindowToFront(hExisting);
        return;
    }

    WNDCLASSEXW existingWc{};
    existingWc.cbSize = sizeof(existingWc);
    if (!GetClassInfoExW(appInst, kFeedbackWndClassName, &existingWc)) {
        WNDCLASSEXW wc{};
        wc.cbSize = sizeof(wc);
        wc.style = CS_HREDRAW | CS_VREDRAW;
        wc.lpfnWndProc = VieLotusFeedbackWndProc;
        wc.hInstance = appInst;
        wc.hIcon = LoadEmbeddedAppIcon(32, 32);
        wc.hIconSm = LoadEmbeddedAppIcon(16, 16);
        wc.hCursor = LoadCursorW(nullptr, MAKEINTRESOURCEW(32512)); // IDC_ARROW
        wc.hbrBackground = nullptr;
        wc.lpszClassName = kFeedbackWndClassName;
        RegisterClassExW(&wc);
    }

    HDC hdc = GetDC(nullptr);
    int dpiY = GetDeviceCaps(hdc, LOGPIXELSY);
    int screenW = GetSystemMetrics(SM_CXSCREEN);
    int screenH = GetSystemMetrics(SM_CYSCREEN);
    ReleaseDC(nullptr, hdc);

    int clientW = MulDiv(640, dpiY, 96);
    int clientH = MulDiv(468, dpiY, 96);

    DWORD dwStyle = WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_CLIPCHILDREN | WS_VISIBLE;
    DWORD dwExStyle = WS_EX_DLGMODALFRAME | WS_EX_APPWINDOW;
    RECT rcWnd = { 0, 0, clientW, clientH };
    AdjustWindowRectEx(&rcWnd, dwStyle, FALSE, dwExStyle);

    int wndW = rcWnd.right - rcWnd.left;
    int wndH = rcWnd.bottom - rcWnd.top;
    int posX = (screenW > wndW) ? ((screenW - wndW) / 2) : 120;
    int posY = (screenH > wndH) ? ((screenH - wndH) / 2) : 120;

    FeedbackDialogState fbState{};
    fbState.prefs = prefs;

    if (hwndParent && IsWindow(hwndParent)) {
        EnableWindow(hwndParent, FALSE);
    }

    const bool isEn = win_l10n::ResolveWindowsIsEnglish(prefs.uiLanguage);
    HWND hwndFb = CreateWindowExW(
        dwExStyle,
        kFeedbackWndClassName,
        win_l10n::Tr(
            isEn,
            L"G\u00F3p \u00FD & B\u00E1o l\u1ED7i \u2014 Sen Vi\u1EC7t (VieLotusIM)",
            L"Feedback & Bugs \u2014 Sen Vi\u1EC7t (VieLotusIM)"
        ),
        dwStyle,
        posX, posY, wndW, wndH,
        hwndParent, nullptr, appInst, &fbState
    );
    if (hwndFb) {
        BringSettingsWindowToFront(hwndFb);
        UpdateWindow(hwndFb);

        MSG msg{};
        while (IsWindow(hwndFb) && GetMessageW(&msg, nullptr, 0, 0) > 0) {
            if (!IsDialogMessageW(hwndFb, &msg)) {
                TranslateMessage(&msg);
                DispatchMessageW(&msg);
            }
        }
    }

    if (hwndParent && IsWindow(hwndParent)) {
        EnableWindow(hwndParent, TRUE);
        SetForegroundWindow(hwndParent);
    }
}

void ShowVieLotusSettingsDialog(
    HINSTANCE hInstance,
    HWND hwndParent,
    bool startHiddenInTray,
    VieLotusActivateProfilesFn onActivateProfiles
) {
    if (hInstance) {
        g_settingsInst = hInstance;
    }
    if (startHiddenInTray) {
        // Zero-background-process UX: never spawn a hidden tray window.
        SyncStartWithWindowsRegistry(false);
        return;
    }
    HINSTANCE appInst = ResolveSettingsInstance(hInstance);

    HWND hExisting = FindWindowW(kSettingsWndClassName, nullptr);
    if (hExisting && IsWindow(hExisting)) {
        WakeExistingSettingsWindow();
        return;
    }

    GdiplusStartupInput gdiplusStartupInput;
    ULONG_PTR gdiplusToken = 0;
    GdiplusStartup(&gdiplusToken, &gdiplusStartupInput, nullptr);

    HICON hClassIconBig = LoadEmbeddedAppIcon(32, 32);
    HICON hClassIconSm  = LoadEmbeddedAppIcon(16, 16);

    WNDCLASSEXW wc{};
    wc.cbSize = sizeof(wc);
    wc.style = CS_HREDRAW | CS_VREDRAW;
    wc.lpfnWndProc = VieLotusSettingsWndProc;
    wc.hInstance = appInst;
    wc.hIcon = hClassIconBig;
    wc.hIconSm = hClassIconSm;
    wc.hCursor = LoadCursorW(nullptr, MAKEINTRESOURCEW(32512)); // IDC_ARROW
    wc.hbrBackground = nullptr;
    wc.lpszClassName = kSettingsWndClassName;
    RegisterClassExW(&wc);

    HDC hdc = GetDC(nullptr);
    int dpiY = GetDeviceCaps(hdc, LOGPIXELSY);
    int screenW = GetSystemMetrics(SM_CXSCREEN);
    int screenH = GetSystemMetrics(SM_CYSCREEN);
    ReleaseDC(nullptr, hdc);

    int clientW = MulDiv(680, dpiY, 96);
    int clientH = MulDiv(424, dpiY, 96);

    DWORD dwStyle = WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX | WS_CLIPCHILDREN | WS_VISIBLE;
    DWORD dwExStyle = WS_EX_APPWINDOW;
    RECT rcWnd = { 0, 0, clientW, clientH };
    AdjustWindowRectEx(&rcWnd, dwStyle, FALSE, dwExStyle);

    int wndW = rcWnd.right - rcWnd.left;
    int wndH = rcWnd.bottom - rcWnd.top;
    int posX = (screenW > wndW) ? ((screenW - wndW) / 2) : 100;
    int posY = (screenH > wndH) ? ((screenH - wndH) / 2) : 100;

    SettingsDialogInitParams initParams{};
    initParams.onActivateProfiles = onActivateProfiles;

    HWND hwnd = CreateWindowExW(
        dwExStyle,
        kSettingsWndClassName,
        L"Sen Vi\u1EC7t (VieLotusIM)",
        dwStyle,
        posX, posY, wndW, wndH,
        hwndParent, nullptr, appInst, &initParams
    );
    if (hwnd) {
        BringSettingsWindowToFront(hwnd);
        UpdateWindow(hwnd);

        MSG msg{};
        while (GetMessageW(&msg, nullptr, 0, 0) > 0) {
            TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }
    }

    if (hClassIconBig) DestroyIcon(hClassIconBig);
    if (hClassIconSm) DestroyIcon(hClassIconSm);

    if (gdiplusToken) {
        GdiplusShutdown(gdiplusToken);
    }
}
