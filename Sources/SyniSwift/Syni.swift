import Foundation

/// The main entry point for the Syni SDK.
///
/// Use `Syni.initialize(config:)` to set up the SDK, then call
/// `Syni.shared.generate(request:completion:)` to perform generation.
public final class Syni: @unchecked Sendable {
    /// The shared singleton instance. Only available after `initialize(config:)` is called.
    public private(set) static var shared: Syni?

    /// The current configuration.
    public let config: SyniConfig

    /// The spec version this SDK conforms to.
    public static let sdkSpecVersion = "1.0.0"

    // MARK: - Internal Components

    private let personaRouter: PersonaRouter
    private let schemaValidator: SchemaValidator
    private let budgetEnforcer: BudgetEnforcer
    private let engineManager: EngineManager
    private let cloudClient: CloudClient?
    private let modelManager: ModelManager

    // MARK: - State

    private var isInitialized = false
    private let lock = NSLock()

    // MARK: - Initialization

    private init(config: SyniConfig) throws {
        self.config = config

        // Initialize components
        self.personaRouter = PersonaRouter(personasPath: config.personasPath)
        self.schemaValidator = SchemaValidator(
            schemasPath: config.schemasPath,
            grammarsPath: config.grammarsPath
        )
        self.budgetEnforcer = BudgetEnforcer()
        self.modelManager = ModelManager(
            modelsPath: config.modelsPath,
            appGroupIdentifier: config.appGroupIdentifier
        )
        self.engineManager = EngineManager(
            appleFMConfig: config.appleFMConfig,
            localEngineConfig: config.localEngineConfig,
            modelManager: modelManager
        )

        if let cloudConfig = config.cloudConfig {
            self.cloudClient = CloudClient(config: cloudConfig)
        } else {
            self.cloudClient = nil
        }
    }

    /// Initializes the Syni SDK with the given configuration.
    ///
    /// This method loads personas, schemas, and grammars but does NOT load models by default.
    /// Models are loaded on-demand or via explicit `ModelManager` calls.
    ///
    /// - Parameter config: The configuration for the SDK.
    /// - Throws: `SyniError.invalidConfiguration` if the configuration is invalid.
    public static func initialize(config: SyniConfig) throws {
        let instance = try Syni(config: config)
        try instance.loadResources()
        shared = instance
        instance.isInitialized = true
    }

    /// Resets the SDK, releasing all resources. Primarily for testing.
    public static func reset() {
        shared?.cleanup()
        shared = nil
    }

    // MARK: - Generation

    /// Generates a response for the given request.
    ///
    /// This method:
    /// 1. Routes to the appropriate engine based on persona policy
    /// 2. Applies grammar-constrained decoding
    /// 3. Validates output against the schema
    /// 4. Retries once on validation failure (if allowed by persona budget)
    /// 5. Returns a safe fallback JSON on final failure
    ///
    /// - Parameters:
    ///   - request: The generation request.
    ///   - completion: Called with the result on completion.
    public func generate(
        request: SyniRequest,
        completion: @escaping (Result<SyniResponse, SyniError>) -> Void
    ) {
        guard isInitialized else {
            completion(.failure(.notInitialized))
            return
        }

        Task {
            do {
                let response = try await generateAsync(request: request)
                completion(.success(response))
            } catch let error as SyniError {
                completion(.failure(error))
            } catch {
                completion(.failure(.internalError(message: error.localizedDescription)))
            }
        }
    }

    /// Async version of generate.
    public func generateAsync(request: SyniRequest) async throws -> SyniResponse {
        guard isInitialized else {
            throw SyniError.notInitialized
        }

        // 1. Get persona
        let persona = try personaRouter.getPersona(id: request.personaId)

        // 2. Get schema and grammar
        let schema = try schemaValidator.getSchema(id: persona.schemaId)
        let grammar = try schemaValidator.getGrammar(id: persona.grammarId)

        // 3. Start budget tracking
        let budgetContext = budgetEnforcer.startTracking(
            budget: persona.budget,
            requestId: request.requestId
        )

        // 4. Route to engine - per RFC, engine unavailable returns fallback, not error
        let engine: any EngineAdapter
        do {
            engine = try await personaRouter.selectEngine(
                for: persona,
                engineManager: engineManager,
                cloudClient: cloudClient,
                options: request.options
            )
        } catch {
            // RFC Section 12: Engine unavailable → safe fallback JSON
            return createFallbackResponse(
                request: request,
                persona: persona,
                error: error,
                budgetContext: budgetContext
            )
        }

        // 5. Generate with retry logic
        var lastError: Error?
        var didRetry = false
        let maxAttempts = persona.budget.allowRetry ? (persona.budget.maxRetries + 1) : 1

        for attempt in 1...maxAttempts {
            do {
                // Check budget before attempting
                try budgetEnforcer.checkBudget(context: budgetContext)

                // Generate raw output
                let rawOutput = try await engine.generate(
                    input: request.input,
                    persona: persona,
                    grammar: grammar,
                    options: request.options
                )

                // Validate against schema
                let validatedJSON = try schemaValidator.validate(
                    output: rawOutput,
                    schema: schema
                )

                // Success - build response
                let latencyMs = budgetEnforcer.getElapsedMs(context: budgetContext)
                let metadata = ResponseMetadata(
                    engine: engine.engineType,
                    latencyMs: latencyMs,
                    tokensGenerated: rawOutput.tokensGenerated,
                    promptTokens: rawOutput.promptTokens,
                    didRetry: didRetry,
                    personaId: persona.id
                )

                return SyniResponse(
                    requestId: request.requestId,
                    outputJSON: validatedJSON,
                    metadata: metadata,
                    isFallback: false
                )

            } catch {
                lastError = error
                if attempt < maxAttempts {
                    didRetry = true
                    continue
                }
            }
        }

        // All attempts failed - return fallback
        return createFallbackResponse(
            request: request,
            persona: persona,
            error: lastError,
            budgetContext: budgetContext
        )
    }

    // MARK: - Private Helpers

    private func loadResources() throws {
        try personaRouter.loadPersonas()
        try schemaValidator.loadSchemas()
        try schemaValidator.loadGrammars()

        // Validate that loaded personas have corresponding schema + grammar.
        let personaIds = personaRouter.availablePersonaIds
        guard !personaIds.isEmpty else {
            throw SyniError.invalidConfiguration(reason: "No personas loaded")
        }

        for personaId in personaIds {
            let persona = try personaRouter.getPersona(id: personaId)
            do {
                _ = try schemaValidator.getSchema(id: persona.schemaId)
            } catch {
                throw SyniError.invalidConfiguration(
                    reason: "Missing schema '\(persona.schemaId)' for persona '\(persona.id)'"
                )
            }

            do {
                _ = try schemaValidator.getGrammar(id: persona.grammarId)
            } catch {
                throw SyniError.invalidConfiguration(
                    reason: "Missing grammar '\(persona.grammarId)' for persona '\(persona.id)'"
                )
            }
        }
    }

    private func cleanup() {
        engineManager.shutdown()
    }

    private func createFallbackResponse(
        request: SyniRequest,
        persona: Persona,
        error: Error?,
        budgetContext: BudgetContext
    ) -> SyniResponse {
        let fallbackJSON = schemaValidator.createFallbackJSON(for: persona.schemaId)
        let latencyMs = budgetEnforcer.getElapsedMs(context: budgetContext)

        let metadata = ResponseMetadata(
            engine: .fallback,
            latencyMs: latencyMs,
            tokensGenerated: 0,
            promptTokens: 0,
            didRetry: persona.budget.allowRetry,
            personaId: persona.id
        )

        return SyniResponse(
            requestId: request.requestId,
            outputJSON: fallbackJSON,
            metadata: metadata,
            isFallback: true
        )
    }
}

// MARK: - Convenience Extensions

extension Syni {
    /// Returns whether the SDK is initialized and ready.
    public static var isReady: Bool {
        shared?.isInitialized ?? false
    }

    /// Returns the model manager for downloading/managing models.
    public var models: ModelManager {
        modelManager
    }

    /// Returns the available personas.
    public var availablePersonas: [String] {
        personaRouter.availablePersonaIds
    }
}
