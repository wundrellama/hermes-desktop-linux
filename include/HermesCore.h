/*
 * HermesCore.h — C ABI consumed by the Linux C++/Qt6/Kirigami UI.
 *
 * Implementation: libHermesCore.a (Swift, built via `swift build -c release`
 * from Sources/HermesDesktop/, Linux-only). Symbols are declared in
 * Sources/HermesDesktop/Platform/Linux/Exports.swift via @_cdecl.
 *
 * Memory ownership rules:
 *
 *   • char * results from any hermes_* function are heap-allocated by
 *     Swift and MUST be freed by the caller via hermes_free_string. Never
 *     free() them directly — the allocator stays under Swift's control.
 *
 *   • Handles (hermes_handle_t) are opaque indices, never dereferenced on
 *     the C/C++ side. Each *_init returns a fresh handle; each *_release
 *     drops the corresponding Swift reference. Handle 0 is reserved as
 *     "invalid"; *_release(0) is a no-op.
 *
 *   • const char * arguments are NOT taken ownership of — Swift copies
 *     what it needs synchronously and the caller may free the buffer
 *     immediately on return.
 *
 *   • All functions are thread-safe unless documented otherwise. The
 *     C++ side may call them from any thread. Internal lock hold-times
 *     are O(1).
 *
 * Error reporting:
 *
 *   • Functions returning a handle return 0 on failure.
 *   • Functions returning char * return NULL on failure.
 *   • Detailed errors (where available) come back via separate
 *     hermes_*_last_error functions returning a JSON payload.
 *
 * Versioning:
 *
 *   • The C ABI is stable within a major version. New functions may be
 *     appended; existing signatures must not change in patch releases.
 *   • hermes_core_version() returns the implementation's build version.
 */

#ifndef HERMES_CORE_H
#define HERMES_CORE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef int64_t hermes_handle_t;

/* ===== Lifecycle / utility ===== */

/*
 * Returns the HermesCore library build version (e.g. "0.1.0-linux-port").
 * Caller frees with hermes_free_string.
 */
char *hermes_core_version(void);

/*
 * Frees any string previously returned by a hermes_* function.
 * Safe to call with NULL (no-op).
 */
void hermes_free_string(char *ptr);

/* ===== AppPaths ===== */

/*
 * Initializes an AppPaths instance, optionally overriding the XDG paths
 * that would otherwise be read from the environment.
 *
 * Passing NULL for either parameter means "read from $XDG_CONFIG_HOME /
 * $XDG_RUNTIME_DIR" (or their documented fallbacks). The C++ UI normally
 * passes NULL/NULL; the override path is for sandboxed-launch and tests.
 *
 * Returns: a fresh non-zero handle, or 0 on failure.
 */
hermes_handle_t hermes_apppaths_init(
    const char *xdg_config,
    const char *xdg_runtime
);

/*
 * Returns the application-support directory (e.g.
 * "$XDG_CONFIG_HOME/HermesDesktop"). Caller frees with hermes_free_string.
 * Returns NULL on invalid handle.
 */
char *hermes_apppaths_application_support_dir(hermes_handle_t handle);

/*
 * Returns the SSH control-socket directory (e.g.
 * "$XDG_RUNTIME_DIR/hermes-desktop/cs"). Caller frees with
 * hermes_free_string. Returns NULL on invalid handle.
 */
char *hermes_apppaths_control_socket_dir(hermes_handle_t handle);

/*
 * Releases the AppPaths handle. No-op on 0 or unknown handles.
 */
void hermes_apppaths_release(hermes_handle_t handle);

/* ===== Connections ===== */

/*
 * Connection storage operates against the AppPaths handle — there is no
 * separate "connection store" handle. ConnectionPersistence on the Swift
 * side is stateless file IO, so each call builds a fresh instance.
 *
 * JSON wire format for a single ConnectionProfile:
 *
 *   {
 *     "id":                   "8E3A2F4C-...-...-...-...",  // UUID
 *     "label":                "prod-east-1",
 *     "sshAlias":             "prod-east",                  // ~/.ssh/config alias
 *     "sshHost":              "10.0.0.4",
 *     "sshPort":              22,                            // or null
 *     "sshUser":              "deploy",
 *     "hermesProfile":        "researcher",                  // or null
 *     "customHermesHomePath": "/srv/hermes",                 // or null
 *     "createdAt":            "2026-05-20T19:00:00Z",        // ISO 8601
 *     "updatedAt":            "2026-05-20T19:00:00Z",
 *     "lastConnectedAt":      null                            // or ISO 8601
 *   }
 *
 * Status codes returned by the integer-returning functions below:
 *
 *    0   success
 *   -1   invalid AppPaths handle
 *   -2   JSON parse failure or malformed argument (bad UUID etc.)
 *   -3   I/O failure (disk full, permission denied, etc.)
 *
 * A future revision will surface structured errors via
 * `hermes_core_last_error(handle)` returning a JSON payload; for now,
 * the integer code is the only error channel.
 */

/*
 * Returns ALL saved connections as a JSON array. Returns an empty
 * "[]" string when the file doesn't exist. Returns NULL only on an
 * invalid handle or unexpected I/O failure.
 * Caller frees with hermes_free_string.
 */
char *hermes_connection_list(hermes_handle_t handle);

/*
 * Returns the connection with the given UUID string, or NULL if no
 * such id exists / load failed / the UUID couldn't be parsed.
 * Caller frees with hermes_free_string.
 */
char *hermes_connection_load(hermes_handle_t handle, const char *id);

/*
 * Upserts a connection. profile_json must encode a single
 * ConnectionProfile (NOT an array). If an existing profile with the
 * same id is on disk, it is replaced; otherwise the profile is
 * appended. The Swift side does not sort, normalize, or validate
 * fields beyond JSON parsing — that's the UI's job.
 *
 * Returns 0 / -1 / -2 / -3 per the status codes above.
 */
int32_t hermes_connection_save(
    hermes_handle_t handle,
    const char *profile_json
);

/*
 * Removes the connection with the given UUID. Idempotent: returns 0
 * whether or not such an id was on disk. Returns -1 / -2 / -3 on
 * handle / argument / I/O failure.
 */
int32_t hermes_connection_delete(
    hermes_handle_t handle,
    const char *id
);

/* ===== Preferences ===== */

/*
 * AppPreferences is a single document, not a collection — there is no
 * list/load/save/delete CRUD, just load/save of the whole struct.
 *
 * JSON wire format (every field is optional; missing means "use the
 * UX default"):
 *
 *   {
 *     "lastConnectionID":              "<uuid>"  | null,
 *     "terminalTheme":                 { ... }   | null,  // see TerminalThemePreference
 *     "automaticallyChecksForUpdates": true      | null,
 *     "lastAutomaticUpdateCheckAt":    "<iso8601>" | null,
 *     "workspaceFileBookmarks":        [ ... ]   | null,  // see WorkspaceFileBookmark
 *     "pinnedSessions":                [ ... ]   | null,  // see PinnedSession
 *     "workflows":                     [ ... ]   | null   // see WorkflowPreset
 *   }
 *
 * Nested type shapes (Codable structs in Swift) — consult their source
 * files when wiring the C++ UI to specific fields:
 *
 *   TerminalThemePreference   Sources/HermesDesktop/Models/TerminalTheme.swift
 *   WorkspaceFileBookmark     Sources/HermesDesktop/Models/WorkspaceFileModels.swift
 *   PinnedSession             Sources/HermesDesktop/Models/SessionModels.swift
 *   WorkflowPreset            Sources/HermesDesktop/Models/WorkflowModels.swift
 *
 * JSONEncoder omits keys with null values, so the wire form for a
 * fresh AppPreferences() is literally "{}".
 */

/*
 * Returns the persisted AppPreferences as JSON. Returns "{}" (an empty
 * JSON object) when the file doesn't exist — callers treat that as
 * "first run, use defaults". Returns NULL only on invalid handle or
 * unexpected I/O failure.
 * Caller frees with hermes_free_string.
 */
char *hermes_preferences_load(hermes_handle_t handle);

/*
 * Persists the entire AppPreferences document. The payload must encode
 * the full struct — partial-update semantics (load + mutate + save) are
 * the C++ UI's responsibility.
 *
 * Returns 0 / -1 / -2 / -3 per the status codes used by the connection
 * surface.
 */
int32_t hermes_preferences_save(
    hermes_handle_t handle,
    const char *preferences_json
);

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /* HERMES_CORE_H */
