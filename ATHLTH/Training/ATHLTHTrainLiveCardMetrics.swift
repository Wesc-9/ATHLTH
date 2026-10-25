import Foundation

/// Display-only live summary for Train → I dag. Never writes workout state.
/// Do not claim a phone-only heart-rate measurement, assume treadmill
/// distance was observed, or show a stale instantaneous GPS pace.
enum ATHLTHTrainLiveCardMetrics {
    static func distanceLabel(
        meters: Double,
        estimated: Bool
    ) -> String? {
        guard meters.isFinite, meters > 0 else { return nil }
        let source = estimated ? "estimert" : "GPS"
        return String(format: "%.2f km (%@)", meters / 1000, source)
    }

    /// Averages *active* time rather than wall time; GPS points are required
    /// by the caller before describing this as a measured outdoor pace.
    static func averagePaceLabel(
        activeSeconds: TimeInterval,
        meters: Double
    ) -> String? {
        guard activeSeconds.isFinite, meters.isFinite,
              activeSeconds > 0, meters >= 200 else { return nil }
        let secondsPerKilometer = activeSeconds * 1000 / meters
        guard secondsPerKilometer.isFinite,
              (100...2400).contains(secondsPerKilometer) else { return nil }
        let rounded = Int(secondsPerKilometer.rounded())
        return String(format: "Snitt %d:%02d/km", rounded / 60, rounded % 60)
    }

    static func phoneDetail(
        _ workout: PhoneWorkout,
        at now: Date = Date()
    ) -> String? {
        var details: [String] = []
        let activeSeconds = workout.elapsed(at: now)

        if workout.runEnvironment == .treadmill {
            details.append("Tredemølle")
            // Integrated belt speed is an estimate, never a GPS observation.
            if let entries = workout.treadmillSpeedHistory,
               !entries.isEmpty,
               let distance = distanceLabel(
                   meters: workout.distanceMeters, estimated: true
               ) {
                details.append(distance)
            }
        } else if workout.points.count >= 2 {
            if let distance = distanceLabel(
                meters: workout.distanceMeters, estimated: false
            ) {
                details.append(distance)
                if let pace = averagePaceLabel(
                    activeSeconds: activeSeconds, meters: workout.distanceMeters
                ) {
                    details.append(pace)
                }
            }
        }

        if workout.awaitingMainStart == true {
            details.append("Venter på hoveddel")
        } else if let stepIndex = workout.structuredStepIndex,
                  let steps = workout.structuredRunningWorkout?.steps,
                  steps.indices.contains(stepIndex),
                  workout.structuredWorkoutComplete != true {
            details.append(steps[stepIndex].title)
        }
        if workout.resumedAt == nil {
            details.append("Pauset")
        }
        return details.isEmpty ? nil : details.joined(separator: " · ")
    }

    static func strengthDetail(
        _ workout: StrengthWorkoutLog,
        exerciseIndex: Int,
        setIndex: Int,
        restEndsAt: Date?,
        at now: Date = Date()
    ) -> String? {
        var details: [String] = []
        if workout.exercises.indices.contains(exerciseIndex) {
            let exercise = workout.exercises[exerciseIndex]
            details.append(exercise.exercise.displayName)
            let sets = exercise.sets.filter { $0.hybridPhaseKind == nil }
            let finished = sets.filter(\.isCompleted).count
            if !sets.isEmpty {
                details.append("\(finished)/\(sets.count) sett")
            } else {
                // A free strength session may have no sets yet.
                details.append("\(workout.totalCompletedSets) sett fullført")
            }
        } else {
            details.append("\(workout.totalCompletedSets) sett fullført")
        }

        if let restEndsAt, restEndsAt > now {
            details.append("Pause pågår")
        }
        return details.isEmpty ? nil : details.joined(separator: " · ")
    }
}
