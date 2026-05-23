import SwiftUI
import PhotosUI

/// Vision Lab — a transparent dashboard of the on-device CV pipeline.
///
/// Drop in a photo and see every stage of the pipeline that the rest of the
/// app uses for PSL / Physique / Cal AI scoring: preprocessing receipt,
/// landmark count, confidence gate, and the AI fallback decision. Lets power
/// users (and us) sanity-check why a score moved or didn't.
struct VisionLabView: View {
    @State private var pickerItem: PhotosPickerItem?
    @State private var input: UIImage?
    @State private var output: UIImage?
    @State private var receipt: PreprocessReceipt?
    @State private var pose: PoseResult?
    @State private var face: FaceMeasurements?
    @State private var mode: ImagePreprocessor.Mode = .body
    @State private var running = false

    var body: some View {
        ZStack {
            AmbientBackground().ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    modePicker

                    photoBlock

                    if let receipt {
                        receiptCard(receipt)
                    }

                    if let pose {
                        poseCard(pose)
                    }

                    if let face {
                        faceCard(face)
                    }

                    correctionsCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("Vision Lab")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    await run(img)
                }
                pickerItem = nil
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CV PIPELINE")
                .font(.system(size: 10, weight: .semibold)).tracking(2)
                .foregroundStyle(Theme.accentGlow)
            Text("Vision Lab")
                .font(.aetherTitle).foregroundStyle(Theme.textPrimary)
            Text("Inspect every stage of the on-device computer-vision pipeline that powers PSL, Physique, and Cal AI.")
                .font(.aetherBody).foregroundStyle(Theme.textSecondary)
        }
    }

    private var modePicker: some View {
        Picker("", selection: $mode) {
            Text("Body").tag(ImagePreprocessor.Mode.body)
            Text("Face").tag(ImagePreprocessor.Mode.face)
            Text("Meal").tag(ImagePreprocessor.Mode.meal)
        }
        .pickerStyle(.segmented)
        .onChange(of: mode) { _, _ in
            if let input { Task { await run(input) } }
        }
    }

    private var photoBlock: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.black.opacity(0.45))
                    .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Theme.lineStrong, lineWidth: 0.6))
                if let output {
                    Image(uiImage: output)
                        .resizable().aspectRatio(contentMode: .fit)
                        .clipShape(.rect(cornerRadius: 20))
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 34, weight: .light))
                            .foregroundStyle(Theme.accent.opacity(0.55))
                        Text("Drop in a photo to inspect the pipeline")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.vertical, 60)
                }
                if running {
                    ProgressView().tint(Theme.accentGlow)
                }
            }
            .frame(minHeight: 260)

            PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                HStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle.angled")
                    Text("Pick photo").font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity).frame(height: 48)
                .glassCard(radius: 14)
            }
        }
    }

    private func receiptCard(_ r: PreprocessReceipt) -> some View {
        Card(title: "Preprocess", icon: "slider.horizontal.3") {
            statRow("Input quality", value: pct(r.inputQuality), good: r.inputQuality > 0.55)
            statRow("Blur variance", value: String(format: "%.0f", r.blurVariance), good: r.blurVariance > 60)
            statRow("Brightness", value: pct(r.brightness), good: r.brightness > 0.18 && r.brightness < 0.85)
            statRow("Subject coverage", value: pct(r.subjectCoverage), good: r.subjectCoverage > 0.18)
            if !r.issues.isEmpty {
                ForEach(r.issues, id: \.self) { i in
                    Label(i, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.warn)
                }
            }
        }
    }

    private func poseCard(_ p: PoseResult) -> some View {
        Card(title: "Body landmarks", icon: "figure.stand") {
            statRow("Landmarks found", value: "\(p.landmarks.count)", good: p.landmarks.count >= 8)
            statRow("Avg confidence", value: pct(p.confidenceAverage), good: p.confidenceAverage > 0.4)
            statRow("Shoulder/hip ratio", value: String(format: "%.2f", p.shoulderWaistRatio), good: p.shoulderWaistRatio > 1.2)
            statRow("Waist/shoulder ratio", value: String(format: "%.2f", p.waistShoulderRatio), good: p.waistShoulderRatio < 0.88)
            statRow("Limb symmetry", value: pct(p.limbSymmetry), good: p.limbSymmetry > 0.8)
            statRow("Posture tilt", value: String(format: "%.1f°", p.shoulderTiltDeg), good: abs(p.shoulderTiltDeg) < 5)
        }
    }

    private func faceCard(_ m: FaceMeasurements) -> some View {
        Card(title: "Face mesh", icon: "face.smiling") {
            statRow("Symmetry", value: pct(m.symmetry), good: m.symmetry > 0.7)
            statRow("Thirds", value: pct(m.thirds), good: m.thirds > 0.7)
            statRow("Canthal tilt", value: String(format: "%.1f°", m.canthalTiltDeg), good: m.canthalTiltDeg > 2)
            statRow("Eye spacing", value: String(format: "%.2f", m.eyeSpacingRatio), good: abs(m.eyeSpacingRatio - 1.0) < 0.15)
            statRow("Jaw ratio", value: String(format: "%.2f", m.jawRatio), good: m.jawRatio > 0.7 && m.jawRatio < 0.82)
        }
    }

    private var correctionsCard: some View {
        Card(title: "Continuous learning", icon: "brain") {
            let corrections = UserCorrectionStore.load()
            if corrections.isEmpty {
                Text("No corrections yet. When you tap a score and adjust it, the AI learns your personal bias and applies it on the next scan.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Text("\(corrections.count) correction\(corrections.count == 1 ? "" : "s") stored locally. The next AI request includes a calibration block derived from these.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func statRow(_ title: String, value: String, good: Bool) -> some View {
        HStack {
            Text(title).font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(good ? Theme.good : Theme.warn)
        }
    }

    private func pct(_ d: Double) -> String { "\(Int(d * 100))%" }

    private func run(_ img: UIImage) async {
        running = true
        input = img
        receipt = nil; pose = nil; face = nil
        let pre = await ImagePreprocessor.shared.process(img, mode: mode)
        output = pre.image
        receipt = pre.receipt
        switch mode {
        case .body: pose = await PoseService.shared.analyze(pre.image)
        case .face: face = await PoseService.shared.analyzeFace(pre.image)
        case .meal: break
        }
        running = false
    }
}

private struct Card<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.accentGlow)
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold)).tracking(2)
                    .foregroundStyle(Theme.textTertiary)
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.lineStrong, lineWidth: 0.6))
    }
}
