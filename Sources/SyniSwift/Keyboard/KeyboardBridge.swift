import Foundation

/// Bridge for communication between keyboard extension and host app.
///
/// Per RFC:
/// - Inference runs in host app
/// - Keyboard communicates via App Group / IPC abstraction
/// - Fallback: small model in-extension with strict limits
public final class KeyboardBridge: @unchecked Sendable {
    /// The shared instance for keyboard extension use.
    public static let shared = KeyboardBridge()

    private let appGroupIdentifier: String?
    private let userDefaults: UserDefaults?
    private let notificationCenter: CFNotificationCenter
    private let lock = NSLock()

    // Pending requests awaiting response from host app
    private var pendingRequests: [String: CheckedContinuation<SyniResponse, Error>] = [:]

    private init() {
        // Try to get app group from Syni config if available
        self.appGroupIdentifier = Syni.shared?.config.appGroupIdentifier

        if let groupId = appGroupIdentifier {
            self.userDefaults = UserDefaults(suiteName: groupId)
        } else {
            self.userDefaults = nil
        }

        self.notificationCenter = CFNotificationCenterGetDarwinNotifyCenter()

        setupNotificationObserver()
    }

    /// Initializes the bridge with a specific app group (call from keyboard extension).
    public static func initialize(appGroupIdentifier: String) -> KeyboardBridge {
        let bridge = KeyboardBridge(appGroupIdentifier: appGroupIdentifier)
        return bridge
    }

    private init(appGroupIdentifier: String) {
        self.appGroupIdentifier = appGroupIdentifier
        self.userDefaults = UserDefaults(suiteName: appGroupIdentifier)
        self.notificationCenter = CFNotificationCenterGetDarwinNotifyCenter()

        setupNotificationObserver()
    }

    // MARK: - Keyboard Extension API

    /// Sends a generation request to the host app.
    ///
    /// This method is called from the keyboard extension. It:
    /// 1. Writes the request to shared storage
    /// 2. Notifies the host app via Darwin notification
    /// 3. Waits for the response with timeout
    ///
    /// - Parameters:
    ///   - request: The generation request.
    ///   - timeoutMs: Maximum time to wait for response.
    /// - Returns: The response from the host app.
    public func sendRequest(
        _ request: SyniRequest,
        timeoutMs: Int = 150
    ) async throws -> SyniResponse {
        guard let defaults = userDefaults else {
            throw SyniError.ipcFailed(underlying: NSError(
                domain: "KeyboardBridge",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "App group not configured"]
            ))
        }

        // Serialize request
        let encoder = JSONEncoder()
        let requestData = try encoder.encode(IPCRequest(from: request))

        // Write to shared storage
        defaults.set(requestData, forKey: "syni.ipc.request.\(request.requestId)")
        defaults.synchronize()

        // Notify host app
        postNotification(name: "com.synheart.syni.request")

        // Wait for response with timeout
        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            pendingRequests[request.requestId] = continuation
            lock.unlock()

            // Set up timeout
            Task {
                try await Task.sleep(nanoseconds: UInt64(timeoutMs) * 1_000_000)

                lock.lock()
                if let cont = pendingRequests.removeValue(forKey: request.requestId) {
                    lock.unlock()
                    cont.resume(throwing: SyniError.budgetExceeded(reason: "IPC timeout"))
                } else {
                    lock.unlock()
                }
            }
        }
    }

    // MARK: - Host App API

    /// Starts listening for requests from keyboard extension.
    /// Call this from the host app on launch.
    public func startHostListener() {
        // Already set up in init via setupNotificationObserver
    }

    /// Processes a request from the keyboard extension.
    /// Called internally when a request notification is received.
    private func processIncomingRequest() {
        guard let defaults = userDefaults else { return }

        // Find pending requests
        let allKeys = defaults.dictionaryRepresentation().keys
        for key in allKeys where key.hasPrefix("syni.ipc.request.") {
            guard let data = defaults.data(forKey: key) else { continue }

            let requestId = String(key.dropFirst("syni.ipc.request.".count))

            // Remove from storage
            defaults.removeObject(forKey: key)

            // Process asynchronously
            Task {
                await handleRequest(data: data, requestId: requestId)
            }
        }
    }

    private func handleRequest(data: Data, requestId: String) async {
        guard let syni = Syni.shared else {
            sendErrorResponse(requestId: requestId, error: .notInitialized)
            return
        }

        do {
            let decoder = JSONDecoder()
            let ipcRequest = try decoder.decode(IPCRequest.self, from: data)
            let request = ipcRequest.toSyniRequest()

            let response = try await syni.generateAsync(request: request)
            sendResponse(response)
        } catch let error as SyniError {
            sendErrorResponse(requestId: requestId, error: error)
        } catch {
            sendErrorResponse(requestId: requestId, error: .internalError(message: error.localizedDescription))
        }
    }

    private func sendResponse(_ response: SyniResponse) {
        guard let defaults = userDefaults else { return }

        do {
            let encoder = JSONEncoder()
            let ipcResponse = IPCResponse(from: response)
            let data = try encoder.encode(ipcResponse)

            defaults.set(data, forKey: "syni.ipc.response.\(response.requestId)")
            defaults.synchronize()

            postNotification(name: "com.synheart.syni.response.\(response.requestId)")
        } catch {
            // Log error in debug mode
        }
    }

    private func sendErrorResponse(requestId: String, error: SyniError) {
        guard let defaults = userDefaults else { return }

        let errorResponse = IPCResponse(
            requestId: requestId,
            outputJSON: "{}",
            isFallback: true,
            error: error.localizedDescription
        )

        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(errorResponse)
            defaults.set(data, forKey: "syni.ipc.response.\(requestId)")
            defaults.synchronize()

            postNotification(name: "com.synheart.syni.response.\(requestId)")
        } catch {
            // Log error
        }
    }

    // MARK: - Notifications

    private func setupNotificationObserver() {
        // Observe for incoming requests (host app)
        let requestCallback: CFNotificationCallback = { _, observer, name, _, _ in
            guard let observer = observer else { return }
            let bridge = Unmanaged<KeyboardBridge>.fromOpaque(observer).takeUnretainedValue()
            bridge.processIncomingRequest()
        }

        CFNotificationCenterAddObserver(
            notificationCenter,
            Unmanaged.passUnretained(self).toOpaque(),
            requestCallback,
            "com.synheart.syni.request" as CFString,
            nil,
            .deliverImmediately
        )

        // Observe for responses (keyboard extension)
        // Response notifications include request ID, handled per-request
    }

    private func observeResponse(requestId: String) {
        let responseCallback: CFNotificationCallback = { _, observer, name, _, _ in
            guard let observer = observer else { return }
            let bridge = Unmanaged<KeyboardBridge>.fromOpaque(observer).takeUnretainedValue()

            // Extract request ID from notification name
            guard let name = name else { return }
            let nameStr = name.rawValue as String
            let requestId = nameStr.replacingOccurrences(of: "com.synheart.syni.response.", with: "")

            bridge.handleResponseNotification(requestId: requestId)
        }

        CFNotificationCenterAddObserver(
            notificationCenter,
            Unmanaged.passUnretained(self).toOpaque(),
            responseCallback,
            "com.synheart.syni.response.\(requestId)" as CFString,
            nil,
            .deliverImmediately
        )
    }

    private func handleResponseNotification(requestId: String) {
        guard let defaults = userDefaults,
              let data = defaults.data(forKey: "syni.ipc.response.\(requestId)") else {
            return
        }

        // Remove from storage
        defaults.removeObject(forKey: "syni.ipc.response.\(requestId)")

        do {
            let decoder = JSONDecoder()
            let ipcResponse = try decoder.decode(IPCResponse.self, from: data)

            lock.lock()
            guard let continuation = pendingRequests.removeValue(forKey: requestId) else {
                lock.unlock()
                return
            }
            lock.unlock()

            if let errorMsg = ipcResponse.error {
                continuation.resume(throwing: SyniError.ipcFailed(
                    underlying: NSError(domain: "IPC", code: -1, userInfo: [NSLocalizedDescriptionKey: errorMsg])
                ))
            } else {
                let response = try ipcResponse.toSyniResponse()
                continuation.resume(returning: response)
            }
        } catch {
            lock.lock()
            if let continuation = pendingRequests.removeValue(forKey: requestId) {
                lock.unlock()
                continuation.resume(throwing: SyniError.ipcFailed(underlying: error))
            } else {
                lock.unlock()
            }
        }
    }

    private func postNotification(name: String) {
        CFNotificationCenterPostNotification(
            notificationCenter,
            CFNotificationName(rawValue: name as CFString),
            nil,
            nil,
            true
        )
    }

    deinit {
        CFNotificationCenterRemoveEveryObserver(notificationCenter, Unmanaged.passUnretained(self).toOpaque())
    }
}

// MARK: - IPC Data Types

private struct IPCRequest: Codable {
    let requestId: String
    let personaId: String
    let inputText: String
    let inputContext: [String: String]
    let maxTokens: Int?
    let temperature: Double?
    let localOnly: Bool
    let cloudOnly: Bool
    let timeoutMs: Int?

    init(from request: SyniRequest) {
        self.requestId = request.requestId
        self.personaId = request.personaId
        self.inputText = request.input.text
        self.inputContext = request.input.context
        self.maxTokens = request.options?.maxTokens
        self.temperature = request.options?.temperature
        self.localOnly = request.options?.localOnly ?? false
        self.cloudOnly = request.options?.cloudOnly ?? false
        self.timeoutMs = request.options?.timeoutMs
    }

    func toSyniRequest() -> SyniRequest {
        SyniRequest(
            personaId: personaId,
            input: SyniInput(text: inputText, context: inputContext),
            options: GenerationOptions(
                maxTokens: maxTokens,
                temperature: temperature,
                localOnly: localOnly,
                cloudOnly: cloudOnly,
                timeoutMs: timeoutMs
            ),
            requestId: requestId
        )
    }
}

private struct IPCResponse: Codable {
    let requestId: String
    let outputJSON: String
    let isFallback: Bool
    let error: String?

    let engine: String?
    let latencyMs: Int?
    let tokensGenerated: Int?
    let promptTokens: Int?
    let didRetry: Bool?
    let personaId: String?

    init(from response: SyniResponse) {
        self.requestId = response.requestId
        self.outputJSON = (try? String(data: JSONSerialization.data(withJSONObject: response.outputJSON), encoding: .utf8)) ?? "{}"
        self.isFallback = response.isFallback
        self.error = nil

        self.engine = response.metadata.engine.rawValue
        self.latencyMs = response.metadata.latencyMs
        self.tokensGenerated = response.metadata.tokensGenerated
        self.promptTokens = response.metadata.promptTokens
        self.didRetry = response.metadata.didRetry
        self.personaId = response.metadata.personaId
    }

    init(requestId: String, outputJSON: String, isFallback: Bool, error: String?) {
        self.requestId = requestId
        self.outputJSON = outputJSON
        self.isFallback = isFallback
        self.error = error
        self.engine = nil
        self.latencyMs = nil
        self.tokensGenerated = nil
        self.promptTokens = nil
        self.didRetry = nil
        self.personaId = nil
    }

    func toSyniResponse() throws -> SyniResponse {
        guard let data = outputJSON.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SyniError.internalError(message: "Invalid IPC response JSON")
        }

        let metadata = ResponseMetadata(
            engine: EngineType(rawValue: engine ?? "fallback") ?? .fallback,
            latencyMs: latencyMs ?? 0,
            tokensGenerated: tokensGenerated ?? 0,
            promptTokens: promptTokens ?? 0,
            didRetry: didRetry ?? false,
            personaId: personaId ?? ""
        )

        return SyniResponse(
            requestId: requestId,
            outputJSON: json,
            metadata: metadata,
            isFallback: isFallback
        )
    }
}
