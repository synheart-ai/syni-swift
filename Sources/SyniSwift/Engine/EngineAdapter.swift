import Foundation

/// Protocol for all inference engines (local and cloud).
protocol EngineAdapter: Sendable {
    /// The type of this engine.
    var engineType: EngineType { get }

    /// Whether this engine is currently available.
    var isAvailable: Bool { get async }

    /// Generates output for the given input.
    func generate(
        input: SyniInput,
        persona: Persona,
        grammar: Grammar,
        options: GenerationOptions?
    ) async throws -> EngineOutput
}

/// Output from an engine's generation.
struct EngineOutput: Sendable {
    /// The raw text output from the engine.
    let text: String

    /// Number of tokens generated.
    let tokensGenerated: Int

    /// Number of tokens in the prompt.
    let promptTokens: Int

    init(text: String, tokensGenerated: Int = 0, promptTokens: Int = 0) {
        self.text = text
        self.tokensGenerated = tokensGenerated
        self.promptTokens = promptTokens
    }
}
