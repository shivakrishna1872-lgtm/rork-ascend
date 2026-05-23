import SwiftUI
import SwiftData
import PhotosUI

/// Scan a workout from a photo — camera or photo library. Runs on-device
/// Vision OCR, then a deterministic parser. Result is saved as a normal
/// editable `WorkoutPlan`.
struct ScanPlanView: View {
    let onCreated: (WorkoutPlan) -> Void
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    @State private var pickerItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var processing: Bool = false
    @State private var error: String?
    @State private var preview: WorkoutOCRService.ParsedPlan?

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground(intensity: 0.55).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        instructionsCard
                        if let img = image {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 320)
                                .clipShape(.rect(cornerRadius: 16))
                                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.lineStrong, lineWidth: 0.6))
                        }
                        pickerButtons
                        if let preview {
                            previewCard(preview)
                        }
                        if let error {
                            Text(error)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.bad)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 6)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Scan Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
                }
                if preview != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Save") { save() }
                            .foregroundStyle(Theme.accentGlow)
                            .fontWeight(.semibold)
                    }
                }
            }
            .onChange(of: pickerItem) { _, newItem in
                Task { await load(newItem) }
            }
        }
    }

    private var instructionsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(Theme.accentGlow)
                Text("How it works")
                    .font(.system(size: 13, weight: .heavy)).tracking(1)
                    .foregroundStyle(Theme.textPrimary)
            }
            Text("Take or pick a clear photo of any workout: a printed sheet, a screenshot, or your handwritten plan. Text is parsed on-device — no cloud upload.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .glassCard(radius: 14)
    }

    private var pickerButtons: some View {
        VStack(spacing: 10) {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                HStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 15, weight: .bold))
                    Text(image == nil ? "Choose Photo" : "Choose Different Photo")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(Theme.bg)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(RoundedRectangle(cornerRadius: 13).fill(Theme.accentGlow))
            }
            .buttonStyle(.plain)

            if processing {
                HStack(spacing: 8) {
                    ProgressView().tint(Theme.accentGlow)
                    Text("Reading…")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity).frame(height: 36)
            }
        }
    }

    private func previewCard(_ p: WorkoutOCRService.ParsedPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PARSED")
                .font(.system(size: 11, weight: .heavy)).tracking(2)
                .foregroundStyle(Theme.textTertiary)
            Text(p.title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            VStack(spacing: 8) {
                ForEach(Array(p.days.enumerated()), id: \.offset) { _, day in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(day.title).font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Text("\(day.exercises.count) exercises")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        ForEach(Array(day.exercises.enumerated()), id: \.offset) { _, ex in
                            HStack {
                                Text(ex.name).font(.system(size: 13))
                                    .foregroundStyle(Theme.textSecondary)
                                Spacer()
                                Text("\(ex.sets) × \(ex.reps)")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Theme.textTertiary)
                            }
                        }
                        Divider().overlay(Theme.line)
                    }
                }
            }
            Text("You can edit everything after saving.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(14)
        .glassCard(radius: 16)
    }

    // MARK: - Logic

    private func load(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        await MainActor.run {
            processing = true
            error = nil
            preview = nil
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let img = UIImage(data: data) else {
                await MainActor.run {
                    processing = false
                    error = "Could not load that image."
                }
                return
            }
            await MainActor.run { image = img }
            let parsed = try await WorkoutOCRService.recognize(image: img)
            await MainActor.run {
                preview = parsed
                processing = false
                if parsed.days.allSatisfy({ $0.exercises.isEmpty }) {
                    error = "No exercises found. Try a clearer photo."
                }
            }
        } catch {
            await MainActor.run {
                processing = false
                self.error = "Couldn't read that image."
            }
        }
    }

    private func save() {
        guard let p = preview else { return }
        let plan = WorkoutPlan(
            title: p.title,
            goalRaw: WorkoutGoal.hypertrophy.rawValue,
            sourceRaw: WorkoutSource.scanned.rawValue
        )
        ctx.insert(plan)
        for (dIdx, day) in p.days.enumerated() {
            let d = WorkoutDay(orderIndex: dIdx, dayTitle: day.title, focus: day.focus)
            d.plan = plan
            ctx.insert(d)
            for (eIdx, ex) in day.exercises.enumerated() {
                let w = WorkoutExercise(
                    orderIndex: eIdx,
                    name: ex.name,
                    sets: ex.sets,
                    reps: ex.reps,
                    restSeconds: ex.restSeconds,
                    notes: ex.notes
                )
                w.day = d
                ctx.insert(w)
            }
        }
        try? ctx.save()
        Haptics.success()
        onCreated(plan)
        dismiss()
    }
}
