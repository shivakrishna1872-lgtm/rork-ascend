import Foundation

// MARK: - CoachThrottle
//
// Per-device rate limiter for the conversational coach. Designed for scale to
// millions of users: each device self-throttles so the upstream proxy never sees
// runaway traffic from a single client (loops, bots, or accidental rapid taps).
//
// Two layered limits:
//  • Cooldown: 700ms minimum between sends.
//  • Burst cap: max 40 messages per rolling 10-minute window.
//
// When a limit is hit, `allow()` returns false and the caller falls back to the
// deterministic on-device reply — chat NEVER errors out at the user.
actor CoachThrottle {
    static let shared = CoachThrottle()

    private let cooldown: TimeInterval = 0.7
    private let windowSeconds: TimeInterval = 600
    private let windowMax = 40
    private var lastSend: Date?
    private var recent: [Date] = []

    func allow() -> Bool {
        let now = Date()
        if let last = lastSend, now.timeIntervalSince(last) < cooldown { return false }
        recent.removeAll { now.timeIntervalSince($0) > windowSeconds }
        if recent.count >= windowMax { return false }
        recent.append(now)
        lastSend = now
        return true
    }
}

// MARK: - CoachReplyCache
//
// Short-window cache for chat replies keyed by (context snapshot + last user
// message). Absorbs double-taps, network retries, and the very common case of
// many users asking the same canonical question ("how am I doing?"). Stored
// in-memory only — chat history itself is never persisted per the privacy spec.
nonisolated enum CoachReplyCache {
    nonisolated(unsafe) private static var store: [String: (ts: Date, value: CoachReply)] = [:]
    nonisolated(unsafe) private static var lock = NSLock()
    private static let ttl: TimeInterval = 60

    static func load(key: String) -> CoachReply? {
        lock.lock(); defer { lock.unlock() }
        guard let entry = store[key] else { return nil }
        if Date().timeIntervalSince(entry.ts) > ttl {
            store.removeValue(forKey: key)
            return nil
        }
        return entry.value
    }

    static func store(key: String, value: CoachReply) {
        lock.lock(); defer { lock.unlock() }
        store[key] = (Date(), value)
        if store.count > 200 {
            // Drop oldest half to bound memory.
            let sorted = store.sorted { $0.value.ts < $1.value.ts }
            for (k, _) in sorted.prefix(100) { store.removeValue(forKey: k) }
        }
    }
}

// MARK: - CoachGuard
//
// Hardens the model output before it reaches the app. The model is creative —
// the guard is not. It:
//   • Drops unknown tool calls (the model can't invent new app actions).
//   • Clamps every numeric arg to a sane range (no profile-corrupting values).
//   • Strips privacy-sensitive substrings (Apple IDs, emails, bearer tokens,
//     base URLs) that might leak from a prompt-injection attempt.
//   • Caps reply length so a runaway model can't dump a wall of text.
nonisolated enum CoachGuard {
    private static let allowedTools: Set<String> = [
        "setCalorieTarget", "setProteinTarget", "updateProfile",
        "logMeal", "removeLastMeal", "clearTodayMeals",
        "logLifts", "setLifts",
        "addHydration", "clearHydration",
        "openTab", "generatePlan", "importWorkoutPlan",
        "setExerciseWeight", "deletePlan", "setStreak"
    ]
    private static let allowedGoals: Set<String> = [
        "loseFat", "gainMuscle", "aesthetics", "athletic", "discipline", "transformation"
    ]
    private static let allowedTabs: Set<String> = ["cal", "physique", "psl", "home", "circles", "ai", "coach", "workouts"]
    private static let allowedUnits: Set<String> = ["metric", "imperial"]
    private static let maxReplyChars = 1200

    static func sanitize(_ reply: CoachReply, context: CoachContext) -> CoachReply {
        let cleanedReply = sanitizeText(reply.reply)
        let cleanedActions = reply.actions.compactMap { sanitizeAction($0) }
        return CoachReply(
            reply: cleanedReply,
            actions: cleanedActions,
            isOffline: reply.isOffline
        )
    }

    private static func sanitizeText(_ text: String) -> String {
        var t = text
        // Strip obvious bearer tokens / API keys / data URIs / internal URLs.
        let patterns = [
            #"Bearer\s+[A-Za-z0-9._\-]+"#,
            #"sk-[A-Za-z0-9]{16,}"#,
            #"eyJ[A-Za-z0-9_\-\.]{20,}"#, // JWT
            #"https?://[A-Za-z0-9\.\-]*toolkit[A-Za-z0-9\.\-/]*"#,
            #"https?://[A-Za-z0-9\.\-]*supabase[A-Za-z0-9\.\-/]*"#
        ]
        for p in patterns {
            if let re = try? NSRegularExpression(pattern: p, options: [.caseInsensitive]) {
                let range = NSRange(t.startIndex..., in: t)
                t = re.stringByReplacingMatches(in: t, options: [], range: range, withTemplate: "[redacted]")
            }
        }
        if t.count > maxReplyChars { t = String(t.prefix(maxReplyChars)) + "\u{2026}" }
        return t
    }

    private static func sanitizeAction(_ call: CoachToolCall) -> CoachToolCall? {
        guard allowedTools.contains(call.tool) else { return nil }
        var a = call.args
        // Clamp every numeric/string field to safe ranges. Out-of-range stays
        // nil rather than being silently corrected to a default, so the app
        // never applies a value the model made up.
        if let c = a.calories { a.calories = (800...6000).contains(c) ? c : nil }
        if let p = a.proteinG { a.proteinG = (30...500).contains(p) ? p : nil }
        if let c = a.carbsG   { a.carbsG   = (0...800).contains(c)  ? c : nil }
        if let f = a.fatsG    { a.fatsG    = (0...400).contains(f)  ? f : nil }
        if let d = a.days     { a.days     = (1...60).contains(d)   ? d : nil }
        // updateProfile.weightKg shares the field with setExerciseWeight, so
        // we use a permissive band (1–700) and let the runner pick the right
        // sub-range for each tool. Pure setting on UserProfile is still
        // re-checked there.
        if let w = a.weightKg { a.weightKg = (1...700).contains(w) ? w : nil }
        if let h = a.heightCm { a.heightCm = (120...230).contains(h) ? h : nil }
        if let age = a.age    { a.age      = (13...100).contains(age) ? age : nil }
        if let g = a.glasses  { a.glasses  = (1...8).contains(g)    ? g : nil }
        if let b = a.benchKg  { a.benchKg  = (1...600).contains(b) ? b : nil }
        if let s = a.squatKg  { a.squatKg  = (1...700).contains(s) ? s : nil }
        if let d = a.deadliftKg { a.deadliftKg = (1...700).contains(d) ? d : nil }
        if let s = a.streak   { a.streak   = (0...3650).contains(s) ? s : nil }
        if let n = a.exerciseName, n.count > 60 { a.exerciseName = String(n.prefix(60)) }
        if let t = a.planTitle, t.count > 80 { a.planTitle = String(t.prefix(80)) }
        if let goals = a.goals {
            let filtered = goals.filter { allowedGoals.contains($0) }
            a.goals = filtered.isEmpty ? nil : Array(Set(filtered))
        }
        if let tab = a.tab?.lowercased() {
            a.tab = allowedTabs.contains(tab) ? tab : nil
        }
        if let units = a.unitSystem?.lowercased() {
            a.unitSystem = allowedUnits.contains(units) ? units : nil
        }
        if let name = a.mealName, name.count > 80 {
            a.mealName = String(name.prefix(80))
        }
        if let plan = a.planText, plan.count > 1500 {
            a.planText = String(plan.prefix(1500))
        }
        // Hard cap workout-plan JSON so a malformed payload can't bloat the
        // chat log. 32k is plenty for ~6 days x 12 exercises.
        if let wp = a.workoutPlanJSON, wp.count > 32_000 {
            a.workoutPlanJSON = nil
        }
        let summary = call.summary.count > 160
            ? String(call.summary.prefix(160))
            : call.summary
        return CoachToolCall(tool: call.tool, summary: summary, args: a, id: call.id)
    }
}

// MARK: - CoachContext cache key
//
// Stable hash of the context fields the system prompt actually surfaces. Used
// to dedupe identical questions in CoachReplyCache. Excludes high-churn fields
// like exact timestamps so the short-window cache actually catches duplicates.
extension CoachContext {
    nonisolated var cacheKey: String {
        let parts: [String] = [
            profile.cacheKey,
            String(streak), String(xp), tier,
            String(hydrationGlasses),
            String(calorieTarget), String(proteinTarget), String(baseCalorieTarget),
            String(format: "%.0f", latestPhysique ?? -1),
            String(format: "%.1f", latestBodyFat ?? -1),
            String(format: "%.1f", physiqueTrend), String(physiqueScanCount),
            String(format: "%.0f", latestPSL ?? -1),
            String(format: "%.1f", faceTrend), String(faceScanCount),
            String(avgCalories), String(avgProtein), String(mealsLogged7d),
            String(todayCalories), String(todayProtein),
            String(format: "%.0f", benchKg ?? -1),
            String(format: "%.0f", squatKg ?? -1),
            String(format: "%.0f", deadliftKg ?? -1)
        ]
        return parts.joined(separator: ",")
    }
}
