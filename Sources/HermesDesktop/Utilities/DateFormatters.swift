import Foundation

extension ISO8601DateFormatter {
    static func fractionalSecondsFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}

enum DateFormatters {
    #if !os(Linux)
    // RelativeDateTimeFormatter is not available in swift-corelibs-foundation
    // as of Swift 6.3. UI callers (Views/) are macOS-only, so this is gated.
    static func relativeFormatter() -> RelativeDateTimeFormatter {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }
    #endif

    static func shortDateTimeFormatter() -> DateFormatter {
        let cacheKey = "HermesDesktop.shortDateTimeFormatter"
        if let formatter = Thread.current.threadDictionary[cacheKey] as? DateFormatter {
            return formatter
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        Thread.current.threadDictionary[cacheKey] = formatter
        return formatter
    }

    static func shortDateTimeString(from date: Date) -> String {
        shortDateTimeFormatter().string(from: date)
    }
}
