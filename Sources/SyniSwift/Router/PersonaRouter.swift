import Foundation

/// Routes requests to the appropriate engine based on persona policy.
final class PersonaRouter: @unchecked Sendable {
    private let personasPath: URL?
    private var personas: [String: Persona] = [:]
    private let lock = NSLock()

    init(personasPath: URL?) {
        self.personasPath = personasPath
    }

    /// Loads personas from the configured path or uses built-in defaults.
    func loadPersonas() throws {
        lock.lock()
        defer { lock.unlock() }

        if let path = personasPath {
            try loadPersonasFromPath(path)
        } else {
            loadBuiltInPersonas()
        }
    }

    /// Gets a persona by ID.
    func getPersona(id: String) throws -> Persona {
        lock.lock()
        defer { lock.unlock() }

        guard let persona = personas[id] else {
            throw SyniError.personaNotFound(id)
        }
        return persona
    }

    /// Returns all available persona IDs.
    var availablePersonaIds: [String] {
        lock.lock()
        defer { lock.unlock() }
        return Array(personas.keys)
    }

    /// Selects the best available engine for the given persona.
    func selectEngine(
        for persona: Persona,
        engineManager: EngineManager,
        cloudClient: CloudClient?,
        options: GenerationOptions?
    ) async throws -> any EngineAdapter {
        let policy = persona.routingPolicy

        // Handle explicit options
        if let opts = options {
            if opts.localOnly {
                return try await selectLocalEngine(policy: policy, engineManager: engineManager)
            }
            if opts.cloudOnly {
                guard let cloud = cloudClient, policy.allowCloud else {
                    throw SyniError.engineUnavailable
                }
                return cloud
            }
        }

        // Follow preferred engine order from policy
        for engineType in policy.preferredEngines {
            switch engineType {
            case .appleFoundationModels:
                if policy.allowAppleFM, let engine = await engineManager.getAppleFMEngine() {
                    return engine
                }

            case .local:
                if policy.allowLocal, let engine = await engineManager.getLocalEngine() {
                    return engine
                }

            case .cloud:
                if policy.allowCloud, let cloud = cloudClient {
                    return cloud
                }

            case .fallback:
                continue
            }
        }

        throw SyniError.engineUnavailable
    }

    // MARK: - Private

    private func selectLocalEngine(
        policy: RoutingPolicy,
        engineManager: EngineManager
    ) async throws -> any EngineAdapter {
        if policy.allowAppleFM, let engine = await engineManager.getAppleFMEngine() {
            return engine
        }
        if policy.allowLocal, let engine = await engineManager.getLocalEngine() {
            return engine
        }
        throw SyniError.engineUnavailable
    }

    private func loadPersonasFromPath(_ path: URL) throws {
        let fileManager = FileManager.default
        let contents = try fileManager.contentsOfDirectory(
            at: path,
            includingPropertiesForKeys: nil
        )

        for fileURL in contents where fileURL.pathExtension == "json" {
            let data = try Data(contentsOf: fileURL)
            let persona = try JSONDecoder().decode(Persona.self, from: data)
            personas[persona.id] = persona
        }
    }

    private func loadBuiltInPersonas() {
        // Built-in keyboard persona per RFC
        let keyboardPersona = Persona(
            id: "keyboard.v1",
            name: "Keyboard Assistant",
            version: "1.0.0",
            schemaId: "keyboard.v1",
            grammarId: "keyboard.v1",
            routingPolicy: RoutingPolicy(
                preferredEngines: [.appleFoundationModels, .local],
                allowAppleFM: true,
                allowLocal: true,
                allowCloud: false // Keyboard must be fast, no cloud
            ),
            budget: .keyboard,
            defaultParams: PersonaParams(
                temperature: 0.3,
                topP: 0.9,
                systemPrompt: nil
            )
        )

        // Built-in life coach persona per RFC
        let lifeCoachPersona = Persona(
            id: "life.coach.v1",
            name: "Life Coach",
            version: "1.0.0",
            schemaId: "life.coach.v1",
            grammarId: "life.coach.v1",
            routingPolicy: RoutingPolicy(
                preferredEngines: [.appleFoundationModels, .local, .cloud],
                allowAppleFM: true,
                allowLocal: true,
                allowCloud: true
            ),
            budget: .lifeCoach,
            defaultParams: PersonaParams(
                temperature: 0.7,
                topP: 0.9,
                systemPrompt: "You are a supportive and insightful life coach."
            )
        )

        personas[keyboardPersona.id] = keyboardPersona
        personas[lifeCoachPersona.id] = lifeCoachPersona
    }

    /// Registers a custom persona at runtime.
    func registerPersona(_ persona: Persona) {
        lock.lock()
        defer { lock.unlock() }
        personas[persona.id] = persona
    }
}
