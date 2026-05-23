import Foundation

/// Deterministic progressive-overload suggester. Pure function of past `SetLog`
/// history — same input history → identical suggestion every time. No AI.
///
/// Rule (industry-standard "double progression"):
/// 1. If the user hit the TOP of the rep range on every working set last
///    session → add load (+2.5kg compound, +1kg isolation).
/// 2. If they hit the bottom-to-middle of the range → repeat same load.
/// 3. If they missed the bottom of the range twice in a row → deload 5–10%.
nonisolated enum ProgressiveOverload {

    struct Suggestion: Sendable, Equatable {
        let weightKg: Double
        let reps: String
        let direction: Direction
        let reason: String
        enum Direction: String, Sendable { case up, hold, down, fresh }
    }

    /// Compute a suggestion for the next session of `exerciseName`.
    /// `history` is the full `SetLog` table; we filter + sort internally.
    /// `repsTarget` is the plan's prescribed range (e.g. "8" or "8-10").
    /// `isCompound` controls the increment size.
    static func suggest(
        exerciseName: String,
        repsTarget: String,
        isCompound: Bool,
        history: [SetLog]
    ) -> Suggestion {
        let canonical = exerciseName.lowercased().trimmingCharacters(in: .whitespaces)
        let logs = history
            .filter { $0.exerciseName.lowercased() == canonical && $0.completed && $0.weightKg > 0 }
            .sorted { $0.date > $1.date }

        let (lo, hi) = parseRepRange(repsTarget)
        let increment: Double = isCompound ? 2.5 : 1.0

        // Group into sessions by calendar day.
        let cal = Calendar.current
        var sessions: [[SetLog]] = []
        var current: [SetLog] = []
        var currentDay: Date?
        for log in logs {
            let day = cal.startOfDay(for: log.date)
            if currentDay == nil || day == currentDay {
                current.append(log)
                currentDay = day
            } else {
                sessions.append(current)
                current = [log]
                currentDay = day
            }
        }
        if !current.isEmpty { sessions.append(current) }

        guard let last = sessions.first, !last.isEmpty else {
            return Suggestion(weightKg: 0, reps: repsTarget, direction: .fresh,
                              reason: "Log your first set — we'll start tracking from here.")
        }

        // Use the heaviest weight worked last session as the baseline.
        let baseline = last.map(\.weightKg).max() ?? 0
        let topSets = last.filter { abs($0.weightKg - baseline) < 0.001 }
        let avgReps = Double(topSets.map(\.reps).reduce(0, +)) / Double(max(1, topSets.count))

        // Two-strike deload check.
        let prev = sessions.dropFirst().first
        let prevBase = prev?.map(\.weightKg).max() ?? 0
        let prevTop = prev?.filter { abs($0.weightKg - prevBase) < 0.001 } ?? []
        let prevAvgReps = prevTop.isEmpty ? Double(hi)
            : Double(prevTop.map(\.reps).reduce(0, +)) / Double(prevTop.count)

        if avgReps >= Double(hi) && topSets.allSatisfy({ $0.reps >= hi }) {
            return Suggestion(
                weightKg: round1(baseline + increment),
                reps: repsTarget,
                direction: .up,
                reason: "Hit top of range on every set — add \(formatKg(increment))."
            )
        }
        if avgReps < Double(lo) && prevAvgReps < Double(lo) {
            let deload = max(0, round1(baseline * 0.92))
            return Suggestion(
                weightKg: deload,
                reps: repsTarget,
                direction: .down,
                reason: "Missed bottom of range twice — small deload to rebuild."
            )
        }
        return Suggestion(
            weightKg: round1(baseline),
            reps: repsTarget,
            direction: .hold,
            reason: "Hold weight — push for more reps this session."
        )
    }

    // MARK: - Helpers

    /// Parses "8", "8-10", "8–10", "8 to 10", etc. Returns (low, high).
    static func parseRepRange(_ s: String) -> (Int, Int) {
        let cleaned = s.replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: " to ", with: "-")
            .replacingOccurrences(of: "s", with: "") // strip "45s" → "45"
        let parts = cleaned.split(separator: "-").map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.count == 2, let a = Int(parts[0]), let b = Int(parts[1]) {
            return (min(a, b), max(a, b))
        }
        if let n = Int(parts.first ?? "") { return (n, n) }
        return (8, 10)
    }

    private static func round1(_ x: Double) -> Double { (x * 10).rounded() / 10 }

    private static func formatKg(_ x: Double) -> String {
        if x == x.rounded() { return "\(Int(x))kg" }
        return String(format: "%.1fkg", x)
    }
}
