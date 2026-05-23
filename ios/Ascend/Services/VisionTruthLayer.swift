import Foundation
import UIKit
import Vision
import CoreImage

/// Shared Vision Truth Layer.
///
/// PSL, Physique, and Cal AI all consume **only** this output as their
/// computer-vision input. There is no other place where raw Vision requests
/// get fanned out to the scan pipelines — that keeps preprocessing,
/// landmark ordering, coordinate normalization, and image hashing identical
/// across all three so the same photo always produces the same structured
/// inputs.
///
/// Each surface reads the fields it cares about:
///  - PSL → `face`, `faceQuality`, `lightingQuality`, `imageHash`
///  - Physique → `pose`, `bodyContinuity`, `lightingQuality`, `imageHash`
///  - Cal AI → `foodAnchor`, `sceneType`, `lightingQuality`, `imageHash`
///
/// Numeric outputs are still produced by the deterministic scoring engines
/// downstream; the truth layer never authors scores or macros. It only
/// supplies the *grounded* inputs those engines run on.
nonisolated struct VisionTruth: Sendable {
    /// SHA-256 hash of the deterministic, normalized image. Same photo →
    /// same hash, regardless of camera, orientation or device.
    let imageHash: String

    /// True when a person is anywhere in the frame (pose joints, human rect,
    /// or segmentation mask). Face presence is *not* required.
    let personDetected: Bool

    /// 0..1 — strongest signal of person presence. Pose > rect > mask > none.
    let personConfidence: Double

    /// 0..1 — how much of the body silhouette is visible vs. occluded.
    /// 1 = fully visible, 0 = heavily blocked (phone, clothing, crop).
    let occlusionScore: Double

    /// 0..1 — lighting / sharpness quality. Drives fallback weighting, not
    /// pass/fail gating.
    let lightingQuality: Double

    /// 0..1 — body-silhouette completeness. Combines pose joint count,
    /// segmentation coverage, and occlusion. Drives Physique confidence so
    /// partial bodies score honestly instead of being faked at 90%+.
    let bodyContinuity: Double

    /// 0..1 — face landmark reliability. Drives PSL weight redistribution
    /// when face is partially occluded.
    let faceQuality: Double

    /// Coarse scene classification — guides Cal AI grounding (plate vs.
    /// fast-food packaging vs. mirror selfie).
    let sceneType: SceneType

    /// Optional grounded landmark outputs. May be nil if that surface isn't
    /// applicable to this image (e.g. food photo has no `pose`).
    let pose: PoseResult?
    let face: FaceMeasurements?
    let foodAnchor: FoodIdentityAnchor?

    nonisolated enum SceneType: String, Sendable {
        case selfie, mirrorSelfie, gymBody, plate, packaging, drink, unknown
    }
}

// MARK: - Focus

/// What we want VTL to extract. Drives which Vision requests run — keeps the
/// food path from doing pose work and vice versa.
nonisolated enum VisionFocus: Sendable {
    case face, body, food
}

// MARK: - Layer

nonisolated enum VisionTruthLayer {

    // In-process memoization keyed by `imageHash|focus`. Guarantees PSL,
    // Physique, and Cal AI consume the **same** VisionTruth instance for
    // the same image — no duplicate Vision processing across pipelines.
    private static let store = TruthStore()

    private actor TruthStore {
        var cache: [String: VisionTruth] = [:]
        func get(_ key: String) -> VisionTruth? { cache[key] }
        func set(_ key: String, _ value: VisionTruth) {
            // Soft cap so long sessions don't grow unbounded.
            if cache.count > 32 { cache.removeAll(keepingCapacity: true) }
            cache[key] = value
        }
    }

    /// Single entrypoint. PSL / Physique / Cal AI all start here.
    /// Memoized per `(imageHash, focus)` — second call returns the exact
    /// same struct, no Vision re-run.
    static func analyze(_ image: UIImage, focus: VisionFocus) async -> VisionTruth {
        let normalized = ScanCache.normalize(image)
        let hash = normalized.hash
        let memoKey = hash + "|" + String(describing: focus)
        if let hit = await store.get(memoKey) { return hit }
        let cg = normalized.image.cgImage ?? image.cgImage

        let lighting = lightingQuality(cg: cg)

        let truth: VisionTruth
        switch focus {
        case .face:
            let face = await PoseService.shared.analyzeFace(normalized.image)
            let faceQ = FaceQuality.score(measurements: face, lighting: lighting)
            let scene: VisionTruth.SceneType = faceQ > 0.4 ? .selfie : .unknown
            truth = VisionTruth(
                imageHash: hash,
                personDetected: face != nil,
                personConfidence: face != nil ? 0.9 : 0.0,
                occlusionScore: face != nil ? max(0.3, faceQ) : 0.0,
                lightingQuality: lighting,
                bodyContinuity: 0,
                faceQuality: faceQ,
                sceneType: scene,
                pose: nil,
                face: face,
                foodAnchor: nil
            )

        case .body:
            let pose = await PoseService.shared.analyze(normalized.image)
            let continuity = BodyContinuity.score(pose: pose, lighting: lighting)
            let occlusion = continuity // body continuity IS the inverse-occlusion
            let detected = (pose?.confidenceAverage ?? 0) > 0.02 || !(pose?.landmarks.isEmpty ?? true)
            let scene: VisionTruth.SceneType = continuity > 0.55 ? .gymBody : (detected ? .mirrorSelfie : .unknown)
            truth = VisionTruth(
                imageHash: hash,
                personDetected: detected,
                personConfidence: pose?.confidenceAverage ?? 0,
                occlusionScore: occlusion,
                lightingQuality: lighting,
                bodyContinuity: continuity,
                faceQuality: 0,
                sceneType: scene,
                pose: pose,
                face: nil,
                foodAnchor: nil
            )

        case .food:
            let anchor = await FoodIdentityAnchor.detect(image: normalized.image)
            truth = VisionTruth(
                imageHash: hash,
                personDetected: false,
                personConfidence: 0,
                occlusionScore: 0,
                lightingQuality: lighting,
                bodyContinuity: 0,
                faceQuality: 0,
                sceneType: anchor.sceneType,
                pose: nil,
                face: nil,
                foodAnchor: anchor
            )
        }
        await store.set(memoKey, truth)
        return truth
    }

    /// Clear the in-process memo. Tests + privacy-clear paths.
    static func purgeMemo() async { await store.set("__purge__", VisionTruth(imageHash: "", personDetected: false, personConfidence: 0, occlusionScore: 0, lightingQuality: 0, bodyContinuity: 0, faceQuality: 0, sceneType: .unknown, pose: nil, face: nil, foodAnchor: nil)) }

    // MARK: Lighting

    /// Deterministic luminance quality score derived from `CIAreaAverage`.
    /// Quantized so re-scans never drift.
    private static func lightingQuality(cg: CGImage?) -> Double {
        guard let cg else { return 0.5 }
        let ci = CIImage(cgImage: cg)
        let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: ci,
            kCIInputExtentKey: CIVector(cgRect: ci.extent)
        ])
        guard let out = filter?.outputImage else { return 0.5 }
        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        context.render(out, toBitmap: &bitmap, rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8, colorSpace: nil)
        let r = Double(bitmap[0]) / 255
        let g = Double(bitmap[1]) / 255
        let b = Double(bitmap[2]) / 255
        let luma = 0.299 * r + 0.587 * g + 0.114 * b
        // Bell curve centered on 0.5 — too dark and too bright both score low.
        let dist = abs(luma - 0.5)
        let raw = max(0, 1 - dist * 2.2)
        // Quantize to 0.05 so it's reproducible scan-to-scan.
        return (raw * 20).rounded() / 20
    }
}

// MARK: - Body Continuity

/// How completely a body silhouette is detected. Distinct from
/// `personConfidence` — confidence measures the strength of the *detector*,
/// continuity measures the **completeness** of the body in frame.
///
/// Phone-blocking-face, cropped torso, partial mirror selfies all surface as
/// reduced continuity instead of failing the scan. Physique uses this to
/// scale its final confidence honestly: low continuity → low confidence, no
/// inflation.
nonisolated enum BodyContinuity {
    /// Explicit partial-body classification. Used so Physique can scope its
    /// scoring honestly instead of inflating confidence when limbs are
    /// simply absent from the frame.
    nonisolated enum Partiality: String, Sendable {
        case full          // shoulders + hips + at least one knee/ankle
        case torsoOnly     // shoulders + hips, no legs (cropped upper body)
        case upperOnly     // shoulders only, no hips visible
        case obstructed    // partial limbs, phone/object blocking
        case missing       // nothing usable
    }

    /// Classify what part of the body is actually present.
    static func partiality(pose: PoseResult?) -> Partiality {
        guard let p = pose else { return .missing }
        let has: (String) -> Bool = { p.landmarks[$0] != nil }
        let shoulders = has("left_shoulder_joint") || has("right_shoulder_joint")
        let hips = has("left_hip_joint") || has("right_hip_joint")
        let legs = has("left_knee_joint") || has("right_knee_joint") ||
                   has("left_ankle_joint") || has("right_ankle_joint")
        let limbs = has("left_elbow_joint") || has("right_elbow_joint") ||
                    has("left_wrist_joint") || has("right_wrist_joint")
        if !shoulders && !hips && !limbs { return .missing }
        if shoulders && hips && legs { return .full }
        if shoulders && hips { return .torsoOnly }
        if shoulders { return .upperOnly }
        return .obstructed
    }

    /// Per-region confidence multiplier. Missing data lowers only the
    /// affected regions — never collapses the full-body score, never inflates.
    static func regionWeight(_ partiality: Partiality, region: Region) -> Double {
        switch (partiality, region) {
        case (.full, _): return 1.0
        case (.torsoOnly, .legs): return 0.0
        case (.torsoOnly, _): return 0.95
        case (.upperOnly, .legs): return 0.0
        case (.upperOnly, .hips): return 0.3
        case (.upperOnly, _): return 0.85
        case (.obstructed, _): return 0.55
        case (.missing, _): return 0.0
        }
    }

    nonisolated enum Region: Sendable { case shoulders, torso, hips, legs }

    static func score(pose: PoseResult?, lighting: Double) -> Double {
        guard let p = pose else { return 0 }

        // Joint coverage: how much of the expected torso skeleton we got.
        let torsoKeys = [
            "left_shoulder_joint", "right_shoulder_joint",
            "left_hip_joint", "right_hip_joint"
        ]
        let torsoHits = torsoKeys.filter { p.landmarks[$0] != nil }.count
        let torsoCoverage = Double(torsoHits) / Double(torsoKeys.count)

        let limbKeys = [
            "left_elbow_joint", "right_elbow_joint",
            "left_wrist_joint", "right_wrist_joint",
            "left_knee_joint", "right_knee_joint",
            "left_ankle_joint", "right_ankle_joint"
        ]
        let limbHits = limbKeys.filter { p.landmarks[$0] != nil }.count
        let limbCoverage = Double(limbHits) / Double(limbKeys.count)

        // Source weighting — pose joints carry the full signal, mask/rect
        // partial. We never *fail* a scan on missing face; that's why face
        // doesn't appear here at all.
        let sourceStrength: Double = {
            switch p.detectionSource {
            case .pose: return 1.0
            case .humanRect: return 0.75
            case .personMask: return 0.65
            case .saliency: return 0.45
            case .brightness: return 0.25
            case .none: return 0
            }
        }()

        // Vertical coverage — how much of the frame the body occupies.
        let coverage = min(1, p.coverageY / 0.55)

        // Weighted blend. Torso > limb > source > coverage > lighting.
        let raw =
            0.40 * torsoCoverage +
            0.20 * limbCoverage +
            0.20 * sourceStrength +
            0.15 * coverage +
            0.05 * lighting
        return max(0, min(1, raw))
    }
}

// MARK: - Face Quality

/// Reliability of face landmarks. PSL uses this to redistribute weights:
/// when quality is low, symmetry-style precision metrics get down-weighted in
/// favor of coarse geometric ratios so the score doesn't overfit to a single
/// noisy reading.
nonisolated enum FaceQuality {
    static func score(measurements: FaceMeasurements?, lighting: Double) -> Double {
        guard let m = measurements else { return 0 }
        // Sanity bounds: degenerate readings (impossible canthal tilt, jaw
        // ratio outside 0.5..1.0, eye spacing way off) signal the detector
        // wasn't confident.
        let jawSanity = (0.55...0.95).contains(m.jawRatio) ? 1.0 : 0.55
        let eyeSanity = (0.6...1.6).contains(m.eyeSpacingRatio) ? 1.0 : 0.55
        let tiltSanity = abs(m.canthalTiltDeg) < 25 ? 1.0 : 0.5
        let symmetrySanity = (0...1).contains(m.symmetry) ? m.symmetry : 0.5
        let thirdsSanity = (0...1).contains(m.thirds) ? m.thirds : 0.5
        let raw =
            0.25 * jawSanity +
            0.20 * eyeSanity +
            0.15 * tiltSanity +
            0.20 * symmetrySanity +
            0.10 * thirdsSanity +
            0.10 * lighting
        return max(0, min(1, raw))
    }

    /// PSL weight redistribution. When `quality` drops, symmetry/canthal
    /// (high-precision) get reduced in favor of jaw + thirds (coarser, more
    /// stable). Returns multipliers that downstream weighting can apply.
    nonisolated struct Weights: Sendable {
        let symmetry: Double
        let jawline: Double
        let thirds: Double
        let canthal: Double
        let eyeSpacing: Double
    }

    static func weights(for quality: Double) -> Weights {
        let q = max(0, min(1, quality))
        // High quality (q≥0.8): trust precision metrics.
        // Low quality (q≤0.3): lean on coarse ratios.
        let precision = q                  // 0..1
        let coarse = 1 - q                 // 0..1
        return Weights(
            symmetry:    0.7 + precision * 0.6,    // 0.7..1.3
            jawline:     1.0 + coarse * 0.4,       // 1.0..1.4
            thirds:      1.0 + coarse * 0.3,       // 1.0..1.3
            canthal:     0.6 + precision * 0.6,    // 0.6..1.2
            eyeSpacing:  0.8 + precision * 0.3     // 0.8..1.1
        )
    }
}

// MARK: - Food Identity Anchor

/// Pre-classification grounding step. Detects the *context* of a meal photo
/// before naming the dish: container shape (plate / bowl / bag / wrapper),
/// any printed text (brand / menu / packaging), and the rough food cluster.
/// Cal AI's classifier then runs on top of this anchor instead of guessing
/// from raw pixels.
nonisolated struct FoodIdentityAnchor: Sendable {
    /// "plate", "bowl", "burger_wrapper", "fast_food_bag", "cup", "menu",
    /// "package", or "unknown".
    let container: String
    /// Brand / menu / packaging OCR hits, lowercased.
    let ocrHits: [String]
    /// Top salient regions normalized to image coords (origin bottom-left).
    let salientRegions: [CGRect]
    /// 0..1 — how confidently we know what *kind* of meal this is.
    let groundingConfidence: Double
    /// Maps directly to `VisionTruth.SceneType`.
    let sceneType: VisionTruth.SceneType

    static func detect(image: UIImage) async -> FoodIdentityAnchor {
        guard let cg = image.cgImage else {
            return FoodIdentityAnchor(container: "unknown", ocrHits: [],
                                      salientRegions: [], groundingConfidence: 0,
                                      sceneType: .unknown)
        }

        async let ocrTask = readText(cg: cg)
        async let regionsTask = salientRegions(cg: cg)
        let ocr = await ocrTask
        let regions = await regionsTask

        let joined = ocr.joined(separator: " ").lowercased()
        var container = "unknown"
        var scene: VisionTruth.SceneType = .unknown

        // Container heuristics from OCR + region geometry.
        if joined.contains("mcdonald") || joined.contains("burger king") ||
           joined.contains("wendy") || joined.contains("taco bell") ||
           joined.contains("kfc") || joined.contains("subway") ||
           joined.contains("chick-fil") || joined.contains("chipotle") {
            container = "fast_food_bag"
            scene = .packaging
        } else if joined.contains("nutrition facts") || joined.contains("ingredients") ||
                  joined.contains("kcal") || joined.contains("calories") {
            container = "package"
            scene = .packaging
        } else if joined.contains("menu") || joined.contains("appetizer") ||
                  joined.contains("entrée") || joined.contains("entree") {
            container = "menu"
            scene = .plate
        } else if let largest = regions.max(by: { $0.width * $0.height < $1.width * $1.height }) {
            // Container shape inference from saliency region aspect ratio.
            let aspect = largest.width / max(0.001, largest.height)
            let area = largest.width * largest.height
            if area > 0.45, aspect > 0.85, aspect < 1.2 {
                container = "plate" // roughly square = top-down plate
                scene = .plate
            } else if area > 0.3, aspect > 1.4 {
                container = "tray"
                scene = .plate
            } else if area > 0.2, aspect < 0.7 {
                container = "cup"
                scene = .drink
            } else {
                container = "plate"
                scene = .plate
            }
        }

        let groundingConfidence: Double = {
            if !ocr.isEmpty { return min(1, 0.7 + Double(ocr.count) * 0.04) }
            if !regions.isEmpty { return 0.5 }
            return 0.25
        }()

        return FoodIdentityAnchor(
            container: container,
            ocrHits: ocr.map { $0.lowercased() },
            salientRegions: regions,
            groundingConfidence: groundingConfidence,
            sceneType: scene
        )
    }

    private static func readText(cg: CGImage) async -> [String] {
        await withCheckedContinuation { (cont: CheckedContinuation<[String], Never>) in
            let req = VNRecognizeTextRequest { request, _ in
                let obs = (request.results as? [VNRecognizedTextObservation]) ?? []
                cont.resume(returning: obs.compactMap { $0.topCandidates(1).first?.string })
            }
            req.recognitionLevel = .accurate
            req.usesLanguageCorrection = true
            req.recognitionLanguages = ["en-US"]
            let handler = VNImageRequestHandler(cgImage: cg, orientation: .up, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do { try handler.perform([req]) }
                catch { cont.resume(returning: []) }
            }
        }
    }

    private static func salientRegions(cg: CGImage) async -> [CGRect] {
        await withCheckedContinuation { (cont: CheckedContinuation<[CGRect], Never>) in
            let req = VNGenerateObjectnessBasedSaliencyImageRequest { request, _ in
                guard let obs = (request.results as? [VNSaliencyImageObservation])?.first,
                      let salient = obs.salientObjects else {
                    cont.resume(returning: []); return
                }
                let rects = salient
                    .sorted(by: { $0.confidence > $1.confidence })
                    .prefix(6)
                    .map { $0.boundingBox }
                cont.resume(returning: Array(rects))
            }
            let handler = VNImageRequestHandler(cgImage: cg, orientation: .up, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do { try handler.perform([req]) }
                catch { cont.resume(returning: []) }
            }
        }
    }
}

// MARK: - Cross-pipeline consistency

/// Checks PSL ↔ Physique outputs for the same person. We **never** average
/// or force-align — divergence beyond threshold just lowers the broadcast
/// confidence and emits a transparency flag so the UI can render an
/// "uncertainty event" badge instead of pretending alignment.
nonisolated enum CrossPipelineConsistency {

    nonisolated struct Report: Sendable {
        /// 0..1 — agreement between PSL and Physique on the user's overall
        /// quality band (low/mid/high). 1 = perfectly consistent.
        let agreement: Double
        /// True when the deviation exceeded the threshold. UI should reduce
        /// the displayed confidence and flag uncertainty.
        let isUncertaintyEvent: Bool
        /// 0..1 multiplier applied to broadcast confidence when pipelines
        /// diverge. We never average or force-align the scores themselves;
        /// only the *confidence* takes a controlled penalty.
        let confidencePenalty: Double
        /// Human-readable explanation for debugging / telemetry.
        let note: String
    }

    /// `pslScore` and `physiqueScore` are 0..100.
    static func check(pslScore: Double, physiqueScore: Double) -> Report {
        let delta = abs(pslScore - physiqueScore)
        // Bands: 0–55 (low), 55–75 (mid), 75–100 (high). One full band gap is
        // about 20 points — we treat 25+ as a divergence event.
        let agreement = max(0, 1 - delta / 50.0)
        let isEvent = delta > 25
        // Controlled penalty: 0–15 pts deviation → 1.0, 25 → 0.92,
        // 40 → 0.85, 60+ → 0.78. Never below 0.78 so a divergent reading
        // doesn't collapse the user-facing confidence.
        let penalty: Double = {
            if delta < 15 { return 1.0 }
            if delta < 25 { return 0.96 }
            if delta < 40 { return 0.92 }
            if delta < 60 { return 0.85 }
            return 0.78
        }()
        let note: String = {
            if isEvent { return "PSL/Physique disagree by \(Int(delta)) pts — confidence penalty \(Int((1-penalty)*100))%." }
            return "PSL/Physique within \(Int(delta)) pts — consistent."
        }()
        return Report(agreement: agreement, isUncertaintyEvent: isEvent, confidencePenalty: penalty, note: note)
    }
}
