import Foundation

/// Client for communicating with the Syni cloud gateway.
///
/// Per RFC: talks ONLY to syni-cloud-gateway, no direct OpenAI or third-party calls.
final class CloudClient: EngineAdapter, @unchecked Sendable {
    let engineType: EngineType = .cloud

    private let config: CloudConfig
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(config: CloudConfig) {
        self.config = config

        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = config.timeoutSeconds
        sessionConfig.timeoutIntervalForResource = config.timeoutSeconds * 2
        self.session = URLSession(configuration: sessionConfig)
    }

    var isAvailable: Bool {
        get async {
            // Cloud is always "available" if configured
            // Actual availability depends on network
            true
        }
    }

    func generate(
        input: SyniInput,
        persona: Persona,
        grammar: Grammar,
        options: GenerationOptions?
    ) async throws -> EngineOutput {
        let request = try buildRequest(input: input, persona: persona, grammar: grammar, options: options)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SyniError.cloudRequestFailed(underlying: nil)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SyniError.cloudRequestFailed(
                underlying: NSError(
                    domain: "SyniCloud",
                    code: httpResponse.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: errorMessage]
                )
            )
        }

        return try parseResponse(data)
    }

    // MARK: - Private

    private func buildRequest(
        input: SyniInput,
        persona: Persona,
        grammar: Grammar,
        options: GenerationOptions?
    ) throws -> URLRequest {
        var url = config.gatewayURL
        url.append(path: "v1/generate")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.authToken)", forHTTPHeaderField: "Authorization")
        request.setValue(Syni.sdkSpecVersion, forHTTPHeaderField: "X-Syni-Spec-Version")

        let payload = CloudRequest(
            personaId: persona.id,
            input: CloudInput(
                text: input.text,
                context: input.context
            ),
            grammarId: grammar.id,
            maxTokens: options?.maxTokens ?? persona.budget.maxTokens,
            temperature: options?.temperature ?? persona.defaultParams.temperature
        )

        request.httpBody = try encoder.encode(payload)

        return request
    }

    private func parseResponse(_ data: Data) throws -> EngineOutput {
        let response = try decoder.decode(CloudResponse.self, from: data)

        return EngineOutput(
            text: response.output,
            tokensGenerated: response.tokensGenerated,
            promptTokens: response.promptTokens
        )
    }
}

// MARK: - Request/Response Types

private struct CloudRequest: Encodable {
    let personaId: String
    let input: CloudInput
    let grammarId: String
    let maxTokens: Int
    let temperature: Double
}

private struct CloudInput: Encodable {
    let text: String
    let context: [String: String]
}

private struct CloudResponse: Decodable {
    let output: String
    let tokensGenerated: Int
    let promptTokens: Int
}
