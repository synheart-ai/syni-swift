import Foundation

/// Identifies a downloadable inference model.
///
/// Mirrors `SyniModelSpec` from `package:syni`. V1 ships a small curated
/// catalog (`SyniModels`). Production builds should validate `sha256`
/// against a release manifest signed by Synheart's release key.
public struct SyniModelSpec: Equatable, Sendable {
    /// Stable identifier (e.g. `qwen2.5-1.5b-instruct-q4_k_m`).
    public let id: String

    /// Filename used on disk (typically `<id>.gguf`).
    public let filename: String

    /// HTTPS URL the GGUF model downloads from.
    public let downloadUrl: String

    /// HTTPS URL for the matching `tokenizer.json`.
    public let tokenizerUrl: String

    /// Lowercase hex SHA-256. Empty string skips verification.
    public let sha256: String

    /// Approximate file size in bytes.
    public let approxBytes: Int64

    public init(
        id: String,
        filename: String,
        downloadUrl: String,
        tokenizerUrl: String,
        sha256: String,
        approxBytes: Int64
    ) {
        self.id = id
        self.filename = filename
        self.downloadUrl = downloadUrl
        self.tokenizerUrl = tokenizerUrl
        self.sha256 = sha256
        self.approxBytes = approxBytes
    }

    /// Parse the `local` block of a `/v1/models` manifest entry.
    public static func fromManifest(id: String, local: [String: Any]) -> SyniModelSpec {
        SyniModelSpec(
            id: id,
            filename: local["filename"] as? String ?? "",
            downloadUrl: local["download_url"] as? String ?? "",
            tokenizerUrl: local["tokenizer_url"] as? String ?? "",
            sha256: local["sha256"] as? String ?? "",
            approxBytes: (local["approx_bytes"] as? NSNumber)?.int64Value ?? 0
        )
    }
}

/// V1 model catalog. Mirrors `SyniModels` from `package:syni`.
public enum SyniModels {
    /// Qwen2.5 1.5B Instruct, Q4_K_M quantization. ~1.1 GB.
    public static let qwen25_15bInstructQ4 = SyniModelSpec(
        id: "qwen2.5-1.5b-instruct-q4_k_m",
        filename: "qwen2.5-1.5b-instruct-q4_k_m.gguf",
        downloadUrl:
            "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf",
        tokenizerUrl:
            "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct/resolve/main/tokenizer.json",
        sha256: "6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e",
        approxBytes: 1_117_320_736
    )

    /// Gemma 3 1B Instruct, Q4_K_M quantization. ~770 MB.
    public static let gemma3_1bInstructQ4 = SyniModelSpec(
        id: "gemma-3-1b-it-q4_k_m",
        filename: "gemma-3-1b-it-q4_k_m.gguf",
        downloadUrl:
            "https://huggingface.co/Synheart/syni-life-gguf-gemma-3-1b/resolve/main/google_gemma-3-1b-it-Q4_K_M.gguf",
        tokenizerUrl:
            "https://huggingface.co/Synheart/syni-life-gguf-gemma-3-1b/resolve/main/tokenizer.json",
        sha256: "12bf0fff8815d5f73a3c9b586bd8fee8e7b248c935de70dec367679873d0f29d",
        approxBytes: 806_058_496
    )
}
