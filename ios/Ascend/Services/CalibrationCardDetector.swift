import Foundation
import Vision
import UIKit

/// Detects a reference card (credit card or A4 paper) held against the body
/// in a scan photo and returns `pixelsPerCm`. This converts pixel-based
/// shoulder/waist/hip widths into real centimeters — turning ratios into
/// measurements.
///
/// Pure Vision rectangle detection — no ML model, no network. Returns nil
/// (and the scan stays ratio-only) when nothing card-shaped is found.
nonisolated enum CalibrationCardDetector {

    /// Standard reference object the user can hold up.
    enum Reference: String, Sendable {
        case creditCard, a4Paper

        /// Long-edge cm. Credit card ISO/IEC 7810 ID-1 = 85.60mm; A4 = 297mm.
        var longEdgeCm: Double {
            switch self {
            case .creditCard: return 8.56
            case .a4Paper:    return 29.70
            }
        }
        /// Aspect ratio (long / short).
        var aspect: Double {
            switch self {
            case .creditCard: return 8.56 / 5.398   // ≈ 1.586
            case .a4Paper:    return 29.7 / 21.0    // ≈ 1.414
            }
        }
    }

    struct Result: Sendable {
        let reference: Reference
        let pixelsPerCm: Double
        /// 0..1 — Vision's reported confidence in the rectangle.
        let confidence: Double
    }

    /// Find the best-matching reference card in the image, if any.
    /// We prefer credit-card aspect (most common). Returns nil when no
    /// suitable rectangle is detected.
    static func detect(in image: UIImage) async -> Result? {
        guard let cg = image.cgImage else { return nil }
        let request = VNDetectRectanglesRequest()
        request.maximumObservations = 8
        request.minimumAspectRatio = 0.4
        request.maximumAspectRatio = 0.85       // capture credit card (~0.63) + A4 (~0.71)
        request.minimumSize = 0.04              // ignore tiny noise rects
        request.quadratureTolerance = 18        // tolerate slight tilt
        request.minimumConfidence = 0.6

        let handler = VNImageRequestHandler(cgImage: cg, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let observations = request.results, !observations.isEmpty else { return nil }

        let pxW = Double(cg.width)
        let pxH = Double(cg.height)

        var best: Result?
        for obs in observations {
            // Convert normalized quad to pixel-space long edge.
            let tl = CGPoint(x: obs.topLeft.x * pxW,     y: (1 - obs.topLeft.y) * pxH)
            let tr = CGPoint(x: obs.topRight.x * pxW,    y: (1 - obs.topRight.y) * pxH)
            let bl = CGPoint(x: obs.bottomLeft.x * pxW,  y: (1 - obs.bottomLeft.y) * pxH)
            let topEdge    = hypot(tr.x - tl.x, tr.y - tl.y)
            let leftEdge   = hypot(bl.x - tl.x, bl.y - tl.y)
            let longEdge   = max(topEdge, leftEdge)
            let shortEdge  = min(topEdge, leftEdge)
            guard shortEdge > 4 else { continue }
            let aspect = longEdge / shortEdge

            // Score each reference candidate by aspect proximity; pick best.
            let candidates: [(Reference, Double)] = [
                (.creditCard, abs(aspect - Reference.creditCard.aspect)),
                (.a4Paper,    abs(aspect - Reference.a4Paper.aspect))
            ]
            guard let (ref, aspectDelta) = candidates.min(by: { $0.1 < $1.1 }),
                  aspectDelta < 0.18 else { continue }

            let pxPerCm = longEdge / ref.longEdgeCm
            // Sanity-clamp: a typical phone shot will land 8–60 px/cm.
            guard pxPerCm > 3, pxPerCm < 200 else { continue }

            let confidence = Double(obs.confidence) * (1.0 - min(1.0, aspectDelta / 0.18))
            let result = Result(reference: ref, pixelsPerCm: pxPerCm, confidence: confidence)
            if best == nil || confidence > best!.confidence {
                best = result
            }
        }
        return best
    }
}
