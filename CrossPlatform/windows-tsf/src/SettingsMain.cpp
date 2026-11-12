#include <windows.h>
#include <shellapi.h>
#include <shlobj.h>
#include <strsafe.h>
#include <string>
#include "vielotus_win_installer.h"

#if __has_include("EmbeddedTipDll.h")
#ifndef VIELOTUS_HAS_EMBEDDED_TIP
#define VIELOTUS_HAS_EMBEDDED_TIP 1
#endif
#include "EmbeddedTipDll.h"
#endif

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

static bool AreFilesIdentical(const std::wstring &pathA, const std::wstring &pathB) {
    HANDLE hA = CreateFileW(pathA.c_str(), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (hA == INVALID_HANDLE_VALUE) return false;
    HANDLE hB = CreateFileW(pathB.c_str(), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (hB == INVALID_HANDLE_VALUE) {
        CloseHandle(hA);
        return false;
    }

    LARGE_INTEGER sizeA{}, sizeB{};
    if (!GetFileSizeEx(hA, &sizeA) || !GetFileSizeEx(hB, &sizeB) || sizeA.QuadPart != sizeB.QuadPart || sizeA.QuadPart <= 0) {
        CloseHandle(hA);
        CloseHandle(hB);
        return false;
    }

    bool identical = true;
    BYTE bufA[8192];
    BYTE bufB[8192];
    DWORD readA = 0, readB = 0;
    while (ReadFile(hA, bufA, sizeof(bufA), &readA, nullptr) && ReadFile(hB, bufB, sizeof(bufB), &readB, nullptr)) {
        if (readA != readB) {
            identical = false;
            break;
        }
        if (readA == 0) break;
        if (memcmp(bufA, bufB, readA) != 0) {
            identical = false;
            break;
        }
    }

    CloseHandle(hA);
    CloseHandle(hB);
    return identical;
}

static bool DoesFileMatchBuffer(const std::wstring &path, const unsigned char *buf, size_t len) {
    if (!buf || len == 0) return false;
    HANDLE h = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (h == INVALID_HANDLE_VALUE) return false;
    LARGE_INTEGER sz{};
    if (!GetFileSizeEx(h, &sz) || static_cast<size_t>(sz.QuadPart) != len) {
        CloseHandle(h);
        return false;
    }
    BYTE chunk[8192];
    size_t offset = 0;
    DWORD readBytes = 0;
    bool match = true;
    while (offset < len && ReadFile(h, chunk, sizeof(chunk), &readBytes, nullptr) && readBytes > 0) {
        if (offset + readBytes > len || memcmp(chunk, buf + offset, readBytes) != 0) {
            match = false;
            break;
        }
        offset += readBytes;
    }
    CloseHandle(h);
    return match && (offset == len);
}

static bool WriteBufferToFile(const std::wstring &path, const unsigned char *buf, size_t len) {
    if (!buf || len == 0) return false;
    HANDLE h = CreateFileW(path.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (h == INVALID_HANDLE_VALUE) return false;
    DWORD written = 0;
    BOOL ok = WriteFile(h, buf, static_cast<DWORD>(len), &written, nullptr);
    CloseHandle(h);
    return (ok && written == static_cast<DWORD>(len));
}

static bool RunSystemToolWait(const wchar_t *exeName, const std::wstring &args, DWORD timeoutMs, DWORD *outExitCode = nullptr) {
    WCHAR winDir[MAX_PATH] = {};
    std::wstring fullExe;
    if (GetSystemWindowsDirectoryW(winDir, MAX_PATH) > 0) {
        fullExe = std::wstring(winDir) + L"\\System32\\" + exeName;
    } else if (GetSystemDirectoryW(winDir, MAX_PATH) > 0) {
        fullExe = std::wstring(winDir) + L"\\" + exeName;
    } else {
        fullExe = exeName;
    }
    std::wstring cmdLine = L"\"" + fullExe + L"\" " + args;
    STARTUPINFOW si{};
    si.cb = sizeof(si);
    si.dwFlags = STARTF_USESHOWWINDOW;
    si.wShowWindow = SW_HIDE;
    PROCESS_INFORMATION pi{};
    PVOID oldWow64Value = nullptr;
    BOOL redirDisabled = Wow64DisableWow64FsRedirection(&oldWow64Value);
    BOOL created = CreateProcessW(nullptr, &cmdLine[0], nullptr, nullptr, FALSE, CREATE_NO_WINDOW, nullptr, nullptr, &si, &pi);
    if (redirDisabled) {
        Wow64RevertWow64FsRedirection(oldWow64Value);
    }
    if (!created) {
        return false;
    }
    WaitForSingleObject(pi.hProcess, timeoutMs);
    DWORD code = 1;
    GetExitCodeProcess(pi.hProcess, &code);
    CloseHandle(pi.hThread);
    CloseHandle(pi.hProcess);
    if (outExitCode) *outExitCode = code;
    return code == 0;
}

static int RunElevatedSelfCommand(const wchar_t *params, DWORD timeoutMs, DWORD *outShellErr = nullptr) {
    if (outShellErr) *outShellErr = 0;
    WCHAR selfExe[MAX_PATH] = {};
    if (GetModuleFileNameW(nullptr, selfExe, MAX_PATH) == 0) {
        if (outShellErr) *outShellErr = GetLastError();
        return 10;
    }

    // Copy selfExe to local %TEMP% before invoking UAC "runas" so launching from a Parallels/VMware
    // Mac shared folder (\\Mac\... or mapped network drive Z:\...) never fails in the elevated token!
    std::wstring runnerExe = selfExe;
    WCHAR tempDir[MAX_PATH] = {};
    if (GetTempPathW(MAX_PATH, tempDir) > 0) {
        std::wstring origDir = GetExecutableDir();
        if (!origDir.empty()) {
            CopyFileW((origDir + L"\\VieLotusIM.ico").c_str(), (std::wstring(tempDir) + L"VieLotusIM.ico").c_str(), FALSE);
        }
        for (int i = 0; i < 10; ++i) {
            WCHAR candidate[MAX_PATH] = {};
            if (i == 0) {
                StringCchPrintfW(candidate, MAX_PATH, L"%sVieLotusSetupElevated.exe", tempDir);
            } else {
                StringCchPrintfW(candidate, MAX_PATH, L"%sVieLotusSetupElevated_%d.exe", tempDir, i);
            }
            DeleteFileW(candidate);
            if (CopyFileW(selfExe, candidate, FALSE)) {
                std::wstring zoneAds = std::wstring(candidate) + L":Zone.Identifier";
                DeleteFileW(zoneAds.c_str());
                runnerExe = candidate;
                break;
            }
        }
    }

    SHELLEXECUTEINFOW sei{};
    sei.cbSize = sizeof(sei);
    sei.fMask = SEE_MASK_NOCLOSEPROCESS;
    sei.lpVerb = L"runas";
    sei.lpFile = runnerExe.c_str();
    sei.lpParameters = params;
    sei.nShow = SW_HIDE;
    if (!ShellExecuteExW(&sei) || !sei.hProcess) {
        if (outShellErr) *outShellErr = GetLastError();
        return 11;
    }
    WaitForSingleObject(sei.hProcess, timeoutMs);
    DWORD exitCode = 12;
    GetExitCodeProcess(sei.hProcess, &exitCode);
    CloseHandle(sei.hProcess);
    return static_cast<int>(exitCode);
}

static bool IsTipRegisteredAndUpToDate(const std::wstring &localDll) {
    if (!vielotus_win_installer::IsUninstallEntryRegistered()) {
        return false;
    }
    HKEY hKey = nullptr;
    LSTATUS st = RegOpenKeyExW(
        HKEY_LOCAL_MACHINE,
        L"SOFTWARE\\Classes\\CLSID\\{C7B08E9D-4762-4C97-8B1F-522197A598DE}\\InprocServer32",
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
#if defined(VIELOTUS_HAS_EMBEDDED_TIP)
                (void)localDll;
                const uint8_t *embData = nullptr;
                size_t embSize = 0;
                GetEmbeddedTipDllForHostOs(embData, embSize);
                if (!DoesFileMatchBuffer(dllPath, embData, embSize)) {
                    return false;
                }
                return true;
#else
                DWORD localAttrs = GetFileAttributesW(localDll.c_str());
                if (localAttrs != INVALID_FILE_ATTRIBUTES && !(localAttrs & FILE_ATTRIBUTE_DIRECTORY)) {
                    if (_wcsicmp(localDll.c_str(), dllPath) != 0 && !AreFilesIdentical(localDll, dllPath)) {
                        return false;
                    }
                    return true;
                }
                return true;
#endif
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
    vielotus_win_installer::CloseRunningSettingsAndTrayWindow();

    std::wstring srcDir = GetExecutableDir();
    std::wstring dstDir = GetProgramFilesInstallDir();
    if (dstDir.empty()) return 1;

    CreateDirectoryW(dstDir.c_str(), nullptr);

    // Remove any obsolete VieLotusCAPI.dll from older builds so it can never shadow the embedded engine
    DeleteFileW((dstDir + L"\\VieLotusCAPI.dll").c_str());

    std::wstring srcDll = srcDir + L"\\VieLotusTIP.dll";
    std::wstring dstDll = dstDir + L"\\VieLotusTIP.dll";
    std::wstring oldDll = dstDir + L"\\VieLotusTIP.old.dll";

    DeleteFileW(oldDll.c_str());
    for (int i = 1; i <= 99; ++i) {
        WCHAR slot[MAX_PATH] = {};
        StringCchPrintfW(slot, MAX_PATH, L"%s\\VieLotusTIP.old.%d.dll", dstDir.c_str(), i);
        DeleteFileW(slot);
    }

    bool deployedDll = false;
#if defined(VIELOTUS_HAS_EMBEDDED_TIP)
    const uint8_t *embData = nullptr;
    size_t embSize = 0;
    GetEmbeddedTipDllForHostOs(embData, embSize);
    if (embData && embSize > 0) {
        if (!WriteBufferToFile(dstDll, embData, embSize)) {
            for (int i = 1; i <= 99; ++i) {
                WCHAR slot[MAX_PATH] = {};
                StringCchPrintfW(slot, MAX_PATH, L"%s\\VieLotusTIP.old.%d.dll", dstDir.c_str(), i);
                DeleteFileW(slot);
                if (MoveFileExW(dstDll.c_str(), slot, MOVEFILE_REPLACE_EXISTING)) {
                    break;
                }
            }
            deployedDll = WriteBufferToFile(dstDll, embData, embSize);
        } else {
            deployedDll = true;
        }
    }
#endif
    if (!deployedDll && !srcDir.empty() && _wcsicmp(srcDir.c_str(), dstDir.c_str()) != 0) {
        DWORD srcAttrs = GetFileAttributesW(srcDll.c_str());
        if (srcAttrs != INVALID_FILE_ATTRIBUTES && !(srcAttrs & FILE_ATTRIBUTE_DIRECTORY)) {
            if (!CopyFileW(srcDll.c_str(), dstDll.c_str(), FALSE)) {
                for (int i = 1; i <= 99; ++i) {
                    WCHAR slot[MAX_PATH] = {};
                    StringCchPrintfW(slot, MAX_PATH, L"%s\\VieLotusTIP.old.%d.dll", dstDir.c_str(), i);
                    DeleteFileW(slot);
                    if (MoveFileExW(dstDll.c_str(), slot, MOVEFILE_REPLACE_EXISTING)) {
                        break;
                    }
                }
                deployedDll = (CopyFileW(srcDll.c_str(), dstDll.c_str(), FALSE) != FALSE);
            } else {
                deployedDll = true;
            }
        }
    }

    if (!srcDir.empty() && _wcsicmp(srcDir.c_str(), dstDir.c_str()) != 0) {
        WCHAR selfExe[MAX_PATH] = {};
        if (GetModuleFileNameW(nullptr, selfExe, MAX_PATH) > 0) {
            std::wstring dstExe = dstDir + L"\\VieLotusSettings.exe";
            if (!CopyFileW(selfExe, dstExe.c_str(), FALSE)) {
                std::wstring oldExe = dstDir + L"\\VieLotusSettings.old.exe";
                DeleteFileW(oldExe.c_str());
                MoveFileExW(dstExe.c_str(), oldExe.c_str(), MOVEFILE_REPLACE_EXISTING);
                CopyFileW(selfExe, dstExe.c_str(), FALSE);
            }
        }
        std::wstring srcIco = srcDir + L"\\VieLotusIM.ico";
        std::wstring dstIco = dstDir + L"\\VieLotusIM.ico";
        CopyFileW(srcIco.c_str(), dstIco.c_str(), FALSE);
        CopyDirectoryPngAssets(srcDir + L"\\assets", dstDir + L"\\assets");
    }

    // Grant AppContainer Read & Execute permissions so UWP / WinUI 3 / Edge / Windows 11 Search can load VieLotusTIP.dll
    std::wstring icaclsArgs = L"\"" + dstDir + L"\" /grant \"*S-1-15-2-1:(OI)(CI)(RX)\" /grant \"*S-1-15-2-2:(OI)(CI)(RX)\" /T /C /Q";
    RunSystemToolWait(L"icacls.exe", icaclsArgs, 10000);

    HRESULT hr = E_FAIL;
    HMODULE hDll = LoadLibraryW(dstDll.c_str());
    if (hDll) {
        auto pfnReg = reinterpret_cast<PFN_DllRegisterServer>(GetProcAddress(hDll, "DllRegisterServer"));
        hr = pfnReg ? pfnReg() : E_FAIL;

        auto pfnAct = reinterpret_cast<PFN_RundllEntryW>(GetProcAddress(hDll, "ActivateUserProfilesW"));
        if (pfnAct) {
            pfnAct(nullptr, hDll, const_cast<LPWSTR>(L""), SW_HIDE);
        }
        FreeLibrary(hDll);
    } else {
        // Fallback when an x64 installer .exe runs under emulation on an ARM64 Windows OS
        // while dstDll is a native ARM64 DLL: invoke native system regsvr32.exe & rundll32.exe!
        std::wstring regArgs = L"/s \"" + dstDll + L"\"";
        if (RunSystemToolWait(L"regsvr32.exe", regArgs, 15000)) {
            hr = S_OK;
        }
        std::wstring actArgs = L"\"" + dstDll + L"\",ActivateUserProfilesW";
        RunSystemToolWait(L"rundll32.exe", actArgs, 15000);
    }

    HRESULT hrCo = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    vielotus_win_installer::RegisterWindowsInstalledAppAndShortcuts(dstDir);
    if (SUCCEEDED(hrCo)) {
        CoUninitialize();
    }

    ShellExecuteW(nullptr, L"open", L"ctfmon.exe", nullptr, nullptr, SW_HIDE);
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

static bool IsSetupExecutableInvocation(const std::wstring &cmdLine) {
    if (cmdLine.find(L"--settings") != std::wstring::npos || cmdLine.find(L"/settings") != std::wstring::npos ||
        cmdLine.find(L"--startup") != std::wstring::npos || cmdLine.find(L"/startup") != std::wstring::npos ||
        cmdLine.find(L"--tray") != std::wstring::npos || cmdLine.find(L"/tray") != std::wstring::npos) {
        return false;
    }
    if (cmdLine.find(L"--setup") != std::wstring::npos || cmdLine.find(L"/setup") != std::wstring::npos) {
        return true;
    }
    WCHAR exePath[MAX_PATH] = {};
    if (GetModuleFileNameW(nullptr, exePath, MAX_PATH) == 0) {
        return false;
    }
    const WCHAR *base = exePath;
    for (const WCHAR *p = exePath; *p; ++p) {
        if (*p == L'\\' || *p == L'/') {
            base = p + 1;
        }
    }
    std::wstring lowerBase(base);
    for (WCHAR &ch : lowerBase) {
        if (ch >= L'A' && ch <= L'Z') {
            ch = static_cast<WCHAR>(ch + (L'a' - L'A'));
        }
    }
    return (lowerBase.find(L"setup") != std::wstring::npos ||
            lowerBase.find(L"install") != std::wstring::npos) &&
           lowerBase.find(L"uninstall") == std::wstring::npos;
}

namespace {

enum {
    IDC_WIZ_BTN_INSTALL = 4001,
    IDC_WIZ_BTN_CANCEL  = 4002,
    IDC_WIZ_CHK_OPEN_UI = 4003,
    IDC_WIZ_EDIT_LOG    = 4004
};

struct SetupWizardState {
    HWND hWnd{nullptr};
    HWND hTitle{nullptr};
    HWND hSubTitle{nullptr};
    HWND hLogEdit{nullptr};
    HWND hChkOpenSettings{nullptr};
    HWND hBtnInstall{nullptr};
    HWND hBtnCancel{nullptr};
    HFONT hTitleFont{nullptr};
    HFONT hBodyFont{nullptr};
    HFONT hMonoFont{nullptr};
    bool installCompleted{false};
    bool openSettingsAfterFinish{true};
    bool userFinishedOk{false};
};

static void AppendWizardLog(HWND hEdit, const wchar_t *text) {
    if (!hEdit || !text) return;
    int len = GetWindowTextLengthW(hEdit);
    SendMessageW(hEdit, EM_SETSEL, static_cast<WPARAM>(len), static_cast<LPARAM>(len));
    SendMessageW(hEdit, EM_REPLACESEL, FALSE, reinterpret_cast<LPARAM>(text));
    SendMessageW(hEdit, EM_SCROLLCARET, 0, 0);
    UpdateWindow(hEdit);
}

static void ResetWinLangListCleanStamp() {
    HKEY hPrefs = nullptr;
    if (RegCreateKeyExW(
            HKEY_CURRENT_USER,
            L"Software\\VieLotusIM",
            0,
            nullptr,
            REG_OPTION_NON_VOLATILE,
            KEY_WRITE,
            nullptr,
            &hPrefs,
            nullptr
        ) == ERROR_SUCCESS && hPrefs) {
        DWORD zero = 0;
        RegSetValueExW(hPrefs, L"WinLangListCleanVer", 0, REG_DWORD, reinterpret_cast<const BYTE *>(&zero), sizeof(zero));
        RegCloseKey(hPrefs);
    }
}

static void ExecuteWizardInstallSteps(SetupWizardState *st) {
    if (!st || !st->hWnd) return;
    EnableWindow(st->hBtnInstall, FALSE);
    EnableWindow(st->hBtnCancel, FALSE);
    SetWindowTextW(st->hBtnInstall, L"\u0110ang c\u00E0i \u0111\u1EB7t...");
    SetWindowTextW(st->hLogEdit, L"");

    AppendWizardLog(st->hLogEdit, L"[1/4] Chu\u1EA9n b\u1ECB th\u01B0 m\u1EE5c C:\\Program Files\\VieLotusIM v\u00E0 ki\u1EC3m tra quy\u1EC1n Qu\u1EA3n tr\u1ECB (Administrator)...\r\n");

    ResetWinLangListCleanStamp();

    int provRes = 1;
    DWORD shellErr = 0;
    if (vielotus_win_installer::IsProcessElevated()) {
        provRes = PerformElevatedMsixTipProvisioning();
    } else {
        provRes = RunElevatedSelfCommand(L"--install-msix-ime", 45000, &shellErr);
    }

    if (provRes != 0) {
        WCHAR errBuf[256] = {};
        StringCchPrintfW(
            errBuf,
            256,
            L"\u2717 L\u1ED6I (code=%d, win32=%lu): Kh\u00F4ng th\u1EC3 c\u00E0i \u0111\u1EB7t t\u1EC7p h\u1EC7 th\u1ED1ng (Vui l\u00F2ng ch\u1EA5p nh\u1EADn h\u1ED9p tho\u1EA1i UAC Yes).\r\n",
            provRes,
            static_cast<unsigned long>(shellErr)
        );
        AppendWizardLog(st->hLogEdit, errBuf);
        SetWindowTextW(st->hBtnInstall, L"Th\u1EED l\u1EA1i C\u00E0i \u0111\u1EB7t");
        EnableWindow(st->hBtnInstall, TRUE);
        EnableWindow(st->hBtnCancel, TRUE);
        return;
    }

    AppendWizardLog(st->hLogEdit, L"[2/4] \u2713 \u0110\u00E3 tri\u1EC3n khai VieLotusTIP.dll (Pure TSF 64-bit) & VieLotusSettings.exe.\r\n");
    AppendWizardLog(st->hLogEdit, L"[3/4] \u2713 \u0110\u00E3 \u0111\u0103ng k\u00FD Windows Installed Apps (Add/Remove Programs) & Start Menu.\r\n");
    AppendWizardLog(st->hLogEdit, L"[4/4] \u0110ang d\u1ECDn d\u1EB9p b\u00E0n ph\u00EDm VIE-US th\u1EEBa v\u00E0 k\u00EDch ho\u1EA1t TSF \"Ti\u1EBFng Vi\u1EC7t (Sen Vi\u1EC7t - Telex)\" cho phi\u00EAn ng\u01B0\u1EDDi d\u00F9ng...\r\n");

    ResetWinLangListCleanStamp();

    std::wstring pfDll = GetProgramFilesInstallDir() + L"\\VieLotusTIP.dll";
    HMODULE hDll = LoadLibraryW(pfDll.c_str());
    if (hDll) {
        auto pfnAct = reinterpret_cast<PFN_RundllEntryW>(GetProcAddress(hDll, "ActivateUserProfilesW"));
        if (pfnAct) {
            pfnAct(st->hWnd, hDll, const_cast<LPWSTR>(L""), SW_HIDE);
        }
        FreeLibrary(hDll);
    } else {
        std::wstring actArgs = L"\"" + pfDll + L"\",ActivateUserProfilesW";
        RunSystemToolWait(L"rundll32.exe", actArgs, 15000);
    }

    AppendWizardLog(st->hLogEdit, L"\r\n\u2728 C\u00C0I \u0110\u1EB6T HO\u00C0N T\u1EA4T 100%! B\u1ED9 g\u00F5 Sen Vi\u1EC7t (Telex / VNI) \u0111\u00E3 s\u1EB5n s\u00E0ng tr\u00EAn m\u1ECDi \u1EE9ng d\u1EE5ng Windows.\r\n");
    st->installCompleted = true;
    SetWindowTextW(st->hBtnInstall, L"Ho\u00E0n t\u1EA5t \u2713");
    EnableWindow(st->hBtnInstall, TRUE);
    SetFocus(st->hBtnInstall);
}

static LRESULT CALLBACK SetupWizardWndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    SetupWizardState *st = reinterpret_cast<SetupWizardState *>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
    switch (msg) {
    case WM_CREATE: {
        CREATESTRUCTW *cs = reinterpret_cast<CREATESTRUCTW *>(lParam);
        st = reinterpret_cast<SetupWizardState *>(cs->lpCreateParams);
        SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(st));
        st->hWnd = hwnd;

        HDC hdc = GetDC(hwnd);
        int dpiY = GetDeviceCaps(hdc, LOGPIXELSY);
        ReleaseDC(hwnd, hdc);
        float s = static_cast<float>(dpiY) / 96.0f;

        st->hTitleFont = CreateFontW(-MulDiv(15, dpiY, 72), 0, 0, 0, FW_BOLD, FALSE, FALSE, FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");
        st->hBodyFont = CreateFontW(-MulDiv(10, dpiY, 72), 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");
        st->hMonoFont = CreateFontW(-MulDiv(9, dpiY, 72), 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY, FIXED_PITCH | FF_MODERN, L"Consolas");

        int pad = static_cast<int>(18 * s);
        int w = static_cast<int>(540 * s);

        st->hTitle = CreateWindowExW(
            0, L"STATIC",
            L"Tr\u00ECnh C\u00E0i \u0110\u1EB7t Sen Vi\u1EC7t (VieLotusIM) v2.0.2",
            WS_CHILD | WS_VISIBLE,
            pad, pad, w, static_cast<int>(28 * s),
            hwnd, nullptr, cs->hInstance, nullptr
        );
        SendMessageW(st->hTitle, WM_SETFONT, reinterpret_cast<WPARAM>(st->hTitleFont), TRUE);

        st->hSubTitle = CreateWindowExW(
            0, L"STATIC",
            L"B\u1ED9 g\u00F5 Ti\u1EBFng Vi\u1EC7t th\u1EBF h\u1EC7 m\u1EDBi (Pure TSF 64-bit \u2022 Song ng\u1EEF Anh-Vi\u1EC7t Th\u00F4ng minh)\r\n"
            L"Th\u01B0 m\u1EE5c \u0111\u00EDch: C:\\Program Files\\VieLotusIM",
            WS_CHILD | WS_VISIBLE,
            pad, pad + static_cast<int>(32 * s), w, static_cast<int>(40 * s),
            hwnd, nullptr, cs->hInstance, nullptr
        );
        SendMessageW(st->hSubTitle, WM_SETFONT, reinterpret_cast<WPARAM>(st->hBodyFont), TRUE);

        st->hLogEdit = CreateWindowExW(
            WS_EX_CLIENTEDGE, L"EDIT",
            L"Nh\u1EA5n \"C\u00E0i \u0111\u1EB7t ngay\" \u0111\u1EC3 c\u00E0i \u0111\u1EB7t ho\u1EB7c c\u1EADp nh\u1EADt Sen Vi\u1EC7t (VieLotusIM) v\u00E0o Windows:\r\n"
            L"  \u2022 C\u00E0i \u0111\u1EB7t nh\u00E2n VieLotusTIP.dll v\u00E0o C:\\Program Files\\VieLotusIM\r\n"
            L"  \u2022 D\u1ECDn s\u1EA1ch b\u00E0n ph\u00EDm VIE-US / ENG th\u1EEBa tr\u00EAn thanh Win + Spacebar\r\n"
            L"  \u2022 K\u00EDch ho\u1EA1t \"Ti\u1EBFng Vi\u1EC7t (Sen Vi\u1EC7t - Telex)\" tr\u00EAn to\u00E0n b\u1ED9 \u1EE9ng d\u1EE5ng\r\n"
            L"  \u2022 \u0110\u0103ng k\u00FD v\u00E0o Windows Installed Apps (h\u1ED7 tr\u1EE3 G\u1EE1 c\u00E0i \u0111\u1EB7t ch\u00EDnh th\u1ED1ng)\r\n",
            WS_CHILD | WS_VISIBLE | WS_VSCROLL | ES_MULTILINE | ES_AUTOVSCROLL | ES_READONLY,
            pad, pad + static_cast<int>(78 * s), w, static_cast<int>(165 * s),
            hwnd, reinterpret_cast<HMENU>(static_cast<INT_PTR>(IDC_WIZ_EDIT_LOG)), cs->hInstance, nullptr
        );
        SendMessageW(st->hLogEdit, WM_SETFONT, reinterpret_cast<WPARAM>(st->hMonoFont), TRUE);

        st->hChkOpenSettings = CreateWindowExW(
            0, L"BUTTON",
            L"M\u1EDF B\u1EA3ng \u0110i\u1EC1u Khi\u1EC3n Sen Vi\u1EC7t sau khi c\u00E0i \u0111\u1EB7t ho\u00E0n t\u1EA5t",
            WS_CHILD | WS_VISIBLE | BS_AUTOCHECKBOX | WS_TABSTOP,
            pad, pad + static_cast<int>(254 * s), w, static_cast<int>(24 * s),
            hwnd, reinterpret_cast<HMENU>(static_cast<INT_PTR>(IDC_WIZ_CHK_OPEN_UI)), cs->hInstance, nullptr
        );
        SendMessageW(st->hChkOpenSettings, WM_SETFONT, reinterpret_cast<WPARAM>(st->hBodyFont), TRUE);
        SendMessageW(st->hChkOpenSettings, BM_SETCHECK, BST_CHECKED, 0);

        int btnW = static_cast<int>(150 * s);
        int btnH = static_cast<int>(36 * s);
        int btnY = pad + static_cast<int>(290 * s);

        st->hBtnInstall = CreateWindowExW(
            0, L"BUTTON",
            L"C\u00E0i \u0111\u1EB7t ngay",
            WS_CHILD | WS_VISIBLE | BS_DEFPUSHBUTTON | WS_TABSTOP,
            pad + w - btnW * 2 - static_cast<int>(10 * s), btnY, btnW, btnH,
            hwnd, reinterpret_cast<HMENU>(static_cast<INT_PTR>(IDC_WIZ_BTN_INSTALL)), cs->hInstance, nullptr
        );
        SendMessageW(st->hBtnInstall, WM_SETFONT, reinterpret_cast<WPARAM>(st->hBodyFont), TRUE);

        st->hBtnCancel = CreateWindowExW(
            0, L"BUTTON",
            L"\u0110\u00F3ng",
            WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON | WS_TABSTOP,
            pad + w - btnW, btnY, btnW, btnH,
            hwnd, reinterpret_cast<HMENU>(static_cast<INT_PTR>(IDC_WIZ_BTN_CANCEL)), cs->hInstance, nullptr
        );
        SendMessageW(st->hBtnCancel, WM_SETFONT, reinterpret_cast<WPARAM>(st->hBodyFont), TRUE);
        return 0;
    }

    case WM_COMMAND: {
        int id = LOWORD(wParam);
        if (id == IDC_WIZ_BTN_INSTALL && st) {
            if (!st->installCompleted) {
                ExecuteWizardInstallSteps(st);
            } else {
                st->openSettingsAfterFinish = (SendMessageW(st->hChkOpenSettings, BM_GETCHECK, 0, 0) == BST_CHECKED);
                st->userFinishedOk = true;
                DestroyWindow(hwnd);
            }
            return 0;
        }
        if (id == IDC_WIZ_BTN_CANCEL && st) {
            st->userFinishedOk = false;
            DestroyWindow(hwnd);
            return 0;
        }
        break;
    }

    case WM_CLOSE:
        DestroyWindow(hwnd);
        return 0;

    case WM_DESTROY:
        if (st) {
            if (st->hTitleFont) DeleteObject(st->hTitleFont);
            if (st->hBodyFont) DeleteObject(st->hBodyFont);
            if (st->hMonoFont) DeleteObject(st->hMonoFont);
        }
        PostQuitMessage(0);
        return 0;
    }
    return DefWindowProcW(hwnd, msg, wParam, lParam);
}

static bool RunInteractiveSetupWizard(HINSTANCE hInstance, bool &outOpenSettings) {
    outOpenSettings = false;
    SetupWizardState st{};

    WNDCLASSEXW wc{};
    wc.cbSize = sizeof(wc);
    wc.style = CS_HREDRAW | CS_VREDRAW;
    wc.lpfnWndProc = SetupWizardWndProc;
    wc.hInstance = hInstance;
    wc.hIcon = LoadIconW(hInstance, MAKEINTRESOURCEW(101));
    wc.hCursor = LoadCursorW(nullptr, MAKEINTRESOURCEW(32512)); // IDC_ARROW
    wc.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW);
    wc.lpszClassName = L"VieLotusSetupWizardWndClass";
    wc.hIconSm = wc.hIcon;
    RegisterClassExW(&wc);

    HDC hdc = GetDC(nullptr);
    int dpiY = GetDeviceCaps(hdc, LOGPIXELSY);
    int screenW = GetSystemMetrics(SM_CXSCREEN);
    int screenH = GetSystemMetrics(SM_CYSCREEN);
    ReleaseDC(nullptr, hdc);

    int clientW = MulDiv(576, dpiY, 96);
    int clientH = MulDiv(346, dpiY, 96);
    DWORD dwStyle = WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX | WS_VISIBLE;
    RECT rc = { 0, 0, clientW, clientH };
    AdjustWindowRectEx(&rc, dwStyle, FALSE, WS_EX_APPWINDOW);
    int winW = rc.right - rc.left;
    int winH = rc.bottom - rc.top;
    int posX = (screenW > winW) ? (screenW - winW) / 2 : 80;
    int posY = (screenH > winH) ? (screenH - winH) / 2 : 80;

    HWND hwnd = CreateWindowExW(
        WS_EX_APPWINDOW,
        L"VieLotusSetupWizardWndClass",
        L"Tr\u00ECnh C\u00E0i \u0110\u1EB7t Sen Vi\u1EC7t (VieLotusIM) v2.0.2",
        dwStyle,
        posX, posY, winW, winH,
        nullptr, nullptr, hInstance, &st
    );
    if (!hwnd) return false;

    ShowWindow(hwnd, SW_SHOW);
    UpdateWindow(hwnd);
    SetForegroundWindow(hwnd);

    MSG msg{};
    while (GetMessageW(&msg, nullptr, 0, 0) > 0) {
        if (!IsDialogMessageW(hwnd, &msg)) {
            TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }
    }

    outOpenSettings = st.userFinishedOk && st.openSettingsAfterFinish;
    return st.userFinishedOk;
}

} // namespace

int WINAPI wWinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, PWSTR lpCmdLine, int nCmdShow) {
    (void)hPrevInstance;
    EnablePerMonitorDpiAwareness();

    std::wstring cmdLine = lpCmdLine ? lpCmdLine : L"";
    if (cmdLine.find(L"--uninstall") != std::wstring::npos || cmdLine.find(L"/uninstall") != std::wstring::npos) {
        bool quiet = (cmdLine.find(L"--quiet") != std::wstring::npos ||
                      cmdLine.find(L"/quiet") != std::wstring::npos ||
                      cmdLine.find(L"/S") != std::wstring::npos);
        return vielotus_win_installer::RunFullUninstallFlow(quiet);
    }
    if (cmdLine.find(L"--install-msix-ime") != std::wstring::npos) {
        return PerformElevatedMsixTipProvisioning();
    }
    if (cmdLine.find(L"--silent") != std::wstring::npos ||
        cmdLine.find(L"/silent") != std::wstring::npos ||
        cmdLine.find(L"/SILENT") != std::wstring::npos ||
        cmdLine.find(L"/verysilent") != std::wstring::npos ||
        cmdLine.find(L"/VERYSILENT") != std::wstring::npos ||
        cmdLine.find(L"--quiet") != std::wstring::npos ||
        cmdLine.find(L"/quiet") != std::wstring::npos ||
        cmdLine.find(L"/S") != std::wstring::npos) {
        if (vielotus_win_installer::IsProcessElevated()) {
            return PerformElevatedMsixTipProvisioning();
        }
        return RunElevatedSelfCommand(L"--install-msix-ime", 60000);
    }

    const bool isStartupMode = (cmdLine.find(L"--startup") != std::wstring::npos ||
                                cmdLine.find(L"/startup") != std::wstring::npos ||
                                cmdLine.find(L"--tray") != std::wstring::npos ||
                                cmdLine.find(L"/tray") != std::wstring::npos);

    // If invoked as VieLotus-Setup-*.exe (or with --setup), run the interactive Setup Wizard UI
    if (!isStartupMode &&
        IsSetupExecutableInvocation(cmdLine) &&
        cmdLine.find(L"--activate") == std::wstring::npos &&
        cmdLine.find(L"/activate") == std::wstring::npos &&
        cmdLine.find(L"--deactivate") == std::wstring::npos &&
        cmdLine.find(L"/deactivate") == std::wstring::npos) {
        bool openSettings = false;
        if (!RunInteractiveSetupWizard(hInstance, openSettings)) {
            return 0;
        }
        std::wstring installedExe = GetProgramFilesInstallDir() + L"\\VieLotusSettings.exe";
        if (GetFileAttributesW(installedExe.c_str()) != INVALID_FILE_ATTRIBUTES) {
            ShellExecuteW(
                nullptr,
                L"open",
                installedExe.c_str(),
                openSettings ? L"--settings" : L"--startup",
                GetProgramFilesInstallDir().c_str(),
                openSettings ? SW_SHOWNORMAL : SW_HIDE
            );
            return 0;
        }
        if (!openSettings) {
            return 0;
        }
    }

    std::wstring exeDir = GetExecutableDir();
    std::wstring localDll = exeDir + L"\\VieLotusTIP.dll";
    std::wstring pfDll = GetProgramFilesInstallDir() + L"\\VieLotusTIP.dll";

    // If launched interactively (never during silent --startup at Windows login) before HKLM TSF registration
    // or after an MSIX Store update, elevate once to provision %ProgramFiles%\VieLotusIM\VieLotusTIP.dll.
    if (!isStartupMode && !IsTipRegisteredAndUpToDate(localDll)) {
        if (vielotus_win_installer::IsProcessElevated()) {
            PerformElevatedMsixTipProvisioning();
        } else {
            RunElevatedSelfCommand(L"--install-msix-ime", 30000);
        }
    }

    HMODULE hDll = LoadLibraryW(pfDll.c_str());
    if (!hDll && GetFileAttributesW(pfDll.c_str()) != INVALID_FILE_ATTRIBUTES) {
        if (cmdLine.find(L"--activate") != std::wstring::npos || cmdLine.find(L"/activate") != std::wstring::npos) {
            RunSystemToolWait(L"rundll32.exe", L"\"" + pfDll + L"\",ActivateUserProfilesW", 15000);
            return 0;
        }
        if (cmdLine.find(L"--deactivate") != std::wstring::npos || cmdLine.find(L"/deactivate") != std::wstring::npos) {
            RunSystemToolWait(L"rundll32.exe", L"\"" + pfDll + L"\",DeactivateUserProfilesW", 15000);
            return 0;
        }
        RunSystemToolWait(L"rundll32.exe", L"\"" + pfDll + L"\",ActivateUserProfilesW", 15000);
        if (!isStartupMode) {
            RunSystemToolWait(L"rundll32.exe", L"\"" + pfDll + L"\",ShowSettingsDialogW", INFINITE);
        }
        return 0;
    }
    if (!hDll) {
        hDll = LoadLibraryW(localDll.c_str());
    }
    if (!hDll) {
        if (!isStartupMode) {
            MessageBoxW(
                nullptr,
                L"Kh\u00F4ng t\u00ECm th\u1EA5y t\u1EC7p nh\u00E2n b\u1ED9 g\u00F5 VieLotusTIP.dll.",
                L"Sen Vi\u1EC7t (VieLotusIM)",
                MB_ICONERROR | MB_OK
            );
        }
        return isStartupMode ? 0 : 1;
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

    // Ensure current user profile has saved Telex/VNI enabled in Windows Language Bar
    auto pfnAct = reinterpret_cast<PFN_RundllEntryW>(GetProcAddress(hDll, "ActivateUserProfilesW"));
    if (pfnAct) {
        pfnAct(nullptr, hDll, const_cast<LPWSTR>(L""), SW_HIDE);
    }

    auto pfnShow = reinterpret_cast<PFN_RundllEntryW>(GetProcAddress(hDll, "ShowSettingsDialogW"));
    if (pfnShow) {
        pfnShow(nullptr, hInstance, lpCmdLine, isStartupMode ? SW_HIDE : nCmdShow);
    }

    FreeLibrary(hDll);
    return 0;
}
