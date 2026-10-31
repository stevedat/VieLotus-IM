/*
 * VieLotusIM (Sen Việt) - Native IBus Engine
 * Pure Swift 6 Core Bridge via C-ABI (vielotus.h)
 */

#include <ibus.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <time.h>
#include "vielotus.h"

#define IBUS_TYPE_VIELOTUS_ENGINE (ibus_vielotus_engine_get_type())
#ifndef IBUS_ATTR_UNDERLINE_NONE
#define IBUS_ATTR_UNDERLINE_NONE 0
#endif

typedef struct _IBusVieLotusEngine IBusVieLotusEngine;
typedef struct _IBusVieLotusEngineClass IBusVieLotusEngineClass;

struct _IBusVieLotusEngine {
    IBusEngine parent;
    vielotus_session_t session;
    gboolean is_vni;
    gboolean smart_bilingual;
    gboolean sen_flex;
    gboolean modern_orthography;
    gboolean quick_telex;
    gboolean relaxed_coda;
    gboolean macro_enabled;
    gboolean developer_mode;
    gboolean preedit_underline;
    gboolean is_password_field;
    time_t config_mtime;
    IBusPropList *prop_list;
};

struct _IBusVieLotusEngineClass {
    IBusEngineClass parent_class;
};

GType ibus_vielotus_engine_get_type(void);
G_DEFINE_TYPE(IBusVieLotusEngine, ibus_vielotus_engine, IBUS_TYPE_ENGINE)

static gchar *ibus_vielotus_get_config_dir(void) {
    const char *snap_real_home = getenv("SNAP_REAL_HOME");
    if (snap_real_home && snap_real_home[0] != '\0') {
        return g_build_filename(snap_real_home, ".config", "vielotus", NULL);
    }
    const gchar *cfg_root = g_get_user_config_dir();
    if (!cfg_root) {
        return NULL;
    }
    return g_build_filename(cfg_root, "vielotus", NULL);
}

static void ibus_vielotus_load_user_config(IBusVieLotusEngine *vl_engine) {
    if (!vl_engine->session) {
        return;
    }
    gchar *dir_path = ibus_vielotus_get_config_dir();
    if (!dir_path) {
        return;
    }
    gchar *path = g_build_filename(dir_path, "config.env", NULL);
    g_free(dir_path);
    struct stat st;
    if (stat(path, &st) == 0) {
        vl_engine->config_mtime = st.st_mtime;
    }
    FILE *fp = fopen(path, "r");
    g_free(path);
    if (!fp) {
        return;
    }
    char line[256];
    gboolean has_input_method_override = FALSE;
    gboolean config_is_vni = FALSE;
    while (fgets(line, sizeof(line), fp)) {
        if (strncmp(line, "INPUT_METHOD=", 13) == 0) {
            has_input_method_override = TRUE;
            config_is_vni = (strstr(line, "vni") != NULL || strstr(line, "VNI") != NULL);
        } else if (strncmp(line, "GRAMMAR_PROFILE=", 16) == 0) {
            vl_engine->sen_flex = (strstr(line, "classic") == NULL);
        } else if (strncmp(line, "SMART_BILINGUAL=", 16) == 0) {
            vl_engine->smart_bilingual = (strstr(line, "false") == NULL && strstr(line, "0") == NULL);
        } else if (strncmp(line, "MODERN_ORTHOGRAPHY=", 19) == 0) {
            vl_engine->modern_orthography = (strstr(line, "false") == NULL && strstr(line, "0") == NULL);
        } else if (strncmp(line, "QUICK_TELEX=", 12) == 0) {
            vl_engine->quick_telex = (strstr(line, "true") != NULL || strstr(line, "1") != NULL);
        } else if (strncmp(line, "RELAXED_CODA=", 13) == 0) {
            vl_engine->relaxed_coda = (strstr(line, "true") != NULL || strstr(line, "1") != NULL);
        } else if (strncmp(line, "MACRO_ENABLED=", 14) == 0) {
            vl_engine->macro_enabled = (strstr(line, "false") == NULL && strstr(line, "0") == NULL);
        } else if (strncmp(line, "DEVELOPER_MODE=", 15) == 0) {
            vl_engine->developer_mode = (strstr(line, "true") != NULL || strstr(line, "1") != NULL);
        } else if (strncmp(line, "PREEDIT_UNDERLINE=", 18) == 0) {
            vl_engine->preedit_underline = (strstr(line, "true") != NULL || strstr(line, "1") != NULL);
        }
    }
    fclose(fp);

    const gchar *engine_name = ibus_engine_get_name((IBusEngine *)vl_engine);
    if (engine_name && strstr(engine_name, "vni") != NULL) {
        vl_engine->is_vni = TRUE;
    } else if (has_input_method_override) {
        vl_engine->is_vni = config_is_vni;
    }
    vielotus_set_input_method(
        vl_engine->session,
        vl_engine->is_vni ? VIELOTUS_INPUT_VNI : VIELOTUS_INPUT_TELEX
    );
    vielotus_set_grammar_profile(
        vl_engine->session,
        vl_engine->sen_flex ? VIELOTUS_GRAMMAR_SEN_FLEX : VIELOTUS_GRAMMAR_CLASSIC
    );
    vielotus_set_smart_bilingual(vl_engine->session, vl_engine->smart_bilingual);
    vielotus_set_modern_orthography(vl_engine->session, vl_engine->modern_orthography);
    vielotus_set_quick_telex(vl_engine->session, vl_engine->quick_telex);
}

static void ibus_vielotus_save_user_config(IBusVieLotusEngine *vl_engine) {
    gchar *dir_path = ibus_vielotus_get_config_dir();
    if (!dir_path) {
        return;
    }
    g_mkdir_with_parents(dir_path, 0755);
    gchar *path = g_build_filename(dir_path, "config.env", NULL);
    g_free(dir_path);

    FILE *fp = fopen(path, "w");
    if (!fp) {
        g_free(path);
        return;
    }
    fprintf(fp, "INPUT_METHOD=\"%s\"\n", vl_engine->is_vni ? "vni" : "telex");
    fprintf(fp, "GRAMMAR_PROFILE=\"%s\"\n", vl_engine->sen_flex ? "sen_flex" : "classic");
    fprintf(fp, "SMART_BILINGUAL=\"%s\"\n", vl_engine->smart_bilingual ? "true" : "false");
    fprintf(fp, "MODERN_ORTHOGRAPHY=\"%s\"\n", vl_engine->modern_orthography ? "true" : "false");
    fprintf(fp, "QUICK_TELEX=\"%s\"\n", vl_engine->quick_telex ? "true" : "false");
    fprintf(fp, "RELAXED_CODA=\"%s\"\n", vl_engine->relaxed_coda ? "true" : "false");
    fprintf(fp, "MACRO_ENABLED=\"%s\"\n", vl_engine->macro_enabled ? "true" : "false");
    fprintf(fp, "DEVELOPER_MODE=\"%s\"\n", vl_engine->developer_mode ? "true" : "false");
    fprintf(fp, "PREEDIT_UNDERLINE=\"%s\"\n", vl_engine->preedit_underline ? "true" : "false");
    fclose(fp);
    struct stat st;
    if (stat(path, &st) == 0) {
        vl_engine->config_mtime = st.st_mtime;
    }
    g_free(path);
}

static void ibus_vielotus_build_prop_list(IBusVieLotusEngine *vl_engine) {
    if (vl_engine->prop_list) {
        g_object_unref(vl_engine->prop_list);
    }
    vl_engine->prop_list = ibus_prop_list_new();
    g_object_ref_sink(vl_engine->prop_list);

    IBusProperty *prop;
    IBusText *label;

    label = ibus_text_new_from_static_string("Song ngữ thông minh Anh-Việt (Smart Bilingual)");
    prop = ibus_property_new("smart-bilingual", PROP_TYPE_TOGGLE, label, NULL, NULL,
                             TRUE, TRUE,
                             vl_engine->smart_bilingual ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED,
                             NULL);
    ibus_prop_list_append(vl_engine->prop_list, prop);

    label = ibus_text_new_from_static_string("Gõ dấu tự do (SEN Flex)");
    prop = ibus_property_new("sen-flex", PROP_TYPE_TOGGLE, label, NULL, NULL,
                             TRUE, TRUE,
                             vl_engine->sen_flex ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED,
                             NULL);
    ibus_prop_list_append(vl_engine->prop_list, prop);

    label = ibus_text_new_from_static_string("Chính tả hiện đại (oà, uý)");
    prop = ibus_property_new("modern-orthography", PROP_TYPE_TOGGLE, label, NULL, NULL,
                             TRUE, TRUE,
                             vl_engine->modern_orthography ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED,
                             NULL);
    ibus_prop_list_append(vl_engine->prop_list, prop);

    label = ibus_text_new_from_static_string("Gõ tắt phụ âm (Quick Telex: cc=ch, gg=gi...)");
    prop = ibus_property_new("quick-telex", PROP_TYPE_TOGGLE, label, NULL, NULL,
                             TRUE, TRUE,
                             vl_engine->quick_telex ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED,
                             NULL);
    ibus_prop_list_append(vl_engine->prop_list, prop);

    label = ibus_text_new_from_static_string("Gạch chân chữ đang gõ (Preedit Underline)");
    prop = ibus_property_new("preedit-underline", PROP_TYPE_TOGGLE, label, NULL, NULL,
                             TRUE, TRUE,
                             vl_engine->preedit_underline ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED,
                             NULL);
    ibus_prop_list_append(vl_engine->prop_list, prop);

    label = ibus_text_new_from_static_string("Bảng cài đặt Sen Việt (Settings)...");
    prop = ibus_property_new("more-settings", PROP_TYPE_NORMAL, label, "preferences-system", NULL,
                             TRUE, TRUE, PROP_STATE_UNCHECKED, NULL);
    ibus_prop_list_append(vl_engine->prop_list, prop);
}

static void ibus_vielotus_clear_preedit(IBusEngine *engine) {
    IBusText *empty = ibus_text_new_from_static_string("");
    ibus_engine_update_preedit_text_with_mode(
        engine,
        empty,
        0,
        FALSE,
        IBUS_ENGINE_PREEDIT_CLEAR
    );
    ibus_engine_hide_preedit_text(engine);
}

static void ibus_vielotus_engine_reset_internal(IBusVieLotusEngine *vl_engine) {
    if (vl_engine->session) {
        vielotus_reset_session(vl_engine->session);
    }
    ibus_vielotus_clear_preedit((IBusEngine *)vl_engine);
}

static void ibus_vielotus_commit_composing(IBusVieLotusEngine *vl_engine, const char *trailing_ascii) {
    IBusEngine *engine = (IBusEngine *)vl_engine;
    char buf[1024];
    buf[0] = '\0';

    if (vl_engine->session && vielotus_is_composing(vl_engine->session)) {
        if (trailing_ascii && trailing_ascii[0] != '\0' && trailing_ascii[1] == '\0') {
            uint32_t cp = (uint32_t)(unsigned char)trailing_ascii[0];
            vielotus_feed_char(vl_engine->session, cp);
        } else {
            vielotus_commit_word(vl_engine->session);
        }
        const char *committed = vielotus_get_last_text(vl_engine->session);
        if (committed && committed[0] != '\0') {
            snprintf(buf, sizeof(buf), "%s", committed);
        }
    }

    if (trailing_ascii && trailing_ascii[0] != '\0') {
        size_t len = strlen(buf);
        if (len < sizeof(buf) - 1) {
            snprintf(buf + len, sizeof(buf) - len, "%s", trailing_ascii);
        }
    }

    if (buf[0] != '\0') {
        IBusText *commit_text = ibus_text_new_from_string(buf);
        ibus_engine_commit_text(engine, commit_text);
    }

    ibus_vielotus_engine_reset_internal(vl_engine);
}

static void ibus_vielotus_update_preedit(IBusVieLotusEngine *vl_engine) {
    IBusEngine *engine = (IBusEngine *)vl_engine;
    if (vl_engine->session && vielotus_is_composing(vl_engine->session)) {
        const char *composing = vielotus_get_composing_text(vl_engine->session);
        if (composing && composing[0] != '\0') {
            IBusText *text = ibus_text_new_from_string(composing);
            guint char_len = ibus_text_get_length(text);
            guint ul_mode = vl_engine->preedit_underline ? IBUS_ATTR_UNDERLINE_SINGLE : IBUS_ATTR_UNDERLINE_NONE;
            ibus_text_append_attribute(text, IBUS_ATTR_TYPE_UNDERLINE, ul_mode, 0, (gint)char_len);
            ibus_engine_update_preedit_text_with_mode(
                engine,
                text,
                char_len,
                TRUE,
                IBUS_ENGINE_PREEDIT_COMMIT
            );
            return;
        }
    }
    ibus_vielotus_clear_preedit(engine);
}

typedef struct {
    const char *lower_utf8;
    const char *upper_utf8;
    char lower_base;
    char upper_base;
    uint8_t mod;  /* 0=none, 1=d-stroke, 2=circumflex(^), 3=breve(ă), 4=horn(ư/ơ) */
    uint8_t tone; /* 0=none, 1=grave(f/2), 2=acute(s/1), 3=hook(r/3), 4=tilde(x/4), 5=dot(j/5) */
} VieLotusUtf8CharMap;

static const VieLotusUtf8CharMap kVnUtf8Map[] = {
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

static size_t ibus_vielotus_utf8_char_len(unsigned char b) {
    if ((b & 0x80) == 0) return 1;
    if ((b & 0xE0) == 0xC0) return 2;
    if ((b & 0xF0) == 0xE0) return 3;
    if ((b & 0xF8) == 0xF0) return 4;
    return 1;
}

static void ibus_vielotus_raw_keys_for_utf8(const char *utf8_str, gboolean is_vni, char *out, size_t out_cap) {
    size_t len = 0;
    char tone_char = 0;
    const char *p = utf8_str;
    while (*p && len + 4 < out_cap) {
        size_t clen = ibus_vielotus_utf8_char_len((unsigned char)*p);
        if (clen == 1) {
            out[len++] = *p;
            p++;
            continue;
        }
        gboolean matched = FALSE;
        for (size_t i = 0; i < sizeof(kVnUtf8Map) / sizeof(kVnUtf8Map[0]); i++) {
            gboolean is_lower = (strlen(kVnUtf8Map[i].lower_utf8) == clen && strncmp(p, kVnUtf8Map[i].lower_utf8, clen) == 0);
            gboolean is_upper = !is_lower && (strlen(kVnUtf8Map[i].upper_utf8) == clen && strncmp(p, kVnUtf8Map[i].upper_utf8, clen) == 0);
            if (is_lower || is_upper) {
                char base = is_upper ? kVnUtf8Map[i].upper_base : kVnUtf8Map[i].lower_base;
                out[len++] = base;
                switch (kVnUtf8Map[i].mod) {
                    case 1: /* đ / Đ */
                        out[len++] = is_vni ? '9' : (is_upper ? 'D' : 'd');
                        break;
                    case 2: /* circumflex (â, ê, ô) */
                        out[len++] = is_vni ? '6' : kVnUtf8Map[i].lower_base;
                        break;
                    case 3: /* breve (ă) */
                        out[len++] = is_vni ? '8' : 'w';
                        break;
                    case 4: /* horn (ư, ơ) */
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
                if (kVnUtf8Map[i].tone > 0 && kVnUtf8Map[i].tone <= 5) {
                    tone_char = is_vni ? "021345"[kVnUtf8Map[i].tone] : "0fsrxj"[kVnUtf8Map[i].tone];
                }
                matched = TRUE;
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

static inline char vl_tolower(char c) {
    return (c >= 'A' && c <= 'Z') ? (char)(c + ('a' - 'A')) : c;
}

static uint8_t ibus_vielotus_telex_tone_for_key(char lower_key) {
    switch (lower_key) {
        case 'f': return 1; /* grave (huyền) */
        case 's': return 2; /* acute (sắc) */
        case 'r': return 3; /* hook (hỏi) */
        case 'x': return 4; /* tilde (ngã) */
        case 'j': return 5; /* dot (nặng) */
        default: return 0;
    }
}

static gboolean ibus_vielotus_has_non_ascii(const char *utf8_str) {
    if (!utf8_str) return FALSE;
    for (const unsigned char *p = (const unsigned char *)utf8_str; *p; p++) {
        if (*p >= 0x80) return TRUE;
    }
    return FALSE;
}

static uint8_t ibus_vielotus_active_tone_of_utf8(const char *utf8_str) {
    if (!utf8_str) return 0;
    const char *p = utf8_str;
    while (*p) {
        size_t clen = ibus_vielotus_utf8_char_len((unsigned char)*p);
        if (clen > 1) {
            for (size_t i = 0; i < sizeof(kVnUtf8Map) / sizeof(kVnUtf8Map[0]); i++) {
                if ((strlen(kVnUtf8Map[i].lower_utf8) == clen && strncmp(p, kVnUtf8Map[i].lower_utf8, clen) == 0) ||
                    (strlen(kVnUtf8Map[i].upper_utf8) == clen && strncmp(p, kVnUtf8Map[i].upper_utf8, clen) == 0)) {
                    if (kVnUtf8Map[i].tone > 0) {
                        return kVnUtf8Map[i].tone;
                    }
                }
            }
        }
        p += clen;
    }
    return 0;
}

static void ibus_vielotus_replay_raw_keys(IBusVieLotusEngine *vl_engine, const char *raw_keys) {
    vielotus_reset_session(vl_engine->session);
    for (size_t i = 0; raw_keys[i] != '\0'; i++) {
        vielotus_feed_char(vl_engine->session, (uint32_t)(unsigned char)raw_keys[i]);
    }
}

/* Whole-character Backspace while composing: deletes the last displayed UTF-8 character
 * ("việt" -> "việ" -> "vi" -> "v" -> "", "được" -> "đượ" -> "đư" -> "đ" -> "")
 * so Backspace never reverts a Vietnamese syllable to raw ASCII ("viêt"/"viet"). */
static void ibus_vielotus_backspace_composing(IBusVieLotusEngine *vl_engine) {
    const char *composing = vielotus_get_composing_text(vl_engine->session);
    if (!composing || composing[0] == '\0') {
        ibus_vielotus_engine_reset_internal(vl_engine);
        return;
    }
    size_t len = strlen(composing);
    if (len >= 512) {
        ibus_vielotus_engine_reset_internal(vl_engine);
        return;
    }
    char prefix[512];
    memcpy(prefix, composing, len + 1);
    size_t cut = len;
    while (cut > 0 && ((unsigned char)prefix[cut - 1] & 0xC0) == 0x80) {
        cut--;
    }
    if (cut > 0) {
        cut--;
    }
    prefix[cut] = '\0';
    if (cut == 0) {
        ibus_vielotus_engine_reset_internal(vl_engine);
        return;
    }
    char raw_keys[1024];
    ibus_vielotus_raw_keys_for_utf8(prefix, vl_engine->is_vni, raw_keys, sizeof(raw_keys));
    vielotus_reset_session(vl_engine->session);
    for (size_t i = 0; raw_keys[i] != '\0'; i++) {
        vielotus_feed_char(vl_engine->session, (uint32_t)(unsigned char)raw_keys[i]);
    }
    if (!vielotus_is_composing(vl_engine->session)) {
        ibus_vielotus_engine_reset_internal(vl_engine);
    } else {
        ibus_vielotus_update_preedit(vl_engine);
    }
}

static void ibus_vielotus_engine_init(IBusVieLotusEngine *vl_engine) {
    vl_engine->session = vielotus_create_session();
    vl_engine->is_vni = FALSE;
    vl_engine->smart_bilingual = TRUE;
    vl_engine->sen_flex = TRUE;
    vl_engine->modern_orthography = TRUE;
    vl_engine->quick_telex = FALSE;
    vl_engine->relaxed_coda = FALSE;
    vl_engine->macro_enabled = TRUE;
    vl_engine->developer_mode = FALSE;
    vl_engine->preedit_underline = FALSE;
    vl_engine->is_password_field = FALSE;
    vl_engine->prop_list = NULL;

    vielotus_set_input_method(vl_engine->session, VIELOTUS_INPUT_TELEX);
    ibus_vielotus_load_user_config(vl_engine);
    ibus_vielotus_build_prop_list(vl_engine);
}

static void ibus_vielotus_engine_finalize(GObject *object) {
    IBusVieLotusEngine *vl_engine = (IBusVieLotusEngine *)object;
    if (vl_engine->prop_list) {
        g_object_unref(vl_engine->prop_list);
        vl_engine->prop_list = NULL;
    }
    if (vl_engine->session) {
        vielotus_destroy_session(vl_engine->session);
        vl_engine->session = NULL;
    }
    G_OBJECT_CLASS(ibus_vielotus_engine_parent_class)->finalize(object);
}

static void ibus_vielotus_engine_reset(IBusEngine *engine) {
    IBusVieLotusEngine *vl_engine = (IBusVieLotusEngine *)engine;
    ibus_vielotus_engine_reset_internal(vl_engine);
    if (vl_engine->session) {
        vielotus_append_context(vl_engine->session, "");
    }
    IBUS_ENGINE_CLASS(ibus_vielotus_engine_parent_class)->reset(engine);
}

static void ibus_vielotus_engine_enable(IBusEngine *engine) {
    IBusVieLotusEngine *vl_engine = (IBusVieLotusEngine *)engine;
    const gchar *engine_name = ibus_engine_get_name(engine);
    if (engine_name && strstr(engine_name, "vni") != NULL) {
        vl_engine->is_vni = TRUE;
        vielotus_set_input_method(vl_engine->session, VIELOTUS_INPUT_VNI);
    } else {
        vl_engine->is_vni = FALSE;
        vielotus_set_input_method(vl_engine->session, VIELOTUS_INPUT_TELEX);
    }
    ibus_vielotus_load_user_config(vl_engine);
    ibus_vielotus_build_prop_list(vl_engine);
    ibus_vielotus_engine_reset_internal(vl_engine);
    if (vl_engine->session) {
        vielotus_append_context(vl_engine->session, "");
    }
    IBUS_ENGINE_CLASS(ibus_vielotus_engine_parent_class)->enable(engine);
}

static gboolean ibus_vielotus_is_sensitive_content_type(guint purpose, guint hints) {
    (void)hints;
    return (purpose == IBUS_INPUT_PURPOSE_PASSWORD) ||
           (purpose == IBUS_INPUT_PURPOSE_PIN);
}

static void ibus_vielotus_engine_set_content_type(
    IBusEngine *engine,
    guint purpose,
    guint hints
) {
    IBusVieLotusEngine *vl_engine = (IBusVieLotusEngine *)engine;
    gboolean is_sensitive = ibus_vielotus_is_sensitive_content_type(purpose, hints);
    vl_engine->is_password_field = is_sensitive;
    if (is_sensitive) {
        if (vielotus_is_composing(vl_engine->session)) {
            ibus_vielotus_engine_reset_internal(vl_engine);
        }
        if (vl_engine->session) {
            vielotus_append_context(vl_engine->session, "");
        }
    }
    if (IBUS_ENGINE_CLASS(ibus_vielotus_engine_parent_class)->set_content_type) {
        IBUS_ENGINE_CLASS(ibus_vielotus_engine_parent_class)->set_content_type(engine, purpose, hints);
    }
}

static void ibus_vielotus_engine_disable(IBusEngine *engine) {
    IBusVieLotusEngine *vl_engine = (IBusVieLotusEngine *)engine;
    vl_engine->is_password_field = FALSE;
    if (vielotus_is_composing(vl_engine->session)) {
        ibus_vielotus_commit_composing(vl_engine, NULL);
    } else {
        ibus_vielotus_engine_reset_internal(vl_engine);
    }
    if (vl_engine->session) {
        vielotus_append_context(vl_engine->session, "");
    }
    IBUS_ENGINE_CLASS(ibus_vielotus_engine_parent_class)->disable(engine);
}

static void ibus_vielotus_engine_focus_in(IBusEngine *engine) {
    IBusVieLotusEngine *vl_engine = (IBusVieLotusEngine *)engine;
    guint purpose = IBUS_INPUT_PURPOSE_FREE_FORM;
    guint hints = IBUS_INPUT_HINT_NONE;
    ibus_engine_get_content_type(engine, &purpose, &hints);
    vl_engine->is_password_field = ibus_vielotus_is_sensitive_content_type(purpose, hints);
    if (vl_engine->session) {
        vielotus_append_context(vl_engine->session, "");
    }
    ibus_vielotus_load_user_config(vl_engine);
    ibus_vielotus_build_prop_list(vl_engine);
    ibus_engine_register_properties(engine, vl_engine->prop_list);
    IBUS_ENGINE_CLASS(ibus_vielotus_engine_parent_class)->focus_in(engine);
}

static void ibus_vielotus_engine_focus_out(IBusEngine *engine) {
    IBusVieLotusEngine *vl_engine = (IBusVieLotusEngine *)engine;
    vl_engine->is_password_field = FALSE;
    if (vielotus_is_composing(vl_engine->session)) {
        ibus_vielotus_commit_composing(vl_engine, NULL);
    } else {
        ibus_vielotus_engine_reset_internal(vl_engine);
    }
    if (vl_engine->session) {
        vielotus_append_context(vl_engine->session, "");
    }
    IBUS_ENGINE_CLASS(ibus_vielotus_engine_parent_class)->focus_out(engine);
}

static void ibus_vielotus_engine_property_activate(
    IBusEngine *engine,
    const gchar *prop_name,
    guint prop_state
) {
    IBusVieLotusEngine *vl_engine = (IBusVieLotusEngine *)engine;
    if (g_strcmp0(prop_name, "more-settings") == 0) {
        if (g_file_test("/usr/bin/vielotus-settings", G_FILE_TEST_IS_EXECUTABLE)) {
            g_spawn_command_line_async("/usr/bin/vielotus-settings", NULL);
        } else {
            g_spawn_command_line_async("vielotus", NULL);
        }
        return;
    } else if (g_strcmp0(prop_name, "smart-bilingual") == 0) {
        vl_engine->smart_bilingual = (prop_state == PROP_STATE_CHECKED);
        vielotus_set_smart_bilingual(vl_engine->session, vl_engine->smart_bilingual);
    } else if (g_strcmp0(prop_name, "sen-flex") == 0) {
        vl_engine->sen_flex = (prop_state == PROP_STATE_CHECKED);
        vielotus_set_grammar_profile(
            vl_engine->session,
            vl_engine->sen_flex ? VIELOTUS_GRAMMAR_SEN_FLEX : VIELOTUS_GRAMMAR_CLASSIC
        );
    } else if (g_strcmp0(prop_name, "modern-orthography") == 0) {
        vl_engine->modern_orthography = (prop_state == PROP_STATE_CHECKED);
        vielotus_set_modern_orthography(vl_engine->session, vl_engine->modern_orthography);
    } else if (g_strcmp0(prop_name, "quick-telex") == 0) {
        vl_engine->quick_telex = (prop_state == PROP_STATE_CHECKED);
        vielotus_set_quick_telex(vl_engine->session, vl_engine->quick_telex);
    } else if (g_strcmp0(prop_name, "preedit-underline") == 0) {
        vl_engine->preedit_underline = (prop_state == PROP_STATE_CHECKED);
    }
    ibus_vielotus_save_user_config(vl_engine);
    ibus_vielotus_build_prop_list(vl_engine);
    ibus_engine_register_properties(engine, vl_engine->prop_list);
}

static void ibus_vielotus_reload_config_if_changed(IBusVieLotusEngine *vl_engine) {
    if (!vl_engine->session) {
        return;
    }
    gchar *dir_path = ibus_vielotus_get_config_dir();
    if (!dir_path) {
        return;
    }
    gchar *path = g_build_filename(dir_path, "config.env", NULL);
    g_free(dir_path);
    struct stat st;
    if (stat(path, &st) == 0 && st.st_mtime != vl_engine->config_mtime) {
        g_free(path);
        ibus_vielotus_load_user_config(vl_engine);
        ibus_vielotus_build_prop_list(vl_engine);
        ibus_engine_register_properties((IBusEngine *)vl_engine, vl_engine->prop_list);
        return;
    }
    g_free(path);
}

static gboolean ibus_vielotus_engine_process_key_event(
    IBusEngine *engine,
    guint keyval,
    guint keycode,
    guint state
) {
    IBusVieLotusEngine *vl_engine = (IBusVieLotusEngine *)engine;
    (void)keycode;

    // Ignore key release events
    if (state & IBUS_RELEASE_MASK) {
        return FALSE;
    }

    // Password / PIN / hidden-text field protection: deterministically clear active composition and pass through raw keystrokes
    if (vl_engine->is_password_field) {
        if (vielotus_is_composing(vl_engine->session)) {
            ibus_vielotus_engine_reset_internal(vl_engine);
        }
        if (vl_engine->session) {
            vielotus_append_context(vl_engine->session, "");
        }
        return FALSE;
    }

    if (!vielotus_is_composing(vl_engine->session)) {
        ibus_vielotus_reload_config_if_changed(vl_engine);
    }

    // Ignore pure modifier presses (Shift, CapsLock) so uppercase letters work mid-word
    if (keyval == IBUS_KEY_Shift_L || keyval == IBUS_KEY_Shift_R ||
        keyval == IBUS_KEY_Caps_Lock || keyval == IBUS_KEY_Shift_Lock ||
        keyval == IBUS_KEY_ISO_Level3_Shift) {
        return FALSE;
    }

    // Pass through hotkey modifiers (Control, Alt, Super/Win) after committing active word
    if (state & (IBUS_CONTROL_MASK | IBUS_MOD1_MASK | IBUS_SUPER_MASK)) {
        if (vielotus_is_composing(vl_engine->session)) {
            ibus_vielotus_commit_composing(vl_engine, NULL);
        }
        return FALSE;
    }

    // Navigation & action keys (Enter, Tab, Delete, Escape, Arrows, Home/End/PgUp/PgDn):
    // commit active word first so it never disappears, clear sentence context, then pass the key through
    if (keyval == IBUS_KEY_Return || keyval == IBUS_KEY_KP_Enter || keyval == IBUS_KEY_Linefeed ||
        keyval == IBUS_KEY_Tab || keyval == IBUS_KEY_ISO_Left_Tab || keyval == IBUS_KEY_KP_Tab ||
        keyval == IBUS_KEY_Delete || keyval == IBUS_KEY_KP_Delete ||
        keyval == IBUS_KEY_Escape ||
        keyval == '\r' || keyval == '\n' || keyval == '\t' || keyval == 0x1b ||
        (keyval >= IBUS_KEY_Home && keyval <= IBUS_KEY_Insert) ||
        (keyval >= IBUS_KEY_KP_Home && keyval <= IBUS_KEY_KP_Delete)) {
        if (vielotus_is_composing(vl_engine->session)) {
            ibus_vielotus_commit_composing(vl_engine, NULL);
        }
        if (vl_engine->session) {
            vielotus_append_context(vl_engine->session, "");
        }
        return FALSE;
    }

    // Handle BackSpace
    if (keyval == IBUS_KEY_BackSpace) {
        if (vielotus_is_composing(vl_engine->session)) {
            ibus_vielotus_backspace_composing(vl_engine);
            return TRUE;
        }
        // When not composing, never call vielotus_feed_backspace (which would set editCaretBack=0
        // and resurrect committed words into preedit on the 2nd BackSpace, causing word duplication).
        vielotus_reset_session(vl_engine->session);
        return FALSE;
    }

    // Handle printable ASCII characters (32..126)
    if (keyval >= 32 && keyval < 127) {
        gboolean is_alpha = (keyval >= 'a' && keyval <= 'z') || (keyval >= 'A' && keyval <= 'Z');
        gboolean is_digit = (keyval >= '0' && keyval <= '9');
        gboolean is_word_char = is_alpha || (vl_engine->is_vni && is_digit && vielotus_is_composing(vl_engine->session));

        if (!is_word_char) {
            if (vielotus_is_composing(vl_engine->session)) {
                if (keyval == '(' || keyval == '[' || keyval == '{') {
                    vielotus_feed_char(vl_engine->session, keyval);
                    const char *committed = vielotus_get_last_text(vl_engine->session);
                    char buf[1024];
                    snprintf(buf, sizeof(buf), "%s%c", committed ? committed : "", (char)keyval);
                    IBusText *commit_text = ibus_text_new_from_string(buf);
                    ibus_engine_commit_text(engine, commit_text);
                    ibus_vielotus_engine_reset_internal(vl_engine);
                    return TRUE;
                }
                char trail[2] = { (char)keyval, '\0' };
                ibus_vielotus_commit_composing(vl_engine, trail);
                return TRUE;
            } else {
                vielotus_feed_char(vl_engine->session, keyval);
                return FALSE;
            }
        }

        /* Auto-flush preedit before internal 64-token buffer limit (e.g. holding a key for 80+ characters) */
        if (vielotus_is_composing(vl_engine->session)) {
            const char *raw_check = vielotus_get_raw_text(vl_engine->session);
            const char *comp_check = vielotus_get_composing_text(vl_engine->session);
            if ((raw_check && strlen(raw_check) >= 48) ||
                (comp_check && strlen(comp_check) >= 48)) {
                ibus_vielotus_commit_composing(vl_engine, NULL);
            }
        }

        if (!vl_engine->is_vni && vielotus_is_composing(vl_engine->session)) {
            char lower_key = vl_tolower((char)keyval);
            uint8_t key_tone = ibus_vielotus_telex_tone_for_key(lower_key);
            const char *raw_before = vielotus_get_raw_text(vl_engine->session);
            const char *comp_before = vielotus_get_composing_text(vl_engine->session);
            if (key_tone > 0 && raw_before && comp_before && ibus_vielotus_has_non_ascii(comp_before)) {
                size_t rlen = strlen(raw_before);
                size_t clen = strlen(comp_before);
                uint8_t active_tone = ibus_vielotus_active_tone_of_utf8(comp_before);
                /* 1. Non-adjacent duplicate tone key (e.g. "vieejt" + 'j' after Backspace on "việt" -> "việ" + 't'):
                 * keep the tone on "việt" and canonicalize raw keys to "vieetj" instead of cancelling to "viêtj". */
                if (active_tone == key_tone && rlen > 0 && vl_tolower(raw_before[rlen - 1]) != lower_key) {
                    char canon_raw[1024];
                    ibus_vielotus_raw_keys_for_utf8(comp_before, FALSE, canon_raw, sizeof(canon_raw));
                    ibus_vielotus_replay_raw_keys(vl_engine, canon_raw);
                    ibus_vielotus_update_preedit(vl_engine);
                    return TRUE;
                }
                /* 2. Stop-coda recovery when 's' or 'j' is pressed after an accidental rejected 'f'/'r'/'x'
                 * on a modified Vietnamese stem (e.g. "vieetfj" -> "việt" instead of "viêtfj"). */
                if ((key_tone == 2 || key_tone == 5) && active_tone == 0 && rlen >= 3 && clen >= 3 && rlen < 512) {
                    char last_r = vl_tolower(raw_before[rlen - 1]);
                    char prev_c = vl_tolower(comp_before[clen - 2]);
                    if ((last_r == 'f' || last_r == 'r' || last_r == 'x') &&
                        vl_tolower(comp_before[clen - 1]) == last_r &&
                        (prev_c == 't' || prev_c == 'c' || prev_c == 'p' || prev_c == 'h')) {
                        char fixed_raw[512];
                        memcpy(fixed_raw, raw_before, rlen);
                        fixed_raw[rlen - 1] = (char)keyval;
                        fixed_raw[rlen] = '\0';
                        ibus_vielotus_replay_raw_keys(vl_engine, fixed_raw);
                        ibus_vielotus_update_preedit(vl_engine);
                        return TRUE;
                    }
                }
            }
        }

        int32_t action = vielotus_feed_char(vl_engine->session, keyval);
        if (!vl_engine->is_vni && vielotus_is_composing(vl_engine->session)) {
            char lower_key = vl_tolower((char)keyval);
            if (lower_key == 'a' || lower_key == 'e' || lower_key == 'o') {
                const char *raw_after = vielotus_get_raw_text(vl_engine->session);
                const char *comp_after = vielotus_get_composing_text(vl_engine->session);
                if (raw_after && comp_after) {
                    size_t rlen = strlen(raw_after);
                    size_t clen = strlen(comp_after);
                    /* 3. Mid-vowel tone before second circumflex vowel on open diphthongs (e.g. "vieje" -> "việ",
                     * "tieje" -> "tiệ", "muojo" -> "muộ") so 'e'+'j'+'e' forms 'ệ' immediately instead of "viẹe". */
                    if (rlen >= 3 && rlen < 512 && clen >= 2 &&
                        vl_tolower(raw_after[rlen - 1]) == lower_key &&
                        vl_tolower(raw_after[rlen - 3]) == lower_key &&
                        vl_tolower(comp_after[clen - 1]) == lower_key) {
                        uint8_t mid_tone = ibus_vielotus_telex_tone_for_key(vl_tolower(raw_after[rlen - 2]));
                        gboolean allow_swap = (mid_tone == 5) ||
                            (mid_tone > 0 && lower_key == 'e' && rlen >= 4 &&
                             (vl_tolower(raw_after[rlen - 4]) == 'i' || vl_tolower(raw_after[rlen - 4]) == 'y') &&
                             vl_tolower(raw_after[0]) != 'p') ||
                            (mid_tone > 0 && lower_key == 'o' && rlen >= 4 &&
                             vl_tolower(raw_after[rlen - 4]) == 'u');
                        if (allow_swap && ibus_vielotus_active_tone_of_utf8(comp_after) == mid_tone) {
                            char swapped_raw[512];
                            memcpy(swapped_raw, raw_after, rlen + 1);
                            char tmp = swapped_raw[rlen - 2];
                            swapped_raw[rlen - 2] = swapped_raw[rlen - 1];
                            swapped_raw[rlen - 1] = tmp;
                            ibus_vielotus_replay_raw_keys(vl_engine, swapped_raw);
                        }
                    }
                }
            }
        }
        if (action == VIELOTUS_ACTION_COMMIT) {
            const char *committed = vielotus_get_last_text(vl_engine->session);
            char buf[1024];
            snprintf(buf, sizeof(buf), "%s", committed ? committed : "");
            if (buf[0] != '\0') {
                IBusText *commit_text = ibus_text_new_from_string(buf);
                ibus_engine_commit_text(engine, commit_text);
            }
            ibus_vielotus_engine_reset_internal(vl_engine);
            return TRUE;
        } else if (vielotus_is_composing(vl_engine->session) ||
                   action == VIELOTUS_ACTION_REPLACE ||
                   action == VIELOTUS_ACTION_CONSUMED) {
            ibus_vielotus_update_preedit(vl_engine);
            return TRUE;
        }
        return FALSE;
    }

    // Any other key (Enter, Tab, Arrows, Home/End, Escape, Function keys):
    // commit active word first so it never disappears, then pass the key through
    if (vielotus_is_composing(vl_engine->session)) {
        ibus_vielotus_commit_composing(vl_engine, NULL);
    }
    return FALSE;
}

static void ibus_vielotus_engine_class_init(IBusVieLotusEngineClass *klass) {
    GObjectClass *object_class = G_OBJECT_CLASS(klass);
    IBusEngineClass *engine_class = IBUS_ENGINE_CLASS(klass);

    object_class->finalize = ibus_vielotus_engine_finalize;

    engine_class->reset = ibus_vielotus_engine_reset;
    engine_class->enable = ibus_vielotus_engine_enable;
    engine_class->disable = ibus_vielotus_engine_disable;
    engine_class->focus_in = ibus_vielotus_engine_focus_in;
    engine_class->focus_out = ibus_vielotus_engine_focus_out;
    engine_class->set_content_type = ibus_vielotus_engine_set_content_type;
    engine_class->property_activate = ibus_vielotus_engine_property_activate;
    engine_class->process_key_event = ibus_vielotus_engine_process_key_event;
}

int main(int argc, char **argv) {
    static gboolean ibus = FALSE;
    GError *error = NULL;
    GOptionContext *context;

    static const GOptionEntry entries[] = {
        { "ibus", 'i', 0, G_OPTION_ARG_NONE, &ibus, "Executed by ibus-daemon", NULL },
        { NULL }
    };

    context = g_option_context_new("- VieLotusIM (Sen Việt) IBus Engine");
    g_option_context_add_main_entries(context, entries, "ibus-vielotus");

    if (!g_option_context_parse(context, &argc, &argv, &error)) {
        g_print("Option parsing failed: %s\n", error->message);
        g_error_free(error);
        return 1;
    }
    g_option_context_free(context);

    ibus_init();

    IBusBus *bus = ibus_bus_new();
    if (!ibus_bus_is_connected(bus)) {
        g_warning("Cannot connect to IBus daemon!");
        return 1;
    }

    IBusFactory *factory = ibus_factory_new(ibus_bus_get_connection(bus));
    ibus_factory_add_engine(factory, "vielotus", IBUS_TYPE_VIELOTUS_ENGINE);
    ibus_factory_add_engine(factory, "vielotus-vni", IBUS_TYPE_VIELOTUS_ENGINE);

    if (ibus) {
        ibus_bus_request_name(bus, "org.freedesktop.IBus.VieLotus", 0);
    } else {
        const char *snap_dir = getenv("SNAP");
        char comp_path[512];
        if (snap_dir && snap_dir[0] != '\0') {
            snprintf(comp_path, sizeof(comp_path), "%s/usr/share/ibus/component/vielotus.xml", snap_dir);
        } else {
            snprintf(comp_path, sizeof(comp_path), "/usr/share/ibus/component/vielotus.xml");
        }
        IBusComponent *component = ibus_component_new_from_file(comp_path);
        if (component) {
            ibus_bus_register_component(bus, component);
        }
    }

    ibus_main();
    return 0;
}
