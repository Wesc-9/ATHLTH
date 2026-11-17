import Foundation

/// Shared, read-only progression decision for the ATHLTH Coach experience.
/// A recommendation is NOT a plan edit or a completed strength result.
/// Any proposed change requires explicit athlete approval elsewhere.
enum ATHLTHCoachStrengthDecision {
    enum Action: String, Equatable {
        case collectEvidence
        case hold
        case reviewSmallIncrease
    }

    enum Reason: String, Equatable {
        case invalidPrescription
        case insufficientSessions
        case missedLatestTarget
        case excessiveIncrement
        case targetsMetInTwoSessions
    }

    struct Evidence: Equatable {
        let workoutID: UUID
        let date: Date
        let workingSetIDs: [UUID]
        let minimumWorkingWeightKg: Double
        let metTargets: Bool
    }

    struct Assessment: Equatable {
        let action: Action
        let reason: Reason
        let sourceWorkoutIDs: [UUID]
        let sourceSetIDs: [UUID]
        let proposedWeightKg: Double?
        let requiresUserApproval: Bool
    }

    /// Only independent, most-recent complete workouts count. A missed
    /// latest target vetoes an older successful run. The upper bound on load
    /// increases prevents a huge percentage jump for a lightweight exercise.
    static func assess(
        evidence: [Evidence],
        prescribedLoadKg: Double,
        incrementKg: Double? = nil
    ) -> Assessment {
        guard prescribedLoadKg.isFinite, prescribedLoadKg > 0 else {
            return Assessment(
                action: .collectEvidence,
                reason: .invalidPrescription,
                sourceWorkoutIDs: [],
                sourceSetIDs: [],
                proposedWeightKg: nil,
                requiresUserApproval: true
            )
        }

        var seen = Set<UUID>()
        let recent = evidence
            .filter {
                $0.minimumWorkingWeightKg.isFinite &&
                $0.minimumWorkingWeightKg >= 0
            }
            .sorted {
                $0.date == $1.date
                    ? $0.workoutID.uuidString < $1.workoutID.uuidString
                    : $0.date > $1.date
            }
            .filter { seen.insert($0.workoutID).inserted }
        let latest = Array(recent.prefix(2))
        let sourceWorkoutIDs = latest.map(\.workoutID)
        let sourceSetIDs = latest.flatMap(\.workingSetIDs)

        func result(_ action: Action, _ reason: Reason, _ proposed: Double? = nil) -> Assessment {
            Assessment(
                action: action,
                reason: reason,
                sourceWorkoutIDs: sourceWorkoutIDs,
                sourceSetIDs: sourceSetIDs,
                proposedWeightKg: proposed,
                requiresUserApproval: true
            )
        }

        // The most recent completed session outweighs older results.
        if let first = latest.first,
           (!first.metTargets || first.minimumWorkingWeightKg + 0.01 < prescribedLoadKg) {
            return result(.hold, .missedLatestTarget)
        }
        guard latest.count == 2 else {
            return result(.collectEvidence, .insufficientSessions)
        }
        guard latest.allSatisfy({
            $0.metTargets &&
            $0.workingSetIDs.count >= 2 &&
            $0.minimumWorkingWeightKg + 0.01 >= prescribedLoadKg
        }) else {
            return result(.hold, .missedLatestTarget)
        }

        // A numeric increase is allowed only when the caller supplies an
        // explicit, finite increment. No invented equipment availability.
        guard let incrementKg else {
            return result(.reviewSmallIncrease, .targetsMetInTwoSessions)
        }
        guard incrementKg.isFinite, (0.5...5).contains(incrementKg),
              incrementKg <= max(0.5, prescribedLoadKg * 0.15) else {
            return result(.hold, .excessiveIncrement)
        }
        let proposed = ((prescribedLoadKg + incrementKg) * 100).rounded() / 100
        guard proposed.isFinite, proposed > prescribedLoadKg else {
            return result(.hold, .excessiveIncrement)
        }
        return result(.reviewSmallIncrease, .targetsMetInTwoSessions, proposed)
    }
}
