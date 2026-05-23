import SwiftUI
import SwiftData

/// Preset workout templates the user can fork into an editable plan.
struct TemplatesPickerView: View {
    let onPicked: (WorkoutPlan) -> Void
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground(intensity: 0.5).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        Text("Pick a proven template, fork it, then edit anything.")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                        ForEach(WorkoutTemplates.all) { tpl in
                            Button {
                                Haptics.medium()
                                fork(tpl)
                            } label: {
                                templateRow(tpl)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 6)
                    .padding(.bottom, 32)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Templates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    private func templateRow(_ tpl: WorkoutTemplates.Template) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Theme.accentGlow.opacity(0.18))
                Image(systemName: tpl.symbol)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.accentGlow)
            }
            .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 4) {
                Text(tpl.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(tpl.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                HStack(spacing: 6) {
                    chip("\(tpl.daysPerWeek) DAYS")
                    chip(tpl.goal.rawValue.uppercased())
                    chip(tpl.level.rawValue.uppercased())
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface.opacity(0.55)))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.lineStrong, lineWidth: 0.6))
    }

    private func chip(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 9, weight: .heavy)).tracking(1.2)
            .foregroundStyle(Theme.textTertiary)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Capsule().fill(Theme.surface.opacity(0.7)))
    }

    private func fork(_ tpl: WorkoutTemplates.Template) {
        let plan = WorkoutPlan(
            title: tpl.title,
            goalRaw: tpl.goal.rawValue,
            sourceRaw: WorkoutSource.generated.rawValue,
            inputHash: tpl.id
        )
        ctx.insert(plan)
        for (dIdx, day) in tpl.days.enumerated() {
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
                    notes: ex.notes,
                    muscleGroup: ex.muscleGroup,
                    equipment: "",
                    difficulty: tpl.level.rawValue
                )
                w.day = d
                ctx.insert(w)
            }
        }
        try? ctx.save()
        onPicked(plan)
        dismiss()
    }
}
