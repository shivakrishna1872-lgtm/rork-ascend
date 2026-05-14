import Foundation
import SwiftData
import WidgetKit

/// Writes the latest user data to a shared App Group UserDefaults
/// so AscendWidgets can render real, live numbers.
enum WidgetSync {
    static let appGroupID = "group.app.rork.5dm6zbnyue71m6ouijlfh.shared"

    enum Key {
        // Cal AI
        static let caloriesEaten = "cal.eaten"
        static let caloriesTarget = "cal.target"
        static let proteinEaten = "cal.proteinEaten"
        static let proteinTarget = "cal.proteinTarget"
        static let carbsEaten = "cal.carbsEaten"
        static let carbsTarget = "cal.carbsTarget"
        static let fatsEaten = "cal.fatsEaten"
        static let fatsTarget = "cal.fatsTarget"
        static let hydration = "cal.hydration"
        static let calorieHistory = "cal.history7"        // [Int] last 7 days kcal (oldest..today)
        static let mealsLogged = "cal.mealsToday"

        // Physique
        static let physiqueScore = "phys.score"
        static let physiqueDate = "phys.date"
        static let symmetryScore = "phys.symmetry"
        static let muscularityScore = "phys.muscle"
        static let conditioningScore = "phys.conditioning"
        static let bodyFat = "phys.bf"
        static let bodyFatPrev = "phys.bfPrev"
        static let physiqueHistory = "phys.history6"      // [Double] last 6 scans (oldest..latest)
        static let physiqueCount = "phys.count"

        // PSL
        static let pslScore = "psl.score"
        static let pslDate = "psl.date"
        static let pslSymmetry = "psl.symmetry"
        static let pslJawline = "psl.jawline"
        static let pslGlowUp = "psl.glowUp"
        static let pslHistory = "psl.history6"
        static let pslCount = "psl.count"

        // Identity / streak / tier
        static let userName = "user.name"
        static let xp = "user.xp"
        static let tierRaw = "user.tier"
        static let tierXPFloor = "user.tierFloor"
        static let tierXPCeil = "user.tierCeil"
        static let streak = "user.streak"
        static let streakHistory = "user.streak7"         // [Int] 0/1 last 7 days (oldest..today)

        // Leaderboard (XP-based circle rank — used for both Physique & PSL widgets)
        static let groupName = "lb.groupName"
        static let groupRank = "lb.rank"
        static let groupSize = "lb.size"
        static let gapToNextXP = "lb.gapNext"
        static let topThreeNames = "lb.topNames"          // [String]
        static let topThreeXP = "lb.topXP"                // [Int]

        // Updated marker
        static let updatedAt = "meta.updatedAt"
    }

    static var defaults: UserDefaults? { UserDefaults(suiteName: appGroupID) }

    @MainActor
    static func push(user: UserProfile, context: ModelContext) {
        guard let d = defaults else { return }

        let cal = Calendar.current
        let now = Date()

        // Meals
        let mealDescriptor = FetchDescriptor<MealEntry>()
        let meals = (try? context.fetch(mealDescriptor)) ?? []
        let today = meals.filter { cal.isDateInToday($0.date) }
        let kcal = today.reduce(0) { $0 + $1.calories }
        let protein = today.reduce(0) { $0 + $1.proteinG }
        let carbs = today.reduce(0) { $0 + $1.carbsG }
        let fats = today.reduce(0) { $0 + $1.fatsG }

        // 7-day kcal history (oldest..today)
        var calorieHistory: [Int] = []
        for offset in stride(from: 6, through: 0, by: -1) {
            guard let day = cal.date(byAdding: .day, value: -offset, to: now) else { continue }
            let total = meals
                .filter { cal.isDate($0.date, inSameDayAs: day) }
                .reduce(0) { $0 + $1.calories }
            calorieHistory.append(total)
        }

        // Streak heatmap (last 7 days, 1 if active that day = meal logged or scan)
        let scanDescAll = FetchDescriptor<PhysiqueScanRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        let allScans = (try? context.fetch(scanDescAll)) ?? []
        let faceDescAll = FetchDescriptor<FaceScanRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        let allFaces = (try? context.fetch(faceDescAll)) ?? []
        var streakHistory: [Int] = []
        for offset in stride(from: 6, through: 0, by: -1) {
            guard let day = cal.date(byAdding: .day, value: -offset, to: now) else { continue }
            let active = meals.contains(where: { cal.isDate($0.date, inSameDayAs: day) })
                || allScans.contains(where: { cal.isDate($0.date, inSameDayAs: day) })
                || allFaces.contains(where: { cal.isDate($0.date, inSameDayAs: day) })
            streakHistory.append(active ? 1 : 0)
        }

        // Hydration (only if same day)
        let hydration: Int = {
            if let date = user.hydrationDate, cal.isDateInToday(date) { return user.hydrationGlasses }
            return 0
        }()

        // Physique
        let latestScan = allScans.first
        let prevScan = allScans.dropFirst().first
        let physiqueHistory: [Double] = allScans.prefix(6).reversed().map { $0.physiqueScore }

        // Face / PSL
        let latestFace = allFaces.first
        let pslHistory: [Double] = allFaces.prefix(6).reversed().map { $0.overallScore }

        // Group rank (XP-based, largest group with members)
        let groupDescriptor = FetchDescriptor<FriendGroup>()
        let groups = (try? context.fetch(groupDescriptor)) ?? []
        let activeGroup = groups.sorted { $0.members.count > $1.members.count }.first
        var rank = 1
        var groupSize = 1
        var groupName = ""
        var gap = 0
        var topNames: [String] = []
        var topXP: [Int] = []
        if let g = activeGroup {
            let ranked = g.rankedMembers(currentUserXP: user.xp, currentUserName: user.name)
            groupSize = ranked.count
            groupName = g.name
            if let idx = ranked.firstIndex(where: { $0.isMe }) {
                rank = idx + 1
                if idx > 0 {
                    gap = max(0, ranked[idx - 1].xp - user.xp)
                }
            }
            for m in ranked.prefix(3) {
                topNames.append(m.name)
                topXP.append(m.xp)
            }
        }

        // Cal AI
        d.set(kcal, forKey: Key.caloriesEaten)
        d.set(user.dailyCalorieTarget, forKey: Key.caloriesTarget)
        d.set(protein, forKey: Key.proteinEaten)
        d.set(user.proteinTargetG, forKey: Key.proteinTarget)
        d.set(carbs, forKey: Key.carbsEaten)
        d.set(user.carbTargetG, forKey: Key.carbsTarget)
        d.set(fats, forKey: Key.fatsEaten)
        d.set(user.fatTargetG, forKey: Key.fatsTarget)
        d.set(hydration, forKey: Key.hydration)
        d.set(calorieHistory, forKey: Key.calorieHistory)
        d.set(today.count, forKey: Key.mealsLogged)

        // Physique
        d.set(latestScan?.physiqueScore ?? 0, forKey: Key.physiqueScore)
        d.set(latestScan?.date.timeIntervalSince1970 ?? 0, forKey: Key.physiqueDate)
        d.set(latestScan?.symmetryScore ?? 0, forKey: Key.symmetryScore)
        d.set(latestScan?.muscularityScore ?? 0, forKey: Key.muscularityScore)
        d.set(latestScan?.conditioningScore ?? 0, forKey: Key.conditioningScore)
        d.set(latestScan?.bodyFatPercent ?? 0, forKey: Key.bodyFat)
        d.set(prevScan?.bodyFatPercent ?? 0, forKey: Key.bodyFatPrev)
        d.set(physiqueHistory, forKey: Key.physiqueHistory)
        d.set(allScans.count, forKey: Key.physiqueCount)

        // PSL
        d.set(latestFace?.overallScore ?? 0, forKey: Key.pslScore)
        d.set(latestFace?.date.timeIntervalSince1970 ?? 0, forKey: Key.pslDate)
        d.set(latestFace?.symmetry ?? 0, forKey: Key.pslSymmetry)
        d.set(latestFace?.jawline ?? 0, forKey: Key.pslJawline)
        d.set(latestFace?.glowUpPotential ?? 0, forKey: Key.pslGlowUp)
        d.set(pslHistory, forKey: Key.pslHistory)
        d.set(allFaces.count, forKey: Key.pslCount)

        // Identity
        d.set(user.name, forKey: Key.userName)
        d.set(user.xp, forKey: Key.xp)
        d.set(user.tier.rawValue, forKey: Key.tierRaw)
        d.set(user.tier.xpFloor, forKey: Key.tierXPFloor)
        d.set(user.tier.xpCeiling, forKey: Key.tierXPCeil)
        d.set(user.streak, forKey: Key.streak)
        d.set(streakHistory, forKey: Key.streakHistory)

        // Leaderboard
        d.set(groupName, forKey: Key.groupName)
        d.set(rank, forKey: Key.groupRank)
        d.set(groupSize, forKey: Key.groupSize)
        d.set(gap, forKey: Key.gapToNextXP)
        d.set(topNames, forKey: Key.topThreeNames)
        d.set(topXP, forKey: Key.topThreeXP)

        d.set(Date().timeIntervalSince1970, forKey: Key.updatedAt)

        WidgetCenter.shared.reloadAllTimelines()
    }
}
