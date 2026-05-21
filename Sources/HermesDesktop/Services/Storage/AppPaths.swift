import Crypto
import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

struct AppPaths {
    let fileManager: FileManager
    let applicationSupportURL: URL
    let connectionsURL: URL
    let preferencesURL: URL
    let controlSocketDirectoryURL: URL

    private static let privateDirectoryPermissions = NSNumber(value: Int16(0o700))

    init(fileManager: FileManager = .default) {
        let baseSupport: URL
        let socketDir: URL

        #if os(Linux)
        baseSupport = Self.linuxApplicationSupportBaseURL()
        socketDir = Self.linuxControlSocketDirectoryURL()
        #else
        baseSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        socketDir = URL(
            fileURLWithPath: "/tmp/hd-\(getuid())",
            isDirectory: true
        )
        #endif

        self.init(
            fileManager: fileManager,
            applicationSupportURL: baseSupport.appendingPathComponent("HermesDesktop", isDirectory: true),
            controlSocketDirectoryURL: socketDir
        )
    }

    init(
        fileManager: FileManager = .default,
        applicationSupportURL: URL,
        controlSocketDirectoryURL: URL
    ) {
        self.fileManager = fileManager
        self.applicationSupportURL = applicationSupportURL
        self.connectionsURL = applicationSupportURL.appendingPathComponent("connections.json")
        self.preferencesURL = applicationSupportURL.appendingPathComponent("preferences.json")
        self.controlSocketDirectoryURL = controlSocketDirectoryURL

        ensureApplicationSupportDirectory()
        ensureControlSocketDirectory()
    }

    func ensureApplicationSupportDirectory() {
        createPrivateDirectoryIfNeeded(at: applicationSupportURL)
    }

    func ensureControlSocketDirectory() {
        createPrivateDirectoryIfNeeded(at: controlSocketDirectoryURL)
    }

    func controlPath(for connection: ConnectionProfile) -> String {
        ensureControlSocketDirectory()

        return controlSocketDirectoryURL
            .appendingPathComponent(controlSocketIdentifier(for: connection))
            .path
    }

    private func createPrivateDirectoryIfNeeded(at url: URL) {
        let attributes: [FileAttributeKey: Any] = [
            .posixPermissions: Self.privateDirectoryPermissions
        ]

        if !fileManager.fileExists(atPath: url.path) {
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: attributes)
        } else {
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
               !isDirectory.boolValue {
                return
            }
        }

        try? fileManager.setAttributes(attributes, ofItemAtPath: url.path)
    }

    private func controlSocketIdentifier(for connection: ConnectionProfile) -> String {
        // Scope SSH control sockets to the workspace so profiles on the same host stay isolated.
        let digest = SHA256.hash(data: Data(connection.workspaceScopeFingerprint.utf8))
        let hexDigest = digest.map { String(format: "%02x", $0) }.joined()
        return String(hexDigest.prefix(24))
    }

    #if os(Linux)
    // Resolves to $XDG_CONFIG_HOME (canonicalized) or $HOME/.config. Foundation's
    // applicationSupportDirectory on swift-corelibs-foundation also returns ~/.config,
    // but we lookup XDG explicitly so the user can override and so we can validate.
    private static func linuxApplicationSupportBaseURL() -> URL {
        let env = ProcessInfo.processInfo.environment
        if let xdg = env["XDG_CONFIG_HOME"], !xdg.isEmpty {
            return URL(fileURLWithPath: xdg, isDirectory: true)
        }
        let home = env["HOME"] ?? NSHomeDirectory()
        return URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent(".config", isDirectory: true)
    }

    // Resolves to $XDG_RUNTIME_DIR/hermes-desktop/cs (tmpfs, per-user, 0700) or
    // /run/user/<uid>/hermes-desktop/cs as a fallback. Unlike macOS we deliberately
    // do NOT fall back to /tmp — see the plan's threat T5 (world-readable socket leak).
    // TODO(linux-port): validate XDG_RUNTIME_DIR is on tmpfs and owned by getuid() with mode 0700.
    private static func linuxControlSocketDirectoryURL() -> URL {
        let env = ProcessInfo.processInfo.environment
        let runtimeBase: URL
        if let xdg = env["XDG_RUNTIME_DIR"], !xdg.isEmpty {
            runtimeBase = URL(fileURLWithPath: xdg, isDirectory: true)
        } else {
            runtimeBase = URL(fileURLWithPath: "/run/user/\(getuid())", isDirectory: true)
        }
        return runtimeBase
            .appendingPathComponent("hermes-desktop", isDirectory: true)
            .appendingPathComponent("cs", isDirectory: true)
    }
    #endif
}
