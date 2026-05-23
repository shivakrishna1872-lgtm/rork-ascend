import Foundation

/// Deterministic summarizer that turns the user's `SetLog` history into a
/// compact, AI-readable training summary. Pure function — same logs in, same
/// summary out. The coach reads this on every chat turn so it can answer
/// questions about training, spot stalls, and suggest next moves grounded in
/// the user's actual logged work.
nonisolated enum WorkoutCoachSummary {

    struct ExerciseStat: Sendable, Equatable {
        let name: String
        let sessions: Int
        let topWeightKg: Double
        let topReps: Int
        let lastDate: Date
        let suggestionDirection: String   // "up" | "hold" | "down" | "fresh"
        let suggestionWeightKg: Double
        let suggestionReason: String
        let isCompound: Bool
    }

    struct Summary: Sendable, Equatable {
        let totalSets14d: Int
        let totalSessions14d: Int
        let lastSessionDate: Date?
        let daysSinceLastSession: Int?
        let topExercises: [ExerciseStat]    // up to 5, ranked by recent volume
        let recentPRs: [String]             // human-readable, max 3
        let stalledExercises: [String]      // names where 3+ sessions show no progress
        let weeklyVolumeKg: Double          // sum(weight × reps) in last 7 days

        var isEmpty: Bool { totalSets14d == 0 }

        /// Compact text block injected into the system prompt.
        var promptBlock: String {
            guard !isEmpty else {
                return "training: no sets logged yet"
            }
            var lines: [String] = []
            let recency = daysSinceLastSession.map { "\($0)d ago" } ?? "—"
            lines.append("training (last 14d): \(totalSessions14d) sessions, \(totalSets14d) sets, last \(recency); 7d volume \(Int(weeklyVolumeKg))kg")
            if !topExercises.isEmpty {
                lines.append("top lifts:")
                for e in topExercises {
                    let top = e.topWeightKg > 0
                        ? "\(formatKg(e.topWeightKg))×\(e.topReps)"
                        : "bw×\(e.topReps)"
                    let next = e.suggestionWeightKg > 0
                        ? formatKg(e.suggestionWeightKg)
                        : "bw"
                    lines.append("  - \(e.name): top \(top), \(e.sessions) sessions, next → \(e.suggestionDirection) @ \(next) (\(e.suggestionReason))")
                }
            }
            if !recentPRs.isEmpty {
                lines.append("recent PRs: \(recentPRs.joined(separator: "; "))")
            }
            if !stalledExercises.isEmpty {
                lines.append("stalled: \(stalledExercises.joined(separator: ", "))")
            }
            return lines.joined(separator: "\n")
        }

        /// Stable cache-key fragment — keeps chat reply cache effective.
        var cacheKey: String {
            let top = topExercises.map {
                "\($0.name):\(Int($0.topWeightKg)):\($0.sessions):\($0.suggestionDirection)"
            }.joined(separator: "|")
            return "\(totalSets14d),\(totalSessions14d),\(Int(weeklyVolumeKg)),\(daysSinceLastSession ?? -1),\(top)"
        }
    }

    /// Build a summary from raw set logs. Compound vs isolation is inferred
    /// from the exercise name keyword list so we don't need to plumb the
    /// `WorkoutExercise` table through.
    static func build(from logs: [SetLog], now: Date = .now) -> Summary {
        let cal = Calendar.current
        let cutoff14 = cal.date(byAdding: .day, value: -14, to: now) ?? now.addingTimeInterval(-14 * 86400)
        let cutoff7  = cal.date(byAdding: .day, value: -7,  to: now) ?? now.addingTimeInterval(-7  * 86400)
        let recent = logs.filter { $0.date >= cutoff14 && $0.completed }
        guard !recent.isEmpty else {
            return Summary(
                totalSets14d: 0, totalSessions14d: 0,
                lastSessionDate: nil, daysSinceLastSession: nil,
                topExercises: [], recentPRs: [], stalledExercises: [],
                weeklyVolumeKg: 0
            )
        }

        let sessionDays = Set(recent.map { cal.startOfDay(for: $0.date) })
        let lastDate = recent.map(\.date).max()
        let daysSince = lastDate.map { max(0, cal.dateComponents([.day], from: cal.startOfDay(for: $0), to: cal.startOfDay(for: now)).day ?? 0) }

        // 7-day total volume = Σ(weight × reps).
        let weeklyVolume = logs
            .filter { $0.date >= cutoff7 && $0.completed }
            .reduce(0.0) { $0 + $1.weightKg * Double(max(1, $1.reps)) }

        // Group recent logs by exercise (lower-cased canonical name) and rank
        // by total volume so the most-trained lifts surface first.
        var byExercise: [String: [SetLog]] = [:]
        for l in recent {
            let key = l.exerciseName.lowercased().trimmingCharacters(in: .whitespaces)
            byExercise[key, default: []].append(l)
        }
        let ranked = byExercise.map { (key, sets) -> (String, [SetLog], Double) in
            let vol = sets.reduce(0.0) { $0 + $1.weightKg * Double(max(1, $1.reps)) }
            return (key, sets, vol)
        }.sorted { $0.2 > $1.2 }

        var stats: [ExerciseStat] = []
        var prs: [String] = []
        var stalled: [String] = []
        for (_, sets, _) in ranked.prefix(5) {
            guard let display = sets.first?.exerciseName else { continue }
            let topWeight = sets.map(\.weightKg).max() ?? 0
            let topSet = sets.first { abs($0.weightKg - topWeight) < 0.001 }
            let topReps = topSet?.reps ?? 0
            let last = sets.map(\.date).max() ?? now
            let isCompound = isCompoundName(display)

            // Use the full log history (not just last 14d) for suggestion math.
            let history = logs.filter { $0.exerciseName.lowercased() == display.lowercased() }
            let reps = topReps > 0 ? "\(max(1, topReps - 1))-\(topReps + 1)" : "8-10"
            let s = ProgressiveOverload.suggest(
                exerciseName: display,
                repsTarget: reps,
                isCompound: isCompound,
                history: history
            )
            stats.append(ExerciseStat(
                name: display,
                sessions: Set(sets.map { cal.startOfDay(for: $0.date) }).count,
                topWeightKg: topWeight,
                topReps: topReps,
                lastDate: last,
                suggestionDirection: s.direction.rawValue,
                suggestionWeightKg: s.weightKg,
                suggestionReason: s.reason,
                isCompound: isCompound
            ))

            // PR detection: top weight in last 14d strictly higher than any
            // earlier session of the same lift.
            let earlier = history.filter { $0.date < cutoff14 }
            let earlierMax = earlier.map(\.weightKg).max() ?? 0
            if topWeight > earlierMax + 0.01, topWeight > 0 {
                prs.append("\(display) \(formatKg(topWeight))×\(topReps)")
            }
            // Stall detection: 3+ recent sessions with non-increasing top weight.
            if s.direction == .hold {
                let sessionMaxes = sessionsTopWeights(history)
                if sessionMaxes.count >= 3,
                   sessionMaxes.prefix(3).allSatisfy({ abs($0 - topWeight) < 0.01 }) {
                    stalled.append(display)
                }
            }
        }

        return Summary(
            totalSets14d: recent.count,
            totalSessions14d: sessionDays.count,
            lastSessionDate: lastDate,
            daysSinceLastSession: daysSince,
            topExercises: stats,
            recentPRs: Array(prs.prefix(3)),
            stalledExercises: Array(stalled.prefix(3)),
            weeklyVolumeKg: weeklyVolume
        )
    }

    // MARK: - Helpers

    private static let compoundKeywords: [String] = [
        "squat", "deadlift", "bench", "press", "row", "pull-up", "pullup", "chin-up",
        "chinup", "clean", "snatch", "lunge", "hip thrust", "rdl", "front squat",
        "overhead", "dip"
    ]

    private static func isCompoundName(_ name: String) -> Bool {
        let lower = name.lowercased()
        return compoundKeywords.contains(where: { lower.contains($0) })
    }

    private static func sessionsTopWeights(_ history: [SetLog]) -> [Double] {
        let cal = Calendar.current
        var byDay: [Date: Double] = [:]
        for l in history where l.completed {
            let d = cal.startOfDay(for: l.date)
            byDay[d] = max(byDay[d] ?? 0, l.weightKg)
        }
        return byDay.sorted { $0.key > $1.key }.map(\.value)
    }

    private static func formatKg(_ x: Double) -> String {
        if x == x.rounded() { return "\(Int(x))kg" }
        return String(format: "%.1fkg", x)
    }
}
