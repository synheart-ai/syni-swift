import Foundation
import SyniRuntime

/// Engine adapter for syni-runtime (llama.cpp based).
///
/// This engine uses GGUF models with grammar-constrained decoding
/// for deterministic, schema-compliant output.
final class LocalEngine: EngineAdapter, @unchecked Sendable {
    let engineType: EngineType = .local

    private let config: LocalEngineConfig
    private let modelManager: ModelManager
    private var engine: OpaquePointer?
    private var modelPath: String?
    private let lock = NSLock()

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
        // Ensure engine is initialized with model
        try await ensureEngineReady()

        let maxTokens = options?.maxTokens ?? persona.budget.maxTokens
        _ = options?.temperature ?? persona.defaultParams.temperature

        // Build the request JSON
        let request = SyniEngineRequest(
            hsi: buildHSIContext(from: input),
            instruction: input.text,
            schema: nil  // Schema validation done at Swift layer
        )

        guard let requestJSON = try? JSONEncoder().encode(request),
              let requestString = String(data: requestJSON, encoding: .utf8) else {
            throw SyniError.localEngineFailed(underlying: nil)
        }

        // Determine preset based on persona budget
        let preset = presetForBudget(persona.budget)

        // Run inference
        let output = try runInference(
            requestJSON: requestString,
            preset: preset,
            grammar: grammar.content,
            maxTokens: maxTokens,
            seed: UInt64.random(in: 0..<UInt64.max)
        )

        return output
    }

    // MARK: - Private

    private func ensureEngineReady() async throws {
        lock.lock()
        if engine != nil {
            lock.unlock()
            return
        }
        lock.unlock()

        guard let modelURL = await modelManager.getActiveModelPath() else {
            throw SyniError.engineUnavailable
        }

        try loadEngine(modelPath: modelURL.path)
    }

    private func loadEngine(modelPath: String) throws {
        lock.lock()
        defer { lock.unlock() }

        // Already loaded?
        if engine != nil && self.modelPath == modelPath {
            return
        }

        // Free existing engine if switching models
        if let existingEngine = engine {
            syni_engine_free(existingEngine)
            engine = nil
        }

        // Create new engine with model
        guard let newEngine = modelPath.withCString({ path in
            syni_engine_new_with_model(path)
        }) else {
            throw SyniError.localEngineFailed(
                underlying: NSError(
                    domain: "SyniRuntime",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to create engine with model: \(modelPath)"]
                )
            )
        }

        // Health check
        let health = syni_engine_healthcheck(newEngine)
        if health != 0 {
            syni_engine_free(newEngine)
            throw SyniError.localEngineFailed(
                underlying: NSError(
                    domain: "SyniRuntime",
                    code: Int(health),
                    userInfo: [NSLocalizedDescriptionKey: "Engine health check failed"]
                )
            )
        }

        self.engine = newEngine
        self.modelPath = modelPath
    }

    private func runInference(
        requestJSON: String,
        preset: syni_preset_t,
        grammar: String,
        maxTokens: Int,
        seed: UInt64
    ) throws -> EngineOutput {
        lock.lock()
        guard let engine = self.engine else {
            lock.unlock()
            throw SyniError.engineUnavailable
        }
        lock.unlock()

        // Call the syni-runtime C API
        let responsePtr = requestJSON.withCString { requestCStr in
            syni_engine_run_json(engine, preset, seed, requestCStr)
        }

        guard let responsePtr = responsePtr else {
            throw SyniError.localEngineFailed(
                underlying: NSError(
                    domain: "SyniRuntime",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "Inference returned null"]
                )
            )
        }

        // Convert response to Swift string
        let responseString = String(cString: responsePtr)

        // Free the C string
        syni_string_free(responsePtr)

        // Parse response JSON to extract the actual output
        guard let responseData = responseString.data(using: .utf8),
              let responseJSON = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            // Return raw response if not JSON (shouldn't happen with proper schema)
            return EngineOutput(text: responseString, tokensGenerated: 0, promptTokens: 0)
        }

        // Extract the message or full response
        if let message = responseJSON["message"] as? String {
            return EngineOutput(text: message, tokensGenerated: 0, promptTokens: 0)
        }

        // Return the full JSON string for schema validation
        return EngineOutput(text: responseString, tokensGenerated: 0, promptTokens: 0)
    }

    private func presetForBudget(_ budget: PerformanceBudget) -> syni_preset_t {
        // Map budget constraints to syni-runtime presets
        // Default to CHAT preset if no latency constraint
        guard let maxLatency = budget.maxLatencyMs else {
            return SYNI_PRESET_CHAT
        }

        if maxLatency <= 200 {
            return SYNI_PRESET_KEYBOARD
        } else if maxLatency <= 2500 {
            return SYNI_PRESET_COACH
        } else {
            return SYNI_PRESET_CHAT
        }
    }

    private func buildPrompt(input: SyniInput, persona: Persona) -> String {
        var prompt = ""

        if let systemPrompt = persona.defaultParams.systemPrompt {
            prompt += "<|im_start|>system\n\(systemPrompt)<|im_end|>\n"
        }

        if !input.context.isEmpty {
            prompt += "<|im_start|>system\nContext:\n"
            for (key, value) in input.context {
                prompt += "\(key): \(value)\n"
            }
            prompt += "<|im_end|>\n"
        }

        prompt += "<|im_start|>user\n\(input.text)<|im_end|>\n"
        prompt += "<|im_start|>assistant\n"

        return prompt
    }

    private func buildHSIContext(from input: SyniInput) -> [String: String] {
        // Convert SyniInput context to HSI format
        var hsi: [String: String] = [:]
        for (key, value) in input.context {
            hsi[key] = value
        }
        return hsi
    }

    /// Get token count for text using the loaded model's tokenizer.
    func tokenCount(for text: String) -> Int? {
        lock.lock()
        guard let engine = self.engine else {
            lock.unlock()
            return nil
        }
        lock.unlock()

        let count = text.withCString { textCStr in
            syni_token_count(engine, nil, textCStr)
        }

        return count >= 0 ? Int(count) : nil
    }

    /// Get library version.
    static var version: String {
        guard let versionPtr = syni_version() else {
            return "unknown"
        }
        let version = String(cString: versionPtr)
        syni_string_free(versionPtr)
        return version
    }

    deinit {
        lock.lock()
        if let engine = engine {
            syni_engine_free(engine)
        }
        lock.unlock()
    }
}

// MARK: - Request Types

/// Internal request structure matching syni-runtime's EngineRequest.
private struct SyniEngineRequest: Encodable {
    let hsi: [String: String]
    let instruction: String
    let schema: String?
}
