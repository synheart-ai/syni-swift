import Foundation
import CommonCrypto

/// Manages model downloading, storage, and lifecycle.
///
/// Per RFC responsibilities:
/// - Download (Wi-Fi only option)
/// - Verify checksum
/// - Store in app container
/// - Delete / switch models
/// - Report storage usage
public final class ModelManager: @unchecked Sendable {
    private let modelsPath: URL?
    private let appGroupIdentifier: String?
    private var activeModelId: String?
    private var downloadedModels: [String: ModelInfo] = [:]
    private let lock = NSLock()
    private let fileManager = FileManager.default

    init(modelsPath: URL?, appGroupIdentifier: String?) {
        self.modelsPath = modelsPath
        self.appGroupIdentifier = appGroupIdentifier

        // Scan existing models
        Task {
            await scanExistingModels()
        }
    }

    // MARK: - Public API

    /// Returns the path to the currently active model.
    public func getActiveModelPath() async -> URL? {
        lock.lock()
        defer { lock.unlock() }

        guard let modelId = activeModelId,
              let info = downloadedModels[modelId] else {
            return nil
        }

        return info.localPath
    }

    /// Returns information about all downloaded models.
    public func getDownloadedModels() -> [ModelInfo] {
        lock.lock()
        defer { lock.unlock() }
        return Array(downloadedModels.values)
    }

    /// Sets the active model by ID.
    public func setActiveModel(id: String) throws {
        lock.lock()
        defer { lock.unlock() }

        guard downloadedModels[id] != nil else {
            throw SyniError.internalError(message: "Model not found: \(id)")
        }

        activeModelId = id
    }

    /// Downloads a model from the specified URL.
    ///
    /// - Parameters:
    ///   - url: The URL to download from.
    ///   - modelId: Unique identifier for this model.
    ///   - expectedChecksum: SHA256 checksum for verification.
    ///   - wifiOnly: If true, only download on Wi-Fi.
    ///   - progress: Called with download progress (0.0 - 1.0).
    public func downloadModel(
        from url: URL,
        modelId: String,
        expectedChecksum: String,
        wifiOnly: Bool = true,
        progress: ((Double) -> Void)? = nil
    ) async throws {
        let destinationPath = try getModelDirectory().appendingPathComponent("\(modelId).gguf")

        // Check if already downloaded
        if fileManager.fileExists(atPath: destinationPath.path) {
            if try verifyChecksum(at: destinationPath, expected: expectedChecksum) {
                registerModel(id: modelId, path: destinationPath, checksum: expectedChecksum)
                return
            } else {
                // Corrupted, delete and re-download
                try fileManager.removeItem(at: destinationPath)
            }
        }

        // Download (with optional progress reporting)
        let (tempURL, response) = try await downloadFile(from: url, wifiOnly: wifiOnly, progress: progress)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw SyniError.modelDownloadFailed(underlying: nil)
        }

        // Move to final location
        try fileManager.moveItem(at: tempURL, to: destinationPath)

        // Verify checksum
        guard try verifyChecksum(at: destinationPath, expected: expectedChecksum) else {
            try? fileManager.removeItem(at: destinationPath)
            throw SyniError.modelChecksumMismatch
        }

        registerModel(id: modelId, path: destinationPath, checksum: expectedChecksum)
    }

    /// Deletes a downloaded model.
    public func deleteModel(id: String) throws {
        lock.lock()
        guard let info = downloadedModels.removeValue(forKey: id) else {
            lock.unlock()
            return
        }

        if activeModelId == id {
            activeModelId = nil
        }
        lock.unlock()

        try fileManager.removeItem(at: info.localPath)
    }

    /// Returns the total storage used by downloaded models in bytes.
    public func getStorageUsage() -> UInt64 {
        lock.lock()
        let models = Array(downloadedModels.values)
        lock.unlock()

        var total: UInt64 = 0
        for model in models {
            if let attrs = try? fileManager.attributesOfItem(atPath: model.localPath.path),
               let size = attrs[.size] as? UInt64 {
                total += size
            }
        }
        return total
    }

    /// Checks if there's sufficient storage for a model of the given size.
    public func hasStorageSpace(forBytes bytes: UInt64) -> Bool {
        guard let path = try? getModelDirectory() else { return false }

        do {
            let attrs = try fileManager.attributesOfFileSystem(forPath: path.path)
            if let freeSpace = attrs[.systemFreeSize] as? UInt64 {
                // Require 10% buffer
                return freeSpace > UInt64(Double(bytes) * 1.1)
            }
        } catch {
            return false
        }
        return false
    }

    // MARK: - Private

    private func getModelDirectory() throws -> URL {
        if let path = modelsPath {
            if !fileManager.fileExists(atPath: path.path) {
                try fileManager.createDirectory(at: path, withIntermediateDirectories: true)
            }
            return path
        }

        // Use app group container if available (for keyboard extension sharing)
        if let groupId = appGroupIdentifier,
           let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: groupId) {
            let modelsDir = containerURL.appendingPathComponent("Models")
            if !fileManager.fileExists(atPath: modelsDir.path) {
                try fileManager.createDirectory(at: modelsDir, withIntermediateDirectories: true)
            }
            return modelsDir
        }

        // Fall back to documents directory
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let modelsDir = documentsPath.appendingPathComponent("SyniModels")
        if !fileManager.fileExists(atPath: modelsDir.path) {
            try fileManager.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        }
        return modelsDir
    }

    private func scanExistingModels() async {
        guard let dir = try? getModelDirectory() else { return }

        do {
            let contents = try fileManager.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.fileSizeKey]
            )

            lock.lock()
            for fileURL in contents where fileURL.pathExtension == "gguf" {
                let modelId = fileURL.deletingPathExtension().lastPathComponent
                let info = ModelInfo(
                    id: modelId,
                    localPath: fileURL,
                    checksum: nil, // Unknown without metadata file
                    sizeBytes: (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(UInt64.init) ?? 0
                )
                downloadedModels[modelId] = info
            }

            // Set first model as active if none set
            if activeModelId == nil, let firstId = downloadedModels.keys.first {
                activeModelId = firstId
            }
            lock.unlock()
        } catch {
            // Ignore scan errors
        }
    }

    private func registerModel(id: String, path: URL, checksum: String) {
        let size = (try? fileManager.attributesOfItem(atPath: path.path)[.size] as? UInt64) ?? 0
        let info = ModelInfo(id: id, localPath: path, checksum: checksum, sizeBytes: size)

        lock.lock()
        downloadedModels[id] = info
        if activeModelId == nil {
            activeModelId = id
        }
        lock.unlock()
    }

    private func verifyChecksum(at path: URL, expected: String) throws -> Bool {
        // Simple checksum verification using CommonCrypto
        // In production, use CC_SHA256 for proper verification
        guard let data = try? Data(contentsOf: path) else {
            return false
        }

        let computed = sha256(data: data)
        return computed.lowercased() == expected.lowercased()
    }

    private func sha256(data: Data) -> String {
        // Use CommonCrypto for SHA256
        var hash = [UInt8](repeating: 0, count: 32)
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    private func downloadFile(
        from url: URL,
        wifiOnly: Bool,
        progress: ((Double) -> Void)?
    ) async throws -> (URL, URLResponse) {
        let sessionConfig = URLSessionConfiguration.default
        if wifiOnly {
            sessionConfig.allowsCellularAccess = false
            sessionConfig.allowsExpensiveNetworkAccess = false
        }

        // We need to capture the temp file URL from didFinishDownloadingTo:
        // Implement a thin wrapper delegate that resumes the continuation there.
        final class BridgeDelegate: NSObject, URLSessionDownloadDelegate {
            let onProgress: ((Double) -> Void)?
            private let lock = NSLock()
            private var continuation: CheckedContinuation<(URL, URLResponse), Error>?

            init(onProgress: ((Double) -> Void)?) {
                self.onProgress = onProgress
            }

            func setContinuation(_ cont: CheckedContinuation<(URL, URLResponse), Error>) {
                lock.lock()
                continuation = cont
                lock.unlock()
            }

            func urlSession(
                _ session: URLSession,
                downloadTask: URLSessionDownloadTask,
                didWriteData bytesWritten: Int64,
                totalBytesWritten: Int64,
                totalBytesExpectedToWrite: Int64
            ) {
                guard totalBytesExpectedToWrite > 0 else { return }
                let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
                if let onProgress {
                    DispatchQueue.main.async {
                        onProgress(max(0.0, min(1.0, fraction)))
                    }
                }
            }

            func urlSession(
                _ session: URLSession,
                downloadTask: URLSessionDownloadTask,
                didFinishDownloadingTo location: URL
            ) {
                lock.lock()
                let cont = continuation
                continuation = nil
                lock.unlock()

                guard let response = downloadTask.response else {
                    cont?.resume(throwing: SyniError.modelDownloadFailed(underlying: nil))
                    return
                }
                cont?.resume(returning: (location, response))
            }

            func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
                if let error {
                    lock.lock()
                    let cont = continuation
                    continuation = nil
                    lock.unlock()
                    cont?.resume(throwing: error)
                }
            }
        }

        let delegate = BridgeDelegate(onProgress: progress)
        let session = URLSession(configuration: sessionConfig, delegate: delegate, delegateQueue: nil)

        return try await withCheckedThrowingContinuation { cont in
            delegate.setContinuation(cont)
            let task = session.downloadTask(with: url)
            task.resume()
        }
    }
}

/// Information about a downloaded model.
public struct ModelInfo: Sendable {
    /// Unique identifier for this model.
    public let id: String

    /// Local file path.
    public let localPath: URL

    /// SHA256 checksum (if known).
    public let checksum: String?

    /// Size in bytes.
    public let sizeBytes: UInt64
}
