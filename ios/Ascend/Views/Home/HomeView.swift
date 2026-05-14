import SwiftUI
import SwiftData

struct HomeView: View {
    let user: UserProfile
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var ctx
    @Query(sort: \PhysiqueScanRecord.date, order: .reverse) private var scans: [PhysiqueScanRecord]
    @Query(sort: \FaceScanRecord.date, order: .reverse) private var faces: [FaceScanRecord]
    @Query(sort: \MealEntry.date, order: .reverse) private var meals: [MealEntry]

    @State private var showProfile = false
    @State private var insightHeadline: String = ""
    @State private var insightDetail: String = ""
    @State private var insightLoading: Bool = true
    @State private var scrollOffset: CGFloat = 0

    var body: some View {
        ScrollView {
            ScrollOffsetReader { v in scrollOffset = v }
            VStack(spacing: 18) {
                header

                heroCard
                    .parallax(scrollOffset, amount: 0.18, blurMax: 4)
                    .cinematicReveal(delay: 0.02)

                insightCard.cinematicReveal(delay: 0.08)

                SectionHeader(title: "Optimization Snapshot")
                    .padding(.horizontal, 4)

                snapshot.cinematicReveal(delay: 0.14)

                SectionHeader(title: "Quick Actions")
                    .padding(.horizontal, 4)

                quickActions.cinematicReveal(delay: 0.20)

            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
        .coordinateSpace(name: "aether.scroll")
        .scrollIndicators(.hidden)
        .tabBarBottomInset()
        .sheet(isPresented: $showProfile) {
            ProfileView(user: user)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .task { await loadInsight() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                Haptics.tap(); showProfile = true
            } label: {
                HStack(spacing: 10) {
                    TierEmblem(tier: user.tier, size: 36)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Welcome back")
                            .font(.system(size: 11, weight: .medium)).tracking(1.5)
                            .foregroundStyle(Theme.textTertiary)
                        Text(user.name)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                    }
                }
            }
            .buttonStyle(.plain)
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: "flame.fill").font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.warn)
                Text("\(user.streak)")
                    .font(.system(size: 14, weight: .semibold))
                    .contentTransition(.numericText())
                    .monospacedDigit()
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .glassCard(radius: 12)
        }
        .padding(.bottom, 4)
    }

    private var heroCard: some View {
        VStack(spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(user.tier.title.uppercased())
                        .font(.system(size: 11, weight: .semibold)).tracking(2.5)
                        .foregroundStyle(user.tier.color)
                    Text(user.tier.subtitle)
                        .font(.aetherTitle2)
                        .foregroundStyle(Theme.textPrimary)
                }
                Spacer()
                ZStack {
                    ThinRing(progress: user.tierProgress, color: user.tier.color, lineWidth: 5)
                        .frame(width: 56, height: 56)
                    Text("\(user.xp)")
                        .font(.system(size: 13, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                }
            }

            // Three primary metrics
            HStack(spacing: 12) {
                heroMetric(label: "Physique", value: latestPhysiqueScore, suffix: "")
                heroMetric(label: "PSL", value: latestPSLScore, suffix: "")
                heroMetric(label: "Cals Left", value: caloriesRemaining, suffix: "")
            }

            // XP progress bar
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("XP to \(user.tier.next?.title ?? "Peak")".uppercased())
                        .font(.system(size: 10, weight: .semibold)).tracking(1.5)
                        .foregroundStyle(Theme.textTertiary)
                    Spacer()
                    Text("\(user.xp) / \(user.tier.xpCeiling)")
                        .font(.aetherMono).foregroundStyle(Theme.textSecondary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.line)
                        Capsule()
                            .fill(LinearGradient(colors: [user.tier.color.opacity(0.7), Theme.accentGlow],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(8, geo.size.width * user.tierProgress))
                            .shadow(color: user.tier.color.opacity(0.5), radius: 6)
                    }
                }.frame(height: 6)
            }
        }
        .padding(20)
        .glassCard(radius: 26)
        .softShadow()
    }

    private func heroMetric(label: String, value: Double, suffix: String) -> some View {
        VStack(spacing: 4) {
            CountingNumber(value: value,
                           font: .system(size: 28, weight: .semibold, design: .rounded),
                           color: Theme.textPrimary)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold)).tracking(1.5)
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(0.25)))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.line, lineWidth: 0.6))
    }

    private var insightCard: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle().fill(Theme.accent.opacity(0.18))
                Image(systemName: "sparkles").font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.accentGlow)
            }.frame(width: 40, height: 40)
                .ambientFloat(amplitude: 2.5, duration: 3.0)
            VStack(alignment: .leading, spacing: 4) {
                Text("Daily Insight".uppercased())
                    .font(.system(size: 10, weight: .semibold)).tracking(2)
                    .foregroundStyle(Theme.textTertiary)
                if insightLoading {
                    Text("Reading the signals…")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Your daily insight will appear here once Ascend has data to learn from.")
                        .font(.aetherBody).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(insightHeadline)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(insightDetail)
                        .font(.aetherBody).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .glassCard(radius: 20)
    }

    private var snapshot: some View {
        let mealsToday = mealsTodayList
        let kcalEaten = mealsToday.reduce(0) { $0 + $1.calories }
        let proteinG = mealsToday.reduce(0) { $0 + $1.proteinG }
        let proteinPct = min(1.0, Double(proteinG) / Double(max(1, user.proteinTargetG)))
        let physiqueProgress = latestPhysiqueScore / 100
        let postureProgress = latestSymmetry / 100
        let hydrationGlasses = currentHydration
        let hydrationProgress = min(1.0, Double(hydrationGlasses) / 8.0)

        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            snapshotCard(icon: "fork.knife",
                         title: "Nutrition",
                         primary: mealsToday.isEmpty ? "—" : "\(kcalEaten) kcal",
                         hint: mealsToday.isEmpty ? "Log a meal" : nil,
                         progress: Double(kcalEaten) / Double(max(1, user.dailyCalorieTarget)),
                         tint: Theme.accent)
            snapshotCard(icon: "figure.stand",
                         title: "Physique",
                         primary: scans.isEmpty ? "—" : "\(Int(latestPhysiqueScore))",
                         hint: scans.isEmpty ? "First scan" : nil,
                         progress: physiqueProgress,
                         tint: Theme.good)
            snapshotCard(icon: "face.smiling",
                         title: "PSL",
                         primary: faces.isEmpty ? "—" : "\(Int(latestPSLScore))",
                         hint: faces.isEmpty ? "Analyze face" : nil,
                         progress: latestPSLScore / 100,
                         tint: Theme.elite)
            snapshotCard(icon: "figure.walk",
                         title: "Posture",
                         primary: scans.isEmpty ? "—" : "\(Int(postureProgress*100))%",
                         hint: scans.isEmpty ? "Awaiting scan" : nil,
                         progress: postureProgress,
                         tint: Theme.accentGlow)
            snapshotCard(icon: "drop.fill",
                         title: "Protein",
                         primary: mealsToday.isEmpty ? "—" : "\(Int(proteinPct*100))%",
                         hint: mealsToday.isEmpty ? "Add a meal" : nil,
                         progress: proteinPct,
                         tint: Theme.elite)
            snapshotCard(icon: "drop.halffull",
                         title: "Hydration",
                         primary: hydrationGlasses > 0 ? "\(hydrationGlasses)/8" : "—",
                         hint: hydrationGlasses == 0 ? "Tap to log" : nil,
                         progress: hydrationProgress,
                         tint: Theme.accent)
        }
    }

    private func snapshotCard(icon: String, title: String, primary: String, hint: String? = nil,
                              progress: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon).font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .semibold)).tracking(1.5)
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
            }
            Text(primary)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(primary == "—" ? Theme.textTertiary : Theme.textPrimary)
            if let hint {
                Text(hint.uppercased())
                    .font(.system(size: 9, weight: .bold)).tracking(1.4)
                    .foregroundStyle(tint.opacity(0.85))
            } else {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.line)
                        Capsule().fill(tint.opacity(0.9))
                            .frame(width: max(6, geo.size.width * min(1, progress)))
                    }
                }.frame(height: 4)
            }
        }
        .padding(14)
        .glassCard(radius: 18)
    }

    private var quickActions: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            quickAction(title: "Scan Physique", icon: "figure.arms.open", tint: Theme.accent) {
                NotificationCenter.default.post(name: .switchTab, object: AppTab.physique)
            }
            quickAction(title: "Log Meal", icon: "fork.knife.circle.fill", tint: Theme.good) {
                NotificationCenter.default.post(name: .switchTab, object: AppTab.cal)
            }
            quickAction(title: "Analyze Face", icon: "face.dashed", tint: Theme.elite) {
                NotificationCenter.default.post(name: .switchTab, object: AppTab.psl)
            }
            quickAction(title: "Hydrate", icon: "drop.fill", tint: Theme.accentGlow) {
                logHydration()
            }
        }
    }

    private func quickAction(title: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap(); action()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    Circle().fill(tint.opacity(0.18))
                    Image(systemName: icon).font(.system(size: 17, weight: .bold)).foregroundStyle(tint)
                }.frame(width: 38, height: 38)
                Text(title).font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(radius: 18)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Derived

    private var latestPhysiqueScore: Double { scans.first?.physiqueScore ?? 0 }
    private var latestPSLScore: Double { faces.first?.overallScore ?? 0 }
    private var latestSymmetry: Double { scans.first?.symmetryScore ?? 0 }

    private var currentHydration: Int {
        if let date = user.hydrationDate, Calendar.current.isDateInToday(date) {
            return user.hydrationGlasses
        }
        return 0
    }

    private var caloriesRemaining: Double {
        let target = Double(user.dailyCalorieTarget)
        let eaten = Double(mealsTodayList.reduce(0) { $0 + $1.calories })
        return max(0, target - eaten)
    }

    private var mealsTodayList: [MealEntry] {
        let cal = Calendar.current
        return meals.filter { cal.isDateInToday($0.date) }
    }

    private func logHydration() {
        let today = Calendar.current.startOfDay(for: .now)
        if user.hydrationDate != today {
            user.hydrationGlasses = 0
            user.hydrationDate = today
        }
        user.hydrationGlasses += 1
        try? ctx.save()
    }

    private func loadInsight() async {
        let snap = ProfileSnapshot(age: user.ageValue, sex: user.sexRaw, heightCm: user.heightCm, weightKg: user.weightKg, goals: user.goalsRaw)
        let mealsToday = mealsTodayList
        let adherence = Double(mealsToday.reduce(0) { $0 + $1.calories }) / Double(max(1, user.dailyCalorieTarget))
        if let r = try? await AIService.shared.dailyInsight(profile: snap, streak: user.streak, recentScansCount: scans.count, caloriesAdherence: adherence) {
            await MainActor.run {
                withAnimation(.smooth(duration: 0.6)) {
                    insightHeadline = r.headline
                    insightDetail = r.detail
                    insightLoading = false
                }
            }
        } else {
            await MainActor.run {
                withAnimation(.smooth(duration: 0.4)) {
                    insightLoading = false
                    insightHeadline = "Begin gathering signals."
                    insightDetail = "Log a meal or run a scan to unlock personalized insight."
                }
            }
        }
    }
}

extension Notification.Name {
    static let switchTab = Notification.Name("aether.switchTab")
}
