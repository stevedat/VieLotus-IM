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

static void ibus_vielotus_append_trace_log(
    const char *stage,
    const char *raw_str,
    const char *preedit_str,
    const char *commit_str,
    const char *mode_str
) {
    gchar *dir_path = ibus_vielotus_get_config_dir();
    if (!dir_path) {
        return;
    }
    g_mkdir_with_parents(dir_path, 0755);
    gchar *log_path = g_build_filename(dir_path, "lab-trace.log", NULL);
    g_free(dir_path);

    struct stat st;
    const char *open_mode = "a";
    if (stat(log_path, &st) == 0 && st.st_size > 262144) {
        open_mode = "w";
    }
    FILE *fp = fopen(log_path, open_mode);
    g_free(log_path);
    if (!fp) {
        return;
    }
    time_t now = time(NULL);
    struct tm tm_info;
    char tbuf[32];
    tbuf[0] = '\0';
    if (localtime_r(&now, &tm_info)) {
        strftime(tbuf, sizeof(tbuf), "%H:%M:%S", &tm_info);
    }
    fprintf(
        fp,
        "[%s] %-7s | raw=\"%s\" | preedit=\"%s\" | commit=\"%s\" | %s\n",
        tbuf,
        stage ? stage : "",
        raw_str ? raw_str : "",
        preedit_str ? preedit_str : "",
        commit_str ? commit_str : "",
        mode_str ? mode_str : ""
    );
    fclose(fp);
}

static void ibus_vielotus_commit_composing(IBusVieLotusEngine *vl_engine, const char *trailing_ascii) {
    IBusEngine *engine = (IBusEngine *)vl_engine;
    char buf[1024];
    char raw_before[512];
    char pre_before[512];
    buf[0] = '\0';
    raw_before[0] = '\0';
    pre_before[0] = '\0';
    gboolean is_override = FALSE;

    if (vl_engine->session && vielotus_is_composing(vl_engine->session)) {
        const char *r0 = vielotus_get_raw_text(vl_engine->session);
        const char *p0 = vielotus_get_composing_text(vl_engine->session);
        if (r0) snprintf(raw_before, sizeof(raw_before), "%s", r0);
        if (p0) snprintf(pre_before, sizeof(pre_before), "%s", p0);

        if (trailing_ascii && trailing_ascii[0] != '\0' && trailing_ascii[1] == '\0') {
            uint32_t cp = (uint32_t)(unsigned char)trailing_ascii[0];
            vielotus_feed_char(vl_engine->session, cp);
        } else {
            vielotus_commit_word(vl_engine->session);
        }
        const char *committed = vielotus_get_last_text(vl_engine->session);
        is_override = vielotus_get_last_is_override(vl_engine->session);
        if (committed && committed[0] != '\0') {
            snprintf(buf, sizeof(buf), "%s", committed);
        }
    }
    char word_only[512];
    snprintf(word_only, sizeof(word_only), "%s", buf);

    if (trailing_ascii && trailing_ascii[0] != '\0') {
        size_t len = strlen(buf);
        if (len < sizeof(buf) - 1) {
            snprintf(buf + len, sizeof(buf) - len, "%s", trailing_ascii);
        }
    }

    if (buf[0] != '\0') {
        gboolean restored = is_override || (raw_before[0] != '\0' && g_strcmp0(word_only, raw_before) == 0 && g_strcmp0(pre_before, word_only) != 0);
        ibus_vielotus_append_trace_log(
            "COMMIT",
            raw_before,
            pre_before,
            buf,
            restored ? "TRẢ THÔ EN (Restore Raw)" : "BIẾN ĐỔI VN (Transform)"
        );
        IBusText *commit_text = ibus_text_new_from_string(buf);
        ibus_engine_commit_text(engine, commit_text);
    }

    ibus_vielotus_engine_reset_internal(vl_engine);
}

static void ibus_vielotus_update_preedit(IBusVieLotusEngine *vl_engine) {
    IBusEngine *engine = (IBusEngine *)vl_engine;
    if (vl_engine->session && vielotus_is_composing(vl_engine->session)) {
        const char *composing = vielotus_get_composing_text(vl_engine->session);
        const char *raw_str = vielotus_get_raw_text(vl_engine->session);
        if (composing && composing[0] != '\0') {
            ibus_vielotus_append_trace_log(
                "PREEDIT",
                raw_str ? raw_str : "",
                composing,
                "(đang gõ)",
                (raw_str && g_strcmp0(raw_str, composing) != 0) ? "Đang biến đổi dấu VN" : "Đang thu thập phím"
            );
            IBusText *text = ibus_text_new_from_string(composing);
            guint char_len = ibus_text_get_length(text);
            ibus_text_append_attribute(text, IBUS_ATTR_TYPE_UNDERLINE, IBUS_ATTR_UNDERLINE_SINGLE, 0, (gint)char_len);
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

static void ibus_vielotus_engine_init(IBusVieLotusEngine *vl_engine) {
    vl_engine->session = vielotus_create_session();
    vl_engine->is_vni = FALSE;
    vl_engine->smart_bilingual = TRUE;
    vl_engine->sen_flex = TRUE;
    vl_engine->modern_orthography = TRUE;
    vl_engine->quick_telex = FALSE;
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
    IBUS_ENGINE_CLASS(ibus_vielotus_engine_parent_class)->enable(engine);
}

static void ibus_vielotus_engine_disable(IBusEngine *engine) {
    IBusVieLotusEngine *vl_engine = (IBusVieLotusEngine *)engine;
    if (vielotus_is_composing(vl_engine->session)) {
        ibus_vielotus_commit_composing(vl_engine, NULL);
    } else {
        ibus_vielotus_engine_reset_internal(vl_engine);
    }
    IBUS_ENGINE_CLASS(ibus_vielotus_engine_parent_class)->disable(engine);
}

static void ibus_vielotus_engine_focus_in(IBusEngine *engine) {
    IBusVieLotusEngine *vl_engine = (IBusVieLotusEngine *)engine;
    ibus_vielotus_load_user_config(vl_engine);
    ibus_vielotus_build_prop_list(vl_engine);
    ibus_engine_register_properties(engine, vl_engine->prop_list);
    IBUS_ENGINE_CLASS(ibus_vielotus_engine_parent_class)->focus_in(engine);
}

static void ibus_vielotus_engine_focus_out(IBusEngine *engine) {
    IBusVieLotusEngine *vl_engine = (IBusVieLotusEngine *)engine;
    if (vielotus_is_composing(vl_engine->session)) {
        ibus_vielotus_commit_composing(vl_engine, NULL);
    } else {
        ibus_vielotus_engine_reset_internal(vl_engine);
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

    // Handle BackSpace
    if (keyval == IBUS_KEY_BackSpace) {
        if (vielotus_is_composing(vl_engine->session)) {
            int32_t action = vielotus_feed_backspace(vl_engine->session);
            if (action == VIELOTUS_ACTION_RESET || !vielotus_is_composing(vl_engine->session)) {
                ibus_vielotus_engine_reset_internal(vl_engine);
            } else {
                ibus_vielotus_update_preedit(vl_engine);
            }
            return TRUE;
        }
        vielotus_feed_backspace(vl_engine->session);
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

        int32_t action = vielotus_feed_char(vl_engine->session, keyval);
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
