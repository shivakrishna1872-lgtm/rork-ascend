import Foundation
import UIKit

/// Pluggable computer-vision pipeline.
///
/// Every CV stage in the app (body landmarks, face mesh, meal segmentation)
/// goes through this single funnel. Stages are protocol-based so we can swap
/// in CoreML / PyTorch Mobile / TF Lite / a future custom-trained Detectron2
/// export without touching the call site.
///
/// Design goals:
///  * High concurrency: every stage is `nonisolated` and `Sendable`. No locks,
///    no shared mutable state. The same `CVPipeline.shared` can be hit from
///    millions of concurrent requests without serializing.
///  * Confidence-gated: each stage returns a numeric confidence; the pipeline
///    short-circuits to the deterministic on-device fallback when confidence
///    drops below threshold, so the AI never gets garbage input and the user
///    never sees a hallucinated number.
///  * Cache-friendly: every stage exposes a stable `cacheKey` derived from its
///    inputs, so embeddings/results can be memoized by `AIResponseCache`.
///  * Ensemble-friendly: stages can declare alternates; the pipeline picks the
///    first successful result with confidence above the gate.

// MARK: - Public protocols

nonisolated protocol CVStage: Sendable {
    associatedtype Output: Sendable
    var id: String { get }
    func run(_ image: UIImage) async -> CVStageResult<Output>
}

nonisolated struct CVStageResult<Output: Sendable>: Sendable {
    let output: Output?
    let confidence: Double      // 0..1
    let modelUsed: String       // for telemetry / debugging
    let preprocessReceipt: PreprocessReceipt
}

// MARK: - Pipeline

nonisolated struct CVPipeline {
    static let shared = CVPipeline()

    /// Minimum confidence to trust a stage's output. Below this the caller
    /// should branch to its deterministic fallback instead of feeding the AI.
    static let confidenceGate: Double = 0.35

    /// Run any stage with preprocessing applied first. Returns the stage's
    /// output plus the preprocess receipt so downstream code can reason about
    /// input quality.
    func run<S: CVStage>(_ stage: S, on image: UIImage, mode: ImagePreprocessor.Mode) async -> CVStageResult<S.Output> {
        let pre = await ImagePreprocessor.shared.process(image, mode: mode)
        guard pre.receipt.isUsable else {
            return CVStageResult(
                output: nil,
                confidence: 0,
                modelUsed: "preprocess.reject",
                preprocessReceipt: pre.receipt
            )
        }
        let result = await stage.run(pre.image)
        // Scale confidence by input quality so a sharp + well-lit photo gets
        // the full landmark confidence, while a marginal photo is downweighted.
        let blended = result.confidence * (0.55 + pre.receipt.inputQuality * 0.45)
        return CVStageResult(
            output: result.output,
            confidence: min(1, blended),
            modelUsed: result.modelUsed,
            preprocessReceipt: pre.receipt
        )
    }

    /// Try multiple homogeneous stages and return the first one that clears
    /// the confidence gate. Lets the body-landmark pipeline degrade from a
    /// future custom CoreML model → Vision body pose → silhouette heuristic
    /// without the caller knowing which one fired. Stages must share the same
    /// `Output` type so future swap-ins stay drop-in compatible.
    func ensemble<S: CVStage>(_ stages: [S], on image: UIImage, mode: ImagePreprocessor.Mode) async -> CVStageResult<S.Output> {
        let pre = await ImagePreprocessor.shared.process(image, mode: mode)
        var lastReceipt = pre.receipt
        for stage in stages {
            let r = await stage.run(pre.image)
            if r.confidence >= Self.confidenceGate, let out = r.output {
                return CVStageResult(
                    output: out,
                    confidence: r.confidence,
                    modelUsed: r.modelUsed,
                    preprocessReceipt: lastReceipt
                )
            }
        }
        return CVStageResult(output: nil, confidence: 0, modelUsed: "ensemble.miss", preprocessReceipt: lastReceipt)
    }
}

// MARK: - Body-landmark stage (Vision implementation; pluggable)

nonisolated struct VisionBodyStage: CVStage {
    typealias Output = PoseResult
    let id = "vision.body.pose"
    func run(_ image: UIImage) async -> CVStageResult<PoseResult> {
        guard let pose = await PoseService.shared.analyze(image) else {
            return CVStageResult(output: nil, confidence: 0, modelUsed: id, preprocessReceipt: .unusable)
        }
        // Confidence is the average per-joint score from Vision.
        return CVStageResult(
            output: pose,
            confidence: pose.confidenceAverage,
            modelUsed: id,
            preprocessReceipt: .unusable // pipeline wrapper supplies the real one
        )
    }
}

// MARK: - Face mesh stage (Vision implementation; pluggable)

nonisolated struct VisionFaceStage: CVStage {
    typealias Output = FaceMeasurements
    let id = "vision.face.mesh"
    func run(_ image: UIImage) async -> CVStageResult<FaceMeasurements> {
        guard let m = await PoseService.shared.analyzeFace(image) else {
            return CVStageResult(output: nil, confidence: 0, modelUsed: id, preprocessReceipt: .unusable)
        }
        // Confidence proxy: how plausible the measurements are.
        let plausible = (0.5...0.99).contains(m.symmetry) &&
                        (0.5...0.95).contains(m.thirds) &&
                        m.jawRatio > 0.5 && m.jawRatio < 1.1
        return CVStageResult(
            output: m,
            confidence: plausible ? 0.85 : 0.55,
            modelUsed: id,
            preprocessReceipt: .unusable
        )
    }
}
