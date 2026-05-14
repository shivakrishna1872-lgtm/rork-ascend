import SwiftUI
import SwiftData

struct ProfileView: View {
    let user: UserProfile
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx
    @Query(sort: \PhysiqueScanRecord.date, order: .reverse) private var scans: [PhysiqueScanRecord]
    @Query(sort: \MealEntry.date, order: .reverse) private var meals: [MealEntry]
    @Query(sort: \FaceScanRecord.date, order: .reverse) private var faces: [FaceScanRecord]

    var body: some View {
        ZStack {
            AmbientBackground().ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    profileHeader.blurFadeIn(delay: 0.0)
                    statsCard.blurFadeIn(delay: 0.10)
                    personalitySection.blurFadeIn(delay: 0.18)
                    accessibilitySection.blurFadeIn(delay: 0.24)
                    aboutSection.blurFadeIn(delay: 0.30)
                    resetButton.blurFadeIn(delay: 0.36)
                }
                .padding(.horizontal, 20).padding(.top, 18)
            }
            .scrollIndicators(.hidden)
            .safeAreaPadding(.bottom, 40)
        }
    }

    private var profileHeader: some View {
        VStack(spacing: 14) {
            TierEmblem(tier: user.tier, size: 72)
                .ambientFloat(amplitude: 3, duration: 3.2)
            VStack(spacing: 4) {
                Text(user.name).font(.aetherTitle).foregroundStyle(Theme.textPrimary)
                Text("\(user.tier.title) · \(user.xp) XP")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(user.tier.color)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private var statsCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 0) {
                stat("Streak", "\(user.streak)", "flame.fill", Theme.warn)
                divider
                stat("Scans", "\(scans.count)", "viewfinder", Theme.accent)
                divider
                stat("Meals", "\(meals.count)", "fork.knife", Theme.good)
                divider
                stat("Faces", "\(faces.count)", "face.smiling", Theme.elite)
            }
        }
        .padding(16)
        .glassCard(radius: 20)
    }

    private var divider: some View {
        Rectangle().fill(Theme.line).frame(width: 0.5, height: 36)
    }

    private func stat(_ label: String, _ value: String, _ icon: String, _ tint: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 13, weight: .bold)).foregroundStyle(tint)
            Text(value).font(.system(size: 19, weight: .semibold, design: .rounded))
            Text(label.uppercased()).font(.system(size: 9, weight: .semibold)).tracking(1.2)
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private var personalitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "AI Personality")
            HStack(spacing: 8) {
                ForEach(AIPersonality.allCases) { p in
                    let on = user.personality == p
                    Button {
                        Haptics.tap()
                        withAnimation(.spring) {
                            user.personalityRaw = p.rawValue
                            try? ctx.save()
                        }
                    } label: {
                        Text(p.rawValue)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(on ? Theme.bg : Theme.textPrimary)
                            .frame(maxWidth: .infinity).frame(height: 44)
                            .background(RoundedRectangle(cornerRadius: 12).fill(on ? .white.opacity(0.9) : Theme.surface.opacity(0.5)))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.lineStrong, lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var accessibilitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Accessibility")
            VStack(spacing: 0) {
                Toggle(isOn: Binding(get: { user.reduceMotion }, set: { v in
                    user.reduceMotion = v; try? ctx.save()
                })) {
                    Label("Reduce Motion", systemImage: "wand.and.stars.inverse")
                        .font(.system(size: 15, weight: .medium))
                }
                .tint(Theme.accent)
                .padding(.vertical, 8)
            }
            .padding(.horizontal, 16).padding(.vertical, 6)
            .glassCard(radius: 16)

            Text("Dynamic Type, VoiceOver, and high-contrast colors are honored throughout the app.")
                .font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 4)
        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "About")
            VStack(alignment: .leading, spacing: 10) {
                row("Age", "\(user.ageValue)")
                Divider().overlay(Theme.line)
                row("Height", "\(Int(user.heightCm)) cm")
                Divider().overlay(Theme.line)
                row("Weight", String(format: "%.1f kg", user.weightKg))
                Divider().overlay(Theme.line)
                row("Calorie Target", "\(user.dailyCalorieTarget) kcal")
                Divider().overlay(Theme.line)
                row("Goals", user.goals.map { $0.rawValue }.joined(separator: ", "))
            }
            .padding(16)
            .glassCard(radius: 18)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textPrimary)
        }
    }

    private var resetButton: some View {
        Button {
            Haptics.warning()
            user.onboarded = false
            try? ctx.save()
            dismiss()
        } label: {
            Text("Restart Onboarding")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.bad)
                .frame(maxWidth: .infinity).frame(height: 44)
                .glassCard(radius: 12)
        }
        .buttonStyle(.plain)
    }
}
