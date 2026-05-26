import Foundation

/// One entry in the Syni model catalog. Mirrors `SyniModelOption` from
/// `package:syni`.
public enum SyniModelOption: Equatable, Sendable {
    case local(SyniLocalModel)
    case cloud(SyniCloudModel)

    public var id: String {
        switch self {
        case let .local(m): return m.id
        case let .cloud(m): return m.id
        }
    }

    public var displayName: String {
        switch self {
        case let .local(m): return m.displayName
        case let .cloud(m): return m.displayName
        }
    }

    public var isDefault: Bool {
        switch self {
        case let .local(m): return m.isDefault
        case let .cloud(m): return m.isDefault
        }
    }

    /// Parse one `/v1/models` manifest entry.
    public static func fromJSON(_ json: [String: Any]) throws -> SyniModelOption {
        let id = (json["id"] as? String) ?? ""
        let displayName = (json["display_name"] as? String) ?? id
        let description = (json["description"] as? String) ?? ""
        let optimizedFor = Set((json["optimized_for"] as? [String]) ?? [])
        let requires = Set((json["requires"] as? [String]) ?? [])
        let isDefault = (json["default"] as? Bool) ?? false
        switch json["kind"] as? String {
        case "local":
            let local = (json["local"] as? [String: Any]) ?? [:]
            return .local(SyniLocalModel(
                id: id, displayName: displayName, description: description,
                optimizedFor: optimizedFor, requires: requires, isDefault: isDefault,
                spec: SyniModelSpec.fromManifest(id: id, local: local)
            ))
        case "cloud":
            let cloud = (json["cloud"] as? [String: Any]) ?? [:]
            return .cloud(SyniCloudModel(
                id: id, displayName: displayName, description: description,
                optimizedFor: optimizedFor, requires: requires, isDefault: isDefault,
                serviceModelId: (cloud["service_model_id"] as? String) ?? "default"
            ))
        default:
            throw SyniCatalogError.unknownKind(String(describing: json["kind"]))
        }
    }
}

public struct SyniLocalModel: Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let description: String
    public let optimizedFor: Set<String>
    public let requires: Set<String>
    public let isDefault: Bool
    public let spec: SyniModelSpec
}

public struct SyniCloudModel: Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let description: String
    public let optimizedFor: Set<String>
    public let requires: Set<String>
    public let isDefault: Bool
    public let serviceModelId: String
}

public enum SyniCatalogError: Error, Equatable, Sendable {
    case unknownKind(String)
}

/// Fetches + caches the Syni model catalog from `syni-service` `GET /v1/models`.
/// Mirrors `SyniModelCatalog` from `package:syni`.
///
/// Auth token and base URL are injected by the host SDK — SyniSwift does
/// not own credentials. With no base URL, or on any fetch failure, falls
/// back to `.bundled`.
public actor SyniModelCatalog {
    private let baseUrl: String?
    private let authToken: (@Sendable () async -> String?)?
    private let session: URLSession
    private var cache: [SyniModelOption]?

    public init(
        baseUrl: String? = nil,
        authToken: (@Sendable () async -> String?)? = nil,
        session: URLSession = .shared
    ) {
        self.baseUrl = baseUrl
        self.authToken = authToken
        self.session = session
    }

    /// Available models. Fetches `/v1/models` on first call (when a base
    /// URL is configured), caches the result, falls back to `.bundled` on
    /// any failure.
    public func available(forceRefresh: Bool = false) async -> [SyniModelOption] {
        if let c = cache, !forceRefresh { return c }
        guard let baseUrl = baseUrl, let url = URL(string: "\(baseUrl)/v1/models") else {
            cache = SyniModelCatalog.bundled
            return SyniModelCatalog.bundled
        }
        var req = URLRequest(url: url)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let tok = await authToken?(), !tok.isEmpty {
            req.setValue("Bearer \(tok)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                cache = SyniModelCatalog.bundled; return SyniModelCatalog.bundled
            }
            let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let raw = (decoded?["models"] as? [[String: Any]]) ?? []
            let parsed = raw.compactMap { try? SyniModelOption.fromJSON($0) }
            cache = parsed.isEmpty ? SyniModelCatalog.bundled : parsed
            return cache!
        } catch {
            cache = SyniModelCatalog.bundled
            return SyniModelCatalog.bundled
        }
    }

    /// The bundled fallback catalog — always available, no network.
    public static let bundled: [SyniModelOption] = [
        .local(SyniLocalModel(
            id: SyniModels.qwen25_15bInstructQ4.id,
            displayName: "Qwen2.5 1.5B (on-device)",
            description: "Runs fully on-device. Private, offline-capable, low-latency. " +
                "Modest reasoning depth.",
            optimizedFor: ["offline", "privacy", "low_latency"],
            requires: [],
            isDefault: true,
            spec: SyniModels.qwen25_15bInstructQ4
        )),
        .cloud(SyniCloudModel(
            id: "cloud-default",
            displayName: "Syni Cloud",
            description: "Runs server-side via Syni Cloud. Deeper reasoning, longer " +
                "context. Requires a network connection.",
            optimizedFor: ["deep_reasoning", "long_context", "quality"],
            requires: ["network"],
            isDefault: false,
            serviceModelId: "default"
        )),
    ]
}
