import Foundation

/// Applies ATHLTH Coach suggestions to an *existing* advanced, dated plan.
/// The athlete's completed workouts, explicit rest days and week-specific
/// choices always win over generated content.
enum ATHLTHGuidedPlanAutofill {
    struct Proposal {
        let edits: [Int: ATHLTHPlanWeekDayEdit]
        let filledDays: Int
        let addedWorkouts: Int
        let restDays: Int

        var hasChanges: Bool { filledDays > 0 }
    }

    enum ProposalError: LocalizedError {
        case incompleteSchedule
        case invalidWorkout

        var errorDescription: String? {
            switch self {
            case .incompleteSchedule:
                return ATHLTHLocalization.choose(
                    english: "ATHLTH Coach returned an incomplete weekly plan. Nothing was changed.",
                    norwegian: "ATHLTH Coach leverte en ufullstendig ukeplan. Ingenting ble endret."
                )
            case .invalidWorkout:
                return ATHLTHLocalization.choose(
                    english: "One of the suggested workouts has no usable exercises or targets. Nothing was changed.",
                    norwegian: "En foreslått økt mangler brukbart innhold. Ingenting ble endret."
                )
            }
        }
    }

    /// Keys are weekIndex * 7 + calendar weekday (Monday = 1).
    /// An existing edit, even a rest day, cannot be replaced by AI.
    static func propose(
        _ draft: AIProgramDraft,
        existing: [Int: ATHLTHPlanWeekDayEdit],
        protectedWeekdays: Set<Int>,
        weekCount: Int,
        defaultSessionMinutes: Int
    ) throws -> Proposal {
        guard (1...52).contains(weekCount), draft.weeks.count == weekCount else {
            throw ProposalError.incompleteSchedule
        }

        var edits = existing
        var addedWorkouts = 0
        var filledDays = 0
        var restDays = 0

        for (weekIndex, week) in draft.weeks.enumerated() {
            let indices = week.days.map(\.dayIndex)
            guard indices.count == 7, Set(indices) == Set(1...7) else {
                throw ProposalError.incompleteSchedule
            }
            for day in week.days {
                let key = weekIndex * 7 + day.dayIndex
                guard edits[key] == nil,
                      !protectedWeekdays.contains(day.dayIndex) else { continue }

                if day.sessions.isEmpty {
                    var rest = ATHLTHPlanWeekDayEdit()
                    rest.isRestDay = true
                    edits[key] = rest
                    restDays += 1
                    filledDays += 1
                    continue
                }

                let workouts = day.sessions.compactMap {
                    blueprint(for: $0, defaultMinutes: defaultSessionMinutes)
                }
                // No partial AI day: if a suggestion cannot be represented
                // in the shared workout engine, reject the entire proposal.
                guard workouts.count == day.sessions.count else {
                    throw ProposalError.invalidWorkout
                }
                var edit = ATHLTHPlanWeekDayEdit()
                edit.isRestDay = false
                edit.detailedWorkout = workouts[0]
                edit.additionalDetailedWorkouts = Array(workouts.dropFirst())
                edit.kind = workouts[0].kind
                edit.title = workouts[0].title
                edit.durationMinutes = workouts[0].durationMinutes
                edits[key] = edit
                addedWorkouts += workouts.count
                filledDays += 1
            }
        }
        return Proposal(
            edits: edits, filledDays: filledDays,
            addedWorkouts: addedWorkouts, restDays: restDays
        )
    }

    private static func blueprint(
        for proposed: AIProgramDraftSession,
        defaultMinutes: Int
    ) -> ATHLTHPlanStructuredWorkoutBlueprint? {
        var workout = proposed.makePlannedSession()
        let minutes = min(max(
            workout.durationMinutes ?? defaultMinutes, 5
        ), 240)
        workout.durationMinutes = minutes
        var blocks = ATHLTHUnifiedWorkout.editorBlocks(from: workout)

        // Older Coach versions may return a run duration without explicit
        // timeline blocks. Keep it editable in the one shared workout engine.
        if blocks.isEmpty,
           workout.kind == .running || workout.kind == .walking {
            var block = WorkoutTemplateBlock(
                sequence: 1, kind: .run,
                title: workout.title,
                exerciseSlug: nil,
                distanceMeters: workout.targetDistanceKilometers.map { $0 * 1_000 },
                repetitions: nil,
                durationSeconds: workout.targetDistanceKilometers == nil
                    ? Double(minutes * 60) : nil,
                targetWeightKilograms: nil,
                loadNote: nil, notes: nil, phase: .main
            )
            block.cardioActivity = workout.kind == .walking ? .walking : .running
            blocks = [block]
        }
        let blueprint = ATHLTHPlanStructuredWorkoutBlueprint(
            title: String(proposed.title.prefix(120)),
            kind: workout.kind,
            durationMinutes: minutes,
            routeID: nil,
            blocks: blocks
        )
        return blueprint.isValid ? blueprint : nil
    }

    /// Copies a completed week to up to 'numberOfWeeks' later weeks,
    /// never overwriting individually planned workouts or rest days.
    static func copy(
        from sourceWeek: Int,
        into edits: [Int: ATHLTHPlanWeekDayEdit],
        numberOfWeeks: Int,
        totalWeeks: Int
    ) -> [Int: ATHLTHPlanWeekDayEdit] {
        guard sourceWeek >= 0, sourceWeek < totalWeeks - 1,
              numberOfWeeks > 0 else { return edits }
        var copied = edits
        let last = min(totalWeeks - 1, sourceWeek + numberOfWeeks)
        for week in (sourceWeek + 1)...last {
            for weekday in 1...7 {
                let sourceKey = sourceWeek * 7 + weekday
                let targetKey = week * 7 + weekday
                guard copied[targetKey] == nil, let source = edits[sourceKey] else {
                    continue
                }
                copied[targetKey] = source
            }
        }
        return copied
    }
}
