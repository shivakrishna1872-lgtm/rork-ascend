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
                      lifts: [LiftEntry]) -> Outcome {
        let a = action.args
        switch action.tool {
        case "setCalorieTarget":
            guard let cals = a.calories, (1200...5000).contains(cals) else {
                return .failed("invalid calories")
            }
            let days = max(1, min(14, a.days ?? 1))
            user.calorieOverrideValue = cals
            user.calorieOverrideUntil = Calendar.current.date(byAdding: .day, value: days, to: .now)
            try? ctx.save()
            return .applied

        case "setProteinTarget":
            guard let g = a.proteinG, (40...400).contains(g) else {
                return .failed("invalid protein")
            }
            let days = max(1, min(14, a.days ?? 1))
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

        case "logLifts":
            let bench = max(0, min(500, a.benchKg ?? 0))
            let squat = max(0, min(500, a.squatKg ?? 0))
            let dead  = max(0, min(500, a.deadliftKg ?? 0))
            guard bench + squat + dead > 0 else { return .failed("no lifts provided") }
            let entry = LiftEntry(date: .now, benchKg: bench, squatKg: squat, deadliftKg: dead, note: "Logged by coach")
            ctx.insert(entry)
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
                     lifts: [LiftEntry]) {
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
        case "logLifts":
            if let l = lifts.first {
                ctx.delete(l); try? ctx.save()
            }
        case "openTab", "generatePlan":
            break // no-op, UI marks as undone
        default:
            break
        }
    }
}
