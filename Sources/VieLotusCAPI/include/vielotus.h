#ifndef VIELOTUS_H
#define VIELOTUS_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Opaque pointer to a typing session instance
typedef void* vielotus_session_t;

/// Input method layout type
typedef enum {
    VIELOTUS_INPUT_TELEX = 0,
    VIELOTUS_INPUT_VNI = 1
} vielotus_input_method_t;

/// Input grammar profile (0 = Classic Telex/VNI, 1 = SEN Flex free-order)
typedef enum {
    VIELOTUS_GRAMMAR_CLASSIC = 0,
    VIELOTUS_GRAMMAR_SEN_FLEX = 1
} vielotus_grammar_profile_t;

/// Result action returned after feeding a keystroke to the session
typedef enum {
    VIELOTUS_ACTION_PASSTHROUGH = 0, // Key not handled; let host application process it
    VIELOTUS_ACTION_CONSUMED    = 1, // Key consumed internally; update composing text
    VIELOTUS_ACTION_REPLACE     = 2, // Host should delete backspaces and insert text
    VIELOTUS_ACTION_COMMIT      = 3, // Word committed to host application
    VIELOTUS_ACTION_RESET       = 4  // Composition cancelled or cleared
} vielotus_action_t;

// ============================================================================
// Lifecycle Management
// ============================================================================

/// Creates a new typing session with default Telex settings.
vielotus_session_t vielotus_create_session(void);

/// Destroys a typing session and frees all allocated memory.
void vielotus_destroy_session(vielotus_session_t session);

/// Resets session composition state (clears active buffer).
void vielotus_reset_session(vielotus_session_t session);

// ============================================================================
// Configuration
// ============================================================================

/// Sets the input method (0 = Telex, 1 = VNI).
void vielotus_set_input_method(vielotus_session_t session, vielotus_input_method_t method);

/// Sets the grammar profile (0 = Classic, 1 = SEN Flex).
void vielotus_set_grammar_profile(vielotus_session_t session, int32_t profile);

/// Returns the active grammar profile (0 = Classic, 1 = SEN Flex).
int32_t vielotus_get_grammar_profile(vielotus_session_t session);

/// Enables or disables smart bilingual auto-restore.
void vielotus_set_smart_bilingual(vielotus_session_t session, bool enabled);

/// Enables or disables modern diacritic orthography (òa/òe vs oà/oè).
void vielotus_set_modern_orthography(vielotus_session_t session, bool enabled);

/// Enables or disables Quick Telex shorthand.
void vielotus_set_quick_telex(vielotus_session_t session, bool enabled);

// ============================================================================
// Keystroke Processing
// ============================================================================

/// Feeds a single UTF-8 codepoint into the session.
/// Returns the resulting action code (0..4).
int32_t vielotus_feed_char(vielotus_session_t session, uint32_t codepoint);

/// Feeds a backspace keystroke into the session.
/// Returns the resulting action code (0..4).
int32_t vielotus_feed_backspace(vielotus_session_t session);

/// Feeds a full key event with scan code, ASCII char, and modifier flags.
/// Returns the resulting action code (0..4).
int32_t vielotus_feed_key(
    vielotus_session_t session,
    uint32_t key_code,
    char char_code,
    uint32_t modifiers
);

/// Explicitly commits the current composing word (triggers Smart Bilingual and macro resolution).
/// Returns the resulting action code (0..4).
int32_t vielotus_commit_word(vielotus_session_t session);

/// Convenience function feeding character and extracting backspaces and replacement text directly.
int32_t vielotus_feed_char_ex(
    vielotus_session_t session,
    uint32_t codepoint,
    int32_t* out_backspaces,
    const char** out_text
);

/// Returns the action from the most recent feed call.
int32_t vielotus_get_last_action(vielotus_session_t session);

/// Returns the number of trailing UTF-16 code units to delete from the most recent feed call.
int32_t vielotus_get_last_backspaces(vielotus_session_t session);

/// Returns the replacement string to insert from the most recent feed call (valid until next feed).
const char* vielotus_get_last_text(vielotus_session_t session);

/// Returns true if the most recent commit action replaced the composed word (e.g. Smart Bilingual restore or Macro).
bool vielotus_get_last_is_override(vielotus_session_t session);

// ============================================================================
// Buffer & State Inspection
// ============================================================================

/// Checks whether the session is currently composing a syllable.
bool vielotus_is_composing(vielotus_session_t session);

/// Returns the current composing string (UTF-8 encoded, valid until next call).
const char* vielotus_get_composing_text(vielotus_session_t session);

/// Returns the raw typed ASCII string before Vietnamese transformation.
const char* vielotus_get_raw_text(vielotus_session_t session);

/// Appends preceding text into the session's context window for bilingual detection.
void vielotus_append_context(vielotus_session_t session, const char* context_word);

/// Synchronizes and arms the word immediately preceding the cursor when idle, enabling seamless post-commit tone edits and backspacing.
void vielotus_sync_armed_word(vielotus_session_t session, const char* before_context_utf8);

// ============================================================================
// Version & Metadata
// ============================================================================

/// Returns the SemVer string of the VieLotus Core engine (e.g. "1.0.0").
const char* vielotus_get_version(void);

// ============================================================================
// EDU-TYPE Local Loopback Bridge (127.0.0.1:2811 — LOCK-IME-VIELOTUS-001)
// ============================================================================

/// Starts the local loopback HTTP bridge daemon on the specified port (default: 2811).
bool vielotus_start_loopback_bridge(uint16_t port);

/// Stops the local loopback HTTP bridge daemon.
void vielotus_stop_loopback_bridge(void);

/// Returns true if the local loopback HTTP bridge daemon is currently running.
bool vielotus_is_loopback_bridge_running(void);

/// Processes a raw HTTP request string through the bridge and returns the HTTP response string.
const char* vielotus_process_bridge_http(const char* raw_request);

#ifdef __cplusplus
}
#endif

#endif // VIELOTUS_H
