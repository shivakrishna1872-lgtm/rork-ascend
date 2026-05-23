import Foundation
import CryptoKit

/// Internal exercise library + deterministic rule-based workout plan generator.
///
/// No AI is involved. Same `WorkoutPreferences` + same `UserProfile` snapshot
/// produces a byte-identical plan every time (verified via `inputHash`).
nonisolated enum WorkoutPlanGenerator {

    // MARK: - Exercise library

    nonisolated struct LibraryExercise: Hashable, Sendable {
        let name: String
        let muscle: Muscle
        let pattern: Pattern
        let equipment: Set<EquipmentLevel>
        let difficulty: FitnessLevel
        let isCompound: Bool
        /// Joints this movement loads heavily — used to skip on injury.
        let stresses: Set<Joint>
    }

    enum Muscle: String, Sendable {
        case chest, back, shoulders, biceps, triceps, quads, hamstrings, glutes, calves, core, fullBody, conditioning
    }
    enum Pattern: String, Sendable {
        case horizontalPush, verticalPush, horizontalPull, verticalPull
        case squat, hinge, lunge, carry
        case isolation, core, conditioning
    }
    enum Joint: String, Sendable {
        case shoulder, elbow, wrist, lowerBack, knee, hip, ankle
    }

    static let library: [LibraryExercise] = [
        // Horizontal push
        .init(name: "Barbell Bench Press",      muscle: .chest, pattern: .horizontalPush, equipment: [.gym], difficulty: .intermediate, isCompound: true, stresses: [.shoulder, .elbow, .wrist]),
        .init(name: "Dumbbell Bench Press",     muscle: .chest, pattern: .horizontalPush, equipment: [.gym, .home, .dumbbells], difficulty: .beginner, isCompound: true, stresses: [.shoulder, .elbow]),
        .init(name: "Incline Dumbbell Press",   muscle: .chest, pattern: .horizontalPush, equipment: [.gym, .home, .dumbbells], difficulty: .intermediate, isCompound: true, stresses: [.shoulder, .elbow]),
        .init(name: "Push-Up",                  muscle: .chest, pattern: .horizontalPush, equipment: [.gym, .home, .dumbbells, .none], difficulty: .beginner, isCompound: true, stresses: [.shoulder, .wrist]),
        .init(name: "Dips",                     muscle: .chest, pattern: .horizontalPush, equipment: [.gym, .home], difficulty: .intermediate, isCompound: true, stresses: [.shoulder, .elbow]),
        .init(name: "Cable Chest Fly",          muscle: .chest, pattern: .isolation, equipment: [.gym], difficulty: .beginner, isCompound: false, stresses: [.shoulder]),

        // Vertical push
        .init(name: "Overhead Press",           muscle: .shoulders, pattern: .verticalPush, equipment: [.gym], difficulty: .intermediate, isCompound: true, stresses: [.shoulder, .lowerBack]),
        .init(name: "Seated Dumbbell Press",    muscle: .shoulders, pattern: .verticalPush, equipment: [.gym, .home, .dumbbells], difficulty: .beginner, isCompound: true, stresses: [.shoulder]),
        .init(name: "Lateral Raise",            muscle: .shoulders, pattern: .isolation, equipment: [.gym, .home, .dumbbells], difficulty: .beginner, isCompound: false, stresses: [.shoulder]),
        .init(name: "Pike Push-Up",             muscle: .shoulders, pattern: .verticalPush, equipment: [.none, .home], difficulty: .intermediate, isCompound: true, stresses: [.shoulder, .wrist]),

        // Horizontal pull
        .init(name: "Barbell Row",              muscle: .back, pattern: .horizontalPull, equipment: [.gym], difficulty: .intermediate, isCompound: true, stresses: [.lowerBack, .elbow]),
        .init(name: "Dumbbell Row",             muscle: .back, pattern: .horizontalPull, equipment: [.gym, .home, .dumbbells], difficulty: .beginner, isCompound: true, stresses: [.elbow]),
        .init(name: "Seated Cable Row",         muscle: .back, pattern: .horizontalPull, equipment: [.gym], difficulty: .beginner, isCompound: true, stresses: [.elbow]),
        .init(name: "Inverted Row",             muscle: .back, pattern: .horizontalPull, equipment: [.gym, .home, .none], difficulty: .beginner, isCompound: true, stresses: [.elbow]),
        .init(name: "Face Pull",                muscle: .back, pattern: .isolation, equipment: [.gym], difficulty: .beginner, isCompound: false, stresses: [.shoulder]),

        // Vertical pull
        .init(name: "Pull-Up",                  muscle: .back, pattern: .verticalPull, equipment: [.gym, .home, .none], difficulty: .intermediate, isCompound: true, stresses: [.shoulder, .elbow]),
        .init(name: "Lat Pulldown",             muscle: .back, pattern: .verticalPull, equipment: [.gym], difficulty: .beginner, isCompound: true, stresses: [.shoulder, .elbow]),
        .init(name: "Chin-Up",                  muscle: .back, pattern: .verticalPull, equipment: [.gym, .home, .none], difficulty: .intermediate, isCompound: true, stresses: [.shoulder, .elbow]),

        // Squat pattern
        .init(name: "Back Squat",               muscle: .quads, pattern: .squat, equipment: [.gym], difficulty: .intermediate, isCompound: true, stresses: [.knee, .lowerBack, .hip]),
        .init(name: "Front Squat",              muscle: .quads, pattern: .squat, equipment: [.gym], difficulty: .advanced, isCompound: true, stresses: [.knee, .lowerBack]),
        .init(name: "Goblet Squat",             muscle: .quads, pattern: .squat, equipment: [.gym, .home, .dumbbells], difficulty: .beginner, isCompound: true, stresses: [.knee, .hip]),
        .init(name: "Bulgarian Split Squat",    muscle: .quads, pattern: .lunge, equipment: [.gym, .home, .dumbbells, .none], difficulty: .intermediate, isCompound: true, stresses: [.knee, .hip]),
        .init(name: "Leg Press",                muscle: .quads, pattern: .squat, equipment: [.gym], difficulty: .beginner, isCompound: true, stresses: [.knee]),
        .init(name: "Bodyweight Squat",         muscle: .quads, pattern: .squat, equipment: [.none, .home], difficulty: .beginner, isCompound: true, stresses: [.knee]),

        // Hinge
        .init(name: "Deadlift",                 muscle: .hamstrings, pattern: .hinge, equipment: [.gym], difficulty: .advanced, isCompound: true, stresses: [.lowerBack, .hip]),
        .init(name: "Romanian Deadlift",        muscle: .hamstrings, pattern: .hinge, equipment: [.gym, .dumbbells], difficulty: .intermediate, isCompound: true, stresses: [.lowerBack, .hip]),
        .init(name: "Hip Thrust",               muscle: .glutes, pattern: .hinge, equipment: [.gym, .dumbbells], difficulty: .beginner, isCompound: true, stresses: [.hip]),
        .init(name: "Glute Bridge",             muscle: .glutes, pattern: .hinge, equipment: [.none, .home], difficulty: .beginner, isCompound: true, stresses: [.hip]),
        .init(name: "Leg Curl",                 muscle: .hamstrings, pattern: .isolation, equipment: [.gym], difficulty: .beginner, isCompound: false, stresses: [.knee]),

        // Lunge
        .init(name: "Walking Lunge",            muscle: .quads, pattern: .lunge, equipment: [.gym, .home, .dumbbells, .none], difficulty: .beginner, isCompound: true, stresses: [.knee, .hip]),
        .init(name: "Reverse Lunge",            muscle: .quads, pattern: .lunge, equipment: [.gym, .home, .dumbbells, .none], difficulty: .beginner, isCompound: true, stresses: [.knee, .hip]),

        // Arms
        .init(name: "Barbell Curl",             muscle: .biceps, pattern: .isolation, equipment: [.gym], difficulty: .beginner, isCompound: false, stresses: [.elbow, .wrist]),
        .init(name: "Dumbbell Curl",            muscle: .biceps, pattern: .isolation, equipment: [.gym, .home, .dumbbells], difficulty: .beginner, isCompound: false, stresses: [.elbow]),
        .init(name: "Hammer Curl",              muscle: .biceps, pattern: .isolation, equipment: [.gym, .home, .dumbbells], difficulty: .beginner, isCompound: false, stresses: [.elbow]),
        .init(name: "Triceps Pushdown",         muscle: .triceps, pattern: .isolation, equipment: [.gym], difficulty: .beginner, isCompound: false, stresses: [.elbow]),
        .init(name: "Overhead Triceps Extension", muscle: .triceps, pattern: .isolation, equipment: [.gym, .home, .dumbbells], difficulty: .beginner, isCompound: false, stresses: [.elbow]),
        .init(name: "Close-Grip Push-Up",       muscle: .triceps, pattern: .horizontalPush, equipment: [.none, .home], difficulty: .beginner, isCompound: true, stresses: [.elbow, .wrist]),

        // Calves
        .init(name: "Standing Calf Raise",      muscle: .calves, pattern: .isolation, equipment: [.gym, .home, .dumbbells, .none], difficulty: .beginner, isCompound: false, stresses: [.ankle]),

        // Core
        .init(name: "Hanging Leg Raise",        muscle: .core, pattern: .core, equipment: [.gym, .home], difficulty: .intermediate, isCompound: false, stresses: [.shoulder]),
        .init(name: "Plank",                    muscle: .core, pattern: .core, equipment: [.none, .home, .gym, .dumbbells], difficulty: .beginner, isCompound: false, stresses: []),
        .init(name: "Cable Crunch",             muscle: .core, pattern: .core, equipment: [.gym], difficulty: .beginner, isCompound: false, stresses: []),

        // Conditioning
        .init(name: "Kettlebell Swing",         muscle: .conditioning, pattern: .conditioning, equipment: [.gym, .home], difficulty: .intermediate, isCompound: true, stresses: [.lowerBack, .hip]),
        .init(name: "Burpee",                   muscle: .conditioning, pattern: .conditioning, equipment: [.none, .home, .gym], difficulty: .intermediate, isCompound: true, stresses: [.wrist, .knee]),
        .init(name: "Mountain Climber",         muscle: .conditioning, pattern: .conditioning, equipment: [.none, .home, .gym], difficulty: .beginner, isCompound: true, stresses: [.wrist]),
        .init(name: "Rowing Machine",           muscle: .conditioning, pattern: .conditioning, equipment: [.gym], difficulty: .beginner, isCompound: true, stresses: []),
        .init(name: "Jump Rope",                muscle: .conditioning, pattern: .conditioning, equipment: [.none, .home, .gym], difficulty: .beginner, isCompound: true, stresses: [.ankle, .knee])
    ]

    // MARK: - Day templates

    private struct DayTemplate {
        let title: String
        let focus: String
        let slots: [Slot]
    }
    private struct Slot {
        let pattern: Pattern
        let muscle: Muscle?
        let role: Role
    }
    private enum Role {
        case primaryCompound
        case secondaryCompound
        case accessory
        case isolation
        case core
        case conditioning
    }

    // MARK: - Public API

    /// Deterministically build a plan from user profile + preferences.
    static func generate(profile: UserProfile, prefs: WorkoutPreferences) -> GeneratedPlan {
        let prefs = sanitize(prefs)
        let templates = templates(for: prefs.daysPerWeek)
        let injuries = parseInjuries(prefs.injuries)

        var dayPlans: [DayPlan] = []
        for (idx, tpl) in templates.enumerated() {
            var exercises: [ExercisePick] = []
            // Use a deterministic per-slot picker (stable index into filtered list).
            for (slotIdx, slot) in tpl.slots.enumerated() {
                guard let pick = chooseExercise(
                    pattern: slot.pattern,
                    muscle: slot.muscle,
                    role: slot.role,
                    prefs: prefs,
                    injuries: injuries,
                    dayIndex: idx,
                    slotIndex: slotIdx,
                    profileSeed: profileSeed(profile)
                ) else { continue }
                let (sets, reps, rest) = setRepRest(role: slot.role, exercise: pick, goal: prefs.goal, level: prefs.level)
                exercises.append(ExercisePick(
                    exercise: pick,
                    sets: sets,
                    reps: reps,
                    restSeconds: rest,
                    notes: noteFor(role: slot.role, pick: pick, goal: prefs.goal)
                ))
            }
            dayPlans.append(DayPlan(title: tpl.title, focus: tpl.focus, exercises: exercises))
        }

        let title = generatedTitle(prefs: prefs)
        let hash = inputHash(profile: profile, prefs: prefs)
        return GeneratedPlan(title: title, goal: prefs.goal, days: dayPlans, inputHash: hash, preferences: prefs)
    }

    // MARK: - Output structs

    nonisolated struct GeneratedPlan: Sendable {
        let title: String
        let goal: WorkoutGoal
        let days: [DayPlan]
        let inputHash: String
        let preferences: WorkoutPreferences
    }
    nonisolated struct DayPlan: Sendable {
        let title: String
        let focus: String
        let exercises: [ExercisePick]
    }
    nonisolated struct ExercisePick: Sendable {
        let exercise: LibraryExercise
        let sets: Int
        let reps: String
        let restSeconds: Int
        let notes: String
    }

    // MARK: - Templates by frequency

    private static func templates(for days: Int) -> [DayTemplate] {
        switch max(1, min(7, days)) {
        case 1, 2:
            return [
                fullBody(title: "Day 1", focus: "Full Body A"),
                fullBody(title: "Day 2", focus: "Full Body B")
            ].prefix(days).map { $0 }
        case 3:
            return [
                fullBody(title: "Day 1", focus: "Full Body A"),
                fullBody(title: "Day 2", focus: "Full Body B"),
                fullBody(title: "Day 3", focus: "Full Body C")
            ]
        case 4:
            return [
                upperBody(title: "Day 1", focus: "Upper Body"),
                lowerBody(title: "Day 2", focus: "Lower Body"),
                upperBody(title: "Day 3", focus: "Upper Body"),
                lowerBody(title: "Day 4", focus: "Lower Body")
            ]
        case 5:
            return [
                push(title: "Day 1", focus: "Push"),
                pull(title: "Day 2", focus: "Pull"),
                legs(title: "Day 3", focus: "Legs"),
                upperBody(title: "Day 4", focus: "Upper Body"),
                lowerBody(title: "Day 5", focus: "Lower Body")
            ]
        default: // 6+
            return [
                push(title: "Day 1", focus: "Push"),
                pull(title: "Day 2", focus: "Pull"),
                legs(title: "Day 3", focus: "Legs"),
                push(title: "Day 4", focus: "Push"),
                pull(title: "Day 5", focus: "Pull"),
                legs(title: "Day 6", focus: "Legs")
            ].prefix(days).map { $0 }
        }
    }

    private static func fullBody(title: String, focus: String) -> DayTemplate {
        DayTemplate(title: title, focus: focus, slots: [
            Slot(pattern: .squat, muscle: nil, role: .primaryCompound),
            Slot(pattern: .horizontalPush, muscle: .chest, role: .primaryCompound),
            Slot(pattern: .horizontalPull, muscle: .back, role: .primaryCompound),
            Slot(pattern: .hinge, muscle: nil, role: .secondaryCompound),
            Slot(pattern: .verticalPush, muscle: .shoulders, role: .accessory),
            Slot(pattern: .core, muscle: .core, role: .core)
        ])
    }
    private static func upperBody(title: String, focus: String) -> DayTemplate {
        DayTemplate(title: title, focus: focus, slots: [
            Slot(pattern: .horizontalPush, muscle: .chest, role: .primaryCompound),
            Slot(pattern: .horizontalPull, muscle: .back, role: .primaryCompound),
            Slot(pattern: .verticalPush, muscle: .shoulders, role: .secondaryCompound),
            Slot(pattern: .verticalPull, muscle: .back, role: .secondaryCompound),
            Slot(pattern: .isolation, muscle: .biceps, role: .isolation),
            Slot(pattern: .isolation, muscle: .triceps, role: .isolation)
        ])
    }
    private static func lowerBody(title: String, focus: String) -> DayTemplate {
        DayTemplate(title: title, focus: focus, slots: [
            Slot(pattern: .squat, muscle: .quads, role: .primaryCompound),
            Slot(pattern: .hinge, muscle: .hamstrings, role: .primaryCompound),
            Slot(pattern: .lunge, muscle: .quads, role: .secondaryCompound),
            Slot(pattern: .hinge, muscle: .glutes, role: .accessory),
            Slot(pattern: .isolation, muscle: .calves, role: .isolation),
            Slot(pattern: .core, muscle: .core, role: .core)
        ])
    }
    private static func push(title: String, focus: String) -> DayTemplate {
        DayTemplate(title: title, focus: focus, slots: [
            Slot(pattern: .horizontalPush, muscle: .chest, role: .primaryCompound),
            Slot(pattern: .verticalPush, muscle: .shoulders, role: .primaryCompound),
            Slot(pattern: .horizontalPush, muscle: .chest, role: .secondaryCompound),
            Slot(pattern: .isolation, muscle: .shoulders, role: .isolation),
            Slot(pattern: .isolation, muscle: .triceps, role: .isolation)
        ])
    }
    private static func pull(title: String, focus: String) -> DayTemplate {
        DayTemplate(title: title, focus: focus, slots: [
            Slot(pattern: .verticalPull, muscle: .back, role: .primaryCompound),
            Slot(pattern: .horizontalPull, muscle: .back, role: .primaryCompound),
            Slot(pattern: .horizontalPull, muscle: .back, role: .secondaryCompound),
            Slot(pattern: .isolation, muscle: .biceps, role: .isolation),
            Slot(pattern: .isolation, muscle: .back, role: .isolation)
        ])
    }
    private static func legs(title: String, focus: String) -> DayTemplate {
        DayTemplate(title: title, focus: focus, slots: [
            Slot(pattern: .squat, muscle: .quads, role: .primaryCompound),
            Slot(pattern: .hinge, muscle: .hamstrings, role: .primaryCompound),
            Slot(pattern: .lunge, muscle: .quads, role: .secondaryCompound),
            Slot(pattern: .hinge, muscle: .glutes, role: .accessory),
            Slot(pattern: .isolation, muscle: .calves, role: .isolation)
        ])
    }

    // MARK: - Selection

    private static func chooseExercise(
        pattern: Pattern,
        muscle: Muscle?,
        role: Role,
        prefs: WorkoutPreferences,
        injuries: Set<Joint>,
        dayIndex: Int,
        slotIndex: Int,
        profileSeed: UInt64
    ) -> LibraryExercise? {
        // Filter by pattern/muscle, equipment availability, injuries.
        var candidates = library.filter { ex in
            ex.equipment.contains(prefs.equipment) &&
            injuries.isDisjoint(with: ex.stresses) &&
            (pattern == .isolation || pattern == .core || pattern == .conditioning
             ? ex.pattern == pattern
             : ex.pattern == pattern) &&
            (muscle == nil || ex.muscle == muscle!)
        }
        if candidates.isEmpty {
            // Relax muscle constraint if nothing matched.
            candidates = library.filter { ex in
                ex.equipment.contains(prefs.equipment) &&
                injuries.isDisjoint(with: ex.stresses) &&
                ex.pattern == pattern
            }
        }
        guard !candidates.isEmpty else { return nil }

        // Difficulty tiering: prefer same level, drop a level if beginner.
        let preferredDifficulty: Set<FitnessLevel> = {
            switch prefs.level {
            case .beginner: return [.beginner]
            case .intermediate: return [.beginner, .intermediate]
            case .advanced: return [.intermediate, .advanced]
            }
        }()
        let tiered = candidates.filter { preferredDifficulty.contains($0.difficulty) }
        let pool = tiered.isEmpty ? candidates : tiered

        // Deterministic stable sort + pick.
        let sorted = pool.sorted { $0.name < $1.name }
        let idx = Int(((profileSeed &+ UInt64(dayIndex &* 31) &+ UInt64(slotIndex &* 7)) % UInt64(sorted.count)))
        return sorted[idx]
    }

    private static func setRepRest(role: Role, exercise: LibraryExercise, goal: WorkoutGoal, level: FitnessLevel) -> (Int, String, Int) {
        let rest: Int = {
            if exercise.pattern == .isolation { return 60 }
            if exercise.pattern == .core { return 45 }
            if exercise.pattern == .conditioning { return 60 }
            if exercise.isCompound { return 90 }
            return 75
        }()
        switch goal {
        case .strength:
            switch role {
            case .primaryCompound:   return (5, "5", max(rest, 150))
            case .secondaryCompound: return (4, "6", max(rest, 120))
            case .accessory:         return (3, "8", 90)
            case .isolation:         return (3, "10", 60)
            case .core:              return (3, "12", 45)
            case .conditioning:      return (3, "45s", 60)
            }
        case .hypertrophy:
            switch role {
            case .primaryCompound:   return (4, "8", 90)
            case .secondaryCompound: return (4, "10", 75)
            case .accessory:         return (3, "10–12", 75)
            case .isolation:         return (3, "12", 60)
            case .core:              return (3, "15", 45)
            case .conditioning:      return (3, "45s", 60)
            }
        case .fatLoss:
            switch role {
            case .primaryCompound:   return (3, "10", 60)
            case .secondaryCompound: return (3, "12", 60)
            case .accessory:         return (3, "12–15", 45)
            case .isolation:         return (3, "15", 40)
            case .core:              return (3, "20", 30)
            case .conditioning:      return (4, "40s", 45)
            }
        case .athletic:
            switch role {
            case .primaryCompound:   return (5, "3", 120)
            case .secondaryCompound: return (4, "6", 90)
            case .accessory:         return (3, "8", 75)
            case .isolation:         return (3, "10", 60)
            case .core:              return (3, "12", 45)
            case .conditioning:      return (4, "30s", 60)
            }
        }
        _ = level // reserved for future tweaks
    }

    private static func noteFor(role: Role, pick: LibraryExercise, goal: WorkoutGoal) -> String {
        switch role {
        case .primaryCompound:
            return "Leave 2 reps in reserve. Add weight when all sets hit the top of the range."
        case .secondaryCompound:
            return "Controlled tempo, full range of motion."
        case .accessory:
            return "Focus on the working muscle, not the weight."
        case .isolation:
            return "Slow eccentric, squeeze at the top."
        case .core:
            return "Brace hard, breathe through the movement."
        case .conditioning:
            return goal == .fatLoss ? "Push effort, short rests." : "Keep tempo high but controlled."
        }
    }

    // MARK: - Helpers

    private static func sanitize(_ prefs: WorkoutPreferences) -> WorkoutPreferences {
        var p = prefs
        p.daysPerWeek = max(1, min(7, p.daysPerWeek))
        return p
    }

    private static func parseInjuries(_ raw: [String]) -> Set<Joint> {
        var out: Set<Joint> = []
        for r in raw.map({ $0.lowercased() }) {
            if r.contains("shoulder") { out.insert(.shoulder) }
            if r.contains("elbow") { out.insert(.elbow) }
            if r.contains("wrist") { out.insert(.wrist) }
            if r.contains("back") || r.contains("spine") { out.insert(.lowerBack) }
            if r.contains("knee") { out.insert(.knee) }
            if r.contains("hip") { out.insert(.hip) }
            if r.contains("ankle") { out.insert(.ankle) }
        }
        return out
    }

    /// Stable seed derived from immutable profile traits + preference snapshot.
    /// Same combination → same exercise picks forever.
    private static func profileSeed(_ profile: UserProfile) -> UInt64 {
        var h = Hasher()
        h.combine(profile.ageValue)
        h.combine(profile.sexRaw)
        h.combine(Int(profile.heightCm.rounded()))
        h.combine(Int(profile.weightKg.rounded()))
        return UInt64(bitPattern: Int64(h.finalize()))
    }

    private static func inputHash(profile: UserProfile, prefs: WorkoutPreferences) -> String {
        let payload = "\(profile.ageValue)|\(profile.sexRaw)|\(Int(profile.heightCm))|\(Int(profile.weightKg))|\(prefs.level.rawValue)|\(prefs.goal.rawValue)|\(prefs.equipment.rawValue)|\(prefs.daysPerWeek)|\(prefs.injuries.sorted().joined(separator: ","))"
        let digest = SHA256.hash(data: Data(payload.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func generatedTitle(prefs: WorkoutPreferences) -> String {
        "\(prefs.daysPerWeek)-Day \(prefs.goal.rawValue) Plan"
    }
}
