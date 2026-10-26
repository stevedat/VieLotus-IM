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

    if (!IsEqualCLSID(rclsid, CLSID_VieLotusTIP)) {
        return CLASS_E_CLASSNOTAVAILABLE;
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
    ActivateUserProfiles();
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
    (void)hinst;
    (void)lpszCmdLine;
    (void)nCmdShow;
    HRESULT hrCo = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    ShowVieLotusSettingsDialog(hwnd);
    if (SUCCEEDED(hrCo)) {
        CoUninitialize();
    }
}
