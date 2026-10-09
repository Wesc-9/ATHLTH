import Foundation

/// Pure, explainable progression preview for sessions already placed in a
/// training block. No external data or AI is used.
enum TrainingBlockProgressionEngine {
    struct Change: Identifiable, Equatable {
        var id: UUID { workoutID }
        let workoutID: UUID
        let weekNumber: Int
        let workoutName: String
        let before: String
        let after: String
        let changedExercises: Int
    }

    struct Summary: Equatable {
        var changes: [Change] = []
        var protectedCompleted = 0
        var protectedPast = 0
        var alreadyApplied = 0
        var unchangedUnprescribed = 0

        var changedWorkouts: Int { changes.count }
        var changedExercises: Int {
            changes.reduce(0) { $0 + $1.changedExercises }
        }
        var hasChanges: Bool { !changes.isEmpty }
    }

    /// Applies only to future, strength-type, unfinished sessions in the
    /// selected block. Never modifies exercise identity or completed logs.
    static func prepare(
        plan: TrainingPlan,
        blockID: UUID,
        rule: TrainingBlockProgressionRule,
        protectedSessionIDs: Set<UUID>,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> (plan: TrainingPlan, summary: Summary)? {
        guard let block = plan.trainingBlocks?.first(where: { $0.id == blockID }),
              let rawStart = plan.startDate,
              rule.weightIncrementKilograms.isFinite,
              rule.weightIncrementKilograms > 0,
              rule.weightIncrementKilograms <= 20,
              (1...10).contains(rule.repetitionIncrement),
              rule.recoveryVolumeFactor.isFinite,
              (0.25...1).contains(rule.recoveryVolumeFactor),
              rule.recoveryWeightFactor.isFinite,
              (0.5...1).contains(rule.recoveryWeightFactor),
              block.startWeek >= 1,
              block.endWeek <= plan.weeks.count,
              block.endWeek >= block.startWeek
        else { return nil }

        var result = plan
        var summary = Summary()
        let start = calendar.startOfDay(for: rawStart)
        let today = calendar.startOfDay(for: now)
        let already = Set(block.progressedSessionIDs ?? [])

        for weekIndex in (block.startWeek - 1)..<block.endWeek {
            let relativeWeek = weekIndex - (block.startWeek - 1)
            for dayIndex in result.weeks[weekIndex].days.indices {
                let day = result.weeks[weekIndex].days[dayIndex]
                let dayOffset = weekIndex * 7 + day.dayIndex - 1
                guard let date = calendar.date(byAdding: .day, value: dayOffset, to: start)
                else { continue }

                for workoutIndex in day.sessions.indices {
                    let old = day.sessions[workoutIndex]
                    guard old.kind == .strength else { continue }
                    if protectedSessionIDs.contains(old.id) {
                        summary.protectedCompleted += 1
                        continue
                    }
                    if date < today {
                        summary.protectedPast += 1
                        continue
                    }
                    if already.contains(old.id) {
                        summary.alreadyApplied += 1
                        continue
                    }

                    var workout = old
                    var exerciseChanges = 0
                    for index in workout.exercises.indices {
                        let oldExercise = workout.exercises[index]
                        var updatedExercise = oldExercise
                        adjust(
                            exercise: &updatedExercise,
                            weekOffset: relativeWeek,
                            rule: rule
                        )
                        if updatedExercise != oldExercise {
                            workout.exercises[index] = updatedExercise
                            exerciseChanges += 1
                        }
                    }

                    guard exerciseChanges > 0 else {
                        summary.unchangedUnprescribed += 1
                        continue
                    }
                    result.weeks[weekIndex].days[dayIndex].sessions[workoutIndex] = workout
                    summary.changes.append(Change(
                        workoutID: old.id,
                        weekNumber: weekIndex + 1,
                        workoutName: old.title,
                        before: displayPrescription(old),
                        after: displayPrescription(workout),
                        changedExercises: exerciseChanges
                    ))
                }
            }
        }
        if let i = result.trainingBlocks?.firstIndex(where: { $0.id == blockID }) {
            result.trainingBlocks?[i].progressionRule = rule
            let newIDs = summary.changes.map(\.workoutID)
            result.trainingBlocks?[i].progressedSessionIDs =
                Array(already.union(newIDs)).sorted { $0.uuidString < $1.uuidString }
        }
        return (result, summary)
    }

    private static func adjust(
        exercise: inout PlannedExercise,
        weekOffset: Int,
        rule: TrainingBlockProgressionRule
    ) {
        guard exercise.resolvedTargetKind == .reps else { return }

        switch rule.kind {
        case .weight:
            guard weekOffset > 0,
                  exercise.resolvedLoadKind == .weightKilograms else { return }
            let addition = Double(weekOffset) * rule.weightIncrementKilograms
            if let old = exercise.targetWeightKilograms, old > 0 {
                exercise.targetWeightKilograms = roundedWeight(old + addition)
            }
            exercise.setTargets = exercise.setTargets?.map {
                var target = $0
                if let old = target.weightKilograms, old > 0 {
                    target.weightKilograms = roundedWeight(old + addition)
                }
                return target
            }

        case .repetitions:
            guard weekOffset > 0 else { return }
            let increase = weekOffset * rule.repetitionIncrement
            if let old = exercise.reps {
                exercise.reps = min(100, old + increase)
            }
            exercise.setTargets = exercise.setTargets?.map {
                var target = $0
                if let old = target.reps {
                    target.reps = min(100, old + increase)
                }
                return target
            }

        case .recovery:
            // Preserve all warmup sets and at least one working set. On
            // individual prescriptions, retain the surviving set IDs.
            let original = exercise.resolvedSetTargets
            let workCount = original.filter {
                $0.isWarmUp != true && $0.setType != .warmUp
            }.count
            guard workCount > 0 else { return }
            let keptWork = max(1, Int((Double(workCount) *
                                      rule.recoveryVolumeFactor).rounded()))
            var workSeen = 0
            var targets: [PlannedExerciseSetTarget] = []
            for var target in original {
                let isWarmup = target.isWarmUp == true || target.setType == .warmUp
                if !isWarmup {
                    guard workSeen < keptWork else { continue }
                    workSeen += 1
                    if exercise.resolvedLoadKind == .weightKilograms,
                       let weight = target.weightKilograms, weight > 0 {
                        target.weightKilograms = roundedWeight(
                            weight * rule.recoveryWeightFactor
                        )
                    }
                }
                targets.append(target)
            }
            let previousCount = exercise.sets
            exercise.sets = targets.count
            if exercise.hasIndividualSetTargets {
                exercise.setTargets = targets
            }
            if exercise.resolvedLoadKind == .weightKilograms,
               let old = exercise.targetWeightKilograms, old > 0,
               rule.recoveryWeightFactor < 1 {
                exercise.targetWeightKilograms = roundedWeight(
                    old * rule.recoveryWeightFactor
                )
            }
            // Where no volume reduction is possible, preserve the original
            // number and do not invent a target.
            if previousCount == 1 && targets.count == 1 &&
               exercise.targetWeightKilograms == nil {
                exercise.sets = previousCount
            }
        }
    }

    private static func roundedWeight(_ value: Double) -> Double {
        (max(0, value) * 2).rounded() / 2
    }

    private static func displayPrescription(_ workout: PlannedSession) -> String {
        let details = workout.exercises.prefix(2).map { item in
            let load = item.targetWeightKilograms.map { "\($0.formatted()) kg" }
            let reps = item.reps.map { "\($0) reps" }
            return "\(item.embeddedExercise.displayName): \(item.sets) sett"
                + [reps, load].compactMap { $0 }.map { " · " + $0 }.joined()
        }
        return details.joined(separator: " | ")
    }
}
