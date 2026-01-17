import Foundation

/// Engine adapter for PortableLocalEngine (llama.cpp based).
///
/// This engine uses GGUF models with grammar-constrained decoding
/// for deterministic, schema-compliant output.
final class PortableLocalEngine: EngineAdapter, @unchecked Sendable {
    let engineType: EngineType = .portableLocalEngine

    private let config: LocalEngineConfig
    private let modelManager: ModelManager
    private var modelLoaded = false
    private let lock = NSLock()

    // C-level handle would go here when integrating with actual llama.cpp
    // private var llamaContext: OpaquePointer?

    init(config: LocalEngineConfig, modelManager: ModelManager) {
        self.config = config
        self.modelManager = modelManager
    }

    var isAvailable: Bool {
        get async {
            // Check if we have a model available
            guard let _ = await modelManager.getActiveModelPath() else {
                return false
            }
            return true
        }
    }

    func generate(
        input: SyniInput,
        persona: Persona,
        grammar: Grammar,
        options: GenerationOptions?
    ) async throws -> EngineOutput {
        // Ensure model is loaded
        try await ensureModelLoaded()

        let prompt = buildPrompt(input: input, persona: persona)
        let maxTokens = options?.maxTokens ?? persona.budget.maxTokens
        let temperature = options?.temperature ?? persona.defaultParams.temperature

        // This is where the actual llama.cpp inference would happen
        // For now, return a stub that demonstrates the expected behavior
        let output = try await runInference(
            prompt: prompt,
            grammar: grammar.content,
            maxTokens: maxTokens,
            temperature: temperature
        )

        return output
    }

    // MARK: - Private

    private func ensureModelLoaded() async throws {
        lock.lock()
        if modelLoaded {
            lock.unlock()
            return
        }
        lock.unlock()

        guard let modelPath = await modelManager.getActiveModelPath() else {
            throw SyniError.engineUnavailable
        }

        try loadModel(at: modelPath)

        lock.lock()
        modelLoaded = true
        lock.unlock()
    }

    private func loadModel(at path: URL) throws {
        // llama.cpp model loading would happen here
        // llama_load_model_from_file(path.path, params)

        // For now, just verify the file exists
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw SyniError.localEngineFailed(underlying: nil)
        }
    }

    private func runInference(
        prompt: String,
        grammar: String,
        maxTokens: Int,
        temperature: Double
    ) async throws -> EngineOutput {
        // This is where llama.cpp inference with grammar constraints would run
        //
        // Actual implementation would:
        // 1. Tokenize the prompt
        // 2. Set up grammar constraints using the GBNF grammar
        // 3. Run inference with the specified parameters
        // 4. Decode tokens to text
        //
        // Example llama.cpp integration:
        // let grammarRules = llama_grammar_init(grammar)
        // let tokens = llama_tokenize(prompt)
        // var output = ""
        // for _ in 0..<maxTokens {
        //     let nextToken = llama_sample_with_grammar(context, grammarRules, temperature)
        //     if nextToken == llama_token_eos() { break }
        //     output += llama_token_to_string(nextToken)
        // }
        // return EngineOutput(text: output, ...)

        // Stub implementation - in production this calls into C/C++
        throw SyniError.localEngineFailed(
            underlying: NSError(
                domain: "SyniSwift",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "PortableLocalEngine not yet linked"]
            )
        )
    }

    private func buildPrompt(input: SyniInput, persona: Persona) -> String {
        var prompt = ""

        if let systemPrompt = persona.defaultParams.systemPrompt {
            prompt += "### System:\n\(systemPrompt)\n\n"
        }

        if !input.context.isEmpty {
            prompt += "### Context:\n"
            for (key, value) in input.context {
                prompt += "\(key): \(value)\n"
            }
            prompt += "\n"
        }

        prompt += "### User:\n\(input.text)\n\n"
        prompt += "### Assistant:\n"

        return prompt
    }

    deinit {
        // Clean up llama.cpp resources
        // llama_free(llamaContext)
    }
}
