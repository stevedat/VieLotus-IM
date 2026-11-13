/*
 * VieLotusIM (Sen Việt) - Native IBus Engine
 * Clean-Room C11 Bridge via C-ABI (vielotus.h) & vielotus_linux_common.h
 * SPDX-License-Identifier: MIT
 */

#include <ibus.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <time.h>
#include "vielotus.h"
#include "vielotus_linux_common.h"

#define IBUS_TYPE_VIELOTUS_ENGINE (ibus_vielotus_engine_get_type())
#ifndef IBUS_ATTR_UNDERLINE_NONE
#define IBUS_ATTR_UNDERLINE_NONE 0
#endif

static const char *const kSystemTypingModesPath =
    "/usr/share/vielotus/VietLotusIM_VieLotusCore.resources/typing-modes.yml";

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
    gboolean replayed_after_backspace;
    gboolean engine_enabled;
    gboolean preedit_visible;
    time_t config_mtime;
    time_t macros_mtime;
    bool macros_had_file;
    gchar *config_path;
    gchar *macros_path;
    gchar *rules_path;
    vl_presentation_rules_t presentation_rules;
    vl_presentation_mode_t active_presentation_mode;
    vl_dev_code_state_t dev_code_state;
    IBusPropList *prop_list;
};

struct _IBusVieLotusEngineClass {
    IBusEngineClass parent_class;
};

GType ibus_vielotus_engine_get_type(void);
G_DEFINE_TYPE(IBusVieLotusEngine, ibus_vielotus_engine, IBUS_TYPE_ENGINE)

static gchar *ibus_vielotus_get_config_dir(void) {
    char dir_buf[1024];
    if (vl_resolve_config_dir(dir_buf, sizeof(dir_buf))) {
        return g_strdup(dir_buf);
    }
    const gchar *cfg_root = g_get_user_config_dir();
    if (!cfg_root) {
        return NULL;
    }
    return g_build_filename(cfg_root, "vielotus", NULL);
}

static void ibus_vielotus_ensure_paths(IBusVieLotusEngine *vl_engine) {
    if (vl_engine->config_path) {
        return;
    }
    gchar *dir_path = ibus_vielotus_get_config_dir();
    if (dir_path) {
        vl_engine->config_path = g_build_filename(dir_path, "config.env", NULL);
        vl_engine->macros_path = g_build_filename(dir_path, "macros.json", NULL);
        vl_engine->rules_path = g_build_filename(dir_path, "typing-modes.yml", NULL);
        g_free(dir_path);
    }
}

static const gchar *ibus_vielotus_get_config_path(IBusVieLotusEngine *vl_engine) {
    ibus_vielotus_ensure_paths(vl_engine);
    return vl_engine->config_path;
}

static void ibus_vielotus_reload_auxiliary_data(IBusVieLotusEngine *vl_engine) {
    ibus_vielotus_ensure_paths(vl_engine);
    vl_macros_reload_if_changed(
        vl_engine->macros_path,
        &vl_engine->macros_mtime,
        &vl_engine->macros_had_file
    );
    vl_presentation_rules_reload_if_changed(
        &vl_engine->presentation_rules,
        vl_engine->rules_path,
        kSystemTypingModesPath
    );
}

static vl_presentation_mode_t ibus_vielotus_resolve_client_mode(
    IBusVieLotusEngine *vl_engine,
    const gchar *client_id
) {
    if (!vl_engine || vl_engine->presentation_rules.count == 0) {
        return VL_PRESENTATION_AUTOMATIC;
    }
    const char *candidate = (client_id && client_id[0] != '\0') ? client_id : getenv("VIELOTUS_APP_ID");
    if (!candidate || candidate[0] == '\0') {
        return VL_PRESENTATION_AUTOMATIC;
    }
    vl_presentation_mode_t m = vl_presentation_rules_resolve(&vl_engine->presentation_rules, candidate);
    if (m != VL_PRESENTATION_AUTOMATIC) {
        return m;
    }
    const char *colon = strchr(candidate, ':');
    if (colon && colon[1] != '\0') {
        m = vl_presentation_rules_resolve(&vl_engine->presentation_rules, colon + 1);
    }
    return m;
}

static void ibus_vielotus_load_user_config(IBusVieLotusEngine *vl_engine) {
    if (!vl_engine->session) {
        return;
    }
    const gchar *path = ibus_vielotus_get_config_path(vl_engine);
    vl_env_config_t env;
    vl_env_config_init_defaults(&env);
    env.sen_flex = vl_engine->sen_flex ? true : false;
    env.smart_bilingual = vl_engine->smart_bilingual ? true : false;
    env.modern_orthography = vl_engine->modern_orthography ? true : false;
    env.quick_telex = vl_engine->quick_telex ? true : false;
    env.relaxed_coda = vl_engine->relaxed_coda ? true : false;
    env.macro_enabled = vl_engine->macro_enabled ? true : false;
    env.developer_mode = vl_engine->developer_mode ? true : false;
    env.preedit_underline = vl_engine->preedit_underline ? true : false;

    bool loaded = false;
    if (path) {
        loaded = vl_env_config_load(path, &env, &vl_engine->config_mtime);
    }
    if (loaded) {
        vl_engine->sen_flex = env.sen_flex ? TRUE : FALSE;
        vl_engine->smart_bilingual = env.smart_bilingual ? TRUE : FALSE;
        vl_engine->modern_orthography = env.modern_orthography ? TRUE : FALSE;
        vl_engine->quick_telex = env.quick_telex ? TRUE : FALSE;
        vl_engine->relaxed_coda = env.relaxed_coda ? TRUE : FALSE;
        vl_engine->macro_enabled = env.macro_enabled ? TRUE : FALSE;
        vl_engine->developer_mode = env.developer_mode ? TRUE : FALSE;
        vl_engine->preedit_underline = env.preedit_underline ? TRUE : FALSE;
    }

    const gchar *engine_name = ibus_engine_get_name((IBusEngine *)vl_engine);
    if (loaded && env.has_input_method) {
        vl_engine->is_vni = env.is_vni ? TRUE : FALSE;
    } else if (engine_name && strstr(engine_name, "vni") != NULL) {
        vl_engine->is_vni = TRUE;
    } else {
        vl_engine->is_vni = FALSE;
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
    vielotus_set_relaxed_coda(vl_engine->session, vl_engine->relaxed_coda);
    vielotus_set_macro_enabled(vl_engine->session, vl_engine->macro_enabled);
    if (!vl_engine->developer_mode) {
        vl_dev_code_reset(&vl_engine->dev_code_state);
    }
}

static void ibus_vielotus_save_user_config(IBusVieLotusEngine *vl_engine) {
    const gchar *path = ibus_vielotus_get_config_path(vl_engine);
    if (!path) {
        return;
    }
    vl_env_config_t env;
    vl_env_config_init_defaults(&env);
    env.has_input_method = true;
    env.is_vni = vl_engine->is_vni ? true : false;
    env.sen_flex = vl_engine->sen_flex ? true : false;
    env.smart_bilingual = vl_engine->smart_bilingual ? true : false;
    env.modern_orthography = vl_engine->modern_orthography ? true : false;
    env.quick_telex = vl_engine->quick_telex ? true : false;
    env.relaxed_coda = vl_engine->relaxed_coda ? true : false;
    env.macro_enabled = vl_engine->macro_enabled ? true : false;
    env.developer_mode = vl_engine->developer_mode ? true : false;
    env.preedit_underline = vl_engine->preedit_underline ? true : false;
    (void)vl_env_config_save_merged(path, &env, &vl_engine->config_mtime);
}

static void ibus_vielotus_build_prop_list(IBusVieLotusEngine *vl_engine) {
    if (vl_engine->prop_list) {
        g_object_unref(vl_engine->prop_list);
    }
    vl_engine->prop_list = ibus_prop_list_new();
    g_object_ref_sink(vl_engine->prop_list);

    IBusProperty *prop;
    IBusText *label;

    label = ibus_text_new_from_static_string("Kiểu gõ: Telex Tự Do (vieetj → việt)");
    prop = ibus_property_new("im-telex", PROP_TYPE_TOGGLE, label, NULL, NULL,
                             TRUE, TRUE,
                             !vl_engine->is_vni ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED,
                             NULL);
    ibus_prop_list_append(vl_engine->prop_list, prop);

    label = ibus_text_new_from_static_string("Kiểu gõ: VNI Chuẩn (viet65 → việt)");
    prop = ibus_property_new("im-vni", PROP_TYPE_TOGGLE, label, NULL, NULL,
                             TRUE, TRUE,
                             vl_engine->is_vni ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED,
                             NULL);
    ibus_prop_list_append(vl_engine->prop_list, prop);

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

    label = ibus_text_new_from_static_string("Gõ tắt thông minh (Smart Macro)");
    prop = ibus_property_new("macro-enabled", PROP_TYPE_TOGGLE, label, NULL, NULL,
                             TRUE, TRUE,
                             vl_engine->macro_enabled ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED,
                             NULL);
    ibus_prop_list_append(vl_engine->prop_list, prop);

    label = ibus_text_new_from_static_string("Gõ tắt phụ âm (Quick Telex: cc=ch, gg=gi...)");
    prop = ibus_property_new("quick-telex", PROP_TYPE_TOGGLE, label, NULL, NULL,
                             TRUE, TRUE,
                             vl_engine->quick_telex ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED,
                             NULL);
    ibus_prop_list_append(vl_engine->prop_list, prop);

    label = ibus_text_new_from_static_string("Gõ vần tốc ký cuối từ (-g→-ng, -h, -k)");
    prop = ibus_property_new("relaxed-coda", PROP_TYPE_TOGGLE, label, NULL, NULL,
                             TRUE, TRUE,
                             vl_engine->relaxed_coda ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED,
                             NULL);
    ibus_prop_list_append(vl_engine->prop_list, prop);

    label = ibus_text_new_from_static_string("Chế độ lập trình viên (bỏ qua trong `code`)");
    prop = ibus_property_new("developer-mode", PROP_TYPE_TOGGLE, label, NULL, NULL,
                             TRUE, TRUE,
                             vl_engine->developer_mode ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED,
                             NULL);
    ibus_prop_list_append(vl_engine->prop_list, prop);


    label = ibus_text_new_from_static_string("Bảng cài đặt Sen Việt (Settings)...");
    prop = ibus_property_new("more-settings", PROP_TYPE_NORMAL, label, "preferences-system", NULL,
                             TRUE, TRUE, PROP_STATE_UNCHECKED, NULL);
    ibus_prop_list_append(vl_engine->prop_list, prop);
}

static void ibus_vielotus_clear_preedit(IBusEngine *engine) {
    IBusVieLotusEngine *vl_engine = (IBusVieLotusEngine *)engine;
    if (!vl_engine->preedit_visible) {
        return;
    }
    vl_engine->preedit_visible = FALSE;
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
    vl_engine->replayed_after_backspace = FALSE;
    if (vl_engine->session) {
        vielotus_reset_session(vl_engine->session);
    }
    ibus_vielotus_clear_preedit((IBusEngine *)vl_engine);
}


static gboolean ibus_vielotus_can_delete_surrounding_before_cursor(IBusEngine *engine, int32_t surr_del) {
    if (!engine || surr_del <= 0 || !(engine->client_capabilities & IBUS_CAP_SURROUNDING_TEXT)) {
        return FALSE;
    }
    IBusText *surr_text = NULL;
    guint cursor_pos = 0;
    guint anchor_pos = 0;
    ibus_engine_get_surrounding_text(engine, &surr_text, &cursor_pos, &anchor_pos);
    if (!surr_text) {
        return FALSE;
    }
    const gchar *text_str = ibus_text_get_text(surr_text);
    if (!text_str || text_str[0] == '\0') {
        return FALSE;
    }
    glong total_chars = g_utf8_strlen(text_str, -1);
    if (total_chars <= 0) {
        return FALSE;
    }
    if ((glong)cursor_pos > total_chars) {
        cursor_pos = (guint)total_chars;
    }
    return cursor_pos >= (guint)surr_del;
}

static void ibus_vielotus_commit_composing(IBusVieLotusEngine *vl_engine, const char *trailing_ascii) {
    IBusEngine *engine = (IBusEngine *)vl_engine;
    char buf[1024];
    buf[0] = '\0';
    size_t comp_cp_before = 0;
    int32_t surr_del = 0;
    gboolean can_delete_surr = FALSE;

    if (vl_engine->session && vielotus_is_composing(vl_engine->session)) {
        const char *comp_str = vielotus_get_composing_text(vl_engine->session);
        comp_cp_before = vl_utf8_codepoint_count(comp_str);
    }


    if (vl_engine->session && vielotus_is_composing(vl_engine->session)) {
        if (trailing_ascii && trailing_ascii[0] != '\0' && trailing_ascii[1] == '\0') {
            uint32_t cp = (uint32_t)(unsigned char)trailing_ascii[0];
            vielotus_feed_char(vl_engine->session, cp);
        } else {
            vielotus_commit_word(vl_engine->session);
        }
        int32_t total_bs = vielotus_get_last_backspaces(vl_engine->session);
        if (total_bs > (int32_t)comp_cp_before && comp_cp_before > 0) {
            surr_del = total_bs - (int32_t)comp_cp_before;
            can_delete_surr = ibus_vielotus_can_delete_surrounding_before_cursor(engine, surr_del);
        }
        const char *committed = vielotus_get_last_text(vl_engine->session);
        if (committed && committed[0] != '\0') {
            if (surr_del > 0 && !can_delete_surr) {
                committed = vl_utf8_after_first_space(committed);
            }
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
        if (surr_del > 0 && can_delete_surr) {
            ibus_vielotus_clear_preedit(engine);
            ibus_engine_delete_surrounding_text(engine, -surr_del, (guint)surr_del);
        }
        IBusText *commit_text = ibus_text_new_from_string(buf);
        ibus_engine_commit_text(engine, commit_text);
    }

    vl_engine->replayed_after_backspace = FALSE;
    if (vl_engine->session && vielotus_is_composing(vl_engine->session)) {
        vielotus_reset_session(vl_engine->session);
    }
    ibus_vielotus_clear_preedit(engine);
}

static void ibus_vielotus_update_preedit(IBusVieLotusEngine *vl_engine) {
    IBusEngine *engine = (IBusEngine *)vl_engine;
    if (vl_engine->session && vielotus_is_composing(vl_engine->session)) {
        const char *composing = vielotus_get_composing_text(vl_engine->session);
        if (composing && composing[0] != '\0') {
            vl_engine->preedit_visible = TRUE;
            IBusText *text = ibus_text_new_from_string(composing);
            guint char_len = ibus_text_get_length(text);
            gboolean show_ul = vl_engine->preedit_underline;
            if (vl_engine->active_presentation_mode == VL_PRESENTATION_MARKED_TEXT) {
                show_ul = TRUE;
            } else if (vl_engine->active_presentation_mode == VL_PRESENTATION_DIRECT_REPLACEMENT) {
                show_ul = FALSE;
            }
            guint ul_mode = show_ul ? IBUS_ATTR_UNDERLINE_SINGLE : IBUS_ATTR_UNDERLINE_NONE;
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

static void ibus_vielotus_replay_raw_keys(IBusVieLotusEngine *vl_engine, const char *raw_keys) {
    vielotus_reset_session(vl_engine->session);
    for (size_t i = 0; raw_keys[i] != '\0'; i++) {
        vielotus_feed_char(vl_engine->session, (uint32_t)(unsigned char)raw_keys[i]);
    }
}

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
    const size_t before_cp = vl_utf8_codepoint_count(composing);
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

    vielotus_feed_backspace(vl_engine->session);
    if (!vielotus_is_composing(vl_engine->session)) {
        ibus_vielotus_engine_reset_internal(vl_engine);
        return;
    }
    const char *after = vielotus_get_composing_text(vl_engine->session);
    if (after && after[0] != '\0' && vl_utf8_codepoint_count(after) < before_cp) {
        vl_engine->replayed_after_backspace = FALSE;
        ibus_vielotus_update_preedit(vl_engine);
        return;
    }

    if (cut == 0) {
        ibus_vielotus_engine_reset_internal(vl_engine);
        return;
    }
    char raw_keys[1024];
    vl_raw_keys_for_utf8(prefix, vl_engine->is_vni ? true : false, raw_keys, sizeof(raw_keys));
    ibus_vielotus_replay_raw_keys(vl_engine, raw_keys);
    vl_engine->replayed_after_backspace = TRUE;
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
    vl_engine->sen_flex = FALSE;
    vl_engine->modern_orthography = TRUE;
    vl_engine->quick_telex = FALSE;
    vl_engine->relaxed_coda = FALSE;
    vl_engine->macro_enabled = FALSE;
    vl_engine->developer_mode = FALSE;
    vl_engine->preedit_underline = FALSE;
    vl_engine->is_password_field = FALSE;
    vl_engine->replayed_after_backspace = FALSE;
    vl_engine->engine_enabled = FALSE;
    vl_engine->preedit_visible = FALSE;
    vl_engine->config_mtime = 0;
    vl_engine->macros_mtime = 0;
    vl_engine->macros_had_file = false;
    vl_engine->config_path = NULL;
    vl_engine->macros_path = NULL;
    vl_engine->rules_path = NULL;
    vl_presentation_rules_init(&vl_engine->presentation_rules);
    vl_engine->active_presentation_mode = VL_PRESENTATION_AUTOMATIC;
    vl_dev_code_reset(&vl_engine->dev_code_state);
    vl_engine->prop_list = NULL;

    vielotus_set_input_method(vl_engine->session, VIELOTUS_INPUT_TELEX);
    ibus_vielotus_load_user_config(vl_engine);
    ibus_vielotus_reload_auxiliary_data(vl_engine);
    ibus_vielotus_build_prop_list(vl_engine);
}

static void ibus_vielotus_engine_finalize(GObject *object) {
    IBusVieLotusEngine *vl_engine = (IBusVieLotusEngine *)object;
    if (vl_engine->config_path) {
        g_free(vl_engine->config_path);
        vl_engine->config_path = NULL;
    }
    if (vl_engine->macros_path) {
        g_free(vl_engine->macros_path);
        vl_engine->macros_path = NULL;
    }
    if (vl_engine->rules_path) {
        g_free(vl_engine->rules_path);
        vl_engine->rules_path = NULL;
    }
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
    vl_dev_code_reset(&vl_engine->dev_code_state);
    ibus_vielotus_engine_reset_internal(vl_engine);
    if (vl_engine->session) {
        vielotus_append_context(vl_engine->session, "");
    }
    IBUS_ENGINE_CLASS(ibus_vielotus_engine_parent_class)->reset(engine);
}

static void ibus_vielotus_activate_by_engine_name(IBusVieLotusEngine *vl_engine) {
    const gchar *engine_name = ibus_engine_get_name((IBusEngine *)vl_engine);
    ibus_vielotus_load_user_config(vl_engine);
    ibus_vielotus_reload_auxiliary_data(vl_engine);
    if (engine_name && engine_name[0] != '\0') {
        gboolean engine_is_vni = (strstr(engine_name, "vni") != NULL);
        vl_engine->is_vni = engine_is_vni;
        vielotus_set_input_method(
            vl_engine->session,
            vl_engine->is_vni ? VIELOTUS_INPUT_VNI : VIELOTUS_INPUT_TELEX
        );
        ibus_vielotus_save_user_config(vl_engine);
    }
    vl_engine->engine_enabled = TRUE;
    ibus_vielotus_build_prop_list(vl_engine);
}

static void ibus_vielotus_engine_enable(IBusEngine *engine) {
    IBusVieLotusEngine *vl_engine = (IBusVieLotusEngine *)engine;
    vl_engine->preedit_visible = FALSE;
    vl_dev_code_reset(&vl_engine->dev_code_state);
    ibus_vielotus_activate_by_engine_name(vl_engine);
    ibus_engine_register_properties(engine, vl_engine->prop_list);
    ibus_vielotus_engine_reset_internal(vl_engine);
    if (vl_engine->session) {
        vielotus_append_context(vl_engine->session, "");
    }
    if (engine->client_capabilities & IBUS_CAP_SURROUNDING_TEXT) {
        ibus_engine_get_surrounding_text(engine, NULL, NULL, NULL);
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
        vl_dev_code_reset(&vl_engine->dev_code_state);
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
    vl_engine->engine_enabled = FALSE;
    vl_engine->is_password_field = FALSE;
    vl_dev_code_reset(&vl_engine->dev_code_state);
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

static void ibus_vielotus_sync_armed_word_from_text(
    IBusVieLotusEngine *vl_engine,
    const gchar *text_str,
    guint cursor_pos,
    guint anchor_pos
) {
    (void)anchor_pos;
    if (!vl_engine || !vl_engine->session || vl_engine->is_password_field) {
        return;
    }
    if (!text_str || text_str[0] == '\0' || cursor_pos == 0) {
        vielotus_append_context(vl_engine->session, "");
        return;
    }
    const gchar *end_ptr = g_utf8_offset_to_pointer(text_str, (glong)cursor_pos);
    size_t byte_len = (size_t)(end_ptr - text_str);
    const size_t max_window = 256;
    const gchar *win_start = text_str;
    if (byte_len > max_window) {
        win_start = end_ptr - max_window;
        while (win_start < end_ptr && ((*win_start & 0xC0) == 0x80)) {
            win_start++;
        }
        byte_len = (size_t)(end_ptr - win_start);
    }
    char prefix_buf[260];
    if (byte_len < sizeof(prefix_buf)) {
        memcpy(prefix_buf, win_start, byte_len);
        prefix_buf[byte_len] = '\0';
        vielotus_sync_armed_word(vl_engine->session, prefix_buf);
    }
}

static gboolean ibus_vielotus_reload_config_if_changed(IBusVieLotusEngine *vl_engine);

static void ibus_vielotus_handle_focus_in_common(
    IBusEngine *engine,
    const gchar *client_id
) {
    IBusVieLotusEngine *vl_engine = (IBusVieLotusEngine *)engine;
    guint purpose = IBUS_INPUT_PURPOSE_FREE_FORM;
    guint hints = IBUS_INPUT_HINT_NONE;
    ibus_engine_get_content_type(engine, &purpose, &hints);
    vl_engine->is_password_field = ibus_vielotus_is_sensitive_content_type(purpose, hints);
    vl_dev_code_reset(&vl_engine->dev_code_state);
    if (vl_engine->session) {
        vielotus_append_context(vl_engine->session, "");
    }
    if (!vl_engine->is_password_field && (engine->client_capabilities & IBUS_CAP_SURROUNDING_TEXT)) {
        ibus_engine_get_surrounding_text(engine, NULL, NULL, NULL);
    }
    if (!vl_engine->engine_enabled) {
        ibus_vielotus_activate_by_engine_name(vl_engine);
    } else {
        ibus_vielotus_reload_config_if_changed(vl_engine);
        ibus_vielotus_reload_auxiliary_data(vl_engine);
    }
    vl_engine->active_presentation_mode = ibus_vielotus_resolve_client_mode(vl_engine, client_id);
    if (!vl_engine->prop_list) {
        ibus_vielotus_build_prop_list(vl_engine);
    }
    ibus_engine_register_properties(engine, vl_engine->prop_list);
}

static void ibus_vielotus_handle_focus_out_common(IBusEngine *engine) {
    IBusVieLotusEngine *vl_engine = (IBusVieLotusEngine *)engine;
    vl_engine->is_password_field = FALSE;
    vl_engine->active_presentation_mode = VL_PRESENTATION_AUTOMATIC;
    vl_dev_code_reset(&vl_engine->dev_code_state);
    if (vielotus_is_composing(vl_engine->session)) {
        ibus_vielotus_commit_composing(vl_engine, NULL);
    } else {
        ibus_vielotus_engine_reset_internal(vl_engine);
    }
    if (vl_engine->session) {
        vielotus_append_context(vl_engine->session, "");
    }
}

static void ibus_vielotus_engine_focus_in(IBusEngine *engine) {
    ibus_vielotus_handle_focus_in_common(engine, NULL);
    if (IBUS_ENGINE_CLASS(ibus_vielotus_engine_parent_class)->focus_in) {
        IBUS_ENGINE_CLASS(ibus_vielotus_engine_parent_class)->focus_in(engine);
    }
}

static void ibus_vielotus_engine_focus_out(IBusEngine *engine) {
    ibus_vielotus_handle_focus_out_common(engine);
    if (IBUS_ENGINE_CLASS(ibus_vielotus_engine_parent_class)->focus_out) {
        IBUS_ENGINE_CLASS(ibus_vielotus_engine_parent_class)->focus_out(engine);
    }
}

#if IBUS_CHECK_VERSION(1, 5, 27)
static GObject *ibus_vielotus_engine_constructor(
    GType type,
    guint n_construct_params,
    GObjectConstructParam *construct_params
) {
    for (guint i = 0; i < n_construct_params; i++) {
        if (construct_params[i].pspec &&
            g_strcmp0(construct_params[i].pspec->name, "has-focus-id") == 0) {
            g_value_set_boolean(construct_params[i].value, TRUE);
        }
    }
    return G_OBJECT_CLASS(ibus_vielotus_engine_parent_class)->constructor(
        type, n_construct_params, construct_params
    );
}

static void ibus_vielotus_engine_focus_in_id(
    IBusEngine *engine,
    const gchar *object_path,
    const gchar *client
) {
    ibus_vielotus_handle_focus_in_common(engine, client);
    if (IBUS_ENGINE_CLASS(ibus_vielotus_engine_parent_class)->focus_in_id) {
        IBUS_ENGINE_CLASS(ibus_vielotus_engine_parent_class)->focus_in_id(engine, object_path, client);
    }
}

static void ibus_vielotus_engine_focus_out_id(
    IBusEngine *engine,
    const gchar *object_path
) {
    ibus_vielotus_handle_focus_out_common(engine);
    if (IBUS_ENGINE_CLASS(ibus_vielotus_engine_parent_class)->focus_out_id) {
        IBUS_ENGINE_CLASS(ibus_vielotus_engine_parent_class)->focus_out_id(engine, object_path);
    }
}
#endif

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
            g_spawn_command_line_async("vielotus-settings", NULL);
        }
        return;
    } else if (g_strcmp0(prop_name, "im-telex") == 0 && prop_state == PROP_STATE_CHECKED) {
        vl_engine->is_vni = FALSE;
        vielotus_set_input_method(vl_engine->session, VIELOTUS_INPUT_TELEX);
        if (g_file_test("/usr/bin/vielotus-settings", G_FILE_TEST_IS_EXECUTABLE)) {
            g_spawn_command_line_async("/usr/bin/vielotus-settings --telex", NULL);
        }
    } else if (g_strcmp0(prop_name, "im-vni") == 0 && prop_state == PROP_STATE_CHECKED) {
        vl_engine->is_vni = TRUE;
        vielotus_set_input_method(vl_engine->session, VIELOTUS_INPUT_VNI);
        if (g_file_test("/usr/bin/vielotus-settings", G_FILE_TEST_IS_EXECUTABLE)) {
            g_spawn_command_line_async("/usr/bin/vielotus-settings --vni", NULL);
        }
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
    } else if (g_strcmp0(prop_name, "macro-enabled") == 0) {
        vl_engine->macro_enabled = (prop_state == PROP_STATE_CHECKED);
        vielotus_set_macro_enabled(vl_engine->session, vl_engine->macro_enabled);
    } else if (g_strcmp0(prop_name, "quick-telex") == 0) {
        vl_engine->quick_telex = (prop_state == PROP_STATE_CHECKED);
        vielotus_set_quick_telex(vl_engine->session, vl_engine->quick_telex);
    } else if (g_strcmp0(prop_name, "relaxed-coda") == 0) {
        vl_engine->relaxed_coda = (prop_state == PROP_STATE_CHECKED);
        vielotus_set_relaxed_coda(vl_engine->session, vl_engine->relaxed_coda);
    } else if (g_strcmp0(prop_name, "developer-mode") == 0) {
        vl_engine->developer_mode = (prop_state == PROP_STATE_CHECKED);
        if (!vl_engine->developer_mode) {
            vl_dev_code_reset(&vl_engine->dev_code_state);
        }
    }
    ibus_vielotus_save_user_config(vl_engine);
    ibus_vielotus_build_prop_list(vl_engine);
    ibus_engine_register_properties(engine, vl_engine->prop_list);
}

static gboolean ibus_vielotus_reload_config_if_changed(IBusVieLotusEngine *vl_engine) {
    if (!vl_engine->session) {
        return FALSE;
    }
    const gchar *path = ibus_vielotus_get_config_path(vl_engine);
    if (!path) {
        return FALSE;
    }
    struct stat st;
    if (stat(path, &st) == 0 && st.st_mtime != vl_engine->config_mtime) {
        ibus_vielotus_load_user_config(vl_engine);
        ibus_vielotus_build_prop_list(vl_engine);
        return TRUE;
    }
    return FALSE;
}

static inline gboolean ibus_vielotus_is_modifier_key(IBusVieLotusEngine *vl_engine, guint keyval) {
    if (vl_engine->is_vni) {
        return (keyval >= '0' && keyval <= '9');
    }
    char lower = vl_ascii_tolower((char)keyval);
    return (lower == 's' || lower == 'f' || lower == 'r' || lower == 'x' || lower == 'j' ||
            lower == 'w' || lower == 'a' || lower == 'e' || lower == 'o' || lower == 'd' || lower == 'z');
}

static gboolean ibus_vielotus_prepare_word_start_from_surrounding(
    IBusVieLotusEngine *vl_engine,
    guint keyval,
    guint keycode,
    guint state,
    uint64_t t0_us
) {
    IBusEngine *engine = (IBusEngine *)vl_engine;
    (void)keycode;
    (void)state;
    (void)t0_us;
    if (!vl_engine || !vl_engine->session || vl_engine->is_password_field) {
        return FALSE;
    }
    if (!(engine->client_capabilities & IBUS_CAP_SURROUNDING_TEXT)) {
        return FALSE;
    }
    IBusText *surrounding_text = NULL;
    guint cursor_pos = 0;
    guint anchor_pos = 0;
    ibus_engine_get_surrounding_text(engine, &surrounding_text, &cursor_pos, &anchor_pos);
    if (!surrounding_text) {
        return FALSE;
    }
    const gchar *text_str = ibus_text_get_text(surrounding_text);
    if (!text_str || text_str[0] == '\0') {
        return FALSE;
    }
    glong total_chars = g_utf8_strlen(text_str, -1);
    if ((glong)cursor_pos > total_chars) cursor_pos = (guint)total_chars;
    if ((glong)anchor_pos > total_chars) anchor_pos = (guint)total_chars;

    /* Case 1: Active selection [sel_start .. sel_end). */
    if (cursor_pos != anchor_pos) {
        guint sel_start = (cursor_pos < anchor_pos) ? cursor_pos : anchor_pos;
        guint sel_end = (cursor_pos > anchor_pos) ? cursor_pos : anchor_pos;
        guint sel_len = sel_end - sel_start;
        gint rel_offset = (gint)sel_start - (gint)cursor_pos;

        const gchar *start_ptr = g_utf8_offset_to_pointer(text_str, (glong)sel_start);
        const gchar *end_ptr = g_utf8_offset_to_pointer(text_str, (glong)sel_end);
        gboolean adj_word_char = FALSE;
        if (sel_start > 0) {
            const gchar *prev_p = g_utf8_prev_char(start_ptr);
            if (g_unichar_isalpha(g_utf8_get_char(prev_p))) adj_word_char = TRUE;
        }
        if (*end_ptr && g_unichar_isalpha(g_utf8_get_char(end_ptr))) {
            adj_word_char = TRUE;
        }
        ibus_engine_delete_surrounding_text(engine, rel_offset, sel_len);
        ibus_vielotus_sync_armed_word_from_text(vl_engine, text_str, sel_start, sel_start);
        if (adj_word_char || vl_has_non_ascii(text_str)) {
            vielotus_append_context(vl_engine->session, "ự");
        }
        return FALSE;
    }

    ibus_vielotus_sync_armed_word_from_text(vl_engine, text_str, cursor_pos, anchor_pos);

    /* Case 2: No selection — inspect contiguous letters around cursor_pos. */
    const gchar *cursor_ptr = g_utf8_offset_to_pointer(text_str, (glong)cursor_pos);
    const gchar *word_start_ptr = cursor_ptr;
    guint left_chars = 0;
    while (word_start_ptr > text_str && left_chars < 20) {
        const gchar *prev_p = g_utf8_prev_char(word_start_ptr);
        if (!g_unichar_isalpha(g_utf8_get_char(prev_p))) {
            break;
        }
        word_start_ptr = prev_p;
        left_chars++;
    }
    const gchar *word_end_ptr = cursor_ptr;
    guint right_chars = 0;
    while (*word_end_ptr && right_chars < 20) {
        if (!g_unichar_isalpha(g_utf8_get_char(word_end_ptr))) {
            break;
        }
        word_end_ptr = g_utf8_next_char(word_end_ptr);
        right_chars++;
    }
    guint total_word_cp = left_chars + right_chars;
    size_t word_bytes = (size_t)(word_end_ptr - word_start_ptr);

    if (total_word_cp >= 1 && total_word_cp <= 15 && word_bytes > 0 && word_bytes < 128) {
        char full_word[128];
        memcpy(full_word, word_start_ptr, word_bytes);
        full_word[word_bytes] = '\0';

        if (!ibus_vielotus_is_modifier_key(vl_engine, keyval)) {
            if (vl_has_non_ascii(full_word) || vl_has_non_ascii(text_str)) {
                vielotus_append_context(vl_engine->session, "ự");
            }
            return FALSE;
        }

        char canon_raw[256];
        vl_raw_keys_for_utf8(full_word, vl_engine->is_vni ? true : false, canon_raw, sizeof(canon_raw));
        if (canon_raw[0] != '\0') {
            vielotus_reset_session(vl_engine->session);
            if (vl_has_non_ascii(full_word) || vl_has_non_ascii(text_str)) {
                vielotus_append_context(vl_engine->session, "ự");
            }
            for (size_t i = 0; canon_raw[i] != '\0'; i++) {
                vielotus_feed_char(vl_engine->session, (uint32_t)(unsigned char)canon_raw[i]);
            }
            const char *reconstructed = vielotus_get_composing_text(vl_engine->session);
            if (vielotus_is_composing(vl_engine->session) &&
                reconstructed && strcmp(reconstructed, full_word) == 0) {
                vielotus_feed_char(vl_engine->session, keyval);
                const char *after_comp = vielotus_get_composing_text(vl_engine->session);
                if (vielotus_is_composing(vl_engine->session) &&
                    after_comp &&
                    vl_utf8_codepoint_count(after_comp) == total_word_cp &&
                    strcmp(after_comp, full_word) != 0 &&
                    vl_has_non_ascii(after_comp) &&
                    cursor_pos >= left_chars &&
                    (cursor_pos - left_chars + total_word_cp) <= (guint)total_chars) {
                    ibus_engine_delete_surrounding_text(engine, -(gint)left_chars, total_word_cp);
                    ibus_vielotus_update_preedit(vl_engine);
                    return TRUE;
                }
            }
            vielotus_reset_session(vl_engine->session);
            ibus_vielotus_sync_armed_word_from_text(vl_engine, text_str, cursor_pos, anchor_pos);
            if (vl_has_non_ascii(full_word) || vl_has_non_ascii(text_str)) {
                vielotus_append_context(vl_engine->session, "ự");
            }
        }
    }
    return FALSE;
}

static gboolean ibus_vielotus_engine_process_key_event(
    IBusEngine *engine,
    guint keyval,
    guint keycode,
    guint state
) {
    IBusVieLotusEngine *vl_engine = (IBusVieLotusEngine *)engine;
    (void)keycode;

    if (state & IBUS_RELEASE_MASK) {
        return FALSE;
    }

    /* Per-app passthrough rule from typing-modes.yml */
    if (vl_engine->active_presentation_mode == VL_PRESENTATION_PASSTHROUGH) {
        if (vielotus_is_composing(vl_engine->session)) {
            ibus_vielotus_engine_reset_internal(vl_engine);
        }
        return FALSE;
    }

    if (vl_engine->is_password_field) {
        if (vielotus_is_composing(vl_engine->session)) {
            ibus_vielotus_engine_reset_internal(vl_engine);
        }
        if (vl_engine->session) {
            vielotus_append_context(vl_engine->session, "");
        }
        return FALSE;
    }

    if (keyval == IBUS_KEY_Shift_L || keyval == IBUS_KEY_Shift_R ||
        keyval == IBUS_KEY_Caps_Lock || keyval == IBUS_KEY_Shift_Lock ||
        keyval == IBUS_KEY_ISO_Level3_Shift) {
        return FALSE;
    }

    if (state & (IBUS_CONTROL_MASK | IBUS_MOD1_MASK | IBUS_SUPER_MASK)) {
        if (vielotus_is_composing(vl_engine->session)) {
            ibus_vielotus_commit_composing(vl_engine, NULL);
        }
        return FALSE;
    }

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
        if (keyval == IBUS_KEY_Escape || keyval == 0x1b) {
            vl_dev_code_reset(&vl_engine->dev_code_state);
        } else if (keyval == IBUS_KEY_Return || keyval == IBUS_KEY_KP_Enter ||
                   keyval == IBUS_KEY_Linefeed || keyval == '\r' || keyval == '\n') {
            vl_dev_code_on_newline(&vl_engine->dev_code_state);
        }
        if (vl_engine->session) {
            vielotus_append_context(vl_engine->session, "");
        }
        return FALSE;
    }

    /* Developer Mode (`inline code` & ```fenced code``` bypass) */
    if (vl_engine->developer_mode) {
        if (keyval == '`') {
            if (vielotus_is_composing(vl_engine->session)) {
                char trail[2] = { '`', '\0' };
                ibus_vielotus_commit_composing(vl_engine, trail);
                vl_dev_code_on_backtick(&vl_engine->dev_code_state);
                return TRUE;
            }
            vl_dev_code_on_backtick(&vl_engine->dev_code_state);
            vielotus_feed_char(vl_engine->session, '`');
            return FALSE;
        }
        if (vl_dev_code_is_bypassing(&vl_engine->dev_code_state)) {
            vl_dev_code_on_non_backtick(&vl_engine->dev_code_state);
            return FALSE;
        }
    }

    if (keyval == IBUS_KEY_BackSpace) {
        if (vielotus_is_composing(vl_engine->session)) {
            ibus_vielotus_backspace_composing(vl_engine);
            return TRUE;
        }
        vielotus_reset_session(vl_engine->session);
        return FALSE;
    }

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

        if (vielotus_is_composing(vl_engine->session)) {
            const char *raw_check = vielotus_get_raw_text(vl_engine->session);
            const char *comp_check = vielotus_get_composing_text(vl_engine->session);
            if ((raw_check && strlen(raw_check) >= 48) ||
                (comp_check && strlen(comp_check) >= 48)) {
                ibus_vielotus_commit_composing(vl_engine, NULL);
            }
        } else {
            uint64_t adopt_t0 = 0;
            if (ibus_vielotus_prepare_word_start_from_surrounding(vl_engine, keyval, keycode, state, adopt_t0)) {
                return TRUE;
            }
        }

        if (!vl_engine->is_vni && vielotus_is_composing(vl_engine->session)) {
            char lower_key = vl_ascii_tolower((char)keyval);
            uint8_t key_tone = vl_telex_tone_for_key(lower_key);
            const char *raw_before = vielotus_get_raw_text(vl_engine->session);
            const char *comp_before = vielotus_get_composing_text(vl_engine->session);
            if (key_tone > 0 && raw_before && comp_before && vl_has_non_ascii(comp_before)) {
                size_t rlen = strlen(raw_before);
                size_t clen = strlen(comp_before);
                uint8_t active_tone = vl_active_tone_of_utf8(comp_before);
                if (vl_engine->replayed_after_backspace &&
                    active_tone == key_tone && rlen > 0 && vl_ascii_tolower(raw_before[rlen - 1]) != lower_key) {
                    char canon_raw[1024];
                    vl_raw_keys_for_utf8(comp_before, false, canon_raw, sizeof(canon_raw));
                    ibus_vielotus_replay_raw_keys(vl_engine, canon_raw);
                    ibus_vielotus_update_preedit(vl_engine);
                    return TRUE;
                }
                if ((key_tone == 2 || key_tone == 5) && active_tone == 0 && rlen >= 3 && clen >= 3 && rlen < 512) {
                    char last_r = vl_ascii_tolower(raw_before[rlen - 1]);
                    char prev_c = vl_ascii_tolower(comp_before[clen - 2]);
                    if ((last_r == 'f' || last_r == 'r' || last_r == 'x') &&
                        vl_ascii_tolower(comp_before[clen - 1]) == last_r &&
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
            char lower_key = vl_ascii_tolower((char)keyval);
            if (lower_key == 'a' || lower_key == 'e' || lower_key == 'o') {
                const char *raw_after = vielotus_get_raw_text(vl_engine->session);
                const char *comp_after = vielotus_get_composing_text(vl_engine->session);
                if (raw_after && comp_after) {
                    size_t rlen = strlen(raw_after);
                    size_t clen = strlen(comp_after);
                    if (rlen >= 3 && rlen < 512 && clen >= 2 &&
                        vl_ascii_tolower(raw_after[rlen - 1]) == lower_key &&
                        vl_ascii_tolower(raw_after[rlen - 3]) == lower_key &&
                        vl_ascii_tolower(comp_after[clen - 1]) == lower_key) {
                        uint8_t mid_tone = vl_telex_tone_for_key(vl_ascii_tolower(raw_after[rlen - 2]));
                        gboolean allow_swap = (mid_tone == 5) ||
                            (mid_tone > 0 && lower_key == 'e' && rlen >= 4 &&
                             (vl_ascii_tolower(raw_after[rlen - 4]) == 'i' || vl_ascii_tolower(raw_after[rlen - 4]) == 'y') &&
                             vl_ascii_tolower(raw_after[0]) != 'p') ||
                            (mid_tone > 0 && lower_key == 'o' && rlen >= 4 &&
                             vl_ascii_tolower(raw_after[rlen - 4]) == 'u');
                        if (allow_swap && vl_active_tone_of_utf8(comp_after) == mid_tone) {
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
            vl_engine->replayed_after_backspace = FALSE;
            ibus_vielotus_clear_preedit(engine);
            return TRUE;
        } else if (vielotus_is_composing(vl_engine->session) ||
                   action == VIELOTUS_ACTION_REPLACE ||
                   action == VIELOTUS_ACTION_CONSUMED) {
            ibus_vielotus_update_preedit(vl_engine);
            return TRUE;
        }
        return FALSE;
    }

    /* Normalize non-ASCII XKB `vn` / VM-forwarded Unicode keysyms & combining marks (U+0309 etc.) to NFC */
    if (keyval >= 128) {
        uint32_t uni_cp = (uint32_t)ibus_keyval_to_unicode(keyval);
        char mapped_seq[16];
        if (vl_keysym_to_raw_seq(keyval, uni_cp, vl_engine->is_vni ? true : false, mapped_seq, sizeof(mapped_seq))) {
            gboolean any_consumed = FALSE;
            guint clean_state = state & ~(IBUS_SHIFT_MASK | IBUS_LOCK_MASK);
            for (size_t i = 0; mapped_seq[i] != '\0'; i++) {
                guint sub_kv = (guint)(unsigned char)mapped_seq[i];
                if (ibus_vielotus_engine_process_key_event(engine, sub_kv, keycode, clean_state)) {
                    any_consumed = TRUE;
                }
            }
            if (any_consumed) {
                return TRUE;
            }
        }
    }

    if (vielotus_is_composing(vl_engine->session)) {
        ibus_vielotus_commit_composing(vl_engine, NULL);
    }
    return FALSE;
}

static void ibus_vielotus_engine_class_init(IBusVieLotusEngineClass *klass) {
    GObjectClass *object_class = G_OBJECT_CLASS(klass);
    IBusEngineClass *engine_class = IBUS_ENGINE_CLASS(klass);

#if IBUS_CHECK_VERSION(1, 5, 27)
    object_class->constructor = ibus_vielotus_engine_constructor;
#endif
    object_class->finalize = ibus_vielotus_engine_finalize;

    engine_class->reset = ibus_vielotus_engine_reset;
    engine_class->enable = ibus_vielotus_engine_enable;
    engine_class->disable = ibus_vielotus_engine_disable;
    engine_class->focus_in = ibus_vielotus_engine_focus_in;
    engine_class->focus_out = ibus_vielotus_engine_focus_out;
#if IBUS_CHECK_VERSION(1, 5, 27)
    engine_class->focus_in_id = ibus_vielotus_engine_focus_in_id;
    engine_class->focus_out_id = ibus_vielotus_engine_focus_out_id;
#endif
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

    if (g_file_test("/usr/bin/vielotus-settings", G_FILE_TEST_IS_EXECUTABLE)) {
        g_spawn_command_line_async("/usr/bin/vielotus-settings --repair-sources", NULL);
    }

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
