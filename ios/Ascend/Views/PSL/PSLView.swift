import SwiftUI
import SwiftData
import PhotosUI

struct PSLView: View {
    let user: UserProfile
    @Environment(\.modelContext) private var ctx
    @Environment(AppState.self) private var app
    @Query(sort: \FaceScanRecord.date, order: .reverse) private var faces: [FaceScanRecord]

    @State private var showScan = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header

                if let latest = faces.first {
                    latestCard(latest).blurFadeIn(delay: 0.06)
                } else {
                    emptyCard.blurFadeIn(delay: 0.06)
                }

                if let latest = faces.first {
                    glowUpCard(latest).blurFadeIn(delay: 0.14)
                    recommendationsCard(latest).blurFadeIn(delay: 0.20)
                    hairstylesCard(latest).blurFadeIn(delay: 0.26)
                }

            }
            .padding(.horizontal, 20).padding(.top, 12)
        }
        .scrollIndicators(.hidden)
        .tabBarBottomInset()
        .sheet(isPresented: $showScan) {
            FaceScanSheet(user: user)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Aesthetic Intelligence".uppercased())
                .font(.system(size: 11, weight: .semibold)).tracking(2)
                .foregroundStyle(Theme.textTertiary)
            Text("Facial Harmony")
                .font(.aetherTitle).foregroundStyle(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyCard: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(Theme.accent.opacity(0.10)).frame(width: 110, height: 110)
                    .ambientFloat(amplitude: 4, duration: 3.5)
                Image(systemName: "face.dashed")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(Theme.accentGlow)
            }
            VStack(spacing: 4) {
                Text("Analyze facial harmony").font(.aetherHeadline)
                Text("Symmetry, proportions, glow-up potential — kindly delivered.")
                    .font(.aetherBody).foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            PrimaryButton(title: "Start Analysis", icon: "sparkles") {
                showScan = true
            }
        }
        .padding(24).frame(maxWidth: .infinity)
        .glassCard(radius: 22)
    }

    private func latestCard(_ rec: FaceScanRecord) -> some View {
        VStack(spacing: 18) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PSL Score".uppercased())
                        .font(.system(size: 10, weight: .semibold)).tracking(2)
                        .foregroundStyle(Theme.accentGlow)
                    Text(rec.insight)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(rec.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.aetherCaption).foregroundStyle(Theme.textTertiary)
                }
                Spacer()
                RadialScore(score: rec.overallScore, label: "Harmony", size: 120)
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                facialMetric("Symmetry", rec.symmetry, "arrow.left.and.right")
                facialMetric("Jawline", rec.jawline, "rectangle")
                facialMetric("Thirds", rec.thirds, "rectangle.split.3x1")
                facialMetric("Canthal Tilt", rec.canthalTilt, "eye")
            }

            PrimaryButton(title: "New Analysis", icon: "arrow.clockwise") {
                showScan = true
            }
        }
        .padding(20)
        .glassCard(radius: 24)
    }

    private func facialMetric(_ label: String, _ value: Double, _ icon: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Image(systemName: icon).font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.accentGlow)
                    Text(label.uppercased())
                        .font(.system(size: 9, weight: .semibold)).tracking(1.3)
                        .foregroundStyle(Theme.textTertiary)
                }
                CountingNumber(value: value, font: .system(size: 20, weight: .semibold, design: .rounded))
            }
            Spacer()
            ThinRing(progress: value/100, color: Theme.accentGlow, lineWidth: 4)
                .frame(width: 34, height: 34)
        }
        .padding(12)
        .glassCard(radius: 14)
    }

    private func glowUpCard(_ rec: FaceScanRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Glow-Up Potential".uppercased())
                    .font(.system(size: 10, weight: .semibold)).tracking(2)
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                Text("+\(Int(rec.glowUpPotential))%")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.good)
            }
            Text("Potential improvement available through grooming, sleep, body fat reduction, posture, and skincare.")
                .font(.aetherBody).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.line)
                    Capsule().fill(LinearGradient(colors: [Theme.good, Theme.accentGlow],
                                                   startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(8, geo.size.width * (rec.glowUpPotential / 100)))
                        .shadow(color: Theme.good.opacity(0.5), radius: 4)
                }
            }.frame(height: 6)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 18)
    }

    private func recommendationsCard(_ rec: FaceScanRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Coaching".uppercased())
                .font(.system(size: 10, weight: .semibold)).tracking(2)
                .foregroundStyle(Theme.textTertiary)
            ForEach(Array(rec.recommendations.enumerated()), id: \.offset) { idx, r in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(idx+1)").font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.bg)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Theme.accentGlow))
                    Text(r).font(.aetherBody).foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 18)
    }

    private func hairstylesCard(_ rec: FaceScanRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hairstyle Suggestions".uppercased())
                .font(.system(size: 10, weight: .semibold)).tracking(2)
                .foregroundStyle(Theme.textTertiary)
            HStack(spacing: 10) {
                ForEach(rec.hairstyles, id: \.self) { h in
                    HStack(spacing: 8) {
                        Image(systemName: "scissors").foregroundStyle(Theme.accentGlow)
                        Text(h).font(.system(size: 13, weight: .semibold))
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .glassCard(radius: 12)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 18)
    }
}

// MARK: - Face Scan Sheet

struct FaceScanSheet: View {
    let user: UserProfile
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx
    @Environment(AppState.self) private var app

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var images: [UIImage] = []
    @State private var analyzing = false
    @State private var phase: Double = 0
    @State private var result: FaceScanRecord?
    @State private var error: String?
    @State private var revealStep: Int = 0
    @State private var showCamera = false
    @State private var showCameraUnavailable = false
    @State private var showCameraDenied = false
    @State private var showLibraryPicker = false
    @Query(sort: \FaceScanRecord.date, order: .reverse) private var priorFaces: [FaceScanRecord]

    private let minPhotos = 3
    private let maxPhotos = 5

    var body: some View {
        ZStack {
            AmbientBackground().ignoresSafeArea()

            if let result {
                ScrollView {
                    VStack(spacing: 18) {
                        topBar
                        if revealStep >= 1 {
                            facePortrait.transition(.opacity)
                        }
                        if revealStep >= 2 {
                            RadialScore(score: result.overallScore, label: "Harmony", size: 220)
                                .padding(.vertical, 8)
                                .transition(.scale.combined(with: .opacity))
                        }
                        if revealStep >= 3 {
                            VStack(spacing: 8) {
                                metricsGrid(result)
                                Label("478-point facial mesh + 52 expression signals, on-device", systemImage: "face.dashed.fill")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(Theme.textTertiary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                        if revealStep >= 4 {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Insight".uppercased())
                                    .font(.system(size: 10, weight: .semibold)).tracking(2)
                                    .foregroundStyle(Theme.textTertiary)
                                Text(result.insight).font(.system(size: 16, weight: .semibold))
                            }
                            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                            .glassCard(radius: 18)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                        Color.clear.frame(height: 60)
                    }
                    .padding(.horizontal, 20).padding(.top, 8)
                }
                .scrollIndicators(.hidden)
                .onAppear { runReveal() }
            } else if analyzing {
                analyzingView
            } else {
                pickerView
            }
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                var loaded: [UIImage] = []
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) {
                        loaded.append(img)
                    }
                }
                await MainActor.run {
                    let combined = (images + loaded).suffix(maxPhotos)
                    images = Array(combined)
                    pickerItems = []
                }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraSheet(
                onCapture: { img in
                    if images.count < maxPhotos { images.append(img) }
                    showCamera = false
                },
                onCancel: { showCamera = false },
                preferFront: true
            )
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showCameraUnavailable) {
            CameraUnavailableSheet(reason: .unavailable, onUseLibrary: { showLibraryPicker = true })
        }
        .sheet(isPresented: $showCameraDenied) {
            CameraUnavailableSheet(reason: .denied, onUseLibrary: { showLibraryPicker = true })
        }
        .photosPicker(isPresented: $showLibraryPicker, selection: $pickerItems, maxSelectionCount: maxPhotos, matching: .images)
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 36, height: 36)
                    .glassCard(radius: 12)
            }
            Spacer()
        }
    }

    private var pickerView: some View {
        ScrollView {
            VStack(spacing: 18) {
                topBar
                VStack(spacing: 6) {
                    Text("Facial Analysis".uppercased())
                        .font(.system(size: 11, weight: .semibold)).tracking(2.5)
                        .foregroundStyle(Theme.accentGlow)
                    Text("Multi-photo harmony")
                        .font(.aetherTitle).foregroundStyle(Theme.textPrimary)
                    Text("Add \(minPhotos)–\(maxPhotos) photos of your face. Any casual selfie works — we average across them so the score stays stable.")
                        .font(.aetherBody).foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                photoStrip
                    .padding(.horizontal, 20)

                progressIndicator

                HStack(spacing: 10) {
                    Button {
                        Haptics.tap()
                        CameraAccessTrigger(
                            onAuthorized: { showCamera = true },
                            onDenied: { showCameraDenied = true },
                            onUnavailable: { showCameraUnavailable = true }
                        ).fire()
                    } label: {
                        HStack {
                            Image(systemName: "camera.fill")
                            Text("Take Photo")
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity).frame(height: 54)
                        .glassCard(radius: 14)
                    }
                    .buttonStyle(.plain)
                    .disabled(images.count >= maxPhotos)
                    .opacity(images.count >= maxPhotos ? 0.5 : 1)

                    PhotosPicker(selection: $pickerItems, maxSelectionCount: maxPhotos - images.count, matching: .images) {
                        HStack {
                            Image(systemName: "photo.on.rectangle.angled")
                            Text(images.isEmpty ? "Upload" : "Add More")
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity).frame(height: 54)
                        .glassCard(radius: 14)
                    }
                    .disabled(images.count >= maxPhotos)
                    .opacity(images.count >= maxPhotos ? 0.5 : 1)
                }
                .padding(.horizontal, 20)

                if images.count >= minPhotos {
                    PrimaryButton(title: "Analyze \(images.count) photos", icon: "sparkles") {
                        Task { await analyze(images) }
                    }
                    .padding(.horizontal, 20)
                } else if !images.isEmpty {
                    Text("Add \(minPhotos - images.count) more photo\(minPhotos - images.count == 1 ? "" : "s") to enable analysis.")
                        .font(.aetherCaption).foregroundStyle(Theme.textTertiary)
                }

                if let error {
                    Text(error).font(.aetherBody).foregroundStyle(Theme.bad)
                        .padding(.horizontal, 20)
                }

                Color.clear.frame(height: 40)
            }
            .padding(.top, 8)
        }
        .scrollIndicators(.hidden)
    }

    private var photoStrip: some View {
        let slots: [UIImage?] = (0..<maxPhotos).map { idx in idx < images.count ? images[idx] : nil }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(slots.enumerated()), id: \.offset) { idx, img in
                    photoSlot(image: img, index: idx)
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(height: 160)
    }

    private func photoSlot(image img: UIImage?, index: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.55)
                .frame(width: 110, height: 150)
                .overlay {
                    if let img {
                        Image(uiImage: img).resizable().aspectRatio(contentMode: .fill)
                            .allowsHitTesting(false)
                    } else {
                        VStack(spacing: 6) {
                            Image(systemName: index == 0 ? "face.smiling" : "plus")
                                .font(.system(size: 28, weight: .light))
                                .foregroundStyle(Theme.accent.opacity(0.55))
                            Text("\(index + 1)")
                                .font(.system(size: 10, weight: .semibold)).tracking(1)
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                }
                .clipShape(.rect(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(img == nil ? Theme.line : Theme.accentGlow.opacity(0.5), lineWidth: 0.8))

            if img != nil {
                Button {
                    Haptics.tap()
                    if index < images.count { images.remove(at: index) }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Color.black.opacity(0.7)))
                }
                .buttonStyle(.plain)
                .padding(6)
            }
        }
    }

    private var progressIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<maxPhotos, id: \.self) { i in
                Capsule()
                    .fill(i < images.count ? Theme.accentGlow : Theme.line)
                    .frame(width: i < images.count ? 20 : 12, height: 3)
                    .animation(.spring(response: 0.3, dampingFraction: 0.85), value: images.count)
            }
        }
        .padding(.top, 2)
    }

    private var analyzingView: some View {
        VStack(spacing: 24) {
            Spacer()
            IrisOrbitScan(image: images.first)
                .frame(width: 320, height: 320)
            VStack(spacing: 6) {
                Text(analyzingLabel.uppercased())
                    .font(.system(size: 11, weight: .semibold)).tracking(2.5)
                    .foregroundStyle(Theme.accentGlow)
                    .contentTransition(.opacity)
                Text("Averaging \(images.count) photos")
                    .font(.aetherTitle).foregroundStyle(Theme.textPrimary)
                Text("Cross-checking symmetry across all uploads…")
                    .font(.aetherCaption).foregroundStyle(Theme.textTertiary)
            }
            Spacer()
        }
        .onAppear {
            withAnimation(.linear(duration: 5).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
    }

    private var analyzingLabel: String {
        let phases = ["Mapping 478-point mesh", "Reading 52 expression signals", "Averaging symmetry", "Analyzing thirds", "Reading jawline", "Synthesizing harmony"]
        let idx = Int(phase / (.pi * 2 / Double(phases.count))) % phases.count
        return phases[idx]
    }

    private var facePortrait: some View {
        Color.clear.frame(height: 200)
            .overlay {
                if let data = result?.imageData, let img = UIImage(data: data) {
                    Image(uiImage: img).resizable().aspectRatio(contentMode: .fill).allowsHitTesting(false)
                }
            }
            .clipShape(.rect(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Theme.line, lineWidth: 0.5))
    }

    private func metricsGrid(_ r: FaceScanRecord) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            metric("Symmetry", r.symmetry, "arrow.left.and.right")
            metric("Jawline", r.jawline, "rectangle.portrait")
            metric("Thirds", r.thirds, "rectangle.split.3x1")
            metric("Canthal Tilt", r.canthalTilt, "eye")
            metric("Eye Spacing", r.eyeSpacing, "eyes")
            metric("Glow-Up", r.glowUpPotential, "sparkles")
        }
    }

    private func metric(_ label: String, _ value: Double, _ icon: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Image(systemName: icon).font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.accentGlow)
                    Text(label.uppercased())
                        .font(.system(size: 9, weight: .semibold)).tracking(1.3)
                        .foregroundStyle(Theme.textTertiary)
                }
                CountingNumber(value: value, font: .system(size: 22, weight: .semibold, design: .rounded))
            }
            Spacer()
            ThinRing(progress: value/100, color: Theme.accentGlow, lineWidth: 5)
                .frame(width: 40, height: 40)
        }
        .padding(12)
        .glassCard(radius: 14)
    }

    private func runReveal() {
        let delays: [Double] = [0.05, 0.22, 0.42, 0.62]
        for (i, d) in delays.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + d) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) { revealStep = i + 1 }
                if i == 1 { Haptics.medium() }
                if i == 3 { Haptics.success() }
            }
        }
    }

    // MARK: - Deterministic text fallbacks (used before AI enrichment)

    private func deterministicFaceInsight(score: DeterministicFaceScoring.Score) -> String {
        guard score.isUsable else { return "Add a clearer front-facing selfie to score." }
        let best = [
            ("symmetry", score.symmetry),
            ("jawline", score.jawline),
            ("thirds", score.thirds),
            ("canthal tilt", score.canthalTilt),
            ("eye spacing", score.eyeSpacing)
        ].max(by: { $0.1 < $1.1 })?.0 ?? "symmetry"
        if score.pslScore >= 80 { return "Strong harmony — \(best) is your standout." }
        if score.pslScore >= 65 { return "Solid baseline — \(best) is leading the rest." }
        return "Balanced features — grooming and posture upgrades will move you up fastest."
    }

    private func deterministicFaceRecs(measurements: FaceMeasurements?, score: DeterministicFaceScoring.Score) -> [String] {
        guard score.isUsable, let m = measurements else {
            return [
                "Use a clear, front-facing selfie with even lighting.",
                "Frame your full face — eyes, nose, and mouth all visible.",
                "Avoid heavy shadows; soft natural light works best."
            ]
        }
        var tips: [String] = []
        if m.jawRatio < 0.70 || m.jawRatio > 0.80 { tips.append("Reducing body-fat 2–3% sharpens jawline definition fastest.") }
        if score.symmetry < 75 { tips.append("Daily posture work + symmetric chewing habits help facial symmetry over time.") }
        if score.canthalTilt < 65 { tips.append("Brow grooming + good sleep posture lift the perceived canthal tilt.") }
        if tips.count < 3 { tips.append("Consistent skincare and 7+ hours sleep compound visibly within 4 weeks.") }
        return Array(tips.prefix(3))
    }

    private func deterministicHairstyles(measurements: FaceMeasurements?) -> [String] {
        guard let m = measurements else { return ["Textured Crop", "Side Part"] }
        if m.jawRatio > 0.78 { return ["Textured Crop", "Buzz Fade"] }     // wider jaw → short on sides
        if m.jawRatio < 0.72 { return ["Side Part", "Mid Length Sweep"] }   // narrower → add width
        return ["Textured Crop", "Modern Quiff"]
    }

    private func analyze(_ imgs: [UIImage]) async {
        analyzing = true
        do {
            // 1) On-device face detection (Vision = MediaPipe-equivalent on iOS) on EVERY photo.
            //    Only photos where a face is actually detected are eligible for scoring.
            var samples: [FaceMeasurements] = []
            var faceImages: [UIImage] = []
            let faceEngine = EngineRegistry.PSL.current.rawValue
            for img in imgs {
                // Content-addressed cache: same selfie → same anchors.
                let key = ScanCache.normalize(img).hash + "|" + faceEngine
                if let hit = ScanCache.loadFace(hash: key) {
                    samples.append(hit.measurements)
                    faceImages.append(img)
                    continue
                }
                // Preprocess each selfie (normalize lighting, crop to subject) so
                // landmark extraction is angle/lighting-invariant.
                let pre = await ImagePreprocessor.shared.process(img, mode: .face)
                let cleaned = pre.receipt.isUsable ? pre.image : img
                if let m = await PoseService.shared.analyzeFace(cleaned) {
                    ScanCache.saveFace(hash: key, anchors: CachedFaceAnchors(m, engineVersion: faceEngine))
                    samples.append(m)
                    faceImages.append(cleaned)
                }
            }

            // GUARD: no face found in any photo → return all zeros, never call the AI.
            if samples.isEmpty {
                try? await Task.sleep(for: .seconds(0.6))
                let zero = FaceScanRecord(
                    overallScore: 0,
                    symmetry: 0,
                    jawline: 0,
                    thirds: 0,
                    canthalTilt: 0,
                    eyeSpacing: 0,
                    glowUpPotential: 0,
                    recommendations: [
                        "Use a clear, front-facing selfie where your full face is visible.",
                        "Make sure your eyes, nose, and mouth are all in frame.",
                        "Soft, even lighting on the face works best."
                    ],
                    hairstyles: [],
                    insight: "No face detected in your photos — add a clear front-facing selfie to score.",
                    imageData: nil
                )
                ctx.insert(zero)
                try? ctx.save()
                await MainActor.run {
                    withAnimation(.smooth(duration: 0.5)) {
                        self.result = zero
                        self.analyzing = false
                    }
                }
                return
            }

            // 2) Trimmed-mean average so a bad-angle photo can't swing scores.
            let averaged = FaceMeasurements.averaged(samples)
            let consistency = FaceMeasurements.consistency(samples)

            // === DETERMINISTIC CORE (highest authority) ============================
            // All numeric PSL outputs come from on-device Vision + fixed math.
            // AI cannot modify these values — reserved for text-only enrichment.
            let det = DeterministicFaceScoring.shared.score(
                measurements: averaged, sampleCount: samples.count, consistency: consistency
            )
            // ======================================================================

            // OFFLINE-FIRST: persist the deterministic result IMMEDIATELY, before
            // any network call. AI enrichment only updates text fields if it
            // succeeds; numeric scores are final.
            let calibration = CalibrationResolver.resolve(for: user.appleUserId ?? "local", in: ctx)
            let replayPayload = averaged.map {
                ScanReplay.capture(measurements: $0, sampleCount: samples.count,
                                   consistency: consistency, calibration: calibration)
            } ?? ""
            let record = FaceScanRecord(
                overallScore: det.pslScore,
                symmetry: det.symmetry,
                jawline: det.jawline,
                thirds: det.thirds,
                canthalTilt: det.canthalTilt,
                eyeSpacing: det.eyeSpacing,
                glowUpPotential: det.glowUpPotential,
                recommendations: deterministicFaceRecs(measurements: averaged, score: det),
                hairstyles: deterministicHairstyles(measurements: averaged),
                insight: deterministicFaceInsight(score: det),
                imageData: nil,
                engineVersion: EngineRegistry.PSL.current.rawValue,
                calibrationVersion: calibration.version,
                inputHash: averaged.map { EngineRegistry.hashFaceMeasurements($0, sampleCount: samples.count) } ?? "",
                inputPayload: replayPayload,
                confidence: round(det.confidence * 100)
            )
            ctx.insert(record)
            app.bumpStreakIfNeeded(user)
            app.awardXP(40, to: user)
            try? ctx.save()
            WidgetSync.push(user: user, context: ctx)

            // === AI ENRICHMENT (lowest authority — text only) ======================
            async let dwell: Void = Task.sleep(for: .seconds(1.0))
            let history = FaceSmoothing.history(from: priorFaces)
            if let raw = try? await AIService.shared.analyzeFace(
                images: faceImages,
                measurements: averaged,
                sampleCount: samples.count,
                consistency: consistency,
                history: history
            ) {
                // AI schema lock: text-only. Strip / reject any score smuggling.
                if case .clean(let t) = AISchemaLock.validateText(raw.insight) {
                    record.insight = t
                } else if case .sanitized(let t, _) = AISchemaLock.validateText(raw.insight) {
                    record.insight = t
                }
                let safeRecs = AISchemaLock.validateList(raw.recommendations)
                if !safeRecs.isEmpty { record.recommendations = safeRecs }
                let safeStyles = AISchemaLock.validateList(raw.hairstyles)
                if !safeStyles.isEmpty { record.hairstyles = safeStyles }
                try? ctx.save()
            }
            _ = try? await dwell
            await MainActor.run {
                withAnimation(.smooth(duration: 0.5)) {
                    self.result = record
                    self.analyzing = false
                }
            }
        } catch {
            await MainActor.run {
                self.analyzing = false
                self.error = (error as? LocalizedError)?.errorDescription ?? "Analysis failed."
            }
        }
    }
}
