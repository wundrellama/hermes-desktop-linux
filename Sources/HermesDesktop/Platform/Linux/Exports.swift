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
