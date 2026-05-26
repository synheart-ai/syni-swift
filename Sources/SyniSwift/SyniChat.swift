import Foundation

/// Which `EngineResponse` variant the runtime returned.
public enum SyniResponseKind: String, Sendable {
    case coach
    case chat
    case suggestions
    case unknown
}

/// A completed Syni response. Mirrors `SyniChatResponse` from
/// `package:syni`. Parses the runtime's tagged `EngineResponse` envelope —
/// `{"type":"coach","data":{...}}` — into a clean typed surface.
public struct SyniChatResponse: Equatable, Sendable {
    /// The persona that produced this response.
    public let personaId: String

    /// Runtime semver reported by `libsyni_ffi`.
    public let runtimeVersion: String

    /// The runtime's raw final JSON.
    public let rawJson: String

    /// Which `EngineResponse` variant this is.
    public let kind: SyniResponseKind

    /// Primary reply text. Nil for a pure suggestions response.
    public let message: String?

    /// Suggestion texts. Populated for `coach` and `suggestions`.
    public let suggestions: [String]

    /// Best-effort display string — `message` if present, else first
    /// suggestion, else a neutral placeholder.
    public var displayText: String {
        if let m = message?.trimmingCharacters(in: .whitespacesAndNewlines), !m.isEmpty {
            return m
        }
        if let s = suggestions.first { return s }
        return "Syni had no response."
    }

    /// Parse the runtime's final `EngineResponse` JSON string. Tolerant of
    /// unexpected shapes — falls back to `.unknown`.
    public static func fromRuntimeJson(
        _ rawJson: String,
        personaId: String,
        runtimeVersion: String
    ) -> SyniChatResponse {
        var kind: SyniResponseKind = .unknown
        var message: String? = nil
        var suggestions: [String] = []

        if let data = rawJson.data(using: .utf8),
           let decoded = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let body = decoded["data"] as? [String: Any] {
            switch decoded["type"] as? String {
            case "coach":
                kind = .coach
                message = body["message"] as? String
                suggestions = suggestionTexts(body["suggestions"])
            case "chat":
                kind = .chat
                message = body["message"] as? String
            case "suggestions":
                kind = .suggestions
                suggestions = suggestionTexts(body["suggestions"])
            default: break
            }
        }

        return SyniChatResponse(
            personaId: personaId,
            runtimeVersion: runtimeVersion,
            rawJson: rawJson,
            kind: kind,
            message: message,
            suggestions: suggestions
        )
    }

    /// Build a response from a cloud `reply` string.
    public static func fromCloudReply(
        _ reply: String,
        personaId: String,
        runtimeVersion: String
    ) -> SyniChatResponse {
        SyniChatResponse(
            personaId: personaId,
            runtimeVersion: runtimeVersion,
            rawJson: reply,
            kind: .chat,
            message: reply,
            suggestions: []
        )
    }

    private static func suggestionTexts(_ raw: Any?) -> [String] {
        guard let arr = raw as? [[String: Any]] else { return [] }
        return arr.compactMap { $0["text"] as? String }
    }
}

// ---------------------------------------------------------------------------
// Streaming events
// ---------------------------------------------------------------------------

/// One event in a streaming chat response. Discriminated union over
/// incremental deltas and the final structured response.
public enum SyniChatEvent: Equatable, Sendable {
    /// An incremental token chunk emitted during generation. For structured
    /// (coach / chat) schemas these are raw JSON tokens — not directly
    /// user-presentable. UI typically shows a "thinking" state until
    /// `.final` arrives.
    case delta(String)

    /// The final parsed response. Always emitted exactly once at the end
    /// of a successful stream.
    case final(SyniChatResponse)
}
