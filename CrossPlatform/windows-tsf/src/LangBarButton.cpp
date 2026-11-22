#include "LangBarButton.h"
#include "VieLotusTIP.h"
#include <strsafe.h>
#include <cmath>
#include <cstring>
#include <vector>

namespace {

constexpr UINT kLangBarSvIconResourceId = 102u;
constexpr UINT kFallbackAppIconResourceId = 101u;

int ResolveLangBarIconSize() {
    int size = GetSystemMetrics(SM_CXSMICON);
    if (size < 16) size = 16;
    if (size > 64) size = 64;
    return size;
}

// Loads the tight-cropped Sen Viet lotus 'SV' icon embedded in VieLotusTIP.dll (resource 102).
// Deliberately omits LR_SHARED because ITfLangBarItemButton::GetIcon transfers HICON ownership
// to the Windows Shell, which calls DestroyIcon() on the returned handle.
HICON LoadVietnameseSvIcon(int size) {
    if (!g_hInst) return nullptr;
    HICON hIcon = static_cast<HICON>(LoadImageW(
        g_hInst,
        MAKEINTRESOURCEW(kLangBarSvIconResourceId),
        IMAGE_ICON,
        size,
        size,
        LR_DEFAULTCOLOR
    ));
    if (!hIcon) {
        hIcon = static_cast<HICON>(LoadImageW(
            g_hInst,
            MAKEINTRESOURCEW(kFallbackAppIconResourceId),
            IMAGE_ICON,
            size,
            size,
            LR_DEFAULTCOLOR
        ));
    }
    return hIcon;
}

// Renders a crisp, DPI-aware, premultiplied 32-bit BGRA rounded-square badge icon ('V' or 'E')
// using pure Win32 GDI (no GDI+ initialization inside arbitrary host processes).
// Ownership of the returned HICON transfers to the caller (Windows Shell calls DestroyIcon).
HICON CreateModeBadgeIcon(bool isVietnamese, int size) {
    HDC hScreenDc = GetDC(nullptr);
    if (!hScreenDc) return nullptr;

    BITMAPINFO bmi{};
    bmi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    bmi.bmiHeader.biWidth = size;
    bmi.bmiHeader.biHeight = -size; // top-down
    bmi.bmiHeader.biPlanes = 1;
    bmi.bmiHeader.biBitCount = 32;
    bmi.bmiHeader.biCompression = BI_RGB;

    uint32_t *badgePixels = nullptr;
    HBITMAP hbmColor = CreateDIBSection(hScreenDc, &bmi, DIB_RGB_COLORS, reinterpret_cast<void **>(&badgePixels), nullptr, 0);
    if (!hbmColor || !badgePixels) {
        if (hbmColor) DeleteObject(hbmColor);
        ReleaseDC(nullptr, hScreenDc);
        return nullptr;
    }

    uint32_t *glyphPixels = nullptr;
    HBITMAP hbmGlyph = CreateDIBSection(hScreenDc, &bmi, DIB_RGB_COLORS, reinterpret_cast<void **>(&glyphPixels), nullptr, 0);
    HDC hGlyphDc = CreateCompatibleDC(hScreenDc);
    if (!hbmGlyph || !glyphPixels || !hGlyphDc) {
        if (hGlyphDc) DeleteDC(hGlyphDc);
        if (hbmGlyph) DeleteObject(hbmGlyph);
        DeleteObject(hbmColor);
        ReleaseDC(nullptr, hScreenDc);
        return nullptr;
    }

    // 1. Render antialiased white bold glyph ('V' or 'E') onto black scratch DIB
    std::memset(glyphPixels, 0, static_cast<size_t>(size) * static_cast<size_t>(size) * sizeof(uint32_t));
    HGDIOBJ hOldBmp = SelectObject(hGlyphDc, hbmGlyph);
    const int fontHeight = -static_cast<int>(static_cast<float>(size) * 0.78f + 0.5f);
    HFONT hFont = CreateFontW(
        fontHeight,
        0, 0, 0,
        FW_BOLD,
        FALSE, FALSE, FALSE,
        DEFAULT_CHARSET,
        OUT_TT_PRECIS,
        CLIP_DEFAULT_PRECIS,
        ANTIALIASED_QUALITY,
        DEFAULT_PITCH | FF_SWISS,
        L"Segoe UI"
    );
    HGDIOBJ hOldFont = hFont ? SelectObject(hGlyphDc, hFont) : nullptr;
    SetBkMode(hGlyphDc, TRANSPARENT);
    SetTextColor(hGlyphDc, RGB(255, 255, 255));
    RECT rcText{0, 0, size, size};
    const WCHAR glyphChar[2] = { isVietnamese ? L'V' : L'E', L'\0' };
    DrawTextW(hGlyphDc, glyphChar, 1, &rcText, DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX);
    GdiFlush();

    if (hOldFont) SelectObject(hGlyphDc, hOldFont);
    if (hFont) DeleteObject(hFont);
    SelectObject(hGlyphDc, hOldBmp);
    DeleteDC(hGlyphDc);

    // 2. Composite rounded-square badge + antialiased white glyph with exact premultiplied BGRA
    // Sen Viet brand Indigo (#5856D6) for Vietnamese ON; neutral Slate (#5A5A66) for English OFF.
    const float bgR = isVietnamese ? 88.0f : 90.0f;
    const float bgG = isVietnamese ? 86.0f : 90.0f;
    const float bgB = isVietnamese ? 214.0f : 102.0f;

    const float half = static_cast<float>(size) * 0.5f;
    const float inset = (size >= 24) ? 1.0f : 0.5f;
    const float halfExtent = half - inset;
    const float radius = static_cast<float>(size) * 0.24f;

    const size_t maskStride = static_cast<size_t>(((size + 15) / 16) * 2);
    std::vector<uint8_t> maskBits(maskStride * static_cast<size_t>(size), 0u);

    for (int y = 0; y < size; ++y) {
        for (int x = 0; x < size; ++x) {
            const float px = std::fabs((static_cast<float>(x) + 0.5f) - half) - (halfExtent - radius);
            const float py = std::fabs((static_cast<float>(y) + 0.5f) - half) - (halfExtent - radius);
            const float qx = (px > 0.0f) ? px : 0.0f;
            const float qy = (py > 0.0f) ? py : 0.0f;
            const float insideDist = (px > py) ? px : py;
            const float sdf = std::sqrt(qx * qx + qy * qy) + ((insideDist < 0.0f) ? insideDist : 0.0f) - radius;

            float badgeAlpha = 0.5f - sdf;
            if (badgeAlpha < 0.0f) badgeAlpha = 0.0f;
            if (badgeAlpha > 1.0f) badgeAlpha = 1.0f;

            const size_t idx = static_cast<size_t>(y) * static_cast<size_t>(size) + static_cast<size_t>(x);
            if (badgeAlpha <= 0.0f) {
                badgePixels[idx] = 0u;
                maskBits[static_cast<size_t>(y) * maskStride + static_cast<size_t>(x / 8)] |=
                    static_cast<uint8_t>(0x80u >> (x & 7));
                continue;
            }

            const uint32_t gp = glyphPixels[idx];
            const uint32_t gR = (gp >> 16) & 0xFFu;
            const uint32_t gG = (gp >> 8) & 0xFFu;
            const uint32_t gB = gp & 0xFFu;
            uint32_t gMax = (gR > gG) ? gR : gG;
            if (gB > gMax) gMax = gB;
            const float glyphCov = static_cast<float>(gMax) / 255.0f;

            const float outR = bgR + (255.0f - bgR) * glyphCov;
            const float outG = bgG + (255.0f - bgG) * glyphCov;
            const float outB = bgB + (255.0f - bgB) * glyphCov;

            const uint32_t a = static_cast<uint32_t>(badgeAlpha * 255.0f + 0.5f);
            const uint32_t r = static_cast<uint32_t>(outR + 0.5f);
            const uint32_t g = static_cast<uint32_t>(outG + 0.5f);
            const uint32_t b = static_cast<uint32_t>(outB + 0.5f);
            badgePixels[idx] = (a << 24) | (r << 16) | (g << 8) | b;
        }
    }

    DeleteObject(hbmGlyph);

    HBITMAP hbmMask = CreateBitmap(size, size, 1, 1, maskBits.data());

    HICON hIcon = nullptr;
    if (hbmMask) {
        ICONINFO ii{};
        ii.fIcon = TRUE;
        ii.hbmMask = hbmMask;
        ii.hbmColor = hbmColor;
        hIcon = CreateIconIndirect(&ii);
        DeleteObject(hbmMask);
    }

    DeleteObject(hbmColor);
    ReleaseDC(nullptr, hScreenDc);
    return hIcon;
}

void AddTfMenuEntry(ITfMenu *pMenu, UINT uId, DWORD dwFlags, const WCHAR *label) {
    if (!pMenu) return;
    if (dwFlags & TF_LBMENUF_SEPARATOR) {
        pMenu->AddMenuItem(0, TF_LBMENUF_SEPARATOR, nullptr, nullptr, nullptr, 0, nullptr);
        return;
    }
    const ULONG len = label ? static_cast<ULONG>(wcslen(label)) : 0u;
    pMenu->AddMenuItem(uId, dwFlags, nullptr, nullptr, label, len, nullptr);
}

} // namespace

CLangBarItemButton::CLangBarItemButton(CVieLotusTIP *pOwner, bool initialVietnamese, bool initialVni)
    : m_pOwner(pOwner),
      m_isVietnamese(initialVietnamese),
      m_isVni(initialVni) {
    DllAddRef();
}

CLangBarItemButton::~CLangBarItemButton() {
    if (m_pSink) {
        m_pSink->Release();
        m_pSink = nullptr;
    }
    DllRelease();
}

void CLangBarItemButton::DetachOwner() {
    m_pOwner = nullptr;
}

STDMETHODIMP CLangBarItemButton::QueryInterface(REFIID riid, void **ppvObj) {
    if (!ppvObj) return E_POINTER;
    *ppvObj = nullptr;

    if (IsEqualIID(riid, IID_IUnknown) ||
        IsEqualIID(riid, IID_ITfLangBarItem_Compat) ||
        IsEqualIID(riid, IID_ITfLangBarItemButton_Compat)) {
        *ppvObj = static_cast<ITfLangBarItemButton *>(this);
    } else if (IsEqualIID(riid, IID_ITfSource)) {
        *ppvObj = static_cast<ITfSource *>(this);
    }

    if (*ppvObj) {
        AddRef();
        return S_OK;
    }
    return E_NOINTERFACE;
}

STDMETHODIMP_(ULONG) CLangBarItemButton::AddRef() {
    return m_cRef.fetch_add(1, std::memory_order_relaxed) + 1;
}

STDMETHODIMP_(ULONG) CLangBarItemButton::Release() {
    LONG cRef = m_cRef.fetch_sub(1, std::memory_order_relaxed) - 1;
    if (cRef == 0) {
        delete this;
    }
    return cRef;
}

STDMETHODIMP CLangBarItemButton::GetInfo(TF_LANGBARITEMINFO *pInfo) {
    if (!pInfo) return E_INVALIDARG;
    std::memset(pInfo, 0, sizeof(TF_LANGBARITEMINFO));
    pInfo->clsidService = CLSID_VieLotusTIP;
    pInfo->guidItem = GUID_LBI_INPUTMODE_Compat;
    pInfo->dwStyle = TF_LBI_STYLE_BTN_BUTTON | TF_LBI_STYLE_BTN_MENU | TF_LBI_STYLE_SHOWNINTRAY;
    pInfo->ulSort = 0;
    StringCchCopyW(pInfo->szDescription, ARRAYSIZE(pInfo->szDescription), L"Sen Viet Input Mode");
    return S_OK;
}

STDMETHODIMP CLangBarItemButton::GetStatus(DWORD *pdwStatus) {
    if (!pdwStatus) return E_INVALIDARG;
    *pdwStatus = m_status;
    return S_OK;
}

STDMETHODIMP CLangBarItemButton::Show(BOOL fShow) {
    const DWORD nextStatus = fShow
        ? (m_status & ~static_cast<DWORD>(TF_LBI_STATUS_HIDDEN))
        : (m_status | static_cast<DWORD>(TF_LBI_STATUS_HIDDEN));
    if (nextStatus != m_status) {
        m_status = nextStatus;
        if (m_pSink) {
            m_pSink->OnUpdate(TF_LBI_STATUS);
        }
    }
    return S_OK;
}

STDMETHODIMP CLangBarItemButton::GetTooltipString(BSTR *pbstrToolTip) {
    if (!pbstrToolTip) return E_INVALIDARG;
    const WCHAR *tip = m_isVietnamese
        ? (m_isVni
            ? L"Sen Vi\u1EC7t: Ti\u1EBFng Vi\u1EC7t (VNI)\nB\u1EA5m tr\u00E1i: \u0111\u1ED5i VI/EN \u2022 B\u1EA5m ph\u1EA3i: Menu & C\u00E0i \u0111\u1EB7t"
            : L"Sen Vi\u1EC7t: Ti\u1EBFng Vi\u1EC7t (Telex)\nB\u1EA5m tr\u00E1i: \u0111\u1ED5i VI/EN \u2022 B\u1EA5m ph\u1EA3i: Menu & C\u00E0i \u0111\u1EB7t")
        : L"Sen Vi\u1EC7t: Ti\u1EBFng Anh (T\u1EAFt g\u00F5 d\u1EA5u)\nB\u1EA5m tr\u00E1i: b\u1EADt Ti\u1EBFng Vi\u1EC7t \u2022 B\u1EA5m ph\u1EA3i: Menu & C\u00E0i \u0111\u1EB7t";
    *pbstrToolTip = SysAllocString(tip);
    return (*pbstrToolTip != nullptr) ? S_OK : E_OUTOFMEMORY;
}

STDMETHODIMP CLangBarItemButton::OnClick(TfLBIClick click, POINT pt, const RECT *prcArea) {
    if (!m_pOwner) return S_OK;

    if (click == TF_LBI_CLK_LEFT) {
        m_pOwner->ToggleVietnameseModeFromUi(nullptr);
        return S_OK;
    }

    if (click == TF_LBI_CLK_RIGHT) {
        HWND hwndOwner = m_pOwner->GetFocusedContextWindow();
        if (!hwndOwner || !IsWindow(hwndOwner)) {
            hwndOwner = GetForegroundWindow();
        }
        if (!hwndOwner || !IsWindow(hwndOwner)) {
            return S_OK;
        }

        HMENU hMenu = CreatePopupMenu();
        if (!hMenu) return S_OK;

        const bool isVn = m_pOwner->IsVietnameseMode();
        const bool isVni = m_pOwner->IsVniMode();

        AppendMenuW(
            hMenu,
            MF_STRING | (isVn ? MF_CHECKED : MF_UNCHECKED),
            vielotus_tsf_guard::kLangBarCmdVietnamese,
            L"Ti\u1EBFng Vi\u1EC7t (B\u1EADt g\u00F5 d\u1EA5u)"
        );
        AppendMenuW(
            hMenu,
            MF_STRING | (!isVn ? MF_CHECKED : MF_UNCHECKED),
            vielotus_tsf_guard::kLangBarCmdEnglish,
            L"Ti\u1EBFng Anh (T\u1EAFt g\u00F5 d\u1EA5u)"
        );
        AppendMenuW(hMenu, MF_SEPARATOR, 0, nullptr);
        AppendMenuW(
            hMenu,
            MF_STRING | (!isVni ? MF_CHECKED : MF_UNCHECKED),
            vielotus_tsf_guard::kLangBarCmdTelex,
            L"Ki\u1EC3u g\u00F5 Telex"
        );
        AppendMenuW(
            hMenu,
            MF_STRING | (isVni ? MF_CHECKED : MF_UNCHECKED),
            vielotus_tsf_guard::kLangBarCmdVni,
            L"Ki\u1EC3u g\u00F5 VNI"
        );
        AppendMenuW(hMenu, MF_SEPARATOR, 0, nullptr);
        AppendMenuW(
            hMenu,
            MF_STRING,
            vielotus_tsf_guard::kLangBarCmdOpenSettings,
            L"M\u1EDF B\u1EA3ng \u0110i\u1EC1u Khi\u1EC3n Sen Vi\u1EC7t..."
        );

        int x = pt.x;
        int y = pt.y;
        if (x == 0 && y == 0 && prcArea) {
            x = prcArea->left;
            y = prcArea->top;
        }

        SetForegroundWindow(hwndOwner);
        AddRef();
        UINT wID = static_cast<UINT>(TrackPopupMenuEx(
            hMenu,
            TPM_NONOTIFY | TPM_RETURNCMD | TPM_RIGHTBUTTON | TPM_BOTTOMALIGN,
            x, y, hwndOwner, nullptr
        ));
        PostMessageW(hwndOwner, WM_NULL, 0, 0);
        DestroyMenu(hMenu);

        if (wID != 0 && m_pOwner) {
            m_pOwner->HandleLangBarMenuSelect(wID);
        }
        Release();
    }
    return S_OK;
}

STDMETHODIMP CLangBarItemButton::InitMenu(ITfMenu *pMenu) {
    if (!pMenu) return E_INVALIDARG;

    const bool isVn = m_pOwner ? m_pOwner->IsVietnameseMode() : m_isVietnamese;
    const bool isVni = m_pOwner ? m_pOwner->IsVniMode() : m_isVni;

    AddTfMenuEntry(
        pMenu,
        vielotus_tsf_guard::kLangBarCmdVietnamese,
        isVn ? TF_LBMENUF_RADIOCHECKED : 0u,
        L"Ti\u1EBFng Vi\u1EC7t (B\u1EADt g\u00F5 d\u1EA5u)"
    );
    AddTfMenuEntry(
        pMenu,
        vielotus_tsf_guard::kLangBarCmdEnglish,
        !isVn ? TF_LBMENUF_RADIOCHECKED : 0u,
        L"Ti\u1EBFng Anh (T\u1EAFt g\u00F5 d\u1EA5u)"
    );
    AddTfMenuEntry(pMenu, 0, TF_LBMENUF_SEPARATOR, nullptr);
    AddTfMenuEntry(
        pMenu,
        vielotus_tsf_guard::kLangBarCmdTelex,
        !isVni ? TF_LBMENUF_RADIOCHECKED : 0u,
        L"Ki\u1EC3u g\u00F5 Telex"
    );
    AddTfMenuEntry(
        pMenu,
        vielotus_tsf_guard::kLangBarCmdVni,
        isVni ? TF_LBMENUF_RADIOCHECKED : 0u,
        L"Ki\u1EC3u g\u00F5 VNI"
    );
    AddTfMenuEntry(pMenu, 0, TF_LBMENUF_SEPARATOR, nullptr);
    AddTfMenuEntry(
        pMenu,
        vielotus_tsf_guard::kLangBarCmdOpenSettings,
        0u,
        L"M\u1EDF B\u1EA3ng \u0110i\u1EC1u Khi\u1EC3n Sen Vi\u1EC7t..."
    );

    return S_OK;
}

STDMETHODIMP CLangBarItemButton::OnMenuSelect(UINT wID) {
    if (m_pOwner) {
        m_pOwner->HandleLangBarMenuSelect(wID);
    }
    return S_OK;
}

STDMETHODIMP CLangBarItemButton::GetIcon(HICON *phIcon) {
    if (!phIcon) return E_INVALIDARG;
    const int size = ResolveLangBarIconSize();
    if (vielotus_tsf_guard::ResolveLangBarIconKind(m_isVietnamese) ==
        vielotus_tsf_guard::LangBarIconKind::VietnameseSvLogo) {
        HICON hSv = LoadVietnameseSvIcon(size);
        if (hSv) {
            *phIcon = hSv;
            return S_OK;
        }
    }
    *phIcon = CreateModeBadgeIcon(m_isVietnamese, size);
    return (*phIcon != nullptr) ? S_OK : E_FAIL;
}

STDMETHODIMP CLangBarItemButton::GetText(BSTR *pbstrText) {
    if (!pbstrText) return E_INVALIDARG;
    *pbstrText = SysAllocString(m_isVietnamese ? L"Ti\u1EBFng Vi\u1EC7t" : L"Ti\u1EBFng Anh");
    return (*pbstrText != nullptr) ? S_OK : E_OUTOFMEMORY;
}

STDMETHODIMP CLangBarItemButton::AdviseSink(REFIID riid, IUnknown *punk, DWORD *pdwCookie) {
    if (!punk || !pdwCookie) return E_INVALIDARG;
    *pdwCookie = 0;

    if (!IsEqualIID(riid, IID_ITfLangBarItemSink_Compat)) {
        return CONNECT_E_CANNOTCONNECT;
    }
    if (m_pSink != nullptr) {
        return CONNECT_E_ADVISELIMIT;
    }

    HRESULT hr = punk->QueryInterface(IID_ITfLangBarItemSink_Compat, reinterpret_cast<void **>(&m_pSink));
    if (FAILED(hr) || !m_pSink) {
        m_pSink = nullptr;
        return E_NOINTERFACE;
    }
    *pdwCookie = kSinkCookie;
    return S_OK;
}

STDMETHODIMP CLangBarItemButton::UnadviseSink(DWORD dwCookie) {
    if (dwCookie != kSinkCookie || !m_pSink) {
        return CONNECT_E_NOCONNECTION;
    }
    m_pSink->Release();
    m_pSink = nullptr;
    return S_OK;
}

void CLangBarItemButton::UpdateState(bool isVietnamese, bool isVni, bool forceNotify) {
    const bool shouldNotify = vielotus_tsf_guard::ShouldNotifyLangBarUpdate(
        m_isVietnamese,
        m_isVni,
        isVietnamese,
        isVni,
        forceNotify
    );
    m_isVietnamese = isVietnamese;
    m_isVni = isVni;
    if (shouldNotify && m_pSink) {
        m_pSink->OnUpdate(TF_LBI_ICON | TF_LBI_TOOLTIP | TF_LBI_TEXT | TF_LBI_STATUS);
    }
}
