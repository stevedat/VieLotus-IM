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
void LoadVieLotusPrefs(VieLotusWindowsPrefs &outPrefs);
void SaveVieLotusPrefs(const VieLotusWindowsPrefs &prefs);

// Native Win32 Settings Dialog ("Cài đặt Sen Việt")
void ShowVieLotusSettingsDialog(HWND hwndParent);
