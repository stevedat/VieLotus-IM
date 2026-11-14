#pragma once

#include <windows.h>
#include <shellapi.h>
#include <shlobj.h>
#include <objbase.h>
#include <shobjidl.h>
#include <shlguid.h>
#include <strsafe.h>
#include <string>
#include <vector>

namespace vielotus_win_installer {

static constexpr const wchar_t *kUninstallRegSubKey =
    L"SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\VieLotusIM";
static constexpr const wchar_t *kLegacyInnoUninstallRegSubKey =
    L"SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\{8E2A7B44-5A1F-4B82-9B7C-123456789ABC}_is1";
static constexpr const wchar_t *kTipClsidInprocSubKey =
    L"SOFTWARE\\Classes\\CLSID\\{C7B08E9D-4762-4C97-8B1F-522197A598DE}\\InprocServer32";
static constexpr const wchar_t *kTipClsidRootSubKey =
    L"SOFTWARE\\Classes\\CLSID\\{C7B08E9D-4762-4C97-8B1F-522197A598DE}";
static constexpr const wchar_t *kLegacyTipClsidInprocSubKey =
    L"SOFTWARE\\Classes\\CLSID\\{C7B08E9D-4762-4C97-8B1F-522197A598DC}\\InprocServer32";
static constexpr const wchar_t *kLegacyTipClsidRootSubKey =
    L"SOFTWARE\\Classes\\CLSID\\{C7B08E9D-4762-4C97-8B1F-522197A598DC}";
static constexpr const wchar_t *kLegacy2TipClsidInprocSubKey =
    L"SOFTWARE\\Classes\\CLSID\\{C7B08E9D-4762-4C97-8B1F-522197A598DD}\\InprocServer32";
static constexpr const wchar_t *kLegacy2TipClsidRootSubKey =
    L"SOFTWARE\\Classes\\CLSID\\{C7B08E9D-4762-4C97-8B1F-522197A598DD}";

inline std::wstring GetInstallDir() {
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

inline bool IsProcessElevated() {
    BOOL isMember = FALSE;
    PSID adminGroup = nullptr;
    SID_IDENTIFIER_AUTHORITY ntAuthority = SECURITY_NT_AUTHORITY;
    if (AllocateAndInitializeSid(
            &ntAuthority, 2,
            SECURITY_BUILTIN_DOMAIN_RID,
            DOMAIN_ALIAS_RID_ADMINS,
            0, 0, 0, 0, 0, 0,
            &adminGroup)) {
        if (!CheckTokenMembership(nullptr, adminGroup, &isMember)) {
            isMember = FALSE;
        }
        FreeSid(adminGroup);
    }
    return isMember != FALSE;
}

inline bool IsUninstallEntryRegistered() {
    HKEY hKey = nullptr;
    if (RegOpenKeyExW(
            HKEY_LOCAL_MACHINE,
            kUninstallRegSubKey,
            0,
            KEY_READ | KEY_WOW64_64KEY,
            &hKey
        ) != ERROR_SUCCESS || !hKey) {
        return false;
    }
    WCHAR uninstallCmd[MAX_PATH * 2] = {};
    DWORD cb = sizeof(uninstallCmd);
    DWORD type = 0;
    bool ok = (RegQueryValueExW(hKey, L"UninstallString", nullptr, &type, reinterpret_cast<LPBYTE>(uninstallCmd), &cb) == ERROR_SUCCESS &&
               uninstallCmd[0] != L'\0');
    RegCloseKey(hKey);
    if (!ok) return false;

    std::wstring uninstExe = GetInstallDir() + L"\\Uninstall-VieLotusIM.exe";
    DWORD attrs = GetFileAttributesW(uninstExe.c_str());
    return (attrs != INVALID_FILE_ATTRIBUTES && !(attrs & FILE_ATTRIBUTE_DIRECTORY));
}

inline void CloseRunningSettingsAndTrayWindow() {
    HWND hFb = FindWindowW(L"VieLotusFeedbackDialogWndClass", nullptr);
    if (hFb && IsWindow(hFb)) {
        SendMessageTimeoutW(hFb, WM_CLOSE, 0, 0, SMTO_ABORTIFHUNG, 1500, nullptr);
    }
    HWND hWnd = FindWindowW(L"VieLotusBentoSettingsWndClass", nullptr);
    if (hWnd && IsWindow(hWnd)) {
        SendMessageTimeoutW(hWnd, WM_USER + 199, 0, 0, SMTO_ABORTIFHUNG, 2000, nullptr);
        Sleep(150);
    }
}

inline bool ExtractRcDataToFile(int resourceId, const std::wstring &dstPath) {
    HMODULE hMod = GetModuleHandleW(nullptr);
    HRSRC hRes = FindResourceW(hMod, MAKEINTRESOURCEW(resourceId), MAKEINTRESOURCEW(10) /* RT_RCDATA */);
    if (!hRes) return false;
    DWORD sz = SizeofResource(hMod, hRes);
    if (sz == 0) return false;
    HGLOBAL hLoad = LoadResource(hMod, hRes);
    if (!hLoad) return false;
    const void *pData = LockResource(hLoad);
    if (!pData) return false;
    HANDLE hFile = CreateFileW(dstPath.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (hFile == INVALID_HANDLE_VALUE) return false;
    DWORD written = 0;
    BOOL ok = WriteFile(hFile, pData, sz, &written, nullptr);
    CloseHandle(hFile);
    return (ok && written == sz);
}

inline void CreateShortcutLink(
    const std::wstring &shortcutPath,
    const std::wstring &targetPath,
    const std::wstring &arguments,
    const std::wstring &workingDir,
    const std::wstring &description,
    const std::wstring &iconPath = L""
) {
    IShellLinkW *pLink = nullptr;
    if (SUCCEEDED(CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER, IID_IShellLinkW, reinterpret_cast<void **>(&pLink))) && pLink) {
        pLink->SetPath(targetPath.c_str());
        if (!arguments.empty()) {
            pLink->SetArguments(arguments.c_str());
        }
        if (!workingDir.empty()) {
            pLink->SetWorkingDirectory(workingDir.c_str());
        }
        if (!description.empty()) {
            pLink->SetDescription(description.c_str());
        }
        if (!iconPath.empty() && GetFileAttributesW(iconPath.c_str()) != INVALID_FILE_ATTRIBUTES) {
            pLink->SetIconLocation(iconPath.c_str(), 0);
        } else {
            pLink->SetIconLocation(targetPath.c_str(), 0);
        }

        IPersistFile *pPersist = nullptr;
        if (SUCCEEDED(pLink->QueryInterface(IID_IPersistFile, reinterpret_cast<void **>(&pPersist))) && pPersist) {
            pPersist->Save(shortcutPath.c_str(), TRUE);
            pPersist->Release();
        }
        pLink->Release();
    }
}

inline void RegisterWindowsInstalledAppAndShortcuts(const std::wstring &installDir) {
    std::wstring uninstallerExe = installDir + L"\\Uninstall-VieLotusIM.exe";
    std::wstring settingsExe = installDir + L"\\VieLotusSettings.exe";
    std::wstring icoFile = installDir + L"\\VieLotusIM.ico";
    std::wstring assetsDir = installDir + L"\\assets";
    CreateDirectoryW(assetsDir.c_str(), nullptr);

    // Always extract embedded VieLotusIM.ico (resource 103) and app-icon-128x128.png (resource 102)
    ExtractRcDataToFile(103, icoFile);
    ExtractRcDataToFile(102, assetsDir + L"\\app-icon-128x128.png");

    WCHAR selfPath[MAX_PATH] = {};
    if (GetModuleFileNameW(nullptr, selfPath, MAX_PATH) > 0) {
        CopyFileW(selfPath, uninstallerExe.c_str(), FALSE);
        if (GetFileAttributesW(settingsExe.c_str()) == INVALID_FILE_ATTRIBUTES) {
            CopyFileW(selfPath, settingsExe.c_str(), FALSE);
        }
    }

    std::wstring iconExe = (GetFileAttributesW(settingsExe.c_str()) != INVALID_FILE_ATTRIBUTES)
                               ? settingsExe
                               : uninstallerExe;
    std::wstring displayIcon = (GetFileAttributesW(icoFile.c_str()) != INVALID_FILE_ATTRIBUTES)
                                   ? icoFile
                                   : (iconExe + L",0");
    std::wstring uninstallCmd = L"\"" + uninstallerExe + L"\" --uninstall";
    std::wstring quietUninstallCmd = L"\"" + uninstallerExe + L"\" --uninstall --quiet";
    std::wstring modifyCmd = L"\"" + iconExe + L"\" --settings";

    // Remove legacy Inno Setup key if present to avoid duplicate entries in Installed Apps
    RegDeleteKeyExW(HKEY_LOCAL_MACHINE, kLegacyInnoUninstallRegSubKey, KEY_WOW64_64KEY, 0);

    HKEY hKey = nullptr;
    if (RegCreateKeyExW(
            HKEY_LOCAL_MACHINE,
            kUninstallRegSubKey,
            0,
            nullptr,
            REG_OPTION_NON_VOLATILE,
            KEY_WRITE | KEY_WOW64_64KEY,
            nullptr,
            &hKey,
            nullptr
        ) == ERROR_SUCCESS && hKey) {
        static const WCHAR kDisplayName[] = L"Sen Vi\u1EC7t (VieLotusIM) \u2014 B\u1ED9 g\u00F5 Ti\u1EBFng Vi\u1EC7t";
        static const WCHAR kDisplayVersion[] = L"2.0.3";
        static const WCHAR kPublisher[] = L"Sen Vi\u1EC7t (VieLotusIM)";
        static const WCHAR kUrlInfo[] = L"https://github.com/stevedat/VieLotus-IM";

        RegSetValueExW(hKey, L"DisplayName", 0, REG_SZ, reinterpret_cast<const BYTE *>(kDisplayName), static_cast<DWORD>(sizeof(kDisplayName)));
        RegSetValueExW(hKey, L"DisplayVersion", 0, REG_SZ, reinterpret_cast<const BYTE *>(kDisplayVersion), static_cast<DWORD>(sizeof(kDisplayVersion)));
        RegSetValueExW(hKey, L"Publisher", 0, REG_SZ, reinterpret_cast<const BYTE *>(kPublisher), static_cast<DWORD>(sizeof(kPublisher)));
        RegSetValueExW(hKey, L"URLInfoAbout", 0, REG_SZ, reinterpret_cast<const BYTE *>(kUrlInfo), static_cast<DWORD>(sizeof(kUrlInfo)));
        RegSetValueExW(hKey, L"DisplayIcon", 0, REG_SZ, reinterpret_cast<const BYTE *>(displayIcon.c_str()), static_cast<DWORD>((displayIcon.size() + 1) * sizeof(WCHAR)));
        RegSetValueExW(hKey, L"InstallLocation", 0, REG_SZ, reinterpret_cast<const BYTE *>(installDir.c_str()), static_cast<DWORD>((installDir.size() + 1) * sizeof(WCHAR)));
        RegSetValueExW(hKey, L"UninstallString", 0, REG_SZ, reinterpret_cast<const BYTE *>(uninstallCmd.c_str()), static_cast<DWORD>((uninstallCmd.size() + 1) * sizeof(WCHAR)));
        RegSetValueExW(hKey, L"QuietUninstallString", 0, REG_SZ, reinterpret_cast<const BYTE *>(quietUninstallCmd.c_str()), static_cast<DWORD>((quietUninstallCmd.size() + 1) * sizeof(WCHAR)));
        RegSetValueExW(hKey, L"ModifyPath", 0, REG_SZ, reinterpret_cast<const BYTE *>(modifyCmd.c_str()), static_cast<DWORD>((modifyCmd.size() + 1) * sizeof(WCHAR)));

        DWORD one = 1;
        DWORD estimatedSizeKb = 9600;
        RegSetValueExW(hKey, L"NoModify", 0, REG_DWORD, reinterpret_cast<const BYTE *>(&one), sizeof(one));
        RegSetValueExW(hKey, L"NoRepair", 0, REG_DWORD, reinterpret_cast<const BYTE *>(&one), sizeof(one));
        RegSetValueExW(hKey, L"EstimatedSize", 0, REG_DWORD, reinterpret_cast<const BYTE *>(&estimatedSizeKb), sizeof(estimatedSizeKb));

        SYSTEMTIME st{};
        GetLocalTime(&st);
        WCHAR dateBuf[16] = {};
        StringCchPrintfW(dateBuf, 16, L"%04u%02u%02u", st.wYear, st.wMonth, st.wDay);
        RegSetValueExW(hKey, L"InstallDate", 0, REG_SZ, reinterpret_cast<const BYTE *>(dateBuf), static_cast<DWORD>((wcslen(dateBuf) + 1) * sizeof(WCHAR)));

        RegCloseKey(hKey);
    }

    // Create Start Menu Program Group & Shortcuts
    WCHAR commonProgs[MAX_PATH] = {};
    if (SUCCEEDED(SHGetFolderPathW(nullptr, CSIDL_COMMON_PROGRAMS, nullptr, 0, commonProgs)) && commonProgs[0] != L'\0') {
        std::wstring groupDir = std::wstring(commonProgs) + L"\\Sen Vi\u1EC7t (VieLotusIM)";
        CreateDirectoryW(groupDir.c_str(), nullptr);
        CreateShortcutLink(
            groupDir + L"\\C\u00E0i \u0111\u1EB7t Sen Vi\u1EC7t (VieLotusIM).lnk",
            iconExe,
            L"--settings",
            installDir,
            L"M\u1EDF b\u1EA3ng \u0111i\u1EC1u khi\u1EC3n b\u1ED9 g\u00F5 Ti\u1EBFng Vi\u1EC7t Sen Vi\u1EC7t",
            icoFile
        );
        CreateShortcutLink(
            groupDir + L"\\G\u1EE1 c\u00E0i \u0111\u1EB7t Sen Vi\u1EC7t (VieLotusIM).lnk",
            uninstallerExe,
            L"--uninstall",
            installDir,
            L"G\u1EE1 c\u00E0i \u0111\u1EB7t b\u1ED9 g\u00F5 Sen Vi\u1EC7t (VieLotusIM)",
            icoFile
        );
    }

    SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, nullptr, nullptr);
}

inline int RunFullUninstallFlow(bool quiet) {
    if (!IsProcessElevated()) {
        WCHAR selfPath[MAX_PATH] = {};
        if (GetModuleFileNameW(nullptr, selfPath, MAX_PATH) == 0) return 1;
        SHELLEXECUTEINFOW sei{};
        sei.cbSize = sizeof(sei);
        sei.fMask = SEE_MASK_NOCLOSEPROCESS;
        sei.lpVerb = L"runas";
        sei.lpFile = selfPath;
        sei.lpParameters = quiet ? L"--uninstall --quiet" : L"--uninstall";
        sei.nShow = SW_SHOWNORMAL;
        if (ShellExecuteExW(&sei) && sei.hProcess) {
            WaitForSingleObject(sei.hProcess, 60000);
            DWORD exitCode = 0;
            GetExitCodeProcess(sei.hProcess, &exitCode);
            CloseHandle(sei.hProcess);
            return static_cast<int>(exitCode);
        }
        return 1;
    }

    if (!quiet) {
        int ans = MessageBoxW(
            nullptr,
            L"B\u1EA1n c\u00F3 ch\u1EAFc ch\u1EAFn mu\u1ED1n g\u1EE1 c\u00E0i \u0111\u1EB7t b\u1ED9 g\u00F5 Ti\u1EBFng Vi\u1EC7t Sen Vi\u1EC7t (VieLotusIM) kh\u1ECFi m\u00E1y t\u00EDnh kh\u00F4ng?",
            L"G\u1EE1 c\u00E0i \u0111\u1EB7t Sen Vi\u1EC7t (VieLotusIM)",
            MB_ICONQUESTION | MB_YESNO | MB_DEFBUTTON2 | MB_SETFOREGROUND
        );
        if (ans != IDYES) {
            return 0;
        }
    }

    CloseRunningSettingsAndTrayWindow();

    HRESULT hrCo = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

    // 1. Switch current keyboard layout back to US English (0x04090409)
    HKL hklUS = LoadKeyboardLayoutW(L"00000409", KLF_ACTIVATE);
    if (hklUS) {
        ActivateKeyboardLayout(hklUS, KLF_SETFORPROCESS);
    }

    // 2. Unregister TSF profiles and COM server
    std::wstring installDir = GetInstallDir();
    std::wstring tipDll = installDir + L"\\VieLotusTIP.dll";
    HMODULE hDll = LoadLibraryW(tipDll.c_str());
    if (hDll) {
        using PFN_RundllEntryW = void(CALLBACK *)(HWND, HINSTANCE, LPWSTR, int);
        using PFN_DllUnregisterServer = HRESULT(STDAPICALLTYPE *)(void);
        auto pfnDeact = reinterpret_cast<PFN_RundllEntryW>(GetProcAddress(hDll, "DeactivateUserProfilesW"));
        if (pfnDeact) {
            pfnDeact(nullptr, hDll, const_cast<LPWSTR>(L""), SW_HIDE);
        }
        auto pfnUnreg = reinterpret_cast<PFN_DllUnregisterServer>(GetProcAddress(hDll, "DllUnregisterServer"));
        if (pfnUnreg) {
            pfnUnreg();
        }
        FreeLibrary(hDll);
    }

    // 3. Clean up HKLM & HKCU Registry entries
    RegDeleteKeyExW(HKEY_LOCAL_MACHINE, kTipClsidInprocSubKey, KEY_WOW64_64KEY, 0);
    RegDeleteKeyExW(HKEY_LOCAL_MACHINE, kTipClsidRootSubKey, KEY_WOW64_64KEY, 0);
    RegDeleteKeyExW(HKEY_LOCAL_MACHINE, kLegacyTipClsidInprocSubKey, KEY_WOW64_64KEY, 0);
    RegDeleteKeyExW(HKEY_LOCAL_MACHINE, kLegacyTipClsidRootSubKey, KEY_WOW64_64KEY, 0);
    RegDeleteKeyExW(HKEY_LOCAL_MACHINE, kLegacy2TipClsidInprocSubKey, KEY_WOW64_64KEY, 0);
    RegDeleteKeyExW(HKEY_LOCAL_MACHINE, kLegacy2TipClsidRootSubKey, KEY_WOW64_64KEY, 0);
    RegDeleteKeyExW(HKEY_LOCAL_MACHINE, kUninstallRegSubKey, KEY_WOW64_64KEY, 0);
    RegDeleteKeyExW(HKEY_LOCAL_MACHINE, kLegacyInnoUninstallRegSubKey, KEY_WOW64_64KEY, 0);

    HKEY hSubKey = nullptr;
    if (RegOpenKeyExW(HKEY_CURRENT_USER, L"Keyboard Layout\\Substitutes", 0, KEY_SET_VALUE, &hSubKey) == ERROR_SUCCESS && hSubKey) {
        RegDeleteValueW(hSubKey, L"0000042a");
        RegDeleteValueW(hSubKey, L"0000042A");
        RegCloseKey(hSubKey);
    }
    HKEY hRunKey = nullptr;
    if (RegOpenKeyExW(HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows\\CurrentVersion\\Run", 0, KEY_SET_VALUE, &hRunKey) == ERROR_SUCCESS && hRunKey) {
        RegDeleteValueW(hRunKey, L"VieLotusIM");
        RegCloseKey(hRunKey);
    }
    RegDeleteKeyW(HKEY_CURRENT_USER, L"Software\\VieLotusIM\\AppBypass");
    RegDeleteKeyW(HKEY_CURRENT_USER, L"Software\\VieLotusIM");

    // 4. Remove Start Menu & Desktop shortcuts
    WCHAR commonProgs[MAX_PATH] = {};
    if (SUCCEEDED(SHGetFolderPathW(nullptr, CSIDL_COMMON_PROGRAMS, nullptr, 0, commonProgs)) && commonProgs[0] != L'\0') {
        std::wstring groupDir = std::wstring(commonProgs) + L"\\Sen Vi\u1EC7t (VieLotusIM)";
        DeleteFileW((groupDir + L"\\C\u00E0i \u0111\u1EB7t Sen Vi\u1EC7t (VieLotusIM).lnk").c_str());
        DeleteFileW((groupDir + L"\\G\u1EE1 c\u00E0i \u0111\u1EB7t Sen Vi\u1EC7t (VieLotusIM).lnk").c_str());
        RemoveDirectoryW(groupDir.c_str());
        DeleteFileW((std::wstring(commonProgs) + L"\\Sen Vi\u1EC7t (VieLotusIM).lnk").c_str());
    }
    WCHAR commonDesktop[MAX_PATH] = {};
    if (SUCCEEDED(SHGetFolderPathW(nullptr, CSIDL_COMMON_DESKTOPDIRECTORY, nullptr, 0, commonDesktop)) && commonDesktop[0] != L'\0') {
        DeleteFileW((std::wstring(commonDesktop) + L"\\Sen Vi\u1EC7t (VieLotusIM).lnk").c_str());
    }

    // 5. Delete files in C:\Program Files\VieLotusIM (or schedule reboot removal for any locked DLL)
    std::wstring pattern = installDir + L"\\*";
    WIN32_FIND_DATAW fd{};
    HANDLE hFind = FindFirstFileW(pattern.c_str(), &fd);
    if (hFind != INVALID_HANDLE_VALUE) {
        do {
            if (wcscmp(fd.cFileName, L".") == 0 || wcscmp(fd.cFileName, L"..") == 0) continue;
            std::wstring fullPath = installDir + L"\\" + fd.cFileName;
            if (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) {
                std::wstring subPattern = fullPath + L"\\*";
                WIN32_FIND_DATAW subFd{};
                HANDLE hSub = FindFirstFileW(subPattern.c_str(), &subFd);
                if (hSub != INVALID_HANDLE_VALUE) {
                    do {
                        if (wcscmp(subFd.cFileName, L".") == 0 || wcscmp(subFd.cFileName, L"..") == 0) continue;
                        std::wstring subFile = fullPath + L"\\" + subFd.cFileName;
                        if (!DeleteFileW(subFile.c_str())) {
                            MoveFileExW(subFile.c_str(), nullptr, MOVEFILE_DELAY_UNTIL_REBOOT);
                        }
                    } while (FindNextFileW(hSub, &subFd));
                    FindClose(hSub);
                }
                if (!RemoveDirectoryW(fullPath.c_str())) {
                    MoveFileExW(fullPath.c_str(), nullptr, MOVEFILE_DELAY_UNTIL_REBOOT);
                }
            } else {
                if (!DeleteFileW(fullPath.c_str())) {
                    MoveFileExW(fullPath.c_str(), nullptr, MOVEFILE_DELAY_UNTIL_REBOOT);
                }
            }
        } while (FindNextFileW(hFind, &fd));
        FindClose(hFind);
    }
    if (!RemoveDirectoryW(installDir.c_str())) {
        MoveFileExW(installDir.c_str(), nullptr, MOVEFILE_DELAY_UNTIL_REBOOT);
    }

    // Spawn a short delayed cleanup command so Uninstall-VieLotusIM.exe itself is removed after process exit
    std::wstring cmdArgs = L"/c ping 127.0.0.1 -n 2 > nul & del /f /q \"" + installDir + L"\\*\" > nul 2>&1 & rmdir /s /q \"" + installDir + L"\" > nul 2>&1";
    SHELLEXECUTEINFOW seiClean{};
    seiClean.cbSize = sizeof(seiClean);
    seiClean.fMask = SEE_MASK_FLAG_NO_UI;
    seiClean.lpVerb = L"open";
    seiClean.lpFile = L"cmd.exe";
    seiClean.lpParameters = cmdArgs.c_str();
    seiClean.nShow = SW_HIDE;
    ShellExecuteExW(&seiClean);

    if (SUCCEEDED(hrCo)) {
        CoUninitialize();
    }

    if (!quiet) {
        MessageBoxW(
            nullptr,
            L"\u0110\u00E3 g\u1EE1 c\u00E0i \u0111\u1EB7t b\u1ED9 g\u00F5 Sen Vi\u1EC7t (VieLotusIM) kh\u1ECFi h\u1EC7 th\u1ED1ng th\u00E0nh c\u00F4ng.",
            L"G\u1EE1 c\u00E0i \u0111\u1EB7t Sen Vi\u1EC7t (VieLotusIM)",
            MB_ICONINFORMATION | MB_OK | MB_SETFOREGROUND
        );
    }
    return 0;
}

} // namespace vielotus_win_installer
