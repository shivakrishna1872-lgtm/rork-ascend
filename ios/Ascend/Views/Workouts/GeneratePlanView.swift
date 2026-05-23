import SwiftUI
import SwiftData

/// Form to capture per-plan inputs (the persistent traits come from
/// `UserProfile`). Runs the deterministic generator and saves the resulting
/// plan to SwiftData.
struct GeneratePlanView: View {
    let user: UserProfile
    let onCreated: (WorkoutPlan) -> Void
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    @State private var prefs: WorkoutPreferences = WorkoutPreferences.load()
    @State private var injuryText: String = ""
    @State private var generating: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground(intensity: 0.55).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        profileSummary
                        section("Fitness Level") {
                            segmented(selection: $prefs.level)
                        }
                        section("Goal") {
                            segmented(selection: $prefs.goal)
                        }
                        section("Equipment") {
                            segmented(selection: $prefs.equipment)
                        }
                        section("Training Days") {
                            HStack(spacing: 8) {
                                ForEach(2...6, id: \.self) { n in
                                    Button {
                                        Haptics.tap()
                                        prefs.daysPerWeek = n
                                    } label: {
                                        Text("\(n)")
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(prefs.daysPerWeek == n ? Theme.bg : Theme.textPrimary)
                                            .frame(maxWidth: .infinity)
                                            .frame(height: 42)
                                            .background(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .fill(prefs.daysPerWeek == n ? Theme.accentGlow : Theme.surface.opacity(0.55))
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .strokeBorder(prefs.daysPerWeek == n ? Theme.accentGlow : Theme.lineStrong, lineWidth: 0.6)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        section("Injuries (optional)") {
                            VStack(alignment: .leading, spacing: 8) {
                                TextField("e.g. shoulder, knee", text: $injuryText)
                                    .font(.system(size: 15))
                                    .foregroundStyle(Theme.textPrimary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 11)
                                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface.opacity(0.55)))
                                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.lineStrong, lineWidth: 0.6))
                                Text("Comma-separated. We'll skip exercises that load those joints.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.textTertiary)
                            }
                        }
                        generateButton
                            .padding(.top, 6)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 6)
                    .padding(.bottom, 32)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Generate Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    // MARK: - Profile summary

    private var profileSummary: some View {
        HStack(spacing: 14) {
            stat("Age", "\(user.ageValue)")
            divider
            stat("Height", user.unitSystem.formatHeight(cm: user.heightCm))
            divider
            stat("Weight", user.unitSystem.formatWeight(kg: user.weightKg))
            divider
            stat("Sex", user.sex == .male ? "M" : "F")
        }
        .padding(14)
        .glassCard(radius: 16)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .heavy)).tracking(1.2)
                .foregroundStyle(Theme.textTertiary)
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle().fill(Theme.lineStrong).frame(width: 0.5, height: 22)
    }

    // MARK: - Section helper

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .heavy)).tracking(2)
                .foregroundStyle(Theme.textTertiary)
            content()
        }
    }

    private func segmented<T: Hashable & RawRepresentable & CaseIterable & Identifiable>(selection: Binding<T>) -> some View where T.RawValue == String, T.AllCases: RandomAccessCollection {
        let items = Array(T.allCases)
        return HStack(spacing: 6) {
            ForEach(items) { item in
                Button {
                    Haptics.tap()
                    selection.wrappedValue = item
                } label: {
                    Text(item.rawValue)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(selection.wrappedValue == item ? Theme.bg : Theme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(
                            RoundedRectangle(cornerRadius: 11)
                                .fill(selection.wrappedValue == item ? Theme.accentGlow : Theme.surface.opacity(0.55))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 11)
                                .strokeBorder(selection.wrappedValue == item ? Theme.accentGlow : Theme.lineStrong, lineWidth: 0.6)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Generate

    private var generateButton: some View {
        Button {
            Haptics.medium()
            generate()
        } label: {
            HStack(spacing: 8) {
                if generating {
                    ProgressView().tint(Theme.bg)
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 15, weight: .bold))
                }
                Text(generating ? "Generating…" : "Generate Plan")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(Theme.bg)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.accentGlow))
            .shadow(color: Theme.accentGlow.opacity(0.4), radius: 14, x: 0, y: 6)
        }
        .buttonStyle(.plain)
        .disabled(generating)
    }

    private func generate() {
        generating = true
        // Persist injuries into prefs.
        let injuries = injuryText
            .split(whereSeparator: { ",;\n".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        prefs.injuries = injuries
        prefs.save()

        let generated = WorkoutPlanGenerator.generate(profile: user, prefs: prefs)
        let prefsJSON = (try? JSONEncoder().encode(prefs)).flatMap { String(data: $0, encoding: .utf8) }

        let plan = WorkoutPlan(
            title: generated.title,
            goalRaw: generated.goal.rawValue,
            sourceRaw: WorkoutSource.generated.rawValue,
            inputHash: generated.inputHash,
            preferencesJSON: prefsJSON
        )
        ctx.insert(plan)
        for (dIdx, day) in generated.days.enumerated() {
            let d = WorkoutDay(orderIndex: dIdx, dayTitle: day.title, focus: day.focus)
            d.plan = plan
            ctx.insert(d)
            for (eIdx, pick) in day.exercises.enumerated() {
                let ex = WorkoutExercise(
                    orderIndex: eIdx,
                    name: pick.exercise.name,
                    sets: pick.sets,
                    reps: pick.reps,
                    restSeconds: pick.restSeconds,
                    notes: pick.notes,
                    muscleGroup: pick.exercise.muscle.rawValue,
                    equipment: prefs.equipment.rawValue,
                    difficulty: pick.exercise.difficulty.rawValue
                )
                ex.day = d
                ctx.insert(ex)
            }
        }
        try? ctx.save()
        generating = false
        onCreated(plan)
        dismiss()
    }
}
