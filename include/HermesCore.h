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

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /* HERMES_CORE_H */
