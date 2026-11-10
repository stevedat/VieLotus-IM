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

    LONG GetActualShifted() const { return m_actualShifted; }
    bool WasSelectionEmpty() const { return m_wasEmpty; }
    HRESULT GetSetTextHr() const { return m_hrSetText; }
    bool WasExecuted() const { return m_executed; }

private:
    std::atomic<LONG> m_cRef{1};
    ITfContext *m_pContext;
    int32_t m_backspaces;
    std::wstring m_insertText;
    bool m_bCommit;
    LONG m_actualShifted{0};
    bool m_wasEmpty{true};
    HRESULT m_hrSetText{S_OK};
    bool m_executed{false};
};
