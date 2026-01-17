import Foundation

/// Engine adapter for Apple Foundation Models.
///
/// This provides integration with Apple's on-device foundation models
/// when available on supported devices and OS versions.
final class AppleFMEngine: EngineAdapter, @unchecked Sendable {
    let engineType: EngineType = .appleFoundationModels

    private var _isAvailable: Bool?
    private let lock = NSLock()

    init() {}

    var isAvailable: Bool {
        get async {
            lock.lock()
            if let cached = _isAvailable {
                lock.unlock()
                return cached
            }
            lock.unlock()

            let available = await checkAvailability()

            lock.lock()
            _isAvailable = available
            lock.unlock()

            return available
        }
    }

    func generate(
        input: SyniInput,
        persona: Persona,
        grammar: Grammar,
        options: GenerationOptions?
    ) async throws -> EngineOutput {
        guard await isAvailable else {
            throw SyniError.engineUnavailable
        }

        // Apple Foundation Models integration
        // This would use the FoundationModels framework when available
        //
        // Example integration (when Apple releases the API):
        // let session = LanguageModelSession()
        // let response = try await session.respond(to: buildPrompt(input, persona))
        // return EngineOutput(text: response.content, ...)

        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            return try await generateWithFoundationModels(input: input, persona: persona, grammar: grammar, options: options)
        }
        #endif
        // Fallback for when FoundationModels is not available
        throw SyniError.engineUnavailable
    }

    // MARK: - Private

    private func checkAvailability() async -> Bool {
        #if canImport(FoundationModels)
        // Check if FoundationModels is available and device supports it
        // This would check for iOS 26+ and supported hardware
        if #available(iOS 26.0, macOS 26.0, *) {
            // Check model availability
            // return await LanguageModelSession.isAvailable
            return true
        }
        return false
        #else
        return false
        #endif
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    private func generateWithFoundationModels(
        input: SyniInput,
        persona: Persona,
        grammar: Grammar,
        options: GenerationOptions?
    ) async throws -> EngineOutput {
        // Integration with Apple Foundation Models
        // import FoundationModels
        // let session = LanguageModelSession()
        // let prompt = buildPrompt(input: input, persona: persona)
        // let response = try await session.respond(to: prompt)
        // return EngineOutput(
        //     text: response.content,
        //     tokensGenerated: response.tokenCount,
        //     promptTokens: prompt.tokenCount
        // )

        throw SyniError.engineUnavailable
    }
    #endif

    private func buildPrompt(input: SyniInput, persona: Persona) -> String {
        var prompt = ""

        if let systemPrompt = persona.defaultParams.systemPrompt {
            prompt += systemPrompt + "\n\n"
        }

        for (key, value) in input.context {
            prompt += "\(key): \(value)\n"
        }

        prompt += input.text

        return prompt
    }
}
