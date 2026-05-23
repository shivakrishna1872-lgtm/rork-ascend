import Foundation
import SwiftData

/// Per-user calibration profile — small, **bounded** weight adjustments that
/// personalize deterministic scoring over time WITHOUT modifying any formula.
///
/// ## Authority hierarchy
/// ```
/// Deterministic Engine > Vision Anchors > Calibration > Cache > AI
/// ```
///
/// Calibration is the only layer that "learns the user", and it does so via:
/// - bounded EMA updates driven exclusively by `FeedbackEvent`s
/// - hard min/max clamps so a corrupted profile can never break scoring
/// - a version stamp on every scan so a calibration change never silently
///   rewrites the past
///
/// Rules (enforced by `apply...` helpers below):
/// - postureBias    ∈ [-0.15, +0.15]
/// - symmetryBias   ∈ [-0.15, +0.15]
/// - vTaperBias     ∈ [-0.15, +0.15]
/// - calorieOffsetPct ∈ [-0.10, +0.10]
///
/// AI is NEVER allowed to write to this model directly. Only the
/// `FeedbackEvent` → calibration update pipeline can change values.
@Model
final class CalibrationProfile {
    /// Stable identifier — one profile per user, scoped by `userKey`.
    var userKey: String
    /// Version stamp written into every scan that consumed this profile.
    var version: String
    var createdAt: Date
    var updatedAt: Date

    // Bounded biases (see clamp ranges above).
    var postureBias: Double
    var symmetryBias: Double
    var vTaperBias: Double
    var calorieOffsetPct: Double

    /// Count of feedback events folded in. Used to decay learning rate.
    var feedbackCount: Int

    init(
        userKey: String,
        version: String = "calibration_v1",
        createdAt: Date = .now,
        updatedAt: Date = .now,
        postureBias: Double = 0,
        symmetryBias: Double = 0,
        vTaperBias: Double = 0,
        calorieOffsetPct: Double = 0,
        feedbackCount: Int = 0
    ) {
        self.userKey = userKey
        self.version = version
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.postureBias = postureBias
        self.symmetryBias = symmetryBias
        self.vTaperBias = vTaperBias
        self.calorieOffsetPct = calorieOffsetPct
        self.feedbackCount = feedbackCount
    }

    // MARK: - Bounded application helpers

    private static let scoreBiasBound = 0.15
    private static let calorieBiasBound = 0.10

    /// Neutral profile — used when calibration is missing or corrupted.
    /// Per spec: "If calibration fails → use neutral profile (all zeros)".
    static let neutral = CalibrationProfile(
        userKey: "__neutral__",
        version: "calibration_v1",
        postureBias: 0,
        symmetryBias: 0,
        vTaperBias: 0,
        calorieOffsetPct: 0
    )

    /// Apply bounded bias to a 0..100 score. Calibration only shifts; it
    /// cannot reshape the curve or push scores outside the engine's own range.
    func applyScoreBias(_ score: Double, bias: Double) -> Double {
        let clampedBias = max(-Self.scoreBiasBound, min(Self.scoreBiasBound, bias))
        // Bias as a percentage of headroom, gently applied so a +0.15 bias
        // moves a 60 to ~63.6, not 75.
        let shifted = score * (1 + clampedBias * 0.4)
        return max(0, min(100, shifted))
    }

    func applyPosture(_ score: Double) -> Double { applyScoreBias(score, bias: postureBias) }
    func applySymmetry(_ score: Double) -> Double { applyScoreBias(score, bias: symmetryBias) }
    func applyVTaper(_ score: Double) -> Double { applyScoreBias(score, bias: vTaperBias) }

    /// Apply bounded calorie offset. ±10% cap.
    func applyCalories(_ kcal: Int) -> Int {
        let clamped = max(-Self.calorieBiasBound, min(Self.calorieBiasBound, calorieOffsetPct))
        return Int(round(Double(kcal) * (1 + clamped)))
    }

    // MARK: - EMA update from feedback (only entry point for changes)

    /// Fold a single feedback event into the profile via EMA. Learning rate
    /// decays as more feedback accumulates so the profile stabilizes.
    ///
    /// `delta` represents the user's signal in the metric's natural units
    /// (e.g. "too high by 5 points on a 0..100 scale" → -0.05).
    func ingest(metric: FeedbackMetric, delta: Double, now: Date = .now) {
        // Learning rate: 0.20 for first event, decaying toward 0.04.
        let n = max(1, feedbackCount + 1)
        let alpha = max(0.04, 0.20 - Double(n) * 0.01)

        func step(_ current: Double, _ signal: Double, bound: Double) -> Double {
            let updated = current + alpha * signal
            return max(-bound, min(bound, updated))
        }

        switch metric {
        case .posture:
            postureBias = step(postureBias, delta, bound: Self.scoreBiasBound)
        case .symmetry:
            symmetryBias = step(symmetryBias, delta, bound: Self.scoreBiasBound)
        case .vTaper:
            vTaperBias = step(vTaperBias, delta, bound: Self.scoreBiasBound)
        case .calories:
            calorieOffsetPct = step(calorieOffsetPct, delta, bound: Self.calorieBiasBound)
        }

        feedbackCount += 1
        updatedAt = now
    }
}

/// Metrics the calibration system can be nudged on.
nonisolated enum FeedbackMetric: String, Codable {
    case posture
    case symmetry
    case vTaper
    case calories
}

/// Resolves or creates the active calibration profile, guaranteeing scoring
/// never has to handle a `nil` calibration.
@MainActor
enum CalibrationResolver {
    static func resolve(for userKey: String, in ctx: ModelContext) -> CalibrationProfile {
        let target = userKey
        let descriptor = FetchDescriptor<CalibrationProfile>(
            predicate: #Predicate { $0.userKey == target }
        )
        if let existing = (try? ctx.fetch(descriptor))?.first {
            return existing
        }
        let fresh = CalibrationProfile(userKey: userKey)
        ctx.insert(fresh)
        try? ctx.save()
        return fresh
    }
}
