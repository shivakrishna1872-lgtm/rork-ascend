import SwiftUI
import SwiftData

@MainActor
@Observable
final class AppState {
    var currentUserId: PersistentIdentifier?
    var showTierPromotion: Tier? = nil
    var lastTier: Tier = .bronze

    // Awards XP and triggers promotion sequence if tier crosses.
    func awardXP(_ amount: Int, to user: UserProfile) {
        let oldTier = user.tier
        user.xp = max(0, user.xp + amount)
        let newTier = user.tier
        if newTier != oldTier && Tier.allCases.firstIndex(of: newTier)! > Tier.allCases.firstIndex(of: oldTier)! {
            lastTier = oldTier
            showTierPromotion = newTier
            Haptics.success()
        }
    }

    func bumpStreakIfNeeded(_ user: UserProfile) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        if let last = user.lastActiveDate {
            let lastDay = cal.startOfDay(for: last)
            if cal.isDate(lastDay, inSameDayAs: today) { return }
            if let yesterday = cal.date(byAdding: .day, value: -1, to: today),
               cal.isDate(lastDay, inSameDayAs: yesterday) {
                user.streak += 1
            } else {
                user.streak = 1
            }
        } else {
            user.streak = 1
        }
        user.lastActiveDate = .now
    }
}
