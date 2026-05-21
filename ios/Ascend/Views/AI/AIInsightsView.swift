import SwiftUI
import SwiftData

/// Synthesizes every signal the app has on the user (physique scans, face
/// scans, nutrition history, lifts, hydration, streak) into one cohesive,
/// data-grounded coaching analysis. Falls back to a deterministic on-device
/// heuristic if every upstream AI model fails, so this tab never shows a blank.
struct AIInsightsView: View {
    let user: UserProfile
    @Environment(\.modelContext) private var ctx
    @Query(sort: \PhysiqueScanRecord.date, order: .reverse) private var scans: [PhysiqueScanRecord]
    @Query(sort: \FaceScanRecord.date, order: .reverse) private var faces: [FaceScanRecord]
    @Query(sort: \MealEntry.date, order: .reverse) private var meals: [MealEntry]
    @Query(sort: \LiftEntry.date, order: .reverse) private var lifts: [LiftEntry]

    @State private var insights: CoachInsights?
    @State private var loading: Bool = true
    @State private var errorText: String? = nil
    @State private var generatedAt: Date? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header.blurFadeIn(delay: 0)

                if loading {
                    loadingCard.blurFadeIn(delay: 0.08)
                    skeletonRow.blurFadeIn(delay: 0.14)
                    skeletonRow.blurFadeIn(delay: 0.18)
                } else if let i = insights {
                    summaryCard(i).blurFadeIn(delay: 0.06)
                    if !i.strengths.isEmpty {
                        SectionHeader(title: "What's Working").padding(.horizontal, 4)
                        strengthsCard(i).blurFadeIn(delay: 0.12)
                    }
                    if !i.focusAreas.isEmpty {
                        SectionHeader(title: "Focus Areas",
                                      trailing: "\(i.focusAreas.count)").padding(.horizontal, 4)
                        VStack(spacing: 10) {
                            ForEach(Array(i.focusAreas.enumerated()), id: \.offset) { idx, f in
                                focusRow(f).blurFadeIn(delay: 0.16 + Double(idx) * 0.05)
                            }
                        }
                    }
                    if !i.actions.isEmpty {
                        SectionHeader(title: "Action Plan",
                                      trailing: "\(i.actions.count) steps").padding(.horizontal, 4)
                        VStack(spacing: 10) {
                            ForEach(Array(i.actions.enumerated()), id: \.offset) { idx, a in
                                actionRow(a, index: idx + 1).blurFadeIn(delay: 0.20 + Double(idx) * 0.05)
                            }
                        }
                    }
                    projectionCard(i).blurFadeIn(delay: 0.30)
                    refreshFooter.blurFadeIn(delay: 0.34)
                } else if let err = errorText {
                    errorCard(err).blurFadeIn(delay: 0.1)
                }

                Color.clear.frame(height: 8)
            }
            .padding(.horizontal, 20).padding(.top, 12)
        }
        .scrollIndicators(.hidden)
        .tabBarBottomInset()
        .refreshable { await refresh(force: true) }
        .task {
            if insights == nil { await refresh(force: false) }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Coach".uppercased())
                    .font(.system(size: 11, weight: .semibold)).tracking(2)
                    .foregroundStyle(Theme.textTertiary)
                Text("AI Analysis")
                    .font(.aetherTitle).foregroundStyle(Theme.textPrimary)
            }
            Spacer()
            Button {
                Haptics.tap()
                Task { await refresh(force: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 42, height: 42)
                    .glassCard(radius: 12)
            }
            .buttonStyle(.plain)
            .disabled(loading)
            .opacity(loading ? 0.5 : 1)
        }
    }

    // MARK: - Summary

    private func summaryCard(_ i: CoachInsights) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                momentumPill(i.momentum)
                if i.isOfflineEstimate == true {
                    Text("OFFLINE")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.5)
                        .foregroundStyle(Theme.warn)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(Theme.warn.opacity(0.15)))
                        .overlay(Capsule().strokeBorder(Theme.warn.opacity(0.4), lineWidth: 0.5))
                }
                Spacer()
            }
            Text(i.headline)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(i.summary)
                .font(.aetherBody)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 22)
    }

    private func momentumPill(_ momentum: String) -> some View {
        let (icon, color, label): (String, Color, String) = {
            switch momentum.lowercased() {
            case "rising":   return ("arrow.up.right", Theme.good, "Rising")
            case "slipping": return ("arrow.down.right", Theme.bad, "Slipping")
            default:         return ("equal", Theme.accentGlow, "Stable")
            }
        }()
        return HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 10, weight: .heavy))
            Text(label.uppercased()).font(.system(size: 10, weight: .heavy)).tracking(1.5)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Capsule().fill(color.opacity(0.15)))
        .overlay(Capsule().strokeBorder(color.opacity(0.45), lineWidth: 0.6))
    }

    // MARK: - Strengths

    private func strengthsCard(_ i: CoachInsights) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(i.strengths.enumerated()), id: \.offset) { _, s in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.good)
                    Text(s)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 18)
    }

    // MARK: - Focus

    private func focusRow(_ f: CoachFocusArea) -> some View {
        let tint = priorityTint(f.priority)
        return HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tint.opacity(0.18))
                Image(systemName: categoryIcon(f.category))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(tint)
            }
            .frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(f.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer(minLength: 0)
                    Text(f.priority.uppercased())
                        .font(.system(size: 9, weight: .heavy)).tracking(1.2)
                        .foregroundStyle(tint)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(tint.opacity(0.16)))
                        .overlay(Capsule().strokeBorder(tint.opacity(0.4), lineWidth: 0.5))
                }
                Text(f.detail)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 18)
    }

    private func priorityTint(_ p: String) -> Color {
        switch p.lowercased() {
        case "high":   return Theme.bad
        case "medium": return Theme.warn
        default:       return Theme.accentGlow
        }
    }

    private func categoryIcon(_ c: String) -> String {
        switch c.lowercased() {
        case "physique":  return "figure.stand"
        case "face":      return "face.smiling"
        case "nutrition": return "fork.knife"
        case "strength":  return "dumbbell.fill"
        case "recovery":  return "moon.zzz.fill"
        case "habits":    return "flame.fill"
        default:          return "sparkles"
        }
    }

    // MARK: - Actions

    private func actionRow(_ a: CoachAction, index: Int) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(Theme.accent.opacity(0.18))
                    .overlay(Circle().strokeBorder(Theme.accent.opacity(0.4), lineWidth: 0.6))
                Text("\(index)")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
            }
            .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(a.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                    Text(a.timeframe.uppercased())
                        .font(.system(size: 9, weight: .heavy)).tracking(1.2)
                        .foregroundStyle(Theme.textTertiary)
                    Text("·")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                    Text(a.impact)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 18)
    }

    // MARK: - Projection

    private func projectionCard(_ i: CoachInsights) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.accentGlow)
                Text("4-WEEK PROJECTION")
                    .font(.system(size: 10, weight: .heavy)).tracking(1.8)
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                CountingNumber(value: Double(i.nextScoreEstimate),
                               font: .system(size: 44, weight: .semibold, design: .rounded),
                               color: Theme.textPrimary)
                Text("/100")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
            }
            Text("Projected strongest score if you stick to the plan for the next 4 weeks.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 22)
    }

    private var refreshFooter: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.textTertiary)
            Text(generatedAt.map { "Updated \(timeAgo($0))" } ?? "Updated just now")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
            Spacer()
            Text("Pull to refresh")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, 4)
    }

    private func timeAgo(_ d: Date) -> String {
        let secs = Int(-d.timeIntervalSinceNow)
        if secs < 60 { return "just now" }
        if secs < 3600 { return "\(secs/60) min ago" }
        if secs < 86400 { return "\(secs/3600) h ago" }
        return "\(secs/86400) d ago"
    }

    // MARK: - Loading / error

    private var loadingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ProgressView().tint(Theme.accentGlow)
                Text("Synthesizing your data…")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
            }
            Text("Reading scans, meals, lifts, and habits to build your plan.")
                .font(.aetherBody).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 22)
    }

    private var skeletonRow: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12).fill(Theme.surface).frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4).fill(Theme.surface).frame(height: 12)
                RoundedRectangle(cornerRadius: 4).fill(Theme.surface).frame(width: 180, height: 10)
            }
        }
        .padding(14)
        .glassCard(radius: 18)
        .opacity(0.5)
    }

    private func errorCard(_ msg: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.warn)
            Text(msg)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
            GhostButton(title: "Retry", icon: "arrow.clockwise") {
                Task { await refresh(force: true) }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .glassCard(radius: 22)
    }

    // MARK: - Data

    private func buildInputs() -> CoachInputs {
        let snap = ProfileSnapshot(
            age: user.ageValue, sex: user.sexRaw,
            heightCm: user.heightCm, weightKg: user.weightKg,
            goals: user.goalsRaw, unitSystem: user.unitSystemRaw
        )
        // Physique
        let p0 = scans.first
        let pTrend: Double = {
            guard let newest = scans.first, scans.count >= 2,
                  let oldest = scans.prefix(6).last else { return 0 }
            return newest.physiqueScore - oldest.physiqueScore
        }()
        // Face
        let f0 = faces.first
        let fTrend: Double = {
            guard let newest = faces.first, faces.count >= 2,
                  let oldest = faces.prefix(6).last else { return 0 }
            return newest.overallScore - oldest.overallScore
        }()
        // Nutrition (7d rolling average across days that have meals)
        let cal = Calendar.current
        let cutoff = cal.date(byAdding: .day, value: -7, to: .now) ?? .now.addingTimeInterval(-7*86400)
        let recent = meals.filter { $0.date >= cutoff }
        // Group by day
        var byDay: [Date: (kcal: Int, p: Int)] = [:]
        for m in recent {
            let d = cal.startOfDay(for: m.date)
            var entry = byDay[d] ?? (0, 0)
            entry.kcal += m.calories
            entry.p += m.proteinG
            byDay[d] = entry
        }
        let daysWithData = max(1, byDay.count)
        let avgKcal = byDay.values.reduce(0) { $0 + $1.kcal } / daysWithData
        let avgProtein = byDay.values.reduce(0) { $0 + $1.p } / daysWithData
        // Strength
        let lastBench = lifts.first(where: { $0.benchKg > 0 })?.benchKg
        let lastSquat = lifts.first(where: { $0.squatKg > 0 })?.squatKg
        let lastDead = lifts.first(where: { $0.deadliftKg > 0 })?.deadliftKg
        let liftTrend: Double = {
            guard lifts.count >= 2,
                  let newest = lifts.first, let oldest = lifts.last else { return 0 }
            return newest.totalKg - oldest.totalKg
        }()
        // Hydration
        let hydration: Int = {
            if let d = user.hydrationDate, cal.isDateInToday(d) { return user.hydrationGlasses }
            return 0
        }()

        return CoachInputs(
            profile: snap,
            streak: user.streak,
            xp: user.xp,
            tier: user.tier.rawValue,
            latestPhysique: p0?.physiqueScore,
            latestSymmetry: p0?.symmetryScore,
            latestMuscularity: p0?.muscularityScore,
            latestConditioning: p0?.conditioningScore,
            latestVTaper: p0?.vTaperScore,
            latestBodyFat: p0?.bodyFatPercent,
            physiqueTrend: pTrend,
            physiqueScanCount: scans.count,
            latestPSL: f0?.overallScore,
            latestJawline: f0?.jawline,
            latestSymmetryFace: f0?.symmetry,
            faceTrend: fTrend,
            faceScanCount: faces.count,
            avgCalories: avgKcal,
            avgProtein: avgProtein,
            calorieTarget: user.dailyCalorieTarget,
            proteinTarget: user.proteinTargetG,
            mealsLogged7d: recent.count,
            benchKg: lastBench,
            squatKg: lastSquat,
            deadliftKg: lastDead,
            liftTrendKg: liftTrend,
            hydrationGlasses: hydration
        )
    }

    private func refresh(force: Bool) async {
        if !force, insights != nil, let at = generatedAt, -at.timeIntervalSinceNow < 60 * 10 {
            return
        }
        await MainActor.run {
            loading = true
            errorText = nil
        }
        let inputs = buildInputs()
        do {
            let result = try await AIService.shared.coachInsights(inputs)
            await MainActor.run {
                withAnimation(.smooth(duration: 0.4)) {
                    insights = result
                    generatedAt = .now
                    loading = false
                }
            }
        } catch let e as AIServiceError {
            // Catastrophic only — heuristic fallback already runs inside AIService
            // for transient failures. consent / config issues land here.
            await MainActor.run {
                withAnimation(.smooth(duration: 0.3)) {
                    errorText = e.errorDescription
                    loading = false
                }
            }
        } catch {
            // Final safety net: never leave the tab empty.
            let fallback = CoachHeuristic.estimate(inputs: inputs)
            await MainActor.run {
                withAnimation(.smooth(duration: 0.3)) {
                    insights = fallback
                    generatedAt = .now
                    loading = false
                }
            }
        }
    }
}
