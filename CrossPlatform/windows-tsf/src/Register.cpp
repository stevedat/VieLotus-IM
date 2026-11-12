#include "Register.h"
#include <strsafe.h>
#include <objidl.h>
#include <gdiplus.h>
#include <dwmapi.h>
#include <shellapi.h>
#include <string>
#include <vector>

#define CLSID_STRLEN 38
#define VI_LANGID 0x042A    // Vietnamese (Vietnam)
#define EN_US_LANGID 0x0409 // English (United States)

#ifndef ILOT_UNINSTALL
#define ILOT_UNINSTALL 0x00000001
#endif

#ifndef SDLOT_APPLYTOCURRENTTHREAD
#define SDLOT_APPLYTOCURRENTTHREAD 0x00000002
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
#ifndef TF_IPPMF_DONTCARECURRENTINPUTLANGUAGE
#define TF_IPPMF_DONTCARECURRENTINPUTLANGUAGE 0x00000004
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
static const WCHAR c_szPrefsGrammarProfileVal[] = L"SenFlexProfile";
static const WCHAR c_szPrefsMacroEnabledVal[] = L"MacroEnabled";
static const WCHAR c_szPrefsDeveloperModeVal[] = L"DeveloperMode";
static const WCHAR c_szPrefsQuickTelexVal[] = L"QuickTelex";
static const WCHAR c_szPrefsRelaxedCodaVal[] = L"RelaxedCoda";
static const WCHAR c_szPrefsAutoBypassRemoteVal[] = L"AutoBypassRemoteApps";
static const WCHAR c_szPrefsStartWithWindowsVal[] = L"StartWithWindows";
static const WCHAR c_szPrefsDefaultMigrationVal[] = L"DefaultPrefsMigrationVer";
static const WCHAR c_szPrefsAppBypassSubKey[] = L"Software\\VieLotusIM\\AppBypass";
static const WCHAR c_szPrefsUpdatedBySettingsVal[] = L"PrefsUpdatedBySettings";
static const WCHAR c_szRunSubKey[] = L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
static const WCHAR c_szRunValueName[] = L"VieLotusIM";

// LayoutOrTip strings for input.dll!InstallLayoutOrTip (042A Vietnamese ONLY — never pollute 0409 English)
static const WCHAR c_szTipTelexLayoutString[] =
    L"042A:{C7B08E9D-4762-4C97-8B1F-522197A598DE}{8E2A7B44-5A1F-4B82-9B7C-123456789ABC}";
static const WCHAR c_szTipVniLayoutString[] =
    L"042A:{C7B08E9D-4762-4C97-8B1F-522197A598DE}{8E2A7B45-5A1F-4B82-9B7C-123456789ABC}";

// Legacy LayoutOrTip strings (98DC, 98DD, 0409 English duplicates, and raw 042A:00000409 / 042A:0000042A layouts)
static const LPCWSTR kLegacyLayoutOrTipStringsToUninstall[] = {
    L"042A:{C7B08E9D-4762-4C97-8B1F-522197A598DC}{8E2A7B44-5A1F-4B82-9B7C-123456789ABC}",
    L"042A:{C7B08E9D-4762-4C97-8B1F-522197A598DC}{8E2A7B45-5A1F-4B82-9B7C-123456789ABC}",
    L"042A:{C7B08E9D-4762-4C97-8B1F-522197A598DD}{8E2A7B44-5A1F-4B82-9B7C-123456789ABC}",
    L"042A:{C7B08E9D-4762-4C97-8B1F-522197A598DD}{8E2A7B45-5A1F-4B82-9B7C-123456789ABC}",
    L"0409:{C7B08E9D-4762-4C97-8B1F-522197A598DC}{8E2A7B44-5A1F-4B82-9B7C-123456789ABC}",
    L"0409:{C7B08E9D-4762-4C97-8B1F-522197A598DC}{8E2A7B45-5A1F-4B82-9B7C-123456789ABC}",
    L"0409:{C7B08E9D-4762-4C97-8B1F-522197A598DD}{8E2A7B44-5A1F-4B82-9B7C-123456789ABC}",
    L"0409:{C7B08E9D-4762-4C97-8B1F-522197A598DD}{8E2A7B45-5A1F-4B82-9B7C-123456789ABC}",
    L"0409:{C7B08E9D-4762-4C97-8B1F-522197A598DE}{8E2A7B44-5A1F-4B82-9B7C-123456789ABC}",
    L"0409:{C7B08E9D-4762-4C97-8B1F-522197A598DE}{8E2A7B45-5A1F-4B82-9B7C-123456789ABC}",
    L"042A:00000409",
    L"042A:0000042A"
};

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

static std::atomic<uint32_t> g_localPrefsRevision{1};

uint32_t GetLocalPrefsRevision() {
    return g_localPrefsRevision.load(std::memory_order_relaxed);
}

static std::wstring ResolveInstalledSettingsExePath() {
    WCHAR pf[MAX_PATH] = {};
    if (ExpandEnvironmentStringsW(L"%ProgramW6432%\\VieLotusIM\\VieLotusSettings.exe", pf, MAX_PATH) > 0 && pf[0] != L'%') {
        if (GetFileAttributesW(pf) != INVALID_FILE_ATTRIBUTES) {
            return std::wstring(pf);
        }
    }
    const WCHAR *fallbackPf = L"C:\\Program Files\\VieLotusIM\\VieLotusSettings.exe";
    if (GetFileAttributesW(fallbackPf) != INVALID_FILE_ATTRIBUTES) {
        return std::wstring(fallbackPf);
    }
    WCHAR dllPath[MAX_PATH] = {};
    if (GetModuleFileNameW(g_hInst, dllPath, MAX_PATH) > 0) {
        std::wstring s(dllPath);
        size_t pos = s.find_last_of(L"\\/");
        if (pos != std::wstring::npos) {
            std::wstring candidate = s.substr(0, pos + 1) + L"VieLotusSettings.exe";
            if (GetFileAttributesW(candidate.c_str()) != INVALID_FILE_ATTRIBUTES) {
                return candidate;
            }
        }
    }
    return L"C:\\Program Files\\VieLotusIM\\VieLotusSettings.exe";
}

void SyncStartWithWindowsRegistry(bool enable) {
    HKEY hRun = nullptr;
    if (RegCreateKeyExW(
            HKEY_CURRENT_USER,
            c_szRunSubKey,
            0,
            nullptr,
            REG_OPTION_NON_VOLATILE,
            KEY_READ | KEY_WRITE,
            nullptr,
            &hRun,
            nullptr
        ) != ERROR_SUCCESS || !hRun) {
        return;
    }

    if (enable) {
        std::wstring exePath = ResolveInstalledSettingsExePath();
        if (GetFileAttributesW(exePath.c_str()) != INVALID_FILE_ATTRIBUTES) {
            std::wstring cmd = L"\"" + exePath + L"\" --startup";
            RegSetValueExW(
                hRun,
                c_szRunValueName,
                0,
                REG_SZ,
                reinterpret_cast<const BYTE *>(cmd.c_str()),
                static_cast<DWORD>((cmd.size() + 1) * sizeof(WCHAR))
            );
        } else {
            RegDeleteValueW(hRun, c_szRunValueName);
        }
    } else {
        RegDeleteValueW(hRun, c_szRunValueName);
    }

    RegCloseKey(hRun);
}

static void EnsureDefaultPrefsInitializedOnce() {
    HKEY hKey = nullptr;
    if (RegCreateKeyExW(
            HKEY_CURRENT_USER,
            c_szPrefsSubKey,
            0,
            nullptr,
            REG_OPTION_NON_VOLATILE,
            KEY_READ | KEY_WRITE,
            nullptr,
            &hKey,
            nullptr
        ) != ERROR_SUCCESS || !hKey) {
        return;
    }

    DWORD migVer = 0;
    if (!ReadRegDword(hKey, c_szPrefsDefaultMigrationVal, migVer) || migVer < 11u) {
        // One-time v2.0.2-r11 baseline initialization:
        // Default = Telex (InputMethod=0) and Dấu trước âm OFF (SenFlexProfile=0).
        // After DefaultPrefsMigrationVer=11 is recorded, user selections persist permanently across Windows reboots.
        WriteRegDword(hKey, c_szPrefsDefaultMigrationVal, 11u);
        WriteRegDword(hKey, c_szPrefsInputMethodVal, 0u);
        WriteRegDword(hKey, c_szPrefsGrammarProfileVal, 0u);

        DWORD dummy = 0;
        if (!ReadRegDword(hKey, c_szPrefsVnEnabledVal, dummy)) {
            WriteRegDword(hKey, c_szPrefsVnEnabledVal, 1u);
        }
        if (!ReadRegDword(hKey, c_szPrefsSmartBilingualVal, dummy)) {
            WriteRegDword(hKey, c_szPrefsSmartBilingualVal, 1u);
        }
        if (!ReadRegDword(hKey, c_szPrefsModernOrthoVal, dummy)) {
            WriteRegDword(hKey, c_szPrefsModernOrthoVal, 1u);
        }
        if (!ReadRegDword(hKey, c_szPrefsMacroEnabledVal, dummy)) {
            WriteRegDword(hKey, c_szPrefsMacroEnabledVal, 1u);
        }
        if (!ReadRegDword(hKey, c_szPrefsStartWithWindowsVal, dummy)) {
            WriteRegDword(hKey, c_szPrefsStartWithWindowsVal, 1u);
        }
    }

    RegCloseKey(hKey);
}

bool LoadPersistedVniPreference(bool &outIsVni) {
    EnsureDefaultPrefsInitializedOnce();
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
        WriteRegDword(hKey, c_szPrefsDefaultMigrationVal, 11u);
        WriteRegDword(hKey, c_szPrefsInputMethodVal, isVni ? 1u : 0u);
        RegCloseKey(hKey);
    }

    // Keep Windows User Profile InputMethodOverride and vi-VN tip order synced with the user's chosen input method
    LPCWSTR preferredTipString = isVni ? c_szTipVniLayoutString : c_szTipTelexLayoutString;
    HKEY hUserProfile = nullptr;
    if (RegOpenKeyExW(HKEY_CURRENT_USER, L"Control Panel\\International\\User Profile", 0, KEY_SET_VALUE, &hUserProfile) == ERROR_SUCCESS && hUserProfile) {
        RegSetValueExW(
            hUserProfile,
            L"InputMethodOverride",
            0,
            REG_SZ,
            reinterpret_cast<const BYTE *>(preferredTipString),
            static_cast<DWORD>((wcslen(preferredTipString) + 1) * sizeof(WCHAR))
        );
        RegCloseKey(hUserProfile);
    }
    HKEY hViKey = nullptr;
    if (RegOpenKeyExW(HKEY_CURRENT_USER, L"Control Panel\\International\\User Profile\\vi-VN", 0, KEY_SET_VALUE, &hViKey) == ERROR_SUCCESS && hViKey) {
        WriteRegDword(hViKey, c_szTipTelexLayoutString, isVni ? 2u : 1u);
        WriteRegDword(hViKey, c_szTipVniLayoutString, isVni ? 1u : 2u);
        RegCloseKey(hViKey);
    }

    g_localPrefsRevision.fetch_add(1, std::memory_order_relaxed);
}

bool ConsumeSettingsVniOverride(bool &outIsVni) {
    HKEY hKey = nullptr;
    if (RegOpenKeyExW(HKEY_CURRENT_USER, c_szPrefsSubKey, 0, KEY_READ | KEY_WRITE, &hKey) != ERROR_SUCCESS) {
        return false;
    }
    DWORD updated = 0;
    bool hasOverride = ReadRegDword(hKey, c_szPrefsUpdatedBySettingsVal, updated) && (updated != 0);
    if (hasOverride) {
        WriteRegDword(hKey, c_szPrefsUpdatedBySettingsVal, 0u);
        DWORD dwVal = 0;
        if (ReadRegDword(hKey, c_szPrefsInputMethodVal, dwVal)) {
            outIsVni = (dwVal == 1);
        }
    }
    RegCloseKey(hKey);
    return hasOverride;
}

void LoadVieLotusPrefs(VieLotusWindowsPrefs &outPrefs) {
    EnsureDefaultPrefsInitializedOnce();
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
    if (ReadRegDword(hKey, c_szPrefsGrammarProfileVal, dwVal)) {
        outPrefs.senFlex = (dwVal != 0);
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
    if (ReadRegDword(hKey, c_szPrefsAutoBypassRemoteVal, dwVal)) {
        outPrefs.autoBypassRemoteApps = (dwVal != 0);
    }
    if (ReadRegDword(hKey, c_szPrefsStartWithWindowsVal, dwVal)) {
        outPrefs.startWithWindows = (dwVal != 0);
    }
    RegCloseKey(hKey);
}

void SaveVieLotusPrefs(const VieLotusWindowsPrefs &prefs) {
    HKEY hKey = nullptr;
    if (RegCreateKeyExW(HKEY_CURRENT_USER, c_szPrefsSubKey, 0, nullptr, REG_OPTION_NON_VOLATILE, KEY_WRITE, nullptr, &hKey, nullptr) == ERROR_SUCCESS) {
        WriteRegDword(hKey, c_szPrefsDefaultMigrationVal, 11u);
        WriteRegDword(hKey, c_szPrefsInputMethodVal, prefs.isVni ? 1u : 0u);
        WriteRegDword(hKey, c_szPrefsVnEnabledVal, prefs.vietnameseEnabled ? 1u : 0u);
        WriteRegDword(hKey, c_szPrefsSmartBilingualVal, prefs.smartBilingual ? 1u : 0u);
        WriteRegDword(hKey, c_szPrefsModernOrthoVal, prefs.modernOrthography ? 1u : 0u);
        WriteRegDword(hKey, c_szPrefsGrammarProfileVal, prefs.senFlex ? 1u : 0u);
        WriteRegDword(hKey, c_szPrefsMacroEnabledVal, prefs.macroEnabled ? 1u : 0u);
        WriteRegDword(hKey, c_szPrefsDeveloperModeVal, prefs.developerMode ? 1u : 0u);
        WriteRegDword(hKey, c_szPrefsQuickTelexVal, prefs.quickTelex ? 1u : 0u);
        WriteRegDword(hKey, c_szPrefsRelaxedCodaVal, prefs.relaxedCoda ? 1u : 0u);
        WriteRegDword(hKey, c_szPrefsAutoBypassRemoteVal, prefs.autoBypassRemoteApps ? 1u : 0u);
        WriteRegDword(hKey, c_szPrefsStartWithWindowsVal, prefs.startWithWindows ? 1u : 0u);
        WriteRegDword(hKey, c_szPrefsUpdatedBySettingsVal, 1u);
        RegCloseKey(hKey);
    }
    SavePersistedVniPreference(prefs.isVni);
    SyncStartWithWindowsRegistry(prefs.startWithWindows);
}

bool LoadPerAppBypassPreference(const wchar_t *exeName, bool &outBypass) {
    if (!exeName || exeName[0] == L'\0') return false;
    HKEY hKey = nullptr;
    if (RegOpenKeyExW(HKEY_CURRENT_USER, c_szPrefsAppBypassSubKey, 0, KEY_READ, &hKey) != ERROR_SUCCESS) {
        return false;
    }
    DWORD dwVal = 0;
    bool ok = ReadRegDword(hKey, exeName, dwVal);
    RegCloseKey(hKey);
    if (ok) {
        outBypass = (dwVal != 0);
    }
    return ok;
}

void SavePerAppBypassPreference(const wchar_t *exeName, bool bypass) {
    if (!exeName || exeName[0] == L'\0') return;
    HKEY hKey = nullptr;
    if (RegCreateKeyExW(HKEY_CURRENT_USER, c_szPrefsAppBypassSubKey, 0, nullptr, REG_OPTION_NON_VOLATILE, KEY_WRITE, nullptr, &hKey, nullptr) == ERROR_SUCCESS) {
        WriteRegDword(hKey, exeName, bypass ? 1u : 0u);
        RegCloseKey(hKey);
    }
    g_localPrefsRevision.fetch_add(1, std::memory_order_relaxed);
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

static void CleanupLegacyClsid98DC() {
    HMODULE hInputDll = LoadLibraryExW(L"input.dll", nullptr, LOAD_LIBRARY_SEARCH_SYSTEM32);
    if (hInputDll) {
        using PFN_InstallLayoutOrTip = BOOL(WINAPI *)(LPCWSTR psz, DWORD dwFlags);
        using PFN_InstallLayoutOrTipUserReg = BOOL(WINAPI *)(LPCWSTR pszUserReg, LPCWSTR pszSystemReg, LPCWSTR pszSoftwareReg, LPCWSTR psz, DWORD dwFlags);
        auto pfnUserReg = reinterpret_cast<PFN_InstallLayoutOrTipUserReg>(GetProcAddress(hInputDll, "InstallLayoutOrTipUserReg"));
        if (pfnUserReg) {
            for (LPCWSTR tip : kLegacyLayoutOrTipStringsToUninstall) {
                pfnUserReg(nullptr, nullptr, nullptr, tip, ILOT_UNINSTALL);
            }
        }
        auto pfnInstall = reinterpret_cast<PFN_InstallLayoutOrTip>(GetProcAddress(hInputDll, "InstallLayoutOrTip"));
        if (pfnInstall) {
            for (LPCWSTR tip : kLegacyLayoutOrTipStringsToUninstall) {
                pfnInstall(tip, ILOT_UNINSTALL);
            }
        }
        FreeLibrary(hInputDll);
    }

    const GUID kLegacyClsids[] = { CLSID_VieLotusTIP_Legacy, CLSID_VieLotusTIP_Legacy2 };
    const LANGID kCleanLangs[] = { VI_LANGID, EN_US_LANGID };

    ITfInputProcessorProfiles *pProfiles = nullptr;
    if (SUCCEEDED(CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr, CLSCTX_INPROC_SERVER, IID_ITfInputProcessorProfiles, (void **)&pProfiles)) && pProfiles) {
        ITfInputProcessorProfileMgr *pProfileMgr = nullptr;
        if (SUCCEEDED(pProfiles->QueryInterface(IID_ITfInputProcessorProfileMgr, reinterpret_cast<void **>(&pProfileMgr))) && pProfileMgr) {
            for (const GUID &legacyClsid : kLegacyClsids) {
                for (LANGID lid : kCleanLangs) {
                    pProfileMgr->UnregisterProfile(legacyClsid, lid, GUID_VieLotusProfile, 0);
                    pProfileMgr->UnregisterProfile(legacyClsid, lid, GUID_VieLotusProfileVNI, 0);
                }
            }
            // Ensure current CLSID is never registered under 0409 English
            pProfileMgr->UnregisterProfile(CLSID_VieLotusTIP, EN_US_LANGID, GUID_VieLotusProfile, 0);
            pProfileMgr->UnregisterProfile(CLSID_VieLotusTIP, EN_US_LANGID, GUID_VieLotusProfileVNI, 0);
            pProfileMgr->Release();
        }
        for (const GUID &legacyClsid : kLegacyClsids) {
            pProfiles->Unregister(legacyClsid);
        }
        pProfiles->EnableLanguageProfile(CLSID_VieLotusTIP, EN_US_LANGID, GUID_VieLotusProfile, FALSE);
        pProfiles->EnableLanguageProfile(CLSID_VieLotusTIP, EN_US_LANGID, GUID_VieLotusProfileVNI, FALSE);
        pProfiles->Release();
    }

    ITfCategoryMgr *pCategoryMgr = nullptr;
    if (SUCCEEDED(CoCreateInstance(CLSID_TF_CategoryMgr, nullptr, CLSCTX_INPROC_SERVER, IID_ITfCategoryMgr, (void **)&pCategoryMgr)) && pCategoryMgr) {
        for (const GUID &legacyClsid : kLegacyClsids) {
            for (const auto &cat : kCategoriesToRegister) {
                pCategoryMgr->UnregisterCategory(legacyClsid, cat, legacyClsid);
            }
        }
        pCategoryMgr->Release();
    }

    HKEY hViKey = nullptr;
    if (RegOpenKeyExW(HKEY_CURRENT_USER, L"Control Panel\\International\\User Profile\\vi-VN", 0, KEY_SET_VALUE, &hViKey) == ERROR_SUCCESS && hViKey) {
        for (LPCWSTR tip : kLegacyLayoutOrTipStringsToUninstall) {
            RegDeleteValueW(hViKey, tip);
        }
        RegDeleteValueW(hViKey, L"042a:00000409");
        RegDeleteValueW(hViKey, L"042a:0000042a");
        RegCloseKey(hViKey);
    }

    HKEY hEnKey = nullptr;
    if (RegOpenKeyExW(HKEY_CURRENT_USER, L"Control Panel\\International\\User Profile\\en-US", 0, KEY_SET_VALUE, &hEnKey) == ERROR_SUCCESS && hEnKey) {
        for (LPCWSTR tip : kLegacyLayoutOrTipStringsToUninstall) {
            RegDeleteValueW(hEnKey, tip);
        }
        RegCloseKey(hEnKey);
    }

    RegDeleteKeyW(HKEY_CLASSES_ROOT, L"CLSID\\{C7B08E9D-4762-4C97-8B1F-522197A598DC}\\InprocServer32");
    RegDeleteKeyW(HKEY_CLASSES_ROOT, L"CLSID\\{C7B08E9D-4762-4C97-8B1F-522197A598DC}");
    RegDeleteKeyW(HKEY_CLASSES_ROOT, L"CLSID\\{C7B08E9D-4762-4C97-8B1F-522197A598DD}\\InprocServer32");
    RegDeleteKeyW(HKEY_CLASSES_ROOT, L"CLSID\\{C7B08E9D-4762-4C97-8B1F-522197A598DD}");
}

HRESULT RegisterProfiles() {
    EnsureDefaultPrefsInitializedOnce();
    CleanupLegacyClsid98DC();

    bool preferVni = false;
    LoadPersistedVniPreference(preferVni);

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
            pProfiles->EnableLanguageProfileByDefault(CLSID_VieLotusTIP, VI_LANGID, GUID_VieLotusProfile, preferVni ? FALSE : TRUE);
            pProfiles->EnableLanguageProfileByDefault(CLSID_VieLotusTIP, VI_LANGID, GUID_VieLotusProfileVNI, preferVni ? TRUE : FALSE);
        }

        ITfInputProcessorProfileMgr *pProfileMgr = nullptr;
        if (SUCCEEDED(pProfiles->QueryInterface(IID_ITfInputProcessorProfileMgr, reinterpret_cast<void **>(&pProfileMgr))) && pProfileMgr) {
            HKL hklUS = reinterpret_cast<HKL>(static_cast<ULONG_PTR>(0x0409042A));
            pProfileMgr->RegisterProfile(
                CLSID_VieLotusTIP,
                VI_LANGID,
                GUID_VieLotusProfile,
                c_szProfileDesc,
                (ULONG)wcslen(c_szProfileDesc),
                szFilePath,
                cchFile,
                0,
                hklUS,
                0,
                preferVni ? FALSE : TRUE,
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
                hklUS,
                0,
                preferVni ? TRUE : FALSE,
                0
            );
            pProfileMgr->Release();
        }

        pProfiles->Release();
    }
    return hr;
}

static void SyncWinUserLanguageListViaPowerShell(bool preferVni) {
    HKEY hPrefs = nullptr;
    DWORD cleanVer = 0;
    if (RegCreateKeyExW(
            HKEY_CURRENT_USER,
            c_szPrefsSubKey,
            0,
            nullptr,
            REG_OPTION_NON_VOLATILE,
            KEY_READ | KEY_WRITE,
            nullptr,
            &hPrefs,
            nullptr
        ) == ERROR_SUCCESS && hPrefs) {
        ReadRegDword(hPrefs, L"WinLangListCleanVer", cleanVer);
        RegCloseKey(hPrefs);
    }
    if (cleanVer >= 9u) {
        return;
    }

    WCHAR cmdLine[2048] = {0};
    StringCchPrintfW(
        cmdLine,
        2048,
        L"powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -Command \""
        L"$ErrorActionPreference='SilentlyContinue';"
        L"$telex='042A:{C7B08E9D-4762-4C97-8B1F-522197A598DE}{8E2A7B44-5A1F-4B82-9B7C-123456789ABC}';"
        L"$vni='042A:{C7B08E9D-4762-4C97-8B1F-522197A598DE}{8E2A7B45-5A1F-4B82-9B7C-123456789ABC}';"
        L"$pref=%s;$other=%s;"
        L"$list=Get-WinUserLanguageList;"
        L"if(-not $list){$list=New-WinUserLanguageList 'vi-VN'};"
        L"foreach($item in $list){if($item.LanguageTag -notlike 'vi*'){"
        L"$rem=@($item.InputMethodTips|Where-Object{$_ -like '*C7B08E9D*'});"
        L"foreach($r in $rem){[void]$item.InputMethodTips.Remove($r)}"
        L"}};"
        L"$v=$list|Where-Object{$_.LanguageTag -like 'vi*'}|Select-Object -First 1;"
        L"$tag=if($v){$v.LanguageTag}else{'vi-VN'};"
        L"$newList=New-WinUserLanguageList $tag;"
        L"$newList[0].InputMethodTips.Clear();"
        L"[void]$newList[0].InputMethodTips.Add($pref);"
        L"[void]$newList[0].InputMethodTips.Add($other);"
        L"foreach($item in $list){if($item.LanguageTag -notlike 'vi*'){$newList.Add($item)}};"
        L"Set-WinUserLanguageList $newList -Force -Confirm:$false;"
        L"Set-WinDefaultInputMethodOverride -InputTip $pref\"",
        preferVni ? L"$vni" : L"$telex",
        preferVni ? L"$telex" : L"$vni"
    );

    STARTUPINFOW si{};
    si.cb = sizeof(si);
    si.dwFlags = STARTF_USESHOWWINDOW;
    si.wShowWindow = SW_HIDE;
    PROCESS_INFORMATION pi{};
    if (CreateProcessW(nullptr, cmdLine, nullptr, nullptr, FALSE, CREATE_NO_WINDOW, nullptr, nullptr, &si, &pi)) {
        WaitForSingleObject(pi.hProcess, 8000);
        DWORD exitCode = 1;
        GetExitCodeProcess(pi.hProcess, &exitCode);
        CloseHandle(pi.hThread);
        CloseHandle(pi.hProcess);
        if (exitCode == 0) {
            if (RegCreateKeyExW(
                    HKEY_CURRENT_USER,
                    c_szPrefsSubKey,
                    0,
                    nullptr,
                    REG_OPTION_NON_VOLATILE,
                    KEY_WRITE,
                    nullptr,
                    &hPrefs,
                    nullptr
                ) == ERROR_SUCCESS && hPrefs) {
                WriteRegDword(hPrefs, L"WinLangListCleanVer", 9u);
                RegCloseKey(hPrefs);
            }
        }
    }
}

static void EnsureVietnameseUserProfileLanguage(bool preferVni) {
    LPCWSTR preferredTipString = preferVni ? c_szTipVniLayoutString : c_szTipTelexLayoutString;

    HKEY hUserProfile = nullptr;
    if (RegCreateKeyExW(
            HKEY_CURRENT_USER,
            L"Control Panel\\International\\User Profile",
            0,
            nullptr,
            REG_OPTION_NON_VOLATILE,
            KEY_READ | KEY_WRITE,
            nullptr,
            &hUserProfile,
            nullptr
        ) == ERROR_SUCCESS && hUserProfile) {
        DWORD dwType = 0;
        DWORD cbData = 0;
        std::vector<std::wstring> otherLangs;

        if (RegQueryValueExW(hUserProfile, L"Languages", nullptr, &dwType, nullptr, &cbData) == ERROR_SUCCESS &&
            (dwType == REG_MULTI_SZ || dwType == REG_SZ) && cbData >= sizeof(WCHAR)) {
            std::vector<WCHAR> buf((cbData / sizeof(WCHAR)) + 2, L'\0');
            if (RegQueryValueExW(hUserProfile, L"Languages", nullptr, &dwType, reinterpret_cast<LPBYTE>(buf.data()), &cbData) == ERROR_SUCCESS) {
                const WCHAR *p = buf.data();
                const WCHAR *end = buf.data() + (cbData / sizeof(WCHAR));
                while (p < end && *p != L'\0') {
                    std::wstring entry(p);
                    if (!entry.empty()) {
                        if (_wcsicmp(entry.c_str(), L"vi-VN") != 0 && _wcsicmp(entry.c_str(), L"vi") != 0) {
                            otherLangs.push_back(entry);
                        }
                    }
                    p += entry.size() + 1;
                }
            }
        }

        // Put vi-VN FIRST so Windows 10/11 defaults all newly opened and existing app windows to Vietnamese (Sen Việt)
        std::vector<std::wstring> langs;
        langs.push_back(L"vi-VN");
        if (otherLangs.empty()) {
            langs.push_back(L"en-US");
        } else {
            for (const auto &s : otherLangs) {
                langs.push_back(s);
            }
        }
        std::vector<WCHAR> multiSz;
        for (const auto &s : langs) {
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

        // Set InputMethodOverride so Windows 10/11 Advanced Keyboard Settings uses Sen Việt across all apps
        RegSetValueExW(
            hUserProfile,
            L"InputMethodOverride",
            0,
            REG_SZ,
            reinterpret_cast<const BYTE *>(preferredTipString),
            static_cast<DWORD>((wcslen(preferredTipString) + 1) * sizeof(WCHAR))
        );
        RegCloseKey(hUserProfile);
    }

    HKEY hViKey = nullptr;
    if (RegCreateKeyExW(
            HKEY_CURRENT_USER,
            L"Control Panel\\International\\User Profile\\vi-VN",
            0,
            nullptr,
            REG_OPTION_NON_VOLATILE,
            KEY_READ | KEY_WRITE,
            nullptr,
            &hViKey,
            nullptr
        ) == ERROR_SUCCESS && hViKey) {
        DWORD dwType = 0;
        DWORD cbData = 0;
        if (RegQueryValueExW(hViKey, L"CachedLanguageName", nullptr, &dwType, nullptr, &cbData) != ERROR_SUCCESS) {
            static const WCHAR kCachedName[] = L"@Winlangdb.dll,-1481";
            RegSetValueExW(
                hViKey,
                L"CachedLanguageName",
                0,
                REG_SZ,
                reinterpret_cast<const BYTE *>(kCachedName),
                static_cast<DWORD>(sizeof(kCachedName))
            );
        }
        WriteRegDword(hViKey, L"TransientLangId", VI_LANGID);
        // Remove raw non-TSF keyboard layouts (VIE — US 042A:00000409 & VIE — Vietnamese 042A:0000042A)
        RegDeleteValueW(hViKey, L"042A:00000409");
        RegDeleteValueW(hViKey, L"042a:00000409");
        RegDeleteValueW(hViKey, L"042A:0000042A");
        RegDeleteValueW(hViKey, L"042a:0000042a");
        for (LPCWSTR tip : kLegacyLayoutOrTipStringsToUninstall) {
            RegDeleteValueW(hViKey, tip);
        }
        WriteRegDword(hViKey, c_szTipTelexLayoutString, preferVni ? 2u : 1u);
        WriteRegDword(hViKey, c_szTipVniLayoutString, preferVni ? 1u : 2u);
        RegCloseKey(hViKey);
    }

    HKEY hEnKey = nullptr;
    if (RegOpenKeyExW(
            HKEY_CURRENT_USER,
            L"Control Panel\\International\\User Profile\\en-US",
            0,
            KEY_SET_VALUE,
            &hEnKey
        ) == ERROR_SUCCESS && hEnKey) {
        for (LPCWSTR tip : kLegacyLayoutOrTipStringsToUninstall) {
            RegDeleteValueW(hEnKey, tip);
        }
        RegCloseKey(hEnKey);
    }

    // Map 0000042a -> 00000409 in Substitutes so physical keys on 0x042A use standard US QWERTY (HKL=0x0409042A)
    // instead of legacy Windows Vietnamese KBDVNTC.DLL (HKL=0x042A042A where 1..0 = ă,â,ê,ô,̀,̉,̃,́,̣,đ).
    HKEY hSubKey = nullptr;
    if (RegCreateKeyExW(
            HKEY_CURRENT_USER,
            L"Keyboard Layout\\Substitutes",
            0,
            nullptr,
            REG_OPTION_NON_VOLATILE,
            KEY_WRITE,
            nullptr,
            &hSubKey,
            nullptr
        ) == ERROR_SUCCESS && hSubKey) {
        static const WCHAR kUsLayout[] = L"00000409";
        RegSetValueExW(hSubKey, L"0000042a", 0, REG_SZ, reinterpret_cast<const BYTE *>(kUsLayout), static_cast<DWORD>(sizeof(kUsLayout)));
        RegSetValueExW(hSubKey, L"d001042a", 0, REG_SZ, reinterpret_cast<const BYTE *>(kUsLayout), static_cast<DWORD>(sizeof(kUsLayout)));
        RegCloseKey(hSubKey);
    }

    HKEY hPreloadKey = nullptr;
    if (RegCreateKeyExW(
            HKEY_CURRENT_USER,
            L"Keyboard Layout\\Preload",
            0,
            nullptr,
            REG_OPTION_NON_VOLATILE,
            KEY_READ | KEY_WRITE,
            nullptr,
            &hPreloadKey,
            nullptr
        ) == ERROR_SUCCESS && hPreloadKey) {
        static const WCHAR kUsLayout[] = L"00000409";
        RegSetValueExW(hPreloadKey, L"1", 0, REG_SZ, reinterpret_cast<const BYTE *>(kUsLayout), static_cast<DWORD>(sizeof(kUsLayout)));
        WCHAR preload2[32] = {0};
        DWORD cb2 = sizeof(preload2);
        if (RegQueryValueExW(hPreloadKey, L"2", nullptr, nullptr, reinterpret_cast<LPBYTE>(preload2), &cb2) == ERROR_SUCCESS) {
            if (_wcsicmp(preload2, L"0000042a") == 0 || _wcsicmp(preload2, L"00000409") == 0) {
                RegDeleteValueW(hPreloadKey, L"2");
            }
        }
        RegCloseKey(hPreloadKey);
    }
}

HRESULT ActivateUserProfiles() {
    EnsureDefaultPrefsInitializedOnce();
    CleanupLegacyClsid98DC();

    VieLotusWindowsPrefs prefs{};
    LoadVieLotusPrefs(prefs);
    SyncStartWithWindowsRegistry(prefs.startWithWindows);

    bool preferVni = prefs.isVni;
    const GUID &preferredGuid = preferVni ? GUID_VieLotusProfileVNI : GUID_VieLotusProfile;
    const GUID &otherGuid = preferVni ? GUID_VieLotusProfile : GUID_VieLotusProfileVNI;
    LPCWSTR preferredTipString = preferVni ? c_szTipVniLayoutString : c_szTipTelexLayoutString;
    LPCWSTR otherTipString = preferVni ? c_szTipTelexLayoutString : c_szTipVniLayoutString;

    EnsureVietnameseUserProfileLanguage(preferVni);
    SyncWinUserLanguageListViaPowerShell(preferVni);

    HMODULE hInputDll = LoadLibraryExW(L"input.dll", nullptr, LOAD_LIBRARY_SEARCH_SYSTEM32);
    if (hInputDll) {
        using PFN_InstallLayoutOrTip = BOOL(WINAPI *)(LPCWSTR psz, DWORD dwFlags);
        using PFN_InstallLayoutOrTipUserReg = BOOL(WINAPI *)(LPCWSTR pszUserReg, LPCWSTR pszSystemReg, LPCWSTR pszSoftwareReg, LPCWSTR psz, DWORD dwFlags);
        using PFN_SetDefaultLayoutOrTip = BOOL(WINAPI *)(LPCWSTR psz, DWORD dwFlags);
        auto pfnInstallLayoutOrTipUserReg = reinterpret_cast<PFN_InstallLayoutOrTipUserReg>(GetProcAddress(hInputDll, "InstallLayoutOrTipUserReg"));
        if (pfnInstallLayoutOrTipUserReg) {
            for (LPCWSTR tip : kLegacyLayoutOrTipStringsToUninstall) {
                pfnInstallLayoutOrTipUserReg(nullptr, nullptr, nullptr, tip, ILOT_UNINSTALL);
            }
            pfnInstallLayoutOrTipUserReg(nullptr, nullptr, nullptr, otherTipString, 0);
            pfnInstallLayoutOrTipUserReg(nullptr, nullptr, nullptr, preferredTipString, 0);
        }
        auto pfnInstallLayoutOrTip = reinterpret_cast<PFN_InstallLayoutOrTip>(GetProcAddress(hInputDll, "InstallLayoutOrTip"));
        if (pfnInstallLayoutOrTip) {
            for (LPCWSTR tip : kLegacyLayoutOrTipStringsToUninstall) {
                pfnInstallLayoutOrTip(tip, ILOT_UNINSTALL);
            }
            pfnInstallLayoutOrTip(otherTipString, 0);
            pfnInstallLayoutOrTip(preferredTipString, 0);
        }
        auto pfnSetDefaultLayoutOrTip = reinterpret_cast<PFN_SetDefaultLayoutOrTip>(GetProcAddress(hInputDll, "SetDefaultLayoutOrTip"));
        if (pfnSetDefaultLayoutOrTip) {
            pfnSetDefaultLayoutOrTip(preferredTipString, 0);
            pfnSetDefaultLayoutOrTip(preferredTipString, SDLOT_APPLYTOCURRENTTHREAD);
        }
        FreeLibrary(hInputDll);
    }

    // Load substituted 0000042a -> 00000409 (HKL=0x0409042A, US QWERTY physical layout on vi-VN)
    // and evict legacy KBDVNTC.DLL (HKL=0x042A042A) if it was loaded in the current session.
    HKL hklViUs = LoadKeyboardLayoutW(L"0000042a", KLF_SUBSTITUTE_OK | KLF_ACTIVATE | KLF_SETFORPROCESS);
    if (!hklViUs) {
        hklViUs = reinterpret_cast<HKL>(static_cast<ULONG_PTR>(0x0409042A));
    }

    ITfInputProcessorProfiles *pProfiles = nullptr;
    HRESULT hr = CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr, CLSCTX_INPROC_SERVER, IID_ITfInputProcessorProfiles, (void **)&pProfiles);
    if (SUCCEEDED(hr) && pProfiles) {
        ITfInputProcessorProfileMgr *pProfileMgr = nullptr;
        pProfiles->QueryInterface(IID_ITfInputProcessorProfileMgr, reinterpret_cast<void **>(&pProfileMgr));

        pProfiles->EnableLanguageProfile(CLSID_VieLotusTIP, VI_LANGID, GUID_VieLotusProfile, TRUE);
        pProfiles->EnableLanguageProfile(CLSID_VieLotusTIP, VI_LANGID, GUID_VieLotusProfileVNI, TRUE);
        pProfiles->EnableLanguageProfileByDefault(CLSID_VieLotusTIP, VI_LANGID, preferredGuid, TRUE);
        pProfiles->EnableLanguageProfileByDefault(CLSID_VieLotusTIP, VI_LANGID, otherGuid, FALSE);
        pProfiles->SetDefaultLanguageProfile(VI_LANGID, CLSID_VieLotusTIP, preferredGuid);
        pProfiles->ChangeCurrentLanguage(VI_LANGID);
        pProfiles->ActivateLanguageProfile(CLSID_VieLotusTIP, VI_LANGID, preferredGuid);

        if (pProfileMgr) {
            pProfileMgr->ActivateProfile(
                TF_PROFILETYPE_INPUTPROCESSOR,
                VI_LANGID,
                CLSID_VieLotusTIP,
                preferredGuid,
                nullptr,
                TF_IPPMF_FORPROCESS | TF_IPPMF_ENABLEPROFILE | TF_IPPMF_DONTCARECURRENTINPUTLANGUAGE
            );
            pProfileMgr->ActivateProfile(
                TF_PROFILETYPE_INPUTPROCESSOR,
                VI_LANGID,
                CLSID_VieLotusTIP,
                preferredGuid,
                nullptr,
                TF_IPPMF_FORSESSION | TF_IPPMF_ENABLEPROFILE | TF_IPPMF_DONTCARECURRENTINPUTLANGUAGE
            );
            pProfileMgr->Release();
        }
        pProfiles->Release();
    }

    if (hklViUs) {
        ActivateKeyboardLayout(hklViUs, KLF_SETFORPROCESS);
    }
    HKL hklLegacyVntc = reinterpret_cast<HKL>(static_cast<ULONG_PTR>(0x042A042A));
    if (hklViUs != hklLegacyVntc) {
        UnloadKeyboardLayout(hklLegacyVntc);
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

    return hr;
}

HRESULT DeactivateUserProfiles() {
    CleanupLegacyClsid98DC();

    HMODULE hInputDll = LoadLibraryExW(L"input.dll", nullptr, LOAD_LIBRARY_SEARCH_SYSTEM32);
    if (hInputDll) {
        using PFN_InstallLayoutOrTip = BOOL(WINAPI *)(LPCWSTR psz, DWORD dwFlags);
        using PFN_InstallLayoutOrTipUserReg = BOOL(WINAPI *)(LPCWSTR pszUserReg, LPCWSTR pszSystemReg, LPCWSTR pszSoftwareReg, LPCWSTR psz, DWORD dwFlags);
        auto pfnUserReg = reinterpret_cast<PFN_InstallLayoutOrTipUserReg>(GetProcAddress(hInputDll, "InstallLayoutOrTipUserReg"));
        if (pfnUserReg) {
            pfnUserReg(nullptr, nullptr, nullptr, c_szTipTelexLayoutString, ILOT_UNINSTALL);
            pfnUserReg(nullptr, nullptr, nullptr, c_szTipVniLayoutString, ILOT_UNINSTALL);
        }
        auto pfnInstallLayoutOrTip = reinterpret_cast<PFN_InstallLayoutOrTip>(GetProcAddress(hInputDll, "InstallLayoutOrTip"));
        if (pfnInstallLayoutOrTip) {
            pfnInstallLayoutOrTip(c_szTipTelexLayoutString, ILOT_UNINSTALL);
            pfnInstallLayoutOrTip(c_szTipVniLayoutString, ILOT_UNINSTALL);
        }
        FreeLibrary(hInputDll);
    }
    HKEY hUserProfile = nullptr;
    if (RegOpenKeyExW(HKEY_CURRENT_USER, L"Control Panel\\International\\User Profile", 0, KEY_SET_VALUE, &hUserProfile) == ERROR_SUCCESS && hUserProfile) {
        RegDeleteValueW(hUserProfile, L"InputMethodOverride");
        RegCloseKey(hUserProfile);
    }
    HKEY hViKey = nullptr;
    if (RegOpenKeyExW(HKEY_CURRENT_USER, L"Control Panel\\International\\User Profile\\vi-VN", 0, KEY_SET_VALUE, &hViKey) == ERROR_SUCCESS && hViKey) {
        RegDeleteValueW(hViKey, c_szTipTelexLayoutString);
        RegDeleteValueW(hViKey, c_szTipVniLayoutString);
        RegCloseKey(hViKey);
    }
    return S_OK;
}

HRESULT UnregisterProfiles() {
    const LANGID kLangs[] = { VI_LANGID, EN_US_LANGID };
    ITfInputProcessorProfiles *pProfiles = nullptr;
    HRESULT hr = CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr, CLSCTX_INPROC_SERVER, IID_ITfInputProcessorProfiles, (void **)&pProfiles);
    if (SUCCEEDED(hr) && pProfiles) {
        ITfInputProcessorProfileMgr *pProfileMgr = nullptr;
        if (SUCCEEDED(pProfiles->QueryInterface(IID_ITfInputProcessorProfileMgr, reinterpret_cast<void **>(&pProfileMgr))) && pProfileMgr) {
            for (LANGID lid : kLangs) {
                pProfileMgr->UnregisterProfile(CLSID_VieLotusTIP, lid, GUID_VieLotusProfile, 0);
                pProfileMgr->UnregisterProfile(CLSID_VieLotusTIP, lid, GUID_VieLotusProfileVNI, 0);
            }
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
// Matches Sources/VieLotusIM/SettingsView.swift (2 Tabs: Cài đặt | Thông tin)
// =============================================================================

namespace {

using namespace Gdiplus;

enum class HitRegion : int {
    None = 0,
    TabSettings,
    TabAbout,
    CardTelex,
    CardVni,
    BarSenFlex,
    TileMacroToggle,
    BtnMacroManage,
    TileDevMode,
    ChipQuickTelex,
    ChipRelaxedCoda,
    TileStartWithWin,
    BtnWinTypingSettings,
    BtnClearTestEdit,
    BtnNidoOfficeExplore,
    BtnYouPersonaExplore,
    RowFeedback,
    RowZalo,
    RowLinkedIn,
    RowGitHub,
    FooterNidoOffice,
    FooterYouPersona,
    FooterZalo,
    FooterGitHub,
    FooterFeedback
};

struct BentoSettingsState {
    VieLotusWindowsPrefs prefs{};
    int selectedTab{0}; // 0 = Cài đặt, 1 = Thông tin
    HitRegion hoveredRegion{HitRegion::None};
    float dpiScale{1.0f};
    bool isDark{false};
    bool trayRegistered{false};
    bool canHideToTrayOnClose{true};
    UINT wmTaskbarCreated{0};
    NOTIFYICONDATAW nid{};
    Image *pAppIcon{nullptr};
    HICON hWndIconBig{nullptr};
    HICON hWndIconSmall{nullptr};
    HWND hTestEdit{nullptr};
    HFONT hEditFont{nullptr};
    HBRUSH hEditBgBrush{nullptr};
};

static HICON LoadEmbeddedAppIcon(int cx, int cy) {
    HICON hIco = static_cast<HICON>(LoadImageW(g_hInst, MAKEINTRESOURCEW(101), IMAGE_ICON, cx, cy, LR_DEFAULTCOLOR));
    if (!hIco) {
        hIco = static_cast<HICON>(LoadImageW(GetModuleHandleW(nullptr), MAKEINTRESOURCEW(101), IMAGE_ICON, cx, cy, LR_DEFAULTCOLOR));
    }
    return hIco;
}

static Image *LoadEmbeddedPngImage(int resourceId) {
    HMODULE hMods[2] = { g_hInst, GetModuleHandleW(nullptr) };
    for (HMODULE hMod : hMods) {
        if (!hMod) continue;
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
        ) == ERROR_SUCCESS) {
        RegQueryValueExW(hKey, L"AppsUseLightTheme", nullptr, nullptr, reinterpret_cast<LPBYTE>(&useLight), &cb);
        RegCloseKey(hKey);
    }
    return (useLight == 0);
}

static std::wstring GetDllDirPath() {
    WCHAR path[MAX_PATH] = {0};
    if (GetModuleFileNameW(g_hInst, path, MAX_PATH) == 0) return L"";
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

    // Header Segmented Tabs (456..660, y=11..43)
    if (PtInDipRect(xDip, yDip, 456.0f, 11.0f, 102.0f, 32.0f)) return HitRegion::TabSettings;
    if (PtInDipRect(xDip, yDip, 558.0f, 11.0f, 102.0f, 32.0f)) return HitRegion::TabAbout;

    // Footer Links (y=384..424)
    if (PtInDipRect(xDip, yDip, 336.0f, 388.0f, 118.0f, 32.0f)) return HitRegion::FooterFeedback;
    if (PtInDipRect(xDip, yDip, 462.0f, 388.0f, 68.0f, 32.0f)) return HitRegion::FooterNidoOffice;
    if (PtInDipRect(xDip, yDip, 538.0f, 388.0f, 88.0f, 32.0f)) return HitRegion::FooterYouPersona;
    if (PtInDipRect(xDip, yDip, 632.0f, 388.0f, 36.0f, 32.0f)) return HitRegion::FooterGitHub;

    if (st->selectedTab == 0) {
        // Row 1: 3 Hero Cards (x=20..224, 238..442, 456..660, y=82..154)
        if (PtInDipRect(xDip, yDip, 20.0f, 82.0f, 204.0f, 72.0f)) return HitRegion::CardTelex;
        if (PtInDipRect(xDip, yDip, 238.0f, 82.0f, 204.0f, 72.0f)) return HitRegion::CardVni;
        if (PtInDipRect(xDip, yDip, 456.0f, 82.0f, 204.0f, 72.0f)) return HitRegion::BarSenFlex;

        // Row 2: Tile 1 (Gõ tắt Macro) & Tile 2 (Chế độ Code) (y=180..246)
        if (PtInDipRect(xDip, yDip, 202.0f, 188.0f, 68.0f, 24.0f)) return HitRegion::BtnMacroManage;
        if (PtInDipRect(xDip, yDip, 20.0f, 180.0f, 314.0f, 66.0f)) return HitRegion::TileMacroToggle;
        if (PtInDipRect(xDip, yDip, 346.0f, 180.0f, 314.0f, 66.0f)) return HitRegion::TileDevMode;

        // Row 3: Tile 3 (Tốc gõ phụ âm) & Tile 4 (Khởi động cùng Windows + Phím tắt) (y=256..322)
        if (PtInDipRect(xDip, yDip, 32.0f, 290.0f, 138.0f, 24.0f)) return HitRegion::ChipQuickTelex;
        if (PtInDipRect(xDip, yDip, 182.0f, 290.0f, 138.0f, 24.0f)) return HitRegion::ChipRelaxedCoda;
        if (PtInDipRect(xDip, yDip, 20.0f, 256.0f, 157.0f, 66.0f)) return HitRegion::ChipQuickTelex;
        if (PtInDipRect(xDip, yDip, 177.0f, 256.0f, 157.0f, 66.0f)) return HitRegion::ChipRelaxedCoda;

        if (PtInDipRect(xDip, yDip, 522.0f, 264.0f, 68.0f, 24.0f)) return HitRegion::BtnWinTypingSettings;
        if (PtInDipRect(xDip, yDip, 346.0f, 256.0f, 314.0f, 66.0f)) return HitRegion::TileStartWithWin;

        // Row 4: Ô thử gõ trực tiếp -> nút "Xoá"
        if (PtInDipRect(xDip, yDip, 594.0f, 338.0f, 58.0f, 28.0f)) return HitRegion::BtnClearTestEdit;
    } else {
        // Tab 1: Thông tin (680x424)
        if (PtInDipRect(xDip, yDip, 20.0f, 168.0f, 314.0f, 104.0f)) return HitRegion::BtnNidoOfficeExplore;
        if (PtInDipRect(xDip, yDip, 346.0f, 168.0f, 314.0f, 104.0f)) return HitRegion::BtnYouPersonaExplore;
        if (PtInDipRect(xDip, yDip, 32.0f, 298.0f, 146.0f, 36.0f)) return HitRegion::RowFeedback;
        if (PtInDipRect(xDip, yDip, 188.0f, 298.0f, 146.0f, 36.0f)) return HitRegion::RowZalo;
        if (PtInDipRect(xDip, yDip, 344.0f, 298.0f, 146.0f, 36.0f)) return HitRegion::RowLinkedIn;
        if (PtInDipRect(xDip, yDip, 500.0f, 298.0f, 148.0f, 36.0f)) return HitRegion::RowGitHub;
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

    // Icon badge square (top-left)
    RectF iconBox((x + 12.0f) * s, (y + 10.0f) * s, 24.0f * s, 24.0f * s);
    FillRoundRect(
        g, iconBox, 6.5f * s,
        isSelected ? accent : (isDark ? Color(255, 50, 50, 64) : Color(255, 236, 236, 241))
    );
    SolidBrush iconTextBrush(
        isSelected ? Color(255, 255, 255, 255) : (isDark ? Color(255, 175, 175, 188) : Color(255, 100, 100, 108))
    );
    g.DrawString(iconText, -1, &fBadge, iconBox, &sfCenter, &iconTextBrush);

    // Title
    SolidBrush primaryBrush(isDark ? Color(255, 245, 245, 247) : Color(255, 28, 28, 30));
    RectF titleRect((x + 42.0f) * s, (y + 10.0f) * s, (w - 72.0f) * s, 24.0f * s);
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
        Pen circlePen(isDark ? Color(255, 92, 92, 110) : Color(255, 195, 195, 204), 1.4f * s);
        g.DrawEllipse(&circlePen, chkRect);
    }

    // Bottom Row: Generous Monospace Pill Badge + Subtitle (zero wrapping)
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

    // Icon box (24x24)
    RectF iconBox((x + 12.0f) * s, (y + 10.0f) * s, 24.0f * s, 24.0f * s);
    Color iconBg = isActive
        ? Color(isDark ? 55 : 38, accent.GetR(), accent.GetG(), accent.GetB())
        : (isDark ? Color(255, 48, 48, 62) : Color(255, 238, 238, 243));
    FillRoundRect(g, iconBox, 6.5f * s, iconBg);
    SolidBrush iconBrush(isActive ? accent : (isDark ? Color(255, 165, 165, 178) : Color(255, 120, 120, 128)));
    g.DrawString(iconGlyph, -1, &fPill, iconBox, &sfCenter, &iconBrush);

    // Title
    float rightControlsW = showToggleSwitch ? (actionPillText ? 126.0f : 56.0f) : 78.0f;
    SolidBrush primaryBrush(isDark ? Color(255, 245, 245, 247) : Color(255, 28, 28, 30));
    RectF titleRect((x + 42.0f) * s, (y + 10.0f) * s, (w - 48.0f - rightControlsW) * s, 22.0f * s);
    g.DrawString(title, -1, &fTitle, titleRect, &sfLeft, &primaryBrush);

    // Optional action button pill (e.g. "Quản lý ↗" or "Phím tắt ↗")
    if (actionPillText && actionPillText[0] != L'\0') {
        float pillW = 68.0f;
        float pillX = showToggleSwitch ? (x + w - pillW - 56.0f) : (x + w - pillW - 12.0f);
        RectF pillRect(pillX * s, (y + 11.0f) * s, pillW * s, 21.0f * s);
        Color pillBg = isDark ? Color(255, 48, 48, 62) : Color(255, 238, 238, 244);
        FillRoundRect(g, pillRect, 6.5f * s, pillBg);
        DrawRoundRect(g, pillRect, 6.5f * s, isDark ? Color(255, 72, 72, 92) : Color(255, 216, 216, 226), 1.0f * s);
        SolidBrush pillTextBrush(isActive ? accent : (isDark ? Color(255, 195, 195, 210) : Color(255, 80, 80, 92)));
        g.DrawString(actionPillText, -1, &fPill, pillRect, &sfCenter, &pillTextBrush);
    }

    // Modern iOS/macOS style Toggle Switch on top-right
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

    // Subtitle
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
        Font fBody(&ffSans, 11.5f * s, FontStyleRegular, UnitPixel);
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

        // 1. Background canvas (680 x 424 DIPs)
        SolidBrush bgBrush(canvasCol);
        g.FillRectangle(&bgBrush, 0, 0, width, height);

        // 2. Top Header Bar (0..54)
        SolidBrush barBrush(barCol);
        g.FillRectangle(&barBrush, 0.0f, 0.0f, static_cast<float>(width), 54.0f * s);
        Pen divPen(divCol, 1.0f * s);
        g.DrawLine(&divPen, 0.0f, 54.0f * s, static_cast<float>(width), 54.0f * s);

        // App Icon (36x36) loaded from embedded PNG resource
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
        g.DrawString(L"v2.0.2", -1, &fVersion, verPill, &sfCenter, &blueBrush);

        // Active mode status badge in header
        RectF modePill(198.0f * s, 10.0f * s, 134.0f * s, 17.0f * s);
        FillRoundRect(g, modePill, 8.5f * s, isDark ? Color(255, 28, 54, 42) : Color(255, 232, 250, 238));
        SolidBrush greenTextBrush(isDark ? Color(255, 74, 222, 128) : Color(255, 22, 163, 74));
        g.DrawString(
            st->prefs.isVni ? L"\u25CF \u0110ang b\u1EADt: Chu\u1EA9n VNI" : L"\u25CF \u0110ang b\u1EADt: Chu\u1EA9n Telex",
            -1, &fVersion, modePill, &sfCenter, &greenTextBrush
        );

        RectF subBrandRect(64.0f * s, 29.0f * s, 380.0f * s, 17.0f * s);
        g.DrawString(L"B\u1ED9 g\u00F5 ti\u1EBFng Vi\u1EC7t thu\u1EA7n chu\u1EA9n Native TSF \u2022 100% Offline", -1, &fHeaderSub, subBrandRect, &sfLeft, &secondaryBrush);

        // 2-Tab Segmented Switcher (Cài đặt | Thông tin) (x=456..660)
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
        g.DrawString(L"C\u00E0i \u0111\u1EB7t", -1, &fTab, tab0Rect, &sfCenter, &tab0Brush);
        g.DrawString(L"Th\u00F4ng tin", -1, &fTab, tab1Rect, &sfCenter, &tab1Brush);

        // =====================================================================
        // TAB 0: CÀI ĐẶT (Bố cục ngang chữ nhật 680x424, biên x=20..660, rộng 640px)
        // =====================================================================
        if (st->selectedTab == 0) {
            // Hàng 1: Kiểu gõ tiếng Việt (Telex Tự Do | VNI | Dấu trước âm)
            g.DrawString(
                L"KI\u1EC2U G\u00D5 TI\u1EBENG VI\u1EC6T",
                -1, &fSecHdr, RectF(20.0f * s, 61.0f * s, 240.0f * s, 17.0f * s), &sfLeft, &secondaryBrush
            );
            g.DrawString(
                L"B\u1ECF d\u1EA5u t\u1EF1 do \u2022 Ph\u00EDm Z xo\u00E1 d\u1EA5u",
                -1, &fSecRight, RectF(380.0f * s, 61.0f * s, 280.0f * s, 17.0f * s), &sfRight, &blueBrush
            );

            DrawHeroInputCard(
                g, s, isDark, 20.0f, 82.0f, 204.0f, 72.0f,
                !st->prefs.isVni,
                st->hoveredRegion == HitRegion::CardTelex,
                L"TX",
                L"Chu\u1EA9n Telex",
                L"s f r x j w",
                L"vieetj \u2192 vi\u1EC7t",
                fCardTitle, fMonoBadge, fSub, sfLeft, sfCenter
            );

            DrawHeroInputCard(
                g, s, isDark, 238.0f, 82.0f, 204.0f, 72.0f,
                st->prefs.isVni,
                st->hoveredRegion == HitRegion::CardVni,
                L"19",
                L"Chu\u1EA9n VNI",
                L"1\u20135 \u2022 6\u20139",
                L"viet65 \u2192 vi\u1EC7t",
                fCardTitle, fMonoBadge, fSub, sfLeft, sfCenter
            );

            DrawHeroInputCard(
                g, s, isDark, 456.0f, 82.0f, 204.0f, 72.0f,
                st->prefs.senFlex,
                st->hoveredRegion == HitRegion::BarSenFlex,
                L"\u2726",
                L"D\u1EA5u tr\u01B0\u1EDBc \u00E2m",
                L"rrung \u2192 r\u1EE7ng",
                st->prefs.senFlex ? L"\u0110ang b\u1EADt" : L"\u0110ang t\u1EAFt",
                fCardTitle, fMonoBadge, fSub, sfLeft, sfCenter
            );

            // Hàng 2 & 3: Tiện ích, Tương thích & Hệ thống (Bento Grid 2x2 rộng 314px/ô, gap 12px)
            g.DrawString(
                L"TI\u1EC6N \u00CDCH, T\u01AF\u01A0NG TH\u00CDCH & H\u1EC6 TH\u1ED0NG",
                -1, &fSecHdr, RectF(20.0f * s, 160.0f * s, 360.0f * s, 17.0f * s), &sfLeft, &secondaryBrush
            );

            // Tile 1: Bảng gõ tắt (x=20, y=180, w=314, h=66)
            DrawBentoFeatureTile(
                g, s, isDark, 20.0f, 180.0f, 314.0f, 66.0f,
                st->prefs.macroEnabled,
                st->hoveredRegion == HitRegion::TileMacroToggle || st->hoveredRegion == HitRegion::BtnMacroManage,
                indigoCol,
                L"GT",
                L"B\u1EA3ng g\u00F5 t\u1EAFt (Macro)",
                st->prefs.macroEnabled
                    ? L"\u0110ang b\u1EADt \u2022 T\u1EF1 bung c\u1EE5m t\u1EEB vi\u1EBFt t\u1EAFt"
                    : L"\u0110ang t\u1EAFt \u2022 B\u1EA5m c\u00F4ng t\u1EAFc \u0111\u1EC3 b\u1EADt",
                L"Qu\u1EA3n l\u00FD \u2197",
                true,
                fTileTitle, fSub, fPill, sfLeft, sfCenter
            );

            // Tile 2: Chế độ Code (x=346, y=180, w=314, h=66)
            DrawBentoFeatureTile(
                g, s, isDark, 346.0f, 180.0f, 314.0f, 66.0f,
                st->prefs.developerMode,
                st->hoveredRegion == HitRegion::TileDevMode,
                tealCol,
                L"<>",
                L"Ch\u1EBF \u0111\u1ED9 Code / IDE",
                st->prefs.developerMode
                    ? L"T\u1EF1 ng\u1EAFt d\u1EA5u trong c\u1EB7p `code` & CLI"
                    : L"Song ng\u1EEF th\u00F4ng minh ti\u00EAu chu\u1EA9n",
                nullptr,
                true,
                fTileTitle, fSub, fPill, sfLeft, sfCenter
            );

            // Tile 3: Tốc gõ phụ âm (x=20, y=256, w=314, h=66)
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
                    L"T\u1ED1c g\u00F5 ph\u1EE5 \u00E2m nhanh",
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

                drawConsonantChip(32.0f, L"\u0110\u1EA7u (cc/gg/qq)", st->prefs.quickTelex, st->hoveredRegion == HitRegion::ChipQuickTelex);
                drawConsonantChip(182.0f, L"Cu\u1ED1i (-g/-h/-k)", st->prefs.relaxedCoda, st->hoveredRegion == HitRegion::ChipRelaxedCoda);
            }

            // Tile 4: Khởi động cùng Windows & Phím tắt (x=346, y=256, w=314, h=66)
            DrawBentoFeatureTile(
                g, s, isDark, 346.0f, 256.0f, 314.0f, 66.0f,
                st->prefs.startWithWindows,
                st->hoveredRegion == HitRegion::TileStartWithWin || st->hoveredRegion == HitRegion::BtnWinTypingSettings,
                blueCol,
                L"WN",
                L"Kh\u1EDFi \u0111\u1ED9ng c\u00F9ng Windows",
                st->prefs.startWithWindows
                    ? L"T\u1EF1 ch\u1EA1y ng\u1EA7m & gi\u1EEF ki\u1EC3u g\u00F5 khi m\u1EDF m\u00E1y"
                    : L"Kh\u00F4ng t\u1EF1 ch\u1EA1y khi kh\u1EDFi \u0111\u1ED9ng Windows",
                L"Ph\u00EDm t\u1EAFt \u2197",
                true,
                fTileTitle, fSub, fPill, sfLeft, sfCenter
            );

            // Hàng 4: Ô thử gõ trực tiếp (x=20, y=332, w=640, h=40)
            RectF stripRect(20.0f * s, 332.0f * s, 640.0f * s, 40.0f * s);
            DrawCard(
                g, stripRect, 10.0f * s,
                cardCol,
                isDark ? Color(255, 72, 76, 130) : Color(255, 198, 202, 248),
                1.1f * s
            );

            SolidBrush indigoBrush(indigoCol);
            g.DrawString(
                L"\u2726 Th\u1EED g\u00F5:",
                -1, &fBodyBold, RectF(32.0f * s, 332.0f * s, 76.0f * s, 40.0f * s), &sfLeft, &indigoBrush
            );
            if (!st->hTestEdit) {
                g.DrawString(
                    L"truowngr \u2192 tr\u01B0\u1EDFng \u2022 12haf \u2192 12h\u00E0 \u2022 window user",
                    -1, &fSub, RectF(110.0f * s, 332.0f * s, 476.0f * s, 40.0f * s), &sfLeft, &secondaryBrush
                );
            }

            // "Xoá" button on the right of the test strip
            RectF clearBtn(594.0f * s, 339.0f * s, 56.0f * s, 26.0f * s);
            FillRoundRect(
                g, clearBtn, 6.5f * s,
                st->hoveredRegion == HitRegion::BtnClearTestEdit
                    ? (isDark ? Color(255, 58, 58, 76) : Color(255, 232, 234, 244))
                    : (isDark ? Color(255, 46, 46, 60) : Color(255, 242, 242, 247))
            );
            DrawRoundRect(g, clearBtn, 6.5f * s, isDark ? Color(255, 70, 70, 88) : Color(255, 220, 220, 228), 1.0f * s);
            g.DrawString(L"Xo\u00E1 th\u1EED", -1, &fPill, clearBtn, &sfCenter, &secondaryBrush);
        } else {
            // =================================================================
            // TAB 1: THÔNG TIN (Bố cục ngang chữ nhật 680x424, rộng 640px)
            // =================================================================
            SolidBrush indigoBrush(indigoCol);
            SolidBrush tealBrush(tealCol);
            SolidBrush whiteTextBrush(Color(255, 255, 255, 255));

            // Hàng 1: SỨ MỆNH SEN VIỆT (x=20, y=68, w=640, h=88)
            DrawCard(g, RectF(20.0f * s, 68.0f * s, 640.0f * s, 88.0f * s), 10.0f * s, cardCol, cardBorderCol);
            g.DrawString(
                L"\u2726 S\u1EE8 M\u1EC6NH SEN VI\u1EC6T",
                -1, &fSecHdr, RectF(34.0f * s, 77.0f * s, 220.0f * s, 18.0f * s), &sfLeft, &indigoBrush
            );
            g.DrawString(
                L"Windows TSF Native \u2022 100% Offline \u2022 An to\u00E0n tuy\u1EC7t \u0111\u1ED1i",
                -1, &fSub, RectF(280.0f * s, 77.0f * s, 366.0f * s, 18.0f * s), &sfRight, &secondaryBrush
            );
            g.DrawString(
                L"\"H\u00E3y \u0111\u1EC3 vi\u1EC7c g\u00F5 l\u00E0 g\u00F5 \u2014 d\u00F9 b\u1EA1n g\u00F5 ti\u1EBFng Vi\u1EC7t hay ti\u1EBFng Anh; nhanh hay ch\u1EADm; g\u00F5 l\u00E0 Sen Vi\u1EC7t.\"",
                -1, &fTileTitle, RectF(34.0f * s, 102.0f * s, 612.0f * s, 44.0f * s), &sfWrap, &primaryBrush
            );

            // Hàng 2 (2 Thẻ ngang song song): Hệ sinh thái AI (NidoOffice | YouPersona.com) (y=168, h=104)
            DrawCard(
                g, RectF(20.0f * s, 168.0f * s, 314.0f * s, 104.0f * s), 10.0f * s,
                st->hoveredRegion == HitRegion::BtnNidoOfficeExplore
                    ? (isDark ? Color(255, 44, 46, 66) : Color(255, 246, 247, 255))
                    : cardCol,
                Color(120, indigoCol.GetR(), indigoCol.GetG(), indigoCol.GetB()), 1.1f * s
            );
            g.DrawString(
                L"NidoOffice",
                -1, &fTileTitle, RectF(34.0f * s, 180.0f * s, 90.0f * s, 20.0f * s), &sfLeft, &primaryBrush
            );
            RectF nidoBadge(124.0f * s, 181.0f * s, 114.0f * s, 18.0f * s);
            FillRoundRect(g, nidoBadge, 9.0f * s, Color(isDark ? 55 : 36, indigoCol.GetR(), indigoCol.GetG(), indigoCol.GetB()));
            g.DrawString(L"EDUCENTER.APP", -1, &fPill, nidoBadge, &sfCenter, &indigoBrush);
            g.DrawString(
                L"So\u1EA1n th\u1EA3o T\u00E0i li\u1EC7u, Trang tr\u00ECnh b\u00E0y & B\u1EA3ng t\u00EDnh t\u00EDch h\u1EE3p AI",
                -1, &fSub, RectF(34.0f * s, 210.0f * s, 286.0f * s, 46.0f * s), &sfWrap, &secondaryBrush
            );
            RectF nidoCta(260.0f * s, 179.0f * s, 60.0f * s, 22.0f * s);
            FillRoundRect(g, nidoCta, 11.0f * s, Color(255, 88, 86, 214));
            g.DrawString(L"M\u1EDF \u2197", -1, &fPill, nidoCta, &sfCenter, &whiteTextBrush);

            DrawCard(
                g, RectF(346.0f * s, 168.0f * s, 314.0f * s, 104.0f * s), 10.0f * s,
                st->hoveredRegion == HitRegion::BtnYouPersonaExplore
                    ? (isDark ? Color(255, 36, 52, 54) : Color(255, 243, 252, 251))
                    : cardCol,
                Color(120, tealCol.GetR(), tealCol.GetG(), tealCol.GetB()), 1.1f * s
            );
            g.DrawString(
                L"YouPersona.com",
                -1, &fTileTitle, RectF(360.0f * s, 180.0f * s, 122.0f * s, 20.0f * s), &sfLeft, &primaryBrush
            );
            RectF ypBadge(484.0f * s, 181.0f * s, 86.0f * s, 18.0f * s);
            FillRoundRect(g, ypBadge, 9.0f * s, Color(isDark ? 55 : 36, tealCol.GetR(), tealCol.GetG(), tealCol.GetB()));
            g.DrawString(L"THU CHI AI", -1, &fPill, ypBadge, &sfCenter, &tealBrush);
            g.DrawString(
                L"Qu\u1EA3n l\u00FD T\u00E0i ch\u00EDnh c\u00E1 nh\u00E2n & Ng\u00E2n s\u00E1ch 6 chi\u1EBFc l\u1ECD b\u1EB1ng AI",
                -1, &fSub, RectF(360.0f * s, 210.0f * s, 286.0f * s, 46.0f * s), &sfWrap, &secondaryBrush
            );
            RectF ypCta(586.0f * s, 179.0f * s, 60.0f * s, 22.0f * s);
            FillRoundRect(g, ypCta, 11.0f * s, Color(255, 13, 148, 136));
            g.DrawString(L"M\u1EDF \u2197", -1, &fPill, ypCta, &sfCenter, &whiteTextBrush);

            // Hàng 3: Góp ý, Cộng đồng & Mã nguồn (x=20, y=284, w=640, h=64)
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

            drawLinkBtn(32.0f, 146.0f, L"G\u00F3p \u00FD & B\u00E1o l\u1ED7i", st->hoveredRegion == HitRegion::RowFeedback, true);
            drawLinkBtn(188.0f, 146.0f, L"C\u1ED9ng \u0111\u1ED3ng Zalo \u2197", st->hoveredRegion == HitRegion::RowZalo, false);
            drawLinkBtn(344.0f, 146.0f, L"Tr\u1EA7n Ph\u00E1t \u0110\u1EA1t \u2197", st->hoveredRegion == HitRegion::RowLinkedIn, false);
            drawLinkBtn(500.0f, 148.0f, L"M\u00E3 ngu\u1ED3n GitHub \u2197", st->hoveredRegion == HitRegion::RowGitHub, false);
        }

        // 3. Bottom Footer Bar (384..424, height=40)
        g.FillRectangle(&barBrush, 0.0f, 384.0f * s, static_cast<float>(width), 40.0f * s);
        g.DrawLine(&divPen, 0.0f, 384.0f * s, static_cast<float>(width), 384.0f * s);

        SolidBrush greenDotBrush(Color(255, 34, 197, 94));
        SolidBrush indigoFooterBrush(indigoCol);
        g.FillEllipse(&greenDotBrush, RectF(20.0f * s, 401.0f * s, 6.5f * s, 6.5f * s));
        g.DrawString(
            L"Song ng\u1EEF Anh\u2013Vi\u1EC7t \u2022 Ch\u00EDnh t\u1EA3 chu\u1EA9n m\u1EDBi t\u1EF1 \u0111\u1ED9ng",
            -1, &fFooter, RectF(32.0f * s, 384.0f * s, 296.0f * s, 40.0f * s), &sfLeft, &secondaryBrush
        );

        // Prominent "Góp ý & Báo lỗi" pill button in footer (opens native Feedback sheet)
        RectF fbPill(336.0f * s, 391.0f * s, 118.0f * s, 26.0f * s);
        FillRoundRect(
            g, fbPill, 13.0f * s,
            st->hoveredRegion == HitRegion::FooterFeedback
                ? Color(isDark ? 85 : 55, blueCol.GetR(), blueCol.GetG(), blueCol.GetB())
                : Color(isDark ? 55 : 32, blueCol.GetR(), blueCol.GetG(), blueCol.GetB())
        );
        DrawRoundRect(g, fbPill, 13.0f * s, Color(140, blueCol.GetR(), blueCol.GetG(), blueCol.GetB()), 1.0f * s);
        g.DrawString(L"G\u00F3p \u00FD & B\u00E1o l\u1ED7i", -1, &fFooterBold, fbPill, &sfCenter, &blueBrush);

        g.DrawString(L"NidoOffice", -1, &fFooterBold, RectF(462.0f * s, 384.0f * s, 68.0f * s, 40.0f * s), &sfCenter, &indigoFooterBrush);
        g.DrawString(L"\u2022", -1, &fFooter, RectF(530.0f * s, 384.0f * s, 8.0f * s, 40.0f * s), &sfCenter, &secondaryBrush);
        g.DrawString(L"YouPersona.com", -1, &fFooterBold, RectF(538.0f * s, 384.0f * s, 88.0f * s, 40.0f * s), &sfCenter, &blueBrush);
        g.DrawString(L"\u2022", -1, &fFooter, RectF(626.0f * s, 384.0f * s, 6.0f * s, 40.0f * s), &sfCenter, &secondaryBrush);
        g.DrawString(L"GitHub", -1, &fFooter, RectF(632.0f * s, 384.0f * s, 38.0f * s, 40.0f * s), &sfCenter, &secondaryBrush);
    }

    BitBlt(hdc, 0, 0, width, height, memDC, 0, 0, SRCCOPY);
    SelectObject(memDC, oldBmp);
    DeleteObject(memBmp);
    DeleteDC(memDC);
}

enum {
    WM_VIELOTUS_ACTIVATE_PROFILES = WM_USER + 100,
    WM_VIELOTUS_SHOW_SETTINGS     = WM_USER + 101,
    WM_VIELOTUS_QUIT_TRAY         = WM_USER + 199,
    WM_VIELOTUS_TRAY_CALLBACK     = WM_USER + 200,

    IDM_TRAY_TELEX                = 2901,
    IDM_TRAY_VNI                  = 2902,
    IDM_TRAY_SENFLEX              = 2903,
    IDM_TRAY_MACRO                = 2904,
    IDM_TRAY_START_WITH_WIN       = 2905,
    IDM_TRAY_OPEN_SETTINGS        = 2906,
    IDM_TRAY_FEEDBACK             = 2907,
    IDM_TRAY_EXIT                 = 2909
};

static void UpdateTrayIconState(HWND hwnd, BentoSettingsState *st) {
    if (!hwnd || !st) return;
    st->nid.cbSize = sizeof(NOTIFYICONDATAW);
    st->nid.hWnd = hwnd;
    st->nid.uID = 1;
    st->nid.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
    st->nid.uCallbackMessage = WM_VIELOTUS_TRAY_CALLBACK;
    st->nid.hIcon = st->hWndIconSmall ? st->hWndIconSmall
                                      : (st->hWndIconBig ? st->hWndIconBig : LoadEmbeddedAppIcon(16, 16));
    StringCchPrintfW(
        st->nid.szTip,
        ARRAYSIZE(st->nid.szTip),
        L"Sen Vi\u1EC7t (VieLotusIM) \u2014 %s%s",
        st->prefs.isVni ? L"Chu\u1EA9n VNI" : L"Chu\u1EA9n Telex",
        st->prefs.senFlex ? L" \u2022 D\u1EA5u tr\u01B0\u1EDBc \u00E2m" : L""
    );
    if (st->trayRegistered) {
        Shell_NotifyIconW(NIM_MODIFY, &st->nid);
    } else {
        st->trayRegistered = (Shell_NotifyIconW(NIM_ADD, &st->nid) != FALSE);
    }
}

static void RemoveTrayIconState(BentoSettingsState *st) {
    if (st && st->trayRegistered) {
        Shell_NotifyIconW(NIM_DELETE, &st->nid);
        st->trayRegistered = false;
    }
}

static void ShowTrayContextMenu(HWND hwnd, BentoSettingsState *st) {
    if (!hwnd || !st) return;
    LoadVieLotusPrefs(st->prefs);

    HMENU hMenu = CreatePopupMenu();
    if (!hMenu) return;

    AppendMenuW(
        hMenu,
        MF_STRING | (!st->prefs.isVni ? MF_CHECKED : MF_UNCHECKED),
        IDM_TRAY_TELEX,
        L"Chu\u1EA9n Telex (M\u1EB7c \u0111\u1ECBnh)"
    );
    AppendMenuW(
        hMenu,
        MF_STRING | (st->prefs.isVni ? MF_CHECKED : MF_UNCHECKED),
        IDM_TRAY_VNI,
        L"Chu\u1EA9n VNI (Ph\u00EDm s\u1ED1 1\u20139)"
    );
    AppendMenuW(hMenu, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(
        hMenu,
        MF_STRING | (st->prefs.senFlex ? MF_CHECKED : MF_UNCHECKED),
        IDM_TRAY_SENFLEX,
        L"Cho ph\u00E9p g\u00F5 d\u1EA5u tr\u01B0\u1EDBc \u00E2m (dducj \u2192 \u0111\u1EE5c)"
    );
    AppendMenuW(
        hMenu,
        MF_STRING | (st->prefs.macroEnabled ? MF_CHECKED : MF_UNCHECKED),
        IDM_TRAY_MACRO,
        L"B\u1EA3ng g\u00F5 t\u1EAFt (Macro)"
    );
    AppendMenuW(
        hMenu,
        MF_STRING | (st->prefs.startWithWindows ? MF_CHECKED : MF_UNCHECKED),
        IDM_TRAY_START_WITH_WIN,
        L"Kh\u1EDFi \u0111\u1ED9ng c\u00F9ng Windows"
    );
    AppendMenuW(hMenu, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(hMenu, MF_STRING, IDM_TRAY_OPEN_SETTINGS, L"M\u1EDF B\u1EA3ng \u0110i\u1EC1u Khi\u1EC3n Sen Vi\u1EC7t...");
    AppendMenuW(hMenu, MF_STRING, IDM_TRAY_FEEDBACK, L"G\u00F3p \u00FD & B\u00E1o l\u1ED7i nhanh...");
    AppendMenuW(hMenu, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(hMenu, MF_STRING, IDM_TRAY_EXIT, L"Tho\u00E1t khay h\u1EC7 th\u1ED1ng");

    SetMenuDefaultItem(hMenu, IDM_TRAY_OPEN_SETTINGS, FALSE);

    POINT pt{};
    GetCursorPos(&pt);
    SetForegroundWindow(hwnd);
    UINT cmd = TrackPopupMenu(
        hMenu,
        TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON | TPM_BOTTOMALIGN,
        pt.x, pt.y, 0, hwnd, nullptr
    );
    PostMessageW(hwnd, WM_NULL, 0, 0);
    DestroyMenu(hMenu);

    switch (cmd) {
    case IDM_TRAY_TELEX:
        st->prefs.isVni = false;
        SaveVieLotusPrefs(st->prefs);
        ActivateUserProfiles();
        UpdateTrayIconState(hwnd, st);
        InvalidateRect(hwnd, nullptr, FALSE);
        break;
    case IDM_TRAY_VNI:
        st->prefs.isVni = true;
        SaveVieLotusPrefs(st->prefs);
        ActivateUserProfiles();
        UpdateTrayIconState(hwnd, st);
        InvalidateRect(hwnd, nullptr, FALSE);
        break;
    case IDM_TRAY_SENFLEX:
        st->prefs.senFlex = !st->prefs.senFlex;
        SaveVieLotusPrefs(st->prefs);
        UpdateTrayIconState(hwnd, st);
        InvalidateRect(hwnd, nullptr, FALSE);
        break;
    case IDM_TRAY_MACRO:
        st->prefs.macroEnabled = !st->prefs.macroEnabled;
        SaveVieLotusPrefs(st->prefs);
        InvalidateRect(hwnd, nullptr, FALSE);
        break;
    case IDM_TRAY_START_WITH_WIN:
        st->prefs.startWithWindows = !st->prefs.startWithWindows;
        SaveVieLotusPrefs(st->prefs);
        InvalidateRect(hwnd, nullptr, FALSE);
        break;
    case IDM_TRAY_OPEN_SETTINGS:
        ShowWindow(hwnd, SW_SHOW);
        ShowWindow(hwnd, SW_RESTORE);
        SetForegroundWindow(hwnd);
        ActivateUserProfiles();
        if (st->hTestEdit && st->selectedTab == 0) SetFocus(st->hTestEdit);
        break;
    case IDM_TRAY_FEEDBACK:
        ShowVieLotusFeedbackDialog(hwnd, st->prefs);
        break;
    case IDM_TRAY_EXIT:
        RemoveTrayIconState(st);
        DestroyWindow(hwnd);
        break;
    default:
        break;
    }
}

static void OpenMacroJsonInNotepad(HWND hwnd) {
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
}

// ============================================================================
// Native Win32/GDI+ Feedback & Bug Report Dialog (Matches macOS FeedbackView)
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
        L"Sen Vi\u1EC7t v2.0.2 \u2022 Windows %s (Build %lu, %s) \u2022 %s \u2022 D\u1EA5u tr\u01B0\u1EDBc \u00E2m: %s \u2022 G\u00F5 t\u1EAFt: %s",
        (buildNum >= 22000) ? L"11" : L"10",
        static_cast<unsigned long>(buildNum),
        arch,
        prefs.isVni ? L"Chu\u1EA9n VNI" : L"Chu\u1EA9n Telex",
        prefs.senFlex ? L"B\u1EACT" : L"T\u1EAET",
        prefs.macroEnabled ? L"B\u1EACT" : L"T\u1EAET"
    );
    return std::wstring(summary);
}

static std::wstring BuildFeedbackReportMarkdown(FeedbackDialogState *st) {
    if (!st) return L"";
    const wchar_t *catNames[4] = {
        L"L\u1ED7i g\u00F5 t\u1EEB / Song ng\u1EEF",
        L"T\u01B0\u01A1ng th\u00EDch App / Web",
        L"\u0110\u1EC1 xu\u1EA5t t\u00EDnh n\u0103ng",
        L"G\u00F3p \u00FD chung"
    };
    int catIdx = (st->category >= 0 && st->category < 4) ? st->category : 0;

    std::wstring raw = GetEditControlText(st->hEditRaw);
    std::wstring actual = GetEditControlText(st->hEditActual);
    std::wstring expected = GetEditControlText(st->hEditExpected);
    std::wstring app = GetEditControlText(st->hEditApp);
    std::wstring contact = GetEditControlText(st->hEditContact);
    std::wstring notes = GetEditControlText(st->hEditNotes);

    std::wstring md = L"### [Sen Vi\u1EC7t Windows] ";
    md += catNames[catIdx];
    md += L"\r\n\r\n";

    if (!raw.empty() || !actual.empty() || !expected.empty()) {
        md += L"- **Ph\u00EDm \u0111\u00E3 g\u00F5 (Raw):** `" + (raw.empty() ? L"(tr\u1ED1ng)" : raw) + L"`\r\n";
        md += L"- **Sen Vi\u1EC7t hi\u1EC7n ra:** `" + (actual.empty() ? L"(tr\u1ED1ng)" : actual) + L"`\r\n";
        md += L"- **Mong mu\u1ED1n \u0111\u00FAng:** `" + (expected.empty() ? L"(tr\u1ED1ng)" : expected) + L"`\r\n";
    }
    if (!app.empty()) {
        md += L"- **\u1EE8ng d\u1EE5ng / Ch\u1EE7 \u0111\u1EC1:** " + app + L"\r\n";
    }
    if (!contact.empty()) {
        md += L"- **Li\u00EAn h\u1EC7 ph\u1EA3n h\u1ED3i:** " + contact + L"\r\n";
    }
    if (!notes.empty()) {
        md += L"\r\n**M\u00F4 t\u1EA3 chi ti\u1EBFt:**\r\n" + notes + L"\r\n";
    }
    if (st->includeDiagnostics) {
        md += L"\r\n---\r\n**C\u1EA5u h\u00ECnh k\u1EF9 thu\u1EADt:** `" + GetWindowsDiagnosticsSummary(st->prefs) + L"`\r\n";
    }
    return md;
}

static std::wstring BuildFeedbackIssueTitle(FeedbackDialogState *st) {
    if (!st) return L"[Windows] G\u00F3p \u00FD Sen Vi\u1EC7t";
    const wchar_t *catShort[4] = {
        L"[Windows][L\u1ED7i g\u00F5 t\u1EEB] ",
        L"[Windows][T\u01B0\u01A1ng th\u00EDch App] ",
        L"[Windows][\u0110\u1EC1 xu\u1EA5t] ",
        L"[Windows][G\u00F3p \u00FD] "
    };
    int catIdx = (st->category >= 0 && st->category < 4) ? st->category : 0;
    std::wstring raw = GetEditControlText(st->hEditRaw);
    std::wstring expected = GetEditControlText(st->hEditExpected);
    std::wstring app = GetEditControlText(st->hEditApp);

    std::wstring title = catShort[catIdx];
    if (!raw.empty() && !expected.empty()) {
        title += L"G\u00F5 '" + raw + L"' mong mu\u1ED1n '" + expected + L"'";
    } else if (!app.empty()) {
        title += app;
    } else {
        title += L"B\u00E1o c\u00E1o t\u1EEB ng\u01B0\u1EDDi d\u00F9ng Sen Vi\u1EC7t v2.0.2";
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

        // Header
        RectF iconRect(20.0f * s, 14.0f * s, 34.0f * s, 34.0f * s);
        if (st->pAppIcon && st->pAppIcon->GetLastStatus() == Ok) {
            g.SetInterpolationMode(InterpolationModeHighQualityBicubic);
            g.DrawImage(st->pAppIcon, iconRect);
        } else {
            FillRoundRect(g, iconRect, 8.0f * s, Color(255, 232, 93, 117));
            g.DrawString(L"SV", -1, &fCatTitle, iconRect, &sfCenter, &whiteBrush);
        }

        g.DrawString(L"G\u00F3p \u00FD & B\u00E1o l\u1ED7i nhanh", -1, &fTitle, RectF(62.0f * s, 12.0f * s, 480.0f * s, 20.0f * s), &sfLeft, &primaryBrush);
        g.DrawString(
            L"\u00DD ki\u1EBFn c\u1EE7a b\u1EA1n gi\u00FAp Sen Vi\u1EC7t ho\u00E0n thi\u1EC7n m\u1ED7i ng\u00E0y \u2014 g\u1EEDi b\u00E1o c\u00E1o trong 10 gi\u00E2y.",
            -1, &fSub, RectF(62.0f * s, 32.0f * s, 490.0f * s, 18.0f * s), &sfLeft, &secondaryBrush
        );

        RectF closeRect(560.0f * s, 16.0f * s, 60.0f * s, 28.0f * s);
        FillRoundRect(g, closeRect, 8.0f * s, st->hovered == FeedbackHit::BtnClose ? cardHoverBg : cardBg);
        DrawRoundRect(g, closeRect, 8.0f * s, cardBorder, 1.0f * s);
        g.DrawString(L"\u0110\u00F3ng", -1, &fLabel, closeRect, &sfCenter, &primaryBrush);

        // 4 Category Cards
        const wchar_t *catTitles[4] = {
            L"L\u1ED7i g\u00F5 t\u1EEB / Song ng\u1EEF",
            L"T\u01B0\u01A1ng th\u00EDch App / Web",
            L"\u0110\u1EC1 xu\u1EA5t t\u00EDnh n\u0103ng",
            L"G\u00F3p \u00FD chung"
        };
        const wchar_t *catSubs[4] = {
            L"Sai d\u1EA5u, kh\u00F4i ph\u1EE5c t\u1EEB",
            L"Nh\u1EA3y con tr\u1ECF, l\u1EB7p ch\u1EEF",
            L"\u00DD t\u01B0\u1EDFng, ph\u00EDm t\u1EAFt, t\u1EEB \u0111i\u1EC3n",
            L"C\u1EA3m nh\u1EADn & h\u1ED7 tr\u1EE3"
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
            g.DrawString(catTitles[i], -1, &fCatTitle, RectF(cx + 8.0f * s, 65.0f * s, 128.0f * s, 18.0f * s), &sfLeft, sel ? &blueBrush : &primaryBrush);
            g.DrawString(catSubs[i], -1, &fCatSub, RectF(cx + 8.0f * s, 84.0f * s, 128.0f * s, 16.0f * s), &sfLeft, &secondaryBrush);
        }

        // Row 1: 3 Word Input Fields
        g.DrawString(L"1. Ph\u00EDm \u0111\u00E3 g\u00F5 (Raw):", -1, &fLabel, RectF(20.0f * s, 114.0f * s, 194.0f * s, 18.0f * s), &sfLeft, &primaryBrush);
        FillRoundRect(g, RectF(20.0f * s, 134.0f * s, 194.0f * s, 32.0f * s), 7.0f * s, cardBg);
        DrawRoundRect(g, RectF(20.0f * s, 134.0f * s, 194.0f * s, 32.0f * s), 7.0f * s, cardBorder, 1.0f * s);

        g.DrawString(L"2. Sen Vi\u1EC7t hi\u1EC7n ra:", -1, &fLabel, RectF(223.0f * s, 114.0f * s, 194.0f * s, 18.0f * s), &sfLeft, &primaryBrush);
        FillRoundRect(g, RectF(223.0f * s, 134.0f * s, 194.0f * s, 32.0f * s), 7.0f * s, cardBg);
        DrawRoundRect(g, RectF(223.0f * s, 134.0f * s, 194.0f * s, 32.0f * s), 7.0f * s, cardBorder, 1.0f * s);

        g.DrawString(L"3. Mong mu\u1ED1n \u0111\u00FAng:", -1, &fLabel, RectF(426.0f * s, 114.0f * s, 194.0f * s, 18.0f * s), &sfLeft, &primaryBrush);
        FillRoundRect(g, RectF(426.0f * s, 134.0f * s, 194.0f * s, 32.0f * s), 7.0f * s, cardBg);
        DrawRoundRect(g, RectF(426.0f * s, 134.0f * s, 194.0f * s, 32.0f * s), 7.0f * s, cardBorder, 1.0f * s);

        // Row 2: App/Topic & Contact
        g.DrawString(L"\u1EE8ng d\u1EE5ng / Tr\u00ECnh duy\u1EC7t g\u1EB7p l\u1ED7i (ho\u1EB7c Ch\u1EE7 \u0111\u1EC1):", -1, &fLabel, RectF(20.0f * s, 174.0f * s, 295.0f * s, 18.0f * s), &sfLeft, &primaryBrush);
        FillRoundRect(g, RectF(20.0f * s, 194.0f * s, 295.0f * s, 32.0f * s), 7.0f * s, cardBg);
        DrawRoundRect(g, RectF(20.0f * s, 194.0f * s, 295.0f * s, 32.0f * s), 7.0f * s, cardBorder, 1.0f * s);

        g.DrawString(L"Email / S\u0110T Zalo li\u00EAn h\u1EC7 (Tu\u1EF3 ch\u1ECDn \u2014 nh\u1EADn ph\u1EA3n h\u1ED3i):", -1, &fLabel, RectF(325.0f * s, 174.0f * s, 295.0f * s, 18.0f * s), &sfLeft, &primaryBrush);
        FillRoundRect(g, RectF(325.0f * s, 194.0f * s, 295.0f * s, 32.0f * s), 7.0f * s, cardBg);
        DrawRoundRect(g, RectF(325.0f * s, 194.0f * s, 295.0f * s, 32.0f * s), 7.0f * s, cardBorder, 1.0f * s);

        // Row 3: Multiline Notes
        g.DrawString(L"M\u00F4 t\u1EA3 chi ti\u1EBFt / C\u00E1c b\u01B0\u1EDBc t\u00E1i hi\u1EC7n:", -1, &fLabel, RectF(20.0f * s, 232.0f * s, 600.0f * s, 18.0f * s), &sfLeft, &primaryBrush);
        FillRoundRect(g, RectF(20.0f * s, 252.0f * s, 600.0f * s, 94.0f * s), 7.0f * s, cardBg);
        DrawRoundRect(g, RectF(20.0f * s, 252.0f * s, 600.0f * s, 94.0f * s), 7.0f * s, cardBorder, 1.0f * s);

        // Row 4: Diagnostic toggle bar
        RectF diagRect(20.0f * s, 354.0f * s, 600.0f * s, 40.0f * s);
        FillRoundRect(g, diagRect, 8.0f * s, st->hovered == FeedbackHit::BarDiagToggle ? cardHoverBg : cardBg);
        DrawRoundRect(g, diagRect, 8.0f * s, cardBorder, 1.0f * s);
        g.DrawString(
            L"\u0110\u00EDnh k\u00E8m c\u1EA5u h\u00ECnh k\u1EF9 thu\u1EADt (phi\u00EAn b\u1EA3n Windows, CPU, ki\u1EC3u g\u00F5 \u2014 kh\u00F4ng ch\u1EE9a d\u1EEF li\u1EC7u c\u00E1 nh\u00E2n)",
            -1, &fLabel, RectF(32.0f * s, 356.0f * s, 520.0f * s, 18.0f * s), &sfLeft, &primaryBrush
        );
        std::wstring diagStr = GetWindowsDiagnosticsSummary(st->prefs);
        g.DrawString(diagStr.c_str(), -1, &fCatSub, RectF(32.0f * s, 374.0f * s, 520.0f * s, 16.0f * s), &sfLeft, &secondaryBrush);
        {
            float swW = 36.0f, swH = 20.0f, swX = 568.0f, swY = 364.0f;
            RectF swTrack(swX * s, swY * s, swW * s, swH * s);
            Color trackCol = st->includeDiagnostics ? greenCol : (isDark ? Color(255, 68, 68, 84) : Color(255, 212, 212, 220));
            FillRoundRect(g, swTrack, 10.0f * s, trackCol);
            float knobD = 16.0f;
            float knobX = st->includeDiagnostics ? (swX + swW - knobD - 2.0f) : (swX + 2.0f);
            g.FillEllipse(&whiteBrush, RectF(knobX * s, (swY + 2.0f) * s, knobD * s, knobD * s));
        }

        // Status / Hint line
        if (st->copiedBanner) {
            g.DrawString(
                L"\u2713 \u0110\u00E3 sao ch\u00E9p b\u00E1o c\u00E1o v\u00E0o Clipboard! B\u1EA1n c\u00F3 th\u1EC3 d\u00E1n (Ctrl+V) ngay v\u00E0o Zalo / Email / GitHub.",
                -1, &fLabel, RectF(20.0f * s, 398.0f * s, 600.0f * s, 20.0f * s), &sfLeft, &greenBrush
            );
        } else {
            g.DrawString(
                L"M\u1EB9o: Khi b\u1EA5m Zalo / Email / GitHub, n\u1ED9i dung b\u00E1o c\u00E1o c\u0169ng t\u1EF1 \u0111\u1ED9ng \u0111\u01B0\u1EE3c sao ch\u00E9p v\u00E0o Clipboard.",
                -1, &fCatSub, RectF(20.0f * s, 398.0f * s, 600.0f * s, 20.0f * s), &sfLeft, &secondaryBrush
            );
        }

        // 4 Action Buttons
        RectF bCopy(20.0f * s, 422.0f * s, 138.0f * s, 34.0f * s);
        FillRoundRect(g, bCopy, 8.0f * s, st->hovered == FeedbackHit::BtnCopyReport ? cardHoverBg : cardBg);
        DrawRoundRect(g, bCopy, 8.0f * s, cardBorder, 1.0f * s);
        g.DrawString(L"Sao ch\u00E9p B\u00E1o c\u00E1o", -1, &fBtn, bCopy, &sfCenter, &primaryBrush);

        RectF bZalo(166.0f * s, 422.0f * s, 144.0f * s, 34.0f * s);
        FillRoundRect(g, bZalo, 8.0f * s, st->hovered == FeedbackHit::BtnOpenZalo ? cardHoverBg : cardBg);
        DrawRoundRect(g, bZalo, 8.0f * s, Color(140, blueCol.GetR(), blueCol.GetG(), blueCol.GetB()), 1.0f * s);
        g.DrawString(L"Nh\u00F3m Zalo H\u1ED7 tr\u1EE3 \u2197", -1, &fBtn, bZalo, &sfCenter, &blueBrush);

        RectF bEmail(318.0f * s, 422.0f * s, 138.0f * s, 34.0f * s);
        FillRoundRect(g, bEmail, 8.0f * s, st->hovered == FeedbackHit::BtnSendEmail ? cardHoverBg : cardBg);
        DrawRoundRect(g, bEmail, 8.0f * s, cardBorder, 1.0f * s);
        g.DrawString(L"G\u1EEDi qua Email \u2197", -1, &fBtn, bEmail, &sfCenter, &primaryBrush);

        RectF bIssue(464.0f * s, 422.0f * s, 156.0f * s, 34.0f * s);
        FillRoundRect(
            g, bIssue, 8.0f * s,
            st->hovered == FeedbackHit::BtnCreateIssue ? Color(255, 0, 112, 235) : blueCol
        );
        g.DrawString(L"T\u1EA1o GitHub Issue \u2197", -1, &fBtn, bIssue, &sfCenter, &whiteBrush);
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

        DWORD cornerPref = 2; // DWMWCP_ROUND
        DwmSetWindowAttribute(hwnd, DWMWA_WINDOW_CORNER_PREFERENCE, &cornerPref, sizeof(cornerPref));
        BOOL darkTitle = st->isDark ? TRUE : FALSE;
        DwmSetWindowAttribute(hwnd, 20, &darkTitle, sizeof(darkTitle));

        float s = st->dpiScale;
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
                hwnd, reinterpret_cast<HMENU>(static_cast<INT_PTR>(id)), g_hInst, nullptr
            );
            if (hEd) {
                if (st->hEditFont) SendMessageW(hEd, WM_SETFONT, reinterpret_cast<WPARAM>(st->hEditFont), TRUE);
                if (cue && cue[0]) SendMessageW(hEd, 0x1501 /* EM_SETCUEBANNER */, TRUE, reinterpret_cast<LPARAM>(cue));
            }
            return hEd;
        };

        st->hEditRaw      = createField(26, 141, 182, 20, 2101, L"VD: truowngr, 12haf...");
        st->hEditActual   = createField(229, 141, 182, 20, 2102, L"VD: truowngr, 12haf...");
        st->hEditExpected = createField(432, 141, 182, 20, 2103, L"VD: tr\u01B0\u1EDFng, 12h\u00E0...");
        st->hEditApp      = createField(26, 201, 283, 20, 2104, L"VD: Chrome, Zalo PC, Word, VS Code...");
        st->hEditContact  = createField(331, 201, 283, 20, 2105, L"Email ho\u1EB7c S\u0110T Zalo (\u0111\u1EC3 nh\u1EADn ph\u1EA3n h\u1ED3i)...");
        st->hEditNotes    = createField(
            26, 258, 588, 82, 2106,
            L"M\u00F4 t\u1EA3 th\u00EAm t\u00ECnh hu\u1ED1ng g\u1EB7p l\u1ED7i ho\u1EB7c \u00FD t\u01B0\u1EDFng c\u1EA3i ti\u1EBFn c\u1EE7a b\u1EA1n...",
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
            std::wstring md = BuildFeedbackReportMarkdown(st);
            CopyWideTextToClipboard(hwnd, md);
            st->copiedBanner = true;
            InvalidateRect(hwnd, nullptr, FALSE);
            break;
        }
        case FeedbackHit::BtnOpenZalo: {
            std::wstring md = BuildFeedbackReportMarkdown(st);
            CopyWideTextToClipboard(hwnd, md);
            st->copiedBanner = true;
            InvalidateRect(hwnd, nullptr, FALSE);
            ShellExecuteW(hwnd, L"open", L"https://zalo.me/g/6wwyvywyvhsb0n6rwkze", nullptr, nullptr, SW_SHOWNORMAL);
            break;
        }
        case FeedbackHit::BtnSendEmail: {
            std::wstring md = BuildFeedbackReportMarkdown(st);
            std::wstring title = BuildFeedbackIssueTitle(st);
            CopyWideTextToClipboard(hwnd, md);
            st->copiedBanner = true;
            InvalidateRect(hwnd, nullptr, FALSE);
            std::wstring mailto = L"mailto:support@vielotus.org?subject=" +
                                  UrlEncodeWideToUtf8W(title) +
                                  L"&body=" +
                                  UrlEncodeWideToUtf8W(md);
            ShellExecuteW(hwnd, L"open", mailto.c_str(), nullptr, nullptr, SW_SHOWNORMAL);
            break;
        }
        case FeedbackHit::BtnCreateIssue: {
            std::wstring md = BuildFeedbackReportMarkdown(st);
            std::wstring title = BuildFeedbackIssueTitle(st);
            CopyWideTextToClipboard(hwnd, md);
            st->copiedBanner = true;
            InvalidateRect(hwnd, nullptr, FALSE);
            std::wstring ghUrl = L"https://github.com/stevedat/VieLotus-IM/issues/new?title=" +
                                 UrlEncodeWideToUtf8W(title) +
                                 L"&body=" +
                                 UrlEncodeWideToUtf8W(md);
            ShellExecuteW(hwnd, L"open", ghUrl.c_str(), nullptr, nullptr, SW_SHOWNORMAL);
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

LRESULT CALLBACK VieLotusSettingsWndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    auto *st = reinterpret_cast<BentoSettingsState *>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));

    if (st && st->wmTaskbarCreated != 0 && msg == st->wmTaskbarCreated) {
        st->trayRegistered = false;
        UpdateTrayIconState(hwnd, st);
        return 0;
    }

    switch (msg) {
    case WM_CREATE: {
        CREATESTRUCTW *cs = reinterpret_cast<CREATESTRUCTW *>(lParam);
        st = new BentoSettingsState();
        if (cs && cs->lpCreateParams) {
            st->canHideToTrayOnClose = (*reinterpret_cast<const bool *>(cs->lpCreateParams));
        }
        SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(st));

        HDC hdc = GetDC(hwnd);
        int dpiY = GetDeviceCaps(hdc, LOGPIXELSY);
        ReleaseDC(hwnd, hdc);
        st->dpiScale = (dpiY > 0) ? (static_cast<float>(dpiY) / 96.0f) : 1.0f;
        st->isDark = IsWindowsDarkMode();
        st->wmTaskbarCreated = RegisterWindowMessageW(L"TaskbarCreated");

        LoadVieLotusPrefs(st->prefs);

        // 1. Load high-resolution PNG & ICO directly from embedded resources (102 & 101)
        st->pAppIcon = LoadEmbeddedPngImage(102);
        st->hWndIconBig = LoadEmbeddedAppIcon(32, 32);
        st->hWndIconSmall = LoadEmbeddedAppIcon(16, 16);

        // 2. Fallback to disk assets if needed
        std::wstring dir = GetDllDirPath();
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

        // Register Windows System Tray icon on taskbar notification area
        UpdateTrayIconState(hwnd, st);

        // Enable Windows 11 rounded window corners & Dark Mode titlebar via DWM
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
            hwnd, reinterpret_cast<HMENU>(static_cast<INT_PTR>(1001)), g_hInst, nullptr
        );
        if (st->hTestEdit) {
            if (st->hEditFont) {
                SendMessageW(st->hTestEdit, WM_SETFONT, reinterpret_cast<WPARAM>(st->hEditFont), TRUE);
            }
            // EM_SETCUEBANNER = 0x1501
            SendMessageW(
                st->hTestEdit, 0x1501, TRUE,
                reinterpret_cast<LPARAM>(L"G\u00F5 th\u1EED: truowngr \u2192 tr\u01B0\u1EDFng \u2022 12haf \u2192 12h\u00E0 \u2022 window user...")
            );
        }
        ActivateUserProfiles();
        if (st->hTestEdit) {
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

    case WM_VIELOTUS_ACTIVATE_PROFILES: {
        if (st) {
            LoadVieLotusPrefs(st->prefs);
            UpdateTrayIconState(hwnd, st);
            InvalidateRect(hwnd, nullptr, FALSE);
        }
        ActivateUserProfiles();
        if (st && st->hTestEdit && st->selectedTab == 0 && IsWindowVisible(hwnd)) {
            SetFocus(st->hTestEdit);
        }
        return 0;
    }

    case WM_VIELOTUS_SHOW_SETTINGS: {
        ShowWindow(hwnd, SW_SHOW);
        ShowWindow(hwnd, SW_RESTORE);
        SetForegroundWindow(hwnd);
        if (st) {
            LoadVieLotusPrefs(st->prefs);
            UpdateTrayIconState(hwnd, st);
            InvalidateRect(hwnd, nullptr, FALSE);
        }
        ActivateUserProfiles();
        if (st && st->hTestEdit && st->selectedTab == 0) {
            SetFocus(st->hTestEdit);
        }
        return 0;
    }

    case WM_VIELOTUS_QUIT_TRAY: {
        RemoveTrayIconState(st);
        DestroyWindow(hwnd);
        return 0;
    }

    case WM_VIELOTUS_TRAY_CALLBACK: {
        UINT mouseMsg = LOWORD(lParam);
        if (mouseMsg == WM_LBUTTONUP || mouseMsg == WM_LBUTTONDBLCLK) {
            ShowWindow(hwnd, SW_SHOW);
            ShowWindow(hwnd, SW_RESTORE);
            SetForegroundWindow(hwnd);
            if (st) {
                LoadVieLotusPrefs(st->prefs);
                UpdateTrayIconState(hwnd, st);
                InvalidateRect(hwnd, nullptr, FALSE);
                if (st->hTestEdit && st->selectedTab == 0) SetFocus(st->hTestEdit);
            }
        } else if (mouseMsg == WM_RBUTTONUP || mouseMsg == WM_CONTEXTMENU) {
            ShowTrayContextMenu(hwnd, st);
        }
        return 0;
    }

    case WM_ACTIVATE:
    case WM_INPUTLANGCHANGE:
    case WM_SETTINGCHANGE: {
        if (st) {
            bool oldVni = st->prefs.isVni;
            bool oldDark = st->isDark;
            LoadVieLotusPrefs(st->prefs);
            st->isDark = IsWindowsDarkMode();
            if (st->isDark != oldDark) {
                if (st->hEditBgBrush) DeleteObject(st->hEditBgBrush);
                st->hEditBgBrush = CreateSolidBrush(st->isDark ? RGB(35, 35, 46) : RGB(255, 255, 255));
                BOOL darkTitle = st->isDark ? TRUE : FALSE;
                DwmSetWindowAttribute(hwnd, 20, &darkTitle, sizeof(darkTitle));
            }
            UpdateTrayIconState(hwnd, st);
            if (st->prefs.isVni != oldVni || st->isDark != oldDark) {
                InvalidateRect(hwnd, nullptr, FALSE);
            }
        }
        break;
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
        case HitRegion::CardTelex:
            st->prefs.isVni = false;
            SaveVieLotusPrefs(st->prefs);
            ActivateUserProfiles();
            UpdateTrayIconState(hwnd, st);
            InvalidateRect(hwnd, nullptr, FALSE);
            if (st->hTestEdit) SetFocus(st->hTestEdit);
            break;
        case HitRegion::CardVni:
            st->prefs.isVni = true;
            SaveVieLotusPrefs(st->prefs);
            ActivateUserProfiles();
            UpdateTrayIconState(hwnd, st);
            InvalidateRect(hwnd, nullptr, FALSE);
            if (st->hTestEdit) SetFocus(st->hTestEdit);
            break;
        case HitRegion::BarSenFlex:
            st->prefs.senFlex = !st->prefs.senFlex;
            SaveVieLotusPrefs(st->prefs);
            UpdateTrayIconState(hwnd, st);
            InvalidateRect(hwnd, nullptr, FALSE);
            break;
        case HitRegion::TileMacroToggle:
            st->prefs.macroEnabled = !st->prefs.macroEnabled;
            SaveVieLotusPrefs(st->prefs);
            InvalidateRect(hwnd, nullptr, FALSE);
            break;
        case HitRegion::BtnMacroManage:
            OpenMacroJsonInNotepad(hwnd);
            break;
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
        case HitRegion::TileStartWithWin:
            st->prefs.startWithWindows = !st->prefs.startWithWindows;
            SaveVieLotusPrefs(st->prefs);
            InvalidateRect(hwnd, nullptr, FALSE);
            break;
        case HitRegion::BtnWinTypingSettings:
            ShellExecuteW(hwnd, L"open", L"ms-settings:typing", nullptr, nullptr, SW_SHOWNORMAL);
            break;
        case HitRegion::BtnClearTestEdit:
            if (st->hTestEdit) {
                SetWindowTextW(st->hTestEdit, L"");
                SetFocus(st->hTestEdit);
            }
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
        case HitRegion::RowFeedback:
        case HitRegion::FooterFeedback:
            ShowVieLotusFeedbackDialog(hwnd, st->prefs);
            break;
        default:
            break;
        }
        return 0;
    }

    case WM_KEYDOWN:
        if (wParam == VK_ESCAPE) {
            if (st && st->canHideToTrayOnClose && st->trayRegistered) {
                ShowWindow(hwnd, SW_HIDE);
            } else {
                DestroyWindow(hwnd);
            }
            return 0;
        }
        break;

    case WM_CLOSE:
        if (st && st->canHideToTrayOnClose && st->trayRegistered) {
            ShowWindow(hwnd, SW_HIDE);
        } else {
            DestroyWindow(hwnd);
        }
        return 0;

    case WM_DESTROY:
        if (st) {
            RemoveTrayIconState(st);
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

void ShowVieLotusFeedbackDialog(HWND hwndParent, const VieLotusWindowsPrefs &prefs) {
    static const WCHAR kFbClassName[] = L"VieLotusFeedbackDialogWndClass";
    HWND hExisting = FindWindowW(kFbClassName, nullptr);
    if (hExisting && IsWindow(hExisting)) {
        ShowWindow(hExisting, SW_SHOW);
        ShowWindow(hExisting, SW_RESTORE);
        SetForegroundWindow(hExisting);
        return;
    }

    WNDCLASSEXW wc{};
    wc.cbSize = sizeof(wc);
    wc.style = CS_HREDRAW | CS_VREDRAW;
    wc.lpfnWndProc = VieLotusFeedbackWndProc;
    wc.hInstance = g_hInst;
    wc.hIcon = LoadEmbeddedAppIcon(32, 32);
    wc.hIconSm = LoadEmbeddedAppIcon(16, 16);
    wc.hCursor = LoadCursorW(nullptr, MAKEINTRESOURCEW(32512)); // IDC_ARROW
    wc.hbrBackground = nullptr;
    wc.lpszClassName = kFbClassName;
    RegisterClassExW(&wc);

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

    HWND hwndFb = CreateWindowExW(
        dwExStyle,
        kFbClassName,
        L"G\u00F3p \u00FD & B\u00E1o l\u1ED7i \u2014 Sen Vi\u1EC7t (VieLotusIM)",
        dwStyle,
        posX, posY, wndW, wndH,
        hwndParent, nullptr, g_hInst, &fbState
    );
    if (hwndFb) {
        ShowWindow(hwndFb, SW_SHOW);
        UpdateWindow(hwndFb);
        SetForegroundWindow(hwndFb);

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

void ShowVieLotusSettingsDialog(HWND hwndParent, bool startHiddenInTray) {
    // If an instance of the settings/tray window is already running, reuse it
    static const WCHAR kWndClassName[] = L"VieLotusBentoSettingsWndClass";
    HWND hExisting = FindWindowW(kWndClassName, nullptr);
    if (hExisting && IsWindow(hExisting)) {
        if (!startHiddenInTray) {
            ShowWindow(hExisting, SW_SHOW);
            ShowWindow(hExisting, SW_RESTORE);
            SetForegroundWindow(hExisting);
            PostMessageW(hExisting, WM_VIELOTUS_SHOW_SETTINGS, 0, 0);
        } else {
            PostMessageW(hExisting, WM_VIELOTUS_ACTIVATE_PROFILES, 0, 0);
        }
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
    wc.hInstance = g_hInst;
    wc.hIcon = hClassIconBig;
    wc.hIconSm = hClassIconSm;
    wc.hCursor = LoadCursorW(nullptr, MAKEINTRESOURCEW(32512)); // IDC_ARROW
    wc.hbrBackground = nullptr;
    wc.lpszClassName = kWndClassName;
    RegisterClassExW(&wc);

    HDC hdc = GetDC(nullptr);
    int dpiY = GetDeviceCaps(hdc, LOGPIXELSY);
    int screenW = GetSystemMetrics(SM_CXSCREEN);
    int screenH = GetSystemMetrics(SM_CYSCREEN);
    ReleaseDC(nullptr, hdc);

    int clientW = MulDiv(680, dpiY, 96);
    int clientH = MulDiv(424, dpiY, 96);

    DWORD dwStyle = WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX | WS_CLIPCHILDREN;
    if (!startHiddenInTray) {
        dwStyle |= WS_VISIBLE;
    }
    DWORD dwExStyle = WS_EX_APPWINDOW;
    RECT rcWnd = { 0, 0, clientW, clientH };
    AdjustWindowRectEx(&rcWnd, dwStyle, FALSE, dwExStyle);

    int wndW = rcWnd.right - rcWnd.left;
    int wndH = rcWnd.bottom - rcWnd.top;
    int posX = (screenW > wndW) ? ((screenW - wndW) / 2) : 100;
    int posY = (screenH > wndH) ? ((screenH - wndH) / 2) : 100;

    bool canHideToTrayOnClose = (hwndParent == nullptr);

    HWND hwnd = CreateWindowExW(
        dwExStyle,
        kWndClassName,
        L"Sen Vi\u1EC7t (VieLotusIM)",
        dwStyle,
        posX, posY, wndW, wndH,
        hwndParent, nullptr, g_hInst, &canHideToTrayOnClose
    );
    if (hwnd) {
        if (!startHiddenInTray) {
            ShowWindow(hwnd, SW_SHOW);
            UpdateWindow(hwnd);
            SetForegroundWindow(hwnd);
        }
        PostMessageW(hwnd, WM_VIELOTUS_ACTIVATE_PROFILES, 0, 0);

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
