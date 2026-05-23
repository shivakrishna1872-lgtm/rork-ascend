import SwiftUI
import SwiftData

/// Entry point for the workout feature. Lists saved plans and exposes the two
/// creation paths: generate from profile, or scan a photo of a written plan.
struct WorkoutsHubView: View {
    let user: UserProfile
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \WorkoutPlan.updatedAt, order: .reverse) private var plans: [WorkoutPlan]

    @State private var showGenerate: Bool = false
    @State private var showScan: Bool = false
    @State private var showTemplates: Bool = false
    @State private var selectedPlan: WorkoutPlan?

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground(intensity: 0.6).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        if let primary = plans.first {
                            thisWeekCard(primary)
                        }
                        RecoveryBadgeView()
                        creationCards
                        templatesButton
                        if plans.isEmpty {
                            emptyState
                        } else {
                            planList
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 6)
                    .padding(.bottom, 32)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Workouts")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.accentGlow)
                }
            }
            .sheet(isPresented: $showGenerate) {
                GeneratePlanView(user: user) { plan in
                    selectedPlan = plan
                }
            }
            .sheet(isPresented: $showScan) {
                ScanPlanView { plan in
                    selectedPlan = plan
                }
            }
            .sheet(isPresented: $showTemplates) {
                TemplatesPickerView { plan in
                    selectedPlan = plan
                }
            }
            .navigationDestination(item: $selectedPlan) { plan in
                WorkoutPlanDetailView(plan: plan, user: user)
            }
        }
    }

    // MARK: - Creation

    // MARK: - This week hero

    private func thisWeekCard(_ plan: WorkoutPlan) -> some View {
        let all = plan.days.flatMap { $0.exercises }
        let totalSets = all.reduce(0) { $0 + $1.sets + $1.warmupSets }
        let totalSecs = all.reduce(0) { $0 + $1.estimatedSeconds }
        let avgMin = plan.days.isEmpty ? 0 : Int((Double(totalSecs) / Double(plan.days.count) / 60).rounded())
        return Button {
            Haptics.tap()
            selectedPlan = plan
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("THIS WEEK")
                        .font(.system(size: 10, weight: .heavy)).tracking(2)
                        .foregroundStyle(Theme.accentGlow)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                }
                Text(plan.title)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 0) {
                    heroStat("\(plan.days.count)", "DAYS")
                    heroDivider
                    heroStat("\(all.count)", "EXERCISES")
                    heroDivider
                    heroStat("\(totalSets)", "SETS")
                    heroDivider
                    heroStat("~\(avgMin)m", "PER DAY")
                }
                weekDots(plan)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(LinearGradient(colors: [
                        Theme.accentGlow.opacity(0.18),
                        Theme.accentGlow.opacity(0.04)
                    ], startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(Theme.accentGlow.opacity(0.35), lineWidth: 0.7)
            )
        }
        .buttonStyle(.plain)
    }

    private func heroStat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(1.2)
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
    private var heroDivider: some View {
        Rectangle().fill(Theme.lineStrong.opacity(0.6)).frame(width: 0.5, height: 28)
    }

    private func weekDots(_ plan: WorkoutPlan) -> some View {
        let days = plan.sortedDays
        return HStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { i in
                let isTraining = i < days.count
                Capsule()
                    .fill(isTraining ? Theme.accentGlow : Theme.line)
                    .frame(height: 4)
            }
        }
    }

    private var creationCards: some View {
        HStack(spacing: 12) {
            creationCard(
                icon: "wand.and.stars",
                title: "Generate",
                subtitle: "From your profile",
                tint: Theme.accentGlow
            ) {
                Haptics.medium()
                showGenerate = true
            }
            creationCard(
                icon: "doc.text.viewfinder",
                title: "Scan",
                subtitle: "From a photo",
                tint: Theme.gold
            ) {
                Haptics.medium()
                showScan = true
            }
        }
    }

    private var templatesButton: some View {
        Button {
            Haptics.tap()
            showTemplates = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(Theme.gold.opacity(0.18))
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.gold)
                }
                .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Browse templates")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("PPL · Upper/Lower · 5×5 · Full Body")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface.opacity(0.55)))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.lineStrong, lineWidth: 0.6))
        }
        .buttonStyle(.plain)
    }

    private func creationCard(icon: String, title: String, subtitle: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(tint.opacity(0.18))
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(tint)
                }
                .frame(width: 36, height: 36)
                Spacer(minLength: 4)
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 130)
            .padding(14)
            .glassCard(radius: 18)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Plan list

    private var planList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("YOUR PLANS")
                    .font(.system(size: 11, weight: .heavy)).tracking(2)
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                Text("\(plans.count)")
                    .font(.system(size: 11, weight: .heavy)).tracking(1)
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 4)
            ForEach(plans) { plan in
                Button {
                    Haptics.tap()
                    selectedPlan = plan
                } label: {
                    planRow(plan)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button(role: .destructive) {
                        Haptics.warning()
                        ctx.delete(plan)
                        try? ctx.save()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
    }

    private func planRow(_ plan: WorkoutPlan) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill((plan.source == .scanned ? Theme.gold : Theme.accentGlow).opacity(0.18))
                Image(systemName: plan.source == .scanned ? "doc.text" : "dumbbell.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(plan.source == .scanned ? Theme.gold : Theme.accentGlow)
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(plan.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text("\(plan.days.count) days")
                    Text("·")
                    Text(plan.source.label.uppercased())
                        .tracking(0.8)
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface.opacity(0.55)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.lineStrong, lineWidth: 0.6))
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
            Text("No plans yet")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Generate a plan from your profile or scan one you already have.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 16)
        .padding(.horizontal, 24)
    }
}
