#pragma once

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif

#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0A00
#endif

#include <windows.h>
#include <msctf.h>
#include <ctfutb.h>
#include <olectl.h>
#include <atomic>
#include <new>
#include "vielotus.h"

#ifndef TF_CLIENTID_NULL
#define TF_CLIENTID_NULL ((TfClientId)0)
#endif

#ifndef __ITfTextInputProcessorEx_INTERFACE_DEFINED__
#define __ITfTextInputProcessorEx_INTERFACE_DEFINED__
EXTERN_C const IID IID_ITfTextInputProcessorEx;
MIDL_INTERFACE("6E4E2102-F9CD-433D-B496-303CE03A6507")
ITfTextInputProcessorEx : public ITfTextInputProcessor {
public:
    virtual HRESULT STDMETHODCALLTYPE ActivateEx(
        ITfThreadMgr *ptim,
        TfClientId tid,
        DWORD dwFlags) = 0;
};
#endif

// MinGW/Zig ctfutb.h compatibility definitions (bit-for-bit identical to Windows 10/11 SDK ctfutb.h)
#ifndef TF_LBI_ICON
#define TF_LBI_ICON      0x00000001
#define TF_LBI_TEXT      0x00000002
#define TF_LBI_TOOLTIP   0x00000004
#define TF_LBI_BITMAP    0x00000008
#define TF_LBI_BALLOON   0x00000010
#define TF_LBI_CUSTOMUI  0x00000020
#define TF_LBI_BTNALL    (TF_LBI_ICON | TF_LBI_TEXT | TF_LBI_TOOLTIP)
#define TF_LBI_STATUS    0x00010000
#endif

#ifndef TF_LBI_STYLE_SHOWNINTRAY
#define TF_LBI_STYLE_HIDDENSTATUSCONTROL 0x00000001
#define TF_LBI_STYLE_SHOWNINTRAY         0x00000002
#define TF_LBI_STYLE_HIDEONNOOTHERITEMS  0x00000004
#define TF_LBI_STYLE_SHOWNINTRAYONLY     0x00000008
#define TF_LBI_STYLE_HIDDENBYDEFAULT     0x00000010
#define TF_LBI_STYLE_TEXTCOLORICON       0x00000020
#define TF_LBI_STYLE_BTN_BUTTON          0x00010000
#define TF_LBI_STYLE_BTN_MENU            0x00020000
#define TF_LBI_STYLE_BTN_TOGGLE          0x00040000
#endif

#ifndef TF_LBI_STATUS_HIDDEN
#define TF_LBI_STATUS_HIDDEN      0x00000001
#define TF_LBI_STATUS_DISABLED    0x00000002
#define TF_LBI_STATUS_BTN_TOGGLED 0x00010000
#endif

#ifndef TF_LBMENUF_CHECKED
#define TF_LBMENUF_CHECKED      0x00000001
#define TF_LBMENUF_SUBMENU      0x00000002
#define TF_LBMENUF_SEPARATOR    0x00000004
#define TF_LBMENUF_RADIOCHECKED 0x00000008
#define TF_LBMENUF_GRAYED       0x00000010
#endif

#ifndef __ITfMenu_INTERFACE_DEFINED__
#define __ITfMenu_INTERFACE_DEFINED__
EXTERN_C const IID IID_ITfMenu;
MIDL_INTERFACE("6F8A98E4-AAA0-4F15-8C5B-07E0DF0A3DD8")
ITfMenu : public IUnknown {
public:
    virtual HRESULT STDMETHODCALLTYPE AddMenuItem(
        UINT uId,
        DWORD dwFlags,
        HBITMAP hbmp,
        HBITMAP hbmpMask,
        const WCHAR *pch,
        ULONG cch,
        ITfMenu **ppMenu) = 0;
};
#endif

#ifndef __ITfLangBarItemButton_INTERFACE_DEFINED__
#define __ITfLangBarItemButton_INTERFACE_DEFINED__
typedef enum __MIDL_VieLotus_TfLBIClick {
    TF_LBI_CLK_RIGHT = 1,
    TF_LBI_CLK_LEFT  = 2
} TfLBIClick;

EXTERN_C const IID IID_ITfLangBarItemButton;
MIDL_INTERFACE("28C7F1D0-DE25-11D2-AFDD-00105A2799B5")
ITfLangBarItemButton : public ITfLangBarItem {
public:
    virtual HRESULT STDMETHODCALLTYPE OnClick(
        TfLBIClick click,
        POINT pt,
        const RECT *prcArea) = 0;

    virtual HRESULT STDMETHODCALLTYPE InitMenu(
        ITfMenu *pMenu) = 0;

    virtual HRESULT STDMETHODCALLTYPE OnMenuSelect(
        UINT wID) = 0;

    virtual HRESULT STDMETHODCALLTYPE GetIcon(
        HICON *phIcon) = 0;

    virtual HRESULT STDMETHODCALLTYPE GetText(
        BSTR *pbstrText) = 0;
};
#endif

// IID for ITfTextInputProcessorEx: {6E4E2102-F9CD-433D-B496-303CE03A6507}
extern const GUID IID_ITfTextInputProcessorEx_Compat;

// Language Bar COM IIDs & Windows 8/10/11 Input Indicator GUID (link-safe across MSVC, MinGW, Zig)
extern const GUID IID_ITfLangBarItemMgr_Compat;
extern const GUID IID_ITfLangBarItem_Compat;
extern const GUID IID_ITfLangBarItemButton_Compat;
extern const GUID IID_ITfLangBarItemSink_Compat;
extern const GUID GUID_LBI_INPUTMODE_Compat;

// CLSID for VieLotusTIP: {C7B08E9D-4762-4C97-8B1F-522197A598DE}
extern const GUID CLSID_VieLotusTIP;

// Legacy CLSIDs (2.0.2-r6 and 2.0.2-r7): {C7B08E9D-4762-4C97-8B1F-522197A598DC}, {C7B08E9D-4762-4C97-8B1F-522197A598DD}
extern const GUID CLSID_VieLotusTIP_Legacy;
extern const GUID CLSID_VieLotusTIP_Legacy2;

// Profile GUID for VieLotusTIP (Telex): {8E2A7B44-5A1F-4B82-9B7C-123456789ABC}
extern const GUID GUID_VieLotusProfile;

// Profile GUID for VieLotusTIP (VNI): {8E2A7B45-5A1F-4B82-9B7C-123456789ABC}
extern const GUID GUID_VieLotusProfileVNI;

// Global Module Handle & COM Reference Counter
extern HINSTANCE g_hInst;
extern std::atomic<LONG> g_cRef;

void DllAddRef();
void DllRelease();
