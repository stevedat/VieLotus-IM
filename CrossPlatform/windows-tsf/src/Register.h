#pragma once

#include "Globals.h"

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
    bool startWithWindows{true};
};

HRESULT RegisterServer();
HRESULT UnregisterServer();
HRESULT RegisterProfiles();
HRESULT UnregisterProfiles();
HRESULT RegisterCategories();
HRESULT UnregisterCategories();
HRESULT ActivateUserProfiles();
HRESULT DeactivateUserProfiles();

// Persisted user preferences in HKCU\Software\VieLotusIM
bool LoadPersistedVniPreference(bool &outIsVni);
void SavePersistedVniPreference(bool isVni);
bool ConsumeSettingsVniOverride(bool &outIsVni);
void LoadVieLotusPrefs(VieLotusWindowsPrefs &outPrefs);
void SaveVieLotusPrefs(const VieLotusWindowsPrefs &prefs);
void SyncStartWithWindowsRegistry(bool enable);
bool LoadPerAppBypassPreference(const wchar_t *exeName, bool &outBypass);
void SavePerAppBypassPreference(const wchar_t *exeName, bool bypass);
uint32_t GetLocalPrefsRevision();

// Native Win32 Settings & Feedback Dialogs ("Cài đặt Sen Việt" & "Góp ý & Báo lỗi")
void ShowVieLotusSettingsDialog(HWND hwndParent, bool startHiddenInTray = false);
void ShowVieLotusFeedbackDialog(HWND hwndParent, const VieLotusWindowsPrefs &prefs);
