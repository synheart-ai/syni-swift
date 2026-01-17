import Foundation

/// A request for generation from the Syni SDK.
public struct SyniRequest: Sendable {
    /// The identifier of the persona to use for this request.
    public let personaId: String

    /// The input context or prompt for generation.
    public let input: SyniInput

    /// Optional overrides for generation parameters.
    public let options: GenerationOptions?

    /// A unique identifier for this request (auto-generated if not provided).
    public let requestId: String

    /// Creates a new generation request.
    public init(
        personaId: String,
        input: SyniInput,
        options: GenerationOptions? = nil,
        requestId: String = UUID().uuidString
    ) {
        self.personaId = personaId
        self.input = input
        self.options = options
        self.requestId = requestId
    }
}

/// Input data for a generation request.
public struct SyniInput: Sendable {
    /// The primary text content for generation.
    public let text: String

    /// Additional context or metadata as key-value pairs.
    public let context: [String: String]

    /// Creates a new input.
    public init(text: String, context: [String: String] = [:]) {
        self.text = text
        self.context = context
    }
}

/// Options to customize generation behavior.
public struct GenerationOptions: Sendable {
    /// Override the default max tokens for this request.
    public let maxTokens: Int?

    /// Override the temperature (0.0 - 1.0).
    public let temperature: Double?

    /// Force local-only execution (no cloud fallback).
    public let localOnly: Bool

    /// Force cloud execution (skip local engines).
    public let cloudOnly: Bool

    /// Custom timeout override in milliseconds.
    public let timeoutMs: Int?

    public init(
        maxTokens: Int? = nil,
        temperature: Double? = nil,
        localOnly: Bool = false,
        cloudOnly: Bool = false,
        timeoutMs: Int? = nil
    ) {
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.localOnly = localOnly
        self.cloudOnly = cloudOnly
        self.timeoutMs = timeoutMs
    }
}
