import Foundation

/// Errors that can occur during Syni SDK operations.
public enum SyniError: Error, Sendable {
    /// SDK has not been initialized. Call `Syni.initialize(config:)` first.
    case notInitialized

    /// The requested persona is not available or not loaded.
    case personaNotFound(String)

    /// The schema for the persona could not be loaded or is invalid.
    case schemaNotFound(String)

    /// The grammar for the persona could not be loaded.
    case grammarNotFound(String)

    /// No suitable engine is available for the request.
    case engineUnavailable

    /// The local engine failed to generate a response.
    case localEngineFailed(underlying: Error?)

    /// The cloud gateway request failed.
    case cloudRequestFailed(underlying: Error?)

    /// The response did not conform to the expected schema after retries.
    case schemaValidationFailed(details: String)

    /// The request exceeded its latency or token budget.
    case budgetExceeded(reason: String)

    /// The request was cancelled.
    case cancelled

    /// Model download or verification failed.
    case modelDownloadFailed(underlying: Error?)

    /// Model checksum verification failed.
    case modelChecksumMismatch

    /// Insufficient storage space for model.
    case insufficientStorage

    /// IPC communication with host app failed.
    case ipcFailed(underlying: Error?)

    /// Configuration is invalid.
    case invalidConfiguration(reason: String)

    /// An unexpected internal error occurred.
    case internalError(message: String)
}

extension SyniError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Syni SDK has not been initialized"
        case .personaNotFound(let id):
            return "Persona not found: \(id)"
        case .schemaNotFound(let id):
            return "Schema not found for persona: \(id)"
        case .grammarNotFound(let id):
            return "Grammar not found for persona: \(id)"
        case .engineUnavailable:
            return "No suitable engine available"
        case .localEngineFailed(let underlying):
            return "Local engine failed: \(underlying?.localizedDescription ?? "unknown error")"
        case .cloudRequestFailed(let underlying):
            return "Cloud request failed: \(underlying?.localizedDescription ?? "unknown error")"
        case .schemaValidationFailed(let details):
            return "Schema validation failed: \(details)"
        case .budgetExceeded(let reason):
            return "Budget exceeded: \(reason)"
        case .cancelled:
            return "Request was cancelled"
        case .modelDownloadFailed(let underlying):
            return "Model download failed: \(underlying?.localizedDescription ?? "unknown error")"
        case .modelChecksumMismatch:
            return "Model checksum verification failed"
        case .insufficientStorage:
            return "Insufficient storage space for model"
        case .ipcFailed(let underlying):
            return "IPC communication failed: \(underlying?.localizedDescription ?? "unknown error")"
        case .invalidConfiguration(let reason):
            return "Invalid configuration: \(reason)"
        case .internalError(let message):
            return "Internal error: \(message)"
        }
    }
}
