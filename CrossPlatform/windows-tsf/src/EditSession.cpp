#include "EditSession.h"

CEditSession::CEditSession(
    ITfContext *pContext,
    int32_t backspaces,
    const std::wstring &insertText,
    bool bCommit
) : m_pContext(pContext),
    m_backspaces(backspaces),
    m_insertText(insertText),
    m_bCommit(bCommit) {
    if (m_pContext) {
        m_pContext->AddRef();
    }
}

CEditSession::~CEditSession() {
    if (m_pContext) {
        m_pContext->Release();
    }
}

STDMETHODIMP CEditSession::QueryInterface(REFIID riid, void **ppvObj) {
    if (!ppvObj) return E_POINTER;
    *ppvObj = nullptr;

    if (IsEqualIID(riid, IID_IUnknown) || IsEqualIID(riid, IID_ITfEditSession)) {
        *ppvObj = static_cast<ITfEditSession *>(this);
        AddRef();
        return S_OK;
    }
    return E_NOINTERFACE;
}

STDMETHODIMP_(ULONG) CEditSession::AddRef() {
    return m_cRef.fetch_add(1, std::memory_order_relaxed) + 1;
}

STDMETHODIMP_(ULONG) CEditSession::Release() {
    LONG cRef = m_cRef.fetch_sub(1, std::memory_order_relaxed) - 1;
    if (cRef == 0) {
        delete this;
    }
    return cRef;
}

STDMETHODIMP CEditSession::DoEditSession(TfEditCookie ec) {
    if (!m_pContext) return E_FAIL;

    TF_SELECTION sel;
    ULONG cFetched = 0;

    // Get current caret selection
    if (FAILED(m_pContext->GetSelection(ec, TF_DEFAULT_SELECTION, 1, &sel, &cFetched)) || cFetched == 0) {
        return E_FAIL;
    }

    ITfRange *pRange = sel.range;
    if (!pRange) return E_FAIL;

    // If backspaces > 0, expand range backwards
    if (m_backspaces > 0) {
        LONG cchShifted = 0;
        pRange->ShiftStart(ec, -m_backspaces, &cchShifted, nullptr);
    }

    // Set new text (replaces the selected range)
    if (!m_insertText.empty()) {
        pRange->SetText(ec, 0, m_insertText.c_str(), static_cast<LONG>(m_insertText.length()));
    } else if (m_backspaces > 0) {
        // Pure backspace delete
        pRange->SetText(ec, 0, L"", 0);
    }

    // Move caret to end of modified text
    pRange->Collapse(ec, TF_ANCHOR_END);
    sel.style.ase = TF_AE_NONE;
    sel.style.fInterimChar = FALSE;
    m_pContext->SetSelection(ec, 1, &sel);

    pRange->Release();
    return S_OK;
}
