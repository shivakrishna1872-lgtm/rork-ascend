import Foundation

/// Deterministic, on-device facial harmony scoring engine.
///
/// All numeric PSL outputs are computed from Apple Vision face-mesh
/// measurements using fixed formulas. No AI model may influence these
/// scores — AI is strictly text-only (insight / recommendations / hairstyles).
///
/// Score contract (matches the spec):
/// ```json
/// {
///   "psl_score": 0-100,
///   "symmetry": 0-100,
///   "jawline": 0-100,
///   "thirds": 0-100,
///   "canthal_tilt": 0-100,
///   "eye_spacing": 0-100,
///   "glow_up": 0-100,
///   "confidence": 0-1
/// }
/// ```
nonisolated struct DeterministicFaceScoring {
    static let shared = DeterministicFaceScoring()

    nonisolated struct Score {
        let pslScore: Double         // 0..100
        let symmetry: Double         // 0..100
        let jawline: Double          // 0..100
        let thirds: Double           // 0..100
        let canthalTilt: Double      // 0..100
        let eyeSpacing: Double       // 0..100
        let glowUpPotential: Double  // 0..100
        let confidence: Double       // 0..1
        let isUsable: Bool           // false → insufficient data
    }

    /// Compute deterministic PSL from averaged on-device face measurements.
    ///
    /// `consistency` (0..1) reflects sample-to-sample agreement across photos
    /// and is folded into the confidence score.
    func score(measurements: FaceMeasurements?, sampleCount: Int, consistency: Double, faceQuality: Double = 1.0) -> Score {
        guard let m = measurements, sampleCount > 0 else {
            return Score(
                pslScore: 0, symmetry: 0, jawline: 0, thirds: 0,
                canthalTilt: 0, eyeSpacing: 0, glowUpPotential: 0,
                confidence: 0, isUsable: false
            )
        }

        // Direct landmark → score mappings. Each metric is clamped 30..98 so
        // a bad photo doesn't produce zero, and a perfect anchor doesn't
        // promise 100 (deterministic ceiling reserved for the math).
        let symmetry   = clamp(m.symmetry * 100, lo: 30, hi: 98)
        let thirds     = clamp(m.thirds * 100, lo: 30, hi: 98)

        // Canthal tilt: −2° → 45, 0° → 62, +4° → 80, +8° → 93
        let canthal = clamp(62 + m.canthalTiltDeg * 4.0, lo: 30, hi: 95)

        // Eye spacing: ideal ratio ≈ 1.0; deviation penalized.
        let eyeSpacing = clamp(92 - abs(m.eyeSpacingRatio - 1.0) * 70, lo: 30, hi: 95)

        // Jaw ratio: ideal 0.70..0.80; deviation penalized.
        let jawline = clamp(92 - abs(m.jawRatio - 0.75) * 160, lo: 30, hi: 95)

        // Face-quality gate: when landmarks are unreliable, redistribute
        // weights from precision metrics (symmetry, canthal) to coarse
        // structural ratios (jaw, thirds). Prevents overfitting low-quality
        // selfies.
        let w = FaceQuality.weights(for: faceQuality)
        let baseSym = 0.25 * w.symmetry
        let baseJaw = 0.25 * w.jawline
        let baseThirds = 0.15 * w.thirds
        let baseCanthal = 0.15 * w.canthal
        let baseEye = 0.10 * w.eyeSpacing
        let groomingW = 0.10
        let totalW = baseSym + baseJaw + baseThirds + baseCanthal + baseEye + groomingW
        let psl = (
            baseSym * symmetry +
            baseJaw * jawline +
            baseThirds * thirds +
            baseCanthal * canthal +
            baseEye * eyeSpacing +
            groomingW * ((symmetry + jawline) / 2)
        ) / totalW

        // Glow-up potential: higher when current PSL is mid-range; lower at
        // either extreme. Fully deterministic.
        let mid = 1 - abs((psl - 65) / 35)
        let glowUp = clamp(20 + mid * 40, lo: 10, hi: 60)

        // Confidence: sample count + agreement + face quality + expression
        // neutrality. 3 photos with high agreement on a clean, relaxed face
        // = 1.0. An expressive face (big smile / squint) distorts proportions,
        // so neutrality scales confidence down honestly rather than pretending
        // the read was structurally clean.
        let sampleBoost = min(1.0, Double(sampleCount) / 3.0)
        let neutrality = measurements?.expressionNeutrality ?? 1.0
        let conf = clamp(
            0.34 * sampleBoost + 0.30 * consistency + 0.21 * faceQuality + 0.15 * neutrality,
            lo: 0, hi: 1
        )

        return Score(
            pslScore:        round(psl * 10) / 10,
            symmetry:        round(symmetry * 10) / 10,
            jawline:         round(jawline * 10) / 10,
            thirds:          round(thirds * 10) / 10,
            canthalTilt:     round(canthal * 10) / 10,
            eyeSpacing:      round(eyeSpacing * 10) / 10,
            glowUpPotential: round(glowUp * 10) / 10,
            confidence:      round(conf * 100) / 100,
            isUsable:        true
        )
    }

    private func clamp(_ v: Double, lo: Double, hi: Double) -> Double {
        max(lo, min(hi, v))
    }
}
