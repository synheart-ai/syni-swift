import Foundation

/// A declarative Syni persona — voice, goals, boundaries, output schema.
///
/// Mirrors `SyniPersona` from `package:syni`. This is the generic type
/// only; SyniSwift defines no concrete personas — that is a product / spec
/// concern. Personas are either supplied by the host app or loaded from
/// bundled `syni-spec` assets via `SyniSpecPersona`.
public struct SyniPersona: Equatable, Sendable {
    /// Canonical spec persona id, e.g. `focus.coach.v1`.
    public let id: String

    /// Human-readable name surfaced in host-app UI.
    public let displayName: String

    /// System prompt prepended to the HSI-conditioned prompt by the runtime.
    public let systemPrompt: String

    /// Output schema selector — one of `suggestions`, `coach`, `chat`.
    public let responseSchemaId: String

    /// One- or two-sentence tone descriptor.
    public let tone: String

    public init(
        id: String,
        displayName: String,
        systemPrompt: String,
        responseSchemaId: String,
        tone: String = "calm"
    ) {
        self.id = id
        self.displayName = displayName
        self.systemPrompt = systemPrompt
        self.responseSchemaId = responseSchemaId
        self.tone = tone
    }
}
