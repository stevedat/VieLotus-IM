#include "Globals.h"

// {6E4E2102-F9CD-433D-B496-303CE03A6507}
const GUID IID_ITfTextInputProcessorEx_Compat = {
    0x6e4e2102, 0xf9cd, 0x433d, { 0xb4, 0x96, 0x30, 0x3c, 0xe0, 0x3a, 0x65, 0x07 }
};

// {C7B08E9D-4762-4C97-8B1F-522197A598DC}
const GUID CLSID_VieLotusTIP = {
    0xc7b08e9d, 0x4762, 0x4c97, { 0x8b, 0x1f, 0x52, 0x21, 0x97, 0xa5, 0x98, 0xdc }
};

// {8E2A7B44-5A1F-4B82-9B7C-123456789ABC}
const GUID GUID_VieLotusProfile = {
    0x8e2a7b44, 0x5a1f, 0x4b82, { 0x9b, 0x7c, 0x12, 0x34, 0x56, 0x78, 0x9a, 0xbc }
};

// {8E2A7B45-5A1F-4B82-9B7C-123456789ABC}
const GUID GUID_VieLotusProfileVNI = {
    0x8e2a7b45, 0x5a1f, 0x4b82, { 0x9b, 0x7c, 0x12, 0x34, 0x56, 0x78, 0x9a, 0xbc }
};

HINSTANCE g_hInst = nullptr;
std::atomic<LONG> g_cRef{0};

void DllAddRef() {
    g_cRef.fetch_add(1, std::memory_order_relaxed);
}

void DllRelease() {
    g_cRef.fetch_sub(1, std::memory_order_relaxed);
}
