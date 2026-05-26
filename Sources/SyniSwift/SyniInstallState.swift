import Foundation

/// Installation lifecycle of the Syni agent.
///
/// Mirrors `SyniInstallState` from `package:syni`. The host SDK's
/// "Activation" authority is gated on this reaching `.installed`; until
/// then, chat calls throw.
public enum SyniInstallState: Equatable, Sendable {
    /// No model downloaded, no persona bound. Default state.
    case notInstalled

    /// Install in progress. `progress` is in `[0.0, 1.0]`; `stage` explains
    /// which sub-step is running.
    case installing(stage: SyniInstallStage, progress: Double)

    /// Successfully installed. The runtime engine has loaded the model and
    /// is ready to receive chat calls.
    case installed(personaId: String, modelPath: String, runtimeVersion: String)

    /// Install failed. `reason` is human-readable; `cause` is the
    /// underlying error message when available.
    case failed(reason: String, cause: String?)

    public var isInstalled: Bool {
        if case .installed = self { return true }
        return false
    }
}

public enum SyniInstallStage: String, CaseIterable, Sendable {
    /// Pre-flight checks.
    case preflight
    /// Model + tokenizer download.
    case downloadingModel
    /// SHA-256 verification of the downloaded model.
    case verifyingModel
    /// Persona binding.
    case materializingPersona
    /// libsyni_ffi engine spawn + model load.
    case loadingEngine
}
