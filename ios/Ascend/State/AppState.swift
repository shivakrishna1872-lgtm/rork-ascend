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
            if cal.isDate(lastDay, inSameDayAs: today) {
                // Already counted today, but make sure a stale value is corrected.
                if user.streak < 1 { user.streak = 1 }
                return
            }
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

    /// Reconciles a possibly-stale streak for display. The streak counter is
    /// only ever advanced when the user logs an activity, so after a missed day
    /// it would otherwise keep showing the old number. Call this on launch /
    /// when surfacing the streak: if the last active day is before yesterday,
    /// the streak is broken and resets to 0.
    func reconcileStreak(_ user: UserProfile) {
        guard user.streak > 0, let last = user.lastActiveDate else {
            if user.lastActiveDate == nil { user.streak = 0 }
            return
        }
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let lastDay = cal.startOfDay(for: last)
        guard let yesterday = cal.date(byAdding: .day, value: -1, to: today) else { return }
        // Active today or yesterday → streak still alive. Anything older is broken.
        if !cal.isDate(lastDay, inSameDayAs: today),
           !cal.isDate(lastDay, inSameDayAs: yesterday),
           lastDay < yesterday {
            user.streak = 0
        }
    }
}
