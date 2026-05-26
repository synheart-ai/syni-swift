import Foundation
import CryptoKit

/// Downloads + verifies a model (GGUF + its `tokenizer.json` sibling).
/// Mirrors `SyniInstaller` from `package:syni`.
public actor SyniInstaller {
    private let session: URLSession
    private let modelsRoot: URL

    public init(
        modelsRoot: URL? = nil,
        session: URLSession = .shared
    ) {
        self.session = session
        if let root = modelsRoot {
            self.modelsRoot = root
        } else {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.modelsRoot = docs.appendingPathComponent("synheart_syni_models", isDirectory: true)
        }
    }

    private func ensureDir() throws -> URL {
        if !FileManager.default.fileExists(atPath: modelsRoot.path) {
            try FileManager.default.createDirectory(at: modelsRoot, withIntermediateDirectories: true)
        }
        return modelsRoot
    }

    /// Whether the GGUF model + its sibling `tokenizer.json` are already on
    /// disk for `spec`.
    public func isModelOnDisk(_ spec: SyniModelSpec) -> Bool {
        let model = modelsRoot.appendingPathComponent(spec.filename)
        let tokenizer = modelsRoot.appendingPathComponent("tokenizer.json")
        let fm = FileManager.default
        return fm.fileExists(atPath: model.path) && fm.fileExists(atPath: tokenizer.path)
    }

    /// On-disk path the GGUF would live at — does NOT touch the filesystem.
    public func modelPathFor(_ spec: SyniModelSpec) -> String {
        modelsRoot.appendingPathComponent(spec.filename).path
    }

    /// Total on-disk bytes occupied by `spec`'s model files (the GGUF plus its
    /// sibling `tokenizer.json`). Returns 0 when nothing is installed. Useful
    /// for telling the user how much storage a delete will reclaim.
    public func installedBytes(_ spec: SyniModelSpec) -> Int64 {
        let fm = FileManager.default
        var total: Int64 = 0
        for path in [
            modelsRoot.appendingPathComponent(spec.filename).path,
            modelsRoot.appendingPathComponent("tokenizer.json").path,
        ] {
            if fm.fileExists(atPath: path),
               let attrs = try? fm.attributesOfItem(atPath: path),
               let size = attrs[.size] as? Int64 {
                total += size
            }
        }
        return total
    }

    /// Permanently deletes `spec`'s model files from disk — the GGUF and its
    /// sibling `tokenizer.json` — reclaiming the ~1.1 GB the install occupies.
    ///
    /// Returns the number of bytes actually freed. Idempotent: deleting when
    /// nothing is on disk is a no-op that returns 0. Throws
    /// `SyniInstallException` if a file exists but cannot be removed.
    public func deleteModel(_ spec: SyniModelSpec) throws -> Int64 {
        let freed = installedBytes(spec)
        let fm = FileManager.default
        for url in [
            modelsRoot.appendingPathComponent(spec.filename),
            modelsRoot.appendingPathComponent("tokenizer.json"),
        ] {
            if fm.fileExists(atPath: url.path) {
                do {
                    try fm.removeItem(at: url)
                } catch {
                    throw SyniInstallException(
                        "failed to delete model file \(url.path): \(error)"
                    )
                }
            }
        }
        return freed
    }

    /// Downloads (if needed) + verifies the model. Returns the on-disk path.
    public func ensureModel(
        _ spec: SyniModelSpec,
        onProgress: @Sendable (SyniInstallStage, Double) -> Void
    ) async throws -> String {
        let dir = try ensureDir()
        let modelURL = dir.appendingPathComponent(spec.filename)
        let tokenizerURL = dir.appendingPathComponent("tokenizer.json")
        let fm = FileManager.default

        if !fm.fileExists(atPath: modelURL.path) {
            onProgress(.downloadingModel, 0.0)
            try await download(spec.downloadUrl, to: modelURL) { p in
                onProgress(.downloadingModel, p * 0.95)
            }
        }

        if !fm.fileExists(atPath: tokenizerURL.path) {
            try await download(spec.tokenizerUrl, to: tokenizerURL) { p in
                onProgress(.downloadingModel, 0.95 + p * 0.05)
            }
        }
        onProgress(.downloadingModel, 1.0)

        if !spec.sha256.isEmpty {
            onProgress(.verifyingModel, 0.0)
            let actual = try sha256(of: modelURL)
            onProgress(.verifyingModel, 1.0)
            if actual.lowercased() != spec.sha256.lowercased() {
                try? fm.removeItem(at: modelURL)
                throw SyniInstallException(
                    "model SHA-256 mismatch: expected \(spec.sha256), got \(actual)"
                )
            }
        }

        return modelURL.path
    }

    private func download(
        _ urlString: String,
        to dest: URL,
        onProgress: @Sendable (Double) -> Void
    ) async throws {
        guard let url = URL(string: urlString) else {
            throw SyniInstallException("invalid download URL: \(urlString)")
        }
        let (tmp, resp) = try await session.download(from: url)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            throw SyniInstallException("model download HTTP \(http.statusCode) for \(urlString)")
        }
        let fm = FileManager.default
        if fm.fileExists(atPath: dest.path) { try? fm.removeItem(at: dest) }
        try fm.moveItem(at: tmp, to: dest)
        onProgress(1.0)
    }

    private func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 64 * 1024) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

public struct SyniInstallException: Error, CustomStringConvertible, Equatable, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { "SyniInstallException: \(message)" }
}
