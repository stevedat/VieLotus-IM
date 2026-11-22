#include "Register.h"
#include <strsafe.h>
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

// Explicit Unicode escapes guarantee zero CP1252 mojibake regardless of compiler source charset flags
static const WCHAR c_szSubKeyPrefix[] = L"CLSID\\";
static const WCHAR c_szInprocServer32[] = L"InprocServer32";
static const WCHAR c_szThreadingModel[] = L"ThreadingModel";
static const WCHAR c_szApartment[] = L"Apartment";
static const WCHAR c_szDesc[] = L"Sen Vi\u1EC7t (VieLotusIM) Text Input Processor";
static const WCHAR c_szProfileDesc[] = L"Ti\u1EBFng Vi\u1EC7t (Sen Vi\u1EC7t - Telex)";
static const WCHAR c_szProfileVniDesc[] = L"Ti\u1EBFng Vi\u1EC7t (Sen Vi\u1EC7t - VNI)";

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

static void WriteRegDwordLocal(HKEY hKey, LPCWSTR valName, DWORD val) {
    RegSetValueExW(hKey, valName, 0, REG_DWORD, reinterpret_cast<const BYTE *>(&val), sizeof(val));
}

static bool RegisterComServerForView(const WCHAR *szCLSID, const WCHAR *dllPath, REGSAM wow64View) {
    WCHAR szKey[MAX_PATH];
    StringCchPrintfW(szKey, MAX_PATH, L"SOFTWARE\\Classes\\%s%s", c_szSubKeyPrefix, szCLSID);

    HKEY hKey = nullptr;
    if (RegCreateKeyExW(
            HKEY_LOCAL_MACHINE,
            szKey,
            0,
            nullptr,
            REG_OPTION_NON_VOLATILE,
            KEY_WRITE | wow64View,
            nullptr,
            &hKey,
            nullptr
        ) != ERROR_SUCCESS) {
        return false;
    }

    RegSetValueExW(hKey, nullptr, 0, REG_SZ, reinterpret_cast<const BYTE *>(c_szDesc), static_cast<DWORD>(wcslen(c_szDesc) + 1) * sizeof(WCHAR));
    RegCloseKey(hKey);

    StringCchPrintfW(szKey, MAX_PATH, L"SOFTWARE\\Classes\\%s%s\\%s", c_szSubKeyPrefix, szCLSID, c_szInprocServer32);
    HKEY hInprocKey = nullptr;
    if (RegCreateKeyExW(
            HKEY_LOCAL_MACHINE,
            szKey,
            0,
            nullptr,
            REG_OPTION_NON_VOLATILE,
            KEY_WRITE | wow64View,
            nullptr,
            &hInprocKey,
            nullptr
        ) == ERROR_SUCCESS) {
        RegSetValueExW(hInprocKey, nullptr, 0, REG_SZ, reinterpret_cast<const BYTE *>(dllPath), static_cast<DWORD>(wcslen(dllPath) + 1) * sizeof(WCHAR));
        RegSetValueExW(hInprocKey, c_szThreadingModel, 0, REG_SZ, reinterpret_cast<const BYTE *>(c_szApartment), static_cast<DWORD>(wcslen(c_szApartment) + 1) * sizeof(WCHAR));
        RegCloseKey(hInprocKey);
    }

    return true;
}

HRESULT RegisterServer() {
    WCHAR szCLSID[CLSID_STRLEN + 1];
    if (!CLSIDToString(CLSID_VieLotusTIP, szCLSID)) {
        return E_FAIL;
    }

    WCHAR szFilePath[MAX_PATH] = {0};
    if (GetModuleFileNameW(g_hInst, szFilePath, MAX_PATH) == 0) {
        return E_FAIL;
    }

#if defined(_WIN64)
    if (!RegisterComServerForView(szCLSID, szFilePath, KEY_WOW64_64KEY)) {
        return E_FAIL;
    }
    // Also register the sibling 32-bit (x86) TIP DLL under WOW6432Node so 32-bit apps
    // (e.g. 32-bit Zalo PC, Steam, legacy Win32 apps) can load VieLotusTIP32.dll in-process.
    std::wstring dllDir(szFilePath);
    size_t slashPos = dllDir.find_last_of(L"\\/");
    if (slashPos != std::wstring::npos) {
        std::wstring dll32Path = dllDir.substr(0, slashPos + 1) + L"VieLotusTIP32.dll";
        DWORD attrs32 = GetFileAttributesW(dll32Path.c_str());
        if (attrs32 != INVALID_FILE_ATTRIBUTES && !(attrs32 & FILE_ATTRIBUTE_DIRECTORY)) {
            RegisterComServerForView(szCLSID, dll32Path.c_str(), KEY_WOW64_32KEY);
        }
    }
#else
    if (!RegisterComServerForView(szCLSID, szFilePath, KEY_WOW64_32KEY)) {
        return E_FAIL;
    }
#endif

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

    WCHAR szInprocKey[MAX_PATH];
    WCHAR szRootKey[MAX_PATH];
    StringCchPrintfW(szInprocKey, MAX_PATH, L"SOFTWARE\\Classes\\%s%s\\%s", c_szSubKeyPrefix, szCLSID, c_szInprocServer32);
    StringCchPrintfW(szRootKey, MAX_PATH, L"SOFTWARE\\Classes\\%s%s", c_szSubKeyPrefix, szCLSID);
    for (REGSAM view : { static_cast<REGSAM>(KEY_WOW64_64KEY), static_cast<REGSAM>(KEY_WOW64_32KEY) }) {
        RegDeleteKeyExW(HKEY_LOCAL_MACHINE, szInprocKey, view, 0);
        RegDeleteKeyExW(HKEY_LOCAL_MACHINE, szRootKey, view, 0);
    }

    return S_OK;
}

static void CleanupLegacyClsid98DC() {
    HMODULE hInputDll = LoadLibraryExW(L"input.dll", nullptr, LOAD_LIBRARY_SEARCH_SYSTEM32);
    if (hInputDll) {
        using PFN_InstallLayoutOrTip = BOOL(WINAPI *)(LPCWSTR psz, DWORD dwFlags);
        using PFN_InstallLayoutOrTipUserReg = BOOL(WINAPI *)(LPCWSTR pszUserReg, LPCWSTR pszSystemReg, LPCWSTR pszSoftwareReg, LPCWSTR psz, DWORD dwFlags);
        FARPROC rawUserReg = GetProcAddress(hInputDll, "InstallLayoutOrTipUserReg");
        auto pfnUserReg = reinterpret_cast<PFN_InstallLayoutOrTipUserReg>(reinterpret_cast<void *>(rawUserReg));
        if (pfnUserReg) {
            for (LPCWSTR tip : kLegacyLayoutOrTipStringsToUninstall) {
                pfnUserReg(nullptr, nullptr, nullptr, tip, ILOT_UNINSTALL);
            }
        }
        FARPROC rawInstall = GetProcAddress(hInputDll, "InstallLayoutOrTip");
        auto pfnInstall = reinterpret_cast<PFN_InstallLayoutOrTip>(reinterpret_cast<void *>(rawInstall));
        if (pfnInstall) {
            for (LPCWSTR tip : kLegacyLayoutOrTipStringsToUninstall) {
                pfnInstall(tip, ILOT_UNINSTALL);
            }
        }
        FreeLibrary(hInputDll);
    }

    HRESULT hrCo = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    const GUID kLegacyClsids[] = { CLSID_VieLotusTIP_Legacy, CLSID_VieLotusTIP_Legacy2 };
    const LANGID kLangs[] = { VI_LANGID, EN_US_LANGID };

    ITfInputProcessorProfiles *pProfiles = nullptr;
    if (SUCCEEDED(CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr, CLSCTX_INPROC_SERVER, IID_ITfInputProcessorProfiles, reinterpret_cast<void **>(&pProfiles))) && pProfiles) {
        ITfInputProcessorProfileMgr *pProfileMgr = nullptr;
        if (SUCCEEDED(pProfiles->QueryInterface(IID_ITfInputProcessorProfileMgr, reinterpret_cast<void **>(&pProfileMgr))) && pProfileMgr) {
            for (const GUID &legClsid : kLegacyClsids) {
                for (LANGID lid : kLangs) {
                    pProfileMgr->UnregisterProfile(legClsid, lid, GUID_VieLotusProfile, 0);
                    pProfileMgr->UnregisterProfile(legClsid, lid, GUID_VieLotusProfileVNI, 0);
                }
            }
            pProfileMgr->Release();
        }
        for (const GUID &legClsid : kLegacyClsids) {
            pProfiles->Unregister(legClsid);
        }
        pProfiles->Release();
    }

    ITfCategoryMgr *pCategoryMgr = nullptr;
    if (SUCCEEDED(CoCreateInstance(CLSID_TF_CategoryMgr, nullptr, CLSCTX_INPROC_SERVER, IID_ITfCategoryMgr, reinterpret_cast<void **>(&pCategoryMgr))) && pCategoryMgr) {
        for (const GUID &legClsid : kLegacyClsids) {
            for (const auto &cat : kCategoriesToRegister) {
                pCategoryMgr->UnregisterCategory(legClsid, cat, legClsid);
            }
        }
        pCategoryMgr->Release();
    }

    // Remove legacy 0409 (English) profiles from current CLSID if previously registered
    ITfInputProcessorProfiles *pCurProfiles = nullptr;
    if (SUCCEEDED(CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr, CLSCTX_INPROC_SERVER, IID_ITfInputProcessorProfiles, reinterpret_cast<void **>(&pCurProfiles))) && pCurProfiles) {
        ITfInputProcessorProfileMgr *pCurMgr = nullptr;
        if (SUCCEEDED(pCurProfiles->QueryInterface(IID_ITfInputProcessorProfileMgr, reinterpret_cast<void **>(&pCurMgr))) && pCurMgr) {
            pCurMgr->UnregisterProfile(CLSID_VieLotusTIP, EN_US_LANGID, GUID_VieLotusProfile, 0);
            pCurMgr->UnregisterProfile(CLSID_VieLotusTIP, EN_US_LANGID, GUID_VieLotusProfileVNI, 0);
            pCurMgr->Release();
        }
        pCurProfiles->Release();
    }

    if (SUCCEEDED(hrCo)) {
        CoUninitialize();
    }

    for (REGSAM view : { static_cast<REGSAM>(KEY_WOW64_64KEY), static_cast<REGSAM>(KEY_WOW64_32KEY) }) {
        RegDeleteKeyExW(HKEY_LOCAL_MACHINE, L"SOFTWARE\\Classes\\CLSID\\{C7B08E9D-4762-4C97-8B1F-522197A598DC}\\InprocServer32", view, 0);
        RegDeleteKeyExW(HKEY_LOCAL_MACHINE, L"SOFTWARE\\Classes\\CLSID\\{C7B08E9D-4762-4C97-8B1F-522197A598DC}", view, 0);
        RegDeleteKeyExW(HKEY_LOCAL_MACHINE, L"SOFTWARE\\Classes\\CLSID\\{C7B08E9D-4762-4C97-8B1F-522197A598DD}\\InprocServer32", view, 0);
        RegDeleteKeyExW(HKEY_LOCAL_MACHINE, L"SOFTWARE\\Classes\\CLSID\\{C7B08E9D-4762-4C97-8B1F-522197A598DD}", view, 0);
    }
}

HRESULT RegisterProfiles() {
    CleanupLegacyClsid98DC();

    bool preferVni = false;
    LoadPersistedVniPreference(preferVni);

    WCHAR szFilePath[MAX_PATH] = {0};
    GetModuleFileNameW(g_hInst, szFilePath, MAX_PATH);
    ULONG cchFile = static_cast<ULONG>(wcslen(szFilePath));

    ITfInputProcessorProfiles *pProfiles = nullptr;
    HRESULT hr = CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr, CLSCTX_INPROC_SERVER, IID_ITfInputProcessorProfiles, reinterpret_cast<void **>(&pProfiles));
    if (SUCCEEDED(hr) && pProfiles) {
        hr = pProfiles->Register(CLSID_VieLotusTIP);
        if (SUCCEEDED(hr)) {
            pProfiles->AddLanguageProfile(
                CLSID_VieLotusTIP,
                VI_LANGID,
                GUID_VieLotusProfile,
                c_szProfileDesc,
                static_cast<ULONG>(wcslen(c_szProfileDesc)),
                szFilePath,
                cchFile,
                0
            );
            pProfiles->AddLanguageProfile(
                CLSID_VieLotusTIP,
                VI_LANGID,
                GUID_VieLotusProfileVNI,
                c_szProfileVniDesc,
                static_cast<ULONG>(wcslen(c_szProfileVniDesc)),
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
                static_cast<ULONG>(wcslen(c_szProfileDesc)),
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
                static_cast<ULONG>(wcslen(c_szProfileVniDesc)),
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

static void EnsureVietnameseUserProfileLanguage(bool preferVni) {
    LPCWSTR preferredTipString = preferVni ? kTipVniLayoutString : kTipTelexLayoutString;

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
        WriteRegDwordLocal(hViKey, L"TransientLangId", VI_LANGID);
        RegDeleteValueW(hViKey, L"042A:00000409");
        RegDeleteValueW(hViKey, L"042a:00000409");
        RegDeleteValueW(hViKey, L"042A:0000042A");
        RegDeleteValueW(hViKey, L"042a:0000042a");
        for (LPCWSTR tip : kLegacyLayoutOrTipStringsToUninstall) {
            RegDeleteValueW(hViKey, tip);
        }
        WriteRegDwordLocal(hViKey, kTipTelexLayoutString, preferVni ? 2u : 1u);
        WriteRegDwordLocal(hViKey, kTipVniLayoutString, preferVni ? 1u : 2u);
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

HRESULT ActivateUserProfiles(bool forceLangListSync) {
    CleanupLegacyClsid98DC();

    VieLotusWindowsPrefs prefs{};
    LoadVieLotusPrefs(prefs);

    bool preferVni = prefs.isVni;
    const GUID &preferredGuid = preferVni ? GUID_VieLotusProfileVNI : GUID_VieLotusProfile;
    const GUID &otherGuid = preferVni ? GUID_VieLotusProfile : GUID_VieLotusProfileVNI;
    LPCWSTR preferredTipString = preferVni ? kTipVniLayoutString : kTipTelexLayoutString;
    LPCWSTR otherTipString = preferVni ? kTipTelexLayoutString : kTipVniLayoutString;

    (void)forceLangListSync;
    EnsureVietnameseUserProfileLanguage(preferVni);

    HMODULE hInputDll = LoadLibraryExW(L"input.dll", nullptr, LOAD_LIBRARY_SEARCH_SYSTEM32);
    if (hInputDll) {
        using PFN_InstallLayoutOrTip = BOOL(WINAPI *)(LPCWSTR psz, DWORD dwFlags);
        using PFN_InstallLayoutOrTipUserReg = BOOL(WINAPI *)(LPCWSTR pszUserReg, LPCWSTR pszSystemReg, LPCWSTR pszSoftwareReg, LPCWSTR psz, DWORD dwFlags);
        using PFN_SetDefaultLayoutOrTip = BOOL(WINAPI *)(LPCWSTR psz, DWORD dwFlags);
        FARPROC rawUserReg = GetProcAddress(hInputDll, "InstallLayoutOrTipUserReg");
        auto pfnInstallLayoutOrTipUserReg = reinterpret_cast<PFN_InstallLayoutOrTipUserReg>(reinterpret_cast<void *>(rawUserReg));
        if (pfnInstallLayoutOrTipUserReg) {
            for (LPCWSTR tip : kLegacyLayoutOrTipStringsToUninstall) {
                pfnInstallLayoutOrTipUserReg(nullptr, nullptr, nullptr, tip, ILOT_UNINSTALL);
            }
            pfnInstallLayoutOrTipUserReg(nullptr, nullptr, nullptr, otherTipString, 0);
            pfnInstallLayoutOrTipUserReg(nullptr, nullptr, nullptr, preferredTipString, 0);
        }
        FARPROC rawInstall = GetProcAddress(hInputDll, "InstallLayoutOrTip");
        auto pfnInstallLayoutOrTip = reinterpret_cast<PFN_InstallLayoutOrTip>(reinterpret_cast<void *>(rawInstall));
        if (pfnInstallLayoutOrTip) {
            for (LPCWSTR tip : kLegacyLayoutOrTipStringsToUninstall) {
                pfnInstallLayoutOrTip(tip, ILOT_UNINSTALL);
            }
            pfnInstallLayoutOrTip(otherTipString, 0);
            pfnInstallLayoutOrTip(preferredTipString, 0);
        }
        FARPROC rawSetDef = GetProcAddress(hInputDll, "SetDefaultLayoutOrTip");
        auto pfnSetDefaultLayoutOrTip = reinterpret_cast<PFN_SetDefaultLayoutOrTip>(reinterpret_cast<void *>(rawSetDef));
        if (pfnSetDefaultLayoutOrTip) {
            pfnSetDefaultLayoutOrTip(preferredTipString, 0);
            pfnSetDefaultLayoutOrTip(preferredTipString, SDLOT_APPLYTOCURRENTTHREAD);
        }
        FreeLibrary(hInputDll);
    }

    HKL hklViUs = LoadKeyboardLayoutW(L"0000042a", KLF_SUBSTITUTE_OK | KLF_ACTIVATE | KLF_SETFORPROCESS);
    if (!hklViUs) {
        hklViUs = reinterpret_cast<HKL>(static_cast<ULONG_PTR>(0x0409042A));
    }

    ITfInputProcessorProfiles *pProfiles = nullptr;
    HRESULT hr = CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr, CLSCTX_INPROC_SERVER, IID_ITfInputProcessorProfiles, reinterpret_cast<void **>(&pProfiles));
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
        FARPROC rawUserReg = GetProcAddress(hInputDll, "InstallLayoutOrTipUserReg");
        auto pfnUserReg = reinterpret_cast<PFN_InstallLayoutOrTipUserReg>(reinterpret_cast<void *>(rawUserReg));
        if (pfnUserReg) {
            pfnUserReg(nullptr, nullptr, nullptr, kTipTelexLayoutString, ILOT_UNINSTALL);
            pfnUserReg(nullptr, nullptr, nullptr, kTipVniLayoutString, ILOT_UNINSTALL);
        }
        FARPROC rawInstall = GetProcAddress(hInputDll, "InstallLayoutOrTip");
        auto pfnInstallLayoutOrTip = reinterpret_cast<PFN_InstallLayoutOrTip>(reinterpret_cast<void *>(rawInstall));
        if (pfnInstallLayoutOrTip) {
            pfnInstallLayoutOrTip(kTipTelexLayoutString, ILOT_UNINSTALL);
            pfnInstallLayoutOrTip(kTipVniLayoutString, ILOT_UNINSTALL);
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
        RegDeleteValueW(hViKey, kTipTelexLayoutString);
        RegDeleteValueW(hViKey, kTipVniLayoutString);
        RegCloseKey(hViKey);
    }
    HKEY hPrefsKey = nullptr;
    if (RegOpenKeyExW(HKEY_CURRENT_USER, kVieLotusPrefsSubKey, 0, KEY_SET_VALUE, &hPrefsKey) == ERROR_SUCCESS && hPrefsKey) {
        WriteRegDwordLocal(hPrefsKey, L"WinLangListCleanVer", 0u);
        RegCloseKey(hPrefsKey);
    }
    return S_OK;
}

HRESULT UnregisterProfiles() {
    const LANGID kLangs[] = { VI_LANGID, EN_US_LANGID };
    ITfInputProcessorProfiles *pProfiles = nullptr;
    HRESULT hr = CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr, CLSCTX_INPROC_SERVER, IID_ITfInputProcessorProfiles, reinterpret_cast<void **>(&pProfiles));
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
    HRESULT hr = CoCreateInstance(CLSID_TF_CategoryMgr, nullptr, CLSCTX_INPROC_SERVER, IID_ITfCategoryMgr, reinterpret_cast<void **>(&pCategoryMgr));
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
    HRESULT hr = CoCreateInstance(CLSID_TF_CategoryMgr, nullptr, CLSCTX_INPROC_SERVER, IID_ITfCategoryMgr, reinterpret_cast<void **>(&pCategoryMgr));
    if (SUCCEEDED(hr) && pCategoryMgr) {
        for (const auto &cat : kCategoriesToRegister) {
            pCategoryMgr->UnregisterCategory(CLSID_VieLotusTIP, cat, CLSID_VieLotusTIP);
        }
        pCategoryMgr->Release();
    }
    return hr;
}
