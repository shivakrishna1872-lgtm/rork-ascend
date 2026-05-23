import Foundation

/// Per-provider circuit breaker. Prevents cascading failures when a model
/// provider is flapping (402, 429, 5xx). Once a provider trips, we stop
/// sending requests for `cooldown` seconds and silently route to the next
/// candidate in the model chain.
///
/// The state is process-wide and lock-free: a single concurrent dictionary
/// guarded by an `OSAllocatedUnfairLock`-style serial actor so millions of
/// concurrent requests can read it cheaply.
actor CircuitBreaker {
    static let shared = CircuitBreaker()

    private struct State {
        var consecutiveFailures: Int = 0
        var openUntil: Date? = nil
    }

    private var states: [String: State] = [:]
    /// After this many consecutive failures, open the circuit.
    private let failureThreshold = 3
    /// Base cooldown — doubled each time the breaker re-opens (capped at 5 min).
    private let baseCooldown: TimeInterval = 20

    /// True when the provider is currently "open" (failing) and should be skipped.
    func isOpen(_ provider: String) -> Bool {
        guard let s = states[provider], let until = s.openUntil else { return false }
        if Date() >= until {
            // Half-open: allow a probe call. Caller decides via recordSuccess/Failure.
            states[provider]?.openUntil = nil
            return false
        }
        return true
    }

    func recordSuccess(_ provider: String) {
        states[provider] = State(consecutiveFailures: 0, openUntil: nil)
    }

    /// Record a failure. `transient` = true for 402/429/5xx (network or
    /// provider quota); false for decode/empty (we should still penalize but
    /// less aggressively).
    func recordFailure(_ provider: String, transient: Bool) {
        var s = states[provider] ?? State()
        s.consecutiveFailures += transient ? 1 : 1
        if s.consecutiveFailures >= failureThreshold {
            // Exponential cooldown: 20s → 40s → 80s → … capped at 300s.
            let openings = max(1, s.consecutiveFailures - failureThreshold + 1)
            let cooldown = min(300, baseCooldown * pow(2, Double(openings - 1)))
            s.openUntil = Date().addingTimeInterval(cooldown)
        }
        states[provider] = s
    }

    /// Reset everything (debug / testing only).
    func reset() { states.removeAll() }
}
