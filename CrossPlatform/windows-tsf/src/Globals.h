#pragma once

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif

#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0A00
#endif

#include <windows.h>
#include <msctf.h>
#include <olectl.h>
#include <atomic>
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

// IID for ITfTextInputProcessorEx: {6E4E2102-F9CD-433D-B496-303CE03A6507}
extern const GUID IID_ITfTextInputProcessorEx_Compat;

// CLSID for VieLotusTIP: {C7B08E9D-4762-4C97-8B1F-522197A598DC}
extern const GUID CLSID_VieLotusTIP;

// Profile GUID for VieLotusTIP (Telex): {8E2A7B44-5A1F-4B82-9B7C-123456789ABC}
extern const GUID GUID_VieLotusProfile;

// Profile GUID for VieLotusTIP (VNI): {8E2A7B45-5A1F-4B82-9B7C-123456789ABC}
extern const GUID GUID_VieLotusProfileVNI;

// Global Module Handle & COM Reference Counter
extern HINSTANCE g_hInst;
extern std::atomic<LONG> g_cRef;

void DllAddRef();
void DllRelease();
