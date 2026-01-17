import Foundation

/// Enforces performance budgets for generation requests.
final class BudgetEnforcer: @unchecked Sendable {
    private var contexts: [String: BudgetContext] = [:]
    private let lock = NSLock()

    init() {}

    /// Starts tracking a budget for a request.
    func startTracking(budget: PerformanceBudget, requestId: String) -> BudgetContext {
        let context = BudgetContext(
            requestId: requestId,
            budget: budget,
            startTime: CFAbsoluteTimeGetCurrent()
        )

        lock.lock()
        contexts[requestId] = context
        lock.unlock()

        return context
    }

    /// Checks if the budget has been exceeded.
    /// - Throws: `SyniError.budgetExceeded` if the budget is exceeded.
    func checkBudget(context: BudgetContext) throws {
        let elapsed = getElapsedMs(context: context)

        if let maxLatency = context.budget.maxLatencyMs, elapsed > maxLatency {
            throw SyniError.budgetExceeded(
                reason: "Latency budget exceeded: \(elapsed)ms > \(maxLatency)ms"
            )
        }
    }

    /// Returns the elapsed time in milliseconds.
    func getElapsedMs(context: BudgetContext) -> Int {
        let elapsed = CFAbsoluteTimeGetCurrent() - context.startTime
        return Int(elapsed * 1000)
    }

    /// Stops tracking and cleans up the context.
    func stopTracking(requestId: String) {
        lock.lock()
        contexts.removeValue(forKey: requestId)
        lock.unlock()
    }

    /// Returns whether the request can retry based on its budget.
    func canRetry(context: BudgetContext, attemptNumber: Int) -> Bool {
        guard context.budget.allowRetry else { return false }
        return attemptNumber <= context.budget.maxRetries
    }

    /// Estimates if there's enough time remaining for a retry.
    func hasTimeForRetry(context: BudgetContext, estimatedRetryMs: Int) -> Bool {
        guard let maxLatency = context.budget.maxLatencyMs else {
            return true // No latency limit
        }

        let elapsed = getElapsedMs(context: context)
        let remaining = maxLatency - elapsed

        return remaining >= estimatedRetryMs
    }
}

/// Context for tracking a request's budget.
struct BudgetContext: Sendable {
    let requestId: String
    let budget: PerformanceBudget
    let startTime: CFAbsoluteTime
}
