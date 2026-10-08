import Foundation

/// Read-only analytics from the plan and ATHLTH's recorded strength history.
/// Never estimates muscle growth, effort, or weights that were not logged.
struct TrainingPlanStrengthReport {
    struct Week: Identifiable {
        let number: Int
        let plannedSessions: Int
        let loggedStrengthSessions: Int
        let plannedWorkingSets: Int
        let performedWorkingSets: Int
        let performedVolumeKilograms: Double

        var id: Int { number }
    }

    struct Muscle: Identifiable {
        let id: String
        let plannedWorkingSets: Int
        let performedWorkingSets: Int
        let performedVolumeKilograms: Double

        var title: String {
            switch id {
            case "biceps": return "Biceps"
            case "triceps": return "Triceps"
            case "forearms":
                return ATHLTHLocalization.choose(english: "Forearms", norwegian: "Underarmer")
            case "chest":
                return ATHLTHLocalization.choose(english: "Chest", norwegian: "Bryst")
            case "back":
                return ATHLTHLocalization.choose(english: "Back", norwegian: "Rygg")
            case "shoulders":
                return ATHLTHLocalization.choose(english: "Shoulders", norwegian: "Skuldre")
            case "quads":
                return ATHLTHLocalization.choose(english: "Quadriceps", norwegian: "Forside lår")
            case "hamstrings":
                return ATHLTHLocalization.choose(english: "Hamstrings", norwegian: "Bakside lår")
            case "glutes":
                return ATHLTHLocalization.choose(english: "Glutes", norwegian: "Sete")
            case "calves":
                return ATHLTHLocalization.choose(english: "Calves", norwegian: "Legger")
            case "core":
                return ATHLTHLocalization.choose(english: "Core", norwegian: "Kjerne")
            default: return id.capitalized
            }
        }
    }

    let weeks: [Week]
    let muscles: [Muscle]
    let totalPlannedStrengthSets: Int
    let totalPerformedStrengthSets: Int
    let totalRecordedVolumeKilograms: Double
    let loggedSessionCount: Int

    static func make(
        plan: TrainingPlan,
        strengthHistory: [StrengthWorkoutLog]
    ) -> TrainingPlanStrengthReport {
        // Use direct planned-session IDs. Names and dates are not unique
        // enough to safely attribute a workout to a specific plan.
        let plannedIDs = Set(
            plan.weeks.flatMap(\.days).flatMap(\.sessions).map(\.id)
        )
        let linkedLogs = strengthHistory.filter { workout in
            guard workout.isFinished,
                  let id = workout.plannedSessionID else { return false }
            return plannedIDs.contains(id)
        }
        let logsBySession = Dictionary(
            grouping: linkedLogs,
            by: { $0.plannedSessionID! }
        )

        var plannedSetsByMuscle: [String: Int] = [:]
        var recordedSetsByMuscle: [String: Int] = [:]
        var recordedLoadByMuscle: [String: Double] = [:]
        var weekReports: [Week] = []

        for (index, week) in plan.weeks.enumerated() {
            let plannedSessions = week.days.flatMap(\.sessions)
            let logs = plannedSessions.flatMap { logsBySession[$0.id] ?? [] }

            var plannedSets = 0
            var recordedSets = 0
            var recordedLoad = 0.0

            for session in plannedSessions {
                for exercise in session.exercises {
                    let count = exercise.resolvedSetTargets.filter {
                        $0.isWarmUp != true && $0.setType != .warmUp
                    }.count
                    plannedSets += count
                    for muscle in normalizedMuscles(exercise.embeddedExercise.primaryMuscles) {
                        plannedSetsByMuscle[muscle, default: 0] += count
                    }
                }
            }

            for workout in logs {
                for exercise in workout.exercises {
                    let workingSets = exercise.sets.filter(\.countsTowardTrainingLoad)
                    let sets = workingSets.count
                    let volume = workingSets.reduce(0.0) { $0 + $1.volumeKilograms }
                    recordedSets += sets
                    recordedLoad += volume

                    for muscle in normalizedMuscles(exercise.exercise.primaryMuscles) {
                        recordedSetsByMuscle[muscle, default: 0] += sets
                        recordedLoadByMuscle[muscle, default: 0] += volume
                    }
                }
            }

            weekReports.append(
                Week(
                    number: index + 1,
                    plannedSessions: plannedSessions.count,
                    loggedStrengthSessions: Set(logs.compactMap(\.plannedSessionID)).count,
                    plannedWorkingSets: plannedSets,
                    performedWorkingSets: recordedSets,
                    performedVolumeKilograms: recordedLoad
                )
            )
        }

        let muscleIDs = Set(plannedSetsByMuscle.keys).union(recordedSetsByMuscle.keys)
        let muscles = muscleIDs.map { id in
            Muscle(
                id: id,
                plannedWorkingSets: plannedSetsByMuscle[id, default: 0],
                performedWorkingSets: recordedSetsByMuscle[id, default: 0],
                performedVolumeKilograms: recordedLoadByMuscle[id, default: 0]
            )
        }
        .sorted {
            if $0.plannedWorkingSets != $1.plannedWorkingSets {
                return $0.plannedWorkingSets > $1.plannedWorkingSets
            }
            if $0.performedWorkingSets != $1.performedWorkingSets {
                return $0.performedWorkingSets > $1.performedWorkingSets
            }
            return $0.id < $1.id
        }

        return TrainingPlanStrengthReport(
            weeks: weekReports,
            muscles: muscles,
            totalPlannedStrengthSets: weekReports.reduce(0) {
                $0 + $1.plannedWorkingSets
            },
            totalPerformedStrengthSets: weekReports.reduce(0) {
                $0 + $1.performedWorkingSets
            },
            totalRecordedVolumeKilograms: weekReports.reduce(0) {
                $0 + $1.performedVolumeKilograms
            },
            loggedSessionCount: Set(linkedLogs.compactMap(\.plannedSessionID)).count
        )
    }

    private static func normalizedMuscles(_ values: [String]) -> [String] {
        let names = values.compactMap { value -> String? in
            let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard !name.isEmpty else { return nil }

            if name.contains("bicep") { return "biceps" }
            if name.contains("tricep") { return "triceps" }
            if name.contains("forearm") { return "forearms" }
            if name.contains("chest") || name.contains("pectoral") { return "chest" }
            if name.contains("hamstring") { return "hamstrings" }
            if name.contains("quad") { return "quads" }
            if name.contains("glute") { return "glutes" }
            if name.contains("calf") || name.contains("calves") { return "calves" }
            if name.contains("shoulder") || name.contains("deltoid") { return "shoulders" }
            if name.contains("abdom") || name == "core" || name == "abs" { return "core" }
            if name.contains("back") || name == "lats" { return "back" }

            return name
        }

        return Array(Set(names)).sorted()
    }
}
