import Foundation
import Vision
import UIKit
import CoreImage

nonisolated struct PoseResult {
    let landmarks: [String: CGPoint]   // normalized 0..1, origin top-left
    let confidenceAverage: Double
    let brightness: Double             // 0..1
    let centeringX: Double             // 0..1 (0.5 = centered)
    let coverageY: Double              // 0..1 (fraction of vertical frame covered by body)
    let symmetry: Double               // 0..1
    let shoulderWaistRatio: Double     // shoulders / hips
    let issues: [String]
}

nonisolated struct FaceMeasurements {
    let symmetry: Double          // 0..1
    let thirds: Double            // 0..1
    let canthalTiltDeg: Double    // degrees (positive = upturned)
    let eyeSpacingRatio: Double   // intercanthal / eye-width
    let jawRatio: Double          // jaw width / face height

    /// Robust trimmed-mean average across multiple measurements.
    /// Drops the single highest + lowest sample when 4+ are present so a
    /// bad-angle or bad-lighting photo can't swing the symmetry score.
    static func averaged(_ samples: [FaceMeasurements]) -> FaceMeasurements? {
        guard !samples.isEmpty else { return nil }
        if samples.count == 1 { return samples[0] }

        func trimmed(_ values: [Double]) -> Double {
            let sorted = values.sorted()
            let trimmedValues: [Double]
            if sorted.count >= 4 {
                trimmedValues = Array(sorted.dropFirst().dropLast())
            } else {
                trimmedValues = sorted
            }
            return trimmedValues.reduce(0, +) / Double(trimmedValues.count)
        }

        return FaceMeasurements(
            symmetry: trimmed(samples.map(\.symmetry)),
            thirds: trimmed(samples.map(\.thirds)),
            canthalTiltDeg: trimmed(samples.map(\.canthalTiltDeg)),
            eyeSpacingRatio: trimmed(samples.map(\.eyeSpacingRatio)),
            jawRatio: trimmed(samples.map(\.jawRatio))
        )
    }

    /// Sample-to-sample agreement (0..1). High when samples are consistent —
    /// used to scale AI confidence and decide if enough data has been gathered.
    static func consistency(_ samples: [FaceMeasurements]) -> Double {
        guard samples.count >= 2 else { return 0.5 }
        func spread(_ values: [Double]) -> Double {
            let mean = values.reduce(0, +) / Double(values.count)
            let variance = values.map { pow($0 - mean, 2) }.reduce(0, +) / Double(values.count)
            return sqrt(variance)
        }
        let symSpread = spread(samples.map(\.symmetry))
        let thirdsSpread = spread(samples.map(\.thirds))
        let canthalSpread = spread(samples.map(\.canthalTiltDeg)) / 20.0
        let total = symSpread + thirdsSpread + canthalSpread
        return max(0, min(1, 1 - total))
    }
}

nonisolated struct PoseService {
    static let shared = PoseService()

    func analyze(_ image: UIImage) async -> PoseResult? {
        guard let cg = image.cgImage else { return nil }
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cgImage: cg, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return analyzeFallback(cg: cg)
        }
        guard let obs = request.results?.first else {
            return analyzeFallback(cg: cg)
        }

        let names: [VNHumanBodyPoseObservation.JointName] = [
            .nose, .neck, .leftShoulder, .rightShoulder,
            .leftElbow, .rightElbow, .leftWrist, .rightWrist,
            .leftHip, .rightHip, .leftKnee, .rightKnee,
            .leftAnkle, .rightAnkle
        ]

        var landmarks: [String: CGPoint] = [:]
        var confSum: Double = 0
        var confCount: Int = 0
        var minY: CGFloat = 1, maxY: CGFloat = 0
        var sumX: CGFloat = 0, count: CGFloat = 0

        for name in names {
            if let p = try? obs.recognizedPoint(name), p.confidence > 0.1 {
                let pt = CGPoint(x: p.location.x, y: 1 - p.location.y)
                landmarks[name.rawValue.rawValue] = pt
                confSum += Double(p.confidence); confCount += 1
                minY = min(minY, pt.y); maxY = max(maxY, pt.y)
                sumX += pt.x; count += 1
            }
        }
        let confAvg = confCount > 0 ? confSum / Double(confCount) : 0
        let centerX = count > 0 ? Double(sumX / count) : 0.5
        let coverageY = Double(max(0, maxY - minY))

        var symmetry: Double = 0.8
        if let ls = landmarks["left_shoulder_joint"], let rs = landmarks["right_shoulder_joint"],
           let lh = landmarks["left_hip_joint"], let rh = landmarks["right_hip_joint"] {
            let shoulderDelta = Double(abs(ls.y - rs.y))
            let hipDelta = Double(abs(lh.y - rh.y))
            symmetry = max(0, min(1, 1 - (shoulderDelta + hipDelta) * 4))
        }

        var swRatio: Double = 1.4
        if let ls = landmarks["left_shoulder_joint"], let rs = landmarks["right_shoulder_joint"],
           let lh = landmarks["left_hip_joint"], let rh = landmarks["right_hip_joint"] {
            let shoulderW = Double(abs(ls.x - rs.x))
            let hipW = Double(abs(lh.x - rh.x))
            if hipW > 0.01 { swRatio = shoulderW / hipW }
        }

        let bright = brightness(cg: cg)

        // Very lenient quality checks — only flag truly problematic captures.
        // Users should be able to scan partial / waist-up framings without being blocked.
        var issues: [String] = []
        if confCount < 3 { issues.append("Body not detected — try a clearer photo") }
        if bright < 0.06 { issues.append("Lighting is too dark") }
        if bright > 0.98 { issues.append("Lighting is too bright") }
        if abs(centerX - 0.5) > 0.42 { issues.append("Try to center your body in frame") }
        // Allow partial body (waist-up, upper torso) — only flag when almost nothing is visible.
        if coverageY < 0.18 { issues.append("Move closer so more of your body is visible") }

        return PoseResult(
            landmarks: landmarks,
            confidenceAverage: confAvg,
            brightness: bright,
            centeringX: centerX,
            coverageY: coverageY,
            symmetry: symmetry,
            shoulderWaistRatio: swRatio,
            issues: issues
        )
    }

    /// Face landmark analysis (Vision = on-device equivalent of MediaPipe Face Mesh)
    func analyzeFace(_ image: UIImage) async -> FaceMeasurements? {
        guard let cg = image.cgImage else { return nil }
        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cgImage: cg, orientation: .up, options: [:])
        do { try handler.perform([request]) } catch { return nil }

        guard let face = request.results?.first,
              let lm = face.landmarks else { return nil }

        let bbox = face.boundingBox // normalized, origin bottom-left

        func denorm(_ p: CGPoint, region: VNFaceLandmarkRegion2D) -> CGPoint {
            // points are normalized within the region; region is within bbox; bbox within image
            let x = bbox.origin.x + p.x * bbox.size.width
            let y = bbox.origin.y + p.y * bbox.size.height
            return CGPoint(x: x, y: 1 - y) // flip y to top-left origin
        }

        func centroid(_ region: VNFaceLandmarkRegion2D?) -> CGPoint? {
            guard let r = region, !r.normalizedPoints.isEmpty else { return nil }
            let pts = r.normalizedPoints.map { denorm($0, region: r) }
            let sx = pts.reduce(0) { $0 + $1.x } / CGFloat(pts.count)
            let sy = pts.reduce(0) { $0 + $1.y } / CGFloat(pts.count)
            return CGPoint(x: sx, y: sy)
        }

        let leftEye = centroid(lm.leftEye)
        let rightEye = centroid(lm.rightEye)
        let nose = centroid(lm.nose)
        let outerLips = centroid(lm.outerLips)
        let faceContour = lm.faceContour

        // Symmetry: how well left/right eye and lips align around the face center
        var symmetry = 0.8
        if let le = leftEye, let re = rightEye, let n = nose {
            let midX = (le.x + re.x) / 2
            let dy = abs(le.y - re.y)
            let xOff = abs(n.x - midX)
            symmetry = max(0, min(1, 1 - Double(dy) * 8 - Double(xOff) * 4))
        }

        // Thirds: forehead/midface/lower-face balance
        var thirds = 0.75
        if let contour = faceContour, !contour.normalizedPoints.isEmpty,
           let le = leftEye, let re = rightEye, let l = outerLips {
            let pts = contour.normalizedPoints.map { denorm($0, region: contour) }
            let top = pts.map(\.y).min() ?? 0
            let bottom = pts.map(\.y).max() ?? 1
            let height = max(0.0001, Double(bottom - top))
            let eyeY = Double((le.y + re.y) / 2 - top)
            let lipY = Double(l.y - top)
            let upper = eyeY / height
            let middle = (lipY - eyeY) / height
            let lower = 1 - lipY / height
            // closer to 0.33 each = better
            let dev = abs(upper - 0.33) + abs(middle - 0.33) + abs(lower - 0.33)
            thirds = max(0, min(1, 1 - dev * 1.5))
        }

        // Canthal tilt degrees from eye corner slope
        var canthalDeg = 4.0
        if let leftEyeRegion = lm.leftEye, leftEyeRegion.normalizedPoints.count >= 2,
           let rightEyeRegion = lm.rightEye, rightEyeRegion.normalizedPoints.count >= 2 {
            let lPts = leftEyeRegion.normalizedPoints.map { denorm($0, region: leftEyeRegion) }
            let rPts = rightEyeRegion.normalizedPoints.map { denorm($0, region: rightEyeRegion) }
            // pick leftmost and rightmost as canthi for each eye
            let lInner = lPts.max(by: { $0.x < $1.x }) ?? .zero
            let lOuter = lPts.min(by: { $0.x < $1.x }) ?? .zero
            let rInner = rPts.min(by: { $0.x < $1.x }) ?? .zero
            let rOuter = rPts.max(by: { $0.x < $1.x }) ?? .zero
            let slopeL = atan2(Double(lInner.y - lOuter.y), Double(lOuter.x - lInner.x))
            let slopeR = atan2(Double(rOuter.y - rInner.y), Double(rOuter.x - rInner.x))
            canthalDeg = ((slopeL + slopeR) / 2) * 180 / .pi
        }

        // Eye spacing ratio: intercanthal / single eye width
        var eyeSpacing = 1.0
        if let le = leftEye, let re = rightEye,
           let leftEyeRegion = lm.leftEye, leftEyeRegion.normalizedPoints.count >= 2 {
            let lPts = leftEyeRegion.normalizedPoints.map { denorm($0, region: leftEyeRegion) }
            let eyeW = (lPts.map(\.x).max() ?? 0) - (lPts.map(\.x).min() ?? 0)
            let intercanthal = abs(re.x - le.x)
            if eyeW > 0.001 { eyeSpacing = Double(intercanthal / eyeW) }
        }

        // Jaw ratio: contour width at bottom third / face height
        var jawRatio = 0.78
        if let contour = faceContour, !contour.normalizedPoints.isEmpty {
            let pts = contour.normalizedPoints.map { denorm($0, region: contour) }
            let top = pts.map(\.y).min() ?? 0
            let bottom = pts.map(\.y).max() ?? 1
            let lower = pts.filter { $0.y > top + (bottom - top) * 0.66 }
            if !lower.isEmpty {
                let w = (lower.map(\.x).max() ?? 0) - (lower.map(\.x).min() ?? 0)
                let h = bottom - top
                if h > 0.001 { jawRatio = Double(w / h) }
            }
        }

        return FaceMeasurements(
            symmetry: symmetry,
            thirds: thirds,
            canthalTiltDeg: canthalDeg,
            eyeSpacingRatio: eyeSpacing,
            jawRatio: jawRatio
        )
    }

    private func analyzeFallback(cg: CGImage) -> PoseResult {
        PoseResult(
            landmarks: [:],
            confidenceAverage: 0,
            brightness: brightness(cg: cg),
            centeringX: 0.5,
            coverageY: 0,
            symmetry: 0.5,
            shoulderWaistRatio: 1.4,
            issues: ["Body not detected"]
        )
    }

    private func brightness(cg: CGImage) -> Double {
        let ci = CIImage(cgImage: cg)
        let extent = ci.extent
        let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: ci,
            kCIInputExtentKey: CIVector(cgRect: extent)
        ])
        guard let output = filter?.outputImage else { return 0.5 }
        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        context.render(output, toBitmap: &bitmap, rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8, colorSpace: nil)
        let r = Double(bitmap[0]) / 255
        let g = Double(bitmap[1]) / 255
        let b = Double(bitmap[2]) / 255
        return 0.299*r + 0.587*g + 0.114*b
    }
}
