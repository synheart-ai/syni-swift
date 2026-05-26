import Foundation
import Combine

/// Where a chat call should run. Mirrors `SyniExecutionMode` from
/// `package:syni`.
public enum SyniExecutionMode: Sendable {
    /// Always runs on the local runtime. Throws if no model is installed.
    /// Offline-safe; never touches the network.
    case localOnly
    /// Always `syni-service`. Throws if no cloud config was injected.
    case cloudOnly
    /// Try local, fall back to cloud on failure or when local isn't
    /// installed. Sensible default.
    case localFirst
}

/// Orchestrates an installed, persona-bound Syni: install lifecycle, model
/// management, and chat over the local runtime. Mirrors `SyniAgent` from
/// `package:syni`.
///
/// **Layering:** this is Syni's orchestration layer. It is HSI-agnostic —
/// it takes the conditioning context as a plain `[String: Any]?`
/// (`hsiContext`) and never imports a host-SDK type. The host SDK
/// (`synheart-core-swift`) wraps this with its four-authority gate and its
/// HSI context builder.
public actor SyniAgent {

    private let installer: SyniInstaller
    private let runtime: SyniRuntimeBridge
    private let cloudClient: SyniCloudClient?
    // `CurrentValueSubject` is thread-safe — accessing it from outside the
    // actor is fine. `nonisolated(unsafe) let` lets `installState` /
    // `currentState` be nonisolated without Swift 6 warnings.
    private nonisolated(unsafe) let stateSubject: CurrentValueSubject<SyniInstallState, Never>
    private var persona: SyniPersona?

    public init(
        installer: SyniInstaller? = nil,
        cloudConfig: SyniCloudConfig? = nil
    ) {
        self.installer = installer ?? SyniInstaller()
        self.runtime = SyniRuntimeBridge()
        self.cloudClient = cloudConfig.map { SyniCloudClient($0) }
        self.stateSubject = CurrentValueSubject(.notInstalled)
    }

    // -------------------------------------------------------------------------
    // State observation
    // -------------------------------------------------------------------------

    /// Whether a cloud client is configured (i.e. cloud chat is reachable).
    public nonisolated var hasCloud: Bool { cloudClient != nil }

    /// Hot stream of installation lifecycle events.
    public nonisolated var installState: AnyPublisher<SyniInstallState, Never> {
        stateSubject.eraseToAnyPublisher()
    }

    /// Current installation state.
    public nonisolated var currentState: SyniInstallState {
        stateSubject.value
    }

    /// True iff `currentState` is `.installed`.
    public nonisolated var isInstalled: Bool { currentState.isInstalled }

    // -------------------------------------------------------------------------
    // Install / uninstall
    // -------------------------------------------------------------------------

    /// Install Syni: download + verify the model, load the engine, bind
    /// `persona`. Emits lifecycle events on `installState`; throws on
    /// failure (after emitting `.failed`).
    public func install(persona: SyniPersona, model: SyniModelSpec) async throws {
        if case .installing = currentState {
            throw SyniRuntimeError(message: "install already in progress")
        }
        do {
            stateSubject.send(.installing(stage: .preflight, progress: 0.0))

            // Capture the subject directly — it's already thread-safe and
            // `nonisolated(unsafe)`, so calling `send` from the installer's
            // progress callback (potentially off-actor) is fine.
            let subject = stateSubject
            let modelPath = try await installer.ensureModel(model) { stage, progress in
                subject.send(.installing(stage: stage, progress: progress))
            }

            stateSubject.send(.installing(stage: .materializingPersona, progress: 0.0))
            self.persona = persona
            stateSubject.send(.installing(stage: .materializingPersona, progress: 1.0))

            stateSubject.send(.installing(stage: .loadingEngine, progress: 0.0))
            try await runtime.initialize()
            try await runtime.loadModel(modelPath)
            let version = SyniRuntimeBridge.runtimeVersion() ?? "unknown"
            stateSubject.send(.installing(stage: .loadingEngine, progress: 1.0))

            stateSubject.send(.installed(
                personaId: persona.id,
                modelPath: modelPath,
                runtimeVersion: version
            ))
        } catch {
            stateSubject.send(.failed(reason: String(describing: error), cause: String(describing: error)))
            throw error
        }
    }

    /// Cold-start restore. If the model + tokenizer are already on disk
    /// for `model`, binds `persona` and loads the engine — no download.
    /// Otherwise leaves state as `.notInstalled` and returns `false`.
    @discardableResult
    public func restoreInstallIfReady(persona: SyniPersona, model: SyniModelSpec) async -> Bool {
        switch currentState {
        case .installed: return true
        case .installing: return false
        default: break
        }
        if await !installer.isModelOnDisk(model) { return false }
        do {
            try await install(persona: persona, model: model)
        } catch {
            // Failure already emitted .failed; the screen handles it.
        }
        return isInstalled
    }

    /// Bind a persona without installing or loading a local model. Use when
    /// the agent will run cloud-only (`SyniExecutionMode.cloudOnly`) and you
    /// want chat methods to find a persona. Idempotent.
    public func bindPersona(_ persona: SyniPersona) {
        self.persona = persona
    }

    /// Free the engine. Keeps the downloaded model on disk.
    public func uninstall() async {
        await runtime.dispose()
        persona = nil
        stateSubject.send(.notInstalled)
    }

    /// Permanently removes `model` from the device: frees the engine, then
    /// deletes the GGUF and its sibling `tokenizer.json` from disk,
    /// reclaiming the ~1.1 GB the install occupies. Resets `installState`
    /// to `.notInstalled` so a subsequent `install()` re-downloads.
    ///
    /// Unlike `uninstall()` (which only frees the engine), this is a
    /// genuine storage-reclaiming delete. Returns the number of bytes
    /// freed.
    @discardableResult
    public func deleteModel(_ model: SyniModelSpec) async throws -> Int64 {
        await runtime.dispose()
        persona = nil
        defer { stateSubject.send(.notInstalled) }
        return try await installer.deleteModel(model)
    }

    /// Total on-disk bytes `model`'s install currently occupies (GGUF +
    /// tokenizer), or 0 when nothing is installed. Lets the UI show how
    /// much storage `deleteModel` will reclaim before the user confirms.
    public func installedBytes(_ model: SyniModelSpec) async -> Int64 {
        await installer.installedBytes(model)
    }

    /// For testing / shutdown.
    public func dispose() async {
        await runtime.dispose()
    }

    // -------------------------------------------------------------------------
    // Chat
    // -------------------------------------------------------------------------

    /// Run a single chat turn. `hsiContext` is the conditioning payload
    /// built by the host SDK (or nil). `mode` picks local vs cloud.
    public func chat(
        _ message: String,
        hsiContext: [String: Any]? = nil,
        seed: UInt64 = 0,
        mode: SyniExecutionMode = .localFirst
    ) async throws -> SyniChatResponse {
        let (_, p) = try requireReady()
        return try await route(
            mode,
            local: { try await self.localChat(p, message, hsiContext, seed) },
            cloud: { try await self.cloudChat(p, message, hsiContext) }
        )
    }

    /// Streaming counterpart to `chat`. Emits `.delta`s as tokens arrive,
    /// then exactly one `.final`.
    public nonisolated func chatStream(
        _ message: String,
        hsiContext: [String: Any]? = nil,
        seed: UInt64 = 0,
        mode: SyniExecutionMode = .localFirst
    ) -> AsyncThrowingStream<SyniChatEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.runStream(message, hsiContext: hsiContext, seed: seed, mode: mode, into: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func runStream(
        _ message: String,
        hsiContext: [String: Any]?,
        seed: UInt64,
        mode: SyniExecutionMode,
        into continuation: AsyncThrowingStream<SyniChatEvent, Error>.Continuation
    ) async throws {
        let (_, p) = try requireReady()
        try await routeStream(
            mode,
            local: { self.localChatStream(p, message, hsiContext, seed) },
            cloud: { await self.cloudClient!.chatStream(message: message, persona: p, hsiContext: hsiContext) },
            into: continuation
        )
    }

    // -------------------------------------------------------------------------
    // Routing
    // -------------------------------------------------------------------------

    private func route(
        _ mode: SyniExecutionMode,
        local: () async throws -> SyniChatResponse,
        cloud: () async throws -> SyniChatResponse
    ) async throws -> SyniChatResponse {
        switch mode {
        case .localOnly:
            return try await local()
        case .cloudOnly:
            guard cloudClient != nil else {
                throw SyniRuntimeError(message: "cloudOnly requested but no SyniCloudConfig injected")
            }
            return try await cloud()
        case .localFirst:
            do { return try await local() } catch {
                guard cloudClient != nil else { throw error }
                return try await cloud()
            }
        }
    }

    private func routeStream(
        _ mode: SyniExecutionMode,
        local: () -> AsyncThrowingStream<SyniChatEvent, Error>,
        cloud: () async -> AsyncThrowingStream<SyniChatEvent, Error>,
        into continuation: AsyncThrowingStream<SyniChatEvent, Error>.Continuation
    ) async throws {
        switch mode {
        case .localOnly:
            for try await e in local() { continuation.yield(e) }
        case .cloudOnly:
            guard cloudClient != nil else {
                throw SyniRuntimeError(message: "cloudOnly requested but no SyniCloudConfig injected")
            }
            for try await e in await cloud() { continuation.yield(e) }
        case .localFirst:
            var producedAny = false
            do {
                for try await e in local() {
                    producedAny = true
                    continuation.yield(e)
                }
                return
            } catch {
                if producedAny || cloudClient == nil { throw error }
                for try await e in await cloud() { continuation.yield(e) }
            }
        }
    }

    // -------------------------------------------------------------------------
    // Local + cloud paths
    // -------------------------------------------------------------------------

    private func localChat(
        _ persona: SyniPersona,
        _ message: String,
        _ hsiContext: [String: Any]?,
        _ seed: UInt64
    ) async throws -> SyniChatResponse {
        guard case let .installed(_, _, runtimeVersion) = currentState else {
            throw SyniRuntimeError(message: "Syni is not installed.")
        }
        let raw = try await runtime.run(
            SyniRuntimeRequest(
                instruction: formatInstruction(persona, message),
                hsi: hsiContext?.mapValues { "\($0)" },
                schema: persona.responseSchemaId
            ),
            preset: presetForSchema(persona.responseSchemaId),
            seed: seed
        )
        return SyniChatResponse.fromRuntimeJson(
            raw.rawJson,
            personaId: persona.id,
            runtimeVersion: runtimeVersion
        )
    }

    private nonisolated func localChatStream(
        _ persona: SyniPersona,
        _ message: String,
        _ hsiContext: [String: Any]?,
        _ seed: UInt64
    ) -> AsyncThrowingStream<SyniChatEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard case let .installed(_, _, runtimeVersion) = self.currentState else {
                        throw SyniRuntimeError(message: "Syni is not installed.")
                    }
                    let p = persona
                    let stream = self.runtime.runStream(
                        SyniRuntimeRequest(
                            instruction: self.formatInstruction(p, message),
                            hsi: hsiContext?.mapValues { "\($0)" },
                            schema: p.responseSchemaId
                        ),
                        preset: self.presetForSchema(p.responseSchemaId),
                        seed: seed
                    )
                    for try await evt in stream {
                        switch evt {
                        case let .delta(text):
                            continuation.yield(.delta(text))
                        case let .final(raw):
                            continuation.yield(.final(SyniChatResponse.fromRuntimeJson(
                                raw, personaId: p.id, runtimeVersion: runtimeVersion
                            )))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func cloudChat(
        _ persona: SyniPersona,
        _ message: String,
        _ hsiContext: [String: Any]?
    ) async throws -> SyniChatResponse {
        guard let client = cloudClient else {
            throw SyniRuntimeError(message: "no cloud client configured")
        }
        return try await client.chat(message: message, persona: persona, hsiContext: hsiContext)
    }

    // -------------------------------------------------------------------------
    // Internals
    // -------------------------------------------------------------------------

    private func requireReady() throws -> (state: SyniInstallState, persona: SyniPersona) {
        let s = currentState
        guard case .installed = s else {
            throw SyniRuntimeError(message: "Syni is not installed. Call install() first.")
        }
        guard let p = persona else {
            throw SyniRuntimeError(message: "persona missing (internal)")
        }
        return (s, p)
    }

    /// V1: prepend the persona's system prompt inline. V2: have the runtime
    /// resolve the persona rather than baking it into the instruction string.
    private nonisolated func formatInstruction(_ persona: SyniPersona, _ userMessage: String) -> String {
        "\(persona.systemPrompt)\n\nUser: \(userMessage)"
    }

    private nonisolated func presetForSchema(_ id: String) -> SyniPreset {
        switch id {
        case "suggestions": return .keyboard
        case "coach": return .coach
        default: return .chat
        }
    }
}
