import Foundation

/// Configuration the cloud client needs from the host SDK.
///
/// Mirrors `SyniCloudConfig` from `package:syni`. SyniSwift owns no
/// credentials and no tenant identity — those belong to the host SDK
/// (`synheart-core-swift`).
public struct SyniCloudConfig: Sendable {
    /// `syni-service` base URL, e.g. `https://api.synheart.ai`.
    public let baseUrl: String

    /// Async bearer token provider. Returns `nil` when no token is
    /// available.
    public let authToken: @Sendable () async -> String?

    public let tenantId: String
    public let userId: String
    public let projectId: String
    public let orgId: String
    public let appId: String
    public let deviceId: String

    public init(
        baseUrl: String,
        authToken: @escaping @Sendable () async -> String?,
        tenantId: String,
        userId: String,
        projectId: String = "",
        orgId: String = "",
        appId: String = "",
        deviceId: String = ""
    ) {
        self.baseUrl = baseUrl
        self.authToken = authToken
        self.tenantId = tenantId
        self.userId = userId
        self.projectId = projectId
        self.orgId = orgId
        self.appId = appId
        self.deviceId = deviceId
    }
}

public struct SyniCloudException: Error, CustomStringConvertible, Equatable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { "SyniCloudException: \(message)" }
}
