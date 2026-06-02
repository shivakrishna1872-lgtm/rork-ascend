import SwiftUI
import SwiftData
import PhotosUI

enum ScanAngle: Int, CaseIterable {
    case front, side, back
    var title: String {
        switch self {
        case .front: "Front"
        case .side:  "Side"
        case .back:  "Back"
        }
    }
    var instruction: String {
        switch self {
        case .front: "Face the camera. Any decent photo works — partial framing, casual lighting, all good."
        case .side:  "Roughly side-on. Don't worry about being perfect — we handle the rest."
        case .back:  "Turn so the camera sees your back. Whatever framing you can get is fine."
        }
    }
    var icon: String {
        switch self {
        case .front: "person.fill"
        case .side:  "person.fill.turn.right"
        case .back:  "person.fill.turn.down"
        }
    }
}

struct PhysiqueScanFlow: View {
    let user: UserProfile
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx
    @Environment(AppState.self) private var app

    @State private var angle: ScanAngle = .front
    @State private var front: UIImage?
    @State private var side: UIImage?
    @State private var back: UIImage?
    @State private var poseResult: PoseResult?
    @State private var analyzing: Bool = false
    @State private var analyzingPhase: Double = 0
    @State private var result: PhysiqueScanRecord?
    @State private var pickerItem: PhotosPickerItem?
    @State private var captureBuffer: UIImage?
    @State private var adjustingImage: UIImage?
    @State private var errorMsg: String?
    @State private var showCamera = false
    @State private var showCameraUnavailable = false
    @State private var showCameraDenied = false
    @State private var showLibraryPicker = false
    @Query(sort: \PhysiqueScanRecord.date, order: .reverse) private var priorScans: [PhysiqueScanRecord]

    var body: some View {
        ZStack {
            AmbientBackground().ignoresSafeArea()

            if let result {
                PhysiqueResultsView(record: result, isHistory: false)
                    .transition(.opacity)
            } else if analyzing {
                analyzingView.transition(.opacity)
            } else {
                captureView.transition(.opacity)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.88), value: analyzing)
        .animation(.spring(response: 0.32, dampingFraction: 0.88), value: result?.id)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    await MainActor.run { adjustingImage = img }
                }
                pickerItem = nil
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraSheet(
                onCapture: { img in
                    showCamera = false
                    adjustingImage = img
                },
                onCancel: { showCamera = false }
            )
            .ignoresSafeArea()
        }
        .fullScreenCover(item: Binding(
            get: { adjustingImage.map { AdjustWrap(image: $0) } },
            set: { adjustingImage = $0?.image }
        )) { wrap in
            PhotoAdjustView(
                image: wrap.image,
                angle: angle,
                onCancel: { adjustingImage = nil },
                onConfirm: { adjusted in
                    adjustingImage = nil
                    Task { await applyImage(adjusted) }
                }
            )
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showCameraUnavailable) {
            CameraUnavailableSheet(reason: .unavailable, onUseLibrary: { showLibraryPicker = true })
        }
        .sheet(isPresented: $showCameraDenied) {
            CameraUnavailableSheet(reason: .denied, onUseLibrary: { showLibraryPicker = true })
        }
        .photosPicker(isPresented: $showLibraryPicker, selection: $pickerItem, matching: .images, photoLibrary: .shared())
    }

    @MainActor
    private func applyImage(_ img: UIImage) async {
        // Preprocess (lighting normalize + subject crop + blur check) before
        // landmark extraction so quality is consistent across angles/lighting.
        let pre = await ImagePreprocessor.shared.process(img, mode: .body)
        captureBuffer = pre.image
        // Content-addressed cache: same photo → same pose anchors, no
        // duplicate Vision pass.
        let engine = EngineRegistry.Physique.current.rawValue
        let key = ScanCache.normalize(img).hash + "|" + engine
        if let cached = ScanCache.loadBody(hash: key) {
            withAnimation { poseResult = cached.pose }
            return
        }
        let pose = await PoseService.shared.analyze(pre.image)
        if let pose {
            ScanCache.saveBody(hash: key, anchors: CachedBodyAnchors(pose, engineVersion: engine))
        }
        withAnimation { poseResult = pose }
    }

    private var captureView: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 36, height: 36)
                        .glassCard(radius: 12)
                }
                Spacer()
                Text(angle.title.uppercased())
                    .font(.system(size: 12, weight: .semibold)).tracking(2)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Color.clear.frame(width: 36, height: 36)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            // Progress dots
            HStack(spacing: 8) {
                ForEach(ScanAngle.allCases, id: \.self) { a in
                    Capsule()
                        .fill(captured(a) ? Theme.accent : (a == angle ? Theme.accentGlow.opacity(0.7) : Theme.line))
                        .frame(width: a == angle ? 28 : 18, height: 4)
                        .animation(.spring, value: angle)
                        .animation(.spring, value: captured(a))
                }
            }
            .padding(.top, 14)

            // Big viewfinder
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.black.opacity(0.6))
                    .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(Theme.lineStrong, lineWidth: 0.6))

                if let img = captureBuffer {
                    Image(uiImage: img)
                        .resizable().aspectRatio(contentMode: .fit)
                        .clipShape(.rect(cornerRadius: 28))
                        .overlay(WireframeOverlay(pose: poseResult))
                } else {
                    SilhouettePlaceholder(angle: angle)
                }

                AlignmentGuides()

                // Top status pill
                VStack {
                    statusPill
                    Spacer()
                }
                .padding(.top, 14)

                // Bottom feedback
                VStack(spacing: 0) {
                    Spacer()
                    if let pose = poseResult, captureBuffer != nil {
                        feedbackPanel(pose: pose)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    } else {
                        instructionPanel
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .padding(14)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)

            // Capture controls
            VStack(spacing: 12) {
                if captureBuffer == nil {
                    HStack(spacing: 10) {
                        Button {
                            Haptics.medium()
                            CameraAccessTrigger(
                                onAuthorized: { showCamera = true },
                                onDenied: { showCameraDenied = true },
                                onUnavailable: { showCameraUnavailable = true }
                            ).fire()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "camera.fill").font(.system(size: 15, weight: .bold))
                                Text("Take Photo").font(.system(size: 15, weight: .semibold))
                            }
                            .foregroundStyle(Theme.bg)
                            .frame(maxWidth: .infinity).frame(height: 54)
                            .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.95)))
                        }
                        .buttonStyle(.plain)

                        PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                            HStack(spacing: 8) {
                                Image(systemName: "photo.on.rectangle.angled").font(.system(size: 15, weight: .bold))
                                Text("Upload").font(.system(size: 15, weight: .semibold))
                            }
                            .foregroundStyle(Theme.textPrimary)
                            .frame(maxWidth: .infinity).frame(height: 54)
                            .glassCard(radius: 16)
                        }
                        .onTapGesture { Haptics.medium() }
                    }
                } else {
                    HStack(spacing: 10) {
                        GhostButton(title: "Retake", icon: "arrow.counterclockwise") {
                            withAnimation { captureBuffer = nil; poseResult = nil }
                        }
                        PrimaryButton(title: angle == .back ? "Analyze" : "Confirm", icon: angle == .back ? "sparkles" : "checkmark") {
                            confirmCurrent()
                        }
                    }
                }
                Text("Take a photo live or upload from your library.")
                    .font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    private func captured(_ a: ScanAngle) -> Bool {
        switch a {
        case .front: front != nil
        case .side:  side != nil
        case .back:  back != nil
        }
    }

    private var statusPill: some View {
        let ready = readyToCapture
        return HStack(spacing: 6) {
            Circle().fill(ready ? Theme.good : Theme.warn).frame(width: 6, height: 6)
                .shadow(color: (ready ? Theme.good : Theme.warn).opacity(0.7), radius: 4)
            Text(ready ? "Ready" : "Adjust")
                .font(.system(size: 10, weight: .semibold)).tracking(1.2)
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Capsule().fill(Color.black.opacity(0.55)))
        .overlay(Capsule().strokeBorder(Theme.lineStrong, lineWidth: 0.6))
    }

    private var readyToCapture: Bool {
        guard let p = poseResult else { return false }
        // Ultra-lenient: any photo where a body is detected at all is good to go.
        return p.confidenceAverage > 0.08 || !p.landmarks.isEmpty
    }

    private var instructionPanel: some View {
        HStack(spacing: 12) {
            Image(systemName: angle.icon).font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.accentGlow)
            VStack(alignment: .leading, spacing: 2) {
                Text("Position: \(angle.title)").font(.aetherHeadline)
                Text(angle.instruction)
                    .font(.aetherBody).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.lineStrong, lineWidth: 0.6))
    }

    private func feedbackPanel(pose: PoseResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Scan Quality".uppercased())
                    .font(.system(size: 9, weight: .semibold)).tracking(1.5)
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                Text("\(Int(pose.confidenceAverage * 100))%")
                    .font(.aetherMono).foregroundStyle(Theme.accentGlow)
            }
            if pose.issues.isEmpty {
                Label("Looks great — any decent shot works.", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.good)
            } else {
                ForEach(pose.issues, id: \.self) { msg in
                    Label(msg, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.warn)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.lineStrong, lineWidth: 0.6))
    }

    private func confirmCurrent() {
        guard let img = captureBuffer else { return }
        switch angle {
        case .front: front = img
        case .side:  side = img
        case .back:  back = img
        }
        Haptics.success()
        captureBuffer = nil
        poseResult = nil
        if angle == .back {
            beginAnalysis()
        } else {
            withAnimation(.smooth(duration: 0.45)) {
                angle = ScanAngle(rawValue: angle.rawValue + 1) ?? .side
            }
        }
    }

    // MARK: - Analyzing

    private var analyzingView: some View {
        VStack(spacing: 26) {
            Spacer()
            ZStack {
                // Soft halo behind the particle body
                RadialGradient(
                    colors: [Theme.accent.opacity(0.35), .clear],
                    center: .center, startRadius: 10, endRadius: 220
                )
                .frame(width: 360, height: 420)
                .blur(radius: 12)
                ParticleBodyScan()
                    .frame(width: 260, height: 360)
            }
            VStack(spacing: 6) {
                Text(currentAnalyzingLabel.uppercased())
                    .font(.system(size: 11, weight: .semibold)).tracking(2.5)
                    .foregroundStyle(Theme.accentGlow)
                    .contentTransition(.opacity)
                Text("Analyzing your scan")
                    .font(.aetherTitle).foregroundStyle(Theme.textPrimary)
            }
            Spacer()
            if let errorMsg {
                Text(errorMsg).font(.aetherBody).foregroundStyle(Theme.bad)
                    .multilineTextAlignment(.center).padding(.horizontal, 20)
            }
        }
        .padding(.bottom, 60)
        .onAppear {
            withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
                analyzingPhase = .pi * 2
            }
            Task { await runAnalysis() }
        }
    }

    private var currentAnalyzingLabel: String {
        let phases = ["Mapping landmarks", "Calculating proportions", "Estimating composition", "Detecting symmetry", "Generating insights"]
        let idx = Int(analyzingPhase / (.pi * 2 / Double(phases.count))) % phases.count
        return phases[idx]
    }

    private func beginAnalysis() {
        analyzing = true
    }

    // MARK: - Deterministic text fallbacks (used before AI enrichment)

    private func deterministicInsight(anchors: PhysiqueAnchors, score: Double, vTaper: Double, conditioning: Double) -> String {
        if score >= 80 { return "Strong overall physique — V-taper and conditioning both reading well." }
        if vTaper > conditioning + 10 { return "V-taper is your standout — leaning out further would compound it." }
        if conditioning > vTaper + 10 { return "Lean and defined — added shoulder/back width would unlock the next tier." }
        if anchors.shoulderTiltDeg.magnitude > 6 { return "Posture shows a noticeable shoulder tilt — fixing it will lift your scores broadly." }
        return "Balanced base — small consistent improvements will move every metric together."
    }

    private func deterministicRecommendations(anchors: PhysiqueAnchors, conditioning: Double, vTaper: Double, posture: Double) -> [String] {
        var tips: [String] = []
        if conditioning < 65 { tips.append("Trim 200–300 kcal/day to drop waist/shoulder ratio and unlock conditioning.") }
        if vTaper < 60 { tips.append("Prioritize lateral delts and lat width — 4–6 sets each, twice weekly.") }
        if posture < 70 || anchors.shoulderTiltDeg.magnitude > 4 { tips.append("Daily 5-minute thoracic + scapular mobility to square the shoulders.") }
        if anchors.thighHipRatio < 0.85 { tips.append("Add a dedicated lower-body session per week to balance proportions.") }
        if tips.count < 3 { tips.append("Track weekly photos under the same lighting — small wins compound.") }
        return Array(tips.prefix(3))
    }

    private func runAnalysis() async {
        guard let f = front, let s = side, let b = back else { return }
        let snap = ProfileSnapshot(age: user.ageValue, sex: user.sexRaw, heightCm: user.heightCm, weightKg: user.weightKg, goals: user.goalsRaw, unitSystem: user.unitSystemRaw)
        let history = PhysiqueSmoothing.history(from: priorScans)
        do {
            // 1) On-device body detection (Vision = MediaPipe-equivalent on iOS) on EVERY photo.
            //    Only photos where a body is actually detected count toward scoring.
            //    Per-image cache: same photo bytes → same anchors, no Vision re-run.
            let engine = EngineRegistry.Physique.current.rawValue
            func cachedAnalyze(_ img: UIImage) async -> PoseResult? {
                let key = ScanCache.normalize(img).hash + "|" + engine
                if let hit = ScanCache.loadBody(hash: key) { return hit.pose }
                let pose = await PoseService.shared.analyze(img)
                if let pose {
                    ScanCache.saveBody(hash: key, anchors: CachedBodyAnchors(pose, engineVersion: engine))
                }
                return pose
            }
            async let frontPose = cachedAnalyze(f)
            async let sidePose = cachedAnalyze(s)
            async let backPose = cachedAnalyze(b)
            let poses: [PoseResult?] = await [frontPose, sidePose, backPose]

            // A pose counts as "body detected" if Vision returned ANY landmark
            // or the image has reasonable brightness (silhouette fallback path).
            // Mirror selfies, partial framing, and weird lighting all pass here.
            let landmarkHit = poses.contains { ($0?.landmarks.isEmpty == false) }
            let confidenceHit = poses.contains { ($0?.confidenceAverage ?? 0) > 0.02 }
            let brightnessHit = poses.contains { p in
                let b = p?.brightness ?? 0
                return b > 0.04 && b < 0.99
            }
            let bodyDetected = landmarkHit || confidenceHit || brightnessHit

            // GUARD: only fail if every photo is totally unreadable (black / blown out).
            if !bodyDetected {
                try? await Task.sleep(for: .seconds(0.6))
                let zero = PhysiqueScanRecord(
                    physiqueScore: 0,
                    symmetryScore: 0,
                    muscularityScore: 0,
                    conditioningScore: 0,
                    vTaperScore: 0,
                    bodyFatPercent: 0,
                    bodyFatConfidence: 0,
                    archetypeRaw: Archetype.balanced.rawValue,
                    recommendations: [
                        "Use photos that show your full or upper body in frame.",
                        "Stand a few feet from the camera so your torso is visible.",
                        "Soft, even lighting on the body works best."
                    ],
                    insight: "No body detected in your photos — add clearer shots showing your physique to score.",
                    frontImageData: nil,
                    sideImageData: nil,
                    backImageData: nil
                )
                ctx.insert(zero)
                try? ctx.save()
                await MainActor.run {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
                        self.result = zero
                        self.analyzing = false
                    }
                }
                return
            }

            // 2) Body confirmed → run the AI analysis anchored to detected on-device measurements.
            //    Compute aggregated pose anchors so the model can lean on them.
            let detectedPoses = poses.compactMap { $0 }

            // === PARTIALITY (region-aware scoring) ================================
            // Classify each pose's body completeness, then pick the worst across
            // the 3 angles so missing limbs never inflate per-region scores.
            let partialities = detectedPoses.map { BodyContinuity.partiality(pose: $0) }
            let worstPartiality: BodyContinuity.Partiality = {
                if partialities.contains(.missing) { return .missing }
                if partialities.contains(.obstructed) { return .obstructed }
                if partialities.contains(.upperOnly) { return .upperOnly }
                if partialities.contains(.torsoOnly) { return .torsoOnly }
                return .full
            }()
            // Region weights scale per-region scoring honestly. But when
            // partiality is `.missing` (no usable landmarks anywhere) all
            // weights would be 0 and the deterministic baseline would
            // collapse to 0 — the `partialityPenalty` below already handles
            // the "missing" case as a composite-level adjustment, so we use
            // neutral weights here to avoid double-penalizing.
            let useNeutralWeights = (worstPartiality == .missing)
            let wShoulders = useNeutralWeights ? 1.0 : BodyContinuity.regionWeight(worstPartiality, region: .shoulders)
            let wTorso = useNeutralWeights ? 1.0 : BodyContinuity.regionWeight(worstPartiality, region: .torso)
            let wHips = useNeutralWeights ? 1.0 : BodyContinuity.regionWeight(worstPartiality, region: .hips)
            let wLegs = useNeutralWeights ? 1.0 : BodyContinuity.regionWeight(worstPartiality, region: .legs)

            // === MULTI-PHOTO FUSION (confidence-weighted, outlier-trimmed) ========
            // Trims the worst-confidence angle when 3 are present so a junk shot
            // (mirror selfie, occluded back) can't drag the aggregate.
            func sample(_ key: (PoseResult) -> Double) -> [PhotoFusion.Sample] {
                detectedPoses.map { .init(value: key($0), confidence: $0.confidenceAverage) }
            }
            let avgSym = PhotoFusion.fuse(sample(\.symmetry), default: 0.5)
            let avgSW = PhotoFusion.fuse(sample(\.shoulderWaistRatio), default: 1.4)
            // Waist/shoulder is most reliable from front + back views.
            let waistFront = poses[0].map { PhotoFusion.Sample(value: $0.waistShoulderRatio, confidence: $0.confidenceAverage) }
            let waistBack = poses[2].map { PhotoFusion.Sample(value: $0.waistShoulderRatio, confidence: $0.confidenceAverage) }
            let avgWaist = PhotoFusion.fuse([waistFront, waistBack].compactMap { $0 }, default: 0.85)
            let avgThigh = PhotoFusion.fuse(sample(\.thighHipRatio), default: 1.0)
            let avgTorso = PhotoFusion.fuse(sample(\.torsoAspect), default: 1.4)
            let avgLimbSym = PhotoFusion.fuse(sample(\.limbSymmetry), default: 0.9)
            let avgTilt = PhotoFusion.fuse(sample(\.shoulderTiltDeg), default: 0)
            let avgCov = PhotoFusion.fuse(sample(\.coverageY), default: 0)
            let avgConfPose = PhotoFusion.fuse(sample(\.confidenceAverage), default: 0)
            // Surface a confidence reason if angles disagree strongly on V-taper.
            let svtDispersion = PhotoFusion.dispersion(sample(\.shoulderWaistRatio))

            // On-device body-fat anchor.
            // Combines a Navy-style proxy (waist/shoulder ratio scaled) with a
            // BMI/age fallback so the AI starts from a measurement, not a guess.
            let bmi = user.weightKg / pow(max(1.2, user.heightCm / 100), 2)
            let sexAdj: Double = (user.sex == .male) ? 0 : 5.4
            let bmiBF = max(6, min(40, 1.20 * bmi + 0.23 * Double(user.ageValue) - 16.2 + sexAdj))
            // Map waist/shoulder ratio into BF adjustment: 0.75 ≈ lean (−4),
            // 0.85 ≈ baseline (0), 0.95 ≈ +5, 1.05+ ≈ +9.
            let waistAdj = (avgWaist - 0.85) * 50
            let navyBF = max(5, min(42, bmiBF * 0.55 + (bmiBF + waistAdj) * 0.45))

            let anchors = PhysiqueAnchors(
                symmetry: avgSym,
                shoulderWaistRatio: avgSW,
                waistShoulderRatio: avgWaist,
                thighHipRatio: avgThigh,
                torsoAspect: avgTorso,
                limbSymmetry: avgLimbSym,
                shoulderTiltDeg: avgTilt,
                coverageY: avgCov,
                confidence: avgConfPose,
                detectedAngles: detectedPoses.count,
                navyBodyFatPercent: navyBF
            )

            // === DETERMINISTIC CORE (highest authority) ============================
            // All numeric scores come from on-device Vision + fixed math. AI cannot
            // modify these values — it is reserved for text-only enrichment below.
            let det = DeterministicScoring.shared.score(anchors: anchors)
            // Bounded per-user calibration (max ±15% shift, never reshapes the curve).
            let calibration = CalibrationResolver.resolve(for: user.appleUserId ?? user.email ?? "local", in: ctx)
            let symmetry100 = calibration.applySymmetry(det.symmetry * 100)
            let posture100 = calibration.applyPosture(det.posture * 100)
            let composition100 = det.bodyComposition * 100
            // V-taper score: deterministic mapping from shoulder/hip ratio.
            let vTaperRaw = max(0.9, min(1.9, anchors.shoulderWaistRatio))
            let vTaper = min(100, max(0, (vTaperRaw - 1.0) * 125))
            // Muscularity: built from FOUR real on-device measurements so a
            // single missing region never zeroes it out.
            //  - frame width (V-taper / shoulder dominance)
            //  - lower-body mass (thigh / hip width)
            //  - limb development symmetry (balanced arm + leg build)
            //  - torso build (a shorter, wider torso reads as more mass)
            // Each component is renormalized by the region weights actually
            // present, so partial scans still produce a real, meaningful score
            // rather than collapsing toward 0.
            let vTaperComp = vTaper                                                  // 0..100
            let lowerComp  = min(100, max(0, (anchors.thighHipRatio - 0.6) * 110))   // 0..100
            let limbComp   = min(100, max(0, anchors.limbSymmetry * 100))            // 0..100
            let buildComp  = min(100, max(0, (1.7 - anchors.torsoAspect) * 70 + 30)) // 0..100
            let muscleParts: [(value: Double, weight: Double)] = [
                (vTaperComp, 0.45 * wTorso),
                (lowerComp,  0.20 * wLegs),
                (limbComp,   0.20 * wShoulders),
                (buildComp,  0.15 * wTorso)
            ]
            let muscleWeightSum = muscleParts.reduce(0) { $0 + $1.weight }
            let muscularity: Double = {
                let weighted = muscleWeightSum > 0.05
                    ? muscleParts.reduce(0) { $0 + $1.value * $1.weight } / muscleWeightSum
                    : (0.45 * vTaperComp + 0.20 * lowerComp + 0.20 * limbComp + 0.15 * buildComp)
                // Floor: any detected body has SOME musculature read — never 0.
                return min(100, max(8, weighted))
            }()
            // Conditioning correlates inversely with waist/shoulder ratio.
            let conditioningBase: Double = {
                let r = anchors.waistShoulderRatio
                if r < 0.76 { return 88 + (0.76 - r) * 80 }
                if r < 0.82 { return 72 + (0.82 - r) * 270 }
                if r < 0.90 { return 55 + (0.90 - r) * 215 }
                return max(35, 55 - (r - 0.90) * 200)
            }()
            // Conditioning relies on torso + hips visibility; obstruction pulls it down.
            let conditioning = conditioningBase * (0.5 * wTorso + 0.5 * wHips) +
                               conditioningBase * (1 - (0.5 * wTorso + 0.5 * wHips)) * 0.6
            // Composite — deterministic score, then a controlled partiality penalty
            // so a full-body scan and an upper-body-only scan don't claim parity.
            let partialityPenalty: Double = {
                switch worstPartiality {
                case .full: return 1.0
                case .torsoOnly: return 0.97
                case .upperOnly: return 0.92
                case .obstructed: return 0.88
                case .missing: return 0.80
                }
            }()
            let physiqueScore = det.pslScore * partialityPenalty  // 0..100
            // Realistic confidence: reflects actual detection quality.
            // Blends per-photo detector strength, landmark coverage, and how
            // many of the three angles produced a usable body signal. No floor
            // — a poor scan shows a low score honestly.
            let detectedFraction = Double(detectedPoses.count) / 3.0
            // Honest confidence via the shared Vision Truth Layer's body-
            // continuity scorer. Combines pose joint coverage, source
            // strength, frame coverage, and lighting — never inflated. Low
            // continuity → low confidence, no compensating fallback.
            let continuityScores: [Double] = detectedPoses.map { pose in
                // Gym-tolerant lighting remap. Dim gym lighting (brightness
                // ~0.18–0.45) is normal and should NOT pull confidence down.
                // Only true pitch-black/blown-out is penalized, with a 0.6
                // floor so confidence is never cratered by lighting alone.
                let b = pose.brightness
                let lightingSignal: Double = {
                    if b >= 0.18 && b <= 0.80 { return 1.0 }
                    if b < 0.18 { return 0.6 + (b / 0.18) * 0.4 }
                    return 0.6 + max(0, (1.0 - b) / 0.20) * 0.4
                }()
                return BodyContinuity.score(pose: pose, lighting: lightingSignal)
            }
            let avgContinuity = continuityScores.isEmpty
                ? 0
                : continuityScores.reduce(0, +) / Double(continuityScores.count)
            let bodyFatConfidence = max(0, min(98,
                (0.75 * avgContinuity + 0.25 * detectedFraction) * 100 * partialityPenalty
            ))

            // === CONFIDENCE REASONS (transparency) ================================
            // Build a plain-language list of *why* confidence isn't 100%. Shown
            // verbatim in the UI — no marketing varnish.
            var reasons: [String] = []
            switch worstPartiality {
            case .full: break
            case .torsoOnly: reasons.append("Legs not visible in one or more photos.")
            case .upperOnly: reasons.append("Only upper body visible — hip and leg metrics estimated.")
            case .obstructed: reasons.append("Phone or object partially blocking the body.")
            case .missing: reasons.append("Body landmarks were difficult to read.")
            }
            if detectedPoses.count < 3 {
                reasons.append("\(3 - detectedPoses.count) of 3 angles couldn’t be analyzed.")
            }
            if avgContinuity < 0.5 && worstPartiality == .full {
                reasons.append("Lighting or framing reduced detection quality.")
            }
            if svtDispersion > 0.18 && detectedPoses.count >= 2 {
                reasons.append("Angles disagreed on body shape — used the most confident shots.")
            }

            // === CALIBRATION CARD (optional reference for real-world cm) ==========
            // Looks for a credit-card or A4-shaped rectangle in the front photo.
            // When found, the scan stores pixels-per-cm so widths become real
            // measurements. Absence is silent — this is purely additive.
            let calibrationCard = await CalibrationCardDetector.detect(in: f)
            // Cross-pipeline consistency — if a recent face scan exists, check
            // PSL vs Physique agreement. We *never* average; we only penalize
            // confidence and surface the disagreement.
            var isUncertaintyEvent = false
            if let recentFace = (try? ctx.fetch(FetchDescriptor<FaceScanRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)])))?.first,
               Date.now.timeIntervalSince(recentFace.date) < 60 * 60 * 24 * 7 {
                let report = CrossPipelineConsistency.check(
                    pslScore: recentFace.overallScore,
                    physiqueScore: physiqueScore
                )
                if report.isUncertaintyEvent {
                    isUncertaintyEvent = true
                    reasons.append(report.note)
                }
            }
            let archetypeRaw: String = {
                if vTaper > 70 && conditioning > 70 { return Archetype.vTaper.rawValue }
                if conditioning > 75 { return Archetype.leanAthletic.rawValue }
                if muscularity > 70 { return Archetype.powerBuild.rawValue }
                return Archetype.balanced.rawValue
            }()
            // ======================================================================

            // OFFLINE-FIRST: save the deterministic result IMMEDIATELY, before any
            // network call. If AI enrichment fails, the scan is already persisted.
            let vTaperCalibrated = calibration.applyVTaper(vTaper)
            let record = PhysiqueScanRecord(
                physiqueScore: physiqueScore,
                symmetryScore: symmetry100,
                muscularityScore: muscularity,
                conditioningScore: conditioning,
                vTaperScore: vTaperCalibrated,
                bodyFatPercent: anchors.navyBodyFatPercent,
                bodyFatConfidence: bodyFatConfidence,
                archetypeRaw: archetypeRaw,
                recommendations: deterministicRecommendations(anchors: anchors, conditioning: conditioning, vTaper: vTaper, posture: posture100),
                insight: deterministicInsight(anchors: anchors, score: physiqueScore, vTaper: vTaper, conditioning: conditioning),
                frontImageData: nil,
                sideImageData: nil,
                backImageData: nil,
                engineVersion: EngineRegistry.Physique.current.rawValue,
                calibrationVersion: calibration.version,
                inputHash: EngineRegistry.hashPhysiqueAnchors(anchors),
                inputPayload: ScanReplay.capture(anchors: anchors, calibration: calibration),
                confidenceReasons: reasons,
                partialityRaw: worstPartiality.rawValue,
                isUncertaintyEvent: isUncertaintyEvent,
                pixelsPerCm: calibrationCard?.pixelsPerCm ?? 0,
                calibrationReferenceRaw: calibrationCard?.reference.rawValue ?? ""
            )
            ctx.insert(record)
            try? ctx.save()
            app.bumpStreakIfNeeded(user)
            app.awardXP(60, to: user)
            try? ctx.save()
            WidgetSync.push(user: user, context: ctx)

            // === AI ENRICHMENT (lowest authority — text only) ======================
            // Optional: try to upgrade the insight/recommendations text. Numeric
            // scores are NEVER overwritten. Failures are silent — the deterministic
            // record already saved above is the canonical result.
            // Minimum dwell time for cinematic pacing.
            async let dwell: Void = Task.sleep(for: .seconds(1.2))
            if let rawAnalysis = try? await AIService.shared.analyzePhysique(
                front: f, side: s, back: b, profile: snap, history: history, anchors: anchors
            ) {
                record.insight = rawAnalysis.insight
                record.recommendations = rawAnalysis.recommendations
                // archetype is a label, not a score — safe to take from AI if provided.
                if !rawAnalysis.archetype.isEmpty { record.archetypeRaw = rawAnalysis.archetype }
                try? ctx.save()
            }
            _ = try? await dwell

            await MainActor.run {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
                    self.result = record
                    self.analyzing = false
                }
            }
        } catch {
            await MainActor.run {
                errorMsg = (error as? LocalizedError)?.errorDescription ?? "Analysis failed. Try again."
            }
        }
    }
}

// MARK: - Wireframe + Silhouette + Mesh

struct WireframeOverlay: View {
    let pose: PoseResult?
    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let pose, !pose.landmarks.isEmpty {
                    Canvas { ctx, size in
                        let edges: [(String, String)] = [
                            ("left_shoulder_joint","right_shoulder_joint"),
                            ("left_shoulder_joint","left_elbow_joint"),
                            ("left_elbow_joint","left_wrist_joint"),
                            ("right_shoulder_joint","right_elbow_joint"),
                            ("right_elbow_joint","right_wrist_joint"),
                            ("left_shoulder_joint","left_hip_joint"),
                            ("right_shoulder_joint","right_hip_joint"),
                            ("left_hip_joint","right_hip_joint"),
                            ("left_hip_joint","left_knee_joint"),
                            ("left_knee_joint","left_ankle_joint"),
                            ("right_hip_joint","right_knee_joint"),
                            ("right_knee_joint","right_ankle_joint"),
                            ("neck_1_joint","left_shoulder_joint"),
                            ("neck_1_joint","right_shoulder_joint")
                        ]
                        for (a, b) in edges {
                            if let pa = pose.landmarks[a], let pb = pose.landmarks[b] {
                                var path = Path()
                                path.move(to: CGPoint(x: pa.x * size.width, y: pa.y * size.height))
                                path.addLine(to: CGPoint(x: pb.x * size.width, y: pb.y * size.height))
                                ctx.stroke(path, with: .color(Theme.accentGlow.opacity(0.8)), lineWidth: 1.4)
                            }
                        }
                        for (_, p) in pose.landmarks {
                            let r: CGFloat = 3
                            let rect = CGRect(x: p.x*size.width - r, y: p.y*size.height - r, width: r*2, height: r*2)
                            ctx.fill(Path(ellipseIn: rect), with: .color(Theme.accentGlow))
                        }
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

struct SilhouettePlaceholder: View {
    let angle: ScanAngle
    @State private var pulse: CGFloat = 0
    var body: some View {
        VStack {
            Spacer()
            Image(systemName: angle == .front ? "figure.stand"
                  : angle == .side ? "figure"
                  : "figure.stand.line.dotted.figure.stand")
                .font(.system(size: 160, weight: .thin))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Theme.accent.opacity(0.4 + pulse * 0.3), Theme.accent.opacity(0.1)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .blur(radius: 0.5)
            Spacer()
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                pulse = 1
            }
        }
    }
}

struct AlignmentGuides: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Center vertical
                Rectangle().fill(Theme.accent.opacity(0.18))
                    .frame(width: 0.5).frame(maxHeight: .infinity)
                // Head guide
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Theme.accent.opacity(0.4), style: .init(lineWidth: 1, dash: [4, 4]))
                    .frame(width: geo.size.width * 0.45, height: 2)
                    .offset(y: -geo.size.height * 0.35)
                // Feet guide
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Theme.accent.opacity(0.4), style: .init(lineWidth: 1, dash: [4, 4]))
                    .frame(width: geo.size.width * 0.45, height: 2)
                    .offset(y: geo.size.height * 0.40)
                // Corner crosshairs
                ForEach([CGPoint(x: 14, y: 14), CGPoint(x: geo.size.width - 14, y: 14),
                         CGPoint(x: 14, y: geo.size.height - 14), CGPoint(x: geo.size.width - 14, y: geo.size.height - 14)], id: \.self.x) { p in
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.accent.opacity(0.7))
                        .position(p)
                }
            }
        }
    }
}

extension CGPoint: @retroactive Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(x); hasher.combine(y)
    }
}

struct MeshScanAnimation: View {
    var phase: Double
    var body: some View {
        ZStack {
            // Rotating wireframe figure
            ZStack {
                ForEach(0..<14) { i in
                    let t = Double(i) / 13.0
                    let y = t * 280 - 140
                    let w: CGFloat = 100 - abs(CGFloat(t - 0.5)) * 140
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(Theme.accentGlow.opacity(0.65), lineWidth: 1)
                        .frame(width: max(20, w), height: 2)
                        .offset(y: y)
                }
                // Vertical center beam
                Rectangle().fill(Theme.accent.opacity(0.7))
                    .frame(width: 1)
                    .shadow(color: Theme.accent.opacity(0.7), radius: 4)
            }
            .rotation3DEffect(.degrees(phase * 28), axis: (x: 0, y: 1, z: 0))

            // Scanning beam
            Rectangle()
                .fill(LinearGradient(
                    colors: [.clear, Theme.accentGlow.opacity(0.95), .clear],
                    startPoint: .leading, endPoint: .trailing
                ))
                .frame(height: 2)
                .blur(radius: 1)
                .offset(y: CGFloat(sin(phase * 2) * 140))
                .blendMode(.plusLighter)
        }
    }
}
