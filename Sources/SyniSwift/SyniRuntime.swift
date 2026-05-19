import Foundation
import SyniRuntime

/// Preset selector matching the C ABI's `syni_preset_t`.
public enum SyniPreset: Int32, Sendable {
    case keyboard = 0
    case coach = 1
    case chat = 2

    fileprivate var raw: syni_preset_t {
        switch self {
        case .keyboard: return SYNI_PRESET_KEYBOARD
        case .coach: return SYNI_PRESET_COACH
        case .chat: return SYNI_PRESET_CHAT
        }
    }
}

/// A single inference request to the local runtime.
public struct SyniRuntimeRequest: Sendable {
    public let instruction: String
    public let hsi: [String: String]?
    public let schema: String?

    public init(instruction: String, hsi: [String: String]? = nil, schema: String? = nil) {
        self.instruction = instruction
        self.hsi = hsi
        self.schema = schema
    }
}

public struct SyniRuntimeResult: Sendable {
    public let rawJson: String
}

public enum SyniRuntimeStreamEvent: Sendable {
    case delta(String)
    case final(String)
}

public struct SyniRuntimeError: Error, Equatable {
    public let message: String
}

/// Thin Swift wrapper around the SyniRuntime C ABI. Mirrors the
/// `SyniRuntime` worker-isolate facade used by the Flutter SDK.
///
/// Internal to the SDK — consumers should use `SyniAgent`.
final class SyniRuntimeBridge: @unchecked Sendable {
    private var engine: OpaquePointer?
    private let lock = NSLock()

    func initialize() async throws {
        // No-op — version() is enough to verify the dylib is wired.
        _ = SyniRuntimeBridge.runtimeVersion()
    }

    func loadModel(_ path: String) async throws {
        lock.lock(); defer { lock.unlock() }
        if let e = engine {
            syni_engine_free(e); engine = nil
        }
        let new = path.withCString { syni_engine_new_with_model($0) }
        guard let new else {
            throw SyniRuntimeError(message: "syni_engine_new_with_model returned NULL for \(path)")
        }
        let hc = syni_engine_healthcheck(new)
        if hc != 0 {
            syni_engine_free(new)
            throw SyniRuntimeError(message: "engine healthcheck failed with code \(hc)")
        }
        engine = new
    }

    static func runtimeVersion() -> String? {
        guard let ptr = syni_version() else { return nil }
        defer { syni_string_free(ptr) }
        return String(cString: ptr)
    }

    func run(
        _ request: SyniRuntimeRequest,
        preset: SyniPreset = .chat,
        seed: UInt64 = 0
    ) async throws -> SyniRuntimeResult {
        lock.lock()
        guard let engine else {
            lock.unlock()
            throw SyniRuntimeError(message: "runtime not initialized — call loadModel() first")
        }
        lock.unlock()

        let body = try Self.encode(request)
        guard let raw = body.withCString({ ptr in
            syni_engine_run_json(engine, preset.raw, seed, ptr)
        }) else {
            throw SyniRuntimeError(message: "syni_engine_run_json returned NULL")
        }
        defer { syni_string_free(raw) }
        return SyniRuntimeResult(rawJson: String(cString: raw))
    }

    /// Streaming variant. V1 emits a single delta with the full text
    /// followed by a final — the FFI callback bridge is deferred until
    /// the API contract proves stable. Consumers see the right shape
    /// (`delta` then exactly one `final`) so they don't change when
    /// token-level streaming lands.
    func runStream(
        _ request: SyniRuntimeRequest,
        preset: SyniPreset = .chat,
        seed: UInt64 = 0
    ) -> AsyncThrowingStream<SyniRuntimeStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let result = try await self.run(request, preset: preset, seed: seed)
                    continuation.yield(.delta(result.rawJson))
                    continuation.yield(.final(result.rawJson))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func dispose() async {
        lock.lock(); defer { lock.unlock() }
        if let e = engine {
            syni_engine_free(e); engine = nil
        }
    }

    deinit {
        if let e = engine { syni_engine_free(e) }
    }

    private static func encode(_ r: SyniRuntimeRequest) throws -> String {
        var obj: [String: Any] = ["instruction": r.instruction]
        if let s = r.schema { obj["schema"] = s }
        if let h = r.hsi { obj["hsi"] = h }
        let data = try JSONSerialization.data(withJSONObject: obj)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
