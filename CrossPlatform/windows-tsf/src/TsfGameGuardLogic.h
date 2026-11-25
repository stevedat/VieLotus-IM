#pragma once

#include <cstdint>

namespace vielotus_tsf_guard {

// Standard Windows TSF HRESULT values represented portably (no <windows.h> dependency)
// so unit tests can execute natively on macOS/Linux as well as Windows.
inline constexpr int32_t kTfSAsync       = 0x00040300;
inline constexpr int32_t kTsESynchronous = static_cast<int32_t>(0x80040208u);
inline constexpr int32_t kTfESynchronous = static_cast<int32_t>(0x80040508u);
inline constexpr int32_t kTfELocked      = static_cast<int32_t>(0x80040500u);
inline constexpr uint32_t kVkSpace = 0x20u;
inline constexpr uint32_t kVkKeyS = 0x53u;

enum class HotkeyKind {
    None = 0,
    ToggleVietnamese = 1,
    OpenSettings = 2
};

enum class ShiftEditPlan {
    ApplyFullRange = 0,
    FallbackWin32Edit = 1,
    RefuseNoMutation = 2
};

enum class TsfEditOutcome {
    Succeeded = 0,
    QueuedAsync = 1,
    DeleteRefused = 2,
    Failed = 3
};

inline HotkeyKind ClassifyHotkey(
    uint32_t vk,
    bool hasCtrl,
    bool hasShift,
    bool hasAlt,
    bool hasWin,
    bool isVietnameseMode,
    bool contextReadOnly
) {
    // VI/EN toggle: Ctrl+Space (or Ctrl+Shift+Space).
    // Bare Shift+Space is NEVER intercepted so sprint+jump in games and fast Shift+Space typing pass cleanly.
    // Remains active even when Vietnamese mode is OFF or context is read-only so users can toggle back ON anytime.
    if (vk == kVkSpace && hasCtrl && !hasAlt && !hasWin) {
        return HotkeyKind::ToggleVietnamese;
    }

    // Ctrl+Shift+S is intentionally NEVER intercepted because it collides with global "Save As"
    // in VS Code, Windows 11 Notepad, Office, and creative apps. Settings opens cleanly via
    // the Taskbar [SV] menu or Start Menu.
    (void)hasShift;
    (void)isVietnameseMode;
    (void)contextReadOnly;

    return HotkeyKind::None;
}

inline bool ShouldBypassContextForTyping(
    bool hasContext,
    bool getStatusSucceeded,
    uint32_t dynamicFlags,
    uint32_t readOnlyFlagBit
) {
    if (!hasContext) {
        return true;
    }
    if (getStatusSucceeded && (dynamicFlags & readOnlyFlagBit) != 0u) {
        return true;
    }
    return false;
}

inline ShiftEditPlan PlanRangeShiftEdit(
    int32_t requestedBackspaces,
    int32_t actualShifted,
    bool selectionWasEmpty,
    bool isWin32EditControl,
    bool win32SelectionEmpty,
    uint32_t win32CaretStart
) {
    if (requestedBackspaces <= 0 || !selectionWasEmpty) {
        return ShiftEditPlan::ApplyFullRange;
    }
    if (actualShifted == requestedBackspaces) {
        return ShiftEditPlan::ApplyFullRange;
    }
    // Missing some or all backspaces (actualShifted == 0 OR 0 < actualShifted < requestedBackspaces).
    // Allow Win32 Edit/RichEdit EM_SETSEL fallback only when the control confirms it holds
    // at least requestedBackspaces UTF-16 code units before the caret.
    if (actualShifted >= 0 && actualShifted < requestedBackspaces &&
        isWin32EditControl && win32SelectionEmpty &&
        win32CaretStart >= static_cast<uint32_t>(requestedBackspaces)) {
        return ShiftEditPlan::FallbackWin32Edit;
    }
    return ShiftEditPlan::RefuseNoMutation;
}

inline bool CanClassicWin32EditDelete(
    int32_t requestedBackspaces,
    uint32_t dwStart,
    uint32_t dwEnd
) {
    if (requestedBackspaces <= 0) {
        return true;
    }
    if (dwStart < dwEnd) {
        return true;
    }
    return dwStart >= static_cast<uint32_t>(requestedBackspaces);
}

// Re-validates the Win32 Edit/RichEdit caret immediately before a single atomic
// EM_SETSEL(dwStart - requestedBackspaces, dwEnd) + EM_REPLACESEL fallback,
// guaranteeing zero prior partial deletion if the caret no longer covers requestedBackspaces.
inline bool CanWin32AtomicFallbackReplace(
    int32_t requestedBackspaces,
    uint32_t dwStart,
    uint32_t dwEnd
) {
    return requestedBackspaces > 0 &&
           dwStart == dwEnd &&
           dwStart >= static_cast<uint32_t>(requestedBackspaces);
}

inline TsfEditOutcome ClassifyRequestEditSessionResult(
    bool allocated,
    int32_t hrReq,
    int32_t hrSession,
    bool wasExecuted,
    bool deleteRefused,
    int32_t hrSetText
) {
    if (!allocated || hrReq < 0) {
        return TsfEditOutcome::Failed;
    }
    if (!wasExecuted) {
        // Per Microsoft TSF ITfContext::RequestEditSession with TF_ES_ASYNCDONTCARE:
        // when the document is locked, RequestEditSession returns S_OK and *phrSession == TF_S_ASYNC,
        // meaning DoEditSession has been queued to execute asynchronously once the lock frees.
        if (hrSession == kTfSAsync) {
            return TsfEditOutcome::QueuedAsync;
        }
        return TsfEditOutcome::Failed;
    }
    if (deleteRefused) {
        return TsfEditOutcome::DeleteRefused;
    }
    if (hrSession < 0 || hrSetText < 0) {
        return TsfEditOutcome::Failed;
    }
    return TsfEditOutcome::Succeeded;
}

inline bool ShouldEatKeyAfterEdit(TsfEditOutcome outcome) {
    return outcome == TsfEditOutcome::Succeeded ||
           outcome == TsfEditOutcome::QueuedAsync;
}

// Sync-first ITfComposition::EndComposition retry & ref-release policy.
// EndActiveComposition tries TF_ES_SYNC | TF_ES_READWRITE first so compositionend
// finishes synchronously before non-eaten keys (e.g. Enter/Tab/Arrows in Chromium web
// editors) are dispatched by the host; if the document lock rejects TF_ES_SYNC
// (TS_E_SYNCHRONOUS / TF_E_SYNCHRONOUS / TF_E_LOCKED) without running DoEditSession,
// fall back once to TF_ES_ASYNCDONTCARE | TF_ES_READWRITE.
inline bool ShouldFallbackEndCompositionAsync(
    int32_t hrReq,
    int32_t hrSession,
    bool wasExecuted
) {
    if (wasExecuted) {
        return false;
    }
    if (hrReq >= 0 && hrSession == kTfSAsync) {
        return false;
    }
    return true;
}

inline bool ShouldReleaseCompositionAfterEndAttempt(
    int32_t hrReq,
    int32_t hrSession,
    bool wasExecuted
) {
    if (wasExecuted) {
        return hrReq < 0 || hrSession < 0;
    }
    if (hrReq >= 0 && hrSession == kTfSAsync) {
        return false;
    }
    return true;
}

inline const char *EditOutcomeName(TsfEditOutcome outcome) {
    switch (outcome) {
    case TsfEditOutcome::Succeeded:     return "OK";
    case TsfEditOutcome::QueuedAsync:   return "ASYNC";
    case TsfEditOutcome::DeleteRefused: return "REFUSED";
    case TsfEditOutcome::Failed:        return "FAILED";
    }
    return "UNKNOWN";
}

// Out-of-process Settings launch policy from VieLotusTIP.dll (handles UIPI & AppContainer safely)
enum class SettingsLaunchPlan {
    PostToExistingWindow = 0,
    WakeViaNamedPipe = 1,
    LaunchSettingsExe = 2,
    SkipUnavailable = 3
};

inline SettingsLaunchPlan PlanSettingsLaunch(
    bool hasExistingWindow,
    bool pipeWakeSucceeded,
    bool isAppContainer,
    bool hasSettingsExe
) {
    if (hasExistingWindow) {
        return SettingsLaunchPlan::PostToExistingWindow;
    }
    if (pipeWakeSucceeded) {
        return SettingsLaunchPlan::WakeViaNamedPipe;
    }
    if (!isAppContainer && hasSettingsExe) {
        return SettingsLaunchPlan::LaunchSettingsExe;
    }
    return SettingsLaunchPlan::SkipUnavailable;
}

inline bool ShouldClearManualOverrideOnSettingsRevision(
    uint32_t lastSeenSettingsRev,
    uint32_t currentSettingsRev
) {
    return currentSettingsRev != 0u && currentSettingsRev != lastSeenSettingsRev;
}

inline bool ShouldIncludeContactInFeedbackChannel(bool isPublicGitHubIssue) {
    return !isPublicGitHubIssue;
}

// Windows Taskbar Input Indicator (GUID_LBI_INPUTMODE) menu command IDs & state sync helpers
inline constexpr uint32_t kLangBarCmdVietnamese   = 4101u;
inline constexpr uint32_t kLangBarCmdEnglish      = 4102u;
inline constexpr uint32_t kLangBarCmdTelex        = 4103u;
inline constexpr uint32_t kLangBarCmdVni          = 4104u;
inline constexpr uint32_t kLangBarCmdOpenSettings = 4105u;

enum class LangBarMenuAction {
    None = 0,
    SetVietnamese = 1,
    SetEnglish = 2,
    SetTelex = 3,
    SetVni = 4,
    OpenSettings = 5
};

inline LangBarMenuAction ResolveLangBarMenuAction(uint32_t cmdId) {
    switch (cmdId) {
    case kLangBarCmdVietnamese:   return LangBarMenuAction::SetVietnamese;
    case kLangBarCmdEnglish:      return LangBarMenuAction::SetEnglish;
    case kLangBarCmdTelex:        return LangBarMenuAction::SetTelex;
    case kLangBarCmdVni:          return LangBarMenuAction::SetVni;
    case kLangBarCmdOpenSettings: return LangBarMenuAction::OpenSettings;
    default:                      return LangBarMenuAction::None;
    }
}

inline bool ShouldNotifyLangBarUpdate(
    bool prevVietnamese,
    bool prevVni,
    bool nextVietnamese,
    bool nextVni,
    bool forceRefresh
) {
    return forceRefresh || (prevVietnamese != nextVietnamese) || (prevVni != nextVni);
}

// Language Bar icon policy (GUID_LBI_INPUTMODE — sits beside Windows' profile SV lotus icon):
//  - Vietnamese ON  -> Indigo '[V]' rounded-square badge (avoids duplicating the adjacent SV profile logo)
//  - English OFF    -> neutral Slate '[E]' rounded-square badge for instant visual contrast
enum class LangBarIconKind {
    VietnameseIndigoBadge = 0,
    EnglishSlateBadge = 1
};

inline LangBarIconKind ResolveLangBarIconKind(bool isVietnamese) {
    return isVietnamese ? LangBarIconKind::VietnameseIndigoBadge : LangBarIconKind::EnglishSlateBadge;
}

// Windows MSIX (Microsoft Store) vs Classic Win32 installer shortcut & Installed Apps policy:
// MSIX packages already register their own Start Menu app tile and Settings > Installed apps entry
// via AppxManifest.xml; skipping duplicate Win32 Start Menu .lnk & Uninstall entries prevents
// duplicate Sen Viet icons in Start Menu, Windows Search, and Installed Apps.
inline bool ShouldRegisterClassicStartMenuAndUninstall(bool isMsixPackage) {
    return !isMsixPackage;
}

inline bool ShouldRequireWin32UninstallEntryForTipCheck(bool isMsixPackage) {
    return !isMsixPackage;
}

// ITfInputProcessorProfileMgr::ActivateProfile scope flags are mutually exclusive on Windows
// (TF_IPPMF_FORPROCESS = 0x10000000, TF_IPPMF_FORSESSION = 0x20000000); combining both in one
// call returns E_INVALIDARG and leaves the desktop profile unchanged.
inline constexpr uint32_t kTfIppmfForProcess                   = 0x10000000u;
inline constexpr uint32_t kTfIppmfForSession                   = 0x20000000u;
inline constexpr uint32_t kTfIppmfEnableProfile                = 0x00000002u;
inline constexpr uint32_t kTfIppmfDontCareCurrentInputLanguage = 0x00000004u;

inline constexpr uint32_t kActivateProfileProcessFlags =
    kTfIppmfForProcess | kTfIppmfEnableProfile | kTfIppmfDontCareCurrentInputLanguage;
inline constexpr uint32_t kActivateProfileSessionFlags =
    kTfIppmfForSession | kTfIppmfEnableProfile | kTfIppmfDontCareCurrentInputLanguage;

inline bool AreActivateProfileFlagsValid(uint32_t flags) {
    return !((flags & kTfIppmfForProcess) != 0u && (flags & kTfIppmfForSession) != 0u);
}

// Cross-process Telex <-> VNI profile synchronization policy using a monotonic InputMethodRevision
// counter instead of a single-consumer flag (which previously let the first focused process consume
// the override and allowed a second already-open process with a stale TSF profile to revert Registry).
enum class ProfileSyncAction {
    NoChange = 0,
    AdoptActiveProfileLocally = 1,
    PushRegistryToActiveProfile = 2
};

inline bool HasUnseenInputMethodRevision(
    bool hasInitializedImRevision,
    uint32_t lastSeenImRevision,
    uint32_t currentRegistryImRevision
) {
    return hasInitializedImRevision &&
           currentRegistryImRevision != 0u &&
           currentRegistryImRevision != lastSeenImRevision;
}

inline ProfileSyncAction PlanProfileSync(
    bool hasInitializedImRevision,
    uint32_t lastSeenImRevision,
    uint32_t currentRegistryImRevision,
    bool forcePushToProfile,
    bool selfTipActive,
    bool hasKnownActiveProfileVni,
    bool activeProfileIsVni,
    bool registryIsVni,
    bool inActivateEx,
    bool activeProfileIsNullOrMissing
) {
    if (forcePushToProfile ||
        HasUnseenInputMethodRevision(hasInitializedImRevision, lastSeenImRevision, currentRegistryImRevision)) {
        if (selfTipActive || inActivateEx) {
            return ProfileSyncAction::PushRegistryToActiveProfile;
        }
        return ProfileSyncAction::NoChange;
    }

    if (selfTipActive) {
        if (hasKnownActiveProfileVni) {
            return ProfileSyncAction::AdoptActiveProfileLocally;
        }
        return ProfileSyncAction::NoChange;
    }

    if (inActivateEx && activeProfileIsNullOrMissing) {
        return ProfileSyncAction::PushRegistryToActiveProfile;
    }

    (void)activeProfileIsVni;
    (void)registryIsVni;
    return ProfileSyncAction::NoChange;
}

inline bool ShouldPersistOnProfileActivated(
    bool inProfileSync,
    bool hasPersistedVni,
    bool persistedVni,
    bool activatedProfileIsVni
) {
    return !inProfileSync && (!hasPersistedVni || persistedVni != activatedProfileIsVni);
}

// Desktop Numpad digits (VK_NUMPAD0..VK_NUMPAD9 = 0x60..0x69) always emit literal digits in VNI mode
// instead of acting as VNI tone/vowel modifiers (top-row '0'..'9' remain standard VNI diacritic keys).
inline constexpr uint32_t kVkNumpad0 = 0x60u;
inline constexpr uint32_t kVkNumpad9 = 0x69u;

inline bool IsNumpadDigitVk(uint32_t vkCode) {
    return vkCode >= kVkNumpad0 && vkCode <= kVkNumpad9;
}

inline bool IsVniDigitModifierKey(bool isVniMode, uint32_t vkCode, uint32_t ch) {
    return isVniMode && !IsNumpadDigitVk(vkCode) && ch >= static_cast<uint32_t>('0') && ch <= static_cast<uint32_t>('9');
}

} // namespace vielotus_tsf_guard
