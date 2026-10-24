#include "Register.h"
#include <strsafe.h>

#define CLSID_STRLEN 38
#define VI_LANGID 0x042A // Vietnamese
#define US_LAYOUT 0x04090409

static const WCHAR c_szSubKeyPrefix[] = L"CLSID\\";
static const WCHAR c_szInprocServer32[] = L"InprocServer32";
static const WCHAR c_szThreadingModel[] = L"ThreadingModel";
static const WCHAR c_szApartment[] = L"Apartment";
static const WCHAR c_szDesc[] = L"Sen Việt (VieLotusIM) Text Input Processor";
static const WCHAR c_szProfileDesc[] = L"Tiếng Việt (Sen Việt - Telex)";
static const WCHAR c_szProfileVniDesc[] = L"Tiếng Việt (Sen Việt - VNI)";

static BOOL CLSIDToString(REFGUID refGUID, WCHAR *pszString) {
    return StringFromGUID2(refGUID, pszString, CLSID_STRLEN + 1) != 0;
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

    RegisterProfiles();
    RegisterCategories();

    return S_OK;
}

HRESULT UnregisterServer() {
    WCHAR szCLSID[CLSID_STRLEN + 1];
    if (!CLSIDToString(CLSID_VieLotusTIP, szCLSID)) {
        return E_FAIL;
    }

    UnregisterCategories();
    UnregisterProfiles();

    WCHAR szKey[MAX_PATH];
    StringCchPrintfW(szKey, MAX_PATH, L"%s%s\\%s", c_szSubKeyPrefix, szCLSID, c_szInprocServer32);
    RegDeleteKeyW(HKEY_CLASSES_ROOT, szKey);

    StringCchPrintfW(szKey, MAX_PATH, L"%s%s", c_szSubKeyPrefix, szCLSID);
    RegDeleteKeyW(HKEY_CLASSES_ROOT, szKey);

    return S_OK;
}

HRESULT RegisterProfiles() {
    ITfInputProcessorProfiles *pProfiles = nullptr;
    HRESULT hr = CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr, CLSCTX_INPROC_SERVER, IID_ITfInputProcessorProfiles, (void **)&pProfiles);
    if (SUCCEEDED(hr) && pProfiles) {
        hr = pProfiles->Register(CLSID_VieLotusTIP);
        if (SUCCEEDED(hr)) {
            WCHAR szFilePath[MAX_PATH];
            GetModuleFileNameW(g_hInst, szFilePath, MAX_PATH);
            pProfiles->AddLanguageProfile(
                CLSID_VieLotusTIP,
                VI_LANGID,
                GUID_VieLotusProfile,
                c_szProfileDesc,
                (ULONG)wcslen(c_szProfileDesc),
                szFilePath,
                (ULONG)wcslen(szFilePath),
                0
            );
            pProfiles->AddLanguageProfile(
                CLSID_VieLotusTIP,
                VI_LANGID,
                GUID_VieLotusProfileVNI,
                c_szProfileVniDesc,
                (ULONG)wcslen(c_szProfileVniDesc),
                szFilePath,
                (ULONG)wcslen(szFilePath),
                0
            );
        }
        pProfiles->Release();
    }
    return hr;
}

HRESULT UnregisterProfiles() {
    ITfInputProcessorProfiles *pProfiles = nullptr;
    HRESULT hr = CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr, CLSCTX_INPROC_SERVER, IID_ITfInputProcessorProfiles, (void **)&pProfiles);
    if (SUCCEEDED(hr) && pProfiles) {
        pProfiles->Unregister(CLSID_VieLotusTIP);
        pProfiles->Release();
    }
    return hr;
}

HRESULT RegisterCategories() {
    ITfCategoryMgr *pCategoryMgr = nullptr;
    HRESULT hr = CoCreateInstance(CLSID_TF_CategoryMgr, nullptr, CLSCTX_INPROC_SERVER, IID_ITfCategoryMgr, (void **)&pCategoryMgr);
    if (SUCCEEDED(hr) && pCategoryMgr) {
        pCategoryMgr->RegisterCategory(CLSID_VieLotusTIP, GUID_TFCAT_TIP_KEYBOARD, CLSID_VieLotusTIP);
        pCategoryMgr->Release();
    }
    return hr;
}

HRESULT UnregisterCategories() {
    ITfCategoryMgr *pCategoryMgr = nullptr;
    HRESULT hr = CoCreateInstance(CLSID_TF_CategoryMgr, nullptr, CLSCTX_INPROC_SERVER, IID_ITfCategoryMgr, (void **)&pCategoryMgr);
    if (SUCCEEDED(hr) && pCategoryMgr) {
        pCategoryMgr->UnregisterCategory(CLSID_VieLotusTIP, GUID_TFCAT_TIP_KEYBOARD, CLSID_VieLotusTIP);
        pCategoryMgr->Release();
    }
    return hr;
}
