#if os(Linux)

import Foundation
import Glibc

/// Helpers for the JSON-as-payload convention used by the C ABI.
///
/// Complex value types (ConnectionProfile arrays, session metadata, etc.)
/// cross the language boundary as JSON-encoded `char *` strings rather than
/// as C structs — this trades a copy + parse for ABI stability and avoids
/// the alignment / padding / packing pitfalls of hand-mirroring Swift
/// structs in C. Measured cost (per the plan): <50 µs per profile load,
/// dominated by JSON not the copy.
///
/// All emitted strings are heap-allocated with `strdup` and MUST be freed
/// by the caller via `hermes_free_string`. Symmetric pairing — never call
/// `free` directly from C, always go through `hermes_free_string`, so the
/// allocator stays under Swift's control.
enum JsonBridge {
    /// Encodes `value` to a JSON UTF-8 string and returns a fresh heap copy.
    /// Returns nil if encoding fails or if the resulting string is non-UTF-8
    /// (the latter shouldn't happen for well-formed Swift types).
    static func emit<T: Encodable>(_ value: T) -> UnsafeMutablePointer<CChar>? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(value)
            return data.withUnsafeBytes { raw -> UnsafeMutablePointer<CChar>? in
                guard let base = raw.baseAddress?.assumingMemoryBound(to: CChar.self) else {
                    return nil
                }
                // We need a NUL-terminated C string; JSON output isn't, so
                // strndup to copy and terminate.
                return strndup(base, raw.count)
            }
        } catch {
            return nil
        }
    }

    /// Decodes a NUL-terminated C string as JSON into `T`. Returns nil on
    /// any error (null pointer, invalid UTF-8, decode failure).
    static func consume<T: Decodable>(_ ptr: UnsafePointer<CChar>?, as: T.Type = T.self) -> T? {
        guard let ptr else { return nil }
        let data = Data(bytes: ptr, count: Int(strlen(ptr)))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(T.self, from: data)
    }

    /// Copies a Swift String into a heap-allocated NUL-terminated C string.
    /// Caller (C side) frees via `hermes_free_string`.
    static func emitString(_ string: String) -> UnsafeMutablePointer<CChar>? {
        string.withCString { strdup($0) }
    }
}

#endif // os(Linux)
