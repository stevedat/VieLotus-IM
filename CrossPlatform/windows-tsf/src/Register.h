#pragma once

#include "Globals.h"
#include "PrefsStore.h"

HRESULT RegisterServer();
HRESULT UnregisterServer();
HRESULT RegisterProfiles();
HRESULT UnregisterProfiles();
HRESULT RegisterCategories();
HRESULT UnregisterCategories();
HRESULT ActivateUserProfiles(bool forceLangListSync = false);
HRESULT DeactivateUserProfiles();
