#pragma once

#include <windows.h>
#include <cstdint>

namespace win_l10n {

enum class UiLanguagePref : uint32_t {
    Auto = 0,
    Vietnamese = 1,
    English = 2
};

inline uint32_t NormalizeUiLanguagePref(uint32_t raw) {
    return (raw <= 2u) ? raw : 0u;
}

inline bool ResolveWindowsIsEnglish(uint32_t pref) {
    const uint32_t norm = NormalizeUiLanguagePref(pref);
    if (norm == 1u) {
        return false;
    }
    if (norm == 2u) {
        return true;
    }
    const LANGID uiLang = GetUserDefaultUILanguage();
    return PRIMARYLANGID(uiLang) != LANG_VIETNAMESE;
}

inline const wchar_t *Tr(bool isEn, const wchar_t *vi, const wchar_t *en) {
    return isEn ? en : vi;
}

inline const wchar_t *LanguageShortLabel(uint32_t pref) {
    switch (NormalizeUiLanguagePref(pref)) {
    case 1u:
        return L"VI";
    case 2u:
        return L"EN";
    default:
        return L"Auto";
    }
}

} // namespace win_l10n
