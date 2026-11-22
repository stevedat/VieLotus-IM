#include "EditSession.h"
#include "TsfGameGuardLogic.h"

namespace {

bool IsClassicWin32EditHwnd(HWND hwnd) {
    if (!hwnd || !IsWindow(hwnd)) return false;
    WCHAR clsName[64] = {0};
    if (GetClassNameW(hwnd, clsName, 64) <= 0) return false;
    return _wcsicmp(clsName, L"edit") == 0;
}

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
    m_executed = true;
    m_deleteRefused = false;
    m_actualShifted = 0;
    m_hrSetText = S_OK;

    if (!m_pContext) {
        m_hrSetText = E_FAIL;
        return E_FAIL;
    }

    if (m_ppComposition && *m_ppComposition &&
        m_ppCompositionContext && *m_ppCompositionContext &&
        *m_ppCompositionContext != m_pContext) {
        SafeReleaseStaleComposition(m_ppComposition, m_ppCompositionContext);
    }

    // Pure composition-termination session (e.g. before non-eaten Enter/Tab/Arrow key)
    if (m_backspaces == 0 && m_insertText.empty() && !m_bKeepComposition) {
        SafeEndAndClearComposition(ec, m_ppComposition, m_ppCompositionContext);
        return S_OK;
    }

    // Classic Win32 "Edit" controls do not implement ITextStoreACP; CUAS wraps them with an IMM32
    // composition buffer that delays WM_CHAR delivery until EndComposition, causing caret races
    // when arrow keys or mouse clicks occur mid-word. Always mutate classic Win32 Edit controls
    // synchronously via EM_GETSEL / EM_SETSEL / EM_REPLACESEL without opening an ITfComposition.
    HWND hFocusTop = GetFocus();
    if (IsClassicWin32EditHwnd(hFocusTop)) {
        SafeEndAndClearComposition(ec, m_ppComposition, m_ppCompositionContext);
        if ((GetWindowLongW(hFocusTop, GWL_STYLE) & ES_READONLY) != 0) {
            m_hrSetText = TS_E_READONLY;
            return TS_E_READONLY;
        }
        DWORD dwStart = 0, dwEnd = 0;
        SendMessageW(hFocusTop, EM_GETSEL, reinterpret_cast<WPARAM>(&dwStart), reinterpret_cast<LPARAM>(&dwEnd));
        if (!vielotus_tsf_guard::CanClassicWin32EditDelete(
                m_backspaces,
                static_cast<uint32_t>(dwStart),
                static_cast<uint32_t>(dwEnd)
            )) {
            m_wasEmpty = (dwStart == dwEnd);
            m_actualShifted = 0;
            m_deleteRefused = true;
            m_hrSetText = S_FALSE;
            return S_FALSE;
        }
        if (dwStart < dwEnd) {
            m_wasEmpty = false;
            SendMessageW(hFocusTop, EM_REPLACESEL, TRUE, reinterpret_cast<LPARAM>(m_insertText.c_str()));
            m_actualShifted = 0;
            m_hrSetText = S_OK;
        } else {
            m_wasEmpty = true;
            const DWORD reqBs = (m_backspaces > 0) ? static_cast<DWORD>(m_backspaces) : 0;
            if (reqBs > 0) {
                SendMessageW(
                    hFocusTop,
                    EM_SETSEL,
                    static_cast<WPARAM>(dwStart - reqBs),
                    static_cast<LPARAM>(dwEnd)
                );
            }
            if (reqBs > 0 || !m_insertText.empty()) {
                SendMessageW(hFocusTop, EM_REPLACESEL, TRUE, reinterpret_cast<LPARAM>(m_insertText.c_str()));
            }
            m_actualShifted = -static_cast<LONG>(reqBs);
            m_hrSetText = S_OK;
        }
        return S_OK;
    }

    TF_SELECTION sel{};
    ULONG cFetched = 0;

    // Get current caret selection
    if (FAILED(m_pContext->GetSelection(ec, TF_DEFAULT_SELECTION, 1, &sel, &cFetched)) || cFetched == 0) {
        SafeEndAndClearComposition(ec, m_ppComposition, m_ppCompositionContext);
        m_hrSetText = E_FAIL;
        return E_FAIL;
    }

    ITfRange *pRange = sel.range;
    if (!pRange) {
        SafeEndAndClearComposition(ec, m_ppComposition, m_ppCompositionContext);
        m_hrSetText = E_FAIL;
        return E_FAIL;
    }

    BOOL fWasEmpty = TRUE;
    pRange->IsEmpty(ec, &fWasEmpty);
    m_wasEmpty = (fWasEmpty != FALSE);

    // If backspaces > 0 and there was no active selection, expand range backwards
    LONG cchShifted = 0;
    if (m_backspaces > 0 && fWasEmpty) {
        HRESULT hrShift = pRange->ShiftStart(ec, -m_backspaces, &cchShifted, nullptr);
        if (FAILED(hrShift)) {
            cchShifted = 0;
        }
    }
    m_actualShifted = cchShifted;
    const int32_t actualShifted = (cchShifted < 0) ? static_cast<int32_t>(-cchShifted) : 0;

    HWND hFocus = GetFocus();
    const bool isWin32Edit = IsWin32EditOrRichEditHwnd(hFocus);
    const bool isWin32ReadOnly = isWin32Edit && ((GetWindowLongW(hFocus, GWL_STYLE) & ES_READONLY) != 0);
    DWORD win32SelStart = 0, win32SelEnd = 0;
    bool win32SelEmpty = false;
    if (isWin32Edit && !isWin32ReadOnly) {
        SendMessageW(hFocus, EM_GETSEL, reinterpret_cast<WPARAM>(&win32SelStart), reinterpret_cast<LPARAM>(&win32SelEnd));
        win32SelEmpty = (win32SelStart == win32SelEnd);
    }

    const auto shiftPlan = vielotus_tsf_guard::PlanRangeShiftEdit(
        m_backspaces,
        actualShifted,
        fWasEmpty != FALSE,
        isWin32Edit && !isWin32ReadOnly,
        win32SelEmpty,
        static_cast<uint32_t>(win32SelStart)
    );

    if (shiftPlan == vielotus_tsf_guard::ShiftEditPlan::RefuseNoMutation) {
        // Host shifted 0 or only part of the requested backspaces (e.g. non-standard game chat
        // control or externally cleared/truncated field). Abort with zero mutation so replacement
        // text can never duplicate or overwrite unrelated characters.
        SafeEndAndClearComposition(ec, m_ppComposition, m_ppCompositionContext);
        pRange->Release();
        m_deleteRefused = true;
        m_hrSetText = S_FALSE;
        return S_FALSE;
    }

    if (shiftPlan == vielotus_tsf_guard::ShiftEditPlan::FallbackWin32Edit) {
        // End composition metadata without deleting any text first, then re-verify EM_GETSEL
        // and execute ONE atomic EM_SETSEL + EM_REPLACESEL across the full m_backspaces span.
        // If the caret no longer covers m_backspaces, refuse with zero characters deleted.
        SafeEndAndClearComposition(ec, m_ppComposition, m_ppCompositionContext);
        DWORD dwStart = 0, dwEnd = 0;
        SendMessageW(hFocus, EM_GETSEL, reinterpret_cast<WPARAM>(&dwStart), reinterpret_cast<LPARAM>(&dwEnd));
        if (!vielotus_tsf_guard::CanWin32AtomicFallbackReplace(
                m_backspaces,
                static_cast<uint32_t>(dwStart),
                static_cast<uint32_t>(dwEnd)
            )) {
            pRange->Release();
            m_deleteRefused = true;
            m_hrSetText = S_FALSE;
            return S_FALSE;
        }
        const DWORD reqBs = static_cast<DWORD>(m_backspaces);
        SendMessageW(
            hFocus,
            EM_SETSEL,
            static_cast<WPARAM>(dwStart - reqBs),
            static_cast<LPARAM>(dwEnd)
        );
        SendMessageW(hFocus, EM_REPLACESEL, TRUE, reinterpret_cast<LPARAM>(m_insertText.c_str()));
        pRange->Release();
        m_actualShifted = -static_cast<LONG>(m_backspaces);
        m_hrSetText = S_OK;
        return S_OK;
    }

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

    bool handledByWin32Edit = false;

    if (fWasEmpty && isWin32Edit && !isWin32ReadOnly && win32SelStart < win32SelEnd) {
        SendMessageW(hFocus, EM_REPLACESEL, TRUE, reinterpret_cast<LPARAM>(m_insertText.c_str()));
        handledByWin32Edit = true;
        m_hrSetText = S_OK;
    }

    if (!handledByWin32Edit) {
        // Ensure forward gravity on the end anchor so newly inserted text is included in pRange
        pRange->SetGravity(ec, TF_GRAVITY_BACKWARD, TF_GRAVITY_FORWARD);

        // Set new text (replaces the selected range)
        if (!m_insertText.empty()) {
            m_hrSetText = pRange->SetText(ec, 0, m_insertText.c_str(), static_cast<LONG>(m_insertText.length()));
        } else if (m_backspaces > 0 || !fWasEmpty) {
            // Pure backspace delete or active selection delete
            m_hrSetText = pRange->SetText(ec, 0, L"", 0);
        }

        if (FAILED(m_hrSetText)) {
            SafeEndAndClearComposition(ec, m_ppComposition, m_ppCompositionContext);
            if (pCompStartAnchor) {
                pCompStartAnchor->Release();
            }
            pRange->Release();
            return m_hrSetText;
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
    return S_OK;
}
