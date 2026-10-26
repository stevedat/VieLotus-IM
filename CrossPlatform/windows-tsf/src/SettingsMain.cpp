#include <windows.h>
#include <shellapi.h>
#include <shlobj.h>
#include <strsafe.h>
#include <string>

typedef HRESULT(STDAPICALLTYPE *PFN_DllRegisterServer)(void);
typedef HRESULT(STDAPICALLTYPE *PFN_DllUnregisterServer)(void);
typedef void(CALLBACK *PFN_RundllEntryW)(HWND, HINSTANCE, LPWSTR, int);

static std::wstring GetExecutableDir() {
    WCHAR buf[MAX_PATH] = {};
    DWORD len = GetModuleFileNameW(nullptr, buf, MAX_PATH);
    if (len == 0 || len >= MAX_PATH) return L"";
    for (int i = static_cast<int>(len) - 1; i >= 0; --i) {
        if (buf[i] == L'\\' || buf[i] == L'/') {
            buf[i] = L'\0';
            break;
        }
    }
    return std::wstring(buf);
}

static std::wstring GetProgramFilesInstallDir() {
    WCHAR pf[MAX_PATH] = {};
    if (ExpandEnvironmentStringsW(L"%ProgramW6432%\\VieLotusIM", pf, MAX_PATH) > 0 && pf[0] != L'%') {
        return std::wstring(pf);
    }
    if (SUCCEEDED(SHGetFolderPathW(nullptr, CSIDL_PROGRAM_FILES, nullptr, 0, pf))) {
        std::wstring res(pf);
        res += L"\\VieLotusIM";
        return res;
    }
    return L"C:\\Program Files\\VieLotusIM";
}

static bool IsTipRegisteredInHKLM() {
    HKEY hKey = nullptr;
    LSTATUS st = RegOpenKeyExW(
        HKEY_LOCAL_MACHINE,
        L"SOFTWARE\\Classes\\CLSID\\{C7B08E9D-4762-4C97-8B1F-522197A598DC}\\InprocServer32",
        0,
        KEY_READ | KEY_WOW64_64KEY,
        &hKey
    );
    if (st == ERROR_SUCCESS && hKey) {
        WCHAR dllPath[MAX_PATH] = {};
        DWORD cb = sizeof(dllPath);
        DWORD type = 0;
        LSTATUS qst = RegQueryValueExW(hKey, nullptr, nullptr, &type, reinterpret_cast<LPBYTE>(dllPath), &cb);
        RegCloseKey(hKey);
        if (qst == ERROR_SUCCESS && dllPath[0] != L'\0') {
            DWORD attrs = GetFileAttributesW(dllPath);
            if (attrs != INVALID_FILE_ATTRIBUTES && !(attrs & FILE_ATTRIBUTE_DIRECTORY)) {
                return true;
            }
        }
    }
    return false;
}

static void CopyDirectoryPngAssets(const std::wstring &srcAssetsDir, const std::wstring &dstAssetsDir) {
    CreateDirectoryW(dstAssetsDir.c_str(), nullptr);
    std::wstring pattern = srcAssetsDir + L"\\*.png";
    WIN32_FIND_DATAW fd{};
    HANDLE hFind = FindFirstFileW(pattern.c_str(), &fd);
    if (hFind == INVALID_HANDLE_VALUE) return;
    do {
        if (!(fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)) {
            std::wstring srcFile = srcAssetsDir + L"\\" + fd.cFileName;
            std::wstring dstFile = dstAssetsDir + L"\\" + fd.cFileName;
            CopyFileW(srcFile.c_str(), dstFile.c_str(), FALSE);
        }
    } while (FindNextFileW(hFind, &fd));
    FindClose(hFind);
}

static int PerformElevatedMsixTipProvisioning() {
    std::wstring srcDir = GetExecutableDir();
    std::wstring dstDir = GetProgramFilesInstallDir();
    if (srcDir.empty() || dstDir.empty()) return 1;

    CreateDirectoryW(dstDir.c_str(), nullptr);

    std::wstring srcDll = srcDir + L"\\VieLotusTIP.dll";
    std::wstring dstDll = dstDir + L"\\VieLotusTIP.dll";
    std::wstring oldDll = dstDir + L"\\VieLotusTIP.old.dll";

    if (_wcsicmp(srcDir.c_str(), dstDir.c_str()) != 0) {
        DeleteFileW(oldDll.c_str());
        if (!CopyFileW(srcDll.c_str(), dstDll.c_str(), FALSE)) {
            MoveFileExW(dstDll.c_str(), oldDll.c_str(), MOVEFILE_REPLACE_EXISTING);
            CopyFileW(srcDll.c_str(), dstDll.c_str(), FALSE);
        }
        std::wstring srcIco = srcDir + L"\\VieLotusIM.ico";
        std::wstring dstIco = dstDir + L"\\VieLotusIM.ico";
        CopyFileW(srcIco.c_str(), dstIco.c_str(), FALSE);
        CopyDirectoryPngAssets(srcDir + L"\\assets", dstDir + L"\\assets");
    }

    // Grant AppContainer Read & Execute permissions so UWP / WinUI 3 / Edge / Windows 11 Search can load VieLotusTIP.dll
    std::wstring icaclsArgs = L"\"" + dstDir + L"\" /grant \"*S-1-15-2-1:(OI)(CI)(RX)\" /grant \"*S-1-15-2-2:(OI)(CI)(RX)\" /T /C /Q";
    SHELLEXECUTEINFOW sei{};
    sei.cbSize = sizeof(sei);
    sei.fMask = SEE_MASK_NOCLOSEPROCESS;
    sei.lpFile = L"icacls.exe";
    sei.lpParameters = icaclsArgs.c_str();
    sei.nShow = SW_HIDE;
    if (ShellExecuteExW(&sei) && sei.hProcess) {
        WaitForSingleObject(sei.hProcess, 10000);
        CloseHandle(sei.hProcess);
    }

    HMODULE hDll = LoadLibraryW(dstDll.c_str());
    if (!hDll) return 2;

    auto pfnReg = reinterpret_cast<PFN_DllRegisterServer>(GetProcAddress(hDll, "DllRegisterServer"));
    HRESULT hr = pfnReg ? pfnReg() : E_FAIL;

    auto pfnAct = reinterpret_cast<PFN_RundllEntryW>(GetProcAddress(hDll, "ActivateUserProfilesW"));
    if (pfnAct) {
        pfnAct(nullptr, hDll, const_cast<LPWSTR>(L""), SW_HIDE);
    }

    FreeLibrary(hDll);
    return SUCCEEDED(hr) ? 0 : 3;
}

static void EnablePerMonitorDpiAwareness() {
    HMODULE hUser32 = GetModuleHandleW(L"user32.dll");
    if (hUser32) {
        typedef BOOL(WINAPI *PFN_SetProcessDpiAwarenessContext)(DPI_AWARENESS_CONTEXT);
        auto pfn = reinterpret_cast<PFN_SetProcessDpiAwarenessContext>(
            GetProcAddress(hUser32, "SetProcessDpiAwarenessContext")
        );
        if (pfn) {
            pfn(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
        }
    }
}

int WINAPI wWinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, PWSTR lpCmdLine, int nCmdShow) {
    (void)hPrevInstance;
    EnablePerMonitorDpiAwareness();

    std::wstring cmdLine = lpCmdLine ? lpCmdLine : L"";
    if (cmdLine.find(L"--install-msix-ime") != std::wstring::npos) {
        return PerformElevatedMsixTipProvisioning();
    }

    std::wstring exeDir = GetExecutableDir();
    std::wstring localDll = exeDir + L"\\VieLotusTIP.dll";
    std::wstring pfDll = GetProgramFilesInstallDir() + L"\\VieLotusTIP.dll";

    // If launched from an MSIX package (or portable directory) before HKLM TSF registration,
    // elevate once to provision %ProgramFiles%\VieLotusIM\VieLotusTIP.dll and register the TSF TIP.
    if (!IsTipRegisteredInHKLM()) {
        WCHAR selfExe[MAX_PATH] = {};
        GetModuleFileNameW(nullptr, selfExe, MAX_PATH);
        SHELLEXECUTEINFOW sei{};
        sei.cbSize = sizeof(sei);
        sei.fMask = SEE_MASK_NOCLOSEPROCESS;
        sei.lpVerb = L"runas";
        sei.lpFile = selfExe;
        sei.lpParameters = L"--install-msix-ime";
        sei.nShow = SW_HIDE;
        if (ShellExecuteExW(&sei) && sei.hProcess) {
            WaitForSingleObject(sei.hProcess, 30000);
            CloseHandle(sei.hProcess);
        }
    }

    HMODULE hDll = LoadLibraryW(localDll.c_str());
    if (!hDll) {
        hDll = LoadLibraryW(pfDll.c_str());
    }
    if (!hDll) {
        MessageBoxW(
            nullptr,
            L"Kh\u00F4ng t\u00ECm th\u1EA5y t\u1EC7p nh\u00E2n b\u1ED9 g\u00F5 VieLotusTIP.dll.",
            L"Sen Vi\u1EC7t (VieLotusIM)",
            MB_ICONERROR | MB_OK
        );
        return 1;
    }

    if (cmdLine.find(L"--activate") != std::wstring::npos || cmdLine.find(L"/activate") != std::wstring::npos) {
        auto pfnAct = reinterpret_cast<PFN_RundllEntryW>(GetProcAddress(hDll, "ActivateUserProfilesW"));
        if (pfnAct) pfnAct(nullptr, hDll, lpCmdLine, SW_HIDE);
        FreeLibrary(hDll);
        return 0;
    }

    if (cmdLine.find(L"--deactivate") != std::wstring::npos || cmdLine.find(L"/deactivate") != std::wstring::npos) {
        auto pfnDeact = reinterpret_cast<PFN_RundllEntryW>(GetProcAddress(hDll, "DeactivateUserProfilesW"));
        if (pfnDeact) pfnDeact(nullptr, hDll, lpCmdLine, SW_HIDE);
        FreeLibrary(hDll);
        return 0;
    }

    // Ensure current user profile has Telex/VNI enabled in Windows Language Bar
    auto pfnAct = reinterpret_cast<PFN_RundllEntryW>(GetProcAddress(hDll, "ActivateUserProfilesW"));
    if (pfnAct) {
        pfnAct(nullptr, hDll, const_cast<LPWSTR>(L""), SW_HIDE);
    }

    auto pfnShow = reinterpret_cast<PFN_RundllEntryW>(GetProcAddress(hDll, "ShowSettingsDialogW"));
    if (pfnShow) {
        pfnShow(nullptr, hInstance, lpCmdLine, nCmdShow);
    }

    FreeLibrary(hDll);
    return 0;
}
