#if !canImport(OSLog)

import Foundation

// Minimal Logger shim for non-Apple platforms. Mirrors the OSLog API surface
// HermesDesktop actually uses (init(subsystem:category:) + notice(_:)).
// Writes plain timestamped lines to stderr.
//
// Future work: swap to swift-log with a journald backend (Phase 11 hardening).
struct Logger {
    let subsystem: String
    let category: String

    init(subsystem: String, category: String) {
        self.subsystem = subsystem
        self.category = category
    }

    func notice(_ message: @autoclosure () -> String) {
        let line = "[\(subsystem)/\(category)] \(message())\n"
        FileHandle.standardError.write(Data(line.utf8))
    }
}

#endif
