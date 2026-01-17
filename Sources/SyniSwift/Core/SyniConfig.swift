import Foundation

/// Configuration for initializing the Syni SDK.
public struct SyniConfig: Sendable {
    /// The version of syni-core-spec this SDK conforms to.
    public let specVersion: String

    /// Path to the directory containing persona definitions.
    public let personasPath: URL?

    /// Path to the directory containing schema files.
    public let schemasPath: URL?

    /// Path to the directory containing grammar files.
    public let grammarsPath: URL?

    /// Path to the directory for storing downloaded models.
    public let modelsPath: URL?

    /// Configuration for the cloud gateway client.
    public let cloudConfig: CloudConfig?

    /// Configuration for Apple Foundation Models engine.
    public let appleFMConfig: AppleFMConfig?

    /// Configuration for the PortableLocalEngine.
    public let localEngineConfig: LocalEngineConfig?

    /// App group identifier for keyboard extension communication.
    public let appGroupIdentifier: String?

    /// Whether to enable debug logging (no raw text logged by default).
    public let debugLoggingEnabled: Bool

    /// Creates a new Syni configuration.
    public init(
        specVersion: String = "1.0.0",
        personasPath: URL? = nil,
        schemasPath: URL? = nil,
        grammarsPath: URL? = nil,
        modelsPath: URL? = nil,
        cloudConfig: CloudConfig? = nil,
        appleFMConfig: AppleFMConfig? = nil,
        localEngineConfig: LocalEngineConfig? = nil,
        appGroupIdentifier: String? = nil,
        debugLoggingEnabled: Bool = false
    ) {
        self.specVersion = specVersion
        self.personasPath = personasPath
        self.schemasPath = schemasPath
        self.grammarsPath = grammarsPath
        self.modelsPath = modelsPath
        self.cloudConfig = cloudConfig
        self.appleFMConfig = appleFMConfig
        self.localEngineConfig = localEngineConfig
        self.appGroupIdentifier = appGroupIdentifier
        self.debugLoggingEnabled = debugLoggingEnabled
    }
}

/// Configuration for the Syni cloud gateway.
public struct CloudConfig: Sendable {
    /// The base URL of the Syni cloud gateway.
    public let gatewayURL: URL

    /// Authentication token for the gateway.
    public let authToken: String

    /// Request timeout in seconds.
    public let timeoutSeconds: TimeInterval

    public init(
        gatewayURL: URL,
        authToken: String,
        timeoutSeconds: TimeInterval = 30.0
    ) {
        self.gatewayURL = gatewayURL
        self.authToken = authToken
        self.timeoutSeconds = timeoutSeconds
    }
}

/// Configuration for Apple Foundation Models engine.
public struct AppleFMConfig: Sendable {
    /// Whether to prefer Apple Foundation Models when available.
    public let preferWhenAvailable: Bool

    public init(preferWhenAvailable: Bool = true) {
        self.preferWhenAvailable = preferWhenAvailable
    }
}

/// Configuration for the PortableLocalEngine (llama.cpp based).
public struct LocalEngineConfig: Sendable {
    /// Number of threads to use for inference.
    public let threadCount: Int

    /// Whether to use Metal acceleration on supported devices.
    public let useMetalAcceleration: Bool

    /// Maximum context length in tokens.
    public let maxContextLength: Int

    public init(
        threadCount: Int = 4,
        useMetalAcceleration: Bool = true,
        maxContextLength: Int = 2048
    ) {
        self.threadCount = threadCount
        self.useMetalAcceleration = useMetalAcceleration
        self.maxContextLength = maxContextLength
    }
}
