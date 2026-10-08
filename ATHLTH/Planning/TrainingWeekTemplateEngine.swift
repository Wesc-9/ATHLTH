import Foundation

/// Repeats a week into empty, upcoming calendar slots. Existing workouts and
/// historical dates are never replaced, even when the source week is edited.
enum TrainingWeekCopyScope {
    case nextWeek
    case allFutureWeeks
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
                        cloneSession($0, offsetWeeks: weekOffset, calendar: calendar)
                    }
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

    private static func cloneSession(
        _ source: PlannedSession,
        offsetWeeks: Int,
        calendar: Calendar
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
            return new
        }

        var clone = PlannedSession(
            id: UUID(),
            title: source.title,
            kind: source.kind,
            scheduledStart: source.scheduledStart.flatMap {
                calendar.date(byAdding: .weekOfYear, value: offsetWeeks, to: $0)
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
