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
        /// More than one matching exercise in this workout is ambiguous.
        let isAmbiguous: Bool
    }

    /// The snapshot does not contain a stable exercise-catalog identifier.
    /// `plannedExerciseID` identifies a planned entry, not necessarily the
    /// underlying reusable library exercise. Until catalog-ID provenance is
    /// persisted for live logs, use conservative movement/equipment matching.
    private struct Signature: Equatable {
        let libraryExerciseID: UUID?
        let loadBasis: ATHLTHStrengthLoadBasis?
        let name: String
        let equipment: [String]
        let primaryMuscles: [String]

        init(_ snapshot: ExerciseSnapshot) {
            libraryExerciseID = snapshot.libraryExerciseID
            loadBasis = snapshot.coachLoadBasis
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
            guard !equipment.isEmpty,
                  equipment == other.equipment else { return false }
            // A known load basis must match on both sides; one unknown
            // record cannot be assumed to use the same per-hand/total kg.
            if loadBasis != nil || other.loadBasis != nil {
                guard loadBasis == other.loadBasis else { return false }
            }
            // The canonical library ID is authoritative when present on both
            // sides. Renaming an exercise does not create a different exercise.
            // A single missing ID can never be guessed from name alone.
            if libraryExerciseID != nil || other.libraryExerciseID != nil {
                // Catalog identity is authoritative. Muscle labels and the
                // display name can change over time without splitting history.
                return libraryExerciseID != nil &&
                    libraryExerciseID == other.libraryExerciseID
            }
            guard !name.isEmpty, name == other.name else { return false }
            // For legacy records without an ID, explicit muscle conflicts
            // are a conservative reason not to merge separate exercises.
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

    /// Stable grouping key for Coach trend summaries and plan suggestions.
    /// Different equipment always means different evidence, even when
    /// exercises share the same visible name or catalog ID.
    static func identityKey(for exercise: ExerciseSnapshot) -> String? {
        let signature = Signature(exercise)
        guard !signature.equipment.isEmpty else { return nil }
        let identity = signature.libraryExerciseID?.uuidString ??
            ("legacy:" + signature.name)
        guard !identity.isEmpty else { return nil }
        let legacyMuscleKey = signature.libraryExerciseID == nil
            ? "|" + signature.primaryMuscles.joined(separator: ",")
            : ""
        let basisKey = signature.loadBasis.map { "|" + $0.rawValue } ?? ""
        return identity + "|" + signature.equipment.joined(separator: ",") +
            legacyMuscleKey + basisKey
    }

    struct TargetEvidence {
        let workingSetIDs: [UUID]
        let maximumRecordedWeightKg: Double
        let minimumRecordedWeightKg: Double
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
        // A skipped/unresolved prescribed working set is not success.
        let prescribed = exercise.sets.filter {
            $0.isWarmUp != true &&
            $0.plannedSetType != .warmUp &&
            $0.hybridPhaseKind == nil
        }
        let working = prescribed.filter(\.countsTowardTrainingLoad)
        guard exercise.isEmbeddedRunningInterval != true,
              exercise.groupStyle != .dropSet,
              prescribed.count >= 2,
              prescribed.count == working.count,
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
            minimumRecordedWeightKg: weights.min() ?? 0,
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
        guard identityKey(for: target.exercise) != nil else { return [] }
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
                guard seenWorkoutIDs.insert(workout.id).inserted else { return nil }
                let matching = workout.exercises.filter { candidate in
                    candidate.isEmbeddedRunningInterval != true &&
                    signature.matches(Signature(candidate.exercise))
                }
                guard let first = matching.first else { return nil }
                // Include even a fully skipped or invalid latest exercise:
                // it must block stale increases from older successful logs.
                // More than one matching entry cannot be treated as two
                // independent successes.
                return Session(
                    workoutID: workout.id,
                    date: workout.endedAt ?? workout.startedAt,
                    exercise: first,
                    isAmbiguous: matching.count != 1
                )
            }
            .prefix(maximum)
            .map { $0 }
    }
}
