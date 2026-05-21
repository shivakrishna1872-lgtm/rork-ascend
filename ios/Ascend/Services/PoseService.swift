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
    let shoulderWaistRatio: Double     // shoulders / hips (V-taper anchor)
    /// Estimated torso "waist" width relative to shoulder width.
    /// Smaller = leaner waist (lower body fat indicator).
    let waistShoulderRatio: Double
    /// Estimated thigh width relative to hip width (when legs visible).
    /// Higher with more leg mass; very high with higher BF on lower body.
    let thighHipRatio: Double
    /// Torso aspect (shoulder-to-hip vertical distance / shoulder width).
    /// Anchors muscle length proportions.
    let torsoAspect: Double
    /// Limb length asymmetry (left vs right arm + leg). 0..1, higher = more symmetric.
    let limbSymmetry: Double
    /// Shoulder slope tilt in degrees off horizontal. Used for posture.
    let shoulderTiltDeg: Double
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
        var shoulderTiltDeg: Double = 0
        if let ls = landmarks["left_shoulder_joint"], let rs = landmarks["right_shoulder_joint"],
           let lh = landmarks["left_hip_joint"], let rh = landmarks["right_hip_joint"] {
            let shoulderDelta = Double(abs(ls.y - rs.y))
            let hipDelta = Double(abs(lh.y - rh.y))
            symmetry = max(0, min(1, 1 - (shoulderDelta + hipDelta) * 4))
            let sx = Double(rs.x - ls.x)
            let sy = Double(rs.y - ls.y)
            if abs(sx) > 0.001 { shoulderTiltDeg = atan2(sy, sx) * 180 / .pi }
        }

        var swRatio: Double = 1.4
        if let ls = landmarks["left_shoulder_joint"], let rs = landmarks["right_shoulder_joint"],
           let lh = landmarks["left_hip_joint"], let rh = landmarks["right_hip_joint"] {
            let shoulderW = Double(abs(ls.x - rs.x))
            let hipW = Double(abs(lh.x - rh.x))
            if hipW > 0.01 { swRatio = shoulderW / hipW }
        }

        // Waist estimate: torso silhouette width at midpoint between shoulders and hips.
        // Sampled from luminance edges in the torso ROI for a body-fat proxy.
        var waistShoulderRatio: Double = 0.85
        if let ls = landmarks["left_shoulder_joint"], let rs = landmarks["right_shoulder_joint"],
           let lh = landmarks["left_hip_joint"], let rh = landmarks["right_hip_joint"] {
            let shoulderW = Double(abs(ls.x - rs.x))
            let shoulderY = Double((ls.y + rs.y) / 2)
            let hipY = Double((lh.y + rh.y) / 2)
            let centerX = Double((ls.x + rs.x + lh.x + rh.x) / 4)
            // Midpoint of torso (roughly navel line)
            let waistY = shoulderY + (hipY - shoulderY) * 0.58
            if let w = estimateBodyWidth(cg: cg, centerX: centerX, y: waistY, maxHalfWidth: shoulderW * 0.9),
               shoulderW > 0.001 {
                waistShoulderRatio = max(0.55, min(1.4, w / shoulderW))
            }
        }

        // Thigh / hip ratio: thigh width sampled below hip line.
        var thighHipRatio: Double = 1.0
        if let lh = landmarks["left_hip_joint"], let rh = landmarks["right_hip_joint"],
           let lk = landmarks["left_knee_joint"], let rk = landmarks["right_knee_joint"] {
            let hipW = Double(abs(lh.x - rh.x))
            let upperThighY = Double((lh.y + rh.y) / 2 + (lk.y + rk.y) / 2) / 2 * 0.5 + Double((lh.y + rh.y) / 2) * 0.5
            let centerX = Double((lh.x + rh.x) / 2)
            if let w = estimateBodyWidth(cg: cg, centerX: centerX, y: upperThighY, maxHalfWidth: hipW * 1.1),
               hipW > 0.001 {
                thighHipRatio = max(0.5, min(1.8, w / hipW))
            }
        }

        // Torso aspect: vertical span shoulder→hip divided by shoulder width.
        var torsoAspect: Double = 1.4
        if let ls = landmarks["left_shoulder_joint"], let rs = landmarks["right_shoulder_joint"],
           let lh = landmarks["left_hip_joint"], let rh = landmarks["right_hip_joint"] {
            let shoulderW = Double(abs(ls.x - rs.x))
            let span = Double(abs(((lh.y + rh.y) / 2) - ((ls.y + rs.y) / 2)))
            if shoulderW > 0.001 { torsoAspect = max(0.6, min(3.0, span / shoulderW)) }
        }

        // Limb symmetry: compare left vs right arm + leg lengths.
        var limbSymmetry: Double = 0.9
        func segLen(_ a: String, _ b: String) -> Double? {
            guard let pa = landmarks[a], let pb = landmarks[b] else { return nil }
            let dx = Double(pa.x - pb.x), dy = Double(pa.y - pb.y)
            return sqrt(dx*dx + dy*dy)
        }
        var diffs: [Double] = []
        if let la = segLen("left_shoulder_joint", "left_elbow_joint"),
           let ra = segLen("right_shoulder_joint", "right_elbow_joint"),
           max(la, ra) > 0.0001 {
            diffs.append(abs(la - ra) / max(la, ra))
        }
        if let lf = segLen("left_elbow_joint", "left_wrist_joint"),
           let rf = segLen("right_elbow_joint", "right_wrist_joint"),
           max(lf, rf) > 0.0001 {
            diffs.append(abs(lf - rf) / max(lf, rf))
        }
        if let ll = segLen("left_hip_joint", "left_knee_joint"),
           let rl = segLen("right_hip_joint", "right_knee_joint"),
           max(ll, rl) > 0.0001 {
            diffs.append(abs(ll - rl) / max(ll, rl))
        }
        if !diffs.isEmpty {
            let avgDiff = diffs.reduce(0, +) / Double(diffs.count)
            limbSymmetry = max(0, min(1, 1 - avgDiff * 2.5))
        }

        let bright = brightness(cg: cg)

        // Ultra-lenient quality checks — only flag completely broken captures.
        // Partial bodies, off-center framing, and unusual lighting all pass.
        var issues: [String] = []
        if confCount < 2 { issues.append("We couldn't see a body — any clearer shot works") }
        if bright < 0.03 { issues.append("Photo looks pitch black — a bit more light helps") }
        if bright > 0.99 { issues.append("Photo is fully blown out — try a softer light") }

        return PoseResult(
            landmarks: landmarks,
            confidenceAverage: confAvg,
            brightness: bright,
            centeringX: centerX,
            coverageY: coverageY,
            symmetry: symmetry,
            shoulderWaistRatio: swRatio,
            waistShoulderRatio: waistShoulderRatio,
            thighHipRatio: thighHipRatio,
            torsoAspect: torsoAspect,
            limbSymmetry: limbSymmetry,
            shoulderTiltDeg: shoulderTiltDeg,
            issues: issues
        )
    }

    /// Estimate body silhouette width at a horizontal slice by walking outward
    /// from `centerX` on the luminance gradient and finding the strongest edges.
    /// Returns normalized width (0..1) or nil if it can't find clean edges.
    private func estimateBodyWidth(cg: CGImage, centerX: Double, y: Double, maxHalfWidth: Double) -> Double? {
        let w = cg.width, h = cg.height
        guard w > 16, h > 16 else { return nil }
        let yPix = Int((y * Double(h)).rounded())
        guard yPix > 0, yPix < h - 1 else { return nil }
        let cxPix = Int((centerX * Double(w)).rounded())

        // Read one row of luminance.
        let bytesPerRow = w * 4
        var buffer = [UInt8](repeating: 0, count: bytesPerRow * 3)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &buffer,
            width: w, height: 3,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        // Render a 3-row slice centered on yPix.
        let srcY = max(0, min(h - 3, yPix - 1))
        ctx.draw(cg, in: CGRect(x: 0, y: -srcY, width: w, height: h))

        func lum(_ x: Int) -> Double {
            let i = bytesPerRow * 1 + x * 4 // middle row
            let r = Double(buffer[i]) / 255
            let g = Double(buffer[i + 1]) / 255
            let b = Double(buffer[i + 2]) / 255
            return 0.299*r + 0.587*g + 0.114*b
        }

        // Walk left/right and find largest local luminance gradient (edge of body).
        let centerLum = lum(min(w - 1, max(0, cxPix)))
        let maxPix = Int((maxHalfWidth * Double(w)).rounded())
        var leftEdge: Int? = nil
        var leftBestGrad: Double = 0
        for d in stride(from: 4, through: max(8, maxPix), by: 2) {
            let x = cxPix - d
            if x < 2 { break }
            let grad = abs(lum(x) - lum(x + 2))
            let contrastFromCenter = abs(lum(x) - centerLum)
            let score = grad + contrastFromCenter * 0.4
            if score > leftBestGrad && score > 0.06 {
                leftBestGrad = score; leftEdge = x
            }
        }
        var rightEdge: Int? = nil
        var rightBestGrad: Double = 0
        for d in stride(from: 4, through: max(8, maxPix), by: 2) {
            let x = cxPix + d
            if x > w - 3 { break }
            let grad = abs(lum(x) - lum(x - 2))
            let contrastFromCenter = abs(lum(x) - centerLum)
            let score = grad + contrastFromCenter * 0.4
            if score > rightBestGrad && score > 0.06 {
                rightBestGrad = score; rightEdge = x
            }
        }
        guard let le = leftEdge, let re = rightEdge, re > le else { return nil }
        return Double(re - le) / Double(w)
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
            waistShoulderRatio: 0.85,
            thighHipRatio: 1.0,
            torsoAspect: 1.4,
            limbSymmetry: 0.9,
            shoulderTiltDeg: 0,
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
