import Foundation

/// Preset selector matching the C ABI's `syni_preset_t` (`enum { keyboard=0, coach=1, chat=2 }`).
public enum SyniPreset: Int32, Sendable {
    case keyboard = 0
    case coach = 1
    case chat = 2
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

public struct SyniRuntimeError: Error, Equatable, Sendable {
    public let message: String
}

// MARK: - Native loader

/// Bridge to `libsyni_ffi` via C ABI / dlsym.
///
/// Library loading:
/// - macOS: `dlopen("libsyni_ffi.dylib")`
/// - Linux: `dlopen("libsyni_ffi.so")`
/// - iOS:   `RTLD_DEFAULT` (statically linked into the app binary)
///
/// The native runtime is shipped by the `synheart` CLI:
/// `synheart install runtime syni` writes the XCFramework / dylib
/// into `<app>/synheart/vendor/syni-runtime/`. Xcode picks it up at
/// link time; SwiftPM never sees the binary.
private enum SyniNative {
    typealias NewWithModelFn  = @convention(c) (UnsafePointer<CChar>?) -> OpaquePointer?
    typealias FreeFn          = @convention(c) (OpaquePointer?) -> Void
    typealias HealthcheckFn   = @convention(c) (OpaquePointer?) -> Int32
    typealias RunJsonFn       = @convention(c) (OpaquePointer?, Int32, UInt64, UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?
    typealias VersionFn       = @convention(c) () -> UnsafeMutablePointer<CChar>?
    typealias StringFreeFn    = @convention(c) (UnsafeMutablePointer<CChar>?) -> Void

    nonisolated(unsafe) static let lib: UnsafeMutableRawPointer? = {
        #if os(macOS)
        if let h = dlopen("libsyni_ffi.dylib", RTLD_LAZY) { return h }
        #endif
        // iOS: library is statically linked into the app binary; use RTLD_DEFAULT.
        return UnsafeMutableRawPointer(bitPattern: -2)
    }()

    static func sym<T>(_ name: String) -> T? {
        guard let lib = lib, let p = dlsym(lib, name) else { return nil }
        return unsafeBitCast(p, to: T.self)
    }

    static let engineNew:     NewWithModelFn? = sym("syni_engine_new_with_model")
    static let engineFree:    FreeFn?         = sym("syni_engine_free")
    static let engineHealth:  HealthcheckFn?  = sym("syni_engine_healthcheck")
    static let engineRun:     RunJsonFn?      = sym("syni_engine_run_json")
    static let version:       VersionFn?      = sym("syni_version")
    static let stringFree:    StringFreeFn?   = sym("syni_string_free")
}

// MARK: - Bridge

/// Thin Swift wrapper around the SyniRuntime C ABI. Mirrors the
/// `SyniRuntime` worker-isolate facade used by the Flutter SDK.
///
/// Internal to the SDK — consumers should use `SyniAgent`.
final class SyniRuntimeBridge: @unchecked Sendable {
    // `nonisolated(unsafe)` — protected by `lock` for all mutation.
    nonisolated(unsafe) private var engine: OpaquePointer?
    private let lock = NSLock()

    func initialize() async throws {
        // No-op — version() is enough to verify the dylib is wired.
        _ = SyniRuntimeBridge.runtimeVersion()
    }

    func loadModel(_ path: String) async throws {
        guard let engineNew = SyniNative.engineNew,
              let engineFree = SyniNative.engineFree,
              let engineHealth = SyniNative.engineHealth else {
            throw SyniRuntimeError(message: "syni_ffi symbols not found — did you run `synheart install runtime syni`?")
        }
        try lock.withLock {
            if let e = engine {
                engineFree(e); engine = nil
            }
            let new = path.withCString { engineNew($0) }
            guard let new else {
                throw SyniRuntimeError(message: "syni_engine_new_with_model returned NULL for \(path)")
            }
            let hc = engineHealth(new)
            if hc != 0 {
                engineFree(new)
                throw SyniRuntimeError(message: "engine healthcheck failed with code \(hc)")
            }
            engine = new
        }
    }

    static func runtimeVersion() -> String? {
        guard let versionFn = SyniNative.version,
              let stringFree = SyniNative.stringFree,
              let ptr = versionFn() else { return nil }
        defer { stringFree(ptr) }
        return String(cString: ptr)
    }

    func run(
        _ request: SyniRuntimeRequest,
        preset: SyniPreset = .chat,
        seed: UInt64 = 0
    ) async throws -> SyniRuntimeResult {
        guard let engineRun = SyniNative.engineRun,
              let stringFree = SyniNative.stringFree else {
            throw SyniRuntimeError(message: "syni_ffi symbols not found — did you run `synheart install runtime syni`?")
        }
        guard let engine = lock.withLock({ self.engine }) else {
            throw SyniRuntimeError(message: "runtime not initialized — call loadModel() first")
        }

        let body = try Self.encode(request)
        guard let raw = body.withCString({ ptr in
            engineRun(engine, preset.rawValue, seed, ptr)
        }) else {
            throw SyniRuntimeError(message: "syni_engine_run_json returned NULL")
        }
        defer { stringFree(raw) }
        return SyniRuntimeResult(rawJson: String(cString: raw))
    }

    /// Streaming variant. V1 emits a single delta with the full text
    /// followed by a final — the FFI callback bridge is deferred until
    /// the API contract proves stable.
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
        lock.withLock {
            if let e = engine, let engineFree = SyniNative.engineFree {
                engineFree(e); engine = nil
            }
        }
    }

    deinit {
        if let e = engine, let engineFree = SyniNative.engineFree {
            engineFree(e)
        }
    }

    private static func encode(_ r: SyniRuntimeRequest) throws -> String {
        var obj: [String: Any] = ["instruction": r.instruction]
        if let s = r.schema { obj["schema"] = s }
        if let h = r.hsi { obj["hsi"] = h }
        let data = try JSONSerialization.data(withJSONObject: obj)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
