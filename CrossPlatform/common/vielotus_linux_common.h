/*
 * VieLotusIM (Sen Việt) — Shared Linux Engine Support Header (IBus & Fcitx5)
 * Copyright (c) 2026 Trần Phát Đạt (Steve Dat) <ttd1232004@gmail.com>
 * SPDX-License-Identifier: MIT
 *
 * 100% Clean-Room C11 / C++20 header-only utilities shared between
 * `ibus-vielotus` and `fcitx5-vielotus`:
 *   1. Precomposed UTF-8 (NFC) Vietnamese syllable key reconstruction
 *   2. Non-destructive `config.env` parser & atomic key-preserving merge writer
 *   3. `PresentationRules` (`typing-modes.yml`) glob parser & matcher
 *      (ported from `Sources/VieLotusCore/PresentationRules.swift`)
 *   4. `mtime`-gated `macros.json` hot-reloader via `vielotus.h` C-ABI
 *   5. Developer Mode inline (`...`) & fenced (```...```) code bypass FSM
 */

#ifndef VIELOTUS_LINUX_COMMON_H
#define VIELOTUS_LINUX_COMMON_H

#include <errno.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#include "vielotus.h"

#ifdef __cplusplus
extern "C" {
#endif

#if defined(__GNUC__) || defined(__clang__)
#define VL_COMMON_UNUSED __attribute__((unused))
#else
#define VL_COMMON_UNUSED
#endif

/* ==========================================================================
 * 1. Precomposed UTF-8 Vietnamese Syllable Key Reconstruction
 * ========================================================================== */

typedef struct {
    const char *lower_utf8;
    const char *upper_utf8;
    char lower_base;
    char upper_base;
    uint8_t mod;  /* 0=none, 1=d-stroke, 2=circumflex(^), 3=breve(ă), 4=horn(ư/ơ) */
    uint8_t tone; /* 0=none, 1=grave(f/2), 2=acute(s/1), 3=hook(r/3), 4=tilde(x/4), 5=dot(j/5) */
} vl_utf8_char_map_t;

static const vl_utf8_char_map_t kVlVnUtf8Map[] VL_COMMON_UNUSED = {
    { "đ", "Đ", 'd', 'D', 1, 0 },
    { "à", "À", 'a', 'A', 0, 1 }, { "á", "Á", 'a', 'A', 0, 2 }, { "ả", "Ả", 'a', 'A', 0, 3 }, { "ã", "Ã", 'a', 'A', 0, 4 }, { "ạ", "Ạ", 'a', 'A', 0, 5 },
    { "ă", "Ă", 'a', 'A', 3, 0 }, { "ằ", "Ằ", 'a', 'A', 3, 1 }, { "ắ", "Ắ", 'a', 'A', 3, 2 }, { "ẳ", "Ẳ", 'a', 'A', 3, 3 }, { "ẵ", "Ẵ", 'a', 'A', 3, 4 }, { "ặ", "Ặ", 'a', 'A', 3, 5 },
    { "â", "Â", 'a', 'A', 2, 0 }, { "ầ", "Ầ", 'a', 'A', 2, 1 }, { "ấ", "Ấ", 'a', 'A', 2, 2 }, { "ẩ", "Ẩ", 'a', 'A', 2, 3 }, { "ẫ", "Ẫ", 'a', 'A', 2, 4 }, { "ậ", "Ậ", 'a', 'A', 2, 5 },
    { "è", "È", 'e', 'E', 0, 1 }, { "é", "É", 'e', 'E', 0, 2 }, { "ẻ", "Ẻ", 'e', 'E', 0, 3 }, { "ẽ", "Ẽ", 'e', 'E', 0, 4 }, { "ẹ", "Ẹ", 'e', 'E', 0, 5 },
    { "ê", "Ê", 'e', 'E', 2, 0 }, { "ề", "Ề", 'e', 'E', 2, 1 }, { "ế", "Ế", 'e', 'E', 2, 2 }, { "ể", "Ể", 'e', 'E', 2, 3 }, { "ễ", "Ễ", 'e', 'E', 2, 4 }, { "ệ", "Ệ", 'e', 'E', 2, 5 },
    { "ì", "Ì", 'i', 'I', 0, 1 }, { "í", "Í", 'i', 'I', 0, 2 }, { "ỉ", "Ỉ", 'i', 'I', 0, 3 }, { "ĩ", "Ĩ", 'i', 'I', 0, 4 }, { "ị", "Ị", 'i', 'I', 0, 5 },
    { "ò", "Ò", 'o', 'O', 0, 1 }, { "ó", "Ó", 'o', 'O', 0, 2 }, { "ỏ", "Ỏ", 'o', 'O', 0, 3 }, { "õ", "Õ", 'o', 'O', 0, 4 }, { "ọ", "Ọ", 'o', 'O', 0, 5 },
    { "ô", "Ô", 'o', 'O', 2, 0 }, { "ồ", "Ồ", 'o', 'O', 2, 1 }, { "ố", "Ố", 'o', 'O', 2, 2 }, { "ổ", "Ổ", 'o', 'O', 2, 3 }, { "ỗ", "Ỗ", 'o', 'O', 2, 4 }, { "ộ", "Ộ", 'o', 'O', 2, 5 },
    { "ơ", "Ơ", 'o', 'O', 4, 0 }, { "ờ", "Ờ", 'o', 'O', 4, 1 }, { "ớ", "Ớ", 'o', 'O', 4, 2 }, { "ở", "Ở", 'o', 'O', 4, 3 }, { "ỡ", "Ỡ", 'o', 'O', 4, 4 }, { "ợ", "Ợ", 'o', 'O', 4, 5 },
    { "ù", "Ù", 'u', 'U', 0, 1 }, { "ú", "Ú", 'u', 'U', 0, 2 }, { "ủ", "Ủ", 'u', 'U', 0, 3 }, { "ũ", "Ũ", 'u', 'U', 0, 4 }, { "ụ", "Ụ", 'u', 'U', 0, 5 },
    { "ư", "Ư", 'u', 'U', 4, 0 }, { "ừ", "Ừ", 'u', 'U', 4, 1 }, { "ứ", "Ứ", 'u', 'U', 4, 2 }, { "ử", "Ử", 'u', 'U', 4, 3 }, { "ữ", "Ữ", 'u', 'U', 4, 4 }, { "ự", "Ự", 'u', 'U', 4, 5 },
    { "ỳ", "Ỳ", 'y', 'Y', 0, 1 }, { "ý", "Ý", 'y', 'Y', 0, 2 }, { "ỷ", "Ỷ", 'y', 'Y', 0, 3 }, { "ỹ", "Ỹ", 'y', 'Y', 0, 4 }, { "ỵ", "Ỵ", 'y', 'Y', 0, 5 },
};

static inline VL_COMMON_UNUSED size_t vl_utf8_char_len(unsigned char b) {
    if ((b & 0x80) == 0) return 1;
    if ((b & 0xE0) == 0xC0) return 2;
    if ((b & 0xF0) == 0xE0) return 3;
    if ((b & 0xF8) == 0xF0) return 4;
    return 1;
}

static inline VL_COMMON_UNUSED size_t vl_utf8_codepoint_count(const char *utf8_str) {
    if (!utf8_str) return 0;
    size_t count = 0;
    for (const unsigned char *p = (const unsigned char *)utf8_str; *p; p++) {
        if ((*p & 0xC0) != 0x80) {
            count++;
        }
    }
    return count;
}

static inline VL_COMMON_UNUSED const char *vl_utf8_after_first_space(const char *utf8_str) {
    if (!utf8_str) return "";
    const char *sp = strchr(utf8_str, ' ');
    return sp ? (sp + 1) : utf8_str;
}

static inline VL_COMMON_UNUSED char vl_ascii_tolower(char c) {
    return (c >= 'A' && c <= 'Z') ? (char)(c + ('a' - 'A')) : c;
}

static inline VL_COMMON_UNUSED uint8_t vl_telex_tone_for_key(char lower_key) {
    switch (lower_key) {
        case 'f': return 1; /* grave (huyền) */
        case 's': return 2; /* acute (sắc) */
        case 'r': return 3; /* hook (hỏi) */
        case 'x': return 4; /* tilde (ngã) */
        case 'j': return 5; /* dot (nặng) */
        default: return 0;
    }
}

static inline VL_COMMON_UNUSED bool vl_has_non_ascii(const char *utf8_str) {
    if (!utf8_str) return false;
    for (const unsigned char *p = (const unsigned char *)utf8_str; *p; p++) {
        if (*p >= 0x80) return true;
    }
    return false;
}

static inline VL_COMMON_UNUSED uint8_t vl_active_tone_of_utf8(const char *utf8_str) {
    if (!utf8_str) return 0;
    const char *p = utf8_str;
    const size_t map_len = sizeof(kVlVnUtf8Map) / sizeof(kVlVnUtf8Map[0]);
    while (*p) {
        size_t clen = vl_utf8_char_len((unsigned char)*p);
        if (clen > 1) {
            for (size_t i = 0; i < map_len; i++) {
                if ((strlen(kVlVnUtf8Map[i].lower_utf8) == clen && strncmp(p, kVlVnUtf8Map[i].lower_utf8, clen) == 0) ||
                    (strlen(kVlVnUtf8Map[i].upper_utf8) == clen && strncmp(p, kVlVnUtf8Map[i].upper_utf8, clen) == 0)) {
                    if (kVlVnUtf8Map[i].tone > 0) {
                        return kVlVnUtf8Map[i].tone;
                    }
                }
            }
        }
        p += clen;
    }
    return 0;
}

static inline VL_COMMON_UNUSED void vl_raw_keys_for_utf8(
    const char *utf8_str,
    bool is_vni,
    char *out,
    size_t out_cap
) {
    if (!out || out_cap == 0) return;
    if (!utf8_str) {
        out[0] = '\0';
        return;
    }
    size_t len = 0;
    char tone_char = 0;
    const char *p = utf8_str;
    const size_t map_len = sizeof(kVlVnUtf8Map) / sizeof(kVlVnUtf8Map[0]);
    while (*p && len + 4 < out_cap) {
        size_t clen = vl_utf8_char_len((unsigned char)*p);
        if (clen == 1) {
            out[len++] = *p;
            p++;
            continue;
        }
        bool matched = false;
        for (size_t i = 0; i < map_len; i++) {
            bool is_lower = (strlen(kVlVnUtf8Map[i].lower_utf8) == clen && strncmp(p, kVlVnUtf8Map[i].lower_utf8, clen) == 0);
            bool is_upper = !is_lower && (strlen(kVlVnUtf8Map[i].upper_utf8) == clen && strncmp(p, kVlVnUtf8Map[i].upper_utf8, clen) == 0);
            if (is_lower || is_upper) {
                char base = is_upper ? kVlVnUtf8Map[i].upper_base : kVlVnUtf8Map[i].lower_base;
                out[len++] = base;
                switch (kVlVnUtf8Map[i].mod) {
                    case 1:
                        out[len++] = is_vni ? '9' : (is_upper ? 'D' : 'd');
                        break;
                    case 2:
                        out[len++] = is_vni ? '6' : kVlVnUtf8Map[i].lower_base;
                        break;
                    case 3:
                        out[len++] = is_vni ? '8' : 'w';
                        break;
                    case 4:
                        if ((base == 'o' || base == 'O') && len >= 3 &&
                            (out[len - 3] == 'u' || out[len - 3] == 'U') &&
                            (out[len - 2] == 'w' || out[len - 2] == '7')) {
                            out[len - 2] = base;
                            out[len - 1] = is_vni ? '7' : 'w';
                        } else {
                            out[len++] = is_vni ? '7' : 'w';
                        }
                        break;
                    default:
                        break;
                }
                if (kVlVnUtf8Map[i].tone > 0 && kVlVnUtf8Map[i].tone <= 5) {
                    tone_char = is_vni ? "021345"[kVlVnUtf8Map[i].tone] : "0fsrxj"[kVlVnUtf8Map[i].tone];
                }
                matched = true;
                break;
            }
        }
        if (!matched) {
            for (size_t k = 0; k < clen && p[k] && len + 1 < out_cap; k++) {
                out[len++] = p[k];
            }
        }
        p += clen;
    }
    if (tone_char != 0 && len + 1 < out_cap) {
        out[len++] = tone_char;
    }
    out[len] = '\0';
}

static inline VL_COMMON_UNUSED size_t vl_encode_utf8_cp(uint32_t cp, char out[5]) {
    if (cp < 0x80) {
        out[0] = (char)cp;
        out[1] = '\0';
        return 1;
    }
    if (cp < 0x800) {
        out[0] = (char)(0xC0 | (cp >> 6));
        out[1] = (char)(0x80 | (cp & 0x3F));
        out[2] = '\0';
        return 2;
    }
    if (cp < 0x10000) {
        out[0] = (char)(0xE0 | (cp >> 12));
        out[1] = (char)(0x80 | ((cp >> 6) & 0x3F));
        out[2] = (char)(0x80 | (cp & 0x3F));
        out[3] = '\0';
        return 3;
    }
    if (cp <= 0x10FFFF) {
        out[0] = (char)(0xF0 | (cp >> 18));
        out[1] = (char)(0x80 | ((cp >> 12) & 0x3F));
        out[2] = (char)(0x80 | ((cp >> 6) & 0x3F));
        out[3] = (char)(0x80 | (cp & 0x3F));
        out[4] = '\0';
        return 4;
    }
    out[0] = '\0';
    return 0;
}

/*
 * Translates non-ASCII Vietnamese XKB (`xkb:vn`) / VM-forwarded Unicode keysyms
 * and combining diacritics (U+0300..U+0323, X11 dead keys) into canonical ASCII
 * Telex/VNI key sequences so the engine always emits precomposed Unicode NFC
 * (e.g. U+1EA9 `ẩ`, U+1EED `ử`) instead of leaking NFD combining marks (`U+0309`).
 */
static inline VL_COMMON_UNUSED bool vl_keysym_to_raw_seq(
    uint32_t keysym,
    uint32_t unicode_cp,
    bool is_vni,
    char *out_seq,
    size_t out_cap
) {
    if (!out_seq || out_cap < 5) {
        return false;
    }
    out_seq[0] = '\0';

    /* Combining diacritics & X11 dead keys used by XKB `vn` and VM key forwarding */
    if (unicode_cp == 0x0300 || keysym == 0xFE50) { /* grave / huyền */
        out_seq[0] = is_vni ? '2' : 'f';
        out_seq[1] = '\0';
        return true;
    }
    if (unicode_cp == 0x0301 || keysym == 0xFE51) { /* acute / sắc */
        out_seq[0] = is_vni ? '1' : 's';
        out_seq[1] = '\0';
        return true;
    }
    if (unicode_cp == 0x0309 || keysym == 0xFE61) { /* hook above / hỏi */
        out_seq[0] = is_vni ? '3' : 'r';
        out_seq[1] = '\0';
        return true;
    }
    if (unicode_cp == 0x0303 || keysym == 0xFE53) { /* tilde / ngã */
        out_seq[0] = is_vni ? '4' : 'x';
        out_seq[1] = '\0';
        return true;
    }
    if (unicode_cp == 0x0323 || keysym == 0xFE60) { /* dot below / nặng */
        out_seq[0] = is_vni ? '5' : 'j';
        out_seq[1] = '\0';
        return true;
    }
    if (unicode_cp == 0x031B || keysym == 0xFE62) { /* horn */
        out_seq[0] = is_vni ? '7' : 'w';
        out_seq[1] = '\0';
        return true;
    }
    if (unicode_cp == 0x0306 || keysym == 0xFE55) { /* breve */
        out_seq[0] = is_vni ? '8' : 'w';
        out_seq[1] = '\0';
        return true;
    }

    if (unicode_cp >= 0x00C0 && unicode_cp <= 0x1EFF) {
        char utf8_ch[5];
        size_t ulen = vl_encode_utf8_cp(unicode_cp, utf8_ch);
        if (ulen > 1) {
            const size_t map_len = sizeof(kVlVnUtf8Map) / sizeof(kVlVnUtf8Map[0]);
            for (size_t i = 0; i < map_len; i++) {
                if ((strlen(kVlVnUtf8Map[i].lower_utf8) == ulen &&
                     memcmp(utf8_ch, kVlVnUtf8Map[i].lower_utf8, ulen) == 0) ||
                    (strlen(kVlVnUtf8Map[i].upper_utf8) == ulen &&
                     memcmp(utf8_ch, kVlVnUtf8Map[i].upper_utf8, ulen) == 0)) {
                    vl_raw_keys_for_utf8(utf8_ch, is_vni, out_seq, out_cap);
                    return out_seq[0] != '\0';
                }
            }
        }
    }
    return false;
}

/* ==========================================================================
 * 2. Non-Destructive `config.env` Reader & Atomic Merge-Writer
 * ========================================================================== */

typedef struct {
    bool has_input_method;
    bool is_vni;
    bool sen_flex;
    bool smart_bilingual;
    bool modern_orthography;
    bool quick_telex;
    bool relaxed_coda;
    bool macro_enabled;
    bool developer_mode;
    bool preedit_underline;
} vl_env_config_t;

static inline VL_COMMON_UNUSED void vl_env_config_init_defaults(vl_env_config_t *cfg) {
    if (!cfg) return;
    cfg->has_input_method = false;
    cfg->is_vni = false;
    cfg->sen_flex = false;
    cfg->smart_bilingual = true;
    cfg->modern_orthography = true;
    cfg->quick_telex = false;
    cfg->relaxed_coda = false;
    cfg->macro_enabled = false;
    cfg->developer_mode = false;
    cfg->preedit_underline = false;
}

static inline VL_COMMON_UNUSED bool vl_resolve_config_dir(char *out_dir, size_t cap) {
    if (!out_dir || cap < 32) return false;
    const char *snap_real_home = getenv("SNAP_REAL_HOME");
    if (snap_real_home && snap_real_home[0] != '\0') {
        int n = snprintf(out_dir, cap, "%s/.config/vielotus", snap_real_home);
        return n > 0 && (size_t)n < cap;
    }
    const char *xdg = getenv("XDG_CONFIG_HOME");
    if (xdg && xdg[0] != '\0') {
        int n = snprintf(out_dir, cap, "%s/vielotus", xdg);
        return n > 0 && (size_t)n < cap;
    }
    const char *home = getenv("HOME");
    if (home && home[0] != '\0') {
        int n = snprintf(out_dir, cap, "%s/.config/vielotus", home);
        return n > 0 && (size_t)n < cap;
    }
    out_dir[0] = '\0';
    return false;
}

static inline VL_COMMON_UNUSED void vl_mkdir_p(const char *dir_path) {
    if (!dir_path || dir_path[0] == '\0') return;
    char tmp[1024];
    size_t len = strlen(dir_path);
    if (len == 0 || len >= sizeof(tmp)) return;
    memcpy(tmp, dir_path, len + 1);
    for (size_t i = 1; i < len; i++) {
        if (tmp[i] == '/') {
            tmp[i] = '\0';
            (void)mkdir(tmp, 0700);
            tmp[i] = '/';
        }
    }
    (void)mkdir(tmp, 0700);
}

static inline VL_COMMON_UNUSED void vl_trim_key_value(
    const char *line,
    char *out_key,
    size_t key_cap,
    char *out_val,
    size_t val_cap
) {
    out_key[0] = '\0';
    out_val[0] = '\0';
    if (!line) return;
    const char *p = line;
    while (*p == ' ' || *p == '\t') p++;
    if (*p == '\0' || *p == '#' || *p == '\r' || *p == '\n') return;
    const char *eq = strchr(p, '=');
    if (!eq) return;

    size_t klen = (size_t)(eq - p);
    while (klen > 0 && (p[klen - 1] == ' ' || p[klen - 1] == '\t')) klen--;
    if (klen == 0 || klen >= key_cap) return;
    memcpy(out_key, p, klen);
    out_key[klen] = '\0';

    const char *vp = eq + 1;
    while (*vp == ' ' || *vp == '\t') vp++;
    size_t vlen = strlen(vp);
    while (vlen > 0 && (vp[vlen - 1] == ' ' || vp[vlen - 1] == '\t' || vp[vlen - 1] == '\r' || vp[vlen - 1] == '\n')) {
        vlen--;
    }
    if (vlen >= 2 && ((vp[0] == '"' && vp[vlen - 1] == '"') || (vp[0] == '\'' && vp[vlen - 1] == '\''))) {
        vp++;
        vlen -= 2;
    }
    if (vlen >= val_cap) vlen = val_cap - 1;
    memcpy(out_val, vp, vlen);
    out_val[vlen] = '\0';
}

static inline VL_COMMON_UNUSED bool vl_parse_bool_str(const char *val, bool default_val) {
    if (!val || val[0] == '\0') return default_val;
    char lower[32];
    size_t i = 0;
    for (; val[i] != '\0' && i + 1 < sizeof(lower); i++) {
        lower[i] = vl_ascii_tolower(val[i]);
    }
    lower[i] = '\0';
    if (strcmp(lower, "true") == 0 || strcmp(lower, "1") == 0 || strcmp(lower, "yes") == 0 || strcmp(lower, "on") == 0) {
        return true;
    }
    if (strcmp(lower, "false") == 0 || strcmp(lower, "0") == 0 || strcmp(lower, "no") == 0 || strcmp(lower, "off") == 0) {
        return false;
    }
    return default_val;
}

static inline VL_COMMON_UNUSED bool vl_env_config_load(
    const char *path,
    vl_env_config_t *cfg,
    time_t *out_mtime
) {
    if (!path || !cfg) return false;
    struct stat st;
    if (stat(path, &st) == 0 && out_mtime) {
        *out_mtime = st.st_mtime;
    }
    FILE *fp = fopen(path, "r");
    if (!fp) return false;

    char line[512];
    char key[128];
    char val[256];
    while (fgets(line, sizeof(line), fp)) {
        vl_trim_key_value(line, key, sizeof(key), val, sizeof(val));
        if (key[0] == '\0') continue;
        if (strcmp(key, "INPUT_METHOD") == 0) {
            cfg->has_input_method = true;
            char lv[16];
            size_t j = 0;
            for (; val[j] != '\0' && j + 1 < sizeof(lv); j++) lv[j] = vl_ascii_tolower(val[j]);
            lv[j] = '\0';
            cfg->is_vni = (strstr(lv, "vni") != NULL);
        } else if (strcmp(key, "GRAMMAR_PROFILE") == 0) {
            char lv[32];
            size_t j = 0;
            for (; val[j] != '\0' && j + 1 < sizeof(lv); j++) lv[j] = vl_ascii_tolower(val[j]);
            lv[j] = '\0';
            cfg->sen_flex = (strstr(lv, "sen_flex") != NULL || strstr(lv, "senflex") != NULL);
        } else if (strcmp(key, "SMART_BILINGUAL") == 0) {
            cfg->smart_bilingual = vl_parse_bool_str(val, true);
        } else if (strcmp(key, "MODERN_ORTHOGRAPHY") == 0) {
            cfg->modern_orthography = vl_parse_bool_str(val, true);
        } else if (strcmp(key, "QUICK_TELEX") == 0) {
            cfg->quick_telex = vl_parse_bool_str(val, false);
        } else if (strcmp(key, "RELAXED_CODA") == 0) {
            cfg->relaxed_coda = vl_parse_bool_str(val, false);
        } else if (strcmp(key, "MACRO_ENABLED") == 0) {
            cfg->macro_enabled = vl_parse_bool_str(val, false);
        } else if (strcmp(key, "DEVELOPER_MODE") == 0) {
            cfg->developer_mode = vl_parse_bool_str(val, false);
        } else if (strcmp(key, "PREEDIT_UNDERLINE") == 0) {
            cfg->preedit_underline = vl_parse_bool_str(val, false);
        }
    }
    fclose(fp);
    return true;
}

/* Non-destructive merge-writer: updates the 9 known keys in place, preserves all
 * comments, blank lines, and unknown/custom user keys, and writes atomically. */
static inline VL_COMMON_UNUSED bool vl_env_config_save_merged(
    const char *path,
    const vl_env_config_t *cfg,
    time_t *out_mtime
) {
    if (!path || !cfg || path[0] == '\0') return false;

    const char *slash = strrchr(path, '/');
    if (slash && slash > path) {
        size_t dlen = (size_t)(slash - path);
        if (dlen < 1024) {
            char parent_dir[1024];
            memcpy(parent_dir, path, dlen);
            parent_dir[dlen] = '\0';
            vl_mkdir_p(parent_dir);
        }
    }

    static const char *const kKnownKeys[9] = {
        "INPUT_METHOD",
        "GRAMMAR_PROFILE",
        "SMART_BILINGUAL",
        "MODERN_ORTHOGRAPHY",
        "QUICK_TELEX",
        "RELAXED_CODA",
        "MACRO_ENABLED",
        "DEVELOPER_MODE",
        "PREEDIT_UNDERLINE"
    };
    const char *knownVals[9] = {
        cfg->is_vni ? "vni" : "telex",
        cfg->sen_flex ? "sen_flex" : "classic",
        cfg->smart_bilingual ? "true" : "false",
        cfg->modern_orthography ? "true" : "false",
        cfg->quick_telex ? "true" : "false",
        cfg->relaxed_coda ? "true" : "false",
        cfg->macro_enabled ? "true" : "false",
        cfg->developer_mode ? "true" : "false",
        cfg->preedit_underline ? "true" : "false"
    };
    bool seen[9] = { false, false, false, false, false, false, false, false, false };

    char tmp_path[1100];
    int tn = snprintf(tmp_path, sizeof(tmp_path), "%s.tmp.%ld", path, (long)getpid());
    if (tn <= 0 || (size_t)tn >= sizeof(tmp_path)) return false;

    FILE *out_fp = fopen(tmp_path, "w");
    if (!out_fp) return false;
    (void)chmod(tmp_path, 0600);

    FILE *in_fp = fopen(path, "r");
    if (in_fp) {
        char line[512];
        char key[128];
        char val[256];
        while (fgets(line, sizeof(line), in_fp)) {
            vl_trim_key_value(line, key, sizeof(key), val, sizeof(val));
            int matched_idx = -1;
            if (key[0] != '\0') {
                for (int i = 0; i < 9; i++) {
                    if (strcmp(key, kKnownKeys[i]) == 0) {
                        matched_idx = i;
                        break;
                    }
                }
            }
            if (matched_idx >= 0) {
                if (!seen[matched_idx]) {
                    fprintf(out_fp, "%s=\"%s\"\n", kKnownKeys[matched_idx], knownVals[matched_idx]);
                    seen[matched_idx] = true;
                }
            } else {
                size_t l = strlen(line);
                if (l > 0 && line[l - 1] != '\n') {
                    fprintf(out_fp, "%s\n", line);
                } else {
                    fputs(line, out_fp);
                }
            }
        }
        fclose(in_fp);
    }

    for (int i = 0; i < 9; i++) {
        if (!seen[i]) {
            fprintf(out_fp, "%s=\"%s\"\n", kKnownKeys[i], knownVals[i]);
        }
    }

    if (fflush(out_fp) != 0) {
        fclose(out_fp);
        (void)remove(tmp_path);
        return false;
    }
    fclose(out_fp);

    if (rename(tmp_path, path) != 0) {
        (void)remove(tmp_path);
        return false;
    }
    struct stat st;
    if (stat(path, &st) == 0 && out_mtime) {
        *out_mtime = st.st_mtime;
    }
    return true;
}

/* ==========================================================================
 * 3. Clean-Room `PresentationRules` (`typing-modes.yml`) Parser & Matcher
 *    Ported from `Sources/VieLotusCore/PresentationRules.swift`
 * ========================================================================== */

#define VL_MAX_PRESENTATION_RULES 128
#define VL_MAX_RULE_KEY_LEN 96

typedef enum {
    VL_PRESENTATION_AUTOMATIC = 0,
    VL_PRESENTATION_DIRECT_REPLACEMENT = 1,
    VL_PRESENTATION_MARKED_TEXT = 2,
    VL_PRESENTATION_PASSTHROUGH = 3
} vl_presentation_mode_t;

typedef struct {
    char key[VL_MAX_RULE_KEY_LEN];
    vl_presentation_mode_t mode;
} vl_presentation_rule_t;

typedef struct {
    vl_presentation_rule_t items[VL_MAX_PRESENTATION_RULES];
    size_t count;
    time_t loaded_mtime;
    char loaded_path[512];
} vl_presentation_rules_t;

static inline VL_COMMON_UNUSED void vl_presentation_rules_init(vl_presentation_rules_t *rules) {
    if (!rules) return;
    rules->count = 0;
    rules->loaded_mtime = 0;
    rules->loaded_path[0] = '\0';
}

/* Case-insensitive ordered `*` glob match, identical to PresentationRule.matches in PresentationRules.swift */
static inline VL_COMMON_UNUSED bool vl_presentation_rule_matches(const char *rule_key, const char *app_id_lower) {
    if (!rule_key || !app_id_lower || rule_key[0] == '\0' || app_id_lower[0] == '\0') {
        return false;
    }
    if (strchr(rule_key, '*') == NULL) {
        return strcmp(rule_key, app_id_lower) == 0;
    }

    const size_t key_len = strlen(rule_key);
    const size_t id_len = strlen(app_id_lower);
    const bool anchored_start = (rule_key[0] != '*');
    const bool anchored_end = (rule_key[key_len - 1] != '*');

    /* Split rule_key on '*' into segments */
    char key_buf[VL_MAX_RULE_KEY_LEN];
    if (key_len >= sizeof(key_buf)) return false;
    memcpy(key_buf, rule_key, key_len + 1);

    const char *segments[16];
    size_t seg_lens[16];
    size_t seg_count = 0;
    char *cur = key_buf;
    while (seg_count < 16) {
        char *star = strchr(cur, '*');
        if (!star) {
            segments[seg_count] = cur;
            seg_lens[seg_count] = strlen(cur);
            seg_count++;
            break;
        }
        *star = '\0';
        segments[seg_count] = cur;
        seg_lens[seg_count] = (size_t)(star - cur);
        seg_count++;
        cur = star + 1;
    }

    size_t search_pos = 0;
    for (size_t idx = 0; idx < seg_count; idx++) {
        const char *seg = segments[idx];
        const size_t slen = seg_lens[idx];
        if (slen == 0) continue;

        if (idx == seg_count - 1 && anchored_end) {
            if (id_len < slen) return false;
            const size_t suffix_pos = id_len - slen;
            if (suffix_pos < search_pos) return false;
            return memcmp(app_id_lower + suffix_pos, seg, slen) == 0;
        }

        const char *found = strstr(app_id_lower + search_pos, seg);
        if (!found) return false;
        const size_t found_pos = (size_t)(found - app_id_lower);
        if (idx == 0 && anchored_start && found_pos != 0) {
            return false;
        }
        search_pos = found_pos + slen;
    }
    return true;
}

static inline VL_COMMON_UNUSED bool vl_parse_presentation_mode(
    const char *raw_val,
    vl_presentation_mode_t *out_mode
) {
    if (!raw_val || !out_mode) return false;
    if (strcmp(raw_val, "automatic") == 0) {
        *out_mode = VL_PRESENTATION_AUTOMATIC;
        return true;
    }
    if (strcmp(raw_val, "directReplacement") == 0) {
        *out_mode = VL_PRESENTATION_DIRECT_REPLACEMENT;
        return true;
    }
    if (strcmp(raw_val, "markedText") == 0) {
        *out_mode = VL_PRESENTATION_MARKED_TEXT;
        return true;
    }
    if (strcmp(raw_val, "passthrough") == 0) {
        *out_mode = VL_PRESENTATION_PASSTHROUGH;
        return true;
    }
    return false;
}

static inline VL_COMMON_UNUSED void vl_presentation_rules_parse_text(
    vl_presentation_rules_t *rules,
    const char *yaml_text
) {
    if (!rules) return;
    rules->count = 0;
    if (!yaml_text) return;

    const char *p = yaml_text;
    while (*p && rules->count < VL_MAX_PRESENTATION_RULES) {
        const char *eol = strchr(p, '\n');
        size_t line_len = eol ? (size_t)(eol - p) : strlen(p);
        char line[256];
        if (line_len >= sizeof(line)) line_len = sizeof(line) - 1;
        memcpy(line, p, line_len);
        line[line_len] = '\0';
        p = eol ? (eol + 1) : (p + strlen(p));

        char *s = line;
        while (*s == ' ' || *s == '\t' || *s == '\r') s++;
        if (*s == '\0' || *s == '#' || (s[0] == '/' && s[1] == '/')) continue;

        char *colon = strchr(s, ':');
        if (!colon) continue;
        *colon = '\0';

        /* Normalize key (trim whitespace & optional quotes, lowercase) */
        char *ks = s;
        size_t klen = strlen(ks);
        while (klen > 0 && (ks[klen - 1] == ' ' || ks[klen - 1] == '\t')) ks[--klen] = '\0';
        if (klen >= 2 && ((ks[0] == '"' && ks[klen - 1] == '"') || (ks[0] == '\'' && ks[klen - 1] == '\''))) {
            ks++;
            klen -= 2;
            ks[klen] = '\0';
        }
        if (klen == 0 || klen >= VL_MAX_RULE_KEY_LEN) continue;

        /* Normalize value (strip trailing '#' comment, trim whitespace & optional quotes) */
        char *vs = colon + 1;
        while (*vs == ' ' || *vs == '\t') vs++;
        char *hash = strchr(vs, '#');
        if (hash) *hash = '\0';
        size_t vlen = strlen(vs);
        while (vlen > 0 && (vs[vlen - 1] == ' ' || vs[vlen - 1] == '\t' || vs[vlen - 1] == '\r')) vs[--vlen] = '\0';
        if (vlen >= 2 && ((vs[0] == '"' && vs[vlen - 1] == '"') || (vs[0] == '\'' && vs[vlen - 1] == '\''))) {
            vs++;
            vlen -= 2;
            vs[vlen] = '\0';
        }

        vl_presentation_mode_t mode = VL_PRESENTATION_AUTOMATIC;
        if (!vl_parse_presentation_mode(vs, &mode)) continue;

        vl_presentation_rule_t *dst = &rules->items[rules->count++];
        for (size_t i = 0; i < klen; i++) {
            dst->key[i] = vl_ascii_tolower(ks[i]);
        }
        dst->key[klen] = '\0';
        dst->mode = mode;
    }
}

static inline VL_COMMON_UNUSED bool vl_presentation_rules_load_file(
    vl_presentation_rules_t *rules,
    const char *path
) {
    if (!rules || !path || path[0] == '\0') return false;
    struct stat st;
    if (stat(path, &st) != 0 || st.st_size < 0 || st.st_size > 131072) return false;
    FILE *fp = fopen(path, "rb");
    if (!fp) return false;
    size_t sz = (size_t)st.st_size;
    char *buf = (char *)malloc(sz + 1);
    if (!buf) {
        fclose(fp);
        return false;
    }
    size_t nread = fread(buf, 1, sz, fp);
    fclose(fp);
    buf[nread] = '\0';
    vl_presentation_rules_parse_text(rules, buf);
    free(buf);
    rules->loaded_mtime = st.st_mtime;
    snprintf(rules->loaded_path, sizeof(rules->loaded_path), "%s", path);
    return true;
}

static inline VL_COMMON_UNUSED void vl_presentation_rules_reload_if_changed(
    vl_presentation_rules_t *rules,
    const char *user_path,
    const char *sys_path
) {
    if (!rules) return;
    const char *chosen = NULL;
    struct stat st;
    if (user_path && user_path[0] != '\0' && stat(user_path, &st) == 0) {
        chosen = user_path;
    } else if (sys_path && sys_path[0] != '\0' && stat(sys_path, &st) == 0) {
        chosen = sys_path;
    }
    if (!chosen) {
        if (rules->loaded_path[0] != '\0') {
            vl_presentation_rules_init(rules);
        }
        return;
    }
    if (strcmp(rules->loaded_path, chosen) == 0 && rules->loaded_mtime == st.st_mtime) {
        return;
    }
    (void)vl_presentation_rules_load_file(rules, chosen);
}

static inline VL_COMMON_UNUSED vl_presentation_mode_t vl_presentation_rules_resolve(
    const vl_presentation_rules_t *rules,
    const char *app_id
) {
    if (!rules || rules->count == 0 || !app_id || app_id[0] == '\0') {
        return VL_PRESENTATION_AUTOMATIC;
    }
    char lower_id[256];
    size_t i = 0;
    for (; app_id[i] != '\0' && i + 1 < sizeof(lower_id); i++) {
        lower_id[i] = vl_ascii_tolower(app_id[i]);
    }
    lower_id[i] = '\0';
    for (size_t r = 0; r < rules->count; r++) {
        if (vl_presentation_rule_matches(rules->items[r].key, lower_id)) {
            return rules->items[r].mode;
        }
    }
    return VL_PRESENTATION_AUTOMATIC;
}

/* ==========================================================================
 * 4. `mtime`-Gated `macros.json` Hot-Reloader via `vielotus.h` C-ABI
 * ========================================================================== */

static inline VL_COMMON_UNUSED void vl_macros_reload_if_changed(
    const char *macros_json_path,
    time_t *last_mtime,
    bool *had_file
) {
    if (!last_mtime || !had_file) return;
    struct stat st;
    if (macros_json_path && macros_json_path[0] != '\0' &&
        stat(macros_json_path, &st) == 0 && st.st_size >= 2 && st.st_size <= 262144) {
        if (!(*had_file) || st.st_mtime != *last_mtime) {
            FILE *fp = fopen(macros_json_path, "rb");
            if (fp) {
                size_t sz = (size_t)st.st_size;
                char *buf = (char *)malloc(sz + 1);
                if (buf) {
                    size_t nread = fread(buf, 1, sz, fp);
                    buf[nread] = '\0';
                    if (vielotus_load_macros_json(buf)) {
                        *last_mtime = st.st_mtime;
                        *had_file = true;
                    }
                    free(buf);
                }
                fclose(fp);
            }
        }
        return;
    }
    if (*had_file) {
        vielotus_reset_default_macros();
        *had_file = false;
        *last_mtime = 0;
    }
}

/* ==========================================================================
 * 5. Developer Mode Backtick Inline (`...`) & Fenced (```...```) Code FSM
 * ========================================================================== */

typedef struct {
    uint8_t consecutive_backticks;
    bool in_inline_code;
    bool in_fenced_code;
} vl_dev_code_state_t;

static inline VL_COMMON_UNUSED void vl_dev_code_reset(vl_dev_code_state_t *st) {
    if (!st) return;
    st->consecutive_backticks = 0;
    st->in_inline_code = false;
    st->in_fenced_code = false;
}

static inline VL_COMMON_UNUSED void vl_dev_code_on_backtick(vl_dev_code_state_t *st) {
    if (!st) return;
    st->consecutive_backticks++;
    if (st->consecutive_backticks >= 3) {
        st->in_fenced_code = !st->in_fenced_code;
        st->in_inline_code = false;
        st->consecutive_backticks = 0;
    } else if (!st->in_fenced_code) {
        st->in_inline_code = !st->in_inline_code;
    }
}

static inline VL_COMMON_UNUSED void vl_dev_code_on_non_backtick(vl_dev_code_state_t *st) {
    if (!st) return;
    st->consecutive_backticks = 0;
}

static inline VL_COMMON_UNUSED void vl_dev_code_on_newline(vl_dev_code_state_t *st) {
    if (!st) return;
    st->consecutive_backticks = 0;
    st->in_inline_code = false;
}

static inline VL_COMMON_UNUSED bool vl_dev_code_is_bypassing(const vl_dev_code_state_t *st) {
    if (!st) return false;
    return st->in_inline_code || st->in_fenced_code;
}

#ifdef __cplusplus
}
#endif

#endif /* VIELOTUS_LINUX_COMMON_H */
