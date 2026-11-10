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

void SafeEndAndClearComposition(
    TfEditCookie ec,
    ITfComposition **ppComposition,
    ITfContext **ppCompositionContext
) {
    if (ppComposition && *ppComposition) {
        ITfComposition *pComp = *ppComposition;
        *ppComposition = nullptr;
        if (ppCompositionContext && *ppCompositionContext) {
            (*ppCompositionContext)->Release();
            *ppCompositionContext = nullptr;
        }
        pComp->EndComposition(ec);
        pComp->Release();
    } else if (ppCompositionContext && *ppCompositionContext) {
        (*ppCompositionContext)->Release();
        *ppCompositionContext = nullptr;
    }
}

void SafeReleaseStaleComposition(
    ITfComposition **ppComposition,
    ITfContext **ppCompositionContext
) {
    if (ppComposition && *ppComposition) {
        (*ppComposition)->Release();
        *ppComposition = nullptr;
    }
    if (ppCompositionContext && *ppCompositionContext) {
        (*ppCompositionContext)->Release();
        *ppCompositionContext = nullptr;
    }
}

} // namespace

CEditSession::CEditSession(
    ITfContext *pContext,
    int32_t backspaces,
    const std::wstring &insertText,
    bool bCommit,
    bool bKeepComposition,
    ITfComposition **ppComposition,
    ITfContext **ppCompositionContext,
    ITfCompositionSink *pCompositionSink
) : m_pContext(pContext),
    m_backspaces(backspaces),
    m_insertText(insertText),
    m_bCommit(bCommit),
    m_bKeepComposition(bKeepComposition),
    m_ppComposition(ppComposition),
    m_ppCompositionContext(ppCompositionContext),
    m_pCompositionSink(pCompositionSink) {
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

    if (m_ppComposition && *m_ppComposition &&
        m_ppCompositionContext && *m_ppCompositionContext &&
        *m_ppCompositionContext != m_pContext) {
        SafeReleaseStaleComposition(m_ppComposition, m_ppCompositionContext);
    }

    // Pure composition-termination session (e.g. before non-eaten Enter/Tab/Arrow key)
    if (m_backspaces == 0 && m_insertText.empty() && !m_bKeepComposition) {
        SafeEndAndClearComposition(ec, m_ppComposition, m_ppCompositionContext);
        m_executed = true;
        return S_OK;
    }

    TF_SELECTION sel{};
    ULONG cFetched = 0;

    // Get current caret selection
    if (FAILED(m_pContext->GetSelection(ec, TF_DEFAULT_SELECTION, 1, &sel, &cFetched)) || cFetched == 0) {
        return E_FAIL;
    }

    ITfRange *pRange = sel.range;
    if (!pRange) return E_FAIL;

    BOOL fWasEmpty = TRUE;
    pRange->IsEmpty(ec, &fWasEmpty);
    m_wasEmpty = (fWasEmpty != FALSE);

    // If backspaces > 0 and there was no active selection, expand range backwards
    LONG cchShifted = 0;
    if (m_backspaces > 0 && fWasEmpty) {
        pRange->ShiftStart(ec, -m_backspaces, &cchShifted, nullptr);
    }
    m_actualShifted = cchShifted;

    // Anchor composition start with backward gravity before mutating text
    ITfRange *pCompStartAnchor = nullptr;
    if (m_ppComposition && *m_ppComposition) {
        ITfRange *pExistingCompRange = nullptr;
        if (SUCCEEDED((*m_ppComposition)->GetRange(&pExistingCompRange)) && pExistingCompRange) {
            if (SUCCEEDED(pExistingCompRange->Clone(&pCompStartAnchor)) && pCompStartAnchor) {
                pCompStartAnchor->Collapse(ec, TF_ANCHOR_START);
                LONG lCmp = 0;
                if (SUCCEEDED(pCompStartAnchor->CompareStart(ec, pRange, TF_ANCHOR_START, &lCmp)) && lCmp > 0) {
                    pCompStartAnchor->ShiftStartToRange(ec, pRange, TF_ANCHOR_START);
                    pCompStartAnchor->Collapse(ec, TF_ANCHOR_START);
                }
                pCompStartAnchor->SetGravity(ec, TF_GRAVITY_BACKWARD, TF_GRAVITY_BACKWARD);
            }
            pExistingCompRange->Release();
        }
    }
    if (!pCompStartAnchor) {
        if (SUCCEEDED(pRange->Clone(&pCompStartAnchor)) && pCompStartAnchor) {
            pCompStartAnchor->Collapse(ec, TF_ANCHOR_START);
            pCompStartAnchor->SetGravity(ec, TF_GRAVITY_BACKWARD, TF_GRAVITY_BACKWARD);
        }
    }

    const int32_t actualShifted = (cchShifted < 0) ? static_cast<int32_t>(-cchShifted) : 0;
    const int32_t missingBs = (fWasEmpty && m_backspaces > actualShifted) ? (m_backspaces - actualShifted) : 0;
    bool handledByWin32Edit = false;
    std::wstring effectiveInsertText = m_insertText;

    if (missingBs > 0) {
        HWND hFocus = GetFocus();
        if (IsWin32EditOrRichEditHwnd(hFocus)) {
            if (actualShifted > 0) {
                pRange->SetText(ec, 0, L"", 0);
            }
            DWORD dwStart = 0, dwEnd = 0;
            SendMessageW(hFocus, EM_GETSEL, reinterpret_cast<WPARAM>(&dwStart), reinterpret_cast<LPARAM>(&dwEnd));
            if (dwStart >= static_cast<DWORD>(missingBs)) {
                SendMessageW(
                    hFocus,
                    EM_SETSEL,
                    static_cast<WPARAM>(dwStart - static_cast<DWORD>(missingBs)),
                    static_cast<LPARAM>(dwEnd)
                );
                SendMessageW(hFocus, EM_REPLACESEL, TRUE, reinterpret_cast<LPARAM>(effectiveInsertText.c_str()));
                handledByWin32Edit = true;
                m_actualShifted = -static_cast<LONG>(m_backspaces);
                m_hrSetText = S_OK;
            }
        } else if (m_bCommit && actualShifted > 0 && effectiveInsertText.size() > static_cast<size_t>(missingBs)) {
            effectiveInsertText.erase(0, static_cast<size_t>(missingBs));
        }
    } else if (fWasEmpty) {
        HWND hFocus = GetFocus();
        if (IsWin32EditOrRichEditHwnd(hFocus)) {
            DWORD dwStart = 0, dwEnd = 0;
            SendMessageW(hFocus, EM_GETSEL, reinterpret_cast<WPARAM>(&dwStart), reinterpret_cast<LPARAM>(&dwEnd));
            if (dwStart < dwEnd) {
                SendMessageW(hFocus, EM_REPLACESEL, TRUE, reinterpret_cast<LPARAM>(effectiveInsertText.c_str()));
                handledByWin32Edit = true;
                m_hrSetText = S_OK;
            }
        }
    }

    if (!handledByWin32Edit) {
        // Ensure forward gravity on the end anchor so newly inserted text is included in pRange
        pRange->SetGravity(ec, TF_GRAVITY_BACKWARD, TF_GRAVITY_FORWARD);

        // Set new text (replaces the selected range)
        if (!effectiveInsertText.empty()) {
            m_hrSetText = pRange->SetText(ec, 0, effectiveInsertText.c_str(), static_cast<LONG>(effectiveInsertText.length()));
        } else if (m_backspaces > 0 || !fWasEmpty) {
            // Pure backspace delete or active selection delete
            m_hrSetText = pRange->SetText(ec, 0, L"", 0);
        }

        // Move caret to end of modified text
        pRange->Collapse(ec, TF_ANCHOR_END);
        sel.style.ase = TF_AE_NONE;
        sel.style.fInterimChar = FALSE;
        m_pContext->SetSelection(ec, 1, &sel);

        // Maintain ITfComposition lifecycle so Chromium TSFTextStore & Univer DocIMEInputController
        // track the active syllable via SetCompositionText / CommitText instead of ExtendSelectionAndDelete.
        if (m_ppComposition) {
            if (m_bKeepComposition) {
                if (*m_ppComposition == nullptr) {
                    if (pCompStartAnchor) {
                        pCompStartAnchor->ShiftEndToRange(ec, pRange, TF_ANCHOR_END);
                        BOOL fCompEmpty = TRUE;
                        pCompStartAnchor->IsEmpty(ec, &fCompEmpty);
                        if (!fCompEmpty) {
                            ITfContextComposition *pCtxComp = nullptr;
                            if (SUCCEEDED(m_pContext->QueryInterface(IID_ITfContextComposition, reinterpret_cast<void **>(&pCtxComp))) && pCtxComp) {
                                pCtxComp->StartComposition(ec, pCompStartAnchor, m_pCompositionSink, m_ppComposition);
                                pCtxComp->Release();
                                if (*m_ppComposition && m_ppCompositionContext) {
                                    *m_ppCompositionContext = m_pContext;
                                    m_pContext->AddRef();
                                }
                            }
                        }
                    }
                } else {
                    (*m_ppComposition)->ShiftEnd(ec, pRange);
                    if (pCompStartAnchor) {
                        (*m_ppComposition)->ShiftStart(ec, pCompStartAnchor);
                        (*m_ppComposition)->ShiftEnd(ec, pRange);
                    }
                    ITfRange *pUpdatedCompRange = nullptr;
                    if (SUCCEEDED((*m_ppComposition)->GetRange(&pUpdatedCompRange)) && pUpdatedCompRange) {
                        BOOL fUpdatedEmpty = TRUE;
                        pUpdatedCompRange->IsEmpty(ec, &fUpdatedEmpty);
                        pUpdatedCompRange->Release();
                        if (fUpdatedEmpty) {
                            SafeEndAndClearComposition(ec, m_ppComposition, m_ppCompositionContext);
                        }
                    }
                }
            } else {
                if (*m_ppComposition != nullptr) {
                    (*m_ppComposition)->ShiftEnd(ec, pRange);
                    if (pCompStartAnchor) {
                        (*m_ppComposition)->ShiftStart(ec, pCompStartAnchor);
                        (*m_ppComposition)->ShiftEnd(ec, pRange);
                    }
                    SafeEndAndClearComposition(ec, m_ppComposition, m_ppCompositionContext);
                }
            }
        }
    } else {
        SafeEndAndClearComposition(ec, m_ppComposition, m_ppCompositionContext);
    }

    if (pCompStartAnchor) {
        pCompStartAnchor->Release();
    }
    pRange->Release();
    m_executed = true;
    return S_OK;
}
