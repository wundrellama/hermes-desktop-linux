#if os(Linux)

import Foundation
import Glibc

// FFI exports consumed by the C++/Qt6/Kirigami UI via the C ABI declared in
// `include/HermesCore.h`. Lives in the HermesDesktop target rather than a
// separate HermesCoreFFI target so internal types like AppPaths and
// ConnectionProfile stay reachable without scattering `public` annotations
// across upstream-owned files.
//
// Everything in this file is Linux-only.

// MARK: - Lifecycle / utility

/// Returns the HermesCore library build version as a fresh heap string.
/// Caller must free via `hermes_free_string`.
@_cdecl("hermes_core_version")
public func hermes_core_version() -> UnsafeMutablePointer<CChar>? {
    // Hard-coded until we wire up Bundle / build-version injection.
    // Future: pass a build-time `-D HERMES_CORE_VERSION=...` flag.
    return JsonBridge.emitString("0.1.0-linux-port")
}

/// Frees any string previously returned by a `hermes_*` function.
/// No-op on a NULL pointer. Safe to call multiple times only if the C
/// caller doesn't re-use the pointer after the first free.
@_cdecl("hermes_free_string")
public func hermes_free_string(_ ptr: UnsafeMutablePointer<CChar>?) {
    guard let ptr else { return }
    free(ptr)
}

// MARK: - AppPaths

/// Initializes an `AppPaths` instance and returns an opaque handle.
///
/// Both `xdgConfig` and `xdgRuntime` are optional overrides; pass NULL to
/// let `AppPaths` read from the process environment (the typical case).
/// When non-NULL, the strings are interpreted as absolute paths.
///
/// Returns `0` on failure.
@_cdecl("hermes_apppaths_init")
public func hermes_apppaths_init(
    _ xdgConfig: UnsafePointer<CChar>?,
    _ xdgRuntime: UnsafePointer<CChar>?
) -> Int64 {
    let paths: AppPaths
    if xdgConfig != nil || xdgRuntime != nil {
        // Explicit overrides path. Builds the URLs from the caller's strings
        // and constructs an AppPaths around them. This is the testing /
        // sandboxed-launch path; normal C++ UI will pass NULL/NULL.
        let support = xdgConfig.flatMap {
            URL(fileURLWithPath: String(cString: $0), isDirectory: true)
                .appendingPathComponent("HermesDesktop", isDirectory: true)
        } ?? defaultApplicationSupportURL()
        let socketDir = xdgRuntime.flatMap {
            URL(fileURLWithPath: String(cString: $0), isDirectory: true)
                .appendingPathComponent("hermes-desktop", isDirectory: true)
                .appendingPathComponent("cs", isDirectory: true)
        } ?? defaultControlSocketDirectoryURL()
        paths = AppPaths(
            applicationSupportURL: support,
            controlSocketDirectoryURL: socketDir
        )
    } else {
        paths = AppPaths()
    }
    return HandleRegistry.shared.register(paths)
}

/// Returns the application-support directory path (e.g. `$XDG_CONFIG_HOME/HermesDesktop`).
/// Caller frees via `hermes_free_string`. Returns NULL on invalid handle.
@_cdecl("hermes_apppaths_application_support_dir")
public func hermes_apppaths_application_support_dir(
    _ handle: Int64
) -> UnsafeMutablePointer<CChar>? {
    guard let paths = HandleRegistry.shared.lookup(handle, as: AppPaths.self) else {
        return nil
    }
    return JsonBridge.emitString(paths.applicationSupportURL.path)
}

/// Returns the SSH control-socket directory path (e.g. `$XDG_RUNTIME_DIR/hermes-desktop/cs`).
/// Caller frees via `hermes_free_string`. Returns NULL on invalid handle.
@_cdecl("hermes_apppaths_control_socket_dir")
public func hermes_apppaths_control_socket_dir(
    _ handle: Int64
) -> UnsafeMutablePointer<CChar>? {
    guard let paths = HandleRegistry.shared.lookup(handle, as: AppPaths.self) else {
        return nil
    }
    return JsonBridge.emitString(paths.controlSocketDirectoryURL.path)
}

/// Releases the AppPaths handle. No-op on `0` or unknown handles.
@_cdecl("hermes_apppaths_release")
public func hermes_apppaths_release(_ handle: Int64) {
    HandleRegistry.shared.release(handle)
}

// MARK: - Connection storage
//
// The handle here is the AppPaths handle returned by hermes_apppaths_init.
// ConnectionPersistence is a stateless file-IO struct, so each call builds
// a fresh instance — no caching, no shared mutable state.
//
// JSON wire format mirrors ConnectionProfile's Codable surface:
//   { "id": "<uuid>", "label": ..., "sshAlias": ..., "sshHost": ...,
//     "sshPort": <int|null>, "sshUser": ..., "hermesProfile": <string|null>,
//     "customHermesHomePath": <string|null>, "createdAt": "<iso8601>",
//     "updatedAt": "<iso8601>", "lastConnectedAt": "<iso8601|null>" }
//
// Status codes:
//    0   success
//   -1   invalid AppPaths handle
//   -2   JSON parse / invalid argument (bad UUID, malformed payload)
//   -3   I/O failure (disk full, permissions, etc.) — future revision
//        will surface a structured error via a separate getter.

/// Returns the saved connections as a JSON array.
/// On absence of the file, returns an empty array (not NULL). NULL is
/// reserved for "invalid handle" or unexpected I/O failure.
/// Caller frees via `hermes_free_string`.
@_cdecl("hermes_connection_list")
public func hermes_connection_list(_ pathsHandle: Int64) -> UnsafeMutablePointer<CChar>? {
    guard let paths = HandleRegistry.shared.lookup(pathsHandle, as: AppPaths.self) else {
        return nil
    }
    let persistence = ConnectionPersistence(paths: paths)
    do {
        let connections = try persistence.loadConnections()
        return JsonBridge.emit(connections)
    } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
        return JsonBridge.emit([ConnectionProfile]())
    } catch {
        return nil
    }
}

/// Returns the single connection with `id`, or NULL if not found / not loadable.
/// Caller frees via `hermes_free_string`.
@_cdecl("hermes_connection_load")
public func hermes_connection_load(
    _ pathsHandle: Int64,
    _ idCString: UnsafePointer<CChar>?
) -> UnsafeMutablePointer<CChar>? {
    guard let paths = HandleRegistry.shared.lookup(pathsHandle, as: AppPaths.self) else {
        return nil
    }
    guard let idCString,
          let id = UUID(uuidString: String(cString: idCString)) else {
        return nil
    }
    let persistence = ConnectionPersistence(paths: paths)
    do {
        let all = try persistence.loadConnections()
        guard let match = all.first(where: { $0.id == id }) else { return nil }
        return JsonBridge.emit(match)
    } catch {
        return nil
    }
}

/// Upserts a connection. The payload is a single ConnectionProfile JSON
/// (NOT an array). An existing profile with the same `id` is replaced;
/// otherwise the profile is appended. The Swift side does not sort or
/// normalize — that's the UI's responsibility.
@_cdecl("hermes_connection_save")
public func hermes_connection_save(
    _ pathsHandle: Int64,
    _ profileJson: UnsafePointer<CChar>?
) -> Int32 {
    guard let paths = HandleRegistry.shared.lookup(pathsHandle, as: AppPaths.self) else {
        return -1
    }
    guard let incoming: ConnectionProfile = JsonBridge.consume(profileJson) else {
        return -2
    }
    let persistence = ConnectionPersistence(paths: paths)
    var current: [ConnectionProfile]
    do {
        current = try persistence.loadConnections()
    } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
        current = []
    } catch {
        return -3
    }
    if let index = current.firstIndex(where: { $0.id == incoming.id }) {
        current[index] = incoming
    } else {
        current.append(incoming)
    }
    do {
        try persistence.saveConnections(current)
        return 0
    } catch {
        return -3
    }
}

/// Removes the connection with `id`. Returns 0 even if no such id exists
/// (idempotent — matches the macOS ConnectionStore.delete semantics).
@_cdecl("hermes_connection_delete")
public func hermes_connection_delete(
    _ pathsHandle: Int64,
    _ idCString: UnsafePointer<CChar>?
) -> Int32 {
    guard let paths = HandleRegistry.shared.lookup(pathsHandle, as: AppPaths.self) else {
        return -1
    }
    guard let idCString,
          let id = UUID(uuidString: String(cString: idCString)) else {
        return -2
    }
    let persistence = ConnectionPersistence(paths: paths)
    var current: [ConnectionProfile]
    do {
        current = try persistence.loadConnections()
    } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
        return 0  // nothing to delete
    } catch {
        return -3
    }
    current.removeAll { $0.id == id }
    do {
        try persistence.saveConnections(current)
        return 0
    } catch {
        return -3
    }
}

// MARK: - Preferences
//
// AppPreferences is a single document (not a collection), so the surface
// is just load/save. Schema includes lastConnectionID, terminalTheme,
// automaticallyChecksForUpdates, lastAutomaticUpdateCheckAt,
// workspaceFileBookmarks, pinnedSessions, workflows — every field is
// optional so older files (missing newer keys) and newer files (with
// keys we don't recognize) both decode cleanly.

/// Returns the persisted AppPreferences as JSON.
/// When the file doesn't exist (first run), returns "{}" rather than NULL —
/// callers treat that as "use defaults everywhere". NULL is reserved for
/// invalid handle or unexpected I/O failure.
/// Caller frees with hermes_free_string.
@_cdecl("hermes_preferences_load")
public func hermes_preferences_load(_ pathsHandle: Int64) -> UnsafeMutablePointer<CChar>? {
    guard let paths = HandleRegistry.shared.lookup(pathsHandle, as: AppPaths.self) else {
        return nil
    }
    let persistence = ConnectionPersistence(paths: paths)
    do {
        let preferences = try persistence.loadPreferences()
        return JsonBridge.emit(preferences)
    } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
        return JsonBridge.emit(AppPreferences())
    } catch {
        return nil
    }
}

/// Persists the entire AppPreferences document. The payload must encode
/// the full AppPreferences struct; partial-update semantics are the C++
/// UI's responsibility (load + mutate + save).
///
/// Status codes match the connection surface:
///    0  success
///   -1  invalid handle
///   -2  JSON parse failure
///   -3  I/O failure
@_cdecl("hermes_preferences_save")
public func hermes_preferences_save(
    _ pathsHandle: Int64,
    _ preferencesJson: UnsafePointer<CChar>?
) -> Int32 {
    guard let paths = HandleRegistry.shared.lookup(pathsHandle, as: AppPaths.self) else {
        return -1
    }
    guard let preferences: AppPreferences = JsonBridge.consume(preferencesJson) else {
        return -2
    }
    let persistence = ConnectionPersistence(paths: paths)
    do {
        try persistence.savePreferences(preferences)
        return 0
    } catch {
        return -3
    }
}

// MARK: - SSH execution (async)
//
// The first async-callback FFI surface. C++ calls hermes_ssh_execute,
// gets a non-zero request_id back immediately, and later receives the
// SSHResultEnvelope JSON via the supplied callback. The callback may
// fire on any thread (specifically: a Swift cooperative-pool worker);
// the C++ side is responsible for marshaling onto Qt's main thread
// via QMetaObject::invokeMethod(qApp, ..., Qt::QueuedConnection).
//
// Memory ownership of the JSON payload passed to the callback follows
// the same rule as every other hermes_* char* return: the C++ side
// MUST free it via hermes_free_string. The Swift side allocates with
// strdup once and does not retain a reference after the callback
// returns.
//
// `user` is opaque to the Swift side — passed through verbatim. The
// C++ side must keep whatever it points at alive until the callback
// fires.
//
// Cancellation is NOT implemented in v1. A future revision will add
// hermes_request_cancel plus Process.terminate() plumbing inside
// SSHTransport so the underlying /usr/bin/ssh actually dies. Today
// you cannot abort an in-flight request.

/// Submit an SSH command. Returns the request_id (non-zero) on success,
/// or 0 on a synchronous failure (invalid handle, malformed
/// connection_json, or missing remote_command).
///
/// `connection_json` must encode a single ConnectionProfile.
/// `remote_command` is the command line to execute on the remote host.
/// `allocate_tty` is a boolean (0 / non-zero) controlling SSH's `-tt`.
/// `stdin_data` is optional UTF-8 stdin (NULL for none).
///
/// The callback type is inlined here (rather than a separate typealias)
/// because @_cdecl public functions cannot reference internal-typealias
/// parameter types under Swift 6 strict visibility checking.
@_cdecl("hermes_ssh_execute")
public func hermes_ssh_execute(
    _ pathsHandle: Int64,
    _ connectionJson: UnsafePointer<CChar>?,
    _ remoteCommand: UnsafePointer<CChar>?,
    _ allocateTTY: Int32,
    _ stdinData: UnsafePointer<CChar>?,
    _ cb: (@convention(c) (Int64, UnsafePointer<CChar>?, UnsafeMutableRawPointer?) -> Void)?,
    _ user: UnsafeMutableRawPointer?
) -> Int64 {
    guard let paths = HandleRegistry.shared.lookup(pathsHandle, as: AppPaths.self) else {
        return 0
    }
    guard let profile: ConnectionProfile = JsonBridge.consume(connectionJson) else {
        return 0
    }
    guard let remoteCommand else {
        return 0
    }
    guard let cb else {
        // No callback = no way to deliver the result; bail synchronously.
        return 0
    }
    let command = String(cString: remoteCommand)
    let stdinBytes: Data? = stdinData.map { Data(String(cString: $0).utf8) }
    let tty = allocateTTY != 0
    let requestId = RequestID.allocate()

    // UnsafeMutableRawPointer is @unchecked Sendable; @convention(c) function
    // pointers are POD. Both cross the Task boundary cleanly.
    let userBox = UncheckedSendableBox(user)

    Task.detached { @Sendable [paths, profile, command, stdinBytes, tty, requestId, userBox] in
        let transport = SSHTransport(paths: paths)
        let envelope: SSHResultEnvelope
        do {
            let result = try await transport.execute(
                on: profile,
                remoteCommand: command,
                standardInput: stdinBytes,
                allocateTTY: tty
            )
            envelope = .success(
                SSHCommandResultPayload(
                    stdout: result.stdout,
                    stderr: result.stderr,
                    exitCode: result.exitCode
                )
            )
        } catch {
            envelope = .from(error: error)
        }

        // Build the JSON payload. Ownership transfers to the C side on
        // callback invocation; C must free with hermes_free_string.
        let payload = JsonBridge.emit(envelope)
        cb(requestId, payload, userBox.value)
    }

    return requestId
}

/// Tiny wrapper to silence the Swift 6 Sendable checker for the
/// raw pointer crossing the Task boundary. The pointer is opaque on
/// the Swift side and only handed back to C; treating it as
/// @unchecked Sendable is honest.
private struct UncheckedSendableBox: @unchecked Sendable {
    let value: UnsafeMutableRawPointer?
    init(_ value: UnsafeMutableRawPointer?) { self.value = value }
}

// MARK: - Private helpers

private func defaultApplicationSupportURL() -> URL {
    // Mirrors AppPaths.init()'s default path resolution on Linux.
    let env = ProcessInfo.processInfo.environment
    let base: URL
    if let xdg = env["XDG_CONFIG_HOME"], !xdg.isEmpty {
        base = URL(fileURLWithPath: xdg, isDirectory: true)
    } else {
        let home = env["HOME"] ?? NSHomeDirectory()
        base = URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent(".config", isDirectory: true)
    }
    return base.appendingPathComponent("HermesDesktop", isDirectory: true)
}

private func defaultControlSocketDirectoryURL() -> URL {
    let env = ProcessInfo.processInfo.environment
    let base: URL
    if let xdg = env["XDG_RUNTIME_DIR"], !xdg.isEmpty {
        base = URL(fileURLWithPath: xdg, isDirectory: true)
    } else {
        base = URL(fileURLWithPath: "/run/user/\(getuid())", isDirectory: true)
    }
    return base
        .appendingPathComponent("hermes-desktop", isDirectory: true)
        .appendingPathComponent("cs", isDirectory: true)
}

#endif // os(Linux)
