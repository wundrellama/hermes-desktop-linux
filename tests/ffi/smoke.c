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
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

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

static void check_status(const char *label, int32_t status, int32_t expected) {
    if (status != expected) {
        fprintf(stderr, "FAIL: %s returned %d, expected %d\n",
                label, status, expected);
        failures++;
    }
}

static void check_substring(const char *label, const char *haystack, const char *needle) {
    if (haystack == NULL || strstr(haystack, needle) == NULL) {
        fprintf(stderr, "FAIL: %s: %s not found in %s\n",
                label, needle, haystack ? haystack : "(null)");
        failures++;
    }
}

static void rmrf(const char *path) {
    char cmd[1024];
    snprintf(cmd, sizeof(cmd), "rm -rf %s", path);
    int rc = system(cmd);
    (void)rc;  /* tolerate missing dir */
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

    /* =====================================================================
     * Connection CRUD round-trip against a fresh /tmp test directory.
     * ===================================================================== */
    printf("\n--- connection CRUD ---\n");

    rmrf("/tmp/hermes-smoke-config/HermesDesktop");
    hermes_handle_t cs = hermes_apppaths_init("/tmp/hermes-smoke-config", NULL);
    check_handle("hermes_apppaths_init(connections)", cs);

    /* 1. List on a fresh dir → empty array. */
    char *initial = hermes_connection_list(cs);
    check_nonnull("hermes_connection_list(empty)", initial);
    if (initial != NULL && strcmp(initial, "[]") != 0) {
        fprintf(stderr, "FAIL: expected '[]' on empty, got '%s'\n", initial);
        failures++;
    } else {
        printf("initial list = %s\n", initial ? initial : "(null)");
    }
    hermes_free_string(initial);

    /* 2. Save a profile. */
    const char *profile_a =
        "{"
        "\"id\":\"11111111-2222-3333-4444-555555555555\","
        "\"label\":\"prod-east\","
        "\"sshAlias\":\"prod-east\","
        "\"sshHost\":\"10.0.0.4\","
        "\"sshPort\":22,"
        "\"sshUser\":\"deploy\","
        "\"hermesProfile\":\"researcher\","
        "\"customHermesHomePath\":null,"
        "\"createdAt\":\"2026-05-20T19:00:00Z\","
        "\"updatedAt\":\"2026-05-20T19:00:00Z\","
        "\"lastConnectedAt\":null"
        "}";
    check_status("hermes_connection_save(A)",
                 hermes_connection_save(cs, profile_a), 0);

    /* 3. List → contains the new profile. */
    char *after_save = hermes_connection_list(cs);
    check_substring("after save: prod-east in list", after_save, "prod-east");
    check_substring("after save: deploy in list", after_save, "deploy");
    printf("after save = %s\n", after_save ? after_save : "(null)");
    hermes_free_string(after_save);

    /* 4. Load by id → returns the saved profile. */
    char *loaded = hermes_connection_load(cs, "11111111-2222-3333-4444-555555555555");
    check_substring("load: contains label", loaded, "prod-east");
    check_substring("load: contains host", loaded, "10.0.0.4");
    hermes_free_string(loaded);

    /* 5. Save a second profile. */
    const char *profile_b =
        "{"
        "\"id\":\"66666666-7777-8888-9999-aaaaaaaaaaaa\","
        "\"label\":\"staging\","
        "\"sshAlias\":\"staging\","
        "\"sshHost\":\"10.0.0.5\","
        "\"sshPort\":null,"
        "\"sshUser\":\"ops\","
        "\"hermesProfile\":null,"
        "\"customHermesHomePath\":null,"
        "\"createdAt\":\"2026-05-20T19:00:00Z\","
        "\"updatedAt\":\"2026-05-20T19:00:00Z\","
        "\"lastConnectedAt\":null"
        "}";
    check_status("hermes_connection_save(B)",
                 hermes_connection_save(cs, profile_b), 0);

    /* 6. Upsert by id (modify existing). */
    const char *profile_a_v2 =
        "{"
        "\"id\":\"11111111-2222-3333-4444-555555555555\","
        "\"label\":\"prod-east-v2\","
        "\"sshAlias\":\"prod-east\","
        "\"sshHost\":\"10.0.0.4\","
        "\"sshPort\":2222,"
        "\"sshUser\":\"deploy\","
        "\"hermesProfile\":\"researcher\","
        "\"customHermesHomePath\":null,"
        "\"createdAt\":\"2026-05-20T19:00:00Z\","
        "\"updatedAt\":\"2026-05-20T19:30:00Z\","
        "\"lastConnectedAt\":null"
        "}";
    check_status("hermes_connection_save(A v2 upsert)",
                 hermes_connection_save(cs, profile_a_v2), 0);

    char *loaded_v2 = hermes_connection_load(cs, "11111111-2222-3333-4444-555555555555");
    check_substring("upsert: new label survives", loaded_v2, "prod-east-v2");
    check_substring("upsert: new port survives", loaded_v2, "2222");
    hermes_free_string(loaded_v2);

    /* 7. Delete the first profile. */
    check_status("hermes_connection_delete(A)",
                 hermes_connection_delete(cs, "11111111-2222-3333-4444-555555555555"), 0);

    /* Delete is idempotent — deleting again still returns 0. */
    check_status("hermes_connection_delete(A idempotent)",
                 hermes_connection_delete(cs, "11111111-2222-3333-4444-555555555555"), 0);

    /* 8. Load deleted id → NULL. */
    char *gone = hermes_connection_load(cs, "11111111-2222-3333-4444-555555555555");
    if (gone != NULL) {
        fprintf(stderr, "FAIL: load of deleted id returned %s\n", gone);
        hermes_free_string(gone);
        failures++;
    }

    /* 9. List still has profile B. */
    char *after_delete = hermes_connection_list(cs);
    check_substring("after delete: staging still present", after_delete, "staging");
    if (after_delete && strstr(after_delete, "prod-east") != NULL) {
        fprintf(stderr, "FAIL: deleted profile still in list: %s\n", after_delete);
        failures++;
    }
    hermes_free_string(after_delete);

    /* 10. Error paths */
    check_status("save with malformed JSON",
                 hermes_connection_save(cs, "{not real json"), -2);
    check_status("delete with malformed UUID",
                 hermes_connection_delete(cs, "not-a-uuid"), -2);
    check_status("save against invalid handle",
                 hermes_connection_save(0, profile_a), -1);

    hermes_apppaths_release(cs);
    rmrf("/tmp/hermes-smoke-config/HermesDesktop");

    if (failures == 0) {
        printf("OK — all smoke checks passed\n");
        return 0;
    } else {
        fprintf(stderr, "FAIL — %d smoke check(s) failed\n", failures);
        return 1;
    }
}
