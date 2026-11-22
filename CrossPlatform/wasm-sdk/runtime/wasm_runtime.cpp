/*
 * VieLotusIM (Sen Việt) — Freestanding wasm32 Runtime
 * License: MIT
 *
 * Provides minimal libc memory/string primitives, a fixed-slot free-list pool
 * for concurrent engine sessions (zero fragmentation, zero wraparound), and a
 * dedicated UTF-8 scratch ring buffer for JS <-> WASM string marshaling.
 */

#include <stddef.h>
#include <stdint.h>

extern "C" {

void *memcpy(void *dst, const void *src, size_t n) {
    auto *d = static_cast<uint8_t *>(dst);
    const auto *s = static_cast<const uint8_t *>(src);
    for (size_t i = 0; i < n; ++i) d[i] = s[i];
    return dst;
}

void *memmove(void *dst, const void *src, size_t n) {
    auto *d = static_cast<uint8_t *>(dst);
    const auto *s = static_cast<const uint8_t *>(src);
    if (d < s) {
        for (size_t i = 0; i < n; ++i) d[i] = s[i];
    } else if (d > s) {
        for (size_t i = n; i > 0; --i) d[i - 1] = s[i - 1];
    }
    return dst;
}

void *memset(void *dst, int c, size_t n) {
    auto *d = static_cast<uint8_t *>(dst);
    const auto byte = static_cast<uint8_t>(c);
    for (size_t i = 0; i < n; ++i) d[i] = byte;
    return dst;
}

int memcmp(const void *a, const void *b, size_t n) {
    const auto *p = static_cast<const uint8_t *>(a);
    const auto *q = static_cast<const uint8_t *>(b);
    for (size_t i = 0; i < n; ++i) {
        if (p[i] != q[i]) return (p[i] < q[i]) ? -1 : 1;
    }
    return 0;
}

size_t strlen(const char *s) {
    size_t n = 0;
    while (s && s[n]) ++n;
    return n;
}

} // extern "C"

namespace {

constexpr size_t kMaxSlots = 32;
constexpr size_t kSlotBytes = 16384;
constexpr size_t kScratchBytes = 65536;

alignas(16) uint8_t g_slots[kMaxSlots][kSlotBytes];
bool g_slot_used[kMaxSlots]{};
size_t g_active_slots = 0;

alignas(16) uint8_t g_str_arena[kScratchBytes];
size_t g_str_offset = 0;

} // namespace

void *operator new(size_t sz) {
    if (sz <= kSlotBytes) {
        for (size_t i = 0; i < kMaxSlots; ++i) {
            if (!g_slot_used[i]) {
                g_slot_used[i] = true;
                ++g_active_slots;
                return g_slots[i];
            }
        }
    }
    __builtin_trap();
}

void operator delete(void *ptr) noexcept {
    if (!ptr) return;
    const auto addr = reinterpret_cast<uintptr_t>(ptr);
    const auto base = reinterpret_cast<uintptr_t>(&g_slots[0][0]);
    if (addr >= base && addr < base + sizeof(g_slots)) {
        const size_t idx = (addr - base) / kSlotBytes;
        if (idx < kMaxSlots && g_slot_used[idx]) {
            g_slot_used[idx] = false;
            --g_active_slots;
        }
    }
}

void operator delete(void *ptr, size_t) noexcept {
    operator delete(ptr);
}

extern "C" {

__attribute__((visibility("default")))
void *vielotus_wasm_alloc(size_t sz) {
    const size_t aligned = (sz + 7) & ~size_t(7);
    if (aligned > sizeof(g_str_arena)) return nullptr;
    if (g_str_offset + aligned > sizeof(g_str_arena)) g_str_offset = 0;
    void *ptr = &g_str_arena[g_str_offset];
    g_str_offset += aligned;
    return ptr;
}

__attribute__((visibility("default")))
uint32_t vielotus_wasm_max_sessions(void) {
    return static_cast<uint32_t>(kMaxSlots);
}

__attribute__((visibility("default")))
uint32_t vielotus_wasm_active_sessions(void) {
    return static_cast<uint32_t>(g_active_slots);
}

__attribute__((visibility("default")))
uint32_t vielotus_wasm_scratch_capacity(void) {
    return static_cast<uint32_t>(kScratchBytes);
}

} // extern "C"
