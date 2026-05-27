import Foundation

/// Multi-photo fusion helpers — produces a single stable value from the
/// front/side/back pose pass. Deterministic: same inputs → same output.
///
/// Unlike a naive mean, this trims the worst-confidence outlier when 3
/// samples are present so a junk angle (mirror selfie, occluded back shot)
/// can't drag the aggregate. When fewer than 3 samples are usable, the
/// fallback is a confidence-weighted mean so the strongest detection
/// still dominates honestly.
nonisolated enum PhotoFusion {

    /// One per-angle sample. `confidence` is `PoseResult.confidenceAverage`.
    struct Sample: Sendable {
        let value: Double
        let confidence: Double
    }

    /// Confidence-weighted, outlier-trimmed fusion.
    /// - Drops the lowest-confidence sample when 3+ are provided AND its
    ///   confidence is below 60% of the strongest sample.
    /// - Returns `defaultValue` when no samples are usable.
    static func fuse(_ samples: [Sample], default defaultValue: Double) -> Double {
        let usable = samples.filter { $0.confidence > 0.01 && $0.value.isFinite }
        guard !usable.isEmpty else { return defaultValue }
        let sorted = usable.sorted { $0.confidence > $1.confidence }
        let trimmed: [Sample] = {
            guard sorted.count >= 3, let best = sorted.first else { return sorted }
            let worst = sorted.last!
            // Only trim when the worst sample is much weaker than the best.
            if worst.confidence < best.confidence * 0.6 {
                return Array(sorted.dropLast())
            }
            return sorted
        }()
        let totalWeight = trimmed.map(\.confidence).reduce(0, +)
        guard totalWeight > 0.001 else { return defaultValue }
        let weighted = trimmed.map { $0.value * $0.confidence }.reduce(0, +)
        return weighted / totalWeight
    }

    /// Cross-sample dispersion (std-dev). Used to inflate confidence reasons
    /// when angles strongly disagree — high dispersion → "angles disagree".
    static func dispersion(_ samples: [Sample]) -> Double {
        let usable = samples.filter { $0.confidence > 0.01 && $0.value.isFinite }
        guard usable.count >= 2 else { return 0 }
        let mean = usable.map(\.value).reduce(0, +) / Double(usable.count)
        let variance = usable.map { pow($0.value - mean, 2) }.reduce(0, +) / Double(usable.count)
        return sqrt(variance)
    }
}
