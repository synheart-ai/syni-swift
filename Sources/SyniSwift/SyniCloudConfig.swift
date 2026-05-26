import Foundation

/// Configuration the cloud client needs from the host SDK.
///
/// Mirrors `SyniCloudConfig` from `package:syni`. SyniSwift owns no
/// credentials and no tenant identity — those belong to the host SDK
/// (`synheart-core-swift`).
public struct SyniCloudConfig: Sendable {
    /// `syni-service` base URL, e.g. `https://api.synheart.ai`.
    public let baseUrl: String

    /// Per-request auth-header provider. Given the HTTP `method` and the
    /// absolute request `url`, returns the headers to attach — e.g.
    /// `["X-Synheart-Proof": "<jws>"]` for device-attestation auth.
    ///
    /// It is request-aware because an `X-Synheart-Proof` is signed over
    /// the method and URL and so cannot be a static token. Return an
    /// empty map when no credential is available (the cloud rejects
    /// unauthenticated requests unless `DISABLE_CHAT_AUTH=true` in test
    /// mode).
    public let authHeaders: @Sendable (String, String) async -> [String: String]

    public let tenantId: String
    public let userId: String
    public let projectId: String
    public let orgId: String
    public let appId: String
    public let deviceId: String

    public init(
        baseUrl: String,
        authHeaders: @escaping @Sendable (String, String) async -> [String: String],
        tenantId: String,
        userId: String,
        projectId: String = "",
        orgId: String = "",
        appId: String = "",
        deviceId: String = ""
    ) {
        self.baseUrl = baseUrl
        self.authHeaders = authHeaders
        self.tenantId = tenantId
        self.userId = userId
        self.projectId = projectId
        self.orgId = orgId
        self.appId = appId
        self.deviceId = deviceId
    }
}

public struct SyniCloudException: Error, CustomStringConvertible, Equatable, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { "SyniCloudException: \(message)" }
}
