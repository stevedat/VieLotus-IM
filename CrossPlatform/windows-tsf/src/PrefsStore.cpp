#include "PrefsStore.h"
#include <atomic>
#include <cstring>

namespace {

const WCHAR c_szPrefsInputMethodVal[]      = L"InputMethod";
const WCHAR c_szPrefsVnEnabledVal[]        = L"VietnameseEnabled";
const WCHAR c_szPrefsSmartBilingualVal[]   = L"SmartBilingual";
const WCHAR c_szPrefsModernOrthoVal[]      = L"ModernOrthography";
const WCHAR c_szPrefsGrammarProfileVal[]   = L"SenFlexProfile";
const WCHAR c_szPrefsMacroEnabledVal[]     = L"MacroEnabled";
const WCHAR c_szPrefsDeveloperModeVal[]    = L"DeveloperMode";
const WCHAR c_szPrefsQuickTelexVal[]       = L"QuickTelex";
const WCHAR c_szPrefsRelaxedCodaVal[]      = L"RelaxedCoda";
const WCHAR c_szPrefsAutoBypassRemoteVal[] = L"AutoBypassRemoteApps";
const WCHAR c_szPrefsStartWithWindowsVal[] = L"StartWithWindows";
const WCHAR c_szPrefsDefaultMigrationVal[] = L"DefaultPrefsMigrationVer";
const WCHAR c_szPrefsUpdatedBySettingsVal[] = L"PrefsUpdatedBySettings";
const WCHAR c_szPrefsSettingsRevisionVal[] = L"SettingsRevision";
const WCHAR c_szPrefsInputMethodRevisionVal[] = L"InputMethodRevision";

std::atomic<uint32_t> g_localPrefsRevision{1};

bool ReadRegDword(HKEY hKey, LPCWSTR valName, DWORD &outVal) {
    DWORD cbData = sizeof(outVal);
    DWORD dwType = 0;
    LSTATUS st = RegQueryValueExW(
        hKey,
        valName,
        nullptr,
        &dwType,
        reinterpret_cast<LPBYTE>(&outVal),
        &cbData
    );
    return (st == ERROR_SUCCESS && dwType == REG_DWORD);
}

void WriteRegDword(HKEY hKey, LPCWSTR valName, DWORD val) {
    RegSetValueExW(
        hKey,
        valName,
        0,
        REG_DWORD,
        reinterpret_cast<const BYTE *>(&val),
        sizeof(val)
    );
}

void EnsureDefaultPrefsInitializedOnce() {
    HKEY hKey = nullptr;
    if (RegCreateKeyExW(
            HKEY_CURRENT_USER,
            kVieLotusPrefsSubKey,
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
        // Default = Telex (InputMethod=0) and Dau truoc am OFF (SenFlexProfile=0).
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
            WriteRegDword(hKey, c_szPrefsStartWithWindowsVal, 0u);
        }
    }
    if (!ReadRegDword(hKey, c_szPrefsDefaultMigrationVal, migVer) || migVer < 12u) {
        // One-time v2.0.9+ zero-background-process migration:
        // Disable legacy System Tray autostart cleanly while preserving all user typing preferences.
        WriteRegDword(hKey, c_szPrefsDefaultMigrationVal, 12u);
        WriteRegDword(hKey, c_szPrefsStartWithWindowsVal, 0u);
    }

    RegCloseKey(hKey);
}

} // namespace

uint32_t GetLocalPrefsRevision() {
    return g_localPrefsRevision.load(std::memory_order_relaxed);
}

uint32_t LoadSettingsRevision() {
    HKEY hKey = nullptr;
    if (RegOpenKeyExW(HKEY_CURRENT_USER, kVieLotusPrefsSubKey, 0, KEY_READ, &hKey) != ERROR_SUCCESS || !hKey) {
        return 0u;
    }
    DWORD dwVal = 0;
    const bool ok = ReadRegDword(hKey, c_szPrefsSettingsRevisionVal, dwVal);
    RegCloseKey(hKey);
    return ok ? static_cast<uint32_t>(dwVal) : 0u;
}

uint32_t LoadInputMethodRevision() {
    HKEY hKey = nullptr;
    if (RegOpenKeyExW(HKEY_CURRENT_USER, kVieLotusPrefsSubKey, 0, KEY_READ, &hKey) != ERROR_SUCCESS || !hKey) {
        return 0u;
    }
    DWORD dwVal = 0;
    const bool ok = ReadRegDword(hKey, c_szPrefsInputMethodRevisionVal, dwVal);
    RegCloseKey(hKey);
    return ok ? static_cast<uint32_t>(dwVal) : 0u;
}

bool LoadPersistedVniPreference(bool &outIsVni) {
    EnsureDefaultPrefsInitializedOnce();
    HKEY hKey = nullptr;
    if (RegOpenKeyExW(HKEY_CURRENT_USER, kVieLotusPrefsSubKey, 0, KEY_READ, &hKey) != ERROR_SUCCESS || !hKey) {
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
    if (RegCreateKeyExW(
            HKEY_CURRENT_USER,
            kVieLotusPrefsSubKey,
            0,
            nullptr,
            REG_OPTION_NON_VOLATILE,
            KEY_READ | KEY_WRITE,
            nullptr,
            &hKey,
            nullptr
        ) == ERROR_SUCCESS && hKey) {
        WriteRegDword(hKey, c_szPrefsDefaultMigrationVal, 12u);
        WriteRegDword(hKey, c_szPrefsInputMethodVal, isVni ? 1u : 0u);
        DWORD curImRev = 0;
        ReadRegDword(hKey, c_szPrefsInputMethodRevisionVal, curImRev);
        DWORD nextImRev = (curImRev == 0xFFFFFFFFu) ? 1u : (curImRev + 1u);
        WriteRegDword(hKey, c_szPrefsInputMethodRevisionVal, nextImRev);
        WriteRegDword(hKey, c_szPrefsUpdatedBySettingsVal, 0u);
        RegCloseKey(hKey);
    }

    // Keep Windows User Profile InputMethodOverride and vi-VN tip order synced with the user's chosen input method
    LPCWSTR preferredTipString = isVni ? kTipVniLayoutString : kTipTelexLayoutString;
    HKEY hUserProfile = nullptr;
    if (RegOpenKeyExW(
            HKEY_CURRENT_USER,
            L"Control Panel\\International\\User Profile",
            0,
            KEY_SET_VALUE,
            &hUserProfile
        ) == ERROR_SUCCESS && hUserProfile) {
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
    if (RegOpenKeyExW(
            HKEY_CURRENT_USER,
            L"Control Panel\\International\\User Profile\\vi-VN",
            0,
            KEY_SET_VALUE,
            &hViKey
        ) == ERROR_SUCCESS && hViKey) {
        WriteRegDword(hViKey, kTipTelexLayoutString, isVni ? 2u : 1u);
        WriteRegDword(hViKey, kTipVniLayoutString, isVni ? 1u : 2u);
        RegCloseKey(hViKey);
    }

    g_localPrefsRevision.fetch_add(1, std::memory_order_relaxed);
}

bool ConsumeSettingsVniOverride(bool &outIsVni) {
    HKEY hKey = nullptr;
    if (RegOpenKeyExW(
            HKEY_CURRENT_USER,
            kVieLotusPrefsSubKey,
            0,
            KEY_READ | KEY_WRITE,
            &hKey
        ) != ERROR_SUCCESS || !hKey) {
        return false;
    }
    DWORD updated = 0;
    bool hasOverride = ReadRegDword(hKey, c_szPrefsUpdatedBySettingsVal, updated) && (updated != 0);
    if (hasOverride) {
        WriteRegDword(hKey, c_szPrefsUpdatedBySettingsVal, 0u);
        DWORD curImRev = 0;
        ReadRegDword(hKey, c_szPrefsInputMethodRevisionVal, curImRev);
        DWORD nextImRev = (curImRev == 0xFFFFFFFFu) ? 1u : (curImRev + 1u);
        WriteRegDword(hKey, c_szPrefsInputMethodRevisionVal, nextImRev);
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
    if (RegOpenKeyExW(HKEY_CURRENT_USER, kVieLotusPrefsSubKey, 0, KEY_READ, &hKey) != ERROR_SUCCESS || !hKey) {
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

void SaveVieLotusPrefs(const VieLotusWindowsPrefs &prefs, bool fromSettingsApp) {
    bool inputMethodChanged = false;
    HKEY hKey = nullptr;
    if (RegCreateKeyExW(
            HKEY_CURRENT_USER,
            kVieLotusPrefsSubKey,
            0,
            nullptr,
            REG_OPTION_NON_VOLATILE,
            KEY_READ | KEY_WRITE,
            nullptr,
            &hKey,
            nullptr
        ) == ERROR_SUCCESS && hKey) {
        DWORD prevInputMethod = 0;
        const bool hadPrevInputMethod = ReadRegDword(hKey, c_szPrefsInputMethodVal, prevInputMethod);
        inputMethodChanged = !hadPrevInputMethod || ((prevInputMethod == 1u) != prefs.isVni);

        WriteRegDword(hKey, c_szPrefsDefaultMigrationVal, 12u);
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
        if (fromSettingsApp) {
            DWORD curRev = 0;
            ReadRegDword(hKey, c_szPrefsSettingsRevisionVal, curRev);
            DWORD nextRev = (curRev == 0xFFFFFFFFu) ? 1u : (curRev + 1u);
            WriteRegDword(hKey, c_szPrefsSettingsRevisionVal, nextRev);
        }
        RegCloseKey(hKey);
    }
    if (fromSettingsApp || inputMethodChanged) {
        SavePersistedVniPreference(prefs.isVni);
    } else {
        g_localPrefsRevision.fetch_add(1, std::memory_order_relaxed);
    }
}

bool LoadPerAppBypassPreference(const wchar_t *exeName, bool &outBypass) {
    if (!exeName || exeName[0] == L'\0') return false;
    HKEY hKey = nullptr;
    if (RegOpenKeyExW(HKEY_CURRENT_USER, kVieLotusPrefsAppBypassSubKey, 0, KEY_READ, &hKey) != ERROR_SUCCESS || !hKey) {
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
    if (RegCreateKeyExW(
            HKEY_CURRENT_USER,
            kVieLotusPrefsAppBypassSubKey,
            0,
            nullptr,
            REG_OPTION_NON_VOLATILE,
            KEY_WRITE,
            nullptr,
            &hKey,
            nullptr
        ) == ERROR_SUCCESS && hKey) {
        WriteRegDword(hKey, exeName, bypass ? 1u : 0u);
        RegCloseKey(hKey);
    }
    g_localPrefsRevision.fetch_add(1, std::memory_order_relaxed);
}

std::wstring GetSettingsWakePipeName() {
    DWORD sessionId = 0;
    if (!ProcessIdToSessionId(GetCurrentProcessId(), &sessionId)) {
        sessionId = 0;
    }
    return L"\\\\.\\pipe\\VieLotusIM_Settings_S" + std::to_wstring(static_cast<unsigned long>(sessionId));
}

bool TryWakeSettingsViaNamedPipe(DWORD waitMs) {
    const std::wstring pipeName = GetSettingsWakePipeName();
    const DWORD desiredAccess = FILE_WRITE_DATA | SYNCHRONIZE;
    HANDLE hPipe = CreateFileW(
        pipeName.c_str(),
        desiredAccess,
        0,
        nullptr,
        OPEN_EXISTING,
        0,
        nullptr
    );
    if (hPipe == INVALID_HANDLE_VALUE && GetLastError() == ERROR_PIPE_BUSY) {
        if (WaitNamedPipeW(pipeName.c_str(), waitMs)) {
            hPipe = CreateFileW(
                pipeName.c_str(),
                desiredAccess,
                0,
                nullptr,
                OPEN_EXISTING,
                0,
                nullptr
            );
        }
    }
    if (hPipe == INVALID_HANDLE_VALUE) {
        return false;
    }

    static const char kCmdShow[4] = {'S', 'H', 'O', 'W'};
    DWORD written = 0;
    const BOOL ok = WriteFile(hPipe, kCmdShow, sizeof(kCmdShow), &written, nullptr);
    CloseHandle(hPipe);
    return (ok != FALSE) && (written == sizeof(kCmdShow));
}
