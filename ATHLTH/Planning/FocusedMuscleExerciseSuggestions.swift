import Foundation

/// Lightweight, editable starting suggestions for muscle-focused strength days.
/// Never substitutes for the full exercise library or AI recommendations.
/// Weight is intentionally not prescribed without a personal performance baseline.
enum FocusedMuscleExerciseSuggestions {
    private struct Prescription {
        let name: String
        let muscle: String
        let equipment: String
        let repetitions: Int
    }

    static func makeExercises(
        for muscleID: String,
        sessionIndex: Int
    ) -> [PlannedExercise] {
        let options: [Prescription]
        switch muscleID {
        case "biceps", "arms":
            options = sessionIndex.isMultiple(of: 2)
                ? [
                    .init(name: "Dumbbell Biceps Curl", muscle: "biceps", equipment: "Dumbbells", repetitions: 10),
                    .init(name: "Hammer Curl", muscle: "biceps", equipment: "Dumbbells", repetitions: 12)
                ]
                : [
                    .init(name: "Incline Dumbbell Curl", muscle: "biceps", equipment: "Dumbbells", repetitions: 10),
                    .init(name: "Cable Biceps Curl", muscle: "biceps", equipment: "Cable", repetitions: 12)
                ]
        case "triceps":
            options = [
                .init(name: "Triceps Pushdown", muscle: "triceps", equipment: "Cable", repetitions: 12),
                .init(name: "Overhead Dumbbell Triceps Extension", muscle: "triceps", equipment: "Dumbbells", repetitions: 10)
            ]
        case "chest":
            options = [
                .init(name: "Dumbbell Bench Press", muscle: "chest", equipment: "Dumbbells", repetitions: 8),
                .init(name: "Push-up", muscle: "chest", equipment: "Bodyweight", repetitions: 12)
            ]
        case "back":
            options = [
                .init(name: "Lat Pulldown", muscle: "back", equipment: "Cable", repetitions: 10),
                .init(name: "Seated Cable Row", muscle: "back", equipment: "Cable", repetitions: 10)
            ]
        case "shoulders":
            options = [
                .init(name: "Dumbbell Shoulder Press", muscle: "shoulders", equipment: "Dumbbells", repetitions: 8),
                .init(name: "Dumbbell Lateral Raise", muscle: "shoulders", equipment: "Dumbbells", repetitions: 12)
            ]
        case "quads":
            options = [
                .init(name: "Goblet Squat", muscle: "quads", equipment: "Dumbbells", repetitions: 10),
                .init(name: "Split Squat", muscle: "quads", equipment: "Bodyweight", repetitions: 10)
            ]
        case "hamstrings":
            options = [
                .init(name: "Romanian Deadlift", muscle: "hamstrings", equipment: "Dumbbells", repetitions: 10),
                .init(name: "Lying Leg Curl", muscle: "hamstrings", equipment: "Machine", repetitions: 12)
            ]
        case "glutes":
            options = [
                .init(name: "Hip Thrust", muscle: "glutes", equipment: "Barbell", repetitions: 10),
                .init(name: "Glute Bridge", muscle: "glutes", equipment: "Bodyweight", repetitions: 12)
            ]
        case "calves":
            options = [
                .init(name: "Standing Calf Raise", muscle: "calves", equipment: "Bodyweight", repetitions: 12),
                .init(name: "Seated Calf Raise", muscle: "calves", equipment: "Machine", repetitions: 12)
            ]
        case "core":
            options = [
                .init(name: "Cable Crunch", muscle: "core", equipment: "Cable", repetitions: 12),
                .init(name: "Dead Bug", muscle: "core", equipment: "Bodyweight", repetitions: 10)
            ]
        case "forearms":
            options = [
                .init(name: "Wrist Curl", muscle: "forearms", equipment: "Dumbbells", repetitions: 12),
                .init(name: "Reverse Wrist Curl", muscle: "forearms", equipment: "Dumbbells", repetitions: 12)
            ]
        default:
            options = []
        }

        return options.map { suggestion in
            PlannedExercise(
                id: UUID(),
                exerciseID: nil,
                embeddedExercise: ExerciseSnapshot(
                    name: suggestion.name,
                    instructions: [],
                    primaryMuscles: [suggestion.muscle],
                    secondaryMuscles: [],
                    equipment: [suggestion.equipment],
                    imageURL: nil
                ),
                sets: 3,
                reps: suggestion.repetitions,
                targetWeightKilograms: nil,
                targetRPE: nil,
                restSeconds: 90,
                notes: ATHLTHLocalization.choose(
                    english: "Editable starting suggestion. Adjust for your experience and equipment.",
                    norwegian: "Redigerbart startforslag. Tilpass til erfaring og utstyr."
                ),
                targetRIR: nil,
                supersetGroupID: nil,
                progression: StrengthProgressionRule.none
            )
        }
    }
}
