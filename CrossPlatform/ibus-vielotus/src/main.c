/*
 * VieLotusIM (Sen Việt) - Native IBus Engine
 * Pure Swift 6 Core Bridge via C-ABI (vielotus.h)
 */

#include <ibus.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "vielotus.h"

#define IBUS_TYPE_VIELOTUS_ENGINE (ibus_vielotus_engine_get_type())

typedef struct _IBusVieLotusEngine IBusVieLotusEngine;
typedef struct _IBusVieLotusEngineClass IBusVieLotusEngineClass;

struct _IBusVieLotusEngine {
    IBusEngine parent;
    vielotus_session_t session;
    gboolean is_vni;
};

struct _IBusVieLotusEngineClass {
    IBusEngineClass parent_class;
};

GType ibus_vielotus_engine_get_type(void);
G_DEFINE_TYPE(IBusVieLotusEngine, ibus_vielotus_engine, IBUS_TYPE_ENGINE)

static void ibus_vielotus_engine_reset_internal(IBusVieLotusEngine *vl_engine) {
    if (vl_engine->session) {
        vielotus_reset_session(vl_engine->session);
    }
    ibus_engine_hide_preedit_text((IBusEngine *)vl_engine);
}

static void ibus_vielotus_engine_init(IBusVieLotusEngine *vl_engine) {
    vl_engine->session = vielotus_create_session();
    vl_engine->is_vni = FALSE;
    vielotus_set_input_method(vl_engine->session, VIELOTUS_INPUT_TELEX);
    vielotus_set_grammar_profile(vl_engine->session, VIELOTUS_GRAMMAR_SEN_FLEX);
    vielotus_set_smart_bilingual(vl_engine->session, true);
    vielotus_set_modern_orthography(vl_engine->session, true);
}

static void ibus_vielotus_engine_finalize(GObject *object) {
    IBusVieLotusEngine *vl_engine = (IBusVieLotusEngine *)object;
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
    ibus_vielotus_engine_reset_internal(vl_engine);
}

static void ibus_vielotus_engine_disable(IBusEngine *engine) {
    IBusVieLotusEngine *vl_engine = (IBusVieLotusEngine *)engine;
    ibus_vielotus_engine_reset_internal(vl_engine);
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

    // Pass through hotkey modifiers (Control, Alt, Super/Win)
    if (state & (IBUS_CONTROL_MASK | IBUS_MOD1_MASK | IBUS_SUPER_MASK)) {
        if (vielotus_is_composing(vl_engine->session)) {
            vielotus_commit_word(vl_engine->session);
            ibus_vielotus_engine_reset_internal(vl_engine);
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
                const char *composing = vielotus_get_composing_text(vl_engine->session);
                IBusText *text = ibus_text_new_from_string(composing ? composing : "");
                ibus_engine_update_preedit_text_with_mode(
                    engine,
                    text,
                    ibus_text_get_length(text),
                    TRUE,
                    IBUS_ENGINE_PREEDIT_COMMIT
                );
            }
            return TRUE;
        }
        return FALSE;
    }

    // Handle printable ASCII characters
    if (keyval >= 32 && keyval < 127) {
        uint32_t codepoint = keyval;
        int32_t action = vielotus_feed_char(vl_engine->session, codepoint);

        if (action == VIELOTUS_ACTION_COMMIT) {
            // Word boundary reached (e.g. Space, punctuation)
            const char *committed = vielotus_get_last_text(vl_engine->session);
            if (committed && committed[0] != '\0') {
                IBusText *commit_text = ibus_text_new_from_string(committed);
                ibus_engine_commit_text(engine, commit_text);
            }
            // Commit trailing boundary
            char boundary_str[2] = { (char)codepoint, '\0' };
            IBusText *boundary_text = ibus_text_new_from_string(boundary_str);
            ibus_engine_commit_text(engine, boundary_text);

            ibus_vielotus_engine_reset_internal(vl_engine);
            return TRUE;
        } else if (action == VIELOTUS_ACTION_REPLACE || action == VIELOTUS_ACTION_CONSUMED || vielotus_is_composing(vl_engine->session)) {
            // Update preedit composition with underline
            const char *composing = vielotus_get_composing_text(vl_engine->session);
            if (composing && composing[0] != '\0') {
                IBusText *text = ibus_text_new_from_string(composing);
                ibus_text_append_attribute(text, IBUS_ATTR_TYPE_UNDERLINE, IBUS_ATTR_UNDERLINE_SINGLE, 0, -1);
                ibus_engine_update_preedit_text_with_mode(
                    engine,
                    text,
                    ibus_text_get_length(text),
                    TRUE,
                    IBUS_ENGINE_PREEDIT_COMMIT
                );
            } else {
                ibus_engine_hide_preedit_text(engine);
            }
            return TRUE;
        }
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
        IBusComponent *component = ibus_component_new_from_file("/usr/share/ibus/component/vielotus.xml");
        if (component) {
            ibus_bus_register_component(bus, component);
        }
    }

    ibus_main();
    return 0;
}
