#include "EditSession.h"

namespace {

bool IsWin32EditOrRichEditHwnd(HWND hwnd) {
    if (!hwnd || !IsWindow(hwnd)) return false;
    WCHAR clsName[64] = {0};
    if (GetClassNameW(hwnd, clsName, 64) <= 0) return false;
    for (WCHAR *p = clsName; *p; ++p) {
        if (*p >= L'A' && *p <= L'Z') {
            *p = static_cast<WCHAR>(*p + (L'a' - L'A'));
        }
    }
    return wcsstr(clsName, L"edit") != nullptr;
}

} // namespace

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
    if (m_pResultCaretRange) {
        m_pResultCaretRange->Release();
        m_pResultCaretRange = nullptr;
    }
    if (m_pContext) {
        m_pContext->Release();
    }
}

ITfRange *CEditSession::DetachResultCaretRange() {
    ITfRange *pRange = m_pResultCaretRange;
    m_pResultCaretRange = nullptr;
    return pRange;
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

    BOOL fWasEmpty = TRUE;
    pRange->IsEmpty(ec, &fWasEmpty);

    // If backspaces > 0, expand range backwards
    LONG cchShifted = 0;
    if (m_backspaces > 0) {
        pRange->ShiftStart(ec, -m_backspaces, &cchShifted, nullptr);
    }

    const int32_t actualShifted = (cchShifted < 0) ? static_cast<int32_t>(-cchShifted) : 0;
    const int32_t missingBs = (m_backspaces > actualShifted) ? (m_backspaces - actualShifted) : 0;
    bool handledByWin32Edit = false;

    if (missingBs > 0) {
        if (actualShifted > 0) {
            pRange->SetText(ec, 0, L"", 0);
        }
        HWND hFocus = GetFocus();
        if (IsWin32EditOrRichEditHwnd(hFocus)) {
            DWORD dwStart = 0, dwEnd = 0;
            SendMessageW(hFocus, EM_GETSEL, reinterpret_cast<WPARAM>(&dwStart), reinterpret_cast<LPARAM>(&dwEnd));
            if (dwStart >= static_cast<DWORD>(missingBs)) {
                SendMessageW(
                    hFocus,
                    EM_SETSEL,
                    static_cast<WPARAM>(dwStart - static_cast<DWORD>(missingBs)),
                    static_cast<LPARAM>(dwEnd)
                );
                SendMessageW(hFocus, EM_REPLACESEL, TRUE, reinterpret_cast<LPARAM>(m_insertText.c_str()));
                handledByWin32Edit = true;
            }
        }
        if (!handledByWin32Edit && hFocus && IsWindow(hFocus)) {
            for (int32_t i = 0; i < missingBs; ++i) {
                SendMessageW(hFocus, WM_CHAR, VK_BACK, 1);
            }
        }
    } else if (fWasEmpty) {
        HWND hFocus = GetFocus();
        if (IsWin32EditOrRichEditHwnd(hFocus)) {
            DWORD dwStart = 0, dwEnd = 0;
            SendMessageW(hFocus, EM_GETSEL, reinterpret_cast<WPARAM>(&dwStart), reinterpret_cast<LPARAM>(&dwEnd));
            if (dwStart < dwEnd) {
                SendMessageW(hFocus, EM_REPLACESEL, TRUE, reinterpret_cast<LPARAM>(m_insertText.c_str()));
                handledByWin32Edit = true;
            }
        }
    }

    // Set new text (replaces the selected range) when not already replaced via EM_REPLACESEL
    if (!handledByWin32Edit) {
        if (!m_insertText.empty()) {
            pRange->SetText(ec, 0, m_insertText.c_str(), static_cast<LONG>(m_insertText.length()));
        } else if (m_backspaces > 0 || !fWasEmpty) {
            // Pure backspace or active selection delete
            pRange->SetText(ec, 0, L"", 0);
        }
    }

    // Move caret to end of modified text
    pRange->Collapse(ec, TF_ANCHOR_END);
    if (m_pResultCaretRange) {
        m_pResultCaretRange->Release();
        m_pResultCaretRange = nullptr;
    }
    pRange->Clone(&m_pResultCaretRange);

    sel.style.ase = TF_AE_NONE;
    sel.style.fInterimChar = FALSE;
    if (!handledByWin32Edit) {
        m_pContext->SetSelection(ec, 1, &sel);
    }

    pRange->Release();
    return S_OK;
}
