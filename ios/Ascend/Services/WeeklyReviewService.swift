import Foundation

/// Deterministic weekly recap of the user's activity. Pure function of
/// SwiftData reads — same inputs → identical recap. The Coach surfaces this
/// as a one-tap "Run weekly review" starter card; AI never authors the
/// numbers.
nonisolated enum WeeklyReviewService {

    struct Review: Sendable, Equatable {
        let weekEnding: Date
        let calorieAdherence: Double     // 0..1 — days hit within ±15% of target
        let proteinAdherence: Double     // 0..1 — days hit ≥85% of target
        let workoutsLogged: Int
        let liftPRs: [String]            // human-readable PRs this week
        let bodyScoreDelta: Double       // change vs prior week's latest scan
        let plateaus: [PlateauDetector.Flag]
        let headline: String
        let bullets: [String]
        let actions: [SuggestedAction]

        struct SuggestedAction: Sendable, Equatable, Identifiable {
            let id: String
            let label: String
            let tool: String     // CoachActionRunner tool name
            let summary: String
            let calories: Int?
            let proteinG: Int?
            let days: Int?
        }
    }

    /// Build a fresh review for the trailing 7 days.
    /// - Parameters:
    ///   - now: anchoring "today" — defaults to .now, parameterized for tests.
    ///   - calorieTarget: user's effective daily calorie target.
    ///   - proteinTarget: user's effective daily protein target.
    static func build(
        now: Date = .now,
        calorieTarget: Int,
        proteinTarget: Int,
        meals: [MealEntry],
        lifts: [LiftEntry],
        sets: [SetLog],
        scans: [PhysiqueScanRecord]
    ) -> Review {
        let cal = Calendar.current
        let weekStart = cal.date(byAdding: .day, value: -7, to: now) ?? now
        let priorStart = cal.date(byAdding: .day, value: -14, to: now) ?? now

        // ---- nutrition adherence ----
        let weekMeals = meals.filter { $0.date >= weekStart && $0.date <= now }
        var dailyCal: [Date: Int] = [:]
        var dailyPro: [Date: Int] = [:]
        for m in weekMeals {
            let day = cal.startOfDay(for: m.date)
            dailyCal[day, default: 0] += m.calories
            dailyPro[day, default: 0] += m.proteinG
        }
        let calHit = dailyCal.values.filter { abs(Double($0 - calorieTarget)) <= Double(calorieTarget) * 0.15 }.count
        let proHit = dailyPro.values.filter { Double($0) >= Double(proteinTarget) * 0.85 }.count
        let activeDays = max(1, dailyCal.count)
        let calorieAdherence = Double(calHit) / Double(activeDays)
        let proteinAdherence = Double(proHit) / Double(activeDays)

        // ---- workouts logged ----
        let weekSets = sets.filter { $0.date >= weekStart && $0.date <= now && $0.completed }
        let workoutDays = Set(weekSets.map { cal.startOfDay(for: $0.date) }).count

        // ---- lift PRs ----
        let weekLifts = lifts.filter { $0.date >= weekStart && $0.date <= now }
        let priorLifts = lifts.filter { $0.date < weekStart }
        let priorBench = priorLifts.map(\.benchKg).max() ?? 0
        let priorSquat = priorLifts.map(\.squatKg).max() ?? 0
        let priorDead  = priorLifts.map(\.deadliftKg).max() ?? 0
        var prs: [String] = []
        if let b = weekLifts.map(\.benchKg).max(), b > priorBench && b > 0 {
            prs.append("Bench PR: \(Int(b))kg")
        }
        if let s = weekLifts.map(\.squatKg).max(), s > priorSquat && s > 0 {
            prs.append("Squat PR: \(Int(s))kg")
        }
        if let d = weekLifts.map(\.deadliftKg).max(), d > priorDead && d > 0 {
            prs.append("Deadlift PR: \(Int(d))kg")
        }

        // ---- body score delta ----
        let recent = scans.first { $0.date >= weekStart }
        let prior = scans.first { $0.date < weekStart && $0.date >= priorStart }
        let bodyDelta = (recent?.physiqueScore ?? 0) - (prior?.physiqueScore ?? 0)

        // ---- plateaus ----
        let plateaus = PlateauDetector.detect(history: sets, minWeeks: 3, limit: 3)

        // ---- narrative ----
        var bullets: [String] = []
        bullets.append(String(format: "Calories hit on %d/%d active days (%.0f%%).", calHit, activeDays, calorieAdherence * 100))
        bullets.append(String(format: "Protein hit on %d/%d days (%.0f%%).", proHit, activeDays, proteinAdherence * 100))
        bullets.append("Trained \(workoutDays) day\(workoutDays == 1 ? "" : "s") this week.")
        if !prs.isEmpty {
            bullets.append("New PRs: " + prs.joined(separator: ", ") + ".")
        }
        if recent != nil && prior != nil {
            bullets.append(String(format: "Physique score %@%.1f vs last week.", bodyDelta >= 0 ? "+" : "", bodyDelta))
        }
        if !plateaus.isEmpty {
            let names = plateaus.prefix(2).map(\.exerciseName).joined(separator: ", ")
            bullets.append("Plateau watch: \(names).")
        }

        let headline: String = {
            if workoutDays == 0 && weekMeals.isEmpty {
                return "Quiet week — let's get the next one on track."
            }
            if calorieAdherence > 0.7 && workoutDays >= 3 {
                return "Strong week. Discipline + volume both showed up."
            }
            if !prs.isEmpty {
                return "PR week — momentum's real, keep stacking."
            }
            if workoutDays >= 3 {
                return "Solid training week. Nutrition can tighten."
            }
            return "Mixed week — small tweaks unlock the next one."
        }()

        // ---- suggested actions (one-tap apply via CoachActionRunner) ----
        var actions: [Review.SuggestedAction] = []
        if calorieAdherence < 0.4 && workoutDays >= 2 {
            // Often overshooting — propose a small cut for one week.
            let cut = max(800, calorieTarget - 200)
            actions.append(.init(
                id: "cal-tighten",
                label: "Tighten calories",
                tool: "setCalorieTarget",
                summary: "Set \(cut) kcal/day for 7 days",
                calories: cut, proteinG: nil, days: 7
            ))
        }
        if proteinAdherence < 0.5 {
            let bump = min(500, proteinTarget + 20)
            actions.append(.init(
                id: "pro-bump",
                label: "Raise protein floor",
                tool: "setProteinTarget",
                summary: "Set \(bump) g protein/day for 7 days",
                calories: nil, proteinG: bump, days: 7
            ))
        }

        return Review(
            weekEnding: now,
            calorieAdherence: calorieAdherence,
            proteinAdherence: proteinAdherence,
            workoutsLogged: workoutDays,
            liftPRs: prs,
            bodyScoreDelta: bodyDelta,
            plateaus: plateaus,
            headline: headline,
            bullets: bullets,
            actions: actions
        )
    }
}
