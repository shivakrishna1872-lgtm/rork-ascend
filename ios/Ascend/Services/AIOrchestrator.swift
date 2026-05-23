import Foundation
import UIKit

/// Top-level orchestrator for the AI vision + reasoning pipeline.
///
/// Architecture (matches the published spec):
///  1. Local preprocessing (ImagePreprocessor) — blur, lighting, crop.
///  2. On-device "truth layer" (PoseService / Vision face mesh) — ALWAYS runs.
///  3. ONE vision model per request, selected via CircuitBreaker descending
///     priority (Gemini 2.5 → GPT-4o → Gemini 2.0 Flash).
///  4. Structured fusion JSON combining the two.
///  5. Reasoning model (Claude Opus 4.7 → GPT-5 → Gemini Pro → Sonnet → 4o →
///     Haiku → on-device heuristic) — receives JSON only, never raw images.
///  6. Consistency engine reconciles + smooths the final scores.
///
/// All upstream calls flow through `RequestQueue` for concurrency capping
/// and perceptual-hash deduplication, so the same scan submitted twice in
/// a row only hits the model once.
nonisolated struct AIOrchestrator {
    static let shared = AIOrchestrator()

    // MARK: - Vision model chain (one used per request, descending priority)

    /// Ordered list of vision providers. We pick the FIRST one whose circuit
    /// breaker isn't open and use only that one for a given request.
    static let visionChain: [String] = [
        "google/gemini-2.5-flash",  // best free-tier vision
        "openai/gpt-4o",            // strong fallback
        "google/gemini-2.0-flash"   // fast last-resort
    ]

    // MARK: - Reasoning model chain (one used per request, descending priority)

    /// Ordered list of reasoning providers. Opus is the target; everything
    /// else is a degraded but valid fallback.
    static let reasoningChain: [String] = [
        "anthropic/claude-opus-4.7",
        "openai/gpt-5",
        "google/gemini-2.5-pro",
        "anthropic/claude-sonnet-4.5",
        "openai/gpt-4o",
        "anthropic/claude-haiku-4.5"
    ]

    /// Pick the first vision provider whose circuit breaker is closed.
    /// Returns nil if every provider is currently open.
    func pickVisionProvider() async -> String? {
        for p in Self.visionChain {
            if await !CircuitBreaker.shared.isOpen(p) { return p }
        }
        return nil
    }

    /// Pick the first reasoning provider whose circuit breaker is closed.
    func pickReasoningProvider() async -> String? {
        for p in Self.reasoningChain {
            if await !CircuitBreaker.shared.isOpen(p) { return p }
        }
        return nil
    }

    // MARK: - Fusion payload

    /// Structured fusion JSON. This is what we send to the reasoning model
    /// instead of raw images, so it can't hallucinate measurements that the
    /// truth layer didn't see.
    nonisolated struct FusionPayload: Codable {
        struct MediaPipeBlock: Codable {
            let symmetry: Double
            let limbSymmetry: Double
            let shoulderHipRatio: Double
            let waistShoulderRatio: Double
            let thighHipRatio: Double
            let torsoAspect: Double
            let shoulderTiltDeg: Double
            let estimatedBodyFatNavy: Double
            let coverageY: Double
            let confidence: Double
        }
        struct VisionBlock: Codable {
            let bodyType: String
            let fatEstimate: String
            let muscleDefinition: String
            let confidence: Double
        }
        struct FusionBlock: Codable {
            let overallConfidence: Double
            let flags: [String]
        }
        let mediapipe: MediaPipeBlock
        let vision: VisionBlock
        let fusion: FusionBlock
    }

    /// Build the fusion payload from the on-device truth layer + the cloud
    /// vision model's structured output.
    func buildPayload(
        anchors: PhysiqueAnchors?,
        vision: FusionPayload.VisionBlock
    ) -> FusionPayload {
        let mp = FusionPayload.MediaPipeBlock(
            symmetry: anchors?.symmetry ?? 0,
            limbSymmetry: anchors?.limbSymmetry ?? 0,
            shoulderHipRatio: anchors?.shoulderWaistRatio ?? 0,
            waistShoulderRatio: anchors?.waistShoulderRatio ?? 0,
            thighHipRatio: anchors?.thighHipRatio ?? 0,
            torsoAspect: anchors?.torsoAspect ?? 0,
            shoulderTiltDeg: anchors?.shoulderTiltDeg ?? 0,
            estimatedBodyFatNavy: anchors?.navyBodyFatPercent ?? 0,
            coverageY: anchors?.coverageY ?? 0,
            confidence: anchors?.confidence ?? 0
        )
        var flags: [String] = []
        if (anchors?.confidence ?? 0) < 0.45 { flags.append("low_anchor_confidence") }
        if vision.confidence < 0.45 { flags.append("low_vision_confidence") }
        if (anchors?.detectedAngles ?? 0) < 2 { flags.append("partial_body_coverage") }
        let overall = ((anchors?.confidence ?? 0) + vision.confidence) / 2
        let fusion = FusionPayload.FusionBlock(overallConfidence: overall, flags: flags)
        return FusionPayload(mediapipe: mp, vision: vision, fusion: fusion)
    }

    /// JSON-encode the fusion payload for embedding into a reasoning prompt.
    /// Compact + deterministic key order.
    func encodePayload(_ payload: FusionPayload) -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        guard let data = try? enc.encode(payload),
              let s = String(data: data, encoding: .utf8) else { return "{}" }
        return s
    }
}
