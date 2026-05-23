import Foundation

/// Deterministic exercise database via the free public Wger API.
///
/// No key required, results cached aggressively in UserDefaults so most
/// lookups are zero-network. This is the rule-based workout layer that
/// powers plan generation without any AI involvement.
actor WgerService {
    static let shared = WgerService()

    nonisolated struct Exercise: Codable, Sendable, Identifiable {
        let id: Int
        let name: String
        let description: String
        let muscles: [Int]
        let category: Int
        let equipment: [Int]
    }

    private let base = "https://wger.de/api/v2"
    private var memCache: [String: [Exercise]] = [:]
    private let cachePrefix = "wger.cache.v1."
    private let ttl: TimeInterval = 60 * 60 * 24 * 7   // 7 days

    /// Search exercises by free-text term.
    func search(_ term: String, limit: Int = 20) async -> [Exercise] {
        let key = "search:\(term.lowercased()):\(limit)"
        if let cached = readCache(key) { return cached }
        guard let q = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(base)/exercise/?language=2&status=2&limit=\(limit)&name=\(q)") else { return [] }
        let results = (try? await fetch(url: url)) ?? []
        writeCache(key, results)
        return results
    }

    /// Exercises that target a specific muscle ID.
    func byMuscle(_ muscleId: Int, limit: Int = 20) async -> [Exercise] {
        let key = "muscle:\(muscleId):\(limit)"
        if let cached = readCache(key) { return cached }
        guard let url = URL(string: "\(base)/exercise/?language=2&status=2&muscles=\(muscleId)&limit=\(limit)") else { return [] }
        let results = (try? await fetch(url: url)) ?? []
        writeCache(key, results)
        return results
    }

    // MARK: - Network

    private func fetch(url: URL) async throws -> [Exercise] {
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        req.setValue("Ascend-iOS/1.0", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else { return [] }
        return results.compactMap { item -> Exercise? in
            guard let id = item["id"] as? Int,
                  let name = item["name"] as? String, !name.isEmpty else { return nil }
            return Exercise(
                id: id,
                name: name,
                description: (item["description"] as? String) ?? "",
                muscles: (item["muscles"] as? [Int]) ?? [],
                category: (item["category"] as? Int) ?? 0,
                equipment: (item["equipment"] as? [Int]) ?? []
            )
        }
    }

    // MARK: - Cache

    private func readCache(_ key: String) -> [Exercise]? {
        if let m = memCache[key] { return m }
        let ud = UserDefaults.standard
        guard let data = ud.data(forKey: cachePrefix + key),
              let env = try? JSONDecoder().decode(CacheEnvelope.self, from: data),
              Date().timeIntervalSince1970 - env.savedAt < ttl else { return nil }
        memCache[key] = env.items
        return env.items
    }

    private func writeCache(_ key: String, _ items: [Exercise]) {
        memCache[key] = items
        let env = CacheEnvelope(savedAt: Date().timeIntervalSince1970, items: items)
        if let data = try? JSONEncoder().encode(env) {
            UserDefaults.standard.set(data, forKey: cachePrefix + key)
        }
    }

    private struct CacheEnvelope: Codable {
        let savedAt: TimeInterval
        let items: [Exercise]
    }
}

// MARK: - Rule-based plan generation
//
// Deterministic weekly split — no AI involved. Used as the second-option
// safety net when the cloud coach is unavailable.
nonisolated enum WgerPlanner {
    nonisolated struct DayPlan: Codable, Sendable {
        let day: String
        let focus: String
        let exerciseQueries: [String]
    }

    /// Standard rule-based 4-day upper/lower split. Caller can hydrate exercises
    /// for each query via `WgerService.search`.
    static func weeklySplit() -> [DayPlan] {
        [
            DayPlan(day: "Monday",    focus: "Upper Push", exerciseQueries: ["bench press", "overhead press", "incline dumbbell", "tricep pushdown"]),
            DayPlan(day: "Tuesday",   focus: "Lower",      exerciseQueries: ["back squat", "romanian deadlift", "leg press", "calf raise"]),
            DayPlan(day: "Wednesday", focus: "Rest",       exerciseQueries: []),
            DayPlan(day: "Thursday",  focus: "Upper Pull", exerciseQueries: ["pull up", "barbell row", "lat pulldown", "barbell curl"]),
            DayPlan(day: "Friday",    focus: "Lower",      exerciseQueries: ["deadlift", "front squat", "hip thrust", "leg curl"]),
            DayPlan(day: "Saturday",  focus: "Conditioning", exerciseQueries: ["kettlebell swing", "burpee", "rowing"]),
            DayPlan(day: "Sunday",    focus: "Rest",       exerciseQueries: [])
        ]
    }
}
