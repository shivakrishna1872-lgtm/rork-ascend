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
                    await applyImage(img)
                }
                pickerItem = nil
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraSheet(
                onCapture: { img in
                    showCamera = false
                    Task { await applyImage(img) }
                },
                onCancel: { showCamera = false }
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
        captureBuffer = img
        let pose = await PoseService.shared.analyze(img)
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

    private func runAnalysis() async {
        guard let f = front, let s = side, let b = back else { return }
        let snap = ProfileSnapshot(age: user.ageValue, sex: user.sexRaw, heightCm: user.heightCm, weightKg: user.weightKg, goals: user.goalsRaw, unitSystem: user.unitSystemRaw)
        let history = PhysiqueSmoothing.history(from: priorScans)
        do {
            // 1) On-device body detection (Vision = MediaPipe-equivalent on iOS) on EVERY photo.
            //    Only photos where a body is actually detected count toward scoring.
            async let frontPose = PoseService.shared.analyze(f)
            async let sidePose = PoseService.shared.analyze(s)
            async let backPose = PoseService.shared.analyze(b)
            let poses: [PoseResult?] = await [frontPose, sidePose, backPose]

            // A pose counts as "body detected" only if Vision returned real landmarks.
            let bodyDetected = poses.contains { ($0?.landmarks.isEmpty == false) || (($0?.confidenceAverage ?? 0) > 0.05) }

            // GUARD: no body found in any photo → return all zeros, never call the AI.
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
                    frontImageData: f.jpegData(compressionQuality: 0.7),
                    sideImageData: s.jpegData(compressionQuality: 0.7),
                    backImageData: b.jpegData(compressionQuality: 0.7)
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
            let avgSym = detectedPoses.isEmpty ? 0.5 : detectedPoses.map(\.symmetry).reduce(0, +) / Double(detectedPoses.count)
            let avgSW = detectedPoses.isEmpty ? 1.4 : detectedPoses.map(\.shoulderWaistRatio).reduce(0, +) / Double(detectedPoses.count)
            let avgCov = detectedPoses.isEmpty ? 0 : detectedPoses.map(\.coverageY).reduce(0, +) / Double(detectedPoses.count)
            let avgConfPose = detectedPoses.isEmpty ? 0 : detectedPoses.map(\.confidenceAverage).reduce(0, +) / Double(detectedPoses.count)
            let anchors = PhysiqueAnchors(
                symmetry: avgSym,
                shoulderWaistRatio: avgSW,
                coverageY: avgCov,
                confidence: avgConfPose,
                detectedAngles: detectedPoses.count
            )
            let rawAnalysis = try await AIService.shared.analyzePhysique(
                front: f, side: s, back: b, profile: snap, history: history, anchors: anchors
            )

            // --- Multi-angle averaging (MediaPipe-style) ---
            // Symmetry: trimmed-mean across every angle that detected a body.
            // Front + back are weighted higher than side (side view distorts L/R).
            let symmetrySamples: [(value: Double, weight: Double)] = [
                poses[0].map { ($0.symmetry * 100, 1.0) },
                poses[1].map { ($0.symmetry * 100, 0.4) },
                poses[2].map { ($0.symmetry * 100, 0.9) }
            ].compactMap { $0 }
            let measuredSymmetry: Double = {
                guard !symmetrySamples.isEmpty else { return rawAnalysis.symmetry }
                let totalW = symmetrySamples.reduce(0) { $0 + $1.weight }
                return symmetrySamples.reduce(0) { $0 + $1.value * $1.weight } / totalW
            }()
            // V-taper: averaged shoulder/hip ratio from front + back; side is unreliable.
            let vTaperSamples: [Double] = [poses[0], poses[2]].compactMap { p in
                guard let p else { return nil }
                let r = max(0.9, min(1.9, p.shoulderWaistRatio))
                return min(100, max(0, (r - 1.0) * 125))
            }
            let measuredVTaper: Double = vTaperSamples.isEmpty
                ? rawAnalysis.vTaper
                : vTaperSamples.reduce(0, +) / Double(vTaperSamples.count)

            // Blend AI + averaged on-device measurements (45/55 toward on-device for stability).
            let symmetry = min(100, max(0, rawAnalysis.symmetry * 0.45 + measuredSymmetry * 0.55))
            let vTaper = min(100, max(0, rawAnalysis.vTaper * 0.45 + measuredVTaper * 0.55))

            // Confidence boost scales with the NUMBER of angles successfully detected.
            let detected = poses.compactMap { $0 }
            let avgPoseConfidence = detected.isEmpty
                ? 0
                : detected.map(\.confidenceAverage).reduce(0, +) / Double(detected.count)
            let coverageBoost = Double(detected.count) * 5.0 // +5/angle, up to +15
            let bodyFatConfidence = min(100, max(0, rawAnalysis.bodyFatConfidence + avgPoseConfidence * 10 + coverageBoost))
            // Minimum dwell time for cinematic pacing (snappy)
            try? await Task.sleep(for: .seconds(1.2))

            // Smooth final scores against the user's recent rolling average so similar
            // photos don't produce wildly different numbers between sessions.
            let analysis = PhysiqueSmoothing.smooth(
                raw: rawAnalysis,
                blendedSymmetry: symmetry,
                blendedVTaper: vTaper,
                priors: priorScans
            )

            let record = PhysiqueScanRecord(
                physiqueScore: analysis.physiqueScore,
                symmetryScore: analysis.symmetry,
                muscularityScore: analysis.muscularity,
                conditioningScore: analysis.conditioning,
                vTaperScore: analysis.vTaper,
                bodyFatPercent: analysis.bodyFatPercent,
                bodyFatConfidence: bodyFatConfidence,
                archetypeRaw: analysis.archetype,
                recommendations: analysis.recommendations,
                insight: analysis.insight,
                frontImageData: f.jpegData(compressionQuality: 0.7),
                sideImageData: s.jpegData(compressionQuality: 0.7),
                backImageData: b.jpegData(compressionQuality: 0.7)
            )
            ctx.insert(record)
            try? ctx.save()
            app.bumpStreakIfNeeded(user)
            app.awardXP(60, to: user)
            try? ctx.save()
            WidgetSync.push(user: user, context: ctx)

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
