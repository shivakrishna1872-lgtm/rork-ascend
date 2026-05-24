import Foundation
import SwiftData

/// Applies coach-proposed tool calls to SwiftData with strict validation.
/// Every input is clamped to a safe range so a hallucinated value can never
/// corrupt the user's profile. Returns a `Result` the chat view turns into a
/// pill ("Applied" / "Failed").
@MainActor
enum CoachActionRunner {
    enum Outcome {
        case applied
        case failed(String)
    }

    static func apply(action: CoachToolCall,
                      user: UserProfile,
                      ctx: ModelContext,
                      meals: [MealEntry],
                      lifts: [LiftEntry],
                      plans: [WorkoutPlan] = []) -> Outcome {
        let a = action.args
        switch action.tool {
        case "setCalorieTarget":
            guard let cals = a.calories, (800...6000).contains(cals) else {
                return .failed("invalid calories")
            }
            let days = max(1, min(60, a.days ?? 7))
            user.calorieOverrideValue = cals
            user.calorieOverrideUntil = Calendar.current.date(byAdding: .day, value: days, to: .now)
            try? ctx.save()
            return .applied

        case "setProteinTarget":
            guard let g = a.proteinG, (30...500).contains(g) else {
                return .failed("invalid protein")
            }
            let days = max(1, min(60, a.days ?? 7))
            user.proteinOverrideValue = g
            user.proteinOverrideUntil = Calendar.current.date(byAdding: .day, value: days, to: .now)
            try? ctx.save()
            return .applied

        case "updateProfile":
            var touched = false
            if let w = a.weightKg, (30...250).contains(w) {
                user.weightKg = w; touched = true
            }
            if let h = a.heightCm, (120...230).contains(h) {
                user.heightCm = h; touched = true
            }
            if let age = a.age, (13...100).contains(age) {
                user.ageValue = age; touched = true
            }
            if let g = a.goals, !g.isEmpty {
                let valid = Set(Goal.allCases.map { $0.rawValue })
                // Also accept the enum case name (e.g. "loseFat" -> "Lose Fat")
                let nameMap: [String: String] = Dictionary(uniqueKeysWithValues: Goal.allCases.map {
                    (String(describing: $0), $0.rawValue)
                })
                let cleaned = g.compactMap { raw -> String? in
                    if valid.contains(raw) { return raw }
                    return nameMap[raw]
                }
                if !cleaned.isEmpty {
                    user.goalsRaw = Array(Set(cleaned))
                    touched = true
                }
            }
            if let u = a.unitSystem?.lowercased() {
                if u.contains("metric") { user.unitSystemRaw = UnitSystem.metric.rawValue; touched = true }
                else if u.contains("imperial") { user.unitSystemRaw = UnitSystem.imperial.rawValue; touched = true }
            }
            if touched {
                try? ctx.save()
                return .applied
            }
            return .failed("nothing to update")

        case "logMeal":
            let cals = max(0, min(4000, a.calories ?? 0))
            let p = max(0, min(300, a.proteinG ?? 0))
            let c = max(0, min(500, a.carbsG ?? 0))
            let f = max(0, min(300, a.fatsG ?? 0))
            let name = (a.mealName?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "Meal"
            guard cals + p + c + f > 0 else { return .failed("missing macros") }
            let meal = MealEntry(date: .now, name: name, calories: cals,
                                 proteinG: p, carbsG: c, fatsG: f,
                                 note: "Logged by coach")
            ctx.insert(meal)
            try? ctx.save()
            return .applied

        case "removeLastMeal":
            guard let m = meals.first else { return .failed("no meals to remove") }
            ctx.delete(m)
            try? ctx.save()
            return .applied

        case "logLifts", "setLifts":
            // Both tools insert a new LiftEntry — the latest row is treated as
            // "current" by the rest of the app, so setLifts is just a clearer
            // user-facing alias for "my bench is now X".
            let bench = max(0, min(600, a.benchKg ?? 0))
            let squat = max(0, min(700, a.squatKg ?? 0))
            let dead  = max(0, min(700, a.deadliftKg ?? 0))
            guard bench + squat + dead > 0 else { return .failed("no lifts provided") }
            let note = action.tool == "setLifts" ? "Set by coach" : "Logged by coach"
            let entry = LiftEntry(date: .now, benchKg: bench, squatKg: squat, deadliftKg: dead, note: note)
            ctx.insert(entry)
            try? ctx.save()
            return .applied

        case "clearHydration":
            user.hydrationDate = .now
            user.hydrationGlasses = 0
            try? ctx.save()
            return .applied

        case "clearTodayMeals":
            let cal = Calendar.current
            let today = meals.filter { cal.isDateInToday($0.date) }
            guard !today.isEmpty else { return .failed("no meals today") }
            for m in today { ctx.delete(m) }
            try? ctx.save()
            return .applied

        case "setStreak":
            guard let s = a.streak, (0...3650).contains(s) else { return .failed("invalid streak") }
            user.streak = s
            try? ctx.save()
            return .applied

        case "setExerciseWeight":
            // Updates the `notes` of every matching exercise across the user's
            // active workout plans with a fresh "working weight" tag. Lets the
            // user say "change my bench to 125" and have it stick on the plan.
            guard let raw = a.exerciseName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                  !raw.isEmpty,
                  let weight = a.weightKg, (1...700).contains(weight)
            else { return .failed("missing exercise or weight") }
            let unit = (a.unitSystem?.lowercased() == "imperial") ? "lb" : "kg"
            let display = unit == "lb" ? Int(weight * 2.2046226218) : Int(weight)
            var touched = 0
            for plan in plans {
                for day in plan.days {
                    for ex in day.exercises where ex.name.lowercased().contains(raw) || raw.contains(ex.name.lowercased()) {
                        // Strip any existing "@ NNNkg" or "@ NNNlb" tag, then append fresh.
                        let stripped = ex.notes.replacingOccurrences(
                            of: #"@\s*\d+\s*(kg|lb)"#,
                            with: "",
                            options: .regularExpression
                        ).trimmingCharacters(in: .whitespacesAndNewlines)
                        let tag = "@ \(display)\(unit)"
                        ex.notes = stripped.isEmpty ? tag : "\(stripped) \(tag)"
                        touched += 1
                    }
                }
                if touched > 0 { plan.updatedAt = .now }
            }
            guard touched > 0 else { return .failed("exercise not found in your plans") }
            // Also log a lift entry so the "current bench/squat/deadlift" cards
            // update if the user named one of the big three.
            let lower = raw
            var b = 0.0, s = 0.0, d = 0.0
            if lower.contains("bench") { b = weight }
            else if lower.contains("squat") { s = weight }
            else if lower.contains("dead") { d = weight }
            if b + s + d > 0 {
                ctx.insert(LiftEntry(date: .now, benchKg: b, squatKg: s, deadliftKg: d, note: "Set by coach"))
            }
            try? ctx.save()
            return .applied

        case "deletePlan":
            guard let title = a.planTitle?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                  !title.isEmpty
            else { return .failed("missing plan title") }
            let match = plans.first { $0.title.lowercased().contains(title) || title.contains($0.title.lowercased()) }
            guard let plan = match else { return .failed("plan not found") }
            ctx.delete(plan)
            try? ctx.save()
            return .applied

        case "addHydration":
            let g = max(1, min(8, a.glasses ?? 1))
            let cal = Calendar.current
            if let d = user.hydrationDate, cal.isDateInToday(d) {
                user.hydrationGlasses = min(8, user.hydrationGlasses + g)
            } else {
                user.hydrationDate = .now
                user.hydrationGlasses = g
            }
            try? ctx.save()
            return .applied

        case "openTab":
            let raw = a.tab?.lowercased() ?? ""
            let tab: AppTab? = {
                switch raw {
                case "cal", "calai", "calorie", "nutrition": return .cal
                case "physique", "body": return .physique
                case "psl", "face": return .psl
                case "home", "dashboard": return .home
                case "circles", "social": return .circles
                case "workouts", "workout", "plan", "coach", "ai": return .ai
                default: return nil
                }
            }()
            guard let tab else { return .failed("unknown tab") }
            NotificationCenter.default.post(name: .switchTab, object: tab)
            return .applied

        case "generatePlan":
            // Plan is rendered inline from args.planText — nothing to persist.
            guard let t = a.planText, !t.isEmpty else { return .failed("empty plan") }
            return .applied

        case "importWorkoutPlan":
            guard let json = a.workoutPlanJSON,
                  let data = json.data(using: .utf8),
                  let parsed = try? JSONDecoder().decode(ImportedWorkoutPlan.self, from: data)
            else { return .failed("empty plan") }
            let nonEmpty = parsed.days.filter { !$0.exercises.isEmpty }
            guard !nonEmpty.isEmpty else { return .failed("no exercises") }

            let title = parsed.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let plan = WorkoutPlan(
                title: title.isEmpty ? "Scanned Plan" : title,
                goalRaw: WorkoutGoal.hypertrophy.rawValue,
                sourceRaw: WorkoutSource.scanned.rawValue
            )
            ctx.insert(plan)
            for (dIdx, day) in parsed.days.enumerated() {
                let d = WorkoutDay(
                    orderIndex: dIdx,
                    dayTitle: day.title.isEmpty ? "Day \(dIdx + 1)" : day.title,
                    focus: day.focus
                )
                d.plan = plan
                ctx.insert(d)
                for (eIdx, ex) in day.exercises.enumerated() {
                    let w = WorkoutExercise(
                        orderIndex: eIdx,
                        name: ex.name,
                        sets: max(1, min(20, ex.sets)),
                        reps: ex.reps,
                        restSeconds: max(0, min(600, ex.restSeconds)),
                        notes: ex.notes
                    )
                    w.day = d
                    ctx.insert(w)
                }
            }
            try? ctx.save()
            return .applied

        default:
            return .failed("unsupported action")
        }
    }

    /// Best-effort undo for actions that support it. Big-confirm actions are
    /// not undoable here — the user can just ask the coach to set them back.
    static func undo(action: CoachToolCall,
                     user: UserProfile,
                     ctx: ModelContext,
                     meals: [MealEntry],
                     lifts: [LiftEntry],
                     plans: [WorkoutPlan] = []) {
        let a = action.args
        switch action.tool {
        case "addHydration":
            let g = max(1, min(8, a.glasses ?? 1))
            user.hydrationGlasses = max(0, user.hydrationGlasses - g)
            try? ctx.save()
        case "logMeal":
            // Remove the newest meal entry that matches the logged name.
            if let m = meals.first {
                ctx.delete(m); try? ctx.save()
            }
        case "logLifts", "setLifts":
            if let l = lifts.first {
                ctx.delete(l); try? ctx.save()
            }
        case "openTab", "generatePlan":
            break // no-op, UI marks as undone
        case "importWorkoutPlan":
            // Remove the most recently inserted scanned plan whose title matches.
            guard let json = a.workoutPlanJSON,
                  let data = json.data(using: .utf8),
                  let parsed = try? JSONDecoder().decode(ImportedWorkoutPlan.self, from: data)
            else { break }
            let title = parsed.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let descriptor = FetchDescriptor<WorkoutPlan>()
            if let plans = try? ctx.fetch(descriptor) {
                let match = plans
                    .filter { $0.sourceRaw == WorkoutSource.scanned.rawValue && $0.title == title }
                    .sorted { $0.createdAt > $1.createdAt }
                    .first
                if let m = match {
                    ctx.delete(m)
                    try? ctx.save()
                }
            }
        default:
            break
        }
    }
}
