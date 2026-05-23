import Foundation
import SwiftData

/// One logged working set. Append-only history that powers the deterministic
/// progressive-overload suggester. Stored locally; never modified after
/// insertion so trend math is reproducible.
@Model
final class SetLog {
    @Attribute(.unique) var id: UUID
    var date: Date
    /// Canonical exercise name (matches `WorkoutExercise.name`).
    var exerciseName: String
    /// Optional link back to the plan it came from. Survives plan deletion.
    var planIdString: String?
    var setIndex: Int
    var weightKg: Double
    var reps: Int
    /// Optional rate-of-perceived-exertion 6-10. 0 means not logged.
    var rpe: Double
    var completed: Bool

    init(
        id: UUID = UUID(),
        date: Date = .now,
        exerciseName: String,
        planIdString: String? = nil,
        setIndex: Int = 0,
        weightKg: Double = 0,
        reps: Int = 0,
        rpe: Double = 0,
        completed: Bool = true
    ) {
        self.id = id
        self.date = date
        self.exerciseName = exerciseName
        self.planIdString = planIdString
        self.setIndex = setIndex
        self.weightKg = weightKg
        self.reps = reps
        self.rpe = rpe
        self.completed = completed
    }
}
