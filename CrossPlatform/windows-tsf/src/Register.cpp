#include "Register.h"
#include <strsafe.h>
#include <objidl.h>
#include <gdiplus.h>
#include <dwmapi.h>
#include <shellapi.h>
#include <string>

#define CLSID_STRLEN 38
#define VI_LANGID 0x042A // Vietnamese

#ifndef ILOT_UNINSTALL
#define ILOT_UNINSTALL 0x00000001
#endif

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

#ifndef DWMWA_WINDOW_CORNER_PREFERENCE
#define DWMWA_WINDOW_CORNER_PREFERENCE 33
#endif

// Explicit Unicode escapes guarantee zero CP1252 mojibake regardless of compiler source charset flags
static const WCHAR c_szSubKeyPrefix[] = L"CLSID\\";
static const WCHAR c_szInprocServer32[] = L"InprocServer32";
static const WCHAR c_szThreadingModel[] = L"ThreadingModel";
static const WCHAR c_szApartment[] = L"Apartment";
static const WCHAR c_szDesc[] = L"Sen Vi\u1EC7t (VieLotusIM) Text Input Processor";
static const WCHAR c_szProfileDesc[] = L"Ti\u1EBFng Vi\u1EC7t (Sen Vi\u1EC7t - Telex)";
static const WCHAR c_szProfileVniDesc[] = L"Ti\u1EBFng Vi\u1EC7t (Sen Vi\u1EC7t - VNI)";
static const WCHAR c_szPrefsSubKey[] = L"Software\\VieLotusIM";
static const WCHAR c_szPrefsInputMethodVal[] = L"InputMethod";
static const WCHAR c_szPrefsVnEnabledVal[] = L"VietnameseEnabled";
static const WCHAR c_szPrefsSmartBilingualVal[] = L"SmartBilingual";
static const WCHAR c_szPrefsModernOrthoVal[] = L"ModernOrthography";
static const WCHAR c_szPrefsMacroEnabledVal[] = L"MacroEnabled";
static const WCHAR c_szPrefsDeveloperModeVal[] = L"DeveloperMode";
static const WCHAR c_szPrefsQuickTelexVal[] = L"QuickTelex";
static const WCHAR c_szPrefsRelaxedCodaVal[] = L"RelaxedCoda";

// LayoutOrTip strings for input.dll!InstallLayoutOrTip
static const WCHAR c_szTipTelexLayoutString[] =
    L"042A:{C7B08E9D-4762-4C97-8B1F-522197A598DC}{8E2A7B44-5A1F-4B82-9B7C-123456789ABC}";
static const WCHAR c_szTipVniLayoutString[] =
    L"042A:{C7B08E9D-4762-4C97-8B1F-522197A598DC}{8E2A7B45-5A1F-4B82-9B7C-123456789ABC}";

// Windows 8/10/11 mandatory TSF capability categories for UWP, WinUI 3, Edge, Notepad, Search, and System Tray
static const GUID kCategoriesToRegister[] = {
    // GUID_TFCAT_TIP_KEYBOARD: {34745C63-B2F0-4784-8B67-5E12C8701A31}
    { 0x34745c63, 0xb2f0, 0x4784, { 0x8b, 0x67, 0x5e, 0x12, 0xc8, 0x70, 0x1a, 0x31 } },
    // GUID_TFCAT_TIPCAP_IMMERSIVESUPPORT: {13A016DF-560B-46CD-947A-4C3AF1E0E35D}
    { 0x13a016df, 0x560b, 0x46cd, { 0x94, 0x7a, 0x4c, 0x3a, 0xf1, 0xe0, 0xe3, 0x5d } },
    // GUID_TFCAT_TIPCAP_SYSTRAYSUPPORT: {25504FB4-7BAB-4BC1-9C69-CF81890F0EF5}
    { 0x25504fb4, 0x7bab, 0x4bc1, { 0x9c, 0x69, 0xcf, 0x81, 0x89, 0x0f, 0x0e, 0xf5 } },
    // GUID_TFCAT_TIPCAP_UIELEMENTENABLED: {49D2F9CE-1F5E-11D7-A6D3-00065B84435C}
    { 0x49d2f9ce, 0x1f5e, 0x11d7, { 0xa6, 0xd3, 0x00, 0x06, 0x5b, 0x84, 0x43, 0x5c } },
    // GUID_TFCAT_TIPCAP_SECUREMODE: {49D2F9CF-1F5E-11D7-A6D3-00065B84435C}
    { 0x49d2f9cf, 0x1f5e, 0x11d7, { 0xa6, 0xd3, 0x00, 0x06, 0x5b, 0x84, 0x43, 0x5c } },
    // GUID_TFCAT_TIPCAP_COMLESS: {364215D9-75BC-11D7-A6EF-00065B84435C}
    { 0x364215d9, 0x75bc, 0x11d7, { 0xa6, 0xef, 0x00, 0x06, 0x5b, 0x84, 0x43, 0x5c } },
    // GUID_TFCAT_DISPLAYATTRIBUTEPROVIDER: {046B8C80-1647-40F7-9B21-B93B81AABC1B}
    { 0x046b8c80, 0x1647, 0x40f7, { 0x9b, 0x21, 0xb9, 0x3b, 0x81, 0xaa, 0xbc, 0x1b } }
};

static BOOL CLSIDToString(REFGUID refGUID, WCHAR *pszString) {
    return StringFromGUID2(refGUID, pszString, CLSID_STRLEN + 1) != 0;
}

static bool ReadRegDword(HKEY hKey, LPCWSTR valName, DWORD &outVal) {
    DWORD cbData = sizeof(outVal);
    DWORD dwType = 0;
    LSTATUS st = RegQueryValueExW(hKey, valName, nullptr, &dwType, reinterpret_cast<LPBYTE>(&outVal), &cbData);
    return (st == ERROR_SUCCESS && dwType == REG_DWORD);
}

static void WriteRegDword(HKEY hKey, LPCWSTR valName, DWORD val) {
    RegSetValueExW(hKey, valName, 0, REG_DWORD, reinterpret_cast<const BYTE *>(&val), sizeof(val));
}

bool LoadPersistedVniPreference(bool &outIsVni) {
    HKEY hKey = nullptr;
    if (RegOpenKeyExW(HKEY_CURRENT_USER, c_szPrefsSubKey, 0, KEY_READ, &hKey) != ERROR_SUCCESS) {
        return false;
    }
    DWORD dwVal = 0;
    bool ok = ReadRegDword(hKey, c_szPrefsInputMethodVal, dwVal);
    RegCloseKey(hKey);
    if (ok) {
        outIsVni = (dwVal == 1);
    }
    return ok;
}

void SavePersistedVniPreference(bool isVni) {
    HKEY hKey = nullptr;
    if (RegCreateKeyExW(HKEY_CURRENT_USER, c_szPrefsSubKey, 0, nullptr, REG_OPTION_NON_VOLATILE, KEY_WRITE, nullptr, &hKey, nullptr) == ERROR_SUCCESS) {
        WriteRegDword(hKey, c_szPrefsInputMethodVal, isVni ? 1u : 0u);
        RegCloseKey(hKey);
    }
}

void LoadVieLotusPrefs(VieLotusWindowsPrefs &outPrefs) {
    outPrefs = VieLotusWindowsPrefs{};
    HKEY hKey = nullptr;
    if (RegOpenKeyExW(HKEY_CURRENT_USER, c_szPrefsSubKey, 0, KEY_READ, &hKey) != ERROR_SUCCESS) {
        return;
    }
    DWORD dwVal = 0;
    if (ReadRegDword(hKey, c_szPrefsInputMethodVal, dwVal)) {
        outPrefs.isVni = (dwVal == 1);
    }
    if (ReadRegDword(hKey, c_szPrefsVnEnabledVal, dwVal)) {
        outPrefs.vietnameseEnabled = (dwVal != 0);
    }
    if (ReadRegDword(hKey, c_szPrefsSmartBilingualVal, dwVal)) {
        outPrefs.smartBilingual = (dwVal != 0);
    }
    if (ReadRegDword(hKey, c_szPrefsModernOrthoVal, dwVal)) {
        outPrefs.modernOrthography = (dwVal != 0);
    }
    if (ReadRegDword(hKey, c_szPrefsMacroEnabledVal, dwVal)) {
        outPrefs.macroEnabled = (dwVal != 0);
    }
    if (ReadRegDword(hKey, c_szPrefsDeveloperModeVal, dwVal)) {
        outPrefs.developerMode = (dwVal != 0);
    }
    if (ReadRegDword(hKey, c_szPrefsQuickTelexVal, dwVal)) {
        outPrefs.quickTelex = (dwVal != 0);
    }
    if (ReadRegDword(hKey, c_szPrefsRelaxedCodaVal, dwVal)) {
        outPrefs.relaxedCoda = (dwVal != 0);
    }
    RegCloseKey(hKey);
}

void SaveVieLotusPrefs(const VieLotusWindowsPrefs &prefs) {
    HKEY hKey = nullptr;
    if (RegCreateKeyExW(HKEY_CURRENT_USER, c_szPrefsSubKey, 0, nullptr, REG_OPTION_NON_VOLATILE, KEY_WRITE, nullptr, &hKey, nullptr) == ERROR_SUCCESS) {
        WriteRegDword(hKey, c_szPrefsInputMethodVal, prefs.isVni ? 1u : 0u);
        WriteRegDword(hKey, c_szPrefsVnEnabledVal, prefs.vietnameseEnabled ? 1u : 0u);
        WriteRegDword(hKey, c_szPrefsSmartBilingualVal, prefs.smartBilingual ? 1u : 0u);
        WriteRegDword(hKey, c_szPrefsModernOrthoVal, prefs.modernOrthography ? 1u : 0u);
        WriteRegDword(hKey, c_szPrefsMacroEnabledVal, prefs.macroEnabled ? 1u : 0u);
        WriteRegDword(hKey, c_szPrefsDeveloperModeVal, prefs.developerMode ? 1u : 0u);
        WriteRegDword(hKey, c_szPrefsQuickTelexVal, prefs.quickTelex ? 1u : 0u);
        WriteRegDword(hKey, c_szPrefsRelaxedCodaVal, prefs.relaxedCoda ? 1u : 0u);
        RegCloseKey(hKey);
    }
}

HRESULT RegisterServer() {
    WCHAR szCLSID[CLSID_STRLEN + 1];
    if (!CLSIDToString(CLSID_VieLotusTIP, szCLSID)) {
        return E_FAIL;
    }

    WCHAR szKey[MAX_PATH];
    StringCchPrintfW(szKey, MAX_PATH, L"%s%s", c_szSubKeyPrefix, szCLSID);

    HKEY hKey = nullptr;
    if (RegCreateKeyExW(HKEY_CLASSES_ROOT, szKey, 0, nullptr, REG_OPTION_NON_VOLATILE, KEY_WRITE, nullptr, &hKey, nullptr) != ERROR_SUCCESS) {
        return E_FAIL;
    }
    RegSetValueExW(hKey, nullptr, 0, REG_SZ, (const BYTE *)c_szDesc, (DWORD)(wcslen(c_szDesc) + 1) * sizeof(WCHAR));

    HKEY hInprocKey = nullptr;
    if (RegCreateKeyExW(hKey, c_szInprocServer32, 0, nullptr, REG_OPTION_NON_VOLATILE, KEY_WRITE, nullptr, &hInprocKey, nullptr) == ERROR_SUCCESS) {
        WCHAR szFilePath[MAX_PATH];
        GetModuleFileNameW(g_hInst, szFilePath, MAX_PATH);
        RegSetValueExW(hInprocKey, nullptr, 0, REG_SZ, (const BYTE *)szFilePath, (DWORD)(wcslen(szFilePath) + 1) * sizeof(WCHAR));
        RegSetValueExW(hInprocKey, c_szThreadingModel, 0, REG_SZ, (const BYTE *)c_szApartment, (DWORD)(wcslen(c_szApartment) + 1) * sizeof(WCHAR));
        RegCloseKey(hInprocKey);
    }
    RegCloseKey(hKey);

    HRESULT hrCo = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    RegisterCategories();
    RegisterProfiles();
    ActivateUserProfiles();
    if (SUCCEEDED(hrCo)) {
        CoUninitialize();
    }

    return S_OK;
}

HRESULT UnregisterServer() {
    WCHAR szCLSID[CLSID_STRLEN + 1];
    if (!CLSIDToString(CLSID_VieLotusTIP, szCLSID)) {
        return E_FAIL;
    }

    HRESULT hrCo = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    DeactivateUserProfiles();
    UnregisterCategories();
    UnregisterProfiles();
    if (SUCCEEDED(hrCo)) {
        CoUninitialize();
    }

    WCHAR szKey[MAX_PATH];
    StringCchPrintfW(szKey, MAX_PATH, L"%s%s\\%s", c_szSubKeyPrefix, szCLSID, c_szInprocServer32);
    RegDeleteKeyW(HKEY_CLASSES_ROOT, szKey);

    StringCchPrintfW(szKey, MAX_PATH, L"%s%s", c_szSubKeyPrefix, szCLSID);
    RegDeleteKeyW(HKEY_CLASSES_ROOT, szKey);

    return S_OK;
}

HRESULT RegisterProfiles() {
    WCHAR szFilePath[MAX_PATH] = {0};
    GetModuleFileNameW(g_hInst, szFilePath, MAX_PATH);
    ULONG cchFile = (ULONG)wcslen(szFilePath);

    ITfInputProcessorProfiles *pProfiles = nullptr;
    HRESULT hr = CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr, CLSCTX_INPROC_SERVER, IID_ITfInputProcessorProfiles, (void **)&pProfiles);
    if (SUCCEEDED(hr) && pProfiles) {
        hr = pProfiles->Register(CLSID_VieLotusTIP);
        if (SUCCEEDED(hr)) {
            pProfiles->AddLanguageProfile(
                CLSID_VieLotusTIP,
                VI_LANGID,
                GUID_VieLotusProfile,
                c_szProfileDesc,
                (ULONG)wcslen(c_szProfileDesc),
                szFilePath,
                cchFile,
                0
            );
            pProfiles->AddLanguageProfile(
                CLSID_VieLotusTIP,
                VI_LANGID,
                GUID_VieLotusProfileVNI,
                c_szProfileVniDesc,
                (ULONG)wcslen(c_szProfileVniDesc),
                szFilePath,
                cchFile,
                0
            );
            pProfiles->EnableLanguageProfile(CLSID_VieLotusTIP, VI_LANGID, GUID_VieLotusProfile, TRUE);
            pProfiles->EnableLanguageProfile(CLSID_VieLotusTIP, VI_LANGID, GUID_VieLotusProfileVNI, TRUE);
            pProfiles->EnableLanguageProfileByDefault(CLSID_VieLotusTIP, VI_LANGID, GUID_VieLotusProfile, TRUE);
            pProfiles->EnableLanguageProfileByDefault(CLSID_VieLotusTIP, VI_LANGID, GUID_VieLotusProfileVNI, TRUE);
        }

        ITfInputProcessorProfileMgr *pProfileMgr = nullptr;
        if (SUCCEEDED(pProfiles->QueryInterface(IID_ITfInputProcessorProfileMgr, reinterpret_cast<void **>(&pProfileMgr))) && pProfileMgr) {
            pProfileMgr->RegisterProfile(
                CLSID_VieLotusTIP,
                VI_LANGID,
                GUID_VieLotusProfile,
                c_szProfileDesc,
                (ULONG)wcslen(c_szProfileDesc),
                szFilePath,
                cchFile,
                0,
                nullptr,
                0,
                TRUE,
                0
            );
            pProfileMgr->RegisterProfile(
                CLSID_VieLotusTIP,
                VI_LANGID,
                GUID_VieLotusProfileVNI,
                c_szProfileVniDesc,
                (ULONG)wcslen(c_szProfileVniDesc),
                szFilePath,
                cchFile,
                0,
                nullptr,
                0,
                TRUE,
                0
            );
            pProfileMgr->Release();
        }

        pProfiles->Release();
    }
    return hr;
}

HRESULT ActivateUserProfiles() {
    HMODULE hInputDll = LoadLibraryExW(L"input.dll", nullptr, LOAD_LIBRARY_SEARCH_SYSTEM32);
    if (hInputDll) {
        using PFN_InstallLayoutOrTip = BOOL(WINAPI *)(LPCWSTR psz, DWORD dwFlags);
        auto pfnInstallLayoutOrTip = reinterpret_cast<PFN_InstallLayoutOrTip>(GetProcAddress(hInputDll, "InstallLayoutOrTip"));
        if (pfnInstallLayoutOrTip) {
            pfnInstallLayoutOrTip(c_szTipTelexLayoutString, 0);
            pfnInstallLayoutOrTip(c_szTipVniLayoutString, 0);
        }
        FreeLibrary(hInputDll);
    }

    bool preferVni = false;
    LoadPersistedVniPreference(preferVni);
    const GUID &preferredGuid = preferVni ? GUID_VieLotusProfileVNI : GUID_VieLotusProfile;

    ITfInputProcessorProfiles *pProfiles = nullptr;
    HRESULT hr = CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr, CLSCTX_INPROC_SERVER, IID_ITfInputProcessorProfiles, (void **)&pProfiles);
    if (SUCCEEDED(hr) && pProfiles) {
        pProfiles->EnableLanguageProfile(CLSID_VieLotusTIP, VI_LANGID, GUID_VieLotusProfile, TRUE);
        pProfiles->EnableLanguageProfile(CLSID_VieLotusTIP, VI_LANGID, GUID_VieLotusProfileVNI, TRUE);
        pProfiles->SetDefaultLanguageProfile(VI_LANGID, CLSID_VieLotusTIP, preferredGuid);
        pProfiles->ActivateLanguageProfile(CLSID_VieLotusTIP, VI_LANGID, preferredGuid);

        ITfInputProcessorProfileMgr *pProfileMgr = nullptr;
        if (SUCCEEDED(pProfiles->QueryInterface(IID_ITfInputProcessorProfileMgr, reinterpret_cast<void **>(&pProfileMgr))) && pProfileMgr) {
            pProfileMgr->ActivateProfile(
                TF_PROFILETYPE_INPUTPROCESSOR,
                VI_LANGID,
                CLSID_VieLotusTIP,
                preferredGuid,
                nullptr,
                TF_IPPMF_FORPROCESS | TF_IPPMF_FORSESSION | TF_IPPMF_ENABLEPROFILE
            );
            pProfileMgr->Release();
        }
        pProfiles->Release();
    }
    return hr;
}

HRESULT DeactivateUserProfiles() {
    HMODULE hInputDll = LoadLibraryExW(L"input.dll", nullptr, LOAD_LIBRARY_SEARCH_SYSTEM32);
    if (hInputDll) {
        using PFN_InstallLayoutOrTip = BOOL(WINAPI *)(LPCWSTR psz, DWORD dwFlags);
        auto pfnInstallLayoutOrTip = reinterpret_cast<PFN_InstallLayoutOrTip>(GetProcAddress(hInputDll, "InstallLayoutOrTip"));
        if (pfnInstallLayoutOrTip) {
            pfnInstallLayoutOrTip(c_szTipTelexLayoutString, ILOT_UNINSTALL);
            pfnInstallLayoutOrTip(c_szTipVniLayoutString, ILOT_UNINSTALL);
        }
        FreeLibrary(hInputDll);
    }
    return S_OK;
}

HRESULT UnregisterProfiles() {
    ITfInputProcessorProfiles *pProfiles = nullptr;
    HRESULT hr = CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr, CLSCTX_INPROC_SERVER, IID_ITfInputProcessorProfiles, (void **)&pProfiles);
    if (SUCCEEDED(hr) && pProfiles) {
        ITfInputProcessorProfileMgr *pProfileMgr = nullptr;
        if (SUCCEEDED(pProfiles->QueryInterface(IID_ITfInputProcessorProfileMgr, reinterpret_cast<void **>(&pProfileMgr))) && pProfileMgr) {
            pProfileMgr->UnregisterProfile(CLSID_VieLotusTIP, VI_LANGID, GUID_VieLotusProfile, 0);
            pProfileMgr->UnregisterProfile(CLSID_VieLotusTIP, VI_LANGID, GUID_VieLotusProfileVNI, 0);
            pProfileMgr->Release();
        }
        pProfiles->Unregister(CLSID_VieLotusTIP);
        pProfiles->Release();
    }
    return hr;
}

HRESULT RegisterCategories() {
    ITfCategoryMgr *pCategoryMgr = nullptr;
    HRESULT hr = CoCreateInstance(CLSID_TF_CategoryMgr, nullptr, CLSCTX_INPROC_SERVER, IID_ITfCategoryMgr, (void **)&pCategoryMgr);
    if (SUCCEEDED(hr) && pCategoryMgr) {
        for (const auto &cat : kCategoriesToRegister) {
            pCategoryMgr->RegisterCategory(CLSID_VieLotusTIP, cat, CLSID_VieLotusTIP);
        }
        pCategoryMgr->Release();
    }
    return hr;
}

HRESULT UnregisterCategories() {
    ITfCategoryMgr *pCategoryMgr = nullptr;
    HRESULT hr = CoCreateInstance(CLSID_TF_CategoryMgr, nullptr, CLSCTX_INPROC_SERVER, IID_ITfCategoryMgr, (void **)&pCategoryMgr);
    if (SUCCEEDED(hr) && pCategoryMgr) {
        for (const auto &cat : kCategoriesToRegister) {
            pCategoryMgr->UnregisterCategory(CLSID_VieLotusTIP, cat, CLSID_VieLotusTIP);
        }
        pCategoryMgr->Release();
    }
    return hr;
}

// =============================================================================
// macOS-Parity Bento Inspector UI ("Cài đặt Sen Việt") powered by GDI+ & DWM
// Matches Sources/VieLotusIM/SettingsView.swift (2 Tabs: Cài đặt | Về ứng dụng)
// =============================================================================

namespace {

using namespace Gdiplus;

enum class HitRegion : int {
    None = 0,
    TabSettings,
    TabAbout,
    CardTelex,
    CardVni,
    TileMacroToggle,
    BtnMacroManage,
    TileDevMode,
    ChipQuickTelex,
    ChipRelaxedCoda,
    TileWinTypingSettings,
    BtnCopyBankStk,
    BtnNidoOfficeExplore,
    BtnYouPersonaExplore,
    RowZalo,
    RowLinkedIn,
    RowGitHub,
    FooterNidoOffice,
    FooterYouPersona,
    FooterZalo,
    FooterGitHub
};

struct BentoSettingsState {
    VieLotusWindowsPrefs prefs{};
    int selectedTab{0}; // 0 = Cài đặt, 1 = Về ứng dụng
    HitRegion hoveredRegion{HitRegion::None};
    bool copiedStk{false};
    float dpiScale{1.0f};
    Image *pAppIcon{nullptr};
    Image *pVietQr{nullptr};
    HICON hWndIconBig{nullptr};
    HICON hWndIconSmall{nullptr};
};

static std::wstring GetDllDirPath() {
    WCHAR path[MAX_PATH] = {0};
    if (GetModuleFileNameW(g_hInst, path, MAX_PATH) == 0) return L"";
    std::wstring s(path);
    size_t pos = s.find_last_of(L"\\/");
    return (pos != std::wstring::npos) ? s.substr(0, pos + 1) : L"";
}

static void CopyTextToClipboard(HWND hwnd, const WCHAR *text) {
    if (!text || !OpenClipboard(hwnd)) return;
    EmptyClipboard();
    size_t bytes = (wcslen(text) + 1) * sizeof(WCHAR);
    HGLOBAL hMem = GlobalAlloc(GMEM_MOVEABLE, bytes);
    if (hMem) {
        void *pMem = GlobalLock(hMem);
        if (pMem) {
            memcpy(pMem, text, bytes);
            GlobalUnlock(hMem);
            SetClipboardData(CF_UNICODETEXT, hMem);
        }
    }
    CloseClipboard();
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
    // Subtle 1px drop shadow
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

    // Header Segmented Tabs
    if (PtInDipRect(xDip, yDip, 286.0f, 16.0f, 96.0f, 32.0f)) return HitRegion::TabSettings;
    if (PtInDipRect(xDip, yDip, 384.0f, 16.0f, 96.0f, 32.0f)) return HitRegion::TabAbout;

    // Footer Links
    if (PtInDipRect(xDip, yDip, 268.0f, 452.0f, 62.0f, 24.0f)) return HitRegion::FooterNidoOffice;
    if (PtInDipRect(xDip, yDip, 336.0f, 452.0f, 82.0f, 24.0f)) return HitRegion::FooterYouPersona;
    if (PtInDipRect(xDip, yDip, 424.0f, 452.0f, 28.0f, 24.0f)) return HitRegion::FooterZalo;
    if (PtInDipRect(xDip, yDip, 456.0f, 452.0f, 36.0f, 24.0f)) return HitRegion::FooterGitHub;

    if (st->selectedTab == 0) {
        // Tab 0: Cài đặt (macOS Bento 2x2 Parity)
        if (PtInDipRect(xDip, yDip, 18.0f, 98.0f, 226.0f, 76.0f)) return HitRegion::CardTelex;
        if (PtInDipRect(xDip, yDip, 256.0f, 98.0f, 226.0f, 76.0f)) return HitRegion::CardVni;

        // Tile 1: Bảng gõ tắt (Toggle + Quản lý button)
        if (PtInDipRect(xDip, yDip, 160.0f, 220.0f, 76.0f, 24.0f)) return HitRegion::BtnMacroManage;
        if (PtInDipRect(xDip, yDip, 18.0f, 210.0f, 226.0f, 82.0f)) return HitRegion::TileMacroToggle;

        // Tile 2: Chế độ Code & Dev
        if (PtInDipRect(xDip, yDip, 256.0f, 210.0f, 226.0f, 82.0f)) return HitRegion::TileDevMode;

        // Tile 3: Tốc gõ phụ âm (2 chips: Đầu cc/gg/qq & Cuối -g/-h/-k)
        if (PtInDipRect(xDip, yDip, 28.0f, 348.0f, 100.0f, 26.0f)) return HitRegion::ChipQuickTelex;
        if (PtInDipRect(xDip, yDip, 134.0f, 348.0f, 100.0f, 26.0f)) return HitRegion::ChipRelaxedCoda;
        if (PtInDipRect(xDip, yDip, 18.0f, 302.0f, 113.0f, 82.0f)) return HitRegion::ChipQuickTelex;
        if (PtInDipRect(xDip, yDip, 131.0f, 302.0f, 113.0f, 82.0f)) return HitRegion::ChipRelaxedCoda;

        // Tile 4: Phím tắt Đổi bộ gõ
        if (PtInDipRect(xDip, yDip, 256.0f, 302.0f, 226.0f, 82.0f)) return HitRegion::TileWinTypingSettings;
    } else {
        // Tab 1: Về ứng dụng (Matches macOS aboutTabView + NidoOffice & YouPersona.com)
        if (PtInDipRect(xDip, yDip, 372.0f, 192.0f, 96.0f, 22.0f)) return HitRegion::BtnCopyBankStk;
        if (PtInDipRect(xDip, yDip, 18.0f, 246.0f, 464.0f, 52.0f)) return HitRegion::BtnNidoOfficeExplore;
        if (PtInDipRect(xDip, yDip, 18.0f, 299.0f, 464.0f, 52.0f)) return HitRegion::BtnYouPersonaExplore;
        if (PtInDipRect(xDip, yDip, 18.0f, 360.0f, 464.0f, 26.0f)) return HitRegion::RowZalo;
        if (PtInDipRect(xDip, yDip, 18.0f, 386.0f, 464.0f, 26.0f)) return HitRegion::RowLinkedIn;
        if (PtInDipRect(xDip, yDip, 18.0f, 412.0f, 464.0f, 26.0f)) return HitRegion::RowGitHub;
    }

    return HitRegion::None;
}

static void DrawHeroInputCard(
    Graphics &g,
    float s,
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
    Color accent(255, 0, 122, 255); // Apple Blue #007AFF
    Color fill = isSelected
        ? Color(255, 236, 245, 255)
        : (isHovered ? Color(255, 250, 250, 253) : Color(255, 255, 255, 255));
    Color border = isSelected
        ? accent
        : (isHovered ? Color(255, 195, 200, 210) : Color(255, 226, 226, 232));
    float borderW = isSelected ? (1.8f * s) : (1.0f * s);

    DrawCard(g, RectF(x * s, y * s, w * s, h * s), 12.0f * s, fill, border, borderW);

    // Icon badge square (top-left)
    RectF iconBox((x + 12.0f) * s, (y + 11.0f) * s, 24.0f * s, 24.0f * s);
    FillRoundRect(g, iconBox, 6.0f * s, isSelected ? Color(255, 0, 122, 255) : Color(255, 236, 236, 241));
    SolidBrush iconTextBrush(isSelected ? Color(255, 255, 255, 255) : Color(255, 100, 100, 108));
    g.DrawString(iconText, -1, &fBadge, iconBox, &sfCenter, &iconTextBrush);

    // Title
    SolidBrush primaryBrush(Color(255, 28, 28, 30));
    RectF titleRect((x + 42.0f) * s, (y + 12.0f) * s, (w - 76.0f) * s, 22.0f * s);
    g.DrawString(title, -1, &fTitle, titleRect, &sfLeft, &primaryBrush);

    // Checkmark circle on top-right
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
        Pen circlePen(Color(255, 195, 195, 204), 1.4f * s);
        g.DrawEllipse(&circlePen, chkRect);
    }

    // Bottom Row: Monospace Pill Badge + Subtitle
    float badgeW = 74.0f;
    RectF badgeRect((x + 12.0f) * s, (y + 44.0f) * s, badgeW * s, 20.0f * s);
    FillRoundRect(g, badgeRect, 5.0f * s, isSelected ? Color(42, 0, 122, 255) : Color(255, 240, 240, 245));
    SolidBrush badgeBrush(isSelected ? accent : Color(255, 95, 95, 102));
    g.DrawString(badge, -1, &fBadge, badgeRect, &sfCenter, &badgeBrush);

    SolidBrush secBrush(Color(255, 110, 110, 115));
    RectF subRect((x + 92.0f) * s, (y + 45.0f) * s, (w - 100.0f) * s, 20.0f * s);
    g.DrawString(subtitle, -1, &fSub, subRect, &sfLeft, &secBrush);
}

static void DrawBentoFeatureTile(
    Graphics &g,
    float s,
    float x, float y, float w, float h,
    bool isActive,
    bool isHovered,
    const Color &accent,
    const WCHAR *iconGlyph,
    const WCHAR *title,
    const WCHAR *subtitle,
    const WCHAR *pillText,
    Font &fTitle,
    Font &fSub,
    Font &fPill,
    StringFormat &sfLeft,
    StringFormat &sfCenter
) {
    Color fill = isHovered ? Color(255, 250, 250, 253) : Color(255, 255, 255, 255);
    Color border = isActive
        ? Color(130, accent.GetR(), accent.GetG(), accent.GetB())
        : Color(255, 226, 226, 232);
    DrawCard(g, RectF(x * s, y * s, w * s, h * s), 12.0f * s, fill, border, 1.1f * s);

    // Icon box (26x26)
    RectF iconBox((x + 11.0f) * s, (y + 11.0f) * s, 26.0f * s, 26.0f * s);
    Color iconBg = isActive
        ? Color(38, accent.GetR(), accent.GetG(), accent.GetB())
        : Color(255, 238, 238, 243);
    FillRoundRect(g, iconBox, 7.0f * s, iconBg);
    SolidBrush iconBrush(isActive ? accent : Color(255, 120, 120, 128));
    g.DrawString(iconGlyph, -1, &fPill, iconBox, &sfCenter, &iconBrush);

    // Title
    SolidBrush primaryBrush(Color(255, 28, 28, 30));
    RectF titleRect((x + 43.0f) * s, (y + 14.0f) * s, (w - 112.0f) * s, 20.0f * s);
    g.DrawString(title, -1, &fTitle, titleRect, &sfLeft, &primaryBrush);

    // Trailing status pill
    float pillW = 60.0f;
    RectF pillRect((x + w - pillW - 10.0f) * s, (y + 14.0f) * s, pillW * s, 19.0f * s);
    Color pillBg = isActive
        ? Color(38, accent.GetR(), accent.GetG(), accent.GetB())
        : Color(255, 238, 238, 243);
    FillRoundRect(g, pillRect, 9.5f * s, pillBg);
    SolidBrush pillTextBrush(isActive ? accent : Color(255, 120, 120, 128));
    g.DrawString(pillText, -1, &fPill, pillRect, &sfCenter, &pillTextBrush);

    // Subtitle
    SolidBrush secBrush(Color(255, 110, 110, 115));
    RectF subRect((x + 11.0f) * s, (y + 48.0f) * s, (w - 22.0f) * s, 22.0f * s);
    g.DrawString(subtitle, -1, &fSub, subRect, &sfLeft, &secBrush);
}

static void RenderBentoSettingsUI(HWND hwnd, HDC hdc, BentoSettingsState *st) {
    if (!st) return;

    RECT rcClient{};
    GetClientRect(hwnd, &rcClient);
    int width = rcClient.right - rcClient.left;
    int height = rcClient.bottom - rcClient.top;
    if (width <= 0 || height <= 0) return;

    // Double-buffered offscreen bitmap
    HDC memDC = CreateCompatibleDC(hdc);
    HBITMAP memBmp = CreateCompatibleBitmap(hdc, width, height);
    HBITMAP oldBmp = static_cast<HBITMAP>(SelectObject(memDC, memBmp));

    {
        Graphics g(memDC);
        g.SetSmoothingMode(SmoothingModeAntiAlias);
        g.SetPixelOffsetMode(PixelOffsetModeHighQuality);
        g.SetTextRenderingHint(TextRenderingHintClearTypeGridFit);

        float s = st->dpiScale;

        FontFamily ffSans(L"Segoe UI");
        FontFamily ffMono(L"Consolas");

        Font fBrand(&ffSans, 13.5f * s, FontStyleBold, UnitPixel);
        Font fVersion(&ffSans, 9.5f * s, FontStyleBold, UnitPixel);
        Font fHeaderSub(&ffSans, 10.5f * s, FontStyleRegular, UnitPixel);
        Font fTab(&ffSans, 11.5f * s, FontStyleBold, UnitPixel);
        Font fSecHdr(&ffSans, 10.0f * s, FontStyleBold, UnitPixel);
        Font fSecRight(&ffSans, 10.5f * s, FontStyleBold, UnitPixel);
        Font fCardTitle(&ffSans, 12.5f * s, FontStyleBold, UnitPixel);
        Font fTileTitle(&ffSans, 11.5f * s, FontStyleBold, UnitPixel);
        Font fBody(&ffSans, 11.5f * s, FontStyleRegular, UnitPixel);
        Font fBodyBold(&ffSans, 11.5f * s, FontStyleBold, UnitPixel);
        Font fSub(&ffSans, 10.5f * s, FontStyleRegular, UnitPixel);
        Font fPill(&ffSans, 9.5f * s, FontStyleBold, UnitPixel);
        Font fMonoBadge(&ffMono, 10.0f * s, FontStyleBold, UnitPixel);
        Font fFooter(&ffSans, 10.0f * s, FontStyleRegular, UnitPixel);
        Font fFooterBold(&ffSans, 10.0f * s, FontStyleBold, UnitPixel);

        StringFormat sfLeft;
        sfLeft.SetAlignment(StringAlignmentNear);
        sfLeft.SetLineAlignment(StringAlignmentCenter);
        sfLeft.SetFormatFlags(StringFormatFlagsNoWrap);

        StringFormat sfWrap;
        sfWrap.SetAlignment(StringAlignmentNear);
        sfWrap.SetLineAlignment(StringAlignmentNear);

        StringFormat sfRight;
        sfRight.SetAlignment(StringAlignmentFar);
        sfRight.SetLineAlignment(StringAlignmentCenter);

        StringFormat sfCenter;
        sfCenter.SetAlignment(StringAlignmentCenter);
        sfCenter.SetLineAlignment(StringAlignmentCenter);

        // 1. Background canvas (#F5F5F7 Apple macOS Grouped Background)
        SolidBrush bgBrush(Color(255, 245, 245, 247));
        g.FillRectangle(&bgBrush, 0, 0, width, height);

        // 2. Top Header Bar (0..64)
        SolidBrush whiteBrush(Color(255, 255, 255, 255));
        g.FillRectangle(&whiteBrush, 0.0f, 0.0f, static_cast<float>(width), 64.0f * s);
        Pen divPen(Color(255, 229, 229, 234), 1.0f * s);
        g.DrawLine(&divPen, 0.0f, 64.0f * s, static_cast<float>(width), 64.0f * s);

        // App Icon (38x38)
        RectF iconRect(18.0f * s, 13.0f * s, 38.0f * s, 38.0f * s);
        if (st->pAppIcon && st->pAppIcon->GetLastStatus() == Ok) {
            g.DrawImage(st->pAppIcon, iconRect);
        } else {
            FillRoundRect(g, iconRect, 9.0f * s, Color(255, 219, 39, 119));
            SolidBrush wBr(Color(255, 255, 255, 255));
            g.DrawString(L"SV", -1, &fBrand, iconRect, &sfCenter, &wBr);
        }

        // Brand Title "Sen Việt" + version pill "v2.0.0"
        SolidBrush primaryBrush(Color(255, 28, 28, 30));
        SolidBrush secondaryBrush(Color(255, 110, 110, 115));
        SolidBrush blueBrush(Color(255, 0, 122, 255));

        RectF brandRect(66.0f * s, 12.0f * s, 72.0f * s, 22.0f * s);
        g.DrawString(L"Sen Vi\u1EC7t", -1, &fBrand, brandRect, &sfLeft, &primaryBrush);

        RectF verPill(134.0f * s, 15.0f * s, 42.0f * s, 17.0f * s);
        FillRoundRect(g, verPill, 8.5f * s, Color(36, 0, 122, 255));
        g.DrawString(L"v2.0.0", -1, &fVersion, verPill, &sfCenter, &blueBrush);

        RectF subBrandRect(66.0f * s, 34.0f * s, 215.0f * s, 18.0f * s);
        g.DrawString(L"Native TSF \u2022 Kh\u00F4ng quy\u1EC1n Tr\u1EE3 n\u0103ng", -1, &fHeaderSub, subBrandRect, &sfLeft, &secondaryBrush);

        // 2-Tab Segmented Switcher (Cài đặt | Về ứng dụng)
        RectF segBg(284.0f * s, 16.0f * s, 198.0f * s, 32.0f * s);
        FillRoundRect(g, segBg, 8.0f * s, Color(255, 235, 235, 240));

        RectF tab0Rect(287.0f * s, 19.0f * s, 94.0f * s, 26.0f * s);
        RectF tab1Rect(385.0f * s, 19.0f * s, 94.0f * s, 26.0f * s);
        RectF activeTabRect = (st->selectedTab == 0) ? tab0Rect : tab1Rect;
        DrawCard(g, activeTabRect, 6.5f * s, Color(255, 255, 255, 255), Color(35, 0, 0, 0), 0.8f * s);

        SolidBrush tab0Brush(st->selectedTab == 0 ? Color(255, 0, 122, 255) : Color(255, 95, 95, 102));
        SolidBrush tab1Brush(st->selectedTab == 1 ? Color(255, 0, 122, 255) : Color(255, 95, 95, 102));
        g.DrawString(L"C\u00E0i \u0111\u1EB7t", -1, &fTab, tab0Rect, &sfCenter, &tab0Brush);
        g.DrawString(L"V\u1EC1 \u1EE9ng d\u1EE5ng", -1, &fTab, tab1Rect, &sfCenter, &tab1Brush);

        // =====================================================================
        // TAB 0: CÀI ĐẶT (Bento Inspector matching macOS SettingsView.swift)
        // =====================================================================
        if (st->selectedTab == 0) {
            // Section 1 Header
            g.DrawString(
                L"KI\u1EC2U G\u00D5 TI\u1EBENG VI\u1EC6T",
                -1, &fSecHdr, RectF(18.0f * s, 74.0f * s, 220.0f * s, 18.0f * s), &sfLeft, &secondaryBrush
            );
            g.DrawString(
                L"B\u1ECF d\u1EA5u t\u1EF1 do m\u1ECDi v\u1ECB tr\u00ED",
                -1, &fSecRight, RectF(260.0f * s, 74.0f * s, 222.0f * s, 18.0f * s), &sfRight, &blueBrush
            );

            // Hero Selector Cards: Telex Tự Do vs VNI Chuẩn
            DrawHeroInputCard(
                g, s, 18.0f, 98.0f, 226.0f, 76.0f,
                !st->prefs.isVni,
                st->hoveredRegion == HitRegion::CardTelex,
                L"TX",
                L"Telex T\u1EF1 Do",
                L"s f r x j w",
                L"vieetj \u2192 vi\u1EC7t \u2022 w \u2192 \u01B0",
                fCardTitle, fMonoBadge, fSub, sfLeft, sfCenter
            );

            DrawHeroInputCard(
                g, s, 256.0f, 98.0f, 226.0f, 76.0f,
                st->prefs.isVni,
                st->hoveredRegion == HitRegion::CardVni,
                L"19",
                L"VNI Chu\u1EA9n",
                L"1\u20135 \u2022 6\u20139",
                L"vie65t \u2192 vi\u1EC7t \u2022 9 \u2192 \u0111",
                fCardTitle, fMonoBadge, fSub, sfLeft, sfCenter
            );

            // Section 2 Header
            g.DrawString(
                L"TI\u1EC6N \u00CDCH & KH\u00D4NG GIAN L\u00C0M VI\u1EC6C",
                -1, &fSecHdr, RectF(18.0f * s, 188.0f * s, 320.0f * s, 18.0f * s), &sfLeft, &secondaryBrush
            );

            // 2x2 Bento Grid (100% Parity with macOS SettingsView.swift)
            // Tile 1: Bảng gõ tắt (Toggle + Quản lý button)
            DrawBentoFeatureTile(
                g, s, 18.0f, 210.0f, 226.0f, 82.0f,
                st->prefs.macroEnabled,
                st->hoveredRegion == HitRegion::TileMacroToggle || st->hoveredRegion == HitRegion::BtnMacroManage,
                Color(255, 88, 86, 214), // Indigo
                L"GT",
                L"B\u1EA3ng g\u00F5 t\u1EAFt",
                st->prefs.macroEnabled
                    ? L"\u0110ang b\u1EADt \u2022 38 c\u1EE5m t\u1EEB"
                    : L"\u0110ang t\u1EAFt g\u00F5 t\u1EAFt",
                L"Qu\u1EA3n l\u00FD (38)",
                fTileTitle, fSub, fPill, sfLeft, sfCenter
            );

            // Tile 2: Chế độ Code & Dev
            DrawBentoFeatureTile(
                g, s, 256.0f, 210.0f, 226.0f, 82.0f,
                st->prefs.developerMode,
                st->hoveredRegion == HitRegion::TileDevMode,
                Color(255, 13, 148, 136), // Teal
                L"<>",
                L"Ch\u1EBF \u0111\u1ED9 Code & Dev",
                st->prefs.developerMode
                    ? L"T\u1EF1 ng\u1EAFt d\u1EA5u trong `code`"
                    : L"G\u00F5 ti\u1EBFng Vi\u1EC7t b\u00ECnh th\u01B0\u1EDDng",
                st->prefs.developerMode ? L"\u0110ANG B\u1EACT" : L"T\u1EAET",
                fTileTitle, fSub, fPill, sfLeft, sfCenter
            );

            // Tile 3: Tốc gõ phụ âm (2 interactive chips: Đầu cc/gg/qq & Cuối -g/-h/-k)
            {
                bool anyChipActive = st->prefs.quickTelex || st->prefs.relaxedCoda;
                bool tileHovered = (st->hoveredRegion == HitRegion::ChipQuickTelex || st->hoveredRegion == HitRegion::ChipRelaxedCoda);
                Color orangeAcc(255, 234, 88, 12);
                Color tileFill = tileHovered ? Color(255, 250, 250, 253) : Color(255, 255, 255, 255);
                Color tileBorder = anyChipActive
                    ? Color(130, orangeAcc.GetR(), orangeAcc.GetG(), orangeAcc.GetB())
                    : Color(255, 226, 226, 232);
                DrawCard(g, RectF(18.0f * s, 302.0f * s, 226.0f * s, 82.0f * s), 12.0f * s, tileFill, tileBorder, 1.1f * s);

                RectF iconBox(29.0f * s, 313.0f * s, 26.0f * s, 26.0f * s);
                FillRoundRect(g, iconBox, 7.0f * s, anyChipActive ? Color(38, 234, 88, 12) : Color(255, 238, 238, 243));
                SolidBrush iconBr(anyChipActive ? orangeAcc : Color(255, 120, 120, 128));
                g.DrawString(L"\u26A1", -1, &fPill, iconBox, &sfCenter, &iconBr);

                g.DrawString(
                    L"T\u1ED1c g\u00F5 ph\u1EE5 \u00E2m",
                    -1, &fTileTitle, RectF(61.0f * s, 316.0f * s, 175.0f * s, 20.0f * s), &sfLeft, &primaryBrush
                );

                auto drawConsonantChip = [&](float cx, const WCHAR *label, bool active, bool hovered) {
                    RectF chipRect(cx * s, 348.0f * s, 100.0f * s, 25.0f * s);
                    Color cFill = active
                        ? Color(38, 234, 88, 12)
                        : (hovered ? Color(255, 234, 234, 240) : Color(255, 242, 242, 247));
                    Color cBorder = active ? Color(180, 234, 88, 12) : Color(255, 222, 222, 228);
                    FillRoundRect(g, chipRect, 7.0f * s, cFill);
                    DrawRoundRect(g, chipRect, 7.0f * s, cBorder, 1.0f * s);
                    SolidBrush cText(active ? orangeAcc : Color(255, 105, 105, 112));
                    g.DrawString(label, -1, &fPill, chipRect, &sfCenter, &cText);
                };

                drawConsonantChip(28.0f, L"\u0110\u1EA7u (cc/gg/qq)", st->prefs.quickTelex, st->hoveredRegion == HitRegion::ChipQuickTelex);
                drawConsonantChip(134.0f, L"Cu\u1ED1i (-g/-h/-k)", st->prefs.relaxedCoda, st->hoveredRegion == HitRegion::ChipRelaxedCoda);
            }

            // Tile 4: Phím tắt Đổi bộ gõ
            DrawBentoFeatureTile(
                g, s, 256.0f, 302.0f, 226.0f, 82.0f,
                true,
                st->hoveredRegion == HitRegion::TileWinTypingSettings,
                Color(255, 0, 122, 255), // Blue
                L"KB",
                L"Ph\u00EDm t\u1EAFt \u0110\u1ED5i b\u1ED9 g\u00F5",
                L"Win+Space \u2022 Ctrl+Shift+S m\u1EDF b\u1EA3ng",
                L"M\u1EDF C\u00C0I \u0110\u1EB6T \u2197",
                fTileTitle, fSub, fPill, sfLeft, sfCenter
            );

            // Section 3: Compact Smart Engine Status Strip
            RectF stripRect(18.0f * s, 396.0f * s, 464.0f * s, 38.0f * s);
            FillRoundRect(g, stripRect, 10.0f * s, Color(255, 237, 238, 253));
            DrawRoundRect(g, stripRect, 10.0f * s, Color(255, 198, 202, 248), 1.0f * s);

            SolidBrush indigoBrush(Color(255, 88, 86, 214));
            g.DrawString(
                L"\u2726 Tr\u00ED tu\u1EC7 Sen Vi\u1EC7t t\u1EF1 \u0111\u1ED9ng:",
                -1, &fBodyBold, RectF(30.0f * s, 396.0f * s, 155.0f * s, 38.0f * s), &sfLeft, &indigoBrush
            );
            g.DrawString(
                L"Song ng\u1EEF \u2022 Chu\u1EA9n m\u1EDBi \u2022 Hu\u1EF7 d\u1EA5u w/a/e/o \u2022 TSF Native",
                -1, &fSub, RectF(182.0f * s, 396.0f * s, 290.0f * s, 38.0f * s), &sfLeft, &secondaryBrush
            );
        } else {
            // =================================================================
            // TAB 1: VỀ ỨNG DỤNG (Matches macOS aboutTabView + NidoOffice)
            // =================================================================
            SolidBrush indigoBrush(Color(255, 88, 86, 214));
            SolidBrush tealBrush(Color(255, 13, 148, 136));
            SolidBrush orangeBrush(Color(255, 234, 88, 12));
            SolidBrush whiteTextBrush(Color(255, 255, 255, 255));

            // Card 1: SỨ MỆNH TỐI THƯỢNG (y=72, h=64)
            DrawCard(g, RectF(18.0f * s, 72.0f * s, 464.0f * s, 64.0f * s), 10.0f * s, Color(255, 255, 255, 255), Color(255, 226, 226, 232));
            g.DrawString(
                L"\u2726 S\u1EE8 M\u1EC6NH T\u1ED0I TH\u01AF\u1EE2NG",
                -1, &fSecHdr, RectF(30.0f * s, 78.0f * s, 250.0f * s, 16.0f * s), &sfLeft, &indigoBrush
            );
            g.DrawString(
                L"Sen Vi\u1EC7t \u0111\u01B0\u1EE3c ph\u00E1t tri\u1EC3n theo kim ch\u1EC9 nam \"H\u00E3y \u0111\u1EC3 vi\u1EC7c g\u00F5 l\u00E0 g\u00F5, d\u00F9 b\u1EA1n g\u00F5 ti\u1EBFng Vi\u1EC7t hay ti\u1EBFng Anh; nhanh hay ch\u1EADm; g\u00F5 l\u00E0 Sen Vi\u1EC7t\".",
                -1, &fSub, RectF(30.0f * s, 96.0f * s, 440.0f * s, 34.0f * s), &sfWrap, &primaryBrush
            );

            // Card 2: Mời tác giả ly cà phê nhỏ (VietQR) (y=142, h=96)
            DrawCard(g, RectF(18.0f * s, 142.0f * s, 464.0f * s, 96.0f * s), 10.0f * s, Color(255, 255, 255, 255), Color(255, 226, 226, 232));
            RectF qrBox(30.0f * s, 150.0f * s, 80.0f * s, 80.0f * s);
            DrawRoundRect(g, qrBox, 8.0f * s, Color(255, 226, 226, 232), 1.0f * s);
            if (st->pVietQr && st->pVietQr->GetLastStatus() == Ok) {
                RectF qrInner(34.0f * s, 154.0f * s, 72.0f * s, 72.0f * s);
                g.DrawImage(st->pVietQr, qrInner);
            } else {
                g.DrawString(L"VietQR\r\nMB Bank", -1, &fPill, qrBox, &sfCenter, &orangeBrush);
            }

            g.DrawString(
                L"\u2615 M\u1EDDi t\u00E1c gi\u1EA3 ly c\u00E0 ph\u00EA nh\u1ECF (VietQR)",
                -1, &fTileTitle, RectF(122.0f * s, 150.0f * s, 346.0f * s, 18.0f * s), &sfLeft, &primaryBrush
            );
            g.DrawString(
                L"Sen Vi\u1EC7t ho\u00E0n to\u00E0n mi\u1EC5n ph\u00ED. N\u1EBFu h\u1EEFu \u00EDch, b\u1EA1n c\u00F3 th\u1EC3 \u1EE7ng h\u1ED9 nh\u1EB9 qua VietQR:",
                -1, &fSub, RectF(122.0f * s, 170.0f * s, 346.0f * s, 16.0f * s), &sfLeft, &secondaryBrush
            );
            g.DrawString(
                L"MB Bank \u2022 STK: 0979266045",
                -1, &fBodyBold, RectF(122.0f * s, 190.0f * s, 235.0f * s, 22.0f * s), &sfLeft, &indigoBrush
            );

            // Copy STK Button (matches HitTestBentoUI: 372, 192, 96, 22)
            RectF copyBtn(372.0f * s, 192.0f * s, 96.0f * s, 22.0f * s);
            FillRoundRect(
                g, copyBtn, 6.0f * s,
                st->copiedStk ? Color(36, 13, 148, 136) : (st->hoveredRegion == HitRegion::BtnCopyBankStk ? Color(48, 88, 86, 214) : Color(28, 88, 86, 214))
            );
            DrawRoundRect(g, copyBtn, 6.0f * s, st->copiedStk ? Color(255, 13, 148, 136) : Color(255, 88, 86, 214), 1.0f * s);
            g.DrawString(
                st->copiedStk ? L"\u2713 \u0110\u00E3 ch\u00E9p" : L"Sao ch\u00E9p STK",
                -1, &fPill, copyBtn, &sfCenter, st->copiedStk ? &tealBrush : &indigoBrush
            );

            g.DrawString(
                L"Ch\u1EE7 TK: Tr\u1EA7n Ph\u00E1t \u0110\u1EA1t \u2022 N\u1ED9i dung: Ung ho Sen Viet",
                -1, &fSub, RectF(122.0f * s, 214.0f * s, 346.0f * s, 16.0f * s), &sfLeft, &secondaryBrush
            );

            // Card 3: Ecosystem Showcase — NidoOffice (Educenter.app) & YouPersona.com (y=244, h=108)
            DrawCard(g, RectF(18.0f * s, 244.0f * s, 464.0f * s, 108.0f * s), 10.0f * s, Color(255, 255, 255, 255), Color(120, 88, 86, 214), 1.1f * s);

            // Row 3A: NidoOffice (https://educenter.app) — y=246..298
            if (st->hoveredRegion == HitRegion::BtnNidoOfficeExplore) {
                FillRoundRect(g, RectF(22.0f * s, 246.0f * s, 456.0f * s, 50.0f * s), 8.0f * s, Color(255, 242, 243, 254));
            }
            g.DrawString(
                L"NidoOffice",
                -1, &fTileTitle, RectF(30.0f * s, 250.0f * s, 85.0f * s, 18.0f * s), &sfLeft, &primaryBrush
            );
            RectF nidoBadge(116.0f * s, 251.0f * s, 162.0f * s, 16.0f * s);
            FillRoundRect(g, nidoBadge, 8.0f * s, Color(36, 88, 86, 214));
            g.DrawString(L"B\u1ED8 OFFICE AI \u2022 EDUCENTER.APP", -1, &fPill, nidoBadge, &sfCenter, &indigoBrush);
            g.DrawString(
                L"So\u1EA1n th\u1EA3o v\u0103n b\u1EA3n, b\u1EA3ng t\u00EDnh, thuy\u1EBFt tr\u00ECnh & h\u1ECDc li\u1EC7u AI th\u1EBF h\u1EC7 m\u1EDBi.",
                -1, &fSub, RectF(30.0f * s, 271.0f * s, 344.0f * s, 20.0f * s), &sfLeft, &secondaryBrush
            );
            RectF nidoCta(382.0f * s, 259.0f * s, 86.0f * s, 24.0f * s);
            FillRoundRect(g, nidoCta, 12.0f * s, Color(255, 88, 86, 214));
            g.DrawString(L"Kh\u00E1m ph\u00E1 \u2197", -1, &fPill, nidoCta, &sfCenter, &whiteTextBrush);

            g.DrawLine(&divPen, 30.0f * s, 298.0f * s, 470.0f * s, 298.0f * s);

            // Row 3B: YouPersona.com — y=299..350
            if (st->hoveredRegion == HitRegion::BtnYouPersonaExplore) {
                FillRoundRect(g, RectF(22.0f * s, 300.0f * s, 456.0f * s, 50.0f * s), 8.0f * s, Color(255, 243, 252, 251));
            }
            g.DrawString(
                L"YouPersona.com",
                -1, &fTileTitle, RectF(30.0f * s, 304.0f * s, 115.0f * s, 18.0f * s), &sfLeft, &primaryBrush
            );
            RectF ypBadge(144.0f * s, 305.0f * s, 146.0f * s, 16.0f * s);
            FillRoundRect(g, ypBadge, 8.0f * s, Color(36, 13, 148, 136));
            g.DrawString(L"QU\u1EA2N L\u00DD THU CHI AI", -1, &fPill, ypBadge, &sfCenter, &tealBrush);
            g.DrawString(
                L"Tr\u1EE3 l\u00FD T\u00E0i ch\u00EDnh C\u00E1 nh\u00E2n AI \u2014 ghi ch\u00E9p gi\u1ECDng n\u00F3i, qu\u00E9t ho\u00E1 \u0111\u01A1n & 6 chi\u1EBFc l\u1ECD.",
                -1, &fSub, RectF(30.0f * s, 325.0f * s, 344.0f * s, 20.0f * s), &sfLeft, &secondaryBrush
            );
            RectF ypCta(382.0f * s, 313.0f * s, 86.0f * s, 24.0f * s);
            FillRoundRect(g, ypCta, 12.0f * s, Color(255, 13, 148, 136));
            g.DrawString(L"Kh\u00E1m ph\u00E1 \u2197", -1, &fPill, ypCta, &sfCenter, &whiteTextBrush);

            // Card 4: Cộng đồng & Tác giả (3 clickable rows at 360, 386, 412)
            DrawCard(g, RectF(18.0f * s, 358.0f * s, 464.0f * s, 80.0f * s), 10.0f * s, Color(255, 255, 255, 255), Color(255, 226, 226, 232));

            auto drawLinkRow = [&](float ry, const WCHAR *label, bool hovered, bool drawBottomDiv) {
                if (hovered) {
                    FillRoundRect(g, RectF(22.0f * s, ry * s, 456.0f * s, 25.0f * s), 6.0f * s, Color(255, 244, 245, 250));
                }
                g.DrawString(label, -1, &fBody, RectF(32.0f * s, ry * s, 400.0f * s, 25.0f * s), &sfLeft, &primaryBrush);
                g.DrawString(L"\u2197", -1, &fBodyBold, RectF(440.0f * s, ry * s, 28.0f * s, 25.0f * s), &sfRight, &indigoBrush);
                if (drawBottomDiv) {
                    g.DrawLine(&divPen, 30.0f * s, (ry + 26.0f) * s, 470.0f * s, (ry + 26.0f) * s);
                }
            };

            drawLinkRow(360.0f, L"K\u00EAnh Th\u1EA3o lu\u1EADn C\u1ED9ng \u0111\u1ED3ng (Zalo)", st->hoveredRegion == HitRegion::RowZalo, true);
            drawLinkRow(386.0f, L"T\u00E1c gi\u1EA3: Tr\u1EA7n Ph\u00E1t \u0110\u1EA1t (LinkedIn)", st->hoveredRegion == HitRegion::RowLinkedIn, true);
            drawLinkRow(412.0f, L"M\u00E3 ngu\u1ED3n M\u1EDF & B\u00E1o l\u1ED7i (GitHub)", st->hoveredRegion == HitRegion::RowGitHub, false);
        }

        // 3. Bottom Footer Bar (446..484)
        g.FillRectangle(&whiteBrush, 0.0f, 446.0f * s, static_cast<float>(width), 38.0f * s);
        g.DrawLine(&divPen, 0.0f, 446.0f * s, static_cast<float>(width), 446.0f * s);

        SolidBrush greenDotBrush(Color(255, 34, 197, 94));
        SolidBrush indigoFooterBrush(Color(255, 88, 86, 214));
        g.FillEllipse(&greenDotBrush, RectF(18.0f * s, 462.0f * s, 6.5f * s, 6.5f * s));
        g.DrawString(
            L"Song ng\u1EEF \u2022 Chu\u1EA9n m\u1EDBi \u2022 T\u1EF1 \u0111\u1ED9ng l\u01B0u",
            -1, &fFooter, RectF(30.0f * s, 446.0f * s, 232.0f * s, 38.0f * s), &sfLeft, &secondaryBrush
        );

        g.DrawString(L"NidoOffice", -1, &fFooterBold, RectF(268.0f * s, 446.0f * s, 62.0f * s, 38.0f * s), &sfCenter, &indigoFooterBrush);
        g.DrawString(L"\u2022", -1, &fFooter, RectF(330.0f * s, 446.0f * s, 6.0f * s, 38.0f * s), &sfCenter, &secondaryBrush);
        g.DrawString(L"YouPersona.com", -1, &fFooterBold, RectF(336.0f * s, 446.0f * s, 82.0f * s, 38.0f * s), &sfCenter, &blueBrush);
        g.DrawString(L"\u2022", -1, &fFooter, RectF(418.0f * s, 446.0f * s, 6.0f * s, 38.0f * s), &sfCenter, &secondaryBrush);
        g.DrawString(L"Zalo", -1, &fFooter, RectF(424.0f * s, 446.0f * s, 28.0f * s, 38.0f * s), &sfCenter, &secondaryBrush);
        g.DrawString(L"\u2022", -1, &fFooter, RectF(452.0f * s, 446.0f * s, 6.0f * s, 38.0f * s), &sfCenter, &secondaryBrush);
        g.DrawString(L"GitHub", -1, &fFooter, RectF(458.0f * s, 446.0f * s, 32.0f * s, 38.0f * s), &sfCenter, &secondaryBrush);
    }

    BitBlt(hdc, 0, 0, width, height, memDC, 0, 0, SRCCOPY);
    SelectObject(memDC, oldBmp);
    DeleteObject(memBmp);
    DeleteDC(memDC);
}

LRESULT CALLBACK VieLotusSettingsWndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    auto *st = reinterpret_cast<BentoSettingsState *>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));

    switch (msg) {
    case WM_CREATE: {
        st = new BentoSettingsState();
        SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(st));

        HDC hdc = GetDC(hwnd);
        int dpiY = GetDeviceCaps(hdc, LOGPIXELSY);
        ReleaseDC(hwnd, hdc);
        st->dpiScale = (dpiY > 0) ? (static_cast<float>(dpiY) / 96.0f) : 1.0f;

        LoadVieLotusPrefs(st->prefs);

        std::wstring dir = GetDllDirPath();
        if (!dir.empty()) {
            std::wstring iconPng = dir + L"assets\\app-icon-128x128.png";
            std::wstring qrPng = dir + L"assets\\vietqr.png";
            std::wstring icoFile = dir + L"VieLotusIM.ico";
            if (GetFileAttributesW(iconPng.c_str()) != INVALID_FILE_ATTRIBUTES) {
                st->pAppIcon = Image::FromFile(iconPng.c_str());
            } else if (GetFileAttributesW(icoFile.c_str()) != INVALID_FILE_ATTRIBUTES) {
                st->pAppIcon = Image::FromFile(icoFile.c_str());
            }
            if (GetFileAttributesW(qrPng.c_str()) != INVALID_FILE_ATTRIBUTES) {
                st->pVietQr = Image::FromFile(qrPng.c_str());
            }
            st->hWndIconBig = static_cast<HICON>(LoadImageW(nullptr, icoFile.c_str(), IMAGE_ICON, 32, 32, LR_LOADFROMFILE));
            st->hWndIconSmall = static_cast<HICON>(LoadImageW(nullptr, icoFile.c_str(), IMAGE_ICON, 16, 16, LR_LOADFROMFILE));
            if (st->hWndIconBig) SendMessageW(hwnd, WM_SETICON, ICON_BIG, reinterpret_cast<LPARAM>(st->hWndIconBig));
            if (st->hWndIconSmall) SendMessageW(hwnd, WM_SETICON, ICON_SMALL, reinterpret_cast<LPARAM>(st->hWndIconSmall));
        }

        // Enable Windows 11 rounded window corners via DWM
        DWORD cornerPref = 2; // DWMWCP_ROUND
        DwmSetWindowAttribute(hwnd, DWMWA_WINDOW_CORNER_PREFERENCE, &cornerPref, sizeof(cornerPref));
        return 0;
    }

    case WM_ERASEBKGND:
        return 1; // Handled in double-buffered WM_PAINT

    case WM_PAINT: {
        PAINTSTRUCT ps{};
        HDC hdc = BeginPaint(hwnd, &ps);
        RenderBentoSettingsUI(hwnd, hdc, st);
        EndPaint(hwnd, &ps);
        return 0;
    }

    case WM_MOUSEMOVE: {
        if (!st) break;
        float xDip = static_cast<float>( static_cast<short>(LOWORD(lParam)) ) / st->dpiScale;
        float yDip = static_cast<float>( static_cast<short>(HIWORD(lParam)) ) / st->dpiScale;
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
        float xDip = static_cast<float>( static_cast<short>(LOWORD(lParam)) ) / st->dpiScale;
        float yDip = static_cast<float>( static_cast<short>(HIWORD(lParam)) ) / st->dpiScale;
        HitRegion hit = HitTestBentoUI(st, xDip, yDip);

        switch (hit) {
        case HitRegion::TabSettings:
            if (st->selectedTab != 0) {
                st->selectedTab = 0;
                InvalidateRect(hwnd, nullptr, FALSE);
            }
            break;
        case HitRegion::TabAbout:
            if (st->selectedTab != 1) {
                st->selectedTab = 1;
                InvalidateRect(hwnd, nullptr, FALSE);
            }
            break;
        case HitRegion::CardTelex:
            if (st->prefs.isVni) {
                st->prefs.isVni = false;
                SaveVieLotusPrefs(st->prefs);
                ActivateUserProfiles();
                InvalidateRect(hwnd, nullptr, FALSE);
            }
            break;
        case HitRegion::CardVni:
            if (!st->prefs.isVni) {
                st->prefs.isVni = true;
                SaveVieLotusPrefs(st->prefs);
                ActivateUserProfiles();
                InvalidateRect(hwnd, nullptr, FALSE);
            }
            break;
        case HitRegion::TileMacroToggle:
            st->prefs.macroEnabled = !st->prefs.macroEnabled;
            SaveVieLotusPrefs(st->prefs);
            InvalidateRect(hwnd, nullptr, FALSE);
            break;
        case HitRegion::BtnMacroManage: {
            WCHAR appData[MAX_PATH] = {};
            if (ExpandEnvironmentStringsW(L"%APPDATA%\\VieLotusIM", appData, MAX_PATH) > 0) {
                CreateDirectoryW(appData, nullptr);
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
                ShellExecuteW(hwnd, L"open", L"notepad.exe", macroPath.c_str(), nullptr, SW_SHOWNORMAL);
            }
            break;
        }
        case HitRegion::TileDevMode:
            st->prefs.developerMode = !st->prefs.developerMode;
            SaveVieLotusPrefs(st->prefs);
            InvalidateRect(hwnd, nullptr, FALSE);
            break;
        case HitRegion::ChipQuickTelex:
            st->prefs.quickTelex = !st->prefs.quickTelex;
            SaveVieLotusPrefs(st->prefs);
            InvalidateRect(hwnd, nullptr, FALSE);
            break;
        case HitRegion::ChipRelaxedCoda:
            st->prefs.relaxedCoda = !st->prefs.relaxedCoda;
            SaveVieLotusPrefs(st->prefs);
            InvalidateRect(hwnd, nullptr, FALSE);
            break;
        case HitRegion::TileWinTypingSettings:
            ShellExecuteW(hwnd, L"open", L"ms-settings:typing", nullptr, nullptr, SW_SHOWNORMAL);
            break;
        case HitRegion::BtnCopyBankStk:
            CopyTextToClipboard(hwnd, L"0979266045");
            st->copiedStk = true;
            SetTimer(hwnd, 1, 1800, nullptr);
            InvalidateRect(hwnd, nullptr, FALSE);
            break;
        case HitRegion::BtnNidoOfficeExplore:
        case HitRegion::FooterNidoOffice:
            ShellExecuteW(hwnd, L"open", L"https://educenter.app", nullptr, nullptr, SW_SHOWNORMAL);
            break;
        case HitRegion::BtnYouPersonaExplore:
        case HitRegion::FooterYouPersona:
            ShellExecuteW(hwnd, L"open", L"https://youpersona.com", nullptr, nullptr, SW_SHOWNORMAL);
            break;
        case HitRegion::RowZalo:
        case HitRegion::FooterZalo:
            ShellExecuteW(hwnd, L"open", L"https://zalo.me/g/6wwyvywyvhsb0n6rwkze", nullptr, nullptr, SW_SHOWNORMAL);
            break;
        case HitRegion::RowLinkedIn:
            ShellExecuteW(hwnd, L"open", L"https://www.linkedin.com/in/stevedat/?isSelfProfile=true", nullptr, nullptr, SW_SHOWNORMAL);
            break;
        case HitRegion::RowGitHub:
        case HitRegion::FooterGitHub:
            ShellExecuteW(hwnd, L"open", L"https://github.com/stevedat/VieLotus-IM", nullptr, nullptr, SW_SHOWNORMAL);
            break;
        default:
            break;
        }
        return 0;
    }

    case WM_TIMER:
        if (wParam == 1 && st) {
            KillTimer(hwnd, 1);
            st->copiedStk = false;
            InvalidateRect(hwnd, nullptr, FALSE);
        }
        return 0;

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
            delete st->pVietQr;
            if (st->hWndIconBig) DestroyIcon(st->hWndIconBig);
            if (st->hWndIconSmall) DestroyIcon(st->hWndIconSmall);
            delete st;
            SetWindowLongPtrW(hwnd, GWLP_USERDATA, 0);
        }
        PostQuitMessage(0);
        return 0;
    }

    return DefWindowProcW(hwnd, msg, wParam, lParam);
}

} // namespace

void ShowVieLotusSettingsDialog(HWND hwndParent) {
    // If an instance of the settings window is already open, bring it to front
    static const WCHAR kWndClassName[] = L"VieLotusBentoSettingsWndClass";
    HWND hExisting = FindWindowW(kWndClassName, nullptr);
    if (hExisting && IsWindow(hExisting)) {
        ShowWindow(hExisting, SW_RESTORE);
        SetForegroundWindow(hExisting);
        return;
    }

    GdiplusStartupInput gdiplusStartupInput;
    ULONG_PTR gdiplusToken = 0;
    GdiplusStartup(&gdiplusToken, &gdiplusStartupInput, nullptr);

    WNDCLASSEXW wc{};
    wc.cbSize = sizeof(wc);
    wc.style = CS_HREDRAW | CS_VREDRAW;
    wc.lpfnWndProc = VieLotusSettingsWndProc;
    wc.hInstance = g_hInst;
    wc.hCursor = LoadCursorW(nullptr, MAKEINTRESOURCEW(32512)); // IDC_ARROW
    wc.hbrBackground = nullptr;
    wc.lpszClassName = kWndClassName;
    RegisterClassExW(&wc);

    HDC hdc = GetDC(nullptr);
    int dpiY = GetDeviceCaps(hdc, LOGPIXELSY);
    int screenW = GetSystemMetrics(SM_CXSCREEN);
    int screenH = GetSystemMetrics(SM_CYSCREEN);
    ReleaseDC(nullptr, hdc);

    int clientW = MulDiv(500, dpiY, 96);
    int clientH = MulDiv(484, dpiY, 96);

    DWORD dwStyle = WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX | WS_VISIBLE;
    DWORD dwExStyle = WS_EX_APPWINDOW;
    RECT rcWnd = { 0, 0, clientW, clientH };
    AdjustWindowRectEx(&rcWnd, dwStyle, FALSE, dwExStyle);

    int wndW = rcWnd.right - rcWnd.left;
    int wndH = rcWnd.bottom - rcWnd.top;
    int posX = (screenW > wndW) ? ((screenW - wndW) / 2) : 100;
    int posY = (screenH > wndH) ? ((screenH - wndH) / 2) : 100;

    HWND hwnd = CreateWindowExW(
        dwExStyle,
        kWndClassName,
        L"Sen Vi\u1EC7t (VieLotusIM)",
        dwStyle,
        posX, posY, wndW, wndH,
        hwndParent, nullptr, g_hInst, nullptr
    );
    if (hwnd) {
        ShowWindow(hwnd, SW_SHOW);
        UpdateWindow(hwnd);
        SetForegroundWindow(hwnd);

        MSG msg{};
        while (GetMessageW(&msg, nullptr, 0, 0) > 0) {
            TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }
    }

    if (gdiplusToken) {
        GdiplusShutdown(gdiplusToken);
    }
}
