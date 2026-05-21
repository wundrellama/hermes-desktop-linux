import Foundation

/// Plain-old file IO for the two on-disk artifacts hermes-desktop owns:
/// `connections.json` (saved SSH hosts) and `preferences.json` (everything
/// else — UI prefs, terminal theme, workflow presets, pinned sessions,
/// workspace bookmarks).
///
/// Stateless. Every call hits the filesystem; nothing is cached in this
/// type. The macOS `ConnectionStore` observable wraps this and provides
/// the SwiftUI binding surface; the Linux FFI exports call this directly
/// so the C++/Qt UI can round-trip connections without a Swift-side
/// observable layer.
///
/// File mode is enforced to 0600 on every write (and best-effort on every
/// successful read) per the threat model's T5/T6 mitigations. All writes
/// go through `.atomic` so a crash mid-write can't leave a half-file.
///
/// On absence, `loadConnections` / `loadPreferences` throw
/// `CocoaError(.fileReadNoSuchFile)`. Callers should treat that as
/// "no saved state yet" rather than as a real error.
struct ConnectionPersistence {
    let paths: AppPaths

    // Computed (not a stored static) because Swift 6 strict concurrency rejects
    // mutable global `[FileAttributeKey: Any]` as non-Sendable. Allocating
    // a 1-key dictionary on each write is trivially cheap.
    private static var privateFileAttributes: [FileAttributeKey: Any] {
        [.posixPermissions: NSNumber(value: Int16(0o600))]
    }

    init(paths: AppPaths) {
        self.paths = paths
    }

    // MARK: - connections.json

    func loadConnections() throws -> [ConnectionProfile] {
        let data = try Data(contentsOf: paths.connectionsURL)
        let connections = try Self.makeDecoder().decode([ConnectionProfile].self, from: data)
        try? setPrivatePermissions(at: paths.connectionsURL)
        return connections
    }

    func saveConnections(_ connections: [ConnectionProfile]) throws {
        paths.ensureApplicationSupportDirectory()
        let data = try Self.makeEncoder().encode(connections)
        try data.write(to: paths.connectionsURL, options: [.atomic])
        try setPrivatePermissions(at: paths.connectionsURL)
    }

    // MARK: - preferences.json

    func loadPreferences() throws -> AppPreferences {
        let data = try Data(contentsOf: paths.preferencesURL)
        let preferences = try Self.makeDecoder().decode(AppPreferences.self, from: data)
        try? setPrivatePermissions(at: paths.preferencesURL)
        return preferences
    }

    func savePreferences(_ preferences: AppPreferences) throws {
        paths.ensureApplicationSupportDirectory()
        let data = try Self.makeEncoder().encode(preferences)
        try data.write(to: paths.preferencesURL, options: [.atomic])
        try setPrivatePermissions(at: paths.preferencesURL)
    }

    // MARK: - helpers

    private func setPrivatePermissions(at url: URL) throws {
        try paths.fileManager.setAttributes(Self.privateFileAttributes, ofItemAtPath: url.path)
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        JSONDecoder()
    }
}

/// On-disk schema for `preferences.json`. Every field is optional so that
/// older files (missing newer fields) decode cleanly and newer files
/// (with fields we don't recognize) don't blow up under strict parsing.
/// Defaults are applied by the caller (`ConnectionStore` on macOS;
/// FFI/UI on Linux).
struct AppPreferences: Codable, Equatable {
    var lastConnectionID: UUID?
    var terminalTheme: TerminalThemePreference?
    var automaticallyChecksForUpdates: Bool?
    var lastAutomaticUpdateCheckAt: Date?
    var workspaceFileBookmarks: [WorkspaceFileBookmark]?
    var pinnedSessions: [PinnedSession]?
    var workflows: [WorkflowPreset]?
}
