#include "Globals.h"
#include "ClassFactory.h"
#include "Register.h"

BOOL WINAPI DllMain(HINSTANCE hInst, DWORD dwReason, LPVOID pvReserved) {
    (void)pvReserved;
    switch (dwReason) {
    case DLL_PROCESS_ATTACH:
        g_hInst = hInst;
        DisableThreadLibraryCalls(hInst);
        break;
    case DLL_PROCESS_DETACH:
        break;
    }
    return TRUE;
}

STDAPI DllGetClassObject(REFCLSID rclsid, REFIID riid, void **ppvObj) {
    if (!ppvObj) return E_POINTER;
    *ppvObj = nullptr;

    if (!IsEqualCLSID(rclsid, CLSID_VieLotusTIP) &&
        !IsEqualCLSID(rclsid, CLSID_VieLotusTIP_Legacy) &&
        !IsEqualCLSID(rclsid, CLSID_VieLotusTIP_Legacy2)) {
        return CLASS_E_CLASSNOTAVAILABLE;
    }

    // If this module was renamed to VieLotusTIP.old.N.dll during a hot-update while the host app remained open,
    // forward class creation to the newest C:\Program Files\VieLotusIM\VieLotusTIP.dll on disk.
    WCHAR selfPath[MAX_PATH] = {0};
    if (GetModuleFileNameW(g_hInst, selfPath, MAX_PATH) > 0 && wcsstr(selfPath, L".old.") != nullptr) {
        WCHAR canonicalPath[MAX_PATH] = {0};
#if defined(_WIN64)
        const wchar_t *canonicalTemplate = L"%ProgramW6432%\\VieLotusIM\\VieLotusTIP.dll";
#else
        const wchar_t *canonicalTemplate = L"%ProgramW6432%\\VieLotusIM\\VieLotusTIP32.dll";
#endif
        if (ExpandEnvironmentStringsW(canonicalTemplate, canonicalPath, MAX_PATH) > 0) {
            HMODULE hNew = LoadLibraryW(canonicalPath);
            if (hNew && hNew != g_hInst) {
                using PFN_DllGetClassObject = HRESULT(STDAPICALLTYPE *)(REFCLSID, REFIID, void **);
                FARPROC rawGet = GetProcAddress(hNew, "DllGetClassObject");
                auto pfnGet = reinterpret_cast<PFN_DllGetClassObject>(reinterpret_cast<void *>(rawGet));
                if (pfnGet) {
                    return pfnGet(rclsid, riid, ppvObj);
                }
            }
        }
    }

    CClassFactory *pFactory = new (std::nothrow) CClassFactory();
    if (!pFactory) {
        return E_OUTOFMEMORY;
    }

    HRESULT hr = pFactory->QueryInterface(riid, ppvObj);
    pFactory->Release();
    return hr;
}

STDAPI DllCanUnloadNow() {
    return (g_cRef.load(std::memory_order_relaxed) == 0) ? S_OK : S_FALSE;
}

STDAPI DllRegisterServer() {
    return RegisterServer();
}

STDAPI DllUnregisterServer() {
    return UnregisterServer();
}

extern "C" void CALLBACK ActivateUserProfilesW(HWND hwnd, HINSTANCE hinst, LPWSTR lpszCmdLine, int nCmdShow) {
    (void)hwnd;
    (void)hinst;
    (void)lpszCmdLine;
    (void)nCmdShow;
    HRESULT hrCo = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    ActivateUserProfiles(true);
    if (SUCCEEDED(hrCo)) {
        CoUninitialize();
    }
}

extern "C" void CALLBACK DeactivateUserProfilesW(HWND hwnd, HINSTANCE hinst, LPWSTR lpszCmdLine, int nCmdShow) {
    (void)hwnd;
    (void)hinst;
    (void)lpszCmdLine;
    (void)nCmdShow;
    HRESULT hrCo = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    DeactivateUserProfiles();
    if (SUCCEEDED(hrCo)) {
        CoUninitialize();
    }
}

extern "C" void CALLBACK ShowSettingsDialogW(HWND hwnd, HINSTANCE hinst, LPWSTR lpszCmdLine, int nCmdShow) {
    (void)hwnd;
    (void)hinst;
    if (nCmdShow == SW_HIDE ||
        (lpszCmdLine && (wcsstr(lpszCmdLine, L"--startup") != nullptr ||
                         wcsstr(lpszCmdLine, L"/startup") != nullptr ||
                         wcsstr(lpszCmdLine, L"--tray") != nullptr))) {
        return;
    }
    HWND hExisting = FindWindowW(kSettingsWndClassName, nullptr);
    if (hExisting && IsWindow(hExisting)) {
        DWORD targetPid = 0;
        if (GetWindowThreadProcessId(hExisting, &targetPid) != 0 && targetPid != 0) {
            AllowSetForegroundWindow(targetPid);
        }
        if (PostMessageW(hExisting, kWmVieLotusShowSettings, 0, 0)) {
            return;
        }
    }
    TryWakeSettingsViaNamedPipe(50);
}
