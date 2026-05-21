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
