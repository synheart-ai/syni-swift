import Foundation

/// The response from a Syni generation request.
public struct SyniResponse: Sendable {
    /// The unique identifier matching the request.
    public let requestId: String

    /// The validated JSON output conforming to the persona's schema.
    /// UI must only consume this field.
    public let outputJSON: [String: Any]

    /// Metadata about the generation.
    public let metadata: ResponseMetadata

    /// Whether this response is a fallback due to engine/validation failure.
    public let isFallback: Bool

    /// Creates a new response.
    public init(
        requestId: String,
        outputJSON: [String: Any],
        metadata: ResponseMetadata,
        isFallback: Bool = false
    ) {
        self.requestId = requestId
        self.outputJSON = outputJSON
        self.metadata = metadata
        self.isFallback = isFallback
    }
}

// MARK: - Sendable conformance workaround for [String: Any]

extension SyniResponse {
    /// Returns the output JSON as Data for safe cross-isolation boundary transfer.
    public var outputJSONData: Data? {
        try? JSONSerialization.data(withJSONObject: outputJSON)
    }

    /// Creates a response from JSON data.
    public static func fromJSONData(
        requestId: String,
        jsonData: Data,
        metadata: ResponseMetadata,
        isFallback: Bool = false
    ) throws -> SyniResponse {
        guard let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw SyniError.internalError(message: "Invalid JSON data")
        }
        return SyniResponse(
            requestId: requestId,
            outputJSON: json,
            metadata: metadata,
            isFallback: isFallback
        )
    }
}

/// Metadata about a generation response.
public struct ResponseMetadata: Sendable {
    /// Which engine was used for generation.
    public let engine: EngineType

    /// Time taken for generation in milliseconds.
    public let latencyMs: Int

    /// Number of tokens generated.
    public let tokensGenerated: Int

    /// Number of tokens in the prompt/context.
    public let promptTokens: Int

    /// Whether schema validation required a retry.
    public let didRetry: Bool

    /// The persona ID used.
    public let personaId: String

    public init(
        engine: EngineType,
        latencyMs: Int,
        tokensGenerated: Int,
        promptTokens: Int,
        didRetry: Bool,
        personaId: String
    ) {
        self.engine = engine
        self.latencyMs = latencyMs
        self.tokensGenerated = tokensGenerated
        self.promptTokens = promptTokens
        self.didRetry = didRetry
        self.personaId = personaId
    }
}

/// The type of engine used for generation.
public enum EngineType: String, Sendable, Codable {
    /// Apple Foundation Models (on-device).
    case appleFoundationModels = "apple_fm"

    /// PortableLocalEngine (llama.cpp based).
    case portableLocalEngine = "local"

    /// Syni cloud gateway.
    case cloud = "cloud"

    /// Fallback/mock engine.
    case fallback = "fallback"
}
