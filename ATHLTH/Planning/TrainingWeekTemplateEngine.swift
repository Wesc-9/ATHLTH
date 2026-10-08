import Foundation

/// Repeats a week into empty, upcoming calendar slots. Existing workouts and
/// historical dates are never replaced, even when the source week is edited.
enum TrainingWeekCopyScope {
    case nextWeek
    case allFutureWeeks
}

/// Opt-in target progression when the user repeats a training week.
enum TrainingWeekProgressionMode: Equatable {
    case unchanged
    case addWeightPerWeek(Double)
    case addRepsPerWeek(Int)
    /// Three strength-loading weeks followed by one deload week, repeated.
    /// Does not touch running targets or workouts already placed in the plan.
    case fourWeekStrengthBlock
}

struct TrainingWeekCopySummary: Equatable {
    var targetWeeks: Int = 0
    var filledDays: Int = 0
    var copiedSessions: Int = 0

    var hasWork: Bool { copiedSessions > 0 }
}

enum TrainingWeekTemplateEngine {
    static func preview(
        plan: TrainingPlan,
        sourceWeekID: UUID,
        scope: TrainingWeekCopyScope,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> TrainingWeekCopySummary {
        guard let sourceIndex = plan.weeks.firstIndex(where: { $0.id == sourceWeekID }),
              sourceIndex + 1 < plan.weeks.count,
              let startDate = plan.startDate else {
            return TrainingWeekCopySummary()
        }

        let source = plan.weeks[sourceIndex]
        let targetIndexes = targetWeekIndexes(
            sourceIndex: sourceIndex,
            weekCount: plan.weeks.count,
            scope: scope
        )
        let today = calendar.startOfDay(for: now)
        let planStart = calendar.startOfDay(for: startDate)
        var summary = TrainingWeekCopySummary()

        for targetIndex in targetIndexes {
            let target = plan.weeks[targetIndex]
            var filledThisWeek = false
            for targetDay in target.days where targetDay.sessions.isEmpty {
                guard let matchingSource = source.days.first(where: {
                    $0.dayIndex == targetDay.dayIndex
                }), !matchingSource.sessions.isEmpty else { continue }

                let offset = target.weekNumber > 0
                    ? (target.weekNumber - 1) * 7 + targetDay.dayIndex - 1
                    : targetIndex * 7 + targetDay.dayIndex - 1
                guard let scheduledDay = calendar.date(
                    byAdding: .day,
                    value: offset,
                    to: planStart
                ), scheduledDay >= today else {
                    continue
                }

                summary.filledDays += 1
                summary.copiedSessions += matchingSource.sessions.count
                filledThisWeek = true
            }
            if filledThisWeek {
                summary.targetWeeks += 1
            }
        }
        return summary
    }

    static func copy(
        plan: TrainingPlan,
        sourceWeekID: UUID,
        scope: TrainingWeekCopyScope,
        progression: TrainingWeekProgressionMode = .unchanged,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> (plan: TrainingPlan, summary: TrainingWeekCopySummary)? {
        let expected = preview(
            plan: plan,
            sourceWeekID: sourceWeekID,
            scope: scope,
            now: now,
            calendar: calendar
        )
        guard expected.hasWork,
              let sourceIndex = plan.weeks.firstIndex(where: { $0.id == sourceWeekID })
        else { return nil }

        var updated = plan
        let source = plan.weeks[sourceIndex]
        let today = calendar.startOfDay(for: now)
        let planStart = calendar.startOfDay(for: plan.startDate ?? now)
        let indexes = targetWeekIndexes(
            sourceIndex: sourceIndex,
            weekCount: plan.weeks.count,
            scope: scope
        )

        for targetIndex in indexes {
            let weekOffset = targetIndex - sourceIndex
            var copiedStrengthSessions = false
            let hadExistingStrength = updated.weeks[targetIndex].days
                .flatMap(\.sessions).contains { $0.kind == .strength }
            for dayIndex in updated.weeks[targetIndex].days.indices {
                let targetDay = updated.weeks[targetIndex].days[dayIndex]
                guard targetDay.sessions.isEmpty,
                      let sourceDay = source.days.first(where: {
                          $0.dayIndex == targetDay.dayIndex
                      }), !sourceDay.sessions.isEmpty
                else { continue }

                let offset = max(updated.weeks[targetIndex].weekNumber - 1, 0) * 7
                    + targetDay.dayIndex - 1
                guard let scheduledDay = calendar.date(
                    byAdding: .day,
                    value: offset,
                    to: planStart
                ), scheduledDay >= today else { continue }

                updated.weeks[targetIndex].days[dayIndex].sessions =
                    sourceDay.sessions.map {
                        cloneSession(
                            $0,
                            offsetWeeks: weekOffset,
                            scheduledDay: scheduledDay,
                            calendar: calendar,
                            progression: progression
                        )
                    }
                if sourceDay.sessions.contains(where: { $0.kind == .strength }) {
                    copiedStrengthSessions = true
                }
            }

            // Mark only weeks whose strength sessions came from this block.
            // Partial future weeks with their own strength sessions remain
            // unmarked to avoid implying a complete deload prescription.
            if case .fourWeekStrengthBlock = progression,
               copiedStrengthSessions && !hadExistingStrength {
                updated.weeks[targetIndex].strengthPhase =
                    strengthPhase(forWeekOffset: weekOffset)
            }
        }

        return (updated, expected)
    }

    private static func targetWeekIndexes(
        sourceIndex: Int,
        weekCount: Int,
        scope: TrainingWeekCopyScope
    ) -> [Int] {
        guard sourceIndex + 1 < weekCount else { return [] }
        switch scope {
        case .nextWeek:
            return [sourceIndex + 1]
        case .allFutureWeeks:
            return Array((sourceIndex + 1)..<weekCount)
        }
    }

    /// Offset 1-2 build; offset 3 deload; repeat every four weeks.
    static func strengthPhase(forWeekOffset offset: Int) -> TrainingWeekStrengthPhase {
        offset % 4 == 3 ? .deload : .build
    }

    private static func applyUserSelectedProgression(
        to exercise: inout PlannedExercise,
        offsetWeeks: Int,
        mode: TrainingWeekProgressionMode
    ) {
        guard offsetWeeks > 0 else { return }

        switch mode {
        case .unchanged:
            break
        case .fourWeekStrengthBlock:
            if strengthPhase(forWeekOffset: offsetWeeks) == .deload {
                // The recovery week of later blocks keeps the previous
                // block's baseline rather than resetting to week one.
                let completedBlocks = offsetWeeks / 4
                if exercise.resolvedTargetKind == .reps {
                    addPrescribedWeight(
                        to: &exercise,
                        amount: Double(completedBlocks * 2) * 2.5
                    )
                }
                applyDeload(to: &exercise, weightFactor: 0.9)
            } else if exercise.resolvedTargetKind == .reps &&
                        exercise.resolvedLoadKind == .weightKilograms {
                // Two 2.5 kg increases per cycle; after the recovery week
                // a new cycle builds from the previous cycle's final load.
                let cycle = offsetWeeks / 4
                let weekInCycle = offsetWeeks % 4
                let earnedSteps = cycle * 2 + min(weekInCycle, 2)
                addPrescribedWeight(
                    to: &exercise,
                    amount: Double(earnedSteps) * 2.5
                )
            }
        case .addWeightPerWeek(let increment):
            guard exercise.resolvedTargetKind == .reps,
                  exercise.resolvedLoadKind == .weightKilograms,
                  increment > 0 else { return }
            addPrescribedWeight(
                to: &exercise,
                amount: increment * Double(offsetWeeks)
            )
        case .addRepsPerWeek(let increment):
            guard exercise.resolvedTargetKind == .reps,
                  increment > 0 else { return }
            let total = offsetWeeks * increment
            if let original = exercise.reps {
                exercise.reps = min(original + total, 100)
            }
            exercise.setTargets = exercise.setTargets?.map { target in
                var adjusted = target
                if let original = adjusted.reps {
                    adjusted.reps = min(original + total, 100)
                }
                return adjusted
            }
        }
    }

    private static func addPrescribedWeight(
        to exercise: inout PlannedExercise,
        amount: Double
    ) {
        guard amount > 0, exercise.resolvedLoadKind == .weightKilograms else {
            return
        }
        if let weight = exercise.targetWeightKilograms {
            exercise.targetWeightKilograms = max(0, weight + amount)
        }
        exercise.setTargets = exercise.setTargets?.map { target in
            var updated = target
            if let weight = updated.weightKilograms {
                updated.weightKilograms = max(0, weight + amount)
            }
            return updated
        }
    }

    private static func applyDeload(
        to exercise: inout PlannedExercise,
        weightFactor: Double
    ) {
        // Only real work sets are reduced. Never erase every working set or
        // turn unprescribed load into an invented weight target.
        let resolved = exercise.resolvedSetTargets
        let workCount = resolved.filter {
            $0.isWarmUp != true && $0.setType != .warmUp
        }.count
        guard workCount > 0 else { return }

        let keepWorkCount = max(1, Int((Double(workCount) * 0.6).rounded()))
        var keptWorkSets = 0
        var kept: [PlannedExerciseSetTarget] = []

        for target in resolved {
            let isWarmUp = target.isWarmUp == true || target.setType == .warmUp
            if !isWarmUp {
                guard keptWorkSets < keepWorkCount else { continue }
                keptWorkSets += 1
            }

            var adjusted = target
            if exercise.resolvedLoadKind == .weightKilograms,
               let weight = adjusted.weightKilograms {
                // Warmup sets remain unchanged.
                if !isWarmUp {
                    adjusted.weightKilograms = (weight * weightFactor * 2)
                        .rounded() / 2
                }
            }
            kept.append(adjusted)
        }

        exercise.sets = kept.count
        if exercise.hasIndividualSetTargets {
            exercise.setTargets = kept
        }
        if exercise.resolvedLoadKind == .weightKilograms,
           let weight = exercise.targetWeightKilograms {
            exercise.targetWeightKilograms = (weight * weightFactor * 2)
                .rounded() / 2
        }
    }

    private static func cloneSession(
        _ source: PlannedSession,
        offsetWeeks: Int,
        scheduledDay: Date,
        calendar: Calendar,
        progression: TrainingWeekProgressionMode
    ) -> PlannedSession {
        var supersetIDMap: [UUID: UUID] = [:]
        let exercises: [PlannedExercise] = source.exercises.map { old in
            var new = PlannedExercise(
                id: UUID(),
                exerciseID: old.exerciseID,
                embeddedExercise: old.embeddedExercise,
                sets: old.sets,
                reps: old.reps,
                targetWeightKilograms: old.targetWeightKilograms,
                targetRPE: old.targetRPE,
                restSeconds: old.restSeconds,
                notes: old.notes,
                targetRIR: old.targetRIR,
                supersetGroupID: old.supersetGroupID.map { original in
                    if let mapped = supersetIDMap[original] { return mapped }
                    let next = UUID()
                    supersetIDMap[original] = next
                    return next
                },
                progression: old.progression
            )
            new.targetKind = old.targetKind
            new.targetDurationSeconds = old.targetDurationSeconds
            new.loadKind = old.loadKind
            new.targetResistanceLevel = old.targetResistanceLevel
            new.setTargets = old.setTargets?.map { target in
                PlannedExerciseSetTarget(
                    id: UUID(),
                    reps: target.reps,
                    durationSeconds: target.durationSeconds,
                    weightKilograms: target.weightKilograms,
                    resistanceLevel: target.resistanceLevel,
                    restSeconds: target.restSeconds,
                    targetRPE: target.targetRPE,
                    targetRIR: target.targetRIR,
                    isWarmUp: target.isWarmUp,
                    setType: target.setType,
                    tempo: target.tempo,
                    notes: target.notes
                )
            }
            if source.kind == .strength {
                applyUserSelectedProgression(
                    to: &new,
                    offsetWeeks: offsetWeeks,
                    mode: progression
                )
            }
            return new
        }

        var clone = PlannedSession(
            id: UUID(),
            title: source.title,
            kind: source.kind,
            scheduledStart: source.scheduledStart.flatMap { original in
                let clock = calendar.dateComponents(
                    [.hour, .minute, .second],
                    from: original
                )
                return calendar.date(
                    bySettingHour: clock.hour ?? 18,
                    minute: clock.minute ?? 0,
                    second: clock.second ?? 0,
                    of: scheduledDay
                )
            },
            durationMinutes: source.durationMinutes,
            targetDistanceKilometers: source.targetDistanceKilometers,
            targetPaceSecondsPerKilometer: source.targetPaceSecondsPerKilometer,
            routeID: source.routeID,
            exercises: exercises,
            notes: source.notes,
            runningWorkout: source.runningWorkout
        )
        clone.runningWorkouts = source.runningWorkouts
        clone.gearIDs = source.gearIDs
        clone.audioCoachConfiguration = source.audioCoachConfiguration
        clone.autoPauseEnabled = source.autoPauseEnabled
        clone.spotifyPlaylist = source.spotifyPlaylist
        clone.spotifyAutoplayOnStart = source.spotifyAutoplayOnStart
        clone.targetAlertConfiguration = source.targetAlertConfiguration
        clone.routeAlertConfiguration = source.routeAlertConfiguration
        clone.ghostTargetDurationSeconds = source.ghostTargetDurationSeconds
        clone.ghostUpdates = source.ghostUpdates
        clone.workoutTemplateID = source.workoutTemplateID
        clone.workoutBlocks = source.workoutBlocks
        clone.workoutCategory = source.workoutCategory
        // A copied workout is an independent planned session, not a newly
        // shared session from another athlete.
        clone.sharedSourceOwnerID = nil
        clone.sharedSourceSessionID = nil
        return clone
    }
}
