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

    @State private var pickerItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var analyzing = false
    @State private var phase: Double = 0
    @State private var result: FaceScanRecord?
    @State private var error: String?
    @State private var revealStep: Int = 0
    @State private var showCamera = false
    @State private var showCameraUnavailable = false
    @Query(sort: \FaceScanRecord.date, order: .reverse) private var priorFaces: [FaceScanRecord]

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
                            metricsGrid(result).transition(.opacity.combined(with: .move(edge: .bottom)))
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
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    await MainActor.run { image = img }
                }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraSheet(
                onCapture: { img in image = img; showCamera = false },
                onCancel: { showCamera = false },
                preferFront: true
            )
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showCameraUnavailable) {
            CameraUnavailableSheet()
        }
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
        VStack(spacing: 20) {
            topBar
            VStack(spacing: 6) {
                Text("Facial Analysis".uppercased())
                    .font(.system(size: 11, weight: .semibold)).tracking(2.5)
                    .foregroundStyle(Theme.accentGlow)
                Text("Front-facing photo")
                    .font(.aetherTitle).foregroundStyle(Theme.textPrimary)
                Text("Neutral lighting, head straight, no glasses.")
                    .font(.aetherBody).foregroundStyle(Theme.textSecondary)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 28).fill(Color.black.opacity(0.6))
                    .frame(height: 340)
                    .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(Theme.lineStrong, lineWidth: 0.6))
                if let image {
                    Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
                        .frame(height: 340)
                        .clipShape(.rect(cornerRadius: 28))
                } else {
                    Image(systemName: "face.smiling")
                        .font(.system(size: 120, weight: .ultraLight))
                        .foregroundStyle(Theme.accent.opacity(0.4))
                }
                // Symmetry guides
                if image == nil {
                    VStack {
                        Spacer()
                        Rectangle().fill(Theme.accent.opacity(0.25)).frame(width: 0.5).frame(height: 280)
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 20)

            HStack(spacing: 10) {
                Button {
                    Haptics.tap()
                    if CameraSheet.isAvailable { showCamera = true }
                    else { showCameraUnavailable = true }
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

                PhotosPicker(selection: $pickerItem, matching: .images) {
                    HStack {
                        Image(systemName: "photo.on.rectangle.angled")
                        Text(image == nil ? "Upload" : "Change")
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity).frame(height: 54)
                    .glassCard(radius: 14)
                }
            }
            .padding(.horizontal, 20)

            if let image {
                PrimaryButton(title: "Analyze", icon: "sparkles") {
                    Task { await analyze(image) }
                }
                .padding(.horizontal, 20)
            }

            if let error {
                Text(error).font(.aetherBody).foregroundStyle(Theme.bad)
                    .padding(.horizontal, 20)
            }

            Spacer()
        }
        .padding(.top, 8)
    }

    private var analyzingView: some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack {
                ForEach(0..<3) { i in
                    Circle()
                        .strokeBorder(Theme.accent.opacity(0.45 - Double(i) * 0.12), lineWidth: 1)
                        .frame(width: 220 + CGFloat(i) * 56, height: 220 + CGFloat(i) * 56)
                        .scaleEffect(1 + CGFloat(sin(phase + Double(i))) * 0.04)
                }
                FaceMeshSweep(image: image)
                    .frame(width: 200, height: 240)
                    .clipShape(.rect(cornerRadius: 24))
                    .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Theme.lineStrong, lineWidth: 0.6))
                    .shadow(color: Theme.accent.opacity(0.4), radius: 18)
            }
            VStack(spacing: 6) {
                Text(analyzingLabel.uppercased())
                    .font(.system(size: 11, weight: .semibold)).tracking(2.5)
                    .foregroundStyle(Theme.accentGlow)
                    .contentTransition(.opacity)
                Text("Analyzing facial harmony")
                    .font(.aetherTitle).foregroundStyle(Theme.textPrimary)
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
        let phases = ["Mapping landmarks", "Measuring symmetry", "Analyzing thirds", "Reading jawline", "Synthesizing harmony"]
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

    private func analyze(_ img: UIImage) async {
        analyzing = true
        do {
            async let measure = PoseService.shared.analyzeFace(img)
            let m = await measure
            let history = FaceSmoothing.history(from: priorFaces)
            let rawAnalysis = try await AIService.shared.analyzeFace(image: img, measurements: m, history: history)
            let r = FaceSmoothing.smooth(raw: rawAnalysis, priors: priorFaces)
            try? await Task.sleep(for: .seconds(1.0))
            let record = FaceScanRecord(
                overallScore: r.overall,
                symmetry: r.symmetry,
                jawline: r.jawline,
                thirds: r.thirds,
                canthalTilt: r.canthalTilt,
                eyeSpacing: r.eyeSpacing,
                glowUpPotential: r.glowUpPotential,
                recommendations: r.recommendations,
                hairstyles: r.hairstyles,
                insight: r.insight,
                imageData: img.jpegData(compressionQuality: 0.7)
            )
            ctx.insert(record)
            app.bumpStreakIfNeeded(user)
            app.awardXP(40, to: user)
            try? ctx.save()
            WidgetSync.push(user: user, context: ctx)
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
