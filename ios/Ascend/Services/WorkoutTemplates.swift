import Foundation

/// Curated preset workout templates users can fork into editable plans.
/// Pure data — no AI, no randomness. Same template → same starting plan.
nonisolated enum WorkoutTemplates {

    struct Template: Identifiable, Sendable, Hashable {
        let id: String
        let title: String
        let subtitle: String
        let goal: WorkoutGoal
        let daysPerWeek: Int
        let level: FitnessLevel
        let symbol: String
        let days: [Day]

        struct Day: Sendable, Hashable {
            let title: String
            let focus: String
            let exercises: [Exercise]
        }
        struct Exercise: Sendable, Hashable {
            let name: String
            let sets: Int
            let reps: String
            let restSeconds: Int
            let muscleGroup: String
            let isCompound: Bool
            let notes: String

            init(_ name: String, sets: Int, reps: String, rest: Int,
                 muscle: String = "", compound: Bool = false, notes: String = "") {
                self.name = name; self.sets = sets; self.reps = reps
                self.restSeconds = rest; self.muscleGroup = muscle
                self.isCompound = compound; self.notes = notes
            }
        }
    }

    static let all: [Template] = [
        ppl,
        upperLower,
        starting5x5,
        fullBody3
    ]

    // MARK: - Templates

    static let ppl = Template(
        id: "ppl-6",
        title: "Push / Pull / Legs",
        subtitle: "6-day classic hypertrophy split",
        goal: .hypertrophy,
        daysPerWeek: 6,
        level: .intermediate,
        symbol: "figure.strengthtraining.traditional",
        days: [
            .init(title: "Day 1", focus: "Push", exercises: [
                .init("Barbell Bench Press", sets: 4, reps: "6-8", rest: 120, muscle: "chest", compound: true),
                .init("Overhead Press", sets: 3, reps: "8", rest: 120, muscle: "shoulders", compound: true),
                .init("Incline Dumbbell Press", sets: 3, reps: "10", rest: 90, muscle: "chest", compound: true),
                .init("Lateral Raise", sets: 4, reps: "12-15", rest: 60, muscle: "shoulders"),
                .init("Triceps Pushdown", sets: 3, reps: "12", rest: 60, muscle: "triceps")
            ]),
            .init(title: "Day 2", focus: "Pull", exercises: [
                .init("Pull-Up", sets: 4, reps: "6-10", rest: 120, muscle: "back", compound: true),
                .init("Barbell Row", sets: 4, reps: "8", rest: 120, muscle: "back", compound: true),
                .init("Seated Cable Row", sets: 3, reps: "10", rest: 90, muscle: "back", compound: true),
                .init("Face Pull", sets: 3, reps: "15", rest: 60, muscle: "back"),
                .init("Barbell Curl", sets: 3, reps: "10", rest: 60, muscle: "biceps")
            ]),
            .init(title: "Day 3", focus: "Legs", exercises: [
                .init("Back Squat", sets: 4, reps: "6-8", rest: 150, muscle: "quads", compound: true),
                .init("Romanian Deadlift", sets: 3, reps: "8", rest: 120, muscle: "hamstrings", compound: true),
                .init("Leg Press", sets: 3, reps: "10-12", rest: 90, muscle: "quads", compound: true),
                .init("Walking Lunge", sets: 3, reps: "10 ea", rest: 75, muscle: "quads"),
                .init("Standing Calf Raise", sets: 4, reps: "12", rest: 45, muscle: "calves")
            ]),
            .init(title: "Day 4", focus: "Push", exercises: [
                .init("Overhead Press", sets: 4, reps: "6-8", rest: 120, muscle: "shoulders", compound: true),
                .init("Dumbbell Bench Press", sets: 3, reps: "10", rest: 90, muscle: "chest", compound: true),
                .init("Dips", sets: 3, reps: "8-10", rest: 90, muscle: "chest", compound: true),
                .init("Cable Chest Fly", sets: 3, reps: "12", rest: 60, muscle: "chest"),
                .init("Overhead Triceps Extension", sets: 3, reps: "12", rest: 60, muscle: "triceps")
            ]),
            .init(title: "Day 5", focus: "Pull", exercises: [
                .init("Deadlift", sets: 3, reps: "5", rest: 180, muscle: "hamstrings", compound: true),
                .init("Lat Pulldown", sets: 4, reps: "8-10", rest: 90, muscle: "back", compound: true),
                .init("Dumbbell Row", sets: 3, reps: "10", rest: 90, muscle: "back", compound: true),
                .init("Hammer Curl", sets: 3, reps: "12", rest: 60, muscle: "biceps"),
                .init("Face Pull", sets: 3, reps: "15", rest: 45, muscle: "back")
            ]),
            .init(title: "Day 6", focus: "Legs", exercises: [
                .init("Front Squat", sets: 4, reps: "8", rest: 120, muscle: "quads", compound: true),
                .init("Hip Thrust", sets: 4, reps: "10", rest: 90, muscle: "glutes", compound: true),
                .init("Bulgarian Split Squat", sets: 3, reps: "10 ea", rest: 75, muscle: "quads"),
                .init("Leg Curl", sets: 3, reps: "12", rest: 60, muscle: "hamstrings"),
                .init("Standing Calf Raise", sets: 4, reps: "15", rest: 45, muscle: "calves")
            ])
        ]
    )

    static let upperLower = Template(
        id: "upper-lower-4",
        title: "Upper / Lower",
        subtitle: "4-day balanced strength + size",
        goal: .hypertrophy,
        daysPerWeek: 4,
        level: .intermediate,
        symbol: "figure.strengthtraining.functional",
        days: [
            .init(title: "Day 1", focus: "Upper", exercises: [
                .init("Barbell Bench Press", sets: 4, reps: "6-8", rest: 120, muscle: "chest", compound: true),
                .init("Barbell Row", sets: 4, reps: "8", rest: 120, muscle: "back", compound: true),
                .init("Overhead Press", sets: 3, reps: "8-10", rest: 90, muscle: "shoulders", compound: true),
                .init("Lat Pulldown", sets: 3, reps: "10", rest: 75, muscle: "back", compound: true),
                .init("Dumbbell Curl", sets: 3, reps: "10", rest: 60, muscle: "biceps"),
                .init("Triceps Pushdown", sets: 3, reps: "12", rest: 60, muscle: "triceps")
            ]),
            .init(title: "Day 2", focus: "Lower", exercises: [
                .init("Back Squat", sets: 4, reps: "6-8", rest: 150, muscle: "quads", compound: true),
                .init("Romanian Deadlift", sets: 4, reps: "8", rest: 120, muscle: "hamstrings", compound: true),
                .init("Walking Lunge", sets: 3, reps: "10 ea", rest: 75, muscle: "quads"),
                .init("Leg Curl", sets: 3, reps: "12", rest: 60, muscle: "hamstrings"),
                .init("Standing Calf Raise", sets: 4, reps: "12", rest: 45, muscle: "calves"),
                .init("Plank", sets: 3, reps: "45s", rest: 45, muscle: "core")
            ]),
            .init(title: "Day 3", focus: "Upper", exercises: [
                .init("Overhead Press", sets: 4, reps: "6-8", rest: 120, muscle: "shoulders", compound: true),
                .init("Pull-Up", sets: 4, reps: "6-10", rest: 120, muscle: "back", compound: true),
                .init("Incline Dumbbell Press", sets: 3, reps: "10", rest: 90, muscle: "chest", compound: true),
                .init("Seated Cable Row", sets: 3, reps: "10", rest: 75, muscle: "back", compound: true),
                .init("Lateral Raise", sets: 4, reps: "12-15", rest: 45, muscle: "shoulders"),
                .init("Hammer Curl", sets: 3, reps: "12", rest: 60, muscle: "biceps")
            ]),
            .init(title: "Day 4", focus: "Lower", exercises: [
                .init("Deadlift", sets: 3, reps: "5", rest: 180, muscle: "hamstrings", compound: true),
                .init("Front Squat", sets: 4, reps: "8", rest: 120, muscle: "quads", compound: true),
                .init("Hip Thrust", sets: 3, reps: "10", rest: 90, muscle: "glutes", compound: true),
                .init("Leg Press", sets: 3, reps: "12", rest: 75, muscle: "quads", compound: true),
                .init("Standing Calf Raise", sets: 4, reps: "15", rest: 45, muscle: "calves")
            ])
        ]
    )

    static let starting5x5 = Template(
        id: "starting-5x5",
        title: "Starting 5×5",
        subtitle: "3-day beginner strength foundation",
        goal: .strength,
        daysPerWeek: 3,
        level: .beginner,
        symbol: "dumbbell.fill",
        days: [
            .init(title: "Day A", focus: "Squat / Press / Row", exercises: [
                .init("Back Squat", sets: 5, reps: "5", rest: 180, muscle: "quads", compound: true,
                      notes: "Same weight all 5 sets. Add 2.5kg next session if all reps hit."),
                .init("Barbell Bench Press", sets: 5, reps: "5", rest: 180, muscle: "chest", compound: true),
                .init("Barbell Row", sets: 5, reps: "5", rest: 150, muscle: "back", compound: true)
            ]),
            .init(title: "Day B", focus: "Squat / OHP / Deadlift", exercises: [
                .init("Back Squat", sets: 5, reps: "5", rest: 180, muscle: "quads", compound: true),
                .init("Overhead Press", sets: 5, reps: "5", rest: 180, muscle: "shoulders", compound: true),
                .init("Deadlift", sets: 1, reps: "5", rest: 240, muscle: "hamstrings", compound: true,
                      notes: "One heavy top set. Add 5kg next session if clean.")
            ]),
            .init(title: "Day C", focus: "Squat / Press / Row", exercises: [
                .init("Back Squat", sets: 5, reps: "5", rest: 180, muscle: "quads", compound: true),
                .init("Barbell Bench Press", sets: 5, reps: "5", rest: 180, muscle: "chest", compound: true),
                .init("Barbell Row", sets: 5, reps: "5", rest: 150, muscle: "back", compound: true)
            ])
        ]
    )

    static let fullBody3 = Template(
        id: "full-body-3",
        title: "Full Body 3-Day",
        subtitle: "Time-efficient hypertrophy",
        goal: .hypertrophy,
        daysPerWeek: 3,
        level: .beginner,
        symbol: "figure.cooldown",
        days: [
            .init(title: "Day 1", focus: "Full Body A", exercises: [
                .init("Goblet Squat", sets: 4, reps: "8-10", rest: 90, muscle: "quads", compound: true),
                .init("Dumbbell Bench Press", sets: 4, reps: "8-10", rest: 90, muscle: "chest", compound: true),
                .init("Dumbbell Row", sets: 4, reps: "10", rest: 75, muscle: "back", compound: true),
                .init("Seated Dumbbell Press", sets: 3, reps: "10", rest: 75, muscle: "shoulders", compound: true),
                .init("Plank", sets: 3, reps: "45s", rest: 45, muscle: "core")
            ]),
            .init(title: "Day 2", focus: "Full Body B", exercises: [
                .init("Romanian Deadlift", sets: 4, reps: "8", rest: 120, muscle: "hamstrings", compound: true),
                .init("Push-Up", sets: 4, reps: "12-15", rest: 60, muscle: "chest", compound: true),
                .init("Inverted Row", sets: 4, reps: "10", rest: 60, muscle: "back", compound: true),
                .init("Walking Lunge", sets: 3, reps: "10 ea", rest: 60, muscle: "quads"),
                .init("Hanging Leg Raise", sets: 3, reps: "10", rest: 45, muscle: "core")
            ]),
            .init(title: "Day 3", focus: "Full Body C", exercises: [
                .init("Back Squat", sets: 4, reps: "8", rest: 120, muscle: "quads", compound: true),
                .init("Incline Dumbbell Press", sets: 3, reps: "10", rest: 90, muscle: "chest", compound: true),
                .init("Pull-Up", sets: 3, reps: "6-10", rest: 90, muscle: "back", compound: true),
                .init("Lateral Raise", sets: 3, reps: "12", rest: 45, muscle: "shoulders"),
                .init("Standing Calf Raise", sets: 3, reps: "15", rest: 45, muscle: "calves")
            ])
        ]
    )
}
