import Foundation

/// Deterministic, on-device PSL / physique scoring engine.
///
/// This is the "second option" safety net: when every cloud model fails or
/// credits are exhausted, the app still produces a stable, explainable PSL
/// score from `PoseService` anchors alone — no AI, no network, no hallucination.
///
/// Outputs match the spec contract:
/// ```json
/// {
///   "psl_score": 0-10,
///   "symmetry": 0-1,
///   "posture": 0-1,
///   "confidence": 0-1
/// }
/// ```
nonisolated struct DeterministicScoring {
    static let shared = DeterministicScoring()

    nonisolated struct Score: Codable {
        let pslScore: Double      // 0..10
        let symmetry: Double      // 0..1
        let posture: Double       // 0..1
        let bodyComposition: Double  // 0..1, higher = leaner / more defined
        let confidence: Double    // 0..1

        enum CodingKeys: String, CodingKey {
            case pslScore = "psl_score"
            case symmetry, posture
            case bodyComposition = "body_composition"
            case confidence
        }
    }

    /// Compute a stable PSL score from on-device anchors.
    ///
    /// Weights (sum to 1.0):
    /// - 0.30 V-taper (shoulder/hip ratio, target ~1.6 Adonis)
    /// - 0.25 leanness (waist/shoulder, lower = better)
    /// - 0.20 symmetry (shoulder + limb)
    /// - 0.15 posture (shoulder tilt deg)
    /// - 0.10 proportions (torso aspect ~1.2-1.6 ideal)
    func score(anchors: PhysiqueAnchors) -> Score {
        // 1. V-taper: Adonis ratio target = 1.618.
        let vTaperRaw = anchors.shoulderWaistRatio
        let vTaper = bell(vTaperRaw, center: 1.55, halfWidth: 0.35) // 0..1

        // 2. Leanness from waist/shoulder ratio (lower = leaner). 0.70 ideal, 1.0 = soft.
        let leanness = bell(anchors.waistShoulderRatio, center: 0.72, halfWidth: 0.18)

        // 3. Symmetry blend: shoulder alignment + limb symmetry.
        let sym = max(0, min(1, 0.6 * anchors.symmetry + 0.4 * anchors.limbSymmetry))

        // 4. Posture: penalize shoulder tilt off horizontal.
        let tiltAbs = abs(anchors.shoulderTiltDeg)
        let posture = max(0, min(1, 1 - tiltAbs / 18.0))

        // 5. Proportions: torso aspect ratio ideal range ~1.2-1.6.
        let proportions = bell(anchors.torsoAspect, center: 1.4, halfWidth: 0.5)

        let composite =
            0.30 * vTaper +
            0.25 * leanness +
            0.20 * sym +
            0.15 * posture +
            0.10 * proportions

        let pslScore = max(0, min(10, composite * 10))

        // Confidence reflects how trustworthy the anchors are.
        let anchorConfidence = anchors.confidence
        let coverageBonus = min(1, anchors.coverageY / 0.6) // full-body = 1
        let confidence = max(0, min(1, anchorConfidence * 0.7 + coverageBonus * 0.3))

        return Score(
            pslScore: round(pslScore * 10) / 10,
            symmetry: round(sym * 100) / 100,
            posture: round(posture * 100) / 100,
            bodyComposition: round(leanness * 100) / 100,
            confidence: round(confidence * 100) / 100
        )
    }

    /// JSON-encode for embedding in prompts or downstream consumers.
    func encode(_ s: Score) -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys, .prettyPrinted]
        guard let data = try? enc.encode(s),
              let str = String(data: data, encoding: .utf8) else { return "{}" }
        return str
    }

    /// Bell-curve scoring: 1.0 at `center`, falling to 0.0 at `center ± halfWidth`.
    private func bell(_ value: Double, center: Double, halfWidth: Double) -> Double {
        let d = abs(value - center) / max(0.0001, halfWidth)
        return max(0, min(1, 1 - d))
    }
}

// MARK: - PhysiqueAnchors bridge
//
// `PhysiqueAnchors` is defined in AIService.swift. This extension is here so
// DeterministicScoring can be used standalone without importing AI types
// into other modules.
