#pragma once

#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0A00
#endif

#include <windows.h>
#include <cstdint>
#include <string>

struct VieLotusWindowsPrefs {
    bool isVni{false};
    bool vietnameseEnabled{true};
    bool smartBilingual{true};
    bool modernOrthography{true};
    bool senFlex{false};
    bool macroEnabled{true};
    bool developerMode{false};
    bool quickTelex{false};
    bool relaxedCoda{false};
    bool autoBypassRemoteApps{false};
    bool startWithWindows{false};
};

inline constexpr UINT kWmVieLotusActivateProfiles = WM_USER + 100;
inline constexpr UINT kWmVieLotusShowSettings     = WM_USER + 101;
inline constexpr UINT kWmVieLotusQuitTray         = WM_USER + 199;
inline constexpr UINT kWmVieLotusTrayCallback     = WM_USER + 200;

inline constexpr const wchar_t *kSettingsWndClassName = L"VieLotusBentoSettingsWndClass";
inline constexpr const wchar_t *kFeedbackWndClassName = L"VieLotusFeedbackDialogWndClass";

inline constexpr const wchar_t *kVieLotusPrefsSubKey = L"Software\\VieLotusIM";
inline constexpr const wchar_t *kVieLotusPrefsAppBypassSubKey = L"Software\\VieLotusIM\\AppBypass";

// LayoutOrTip strings for input.dll!InstallLayoutOrTip (042A Vietnamese ONLY — never pollute 0409 English)
inline constexpr const wchar_t *kTipTelexLayoutString =
    L"042A:{C7B08E9D-4762-4C97-8B1F-522197A598DE}{8E2A7B44-5A1F-4B82-9B7C-123456789ABC}";
inline constexpr const wchar_t *kTipVniLayoutString =
    L"042A:{C7B08E9D-4762-4C97-8B1F-522197A598DE}{8E2A7B45-5A1F-4B82-9B7C-123456789ABC}";

bool LoadPersistedVniPreference(bool &outIsVni);
void SavePersistedVniPreference(bool isVni);
bool ConsumeSettingsVniOverride(bool &outIsVni);
void LoadVieLotusPrefs(VieLotusWindowsPrefs &outPrefs);
void SaveVieLotusPrefs(const VieLotusWindowsPrefs &prefs, bool fromSettingsApp = false);
bool LoadPerAppBypassPreference(const wchar_t *exeName, bool &outBypass);
void SavePerAppBypassPreference(const wchar_t *exeName, bool bypass);
uint32_t GetLocalPrefsRevision();
uint32_t LoadSettingsRevision();
uint32_t LoadInputMethodRevision();

std::wstring GetSettingsWakePipeName();
bool TryWakeSettingsViaNamedPipe(DWORD waitMs = 50);
