/*
 * tests/ffi/smoke.c — minimal C consumer of the HermesCore C ABI.
 *
 * Builds against the static library produced by `swift build` and
 * exercises the lifecycle / utility + AppPaths exports. Intended as the
 * end-to-end proof that the C ABI works from a non-Swift caller, prior
 * to the C++/Qt UI being scaffolded.
 *
 * Build (from repo root, inside the hermes-build Distrobox):
 *
 *   tests/ffi/build-smoke.sh
 *
 * Or by hand:
 *
 *   $SWIFT_HOME/usr/bin/swiftc \
 *     -o tests/ffi/smoke \
 *     tests/ffi/smoke.c \
 *     -I include \
 *     .build/x86_64-unknown-linux-gnu/debug/libHermesCore.a \
 *     -lpthread -ldl -lm
 */

#include "HermesCore.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int failures = 0;

static void check_nonnull(const char *label, const void *ptr) {
    if (ptr == NULL) {
        fprintf(stderr, "FAIL: %s returned NULL\n", label);
        failures++;
    }
}

static void check_handle(const char *label, hermes_handle_t handle) {
    if (handle == 0) {
        fprintf(stderr, "FAIL: %s returned handle 0\n", label);
        failures++;
    }
}

int main(void) {
    /* hermes_core_version */
    char *version = hermes_core_version();
    check_nonnull("hermes_core_version", version);
    printf("version = %s\n", version ? version : "(null)");
    hermes_free_string(version);

    /* hermes_apppaths_init with NULL/NULL → env defaults */
    hermes_handle_t paths = hermes_apppaths_init(NULL, NULL);
    check_handle("hermes_apppaths_init(NULL, NULL)", paths);

    /* application_support_dir */
    char *app_support = hermes_apppaths_application_support_dir(paths);
    check_nonnull("hermes_apppaths_application_support_dir", app_support);
    printf("application_support_dir = %s\n", app_support ? app_support : "(null)");
    hermes_free_string(app_support);

    /* control_socket_dir */
    char *socket_dir = hermes_apppaths_control_socket_dir(paths);
    check_nonnull("hermes_apppaths_control_socket_dir", socket_dir);
    printf("control_socket_dir = %s\n", socket_dir ? socket_dir : "(null)");
    hermes_free_string(socket_dir);

    /* release */
    hermes_apppaths_release(paths);

    /* lookup-after-release returns NULL */
    char *post_release = hermes_apppaths_application_support_dir(paths);
    if (post_release != NULL) {
        fprintf(stderr, "FAIL: lookup after release returned %s\n", post_release);
        hermes_free_string(post_release);
        failures++;
    }

    /* invalid handle (never registered) */
    char *bad = hermes_apppaths_application_support_dir(999999);
    if (bad != NULL) {
        fprintf(stderr, "FAIL: lookup of bogus handle returned %s\n", bad);
        hermes_free_string(bad);
        failures++;
    }

    /* free(NULL) is a no-op */
    hermes_free_string(NULL);

    /* release(0) is a no-op */
    hermes_apppaths_release(0);

    /* explicit XDG override path */
    hermes_handle_t override = hermes_apppaths_init("/tmp/hermes-test-config",
                                                   "/tmp/hermes-test-runtime");
    check_handle("hermes_apppaths_init(/tmp/...)", override);
    char *override_support = hermes_apppaths_application_support_dir(override);
    if (override_support == NULL || strstr(override_support, "/tmp/hermes-test-config/HermesDesktop") == NULL) {
        fprintf(stderr, "FAIL: override path mismatch: %s\n",
                override_support ? override_support : "(null)");
        failures++;
    } else {
        printf("override_support = %s\n", override_support);
    }
    hermes_free_string(override_support);
    hermes_apppaths_release(override);

    if (failures == 0) {
        printf("OK — all smoke checks passed\n");
        return 0;
    } else {
        fprintf(stderr, "FAIL — %d smoke check(s) failed\n", failures);
        return 1;
    }
}
