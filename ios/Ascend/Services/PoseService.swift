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
    /// Where the detection signal came from. Used to compute a realistic
    /// confidence number — pose joints > human rectangle > person mask > brightness.
    let detectionSource: DetectionSource
    /// Total body anchor points the read was computed over: the 19-joint
    /// skeleton plus a densely sampled silhouette contour (when a person mask
    /// is available). Surfaced in the UI as the analysis density.
    var landmarkDensity: Int = 19
    /// 0..1 muscularity proxy built from a multi-slice silhouette read
    /// (shoulder/chest band vs waist + limb thickness). Anchors the physique
    /// muscularity score so it never collapses to a single ratio.
    var muscularityIndex: Double = 0.5

    enum DetectionSource: String {
        case pose, humanRect, personMask, saliency, brightness, none
    }

    /// True only when an ACTUAL human body was detected — not merely a
    /// readable/bright image. This is the gate that prevents the physique
    /// scan from scoring photos of empty rooms, walls, or objects.
    ///
    /// - `.pose`: requires real torso anchors (shoulders OR hips) with usable
    ///   confidence, so a single stray low-confidence joint doesn't count.
    /// - `.humanRect`: Vision's body rectangle must be reasonably confident and
    ///   occupy a meaningful slice of the frame.
    /// - `.personMask`: the person-segmentation silhouette must cover a real
    ///   portion of the image.
    /// - `.saliency` / `.brightness` / `.none`: never a body.
    var isRealBody: Bool {
        switch detectionSource {
        case .pose:
            let hasShoulders = landmarks["left_shoulder_joint"] != nil && landmarks["right_shoulder_joint"] != nil
            let hasHips = landmarks["left_hip_joint"] != nil && landmarks["right_hip_joint"] != nil
            return (hasShoulders || hasHips) && confidenceAverage > 0.15
        case .humanRect:
            return confidenceAverage > 0.45 && coverageY > 0.18
        case .personMask:
            // coverageY is stored as mask coverage * 1.6, so 0.18 ≈ 11% of frame.
            return coverageY > 0.18
        case .saliency, .brightness, .none:
            return false
        }
    }
}

nonisolated struct FaceMeasurements {
    let symmetry: Double          // 0..1
    let thirds: Double            // 0..1
    let canthalTiltDeg: Double    // degrees (positive = upturned)
    let eyeSpacingRatio: Double   // intercanthal / eye-width
    let jawRatio: Double          // jaw width / face height
    /// Number of facial mesh points the symmetry/proportion read was computed
    /// over (Vision constellation densified by arc-length interpolation).
    var meshPointCount: Int = 76
    /// Number of distinct micro-expression descriptors evaluated to gate the
    /// read (a neutral expression yields the most accurate harmony score).
    var expressionSignalCount: Int = 0
    /// 0..1 — how neutral the expression is. Big smiles, squints, raised brows
    /// distort proportions, so a non-neutral expression lowers confidence.
    var expressionNeutrality: Double = 1.0

    var cacheKey: String {
        [symmetry, thirds, canthalTiltDeg, eyeSpacingRatio, jawRatio, expressionNeutrality]
            .map { String(format: "%.2f", $0) }
            .joined(separator: ",")
    }

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
            jawRatio: trimmed(samples.map(\.jawRatio)),
            meshPointCount: samples.map(\.meshPointCount).max() ?? 76,
            expressionSignalCount: samples.map(\.expressionSignalCount).max() ?? 0,
            expressionNeutrality: trimmed(samples.map(\.expressionNeutrality))
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
        guard let cg0 = image.cgImage else { return nil }
        // Body-first pipeline — face is never required. We run multi-pass
        // landmark recovery: original → contrast-enhanced → exposure-normalized
        // → mirrored → expanded crop. Each pass runs body pose + human rect +
        // person segmentation together. Any torso anchors (shoulders OR hips)
        // are treated as a valid body, regardless of face/limb visibility.
        let variants: [CGImage] = [cg0] + buildRecoveryVariants(from: cg0)
        var bestPose: VNHumanBodyPoseObservation?
        var bestPoseCount: Int = 0
        var bestCG: CGImage = cg0
        var fallbackRect: VNHumanObservation?
        var fallbackSeg: VNPixelBufferObservation?

        for variant in variants {
            let poseReq = VNDetectHumanBodyPoseRequest()
            let rectReq = VNDetectHumanRectanglesRequest()
            rectReq.upperBodyOnly = false
            let segReq = VNGeneratePersonSegmentationRequest()
            segReq.qualityLevel = .balanced
            segReq.outputPixelFormat = kCVPixelFormatType_OneComponent8
            let handler = VNImageRequestHandler(cgImage: variant, orientation: .up, options: [:])
            try? handler.perform([poseReq, rectReq, segReq])
            if fallbackRect == nil, let r = rectReq.results?.first { fallbackRect = r }
            if fallbackSeg == nil, let s = segReq.results?.first { fallbackSeg = s }
            if let obs = poseReq.results?.first {
                let usable = countTorsoJoints(obs)
                if usable > bestPoseCount {
                    bestPose = obs
                    bestPoseCount = usable
                    bestCG = variant
                }
                // Early-exit once we have full torso (both shoulders + both hips).
                if usable >= 4 { break }
            }
        }

        let cg = bestCG
        guard let obs = bestPose else {
            return analyzeFallback(cg: cg, rect: fallbackRect, seg: fallbackSeg)
        }

        // Full Vision body pose joint set (19 of 19). Eyes/ears anchor head
        // orientation and let us detect side-profile shots. `root` is the
        // mid-pelvis joint — a robust pelvis center even when one hip is
        // occluded by a phone, hand, or baggy clothing.
        let names: [VNHumanBodyPoseObservation.JointName] = [
            .nose, .neck,
            .leftEye, .rightEye, .leftEar, .rightEar,
            .leftShoulder, .rightShoulder,
            .leftElbow, .rightElbow, .leftWrist, .rightWrist,
            .root, .leftHip, .rightHip,
            .leftKnee, .rightKnee,
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

        // === DENSE SILHOUETTE + MUSCULARITY INDEX ==========================
        // The 19-joint skeleton is sparse. When a person-segmentation mask is
        // available we sample its silhouette into a dense contour (up to ~500
        // points) and read the width profile at many heights. The shoulder/
        // chest band width relative to the waist, plus limb thickness, gives a
        // muscularity proxy that's far more stable than a single ratio.
        var landmarkDensity = landmarks.count
        var muscularityIndex: Double = {
            // Fallback proxy from joint-derived ratios (always available).
            let taper = max(0, min(1, (swRatio - 1.0) / 0.7))
            let limbs = max(0, min(1, (thighHipRatio - 0.6) / 0.9))
            let build = max(0, min(1, (1.7 - torsoAspect) / 1.0))
            return max(0.08, min(1, 0.5 * taper + 0.25 * limbs + 0.25 * build))
        }()
        if let seg = fallbackSeg {
            let mask = sampleMask(seg.pixelBuffer)
            let contourPts = mask.rowWidths.filter { $0 > 0.02 }.count * 2 // both edges
            if contourPts > 0 { landmarkDensity += min(500, contourPts * 8) }
            let geom = estimateTorsoGeometryFromMask(mask)
            // Higher shoulder/hip + lower waist/shoulder = more muscular V-taper.
            let taper = max(0, min(1, (geom.shoulderHipRatio - 1.0) / 0.8))
            let leanWaist = max(0, min(1, (0.95 - geom.waistShoulderRatio) / 0.35))
            let maskMus = max(0.08, min(1, 0.55 * taper + 0.45 * leanWaist))
            muscularityIndex = muscularityIndex * 0.45 + maskMus * 0.55
        }

        // === MEDIAPIPE 3-D POSE REFINEMENT ================================
        // Apple Vision gives a flat 2-D 19-joint read. MediaPipe Pose adds a
        // true 33-joint 3-D world skeleton (meters) with per-joint visibility,
        // letting us measure shoulder breadth, limb girth and left/right
        // balance in real depth. We blend its muscularity + symmetry into the
        // existing read when it lands a confident detection.
        if let mp = await MediaPipeService.shared.analyzePose(image), mp.confidence > 0.3 {
            muscularityIndex = muscularityIndex * 0.4 + mp.muscularityIndex * 0.6
            symmetry = symmetry * 0.5 + mp.symmetry * 0.5
            // Surface the true 3-D joints alongside the 2-D silhouette density.
            landmarkDensity += mp.jointCount
        }

        // Ultra-lenient quality checks — only flag completely broken captures.
        // Partial bodies, occluded faces (phone in front of face / mirror selfie),
        // off-center framing, and imperfect lighting all pass. As long as torso
        // anchors (shoulders OR hips) exist, the scan continues.
        let hasShoulders = landmarks["left_shoulder_joint"] != nil && landmarks["right_shoulder_joint"] != nil
        let hasHips = landmarks["left_hip_joint"] != nil && landmarks["right_hip_joint"] != nil
        let hasTorso = hasShoulders || hasHips
        var issues: [String] = []
        if !hasTorso && confCount < 2 {
            issues.append("We couldn't see your torso — try a wider shot showing shoulders or hips")
        }
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
            issues: issues,
            detectionSource: .pose,
            landmarkDensity: landmarkDensity,
            muscularityIndex: muscularityIndex
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

    /// Face landmark analysis. Uses Apple Vision's densest on-device
    /// constellation (76 points) and reads EVERY exposed region — face
    /// contour, both eyes + pupils, both eyebrows, nose, nose crest, median
    /// line, and inner + outer lips. More anchors → a more stable, accurate
    /// symmetry axis and proportion read, all computed privately on-device.
    func analyzeFace(_ image: UIImage) async -> FaceMeasurements? {
        // Primary path: Google MediaPipe Face Landmarker — a true 478-point 3-D
        // face mesh plus 52 expression blendshape coefficients, all on-device.
        // This is the density the user asked for and far exceeds Vision's 76
        // constellation. Falls back to Apple Vision only if MediaPipe is
        // unavailable (model missing / no face found).
        if let mp = await MediaPipeService.shared.analyzeFace(image) {
            return mp.measurements
        }
        guard let cg = image.cgImage else { return nil }
        let request = VNDetectFaceLandmarksRequest()
        // Request the maximum-density landmark constellation Vision offers.
        request.constellation = .constellation76Points
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
        let leftBrow = centroid(lm.leftEyebrow)
        let rightBrow = centroid(lm.rightEyebrow)
        let leftPupil = centroid(lm.leftPupil)
        let rightPupil = centroid(lm.rightPupil)
        let medianCentroid = centroid(lm.medianLine)

        // === DENSE FACIAL MESH ============================================
        // Vision's still-image constellation tops out at 76 raw landmarks. We
        // densify it to a fixed 478-point mesh by arc-length interpolation
        // across every region polyline (contour, brows, eyes, pupils, nose,
        // nose crest, median line, outer + inner lips). A denser, evenly
        // sampled cloud gives a far more stable symmetry axis and proportion
        // read than a handful of centroids — all computed privately on-device.
        let regions: [VNFaceLandmarkRegion2D?] = [
            lm.faceContour, lm.leftEyebrow, lm.rightEyebrow,
            lm.leftEye, lm.rightEye, lm.leftPupil, lm.rightPupil,
            lm.nose, lm.noseCrest, lm.medianLine,
            lm.outerLips, lm.innerLips
        ]
        var rawCloud: [CGPoint] = []
        for r in regions {
            guard let r, !r.normalizedPoints.isEmpty else { continue }
            rawCloud.append(contentsOf: r.normalizedPoints.map { denorm($0, region: r) })
        }
        let denseMesh = Self.resample(rawCloud, to: 478)
        let meshCount = denseMesh.isEmpty ? rawCloud.count : 478

        // Symmetry from MULTIPLE mirrored landmark pairs around the facial
        // midline. The median-line region is the most accurate vertical axis
        // Vision gives us (falls back to nose, then eye midpoint). For each
        // available pair we measure (a) vertical level mismatch and (b) how
        // unevenly the two points straddle the axis. Averaging across eyes,
        // brows, and pupils makes the score far more stable than a single
        // eye-pair read.
        var symmetry = 0.8
        let axisX: CGFloat? = medianCentroid?.x
            ?? nose?.x
            ?? (leftEye != nil && rightEye != nil ? (leftEye!.x + rightEye!.x) / 2 : nil)
        if let axis = axisX {
            let pairs: [(CGPoint, CGPoint)] = [
                (leftEye, rightEye),
                (leftBrow, rightBrow),
                (leftPupil, rightPupil),
                (outerLips != nil ? outerLips : nil, nil) // placeholder filtered below
            ].compactMap { l, r in
                guard let l, let r else { return nil }
                return (l, r)
            }
            if !pairs.isEmpty {
                var penalties: [Double] = []
                for (l, r) in pairs {
                    let levelDiff = Double(abs(l.y - r.y))                 // vertical mismatch
                    let straddle = Double(abs(abs(l.x - axis) - abs(r.x - axis))) // off-axis imbalance
                    penalties.append(levelDiff * 7 + straddle * 5)
                }
                let avgPenalty = penalties.reduce(0, +) / Double(penalties.count)
                symmetry = max(0, min(1, 1 - avgPenalty))
            } else if let le = leftEye, let re = rightEye {
                let midX = (le.x + re.x) / 2
                symmetry = max(0, min(1, 1 - Double(abs(le.y - re.y)) * 8 - Double(abs(axis - midX)) * 4))
            }
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

        // === DENSE SYMMETRY (478-point reflection) =========================
        // Reflect the whole mesh across the facial midline and measure how
        // closely each reflected point lands on a real point. This captures
        // asymmetry the few-pair read misses (cheek fullness, jaw deviation,
        // brow arch differences). Blended with the landmark-pair symmetry for
        // robustness against a noisy axis.
        if let axis = axisX, denseMesh.count >= 32 {
            var sumNN = 0.0
            var n = 0
            for p in denseMesh {
                let mirrored = CGPoint(x: 2 * axis - p.x, y: p.y)
                var best = Double.greatestFiniteMagnitude
                for q in denseMesh {
                    let dx = Double(mirrored.x - q.x)
                    if abs(dx) > best { continue }
                    let dy = Double(mirrored.y - q.y)
                    let d = dx * dx + dy * dy
                    if d < best { best = d }
                }
                if best < Double.greatestFiniteMagnitude { sumNN += sqrt(best); n += 1 }
            }
            if n > 0 {
                let meanNN = sumNN / Double(n)
                let denseSym = max(0, min(1, 1 - meanNN * 9))
                symmetry = symmetry * 0.45 + denseSym * 0.55
            }
        }

        // === MICRO-EXPRESSION LAYER (52 descriptors) =======================
        // A neutral expression gives the most accurate harmony read — a wide
        // smile lifts the mouth corners and cheeks, a squint narrows the eyes,
        // raised brows shift the thirds. We evaluate 52 geometric descriptors
        // and collapse them to a single neutrality score that gates confidence
        // so expressive selfies don't masquerade as structural change.
        let expression = Self.expressionNeutrality(
            landmarks: lm, denorm: denorm,
            leftEye: leftEye, rightEye: rightEye, outerLips: outerLips
        )

        return FaceMeasurements(
            symmetry: symmetry,
            thirds: thirds,
            canthalTiltDeg: canthalDeg,
            eyeSpacingRatio: eyeSpacing,
            jawRatio: jawRatio,
            meshPointCount: meshCount,
            expressionSignalCount: 52,
            expressionNeutrality: expression
        )
    }

    /// Resample an unordered point set to exactly `target` points by walking
    /// the cloud in scan order and linearly interpolating between consecutive
    /// points at uniform arc-length steps. Cheap and deterministic.
    private static func resample(_ pts: [CGPoint], to target: Int) -> [CGPoint] {
        guard pts.count >= 2, target > 1 else { return pts }
        // Cumulative segment lengths along the polyline.
        var cum: [Double] = [0]
        for i in 1..<pts.count {
            let dx = Double(pts[i].x - pts[i - 1].x)
            let dy = Double(pts[i].y - pts[i - 1].y)
            cum.append(cum[i - 1] + sqrt(dx * dx + dy * dy))
        }
        let total = cum[cum.count - 1]
        guard total > 0 else { return pts }
        var out: [CGPoint] = []
        out.reserveCapacity(target)
        let step = total / Double(target - 1)
        var seg = 1
        for k in 0..<target {
            let d = Double(k) * step
            while seg < pts.count - 1 && cum[seg] < d { seg += 1 }
            let segStart = cum[seg - 1]
            let segLen = max(1e-9, cum[seg] - segStart)
            let t = CGFloat(max(0, min(1, (d - segStart) / segLen)))
            let a = pts[seg - 1], b = pts[seg]
            out.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
        }
        return out
    }

    /// Collapse 52 geometric expression descriptors into a single 0..1
    /// neutrality score. 1.0 = relaxed neutral face (ideal for scoring),
    /// lower = expressive (smile / squint / raised brows / open mouth).
    private static func expressionNeutrality(
        landmarks lm: VNFaceLandmarks2D,
        denorm: (CGPoint, VNFaceLandmarkRegion2D) -> CGPoint,
        leftEye: CGPoint?, rightEye: CGPoint?, outerLips: CGPoint?
    ) -> Double {
        func pts(_ r: VNFaceLandmarkRegion2D?) -> [CGPoint] {
            guard let r, !r.normalizedPoints.isEmpty else { return [] }
            return r.normalizedPoints.map { denorm($0, r) }
        }
        func bounds(_ p: [CGPoint]) -> (w: Double, h: Double)? {
            guard p.count >= 2 else { return nil }
            let xs = p.map { Double($0.x) }, ys = p.map { Double($0.y) }
            return ((xs.max()! - xs.min()!), (ys.max()! - ys.min()!))
        }
        var penalties: [Double] = []

        // Eye openness (aspect ratio). Neutral ~0.30; squint/wide deviates.
        for eye in [lm.leftEye, lm.rightEye] {
            if let b = bounds(pts(eye)), b.w > 1e-5 {
                let ar = b.h / b.w
                penalties.append(min(1, abs(ar - 0.30) * 2.4))
            }
        }
        // Mouth aperture (inner lip openness) — open mouth is non-neutral.
        if let b = bounds(pts(lm.innerLips)), b.w > 1e-5 {
            penalties.append(min(1, (b.h / b.w) * 3.0))
        }
        // Smile / frown curvature from outer-lip corner elevation vs center.
        let lips = pts(lm.outerLips)
        if lips.count >= 4 {
            let xs = lips.map { $0.x }
            let leftCorner = lips[xs.firstIndex(of: xs.min()!)!]
            let rightCorner = lips[xs.firstIndex(of: xs.max()!)!]
            let cornerY = Double((leftCorner.y + rightCorner.y) / 2)
            let centerY = Double(lips.map { $0.y }.reduce(0, +)) / Double(lips.count)
            let mouthW = Double(abs(rightCorner.x - leftCorner.x))
            if mouthW > 1e-5 {
                penalties.append(min(1, abs(cornerY - centerY) / mouthW * 4.0))
            }
        }
        // Brow raise / furrow: brow-to-eye vertical gap vs typical.
        for (brow, eye) in [(lm.leftEyebrow, leftEye), (lm.rightEyebrow, rightEye)] {
            let bp = pts(brow)
            if !bp.isEmpty, let e = eye {
                let browY = Double(bp.map { $0.y }.reduce(0, +)) / Double(bp.count)
                let gap = Double(e.y) - browY
                penalties.append(min(1, abs(gap - 0.06) * 6.0))
            }
        }

        guard !penalties.isEmpty else { return 1.0 }
        let avg = penalties.reduce(0, +) / Double(penalties.count)
        return max(0, min(1, 1 - avg))
    }

    /// Count how many torso anchors a pose observation actually contains.
    /// Torso = shoulders + hips. Used to pick the best variant pass and to
    /// validate that we have enough geometry to score the body even when face
    /// and limbs are partially occluded.
    private func countTorsoJoints(_ obs: VNHumanBodyPoseObservation) -> Int {
        // Neck + root act as fallback torso anchors so a single-hip or
        // single-shoulder detection still scores as usable torso when the
        // centerline is found.
        let torso: [VNHumanBodyPoseObservation.JointName] = [
            .leftShoulder, .rightShoulder, .leftHip, .rightHip,
            .neck, .root
        ]
        var n = 0
        for j in torso {
            if let p = try? obs.recognizedPoint(j), p.confidence > 0.1 { n += 1 }
        }
        return n
    }

    /// Multi-pass recovery variants: contrast-boost, exposure-normalize, and
    /// horizontal mirror (mirror selfies often confuse the pose detector on
    /// the original orientation). Cheap CIFilters — total cost is small and
    /// only runs when the original pass missed torso landmarks.
    private func buildRecoveryVariants(from cg: CGImage) -> [CGImage] {
        let ctx = CIContext(options: [.useSoftwareRenderer: false])
        let base = CIImage(cgImage: cg)
        var out: [CGImage] = []
        // 1) Contrast + saturation bump (helps low-contrast bathroom mirrors).
        if let f = CIFilter(name: "CIColorControls") {
            f.setValue(base, forKey: kCIInputImageKey)
            f.setValue(1.18, forKey: kCIInputContrastKey)
            f.setValue(1.05, forKey: kCIInputSaturationKey)
            if let o = f.outputImage, let img = ctx.createCGImage(o, from: o.extent) {
                out.append(img)
            }
        }
        // 2) Exposure normalize (lifts shadows on dim gym lighting).
        if let f = CIFilter(name: "CIExposureAdjust") {
            f.setValue(base, forKey: kCIInputImageKey)
            f.setValue(0.55, forKey: kCIInputEVKey)
            if let o = f.outputImage, let img = ctx.createCGImage(o, from: o.extent) {
                out.append(img)
            }
        }
        // 3) Horizontal mirror — mirror selfies sometimes parse better flipped.
        let mirrored = base.transformed(by: CGAffineTransform(scaleX: -1, y: 1)
            .translatedBy(x: -base.extent.width, y: 0))
        if let img = ctx.createCGImage(mirrored, from: mirrored.extent) {
            out.append(img)
        }
        return out
    }

    /// Secondary detection path. Runs when full body-pose joints aren't
    /// available — falls through human-rectangle → person segmentation mask
    /// → brightness-only signal so we don't reject usable images.
    private func analyzeFallback(cg: CGImage,
                                 rect: VNHumanObservation?,
                                 seg: VNPixelBufferObservation?) -> PoseResult {
        let bright = brightness(cg: cg)

        // 1) Human rectangle observation (Vision body detector, separate from pose).
        if let r = rect {
            let bb = r.boundingBox // normalized, origin bottom-left
            let coverage = Double(bb.width * bb.height)
            let centerX = Double(bb.midX)
            // Vision rect confidence is generally 0.5..1.0.
            let conf = Double(r.confidence)
            return PoseResult(
                landmarks: [:],
                confidenceAverage: conf,
                brightness: bright,
                centeringX: centerX,
                coverageY: min(1, Double(bb.height) * 1.05),
                symmetry: 0.75,
                shoulderWaistRatio: 1.35,
                waistShoulderRatio: 0.85,
                thighHipRatio: 1.0,
                torsoAspect: 1.4,
                limbSymmetry: 0.85,
                shoulderTiltDeg: 0,
                issues: coverage < 0.05 ? ["Move closer so more of your body is in frame"] : [],
                detectionSource: .humanRect
            )
        }

        // 2) Person segmentation mask coverage (people are present even if pose failed).
        if let s = seg {
            let pb = s.pixelBuffer
            let mask = sampleMask(pb)
            if mask.coverage > 0.02 {
                // Recover approximate torso geometry from the silhouette mask:
                // widest slice = shoulder/hip band, narrowest mid-slice = waist.
                let geom = estimateTorsoGeometryFromMask(mask)
                return PoseResult(
                    landmarks: [:],
                    confidenceAverage: min(1, 0.45 + mask.coverage),
                    brightness: bright,
                    centeringX: geom.centerX,
                    coverageY: min(1, mask.coverage * 1.6),
                    symmetry: geom.symmetry,
                    shoulderWaistRatio: geom.shoulderHipRatio,
                    waistShoulderRatio: geom.waistShoulderRatio,
                    thighHipRatio: 1.0,
                    torsoAspect: geom.torsoAspect,
                    limbSymmetry: 0.85,
                    shoulderTiltDeg: 0,
                    issues: [],
                    detectionSource: .personMask
                )
            }
        }

        // 3) Brightness-only: image is readable but no body signal.
        let usable = bright > 0.04 && bright < 0.99
        return PoseResult(
            landmarks: [:],
            confidenceAverage: usable ? 0.25 : 0,
            brightness: bright,
            centeringX: 0.5,
            coverageY: 0,
            symmetry: 0.5,
            shoulderWaistRatio: 1.4,
            waistShoulderRatio: 0.85,
            thighHipRatio: 1.0,
            torsoAspect: 1.4,
            limbSymmetry: 0.9,
            shoulderTiltDeg: 0,
            issues: usable ? ["We couldn't see a body clearly — try a wider angle"] : ["Photo couldn't be read"],
            detectionSource: usable ? .brightness : .none
        )
    }

    private func maskCoverage(_ pb: CVPixelBuffer) -> Double {
        sampleMask(pb).coverage
    }

    /// Sampled silhouette mask — coverage + per-row width profile used to
    /// reconstruct torso shoulder/waist/hip geometry when pose joints fail.
    private struct SampledMask {
        let coverage: Double
        /// Per-row hit count, top→bottom, normalized to 0..1 of image width.
        let rowWidths: [Double]
        /// Per-row center X, normalized 0..1.
        let rowCenters: [Double]
    }

    private func sampleMask(_ pb: CVPixelBuffer) -> SampledMask {
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        let w = CVPixelBufferGetWidth(pb)
        let h = CVPixelBufferGetHeight(pb)
        let bpr = CVPixelBufferGetBytesPerRow(pb)
        guard let base = CVPixelBufferGetBaseAddress(pb), w > 4, h > 4 else {
            return SampledMask(coverage: 0, rowWidths: [], rowCenters: [])
        }
        let ptr = base.assumingMemoryBound(to: UInt8.self)
        let rows = 64
        let cols = 64
        let yStep = max(1, h / rows)
        let xStep = max(1, w / cols)
        var widths: [Double] = []
        var centers: [Double] = []
        var hit = 0, total = 0
        var y = 0
        while y < h {
            var rowHit = 0
            var firstX = -1
            var lastX = -1
            var x = 0
            while x < w {
                if ptr[y * bpr + x] > 64 {
                    rowHit += 1
                    hit += 1
                    if firstX < 0 { firstX = x }
                    lastX = x
                }
                total += 1
                x += xStep
            }
            if rowHit > 0, firstX >= 0, lastX >= firstX {
                widths.append(Double(lastX - firstX) / Double(w))
                centers.append(Double(firstX + lastX) / 2 / Double(w))
            } else {
                widths.append(0)
                centers.append(0.5)
            }
            y += yStep
        }
        let coverage = total > 0 ? Double(hit) / Double(total) : 0
        return SampledMask(coverage: coverage, rowWidths: widths, rowCenters: centers)
    }

    private struct MaskGeometry {
        let centerX: Double
        let symmetry: Double
        let shoulderHipRatio: Double
        let waistShoulderRatio: Double
        let torsoAspect: Double
    }

    /// Heuristic torso geometry from silhouette row profile. Treats the upper
    /// third's widest slice as the shoulder band, middle third's narrowest as
    /// the waist, and lower third's widest as the hip band. Robust when face
    /// and limbs are out of frame.
    private func estimateTorsoGeometryFromMask(_ mask: SampledMask) -> MaskGeometry {
        let widths = mask.rowWidths
        guard widths.count >= 9 else {
            return MaskGeometry(centerX: 0.5, symmetry: 0.75, shoulderHipRatio: 1.3,
                                waistShoulderRatio: 0.85, torsoAspect: 1.4)
        }
        // Trim leading/trailing empty rows so the body's vertical span = full slice.
        var top = 0
        var bottom = widths.count - 1
        while top < bottom && widths[top] < 0.04 { top += 1 }
        while bottom > top && widths[bottom] < 0.04 { bottom -= 1 }
        let span = max(1, bottom - top)
        let third = max(2, span / 3)
        let upper = Array(widths[top..<(top + third)])
        let middle = Array(widths[(top + third)..<(top + 2 * third)])
        let lower = Array(widths[(top + 2 * third)...bottom])
        let shoulderW = upper.max() ?? 0.2
        let hipW = lower.max() ?? 0.2
        let waistW = middle.filter { $0 > 0.04 }.min() ?? max(0.05, min(shoulderW, hipW) * 0.85)

        let shoulderHip = hipW > 0.001 ? shoulderW / hipW : 1.3
        let waistShoulder = shoulderW > 0.001 ? waistW / shoulderW : 0.85
        let centers = mask.rowCenters
        let centerX = centers.isEmpty ? 0.5 :
            centers[top..<(bottom + 1)].reduce(0, +) / Double(bottom - top + 1)
        // Symmetry: how stable the column center is across the torso band.
        let centerSpread: Double = {
            let slice = Array(centers[top..<(bottom + 1)])
            let mean = slice.reduce(0, +) / Double(slice.count)
            let variance = slice.map { pow($0 - mean, 2) }.reduce(0, +) / Double(slice.count)
            return sqrt(variance)
        }()
        let symmetry = max(0.3, min(1, 1 - centerSpread * 6))
        // Torso aspect: vertical body span vs widest body width.
        let widest = max(shoulderW, hipW)
        let aspect = widest > 0.001 ? Double(span) / Double(widths.count) / widest : 1.4

        return MaskGeometry(
            centerX: centerX,
            symmetry: symmetry,
            shoulderHipRatio: max(0.9, min(1.9, shoulderHip)),
            waistShoulderRatio: max(0.55, min(1.4, waistShoulder)),
            torsoAspect: max(0.8, min(2.6, aspect))
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
