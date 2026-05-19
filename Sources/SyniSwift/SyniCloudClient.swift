import Foundation

/// HTTP + SSE client for `syni-service` `/v1/chat[/stream]`. Mirrors
/// `SyniCloudClient` from `package:syni`. Internal — consumers drive
/// this through `SyniAgent`.
actor SyniCloudClient {
    private let config: SyniCloudConfig
    private let session: URLSession
    private var sessionId: String?

    init(_ config: SyniCloudConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    // -------------------------------------------------------------------------
    // Non-streaming chat
    // -------------------------------------------------------------------------

    func chat(
        message: String,
        persona: SyniPersona,
        hsiContext: [String: Any]?
    ) async throws -> SyniChatResponse {
        let body = try buildRequest(message: message, persona: persona, hsiContext: hsiContext, stream: false)
        guard let url = URL(string: "\(config.baseUrl)/v1/chat") else {
            throw SyniCloudException("invalid baseUrl: \(config.baseUrl)")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = body
        await applyHeaders(&req)
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            throw SyniCloudException("POST /v1/chat HTTP \(code)")
        }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        sessionId = (json["session_id"] as? String) ?? sessionId
        return SyniChatResponse.fromCloudReply(
            (json["reply"] as? String) ?? "",
            personaId: persona.id,
            runtimeVersion: "cloud"
        )
    }

    // -------------------------------------------------------------------------
    // Streaming chat (SSE)
    // -------------------------------------------------------------------------

    func chatStream(
        message: String,
        persona: SyniPersona,
        hsiContext: [String: Any]?
    ) -> AsyncThrowingStream<SyniChatEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.runStream(
                        message: message,
                        persona: persona,
                        hsiContext: hsiContext,
                        continuation: continuation
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func runStream(
        message: String,
        persona: SyniPersona,
        hsiContext: [String: Any]?,
        continuation: AsyncThrowingStream<SyniChatEvent, Error>.Continuation
    ) async throws {
        let body = try buildRequest(message: message, persona: persona, hsiContext: hsiContext, stream: true)
        guard let url = URL(string: "\(config.baseUrl)/v1/chat/stream") else {
            throw SyniCloudException("invalid baseUrl: \(config.baseUrl)")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = body
        await applyHeaders(&req)
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        let (bytes, resp) = try await session.bytes(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            throw SyniCloudException("POST /v1/chat/stream HTTP \(code)")
        }

        var frameLines: [String] = []
        var messageBuf = ""
        for try await line in bytes.lines {
            if line.isEmpty {
                try processFrame(frameLines, persona: persona, messageBuf: &messageBuf, continuation: continuation)
                frameLines.removeAll(keepingCapacity: true)
            } else {
                frameLines.append(line)
            }
        }
        // Stream ended without an explicit `done` — synthesize a final.
        if !messageBuf.isEmpty {
            continuation.yield(.final(SyniChatResponse.fromCloudReply(
                messageBuf, personaId: persona.id, runtimeVersion: "cloud"
            )))
        }
    }

    private func processFrame(
        _ lines: [String],
        persona: SyniPersona,
        messageBuf: inout String,
        continuation: AsyncThrowingStream<SyniChatEvent, Error>.Continuation
    ) throws {
        for line in lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload.isEmpty { continue }
            guard let data = payload.data(using: .utf8),
                  let evt = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            else { continue }
            switch evt["type"] as? String {
            case "content":
                let content = (evt["content"] as? String) ?? ""
                messageBuf += content
                continuation.yield(.delta(content))
            case "done":
                if let sid = evt["session_id"] as? String { sessionId = sid }
                continuation.yield(.final(SyniChatResponse.fromCloudReply(
                    messageBuf, personaId: persona.id, runtimeVersion: "cloud"
                )))
                // Allow the outer loop to terminate naturally.
            case "error":
                throw SyniCloudException((evt["error"] as? String) ?? "unknown server error")
            default:
                break
            }
        }
    }

    // -------------------------------------------------------------------------
    // Internals
    // -------------------------------------------------------------------------

    private func applyHeaders(_ req: inout URLRequest) async {
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let tok = await config.authToken(), !tok.isEmpty {
            req.setValue("Bearer \(tok)", forHTTPHeaderField: "Authorization")
        }
    }

    private func buildRequest(
        message: String,
        persona: SyniPersona,
        hsiContext: [String: Any]?,
        stream: Bool
    ) throws -> Data {
        var body: [String: Any] = [
            "message": message,
            "persona_id": persona.id,
            "tenant_id": config.tenantId,
            "user_id": config.userId,
            "execution_mode": "cloud_only",
            "include_state": true,
            "stream": stream,
        ]
        if !config.projectId.isEmpty { body["project_id"] = config.projectId }
        if !config.orgId.isEmpty { body["org_id"] = config.orgId }
        if !config.appId.isEmpty { body["app_id"] = config.appId }
        if !config.deviceId.isEmpty { body["device_id"] = config.deviceId }
        if let sid = sessionId { body["session_id"] = sid }
        if let hsi = hsiContext { body["context"] = hsi }
        return try JSONSerialization.data(withJSONObject: body)
    }
}
