#if os(Linux)

import Foundation

// MARK: - Wire envelopes

/// Wire format for an SSH command's stdout/stderr/exit code.
struct SSHCommandResultPayload: Codable {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

/// Wire format for an SSH command failure. `code` is a stable string
/// (one of "invalidConnection", "launchFailure", "localFailure",
/// "remoteFailure", "invalidResponse", "cancelled", or "internal" for
/// non-SSHTransportError errors). `message` is the human-readable
/// description.
struct SSHErrorEnvelope: Codable {
    let code: String
    let message: String
}

/// Result envelope returned to the C++ side via the async callback.
/// Either `data` or `error` is non-nil; `ok` indicates which. The
/// JSONEncoder omits nil keys, so the wire shape on success is
/// `{"data":{...},"ok":true}` and on failure is
/// `{"error":{...},"ok":false}`.
struct SSHResultEnvelope: Codable {
    let ok: Bool
    let data: SSHCommandResultPayload?
    let error: SSHErrorEnvelope?

    static func success(_ payload: SSHCommandResultPayload) -> SSHResultEnvelope {
        SSHResultEnvelope(ok: true, data: payload, error: nil)
    }

    static func failure(code: String, message: String) -> SSHResultEnvelope {
        SSHResultEnvelope(
            ok: false,
            data: nil,
            error: SSHErrorEnvelope(code: code, message: message)
        )
    }
}

extension SSHResultEnvelope {
    /// Build an envelope from any thrown error. Maps SSHTransportError
    /// cases to their stable string codes; everything else becomes
    /// "internal".
    static func from(error: Error) -> SSHResultEnvelope {
        if let transportError = error as? SSHTransportError {
            return .failure(
                code: transportError.ffiCode,
                message: transportError.errorDescription ?? String(describing: transportError)
            )
        }
        return .failure(code: "internal", message: String(describing: error))
    }
}

private extension SSHTransportError {
    /// Stable string identifier for the wire. Do NOT rename existing
    /// values — the C++ side branches on them.
    var ffiCode: String {
        switch self {
        case .invalidConnection: return "invalidConnection"
        case .launchFailure: return "launchFailure"
        case .localFailure: return "localFailure"
        case .remoteFailure: return "remoteFailure"
        case .invalidResponse: return "invalidResponse"
        }
    }
}

// MARK: - Request IDs

/// Monotonic request-ID counter. Each `hermes_ssh_execute` call (and any
/// future async-callback export) gets a fresh non-zero id. The id is
/// just a number — there is no in-memory registry behind it for v1,
/// because cancel isn't implemented yet. Future work will add a small
/// registry mapping ids to Tasks for cancel + diagnostics.
enum RequestID {
    private static let lock = NSLock()
    // `nonisolated(unsafe)` is honest here: every read and write is
    // serialized by the NSLock above. Swift 6 strict concurrency can't
    // see that statically, so we assert it.
    nonisolated(unsafe) private static var nextValue: Int64 = 1

    static func allocate() -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        let value = nextValue
        nextValue &+= 1
        if nextValue == 0 { nextValue = 1 }  // skip 0 if we ever wrap
        return value
    }
}

#endif // os(Linux)
