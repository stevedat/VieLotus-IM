#pragma once

#include "Globals.h"
#include "TsfGameGuardLogic.h"

class CVieLotusTIP;

class CLangBarItemButton : public ITfLangBarItemButton,
                           public ITfSource {
public:
    explicit CLangBarItemButton(CVieLotusTIP *pOwner, bool initialVietnamese, bool initialVni);
    virtual ~CLangBarItemButton();

    // IUnknown
    STDMETHODIMP QueryInterface(REFIID riid, void **ppvObj) override;
    STDMETHODIMP_(ULONG) AddRef() override;
    STDMETHODIMP_(ULONG) Release() override;

    // ITfLangBarItem
    STDMETHODIMP GetInfo(TF_LANGBARITEMINFO *pInfo) override;
    STDMETHODIMP GetStatus(DWORD *pdwStatus) override;
    STDMETHODIMP Show(BOOL fShow) override;
    STDMETHODIMP GetTooltipString(BSTR *pbstrToolTip) override;

    // ITfLangBarItemButton
    STDMETHODIMP OnClick(TfLBIClick click, POINT pt, const RECT *prcArea) override;
    STDMETHODIMP InitMenu(ITfMenu *pMenu) override;
    STDMETHODIMP OnMenuSelect(UINT wID) override;
    STDMETHODIMP GetIcon(HICON *phIcon) override;
    STDMETHODIMP GetText(BSTR *pbstrText) override;

    // ITfSource
    STDMETHODIMP AdviseSink(REFIID riid, IUnknown *punk, DWORD *pdwCookie) override;
    STDMETHODIMP UnadviseSink(DWORD dwCookie) override;

    void DetachOwner();
    void UpdateState(bool isVietnamese, bool isVni, bool forceNotify = false);

private:
    static constexpr DWORD kSinkCookie = 0x564C4249u; // 'VLBI'

    std::atomic<LONG> m_cRef{1};
    CVieLotusTIP *m_pOwner{nullptr};
    ITfLangBarItemSink *m_pSink{nullptr};
    DWORD m_status{0};
    bool m_isVietnamese{true};
    bool m_isVni{false};
};
