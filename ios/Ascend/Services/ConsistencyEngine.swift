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

    // MARK: - Cross-metric harmonization
    //
    // PSL, physique, and calorie-derived scores all measure different things,
    // but they describe the SAME person. In practice they should land in a
    // similar range; a 90 physique with a 35 PSL is almost always noise from
    // one bad photo, not reality. We gently pull them toward each other when
    // the gap is moderate, leave them alone when the gap is small (already
    // coherent), and ALSO leave them alone when the gap is huge (probably a
    // real, meaningful difference worth surfacing instead of hiding).
    //
    // Bands (absolute point difference on 0…100 scale):
    //   ≤  smallGap  →  no change (already consistent)
    //   ≤  bigGap    →  pull each side a fraction toward the weighted center
    //   >  bigGap    →  no change (real divergence, respect the data)
    static func harmonize(
        primary: Double,
        primaryConfidence: Double,
        secondary: Double,
        secondaryConfidence: Double,
        smallGap: Double = 8,
        bigGap: Double = 25
    ) -> (primary: Double, secondary: Double, adjusted: Bool) {
        let p = clamp(primary, 0, 100)
        let s = clamp(secondary, 0, 100)
        let gap = abs(p - s)
        guard gap > smallGap, gap <= bigGap else {
            return (p, s, false)
        }
        let pc = clamp(primaryConfidence, 0, 1)
        let sc = clamp(secondaryConfidence, 0, 1)
        // Confidence-weighted center; if both equal we fall back to mean.
        let totalConf = max(0.0001, pc + sc)
        let center = (p * pc + s * sc) / totalConf
        // Pull strength scales with how far into the moderate band we are.
        // At smallGap → 0 pull, at bigGap → up to 0.45 pull.
        let t = (gap - smallGap) / max(0.0001, bigGap - smallGap)
        let maxPull = 0.45
        // The lower-confidence side moves more, the higher-confidence side moves less.
        let pullP = maxPull * t * (1 - pc / (pc + sc + 0.0001))
        let pullS = maxPull * t * (1 - sc / (pc + sc + 0.0001))
        let newP = p + (center - p) * pullP
        let newS = s + (center - s) * pullS
        return (clamp(newP, 0, 100), clamp(newS, 0, 100), true)
    }

    private static func clamp<T: Comparable>(_ v: T, _ lo: T, _ hi: T) -> T {
        min(max(v, lo), hi)
    }
}
