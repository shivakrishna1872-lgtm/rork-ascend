import Foundation
import SwiftData

/// Deterministic, fully-editable workout plan stored locally.
/// Source is either `generated` (rule-based generator) or `scanned` (OCR import).
@Model
final class WorkoutPlan {
    @Attribute(.unique) var id: UUID
    var title: String
    var goalRaw: String
    var sourceRaw: String
    var createdAt: Date
    var updatedAt: Date
    /// Hash of the deterministic inputs — same hash means the exact same plan
    /// will be produced if regenerated. nil for scanned plans.
    var inputHash: String?
    /// Encoded `WorkoutPreferences` snapshot (JSON) — drives regeneration.
    var preferencesJSON: String?

    @Relationship(deleteRule: .cascade, inverse: \WorkoutDay.plan)
    var days: [WorkoutDay] = []

    init(
        id: UUID = UUID(),
        title: String,
        goalRaw: String,
        sourceRaw: String,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        inputHash: String? = nil,
        preferencesJSON: String? = nil
    ) {
        self.id = id
        self.title = title
        self.goalRaw = goalRaw
        self.sourceRaw = sourceRaw
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.inputHash = inputHash
        self.preferencesJSON = preferencesJSON
    }

    var source: WorkoutSource { WorkoutSource(rawValue: sourceRaw) ?? .generated }
    var goal: WorkoutGoal { WorkoutGoal(rawValue: goalRaw) ?? .hypertrophy }
    var sortedDays: [WorkoutDay] { days.sorted { $0.orderIndex < $1.orderIndex } }
}

@Model
final class WorkoutDay {
    @Attribute(.unique) var id: UUID
    var orderIndex: Int
    var dayTitle: String
    var focus: String
    var plan: WorkoutPlan?

    @Relationship(deleteRule: .cascade, inverse: \WorkoutExercise.day)
    var exercises: [WorkoutExercise] = []

    init(id: UUID = UUID(), orderIndex: Int, dayTitle: String, focus: String) {
        self.id = id
        self.orderIndex = orderIndex
        self.dayTitle = dayTitle
        self.focus = focus
    }

    var sortedExercises: [WorkoutExercise] {
        exercises.sorted { $0.orderIndex < $1.orderIndex }
    }

    var isRest: Bool { exercises.isEmpty && focus.lowercased().contains("rest") }
}

@Model
final class WorkoutExercise {
    @Attribute(.unique) var id: UUID
    var orderIndex: Int
    var name: String
    var sets: Int
    var reps: String
    var restSeconds: Int
    var notes: String
    var muscleGroup: String
    var equipment: String
    var difficulty: String
    var day: WorkoutDay?

    init(
        id: UUID = UUID(),
        orderIndex: Int,
        name: String,
        sets: Int,
        reps: String,
        restSeconds: Int,
        notes: String = "",
        muscleGroup: String = "",
        equipment: String = "",
        difficulty: String = ""
    ) {
        self.id = id
        self.orderIndex = orderIndex
        self.name = name
        self.sets = sets
        self.reps = reps
        self.restSeconds = restSeconds
        self.notes = notes
        self.muscleGroup = muscleGroup
        self.equipment = equipment
        self.difficulty = difficulty
    }
}

// MARK: - Enums & preferences

nonisolated enum WorkoutSource: String, Codable, Sendable {
    case generated, scanned
    var label: String { self == .generated ? "Generated" : "Scanned" }
}

nonisolated enum WorkoutGoal: String, Codable, CaseIterable, Sendable, Identifiable {
    case fatLoss = "Fat Loss"
    case hypertrophy = "Hypertrophy"
    case strength = "Strength"
    case athletic = "Athletic"
    var id: String { rawValue }
}

nonisolated enum FitnessLevel: String, Codable, CaseIterable, Sendable, Identifiable {
    case beginner = "Beginner"
    case intermediate = "Intermediate"
    case advanced = "Advanced"
    var id: String { rawValue }
}

nonisolated enum EquipmentLevel: String, Codable, CaseIterable, Sendable, Identifiable {
    case gym = "Full Gym"
    case home = "Home Setup"
    case dumbbells = "Dumbbells Only"
    case none = "Bodyweight"
    var id: String { rawValue }
}

/// User-editable inputs that drive the deterministic generator. Persisted on
/// the plan + cached in UserDefaults so the form remembers last selections.
nonisolated struct WorkoutPreferences: Codable, Hashable, Sendable {
    var level: FitnessLevel
    var goal: WorkoutGoal
    var equipment: EquipmentLevel
    var daysPerWeek: Int
    var injuries: [String]

    static let `default` = WorkoutPreferences(
        level: .intermediate,
        goal: .hypertrophy,
        equipment: .gym,
        daysPerWeek: 4,
        injuries: []
    )

    static let storageKey = "ascend.workout.prefs.v1"

    static func load() -> WorkoutPreferences {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let prefs = try? JSONDecoder().decode(WorkoutPreferences.self, from: data)
        else { return .default }
        return prefs
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
