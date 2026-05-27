import Foundation

/// Flags lifts that haven't progressed in 3+ weeks and proposes a concrete,
/// deterministic remedy (deload / variation swap). Pure function of the
/// `SetLog` table — same history → same flags, no AI.
nonisolated enum PlateauDetector {

    struct Flag: Sendable, Equatable, Identifiable {
        let exerciseName: String
        let weeksStalled: Int
        let bestWeightKg: Double
        let suggestion: Suggestion

        var id: String { exerciseName.lowercased() }

        enum Suggestion: String, Sendable, Equatable {
            case deload      // pull weight back 8–10% and rebuild
            case variation   // swap to a close cousin to renew stimulus
            case repsFirst   // add reps before adding load
        }

        var rationale: String {
            switch suggestion {
            case .deload:
                return "No progress in \(weeksStalled)w — drop to \(Int(round(bestWeightKg * 0.92)))kg for 1–2 sessions, then push back."
            case .variation:
                return "Stalled for \(weeksStalled)w — swap to a cousin movement for 2–3 weeks, then return."
            case .repsFirst:
                return "Same load for \(weeksStalled)w — chase +1–2 reps per set before adding weight."
            }
        }
    }

    /// Returns at most `limit` flagged exercises, sorted by weeks-stalled descending.
    /// `minWeeks` is the threshold for "stalled" (default 3).
    static func detect(history: [SetLog], minWeeks: Int = 3, limit: Int = 4) -> [Flag] {
        let working = history.filter { $0.completed && $0.weightKg > 0 }
        let grouped = Dictionary(grouping: working) { $0.exerciseName.lowercased() }
        let now = Date()
        let cal = Calendar.current
        var flags: [Flag] = []
        for (key, logs) in grouped {
            // Need at least two distinct calendar weeks of data to call it stalled.
            let weeks = Set(logs.compactMap { cal.dateInterval(of: .weekOfYear, for: $0.date)?.start })
            guard weeks.count >= max(2, minWeeks) else { continue }

            let best = logs.map(\.weightKg).max() ?? 0
            guard best > 0 else { continue }

            // Find the most-recent log AT that best weight; if it's >= minWeeks ago, stalled.
            guard let firstHitDate = logs.filter({ abs($0.weightKg - best) < 0.001 }).map(\.date).min() else { continue }
            let weeksSinceFirstHit = max(0, cal.dateComponents([.weekOfYear], from: firstHitDate, to: now).weekOfYear ?? 0)
            guard weeksSinceFirstHit >= minWeeks else { continue }

            // Has the user logged the lift recently at all? If they stopped touching it
            // entirely, suggest variation; otherwise deload vs reps-first based on rep trend.
            let recentLogs = logs.filter { now.timeIntervalSince($0.date) < 60 * 60 * 24 * 21 }
            let suggestion: Flag.Suggestion
            if recentLogs.isEmpty {
                suggestion = .variation
            } else {
                let recentAtBest = recentLogs.filter { abs($0.weightKg - best) < 0.001 }
                let avgReps = recentAtBest.isEmpty
                    ? 0
                    : Double(recentAtBest.map(\.reps).reduce(0, +)) / Double(recentAtBest.count)
                // If they're already pushing high reps at top weight → deload to break through.
                // If reps are mid → tell them to chase reps first.
                suggestion = avgReps >= 8 ? .deload : .repsFirst
            }

            // Use the original casing from the most recent log.
            let display = logs.sorted { $0.date > $1.date }.first?.exerciseName ?? key
            flags.append(Flag(exerciseName: display,
                              weeksStalled: weeksSinceFirstHit,
                              bestWeightKg: best,
                              suggestion: suggestion))
        }
        return flags.sorted { $0.weeksStalled > $1.weeksStalled }.prefix(limit).map { $0 }
    }
}
