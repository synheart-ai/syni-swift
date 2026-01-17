import Foundation

/// A persona definition that controls routing, budgets, and schema selection.
public struct Persona: Sendable, Codable {
    /// Unique identifier for the persona (e.g., "keyboard.v1", "life.coach.v1").
    public let id: String

    /// Human-readable name.
    public let name: String

    /// Version of this persona definition.
    public let version: String

    /// The schema identifier for validating outputs.
    public let schemaId: String

    /// The grammar identifier for constrained decoding.
    public let grammarId: String

    /// Routing policy determining which engines can be used.
    public let routingPolicy: RoutingPolicy

    /// Performance budget for this persona.
    public let budget: PerformanceBudget

    /// Default generation parameters.
    public let defaultParams: PersonaParams

    public init(
        id: String,
        name: String,
        version: String,
        schemaId: String,
        grammarId: String,
        routingPolicy: RoutingPolicy,
        budget: PerformanceBudget,
        defaultParams: PersonaParams
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.schemaId = schemaId
        self.grammarId = grammarId
        self.routingPolicy = routingPolicy
        self.budget = budget
        self.defaultParams = defaultParams
    }
}

/// Routing policy for engine selection.
public struct RoutingPolicy: Sendable, Codable {
    /// Ordered list of preferred engines.
    public let preferredEngines: [EngineType]

    /// Whether Apple Foundation Models are allowed for this persona.
    public let allowAppleFM: Bool

    /// Whether local PortableLocalEngine is allowed.
    public let allowLocal: Bool

    /// Whether cloud fallback is allowed.
    public let allowCloud: Bool

    public init(
        preferredEngines: [EngineType] = [.appleFoundationModels, .portableLocalEngine, .cloud],
        allowAppleFM: Bool = true,
        allowLocal: Bool = true,
        allowCloud: Bool = true
    ) {
        self.preferredEngines = preferredEngines
        self.allowAppleFM = allowAppleFM
        self.allowLocal = allowLocal
        self.allowCloud = allowCloud
    }
}

/// Performance budget constraints for a persona.
public struct PerformanceBudget: Sendable, Codable {
    /// Maximum latency in milliseconds (nil = relaxed/no limit).
    public let maxLatencyMs: Int?

    /// Maximum tokens to generate.
    public let maxTokens: Int

    /// Whether retries are allowed on validation failure.
    public let allowRetry: Bool

    /// Maximum number of retries (only used if allowRetry is true).
    public let maxRetries: Int

    public init(
        maxLatencyMs: Int? = nil,
        maxTokens: Int = 256,
        allowRetry: Bool = true,
        maxRetries: Int = 1
    ) {
        self.maxLatencyMs = maxLatencyMs
        self.maxTokens = maxTokens
        self.allowRetry = allowRetry
        self.maxRetries = maxRetries
    }

    /// Preset for keyboard persona: ~150ms, no retries.
    public static let keyboard = PerformanceBudget(
        maxLatencyMs: 150,
        maxTokens: 64,
        allowRetry: false,
        maxRetries: 0
    )

    /// Preset for life coach persona: relaxed latency, 1 retry allowed.
    public static let lifeCoach = PerformanceBudget(
        maxLatencyMs: nil,
        maxTokens: 512,
        allowRetry: true,
        maxRetries: 1
    )
}

/// Default generation parameters for a persona.
public struct PersonaParams: Sendable, Codable {
    /// Default temperature for generation.
    public let temperature: Double

    /// Default top-p for nucleus sampling.
    public let topP: Double

    /// System prompt or instruction prefix.
    public let systemPrompt: String?

    public init(
        temperature: Double = 0.7,
        topP: Double = 0.9,
        systemPrompt: String? = nil
    ) {
        self.temperature = temperature
        self.topP = topP
        self.systemPrompt = systemPrompt
    }
}
