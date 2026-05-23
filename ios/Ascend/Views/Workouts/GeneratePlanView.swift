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
    @State private var didInitFromProfile: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground(intensity: 0.55).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        profileSummary
                        targetCard
                        section("Fitness Level") {
                            segmented(selection: $prefs.level)
                        }
                        section("Goal") {
                            segmented(selection: $prefs.goal)
                        }
                        section("Session Length") {
                            sessionLengthPicker
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
            .onAppear { initFromProfileIfNeeded() }
        }
    }

    private func initFromProfileIfNeeded() {
        guard !didInitFromProfile else { return }
        didInitFromProfile = true
        // Auto-suggest goal from ideal aesthetic / pace direction the first
        // time this form opens, so the user sees a plan that matches what they
        // already told us in onboarding.
        if let a = user.idealAesthetic {
            prefs.goal = a.suggestedGoal
        } else if user.weightPaceKgPerWeek < 0 {
            prefs.goal = .fatLoss
        } else if user.weightPaceKgPerWeek > 0 {
            prefs.goal = .hypertrophy
        }
    }

    // MARK: - Target summary

    private var targetCard: some View {
        let aesthetic = user.idealAesthetic
        let weeks = user.weeksToGoal
        let hasTarget = user.idealWeightKg > 0
        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.accentGlow.opacity(0.18))
                Image(systemName: aesthetic?.icon ?? "target")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.accentGlow)
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(aesthetic?.rawValue.uppercased() ?? "NO AESTHETIC SET")
                    .font(.system(size: 10, weight: .heavy)).tracking(1.6)
                    .foregroundStyle(Theme.accentGlow)
                if hasTarget {
                    Text("\(user.unitSystem.formatWeight(kg: user.weightKg)) → \(user.unitSystem.formatWeight(kg: user.idealWeightKg))")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    if let w = weeks {
                        Text("~\(w) week\(w == 1 ? "" : "s") at your pace")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        Text(aesthetic?.caption ?? "Maintenance training.")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                    }
                } else {
                    Text(aesthetic?.caption ?? "Tap to set goals in Profile.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.accentGlow.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.accentGlow.opacity(0.3), lineWidth: 0.7))
    }

    // MARK: - Session length

    private var sessionLengthPicker: some View {
        HStack(spacing: 6) {
            ForEach(SessionLength.allCases) { item in
                let on = prefs.sessionLength == item
                Button {
                    Haptics.tap()
                    prefs.sessionLength = item
                } label: {
                    VStack(spacing: 2) {
                        Text(item.rawValue)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(on ? Theme.bg : Theme.textPrimary)
                        Text(item.minutesLabel)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(on ? Theme.bg.opacity(0.7) : Theme.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(
                        RoundedRectangle(cornerRadius: 11)
                            .fill(on ? Theme.accentGlow : Theme.surface.opacity(0.55))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 11)
                            .strokeBorder(on ? Theme.accentGlow : Theme.lineStrong, lineWidth: 0.6)
                    )
                }
                .buttonStyle(.plain)
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
                    difficulty: pick.exercise.difficulty.rawValue,
                    warmupSets: pick.warmupSets,
                    tempo: pick.tempo
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
