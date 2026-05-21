import SwiftUI
import SwiftData

/// Bench / Squat / Deadlift logging — single sheet that captures all three
/// (any subset, blanks are stored as 0) and respects the user's unit system.
struct LiftLogSheet: View {
    let user: UserProfile
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx
    @Environment(AppState.self) private var app

    @State private var bench: String = ""
    @State private var squat: String = ""
    @State private var dead: String = ""
    @State private var note: String = ""

    private var unit: String { user.unitSystem.weightUnit }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("Log Your Lifts".uppercased())
                    .font(.system(size: 11, weight: .semibold)).tracking(2.5)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.top, 18)

                Text("Enter your current 1RM or top working set. Blank fields are skipped.")
                    .font(.aetherBody).foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)

                liftField("Bench Press", icon: "figure.strengthtraining.functional", text: $bench)
                liftField("Squat", icon: "figure.cross.training", text: $squat)
                liftField("Deadlift", icon: "figure.strengthtraining.traditional", text: $dead)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Note (optional)")
                        .font(.system(size: 11, weight: .semibold)).tracking(1.5)
                        .foregroundStyle(Theme.textTertiary)
                    TextField("e.g. PR after a 12-week cycle", text: $note, axis: .vertical)
                        .lineLimit(1...3)
                        .font(.system(size: 15, weight: .medium))
                        .padding(14)
                        .glassCard(radius: 14)
                }

                PrimaryButton(title: "Save Lifts", icon: "checkmark") {
                    save()
                }
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.5)

                Color.clear.frame(height: 30)
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .background(Theme.bg)
    }

    private var canSave: Bool {
        parsed(bench) > 0 || parsed(squat) > 0 || parsed(dead) > 0
    }

    private func liftField(_ label: String, icon: String, text: Binding<String>) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Theme.accent.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.accentGlow)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .semibold)).tracking(1.4)
                    .foregroundStyle(Theme.textTertiary)
                HStack(spacing: 6) {
                    TextField("0", text: text)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                    Text(unit)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            Spacer()
        }
        .padding(14)
        .glassCard(radius: 14)
    }

    private func parsed(_ s: String) -> Double {
        Double(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    /// Convert the user's typed value into kilograms for storage.
    private func toKg(_ s: String) -> Double {
        let v = parsed(s)
        guard v > 0 else { return 0 }
        return user.unitSystem == .imperial ? v / 2.2046226218 : v
    }

    private func save() {
        let entry = LiftEntry(
            benchKg: toKg(bench),
            squatKg: toKg(squat),
            deadliftKg: toKg(dead),
            note: note.trimmingCharacters(in: .whitespaces)
        )
        ctx.insert(entry)
        app.awardXP(20, to: user)
        app.bumpStreakIfNeeded(user)
        try? ctx.save()
        Haptics.success()
        dismiss()
    }
}
