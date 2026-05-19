import Foundation

/// Manages available inference engines.
final class EngineManager: @unchecked Sendable {
    private let appleFMConfig: AppleFMConfig?
    private let localEngineConfig: LocalEngineConfig?
    private let modelManager: ModelManager

    private var appleFMEngine: AppleFMEngine?
    private var localEngine: LocalEngine?
    private let lock = NSLock()

    init(
        appleFMConfig: AppleFMConfig?,
        localEngineConfig: LocalEngineConfig?,
        modelManager: ModelManager
    ) {
        self.appleFMConfig = appleFMConfig
        self.localEngineConfig = localEngineConfig
        self.modelManager = modelManager
    }

    /// Returns the Apple Foundation Models engine if available.
    func getAppleFMEngine() async -> AppleFMEngine? {
        lock.lock()
        if let existing = appleFMEngine {
            lock.unlock()
            return await existing.isAvailable ? existing : nil
        }

        guard let config = appleFMConfig, config.preferWhenAvailable else {
            lock.unlock()
            return nil
        }

        let engine = AppleFMEngine()
        appleFMEngine = engine
        lock.unlock()

        return await engine.isAvailable ? engine : nil
    }

    /// Returns the LocalEngine if available.
    func getLocalEngine() async -> LocalEngine? {
        lock.lock()
        if let existing = localEngine {
            lock.unlock()
            return await existing.isAvailable ? existing : nil
        }

        guard let config = localEngineConfig else {
            lock.unlock()
            return nil
        }

        let engine = LocalEngine(config: config, modelManager: modelManager)
        localEngine = engine
        lock.unlock()

        return await engine.isAvailable ? engine : nil
    }

    /// Shuts down all engines and releases resources.
    func shutdown() {
        lock.lock()
        appleFMEngine = nil
        localEngine = nil
        lock.unlock()
    }
}
