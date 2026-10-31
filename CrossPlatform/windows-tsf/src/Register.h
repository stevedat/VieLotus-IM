#pragma once

#include "Globals.h"

struct VieLotusWindowsPrefs {
    bool isVni{false};
    bool vietnameseEnabled{true};
    bool smartBilingual{true};
    bool modernOrthography{true};
    bool macroEnabled{true};
    bool developerMode{false};
    bool quickTelex{false};
    bool relaxedCoda{false};
    bool autoBypassRemoteApps{false};
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
bool LoadPerAppBypassPreference(const wchar_t *exeName, bool &outBypass);
void SavePerAppBypassPreference(const wchar_t *exeName, bool bypass);

// Native Win32 Settings Dialog ("Cài đặt Sen Việt")
void ShowVieLotusSettingsDialog(HWND hwndParent);
