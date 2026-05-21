#if os(Linux)

import Foundation

/// Thread-safe registry mapping opaque `int64_t` handles to Swift objects.
///
/// The C++ Qt UI receives handles back from `hermes_*_init`-style functions
/// and never dereferences them — handles are just indices into this map.
/// On the Swift side, the registry holds a strong reference to the object so
/// it stays alive until `*_release` is called.
///
/// Thread safety: every public method takes an `NSLock`. Lock hold-time is
/// strictly O(1) — `register` increments a counter, `lookup` is a dictionary
/// read, `release` is a dictionary remove. The C++ side is free to call
/// these from any thread.
///
/// Handle `0` is intentionally reserved as "invalid" — `register` never
/// returns 0, `lookup(0)` always returns nil, `release(0)` is a no-op.
final class HandleRegistry: @unchecked Sendable {
    static let shared = HandleRegistry()

    private let lock = NSLock()
    private var storage: [Int64: Any] = [:]
    private var nextHandle: Int64 = 1

    /// Stores `value` and returns a fresh non-zero handle.
    func register(_ value: Any) -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        let handle = nextHandle
        nextHandle &+= 1  // wrap on overflow; practically unreachable
        if nextHandle == 0 { nextHandle = 1 }  // skip 0 if we ever wrap
        storage[handle] = value
        return handle
    }

    /// Returns the stored value if it matches the requested type, otherwise nil.
    /// Type mismatch typically indicates a C-side bug (using the wrong handle
    /// for the wrong function) — silently returning nil here lets the caller
    /// handle the error path cleanly without a Swift trap.
    func lookup<T>(_ handle: Int64, as type: T.Type) -> T? {
        guard handle != 0 else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return storage[handle] as? T
    }

    /// Drops the entry. Safe to call with handle 0 or a stale/unknown handle.
    func release(_ handle: Int64) {
        guard handle != 0 else { return }
        lock.lock()
        defer { lock.unlock() }
        storage.removeValue(forKey: handle)
    }
}

#endif // os(Linux)
