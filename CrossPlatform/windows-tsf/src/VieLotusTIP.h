#pragma once

#include "Globals.h"
#if defined(VIELOTUS_EMBEDDED_ENGINE)
#include "WindowsNativeEngine.h"
#endif
#include <string>

class CVieLotusTIP : public ITfTextInputProcessorEx,
                     public ITfKeyEventSink,
                     public ITfThreadMgrEventSink,
                     public ITfActiveLanguageProfileNotifySink,
                     public ITfCompositionSink {
public:
    CVieLotusTIP();
    virtual ~CVieLotusTIP();

    // IUnknown
    STDMETHODIMP QueryInterface(REFIID riid, void **ppvObj) override;
    STDMETHODIMP_(ULONG) AddRef() override;
    STDMETHODIMP_(ULONG) Release() override;

    // ITfTextInputProcessor
    STDMETHODIMP Activate(ITfThreadMgr *ptim, TfClientId tid) override;
    STDMETHODIMP Deactivate() override;

    // ITfTextInputProcessorEx
    STDMETHODIMP ActivateEx(ITfThreadMgr *ptim, TfClientId tid, DWORD dwFlags) override;

    // ITfKeyEventSink
    STDMETHODIMP OnSetFocus(BOOL fForeground) override;
    STDMETHODIMP OnTestKeyDown(ITfContext *pic, WPARAM wParam, LPARAM lParam, BOOL *pfEaten) override;
    STDMETHODIMP OnKeyDown(ITfContext *pic, WPARAM wParam, LPARAM lParam, BOOL *pfEaten) override;
    STDMETHODIMP OnTestKeyUp(ITfContext *pic, WPARAM wParam, LPARAM lParam, BOOL *pfEaten) override;
    STDMETHODIMP OnKeyUp(ITfContext *pic, WPARAM wParam, LPARAM lParam, BOOL *pfEaten) override;
    STDMETHODIMP OnPreservedKey(ITfContext *pic, REFGUID rguid, BOOL *pfEaten) override;

    // ITfThreadMgrEventSink
    STDMETHODIMP OnInitDocumentMgr(ITfDocumentMgr *pdim) override;
    STDMETHODIMP OnUninitDocumentMgr(ITfDocumentMgr *pdim) override;
    STDMETHODIMP OnSetFocus(ITfDocumentMgr *pdimFocus, ITfDocumentMgr *pdimPrevFocus) override;
    STDMETHODIMP OnPushContext(ITfContext *pic) override;
    STDMETHODIMP OnPopContext(ITfContext *pic) override;

    // ITfActiveLanguageProfileNotifySink
    STDMETHODIMP OnActivated(REFCLSID clsid, REFGUID guidProfile, BOOL fActivated) override;

    // ITfCompositionSink
    STDMETHODIMP OnCompositionTerminated(TfEditCookie ecWrite, ITfComposition *pComposition) override;

private:
    std::atomic<LONG> m_cRef{1};
    ITfThreadMgr *m_pThreadMgr{nullptr};
    TfClientId m_tfClientId{TF_CLIENTID_NULL};
    DWORD m_dwThreadMgrEventSinkCookie{TF_INVALID_COOKIE};
    DWORD m_dwProfileNotifySinkCookie{TF_INVALID_COOKIE};

    vielotus_session_t m_session{nullptr};
#if defined(VIELOTUS_EMBEDDED_ENGINE)
    vielotus_win::WindowsNativeEngine m_nativeEngine{};
#endif
    ITfComposition *m_pComposition{nullptr};

    bool m_isVietnameseMode{true};
    bool m_isVniMode{false};
    bool m_isRemoteProcess{false};
    bool m_hasManualProcessOverride{false};
    bool m_manualProcessVietnameseMode{true};
    std::wstring m_currentExeName{};

    void InitSession();
    void CleanSession();
    void ApplyVniMode(bool isVni, bool persistToRegistry);
    void ReloadUserPreferences();
    void SyncActiveLanguageProfile();
    void ResetComposingSession();
    bool IsComposingSession() const;
    int32_t FeedCharSession(uint32_t codePoint);
    int32_t FeedBackspaceSession();
    int32_t CommitWordSession();
    int32_t GetLastBackspacesSession() const;
    const char *GetLastTextSession() const;
    void ExecuteEditSession(ITfContext *pic, int32_t backspaces, const std::wstring &text, bool bCommit);
};
