#pragma once

#include "Globals.h"

class CClassFactory : public IClassFactory {
public:
    CClassFactory();
    virtual ~CClassFactory();

    // IUnknown
    STDMETHODIMP QueryInterface(REFIID riid, void **ppvObj) override;
    STDMETHODIMP_(ULONG) AddRef() override;
    STDMETHODIMP_(ULONG) Release() override;

    // IClassFactory
    STDMETHODIMP CreateInstance(IUnknown *pUnkOuter, REFIID riid, void **ppvObj) override;
    STDMETHODIMP LockServer(BOOL fLock) override;

private:
    std::atomic<LONG> m_cRef{1};
};
