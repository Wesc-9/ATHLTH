import Foundation

/// Read-only, deterministic exercise-history boundary for ATHLTH Coach.
///
/// This is shared by the live strength progression hint and the future
/// cross-app Coach decision engine. It never mutates workouts or plans.
/// Missing exercise identity/load provenance must not become permission
/// to treat unrelated exercises or apparatus weights as equivalent.
enum ATHLTHCoachStrengthComparableHistory {
    struct Session {
        let workoutID: UUID
        let date: Date
        let exercise: StrengthExerciseLog
    }

    /// The snapshot does not contain a stable exercise-catalog identifier.
    /// `plannedExerciseID` identifies a planned entry, not necessarily the
    /// underlying reusable library exercise. Until catalog-ID provenance is
    /// persisted for live logs, use conservative movement/equipment matching.
    private struct Signature: Equatable {
        let libraryExerciseID: UUID?
        let name: String
        let equipment: [String]
        let primaryMuscles: [String]

        init(_ snapshot: ExerciseSnapshot) {
            libraryExerciseID = snapshot.libraryExerciseID
            name = Self.normalized(snapshot.name)
            equipment = Self.normalizedSet(snapshot.equipment)
            primaryMuscles = Self.normalizedSet(snapshot.primaryMuscles)
        }

        private static func normalized(_ value: String) -> String {
            value
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        private static func normalizedSet(_ values: [String]) -> [String] {
            Array(Set(values.map(normalized).filter { !$0.isEmpty })).sorted()
        }

        func matches(_ other: Signature) -> Bool {
            guard !name.isEmpty, name == other.name,
                  !equipment.isEmpty,
                  equipment == other.equipment else { return false }
            // If either record supplies a canonical library ID, its partner
            // must supply the SAME ID. Never infer that two different
            // variants (or an unidentified legacy exercise) are one exercise.
            if libraryExerciseID != nil || other.libraryExerciseID != nil {
                guard libraryExerciseID == other.libraryExerciseID else { return false }
            }
            // Older snapshots can omit muscle metadata; use it only to rule
            // out an explicit conflict, not invent a new identity from it.
            if !primaryMuscles.isEmpty && !other.primaryMuscles.isEmpty {
                return primaryMuscles == other.primaryMuscles
            }
            return true
        }
    }

    /// Use this single provenance check across both the live Coach and
    /// scheduled-plan Coach. It compares identity and load-equipment semantics.
    static func isSameExercise(
        _ lhs: ExerciseSnapshot,
        _ rhs: ExerciseSnapshot
    ) -> Bool {
        Signature(lhs).matches(Signature(rhs))
    }

    struct TargetEvidence {
        let workingSetIDs: [UUID]
        let maximumRecordedWeightKg: Double
        let metAllTargets: Bool
    }

    /// A verified session must contain at least two recorded working sets,
    /// not skipped or warm-up sets, and every one must meet prescribed reps
    /// and weight. Very hard RPE/RIR scores prevent automatic weight review.
    /// Missing effort scores do not become invented RIR values.
    static func targetEvidence(
        for exercise: StrengthExerciseLog,
        minimumLoadKg: Double? = nil
    ) -> TargetEvidence? {
        let working = exercise.sets.filter(\.countsTowardTrainingLoad)
        guard working.count >= 2,
              minimumLoadKg.map({ $0.isFinite && $0 > 0 }) ?? true else {
            return nil
        }
        var weights: [Double] = []
        var allMet = true
        for set in working {
            guard isComparableWorkingSet(set),
                  let actualWeight = set.completedWeightKilograms,
                  let targetWeight = set.plannedWeightKilograms,
                  targetWeight.isFinite, targetWeight > 0,
                  let actualReps = set.resolvedCompletedReps,
                  let targetReps = set.plannedReps,
                  targetReps > 0 else {
                allMet = false
                break
            }
            if actualReps < targetReps ||
                actualWeight + 0.01 < targetWeight ||
                (minimumLoadKg.map { actualWeight + 0.01 < $0 } ?? false) ||
                (set.rpe.map { !$0.isFinite || $0 > 9 } ?? false) ||
                (set.rir.map { !$0.isFinite || $0 < 1 } ?? false) {
                allMet = false
            }
            weights.append(actualWeight)
        }
        guard !weights.isEmpty else { return nil }
        return TargetEvidence(
            workingSetIDs: working.map(\.id),
            maximumRecordedWeightKg: weights.max() ?? 0,
            metAllTargets: allMet && weights.count == working.count
        )
    }

    /// A logged working set is eligible for weight-based progression evidence
    /// only if actual repetitions and an actual external load are recorded.
    /// Timed stations, bodyweight-only, resistance levels, skipped/warm-up
    /// sets and compound dropset segments require a different policy.
    static func isComparableWorkingSet(_ set: StrengthSetLog) -> Bool {
        guard set.countsTowardTrainingLoad,
              set.resolvedTargetKind == .reps,
              set.resolvedLoadKind == .weightKilograms,
              set.recordsWeight != false,
              set.effortSegments?.isEmpty != false,
              let weight = set.completedWeightKilograms,
              weight.isFinite, weight > 0,
              let repetitions = set.resolvedCompletedReps,
              repetitions > 0 else { return false }
        return true
    }

    /// Bound reads to the last eight weeks and a small number of complete,
    /// independent workouts. Do not compare to a future or ongoing workout.
    /// This produces evidence, never a recommendation or automatic increase.
    static func sessions(
        for target: StrengthExerciseLog,
        in history: [StrengthWorkoutLog],
        now: Date = Date(),
        windowDays: Int = 56,
        limit: Int = 4
    ) -> [Session] {
        guard target.isEmbeddedRunningInterval != true,
              target.sets.contains(where: {
                  $0.resolvedTargetKind == .reps &&
                  $0.resolvedLoadKind == .weightKilograms
              }) else { return [] }

        let signature = Signature(target.exercise)
        guard !signature.name.isEmpty else { return [] }
        let days = min(max(windowDays, 1), 56)
        let earliest = now.addingTimeInterval(-Double(days) * 86_400)
        let maximum = min(max(limit, 0), 12)
        guard maximum > 0 else { return [] }

        var seenWorkoutIDs = Set<UUID>()
        return history
            .filter { workout in
                workout.isFinished &&
                workout.startedAt <= now &&
                (workout.endedAt ?? workout.startedAt) <= now &&
                (workout.endedAt ?? workout.startedAt) >= earliest
            }
            .sorted {
                ($0.endedAt ?? $0.startedAt) > ($1.endedAt ?? $1.startedAt)
            }
            .compactMap { workout -> Session? in
                guard seenWorkoutIDs.insert(workout.id).inserted,
                      let matching = workout.exercises.first(where: { candidate in
                          candidate.isEmbeddedRunningInterval != true &&
                          signature.matches(Signature(candidate.exercise)) &&
                          candidate.sets.contains(where: isComparableWorkingSet)
                      }) else { return nil }
                return Session(
                    workoutID: workout.id,
                    date: workout.endedAt ?? workout.startedAt,
                    exercise: matching
                )
            }
            .prefix(maximum)
            .map { $0 }
    }
}
