import Foundation

/// Continuous-learning store.
///
/// When a user corrects something the AI returned (e.g. "this meal was
/// actually 720 cal, not 540", or "my body fat is 14% not 18%"), we
/// persist the delta locally and feed it back into the next prompt as
/// PERSONAL CALIBRATION DATA so the model self-trains to this user.
///
/// No network. No credits. No external annotation pipeline needed today —
/// but the schema is intentionally future-compatible with an upload step
/// once we add a labeled-dataset endpoint.
nonisolated struct UserCorrection: Codable, Hashable {
    let id: UUID
    let category: String        // "physique" | "psl" | "meal"
    let field: String           // e.g. "bodyFatPercent", "calories"
    let aiValue: Double
    let userValue: Double
    let timestamp: Date
}

nonisolated enum UserCorrectionStore {
    private static let key = "ai.corrections.v1"
    private static let maxStored = 200

    static func record(category: String, field: String, aiValue: Double, userValue: Double) {
        var all = load()
        all.append(UserCorrection(
            id: UUID(), category: category, field: field,
            aiValue: aiValue, userValue: userValue, timestamp: Date()
        ))
        if all.count > maxStored { all = Array(all.suffix(maxStored)) }
        save(all)
    }

    static func load() -> [UserCorrection] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let arr = try? JSONDecoder().decode([UserCorrection].self, from: data) else { return [] }
        return arr
    }

    private static func save(_ arr: [UserCorrection]) {
        guard let data = try? JSONEncoder().encode(arr) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    /// Compact summary for an AI prompt. Returns the average delta per
    /// (category, field) so the model can systematically adjust.
    ///
    /// Example output:
    ///   "calibration: physique.bodyFatPercent → user runs 2.8 lower than AI;
    ///    meal.calories → user runs 9% higher than AI (n=14)"
    static func calibrationSummary(category: String) -> String? {
        let mine = load().filter { $0.category == category }
        guard !mine.isEmpty else { return nil }
        let byField = Dictionary(grouping: mine, by: \.field)
        var lines: [String] = []
        for (field, entries) in byField {
            let deltas = entries.map { $0.userValue - $0.aiValue }
            let avg = deltas.reduce(0, +) / Double(deltas.count)
            let mag = abs(avg) < 0.01 ? "no consistent bias" :
                      String(format: "%@%.2f", avg > 0 ? "+" : "", avg)
            lines.append("- \(field): user delta \(mag) (n=\(entries.count))")
        }
        return "USER CORRECTIONS (continuous learning — adjust toward these biases):\n" + lines.joined(separator: "\n")
    }
}
