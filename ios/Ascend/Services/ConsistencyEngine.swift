import Foundation

/// Consistency engine. Cross-checks the on-device Vision "truth layer"
/// against the cloud reasoning model output, flags contradictions, applies
/// confidence weighting, rejects extreme outliers, and smooths results
/// across scans so a single bad photo can't tank a user's score.
///
/// All inputs are normalized to 0…100 internally. Designed to be cheap and
/// fully deterministic — same inputs, same outputs.
nonisolated enum ConsistencyEngine {

    /// Cross-check a model-proposed score against the on-device anchor.
    /// Returns the reconciled score plus a `disagreement` value (0…1).
    static func reconcile(modelScore: Double, anchorScore: Double, anchorConfidence: Double) -> (score: Double, disagreement: Double) {
        let m = clamp(modelScore, 0, 100)
        let a = clamp(anchorScore, 0, 100)
        let conf = clamp(anchorConfidence, 0, 1)
        // Disagreement scaled by anchor confidence — high-confidence anchor
        // makes contradictions matter more.
        let raw = abs(m - a) / 100.0
        let disagreement = raw * (0.4 + conf * 0.6)
        // Weighted blend toward anchor when anchor is high-confidence.
        let weight = 0.35 + conf * 0.35 // 0.35…0.70 toward anchor
        let blended = m * (1 - weight) + a * weight
        return (clamp(blended, 0, 100), clamp(disagreement, 0, 1))
    }

    /// Smooth a new score against recent history (EMA with outlier rejection).
    /// Rejects any value more than `maxJump` away from the recent mean and
    /// pulls it inward; otherwise applies an EMA with `alpha = 0.55` so real
    /// progress shows up immediately but noise is damped.
    static func smooth(newScore: Double, recent: [Double], maxJump: Double = 18) -> Double {
        guard !recent.isEmpty else { return clamp(newScore, 0, 100) }
        let mean = recent.reduce(0, +) / Double(recent.count)
        var value = clamp(newScore, 0, 100)
        if abs(value - mean) > maxJump {
            // Pull the outlier toward the mean but don't fully erase the change.
            let direction: Double = value > mean ? 1 : -1
            value = mean + direction * maxJump
        }
        // EMA with the most recent sample to avoid jitter while still moving.
        let alpha = 0.55
        let prev = recent.last ?? mean
        return clamp(alpha * value + (1 - alpha) * prev, 0, 100)
    }

    /// Penalize confidence when the model and the on-device anchor disagree
    /// strongly. The output is a 0…100 confidence value the UI can show.
    static func confidenceAfterFusion(modelConfidence: Double, disagreement: Double, anchorConfidence: Double) -> Double {
        let m = clamp(modelConfidence, 0, 100)
        let penalty = disagreement * 60 // up to 60-point hit on strong disagreement
        let anchorBoost = anchorConfidence * 8 // up to +8 when anchor is sharp
        return clamp(m - penalty + anchorBoost, 0, 100)
    }

    private static func clamp<T: Comparable>(_ v: T, _ lo: T, _ hi: T) -> T {
        min(max(v, lo), hi)
    }
}
