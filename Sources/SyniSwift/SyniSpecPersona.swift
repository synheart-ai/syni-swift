import Foundation

/// Loads a `SyniPersona` from a bundled `syni-spec` JSON asset.
///
/// Mirrors `SyniSpecPersona` from `package:syni`. V1 lookup is by id only
/// (e.g. `focus.coach.v1`) and searches the `prod` tier inside the host
/// bundle's `personas/prod/<id>.json` resource path.
public enum SyniSpecPersona {

    /// Resolve and parse the bundled persona JSON for `id`. Throws
    /// `SyniSpecPersonaError` when the id is unknown or the JSON can't
    /// be projected onto `SyniPersona`.
    public static func load(_ id: String, bundle: Bundle = .main) throws -> SyniPersona {
        let resource = "personas/prod/\(id)"
        guard let url = bundle.url(forResource: resource, withExtension: "json") else {
            throw SyniSpecPersonaError.notBundled(id: id, assetPath: "\(resource).json")
        }
        let raw: Data
        do {
            raw = try Data(contentsOf: url)
        } catch {
            throw SyniSpecPersonaError.notBundled(id: id, assetPath: url.path)
        }
        return try fromJSON(raw, id: id)
    }

    /// Visible for testing.
    public static func fromJSON(_ raw: Data, id idHint: String? = nil) throws -> SyniPersona {
        let parsed: Any
        do {
            parsed = try JSONSerialization.jsonObject(with: raw)
        } catch {
            throw SyniSpecPersonaError.invalidJSON(id: idHint ?? "?")
        }
        guard let j = parsed as? [String: Any] else {
            throw SyniSpecPersonaError.invalidJSON(id: idHint ?? "?")
        }
        guard
            let id = j["id"] as? String,
            let name = j["name"] as? String,
            let systemPrompt = j["system_prompt"] as? String,
            let outputSchemaId = j["output_schema_id"] as? String
        else {
            throw SyniSpecPersonaError.missingFields(id: idHint ?? "?")
        }
        return SyniPersona(
            id: id,
            displayName: name,
            systemPrompt: systemPrompt,
            responseSchemaId: normalizeOutputSchema(outputSchemaId)
        )
    }

    /// Map a versioned spec output schema id to the short name the runtime
    /// expects (`coach`, `chat`, `suggestions`).
    public static func normalizeOutputSchema(_ id: String) -> String {
        (id.split(separator: ".").first.map(String.init) ?? id).lowercased()
    }
}

public enum SyniSpecPersonaError: Error, CustomStringConvertible, Equatable, Sendable {
    case notBundled(id: String, assetPath: String)
    case invalidJSON(id: String)
    case missingFields(id: String)

    public var description: String {
        switch self {
        case let .notBundled(id, path):
            return "SyniSpecPersonaException: persona \"\(id)\" not bundled at \(path)"
        case let .invalidJSON(id):
            return "SyniSpecPersonaException: persona \"\(id)\": invalid JSON"
        case let .missingFields(id):
            return "SyniSpecPersonaException: persona \"\(id)\" missing one of {id, name, system_prompt, output_schema_id}"
        }
    }
}
