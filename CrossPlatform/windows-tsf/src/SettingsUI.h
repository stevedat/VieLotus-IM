#pragma once

#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0A00
#endif

#include <windows.h>
#include "PrefsStore.h"

using VieLotusActivateProfilesFn = void (*)(bool forceLangListSync);

void SyncStartWithWindowsRegistry(bool enable);
void BringSettingsWindowToFront(HWND hwnd);
bool WakeExistingSettingsWindow();
void ShowVieLotusSettingsDialog(
    HINSTANCE hInstance,
    HWND hwndParent,
    bool startHiddenInTray,
    VieLotusActivateProfilesFn onActivateProfiles
);
void ShowVieLotusFeedbackDialog(
    HINSTANCE hInstance,
    HWND hwndParent,
    const VieLotusWindowsPrefs &prefs
);
