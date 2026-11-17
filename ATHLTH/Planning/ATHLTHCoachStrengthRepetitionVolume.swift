import Foundation

/// Conservative, evidence-based repetition and volume review for ATHLTH Coach.
/// This never edits a workout, and it never invents a repetition range or a
/// user's training goal. It is deliberately independent of generative AI.
enum ATHLTHCoachStrengthRepetitionVolume {
    struct RepRange: Equatable, Hashable {
        let lower: Int
        let upper: Int

        init?(lower: Int, upper: Int) {
            guard (1...30).contains(lower),
                  (1...30).contains(upper),
                  lower < upper else { return nil }
            self.lower = lower
            self.upper = upper
        }
    }

    enum Action: String, Equatable {
        case collectEvidence
        case hold
        case reviewOneMoreRep
        case reviewTrainingVolume
    }

    enum Reason: String, Equatable {
        case goalOrRangeMissing
        case invalidPrescription
        case notEnoughSessions
        case latestSessionMissedTarget
        case effortNotVerified
        case readyToIncreaseRepetitions
        case alreadyAtUpperLimit
        case plateauForReview
    }

    struct Session: Equatable {
        let workoutID: UUID
        let date: Date
        let workingSetIDs: [UUID]
        let minimumReps: Int
        let minimumWeightKg: Double
        let allTargetsMet: Bool
        let effortSupportsMore: Bool
    }

    struct Recommendation: Equatable {
        let action: Action
        let reason: Reason
        let currentReps: Int
        let proposedReps: Int?
        let sourceWorkoutIDs: [UUID]
        let sourceSetIDs: [UUID]
        /// Never imply that a review is a ready-to-apply extra set.
        let proposedAdditionalSets: Int?
        let requiresUserApproval: Bool
    }

    /// Uses only a genuinely logged, same-load working-set session. A
    /// missing RPE/RIR is not proof of reserve. A single very hard set vetoes
    /// progression, even if the other sets were easy.
    static func evidence(
        workoutID: UUID,
        date: Date,
        exercise: StrengthExerciseLog,
        prescribedLoadKg: Double
    ) -> Session? {
        guard exercise.isEmbeddedRunningInterval != true,
              exercise.groupStyle == nil,
              prescribedLoadKg.isFinite,
              prescribedLoadKg > 0,
              let verified = ATHLTHCoachStrengthComparableHistory.targetEvidence(
                  for: exercise, minimumLoadKg: prescribedLoadKg
              ),
              verified.workingSetIDs.count >= 2 else { return nil }

        let working = exercise.sets.filter(\.countsTowardTrainingLoad)
        guard working.count == verified.workingSetIDs.count,
              working.allSatisfy({ $0.plannedReps != nil }) else { return nil }
        let reps = working.compactMap(\.resolvedCompletedReps)
        guard reps.count == working.count,
              let minReps = reps.min(), minReps > 0 else { return nil }
        let effortSupportsMore = working.allSatisfy { set in
            let rirOK = set.rir.map { $0.isFinite && $0 >= 2 }
            let rpeOK = set.rpe.map { $0.isFinite && $0 <= 8 }
            // If either metric explicitly reports excessive effort, veto.
            guard rirOK != false, rpeOK != false else { return false }
            return rirOK == true || rpeOK == true
        }
        return Session(
            workoutID: workoutID,
            date: date,
            workingSetIDs: verified.workingSetIDs,
            minimumReps: minReps,
            minimumWeightKg: verified.minimumRecordedWeightKg,
            allTargetsMet: verified.metAllTargets,
            effortSupportsMore: effortSupportsMore
        )
    }

    static func assess(
        sessions: [Session],
        goal: TrainingPlanGoalType?,
        range: RepRange?,
        prescribedReps: Int,
        prescribedLoadKg: Double
    ) -> Recommendation {
        var seen = Set<UUID>()
        let recent = Array(sessions
            .sorted {
                $0.date == $1.date
                    ? $0.workoutID.uuidString < $1.workoutID.uuidString
                    : $0.date > $1.date
            }
            .filter { seen.insert($0.workoutID).inserted }
            .prefix(4))
        let sourceWorkoutIDs = recent.map(\.workoutID)
        let sourceSetIDs = recent.flatMap(\.workingSetIDs)
        func result(
            _ action: Action, _ reason: Reason,
            _ newReps: Int? = nil
        ) -> Recommendation {
            Recommendation(
                action: action,
                reason: reason,
                currentReps: prescribedReps,
                proposedReps: newReps,
                sourceWorkoutIDs: sourceWorkoutIDs,
                sourceSetIDs: sourceSetIDs,
                proposedAdditionalSets: nil,
                requiresUserApproval: true
            )
        }

        guard goal == .getStronger || goal == .buildMuscle, let range else {
            return result(.collectEvidence, .goalOrRangeMissing)
        }
        guard prescribedLoadKg.isFinite, prescribedLoadKg > 0,
              range.lower <= prescribedReps,
              prescribedReps <= range.upper else {
            return result(.collectEvidence, .invalidPrescription)
        }
        guard recent.count >= 2 else {
            return result(.collectEvidence, .notEnoughSessions)
        }
        let latestTwo = Array(recent.prefix(2))
        guard latestTwo.allSatisfy({
            $0.allTargetsMet &&
            $0.workingSetIDs.count >= 2 &&
            $0.minimumReps >= prescribedReps &&
            $0.minimumWeightKg.isFinite &&
            $0.minimumWeightKg + 0.01 >= prescribedLoadKg
        }) else {
            return result(.hold, .latestSessionMissedTarget)
        }
        guard latestTwo.allSatisfy(\.effortSupportsMore) else {
            return result(.hold, .effortNotVerified)
        }

        if prescribedReps < range.upper {
            return result(
                .reviewOneMoreRep, .readyToIncreaseRepetitions,
                prescribedReps + 1
            )
        }

        // At the explicit upper limit, do not recommend unbounded reps.
        // Three separate stalled sessions spanning at least 14 days are a
        // reason to REVIEW volume, not to add sets or imply a diagnosis.
        if goal == .buildMuscle, recent.count >= 3 {
            let firstThree = Array(recent.prefix(3))
            let days = firstThree[0].date.timeIntervalSince(firstThree[2].date)
            if days >= 14 * 86_400,
               firstThree.allSatisfy({
                   $0.allTargetsMet && $0.effortSupportsMore &&
                   $0.minimumReps <= prescribedReps
               }) {
                return result(.reviewTrainingVolume, .plateauForReview)
            }
        }
        return result(.hold, .alreadyAtUpperLimit)
    }
}
