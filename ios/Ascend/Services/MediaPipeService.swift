import Foundation
import UIKit
import MediaPipeTasksVision

/// Dense facial geometry produced by Google MediaPipe Face Landmarker.
/// 478 3D face-mesh landmarks + 52 expression blendshape coefficients,
/// all computed entirely on-device (no upload, fully private).
nonisolated struct MediaPipeFaceResult {
    /// Geometry distilled into the same measurement shape the scoring engine
    /// already consumes — but derived from 478 mesh points instead of 76.
    let measurements: FaceMeasurements
    /// Raw 478-point normalized mesh (x, y in 0..1, origin top-left).
    let meshPointCount: Int
    /// Number of blendshape expression coefficients evaluated (52).
    let blendshapeCount: Int
}

/// Facial-adiposity cross-signal derived from the Google MediaPipe 478-point
/// face mesh. Facial fullness — cheek/jaw width relative to face height plus a
/// lower-face roundness read — is a documented correlate of overall body fat.
/// Used purely as an INDEPENDENT cross-check for the physique body-fat /
/// conditioning estimate, never as the sole source.
nonisolated struct MediaPipeFaceAdiposity {
    /// 0..1 — higher = fuller / softer face (more adiposity).
    let adiposityIndex: Double
    /// Body-fat % estimate implied by facial fullness alone (clamped 6–38).
    let impliedBodyFatPercent: Double
    /// Number of mesh points the read was computed over (478).
    let meshPointCount: Int
    /// 0..1 — higher = leaner / sharper facial definition.
    var leannessIndex: Double { max(0, min(1, 1 - adiposityIndex)) }
}

/// Dense body geometry produced by Google MediaPipe Pose Landmarker.
/// 33 landmarks with real 3-D world coordinates (meters) + per-joint
/// visibility — a true depth-aware skeleton, unlike a flat 2-D read.
nonisolated struct MediaPipePoseResult {
    /// Normalized image landmarks keyed by Vision-compatible joint names so
    /// they can flow straight into the existing physique math.
    let landmarks: [String: CGPoint]
    /// 0..1 muscularity proxy built from the 3-D world skeleton (shoulder
    /// breadth vs waist depth/width and limb girth).
    let muscularityIndex: Double
    /// 0..1 left/right balance from mirrored 3-D joint distances.
    let symmetry: Double
    /// Average per-joint visibility (detection confidence).
    let confidence: Double
    /// Number of true 3-D joints recovered (max 33).
    let jointCount: Int
}

/// Serialized, lazily-initialized wrapper around the MediaPipe Tasks Vision
/// landmarkers. An `actor` keeps the blocking `detect` calls off the main
/// thread and serializes access to the non-Sendable landmarker instances.
actor MediaPipeService {
    static let shared = MediaPipeService()

    private var faceLandmarker: FaceLandmarker?
    private var poseLandmarker: PoseLandmarker?
    private var faceInitFailed = false
    private var poseInitFailed = false

    // MARK: - Face (478 landmarks + 52 blendshapes)

    private func ensureFaceLandmarker() -> FaceLandmarker? {
        if let faceLandmarker { return faceLandmarker }
        if faceInitFailed { return nil }
        guard let path = Bundle.main.path(forResource: "face_landmarker", ofType: "task") else {
            faceInitFailed = true
            return nil
        }
        let options = FaceLandmarkerOptions()
        options.baseOptions.modelAssetPath = path
        options.runningMode = .image
        options.numFaces = 1
        options.outputFaceBlendshapes = true
        do {
            let lm = try FaceLandmarker(options: options)
            faceLandmarker = lm
            return lm
        } catch {
            faceInitFailed = true
            return nil
        }
    }

    func analyzeFace(_ image: UIImage) -> MediaPipeFaceResult? {
        guard let landmarker = ensureFaceLandmarker(),
              let mpImage = try? MPImage(uiImage: image),
              let result = try? landmarker.detect(image: mpImage),
              let mesh = result.faceLandmarks.first, mesh.count >= 400 else {
            return nil
        }

        // Convert the normalized 3-D mesh to 2-D points (origin top-left, which
        // MediaPipe already uses) for the geometry read.
        let pts: [CGPoint] = mesh.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) }

        func p(_ i: Int) -> CGPoint? { i >= 0 && i < pts.count ? pts[i] : nil }

        // Canonical MediaPipe Face Mesh indices.
        let noseTip = p(1)
        let chin = p(152)
        let foreheadTop = p(10)
        let leftEyeOuter = p(33),  leftEyeInner = p(133)
        let rightEyeInner = p(362), rightEyeOuter = p(263)
        let leftBrow = p(105), rightBrow = p(334)
        let noseBase = p(2)
        let leftJaw = p(172), rightJaw = p(397)
        let mouthLeft = p(61), mouthRight = p(291)

        // --- Symmetry: reflect the whole mesh across the facial midline and
        // measure how closely each reflected point lands on a real point.
        let axisX: CGFloat = noseTip?.x
            ?? ((leftEyeInner?.x ?? 0.5) + (rightEyeInner?.x ?? 0.5)) / 2
        var symmetry = 0.85
        do {
            // Subsample for the O(n^2) nearest-neighbour pass.
            let sample = stride(from: 0, to: pts.count, by: 3).map { pts[$0] }
            var sumNN = 0.0
            var n = 0
            for q in sample {
                let mx = 2 * axisX - q.x
                var best = Double.greatestFiniteMagnitude
                for r in sample {
                    let dx = Double(mx - r.x)
                    if abs(dx) > best { continue }
                    let dy = Double(q.y - r.y)
                    let d = dx * dx + dy * dy
                    if d < best { best = d }
                }
                if best < .greatestFiniteMagnitude { sumNN += best.squareRoot(); n += 1 }
            }
            if n > 0 {
                let meanNN = sumNN / Double(n)
                symmetry = max(0, min(1, 1 - meanNN * 11))
            }
        }

        // --- Thirds: trichion→brow, brow→nose-base, nose-base→chin.
        var thirds = 0.75
        if let top = foreheadTop, let bottom = chin,
           let lb = leftBrow, let rb = rightBrow, let nb = noseBase {
            let height = max(0.0001, Double(bottom.y - top.y))
            let browY = Double((lb.y + rb.y) / 2 - top.y)
            let noseY = Double(nb.y - top.y)
            let upper = browY / height
            let middle = (noseY - browY) / height
            let lower = 1 - noseY / height
            let dev = abs(upper - 0.33) + abs(middle - 0.33) + abs(lower - 0.33)
            thirds = max(0, min(1, 1 - dev * 1.5))
        }

        // --- Canthal tilt: average of both eyes' inner→outer corner slope.
        var canthalDeg = 4.0
        if let lo = leftEyeOuter, let li = leftEyeInner,
           let ro = rightEyeOuter, let ri = rightEyeInner {
            // y grows downward, so a raised outer corner means smaller y.
            let slopeL = atan2(Double(li.y - lo.y), Double(lo.x - li.x))
            let slopeR = atan2(Double(ro.y - ri.y), Double(ro.x - ri.x))
            canthalDeg = ((slopeL + slopeR) / 2) * 180 / .pi
        }

        // --- Eye spacing: intercanthal distance / single-eye width.
        var eyeSpacing = 1.0
        if let li = leftEyeInner, let ri = rightEyeInner,
           let lo = leftEyeOuter {
            let intercanthal = abs(Double(ri.x - li.x))
            let eyeW = abs(Double(li.x - lo.x))
            if eyeW > 0.001 { eyeSpacing = intercanthal / eyeW }
        }

        // --- Jaw ratio: gonial (jaw) width / face height.
        var jawRatio = 0.78
        if let lj = leftJaw, let rj = rightJaw, let top = foreheadTop, let bottom = chin {
            let w = abs(Double(rj.x - lj.x))
            let h = abs(Double(bottom.y - top.y))
            if h > 0.001 { jawRatio = w / h }
        }
        _ = (mouthLeft, mouthRight)

        // --- Neutrality from 52 blendshapes (real expression coefficients).
        var neutrality = 1.0
        if let shapes = result.faceBlendshapes.first {
            var scores: [String: Double] = [:]
            for c in shapes.categories {
                if let name = c.categoryName { scores[name] = Double(c.score) }
            }
            // Weight the expression-distorting shapes that most skew a harmony read.
            let distorting: [(String, Double)] = [
                ("jawOpen", 1.0),
                ("mouthSmileLeft", 0.8), ("mouthSmileRight", 0.8),
                ("mouthFrownLeft", 0.7), ("mouthFrownRight", 0.7),
                ("mouthPucker", 0.6), ("mouthFunnel", 0.6),
                ("eyeSquintLeft", 0.7), ("eyeSquintRight", 0.7),
                ("eyeWideLeft", 0.5), ("eyeWideRight", 0.5),
                ("eyeBlinkLeft", 0.6), ("eyeBlinkRight", 0.6),
                ("browInnerUp", 0.6),
                ("browDownLeft", 0.5), ("browDownRight", 0.5),
                ("browOuterUpLeft", 0.5), ("browOuterUpRight", 0.5),
                ("cheekPuff", 0.5)
            ]
            var weighted = 0.0
            var wsum = 0.0
            for (name, w) in distorting {
                if let s = scores[name] { weighted += s * w; wsum += w }
            }
            if wsum > 0 {
                // Normalize and emphasize larger activations.
                let activation = min(1, (weighted / wsum) * 2.2)
                neutrality = max(0, 1 - activation)
            } else if let neutral = scores["_neutral"] {
                neutrality = max(0, min(1, neutral))
            }
        }

        let measurements = FaceMeasurements(
            symmetry: symmetry,
            thirds: thirds,
            canthalTiltDeg: canthalDeg,
            eyeSpacingRatio: eyeSpacing,
            jawRatio: jawRatio,
            meshPointCount: pts.count,
            expressionSignalCount: 52,
            expressionNeutrality: neutrality
        )

        return MediaPipeFaceResult(
            measurements: measurements,
            meshPointCount: pts.count,
            blendshapeCount: 52
        )
    }

    /// Read facial adiposity from the 478-point face mesh on a (front) physique
    /// photo. Combines facial width-to-height ratio, lower-face (jaw/cheek)
    /// roundness, and cheek fullness — all robust correlates of body fat — into
    /// a single 0..1 index plus an implied body-fat %. Returns nil when no face
    /// is visible (e.g. a back/side shot), so the caller can ignore it cleanly.
    func analyzeFacialAdiposity(_ image: UIImage) -> MediaPipeFaceAdiposity? {
        guard let landmarker = ensureFaceLandmarker(),
              let mpImage = try? MPImage(uiImage: image),
              let result = try? landmarker.detect(image: mpImage),
              let mesh = result.faceLandmarks.first, mesh.count >= 400 else {
            return nil
        }
        let pts: [CGPoint] = mesh.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) }
        func p(_ i: Int) -> CGPoint? { i >= 0 && i < pts.count ? pts[i] : nil }
        func dist(_ a: CGPoint, _ b: CGPoint) -> Double {
            let dx = Double(a.x - b.x), dy = Double(a.y - b.y)
            return (dx * dx + dy * dy).squareRoot()
        }

        // Canonical MediaPipe Face Mesh indices.
        guard let foreheadTop = p(10), let chin = p(152),
              let cheekL = p(234), let cheekR = p(454),   // bizygomatic (widest)
              let jawL = p(172), let jawR = p(397),        // gonial (jaw) width
              let midCheekL = p(50), let midCheekR = p(280) // mid-cheek fullness
        else { return nil }

        let faceHeight = dist(foreheadTop, chin)
        guard faceHeight > 0.001 else { return nil }
        let bizygomatic = dist(cheekL, cheekR)
        let jawWidth = dist(jawL, jawR)
        let cheekFullness = dist(midCheekL, midCheekR)

        // 1) Facial width-to-height ratio (fWHR). Higher = rounder/fuller face.
        //    Lean ≈ 0.82, average ≈ 0.95, high adiposity ≈ 1.10+.
        let fWHR = bizygomatic / faceHeight
        let whrScore = max(0, min(1, (fWHR - 0.80) / 0.34))
        // 2) Lower-face roundness: jaw width relative to cheekbone width. A sharp
        //    (lean) jaw tapers in; a fuller face keeps width down to the jaw.
        let jawRound = bizygomatic > 0.001 ? jawWidth / bizygomatic : 0.7
        let jawScore = max(0, min(1, (jawRound - 0.62) / 0.28))
        // 3) Cheek fullness relative to face height.
        let cheekScore = max(0, min(1, (cheekFullness / faceHeight - 0.55) / 0.30))

        let adiposity = max(0, min(1, 0.45 * whrScore + 0.35 * jawScore + 0.20 * cheekScore))
        // Map leanness → BF%: a razor-sharp face ≈ 7%, a very full face ≈ 36%.
        let impliedBF = 7 + adiposity * 29

        return MediaPipeFaceAdiposity(
            adiposityIndex: adiposity,
            impliedBodyFatPercent: impliedBF,
            meshPointCount: pts.count
        )
    }

    // MARK: - Pose (33 3-D world joints)

    private func ensurePoseLandmarker() -> PoseLandmarker? {
        if let poseLandmarker { return poseLandmarker }
        if poseInitFailed { return nil }
        guard let path = Bundle.main.path(forResource: "pose_landmarker_full", ofType: "task") else {
            poseInitFailed = true
            return nil
        }
        let options = PoseLandmarkerOptions()
        options.baseOptions.modelAssetPath = path
        options.runningMode = .image
        options.numPoses = 1
        do {
            let lm = try PoseLandmarker(options: options)
            poseLandmarker = lm
            return lm
        } catch {
            poseInitFailed = true
            return nil
        }
    }

    func analyzePose(_ image: UIImage) -> MediaPipePoseResult? {
        guard let landmarker = ensurePoseLandmarker(),
              let mpImage = try? MPImage(uiImage: image),
              let result = try? landmarker.detect(image: mpImage),
              let norm = result.landmarks.first,
              let world = result.worldLandmarks.first,
              norm.count >= 33 else {
            return nil
        }

        // MediaPipe BlazePose 33-joint topology → Vision-compatible names so
        // the existing physique math can consume them directly.
        func n(_ i: Int) -> CGPoint { CGPoint(x: CGFloat(norm[i].x), y: CGFloat(norm[i].y)) }
        // Full BlazePose 33-joint topology mapped to Vision-compatible names so
        // the existing physique math can consume every joint directly. Beyond
        // the core torso/limb joints we now also surface the face detail points,
        // both hands (pinky / index / thumb) and both feet (heel / foot index)
        // — the complete skeleton, not a 17-joint subset.
        var landmarks: [String: CGPoint] = [
            "nose_joint": n(0),
            "left_eye_inner_joint": n(1),
            "left_eye_joint": n(2),
            "left_eye_outer_joint": n(3),
            "right_eye_inner_joint": n(4),
            "right_eye_joint": n(5),
            "right_eye_outer_joint": n(6),
            "left_ear_joint": n(7),
            "right_ear_joint": n(8),
            "mouth_left_joint": n(9),
            "mouth_right_joint": n(10),
            "left_shoulder_joint": n(11),
            "right_shoulder_joint": n(12),
            "left_elbow_joint": n(13),
            "right_elbow_joint": n(14),
            "left_wrist_joint": n(15),
            "right_wrist_joint": n(16),
            "left_pinky_joint": n(17),
            "right_pinky_joint": n(18),
            "left_index_joint": n(19),
            "right_index_joint": n(20),
            "left_thumb_joint": n(21),
            "right_thumb_joint": n(22),
            "left_hip_joint": n(23),
            "right_hip_joint": n(24),
            "left_knee_joint": n(25),
            "right_knee_joint": n(26),
            "left_ankle_joint": n(27),
            "right_ankle_joint": n(28),
            "left_heel_joint": n(29),
            "right_heel_joint": n(30),
            "left_foot_index_joint": n(31),
            "right_foot_index_joint": n(32)
        ]
        // Pelvis center as a robust root anchor.
        landmarks["root_joint"] = CGPoint(
            x: (landmarks["left_hip_joint"]!.x + landmarks["right_hip_joint"]!.x) / 2,
            y: (landmarks["left_hip_joint"]!.y + landmarks["right_hip_joint"]!.y) / 2
        )
        // Neck = midpoint of the shoulder line (drives the wireframe + posture).
        landmarks["neck_1_joint"] = CGPoint(
            x: (landmarks["left_shoulder_joint"]!.x + landmarks["right_shoulder_joint"]!.x) / 2,
            y: (landmarks["left_shoulder_joint"]!.y + landmarks["right_shoulder_joint"]!.y) / 2
        )

        // Average visibility as a confidence proxy.
        let vis = norm.compactMap { $0.visibility?.doubleValue }
        let confidence = vis.isEmpty ? 0.6 : vis.reduce(0, +) / Double(vis.count)

        // --- 3-D world geometry (meters). Real depth lets us measure breadth
        // and girth far more reliably than a flat 2-D silhouette.
        func w(_ i: Int) -> (x: Double, y: Double, z: Double) {
            (Double(world[i].x), Double(world[i].y), Double(world[i].z))
        }
        func dist3(_ a: Int, _ b: Int) -> Double {
            let p = w(a), q = w(b)
            let dx = p.x - q.x, dy = p.y - q.y, dz = p.z - q.z
            return (dx * dx + dy * dy + dz * dz).squareRoot()
        }

        let shoulderBreadth = dist3(11, 12)
        let hipBreadth = dist3(23, 24)
        let upperArm = (dist3(11, 13) + dist3(12, 14)) / 2
        let forearm = (dist3(13, 15) + dist3(14, 16)) / 2
        let thigh = (dist3(23, 25) + dist3(24, 26)) / 2
        let shin = (dist3(25, 27) + dist3(26, 28)) / 2
        let torsoLen = (dist3(11, 23) + dist3(12, 24)) / 2
        // Hand span (wrist→index) and foot length (heel→foot-index) — extra
        // joints that anchor true limb scale in meters and stabilise the
        // arm/leg girth proxies against foreshortening.
        let handSpan = (dist3(15, 19) + dist3(16, 20)) / 2
        let footLen = (dist3(29, 31) + dist3(30, 32)) / 2

        // V-taper: shoulder breadth vs hip breadth.
        let taper = hipBreadth > 0.01 ? shoulderBreadth / hipBreadth : 1.3
        // Frame robustness: broad shoulders relative to torso length read as
        // more developed upper body. Limb segments anchor overall mass.
        let taperScore = max(0, min(1, (taper - 1.0) / 0.7))
        let frameScore = torsoLen > 0.01 ? max(0, min(1, (shoulderBreadth / torsoLen - 0.7) / 0.6)) : 0.4
        // Full-limb mass: upper arm + forearm + thigh + shin relative to torso.
        let limbTotal = upperArm + forearm + thigh + shin
        let limbScore = max(0, min(1, (limbTotal / max(0.01, torsoLen) - 1.9) / 1.6))
        // Distal scale: hand + foot length vs torso — bigger extremities track
        // larger overall frame/bone structure.
        let distalScore = max(0, min(1, ((handSpan + footLen) / max(0.01, torsoLen) - 0.25) / 0.35))
        let muscularity = max(0.08, min(1,
            0.44 * taperScore + 0.26 * frameScore + 0.20 * limbScore + 0.10 * distalScore))

        // --- Symmetry from mirrored 3-D limb segment lengths.
        var diffs: [Double] = []
        func sym(_ la: Int, _ lb: Int, _ ra: Int, _ rb: Int) {
            let l = dist3(la, lb), r = dist3(ra, rb)
            if max(l, r) > 0.0001 { diffs.append(abs(l - r) / max(l, r)) }
        }
        sym(11, 13, 12, 14) // upper arm
        sym(13, 15, 14, 16) // forearm
        sym(15, 19, 16, 20) // hand
        sym(23, 25, 24, 26) // thigh
        sym(25, 27, 26, 28) // shin
        sym(27, 31, 28, 32) // foot
        let symmetry: Double = diffs.isEmpty
            ? 0.9
            : max(0, min(1, 1 - (diffs.reduce(0, +) / Double(diffs.count)) * 2.5))

        return MediaPipePoseResult(
            landmarks: landmarks,
            muscularityIndex: muscularity,
            symmetry: symmetry,
            confidence: confidence,
            jointCount: norm.count
        )
    }
}
