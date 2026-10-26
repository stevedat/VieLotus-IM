#pragma once

#include "Globals.h"
#include <string>

class CEditSession : public ITfEditSession {
public:
    CEditSession(
        ITfContext *pContext,
        int32_t backspaces,
        const std::wstring &insertText,
        bool bCommit
    );
    virtual ~CEditSession();

    // IUnknown
    STDMETHODIMP QueryInterface(REFIID riid, void **ppvObj) override;
    STDMETHODIMP_(ULONG) AddRef() override;
    STDMETHODIMP_(ULONG) Release() override;

    // ITfEditSession
    STDMETHODIMP DoEditSession(TfEditCookie ec) override;

private:
    std::atomic<LONG> m_cRef{1};
    ITfContext *m_pContext;
    int32_t m_backspaces;
    std::wstring m_insertText;
    bool m_bCommit;
};
