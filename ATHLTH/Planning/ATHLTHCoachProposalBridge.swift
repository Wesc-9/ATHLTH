import Foundation

/// Converts a validated Coach proposal into ATHLTH's real workout / plan
/// editors. Proposals never mutate a plan until the athlete explicitly acts.
enum ATHLTHCoachProposalBridge {
    static func workout(_ proposal: RecoveryCoachProposal) -> PlannedSession? {
        guard proposal.isWorkout,
              !proposal.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              (10...180).contains(proposal.durationMinutes),
              (1...20).contains(proposal.steps.count) else { return nil }

        let activity = proposal.activity
        let kind: WorkoutKind
        switch activity {
        case "running": kind = .running
        case "walking": kind = .walking
        case "strength": kind = .strength
        case "hybrid": kind = .custom
        default: return nil
        }

        // Reject malformed steps before constructing any ATHLTH workout data.
        guard proposal.steps.allSatisfy({ item in
            !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                WorkoutPhaseKind(rawValue: item.phase) != nil &&
                (0...180).contains(item.minutes) &&
                (0...20).contains(item.sets) &&
                (0...100).contains(item.repetitions) &&
                (0...600).contains(item.restSeconds)
        }) else { return nil }

        var blocks: [WorkoutTemplateBlock] = []
        for (index, item) in proposal.steps.enumerated() {
            guard let phase = WorkoutPhaseKind(rawValue: item.phase) else { return nil }
            let blockKind: WorkoutTemplateBlockKind
            if phase == .recovery && item.minutes > 0 && kind == .strength {
                blockKind = .rest
            } else if kind == .strength {
                blockKind = .exercise
            } else if activity == "hybrid" {
                blockKind = (item.sets > 0 || item.repetitions > 0) ? .exercise : .run
            } else {
                blockKind = .run
            }
            // A cardio step without any duration or distance cannot be
            // executed. Ask Coach for a better proposal instead of adding it.
            if blockKind == .run && item.minutes == 0 { return nil }
            var block = WorkoutTemplateBlock(
                sequence: blocks.count + 1,
                kind: blockKind,
                title: item.title,
                exerciseSlug: nil,
                distanceMeters: nil,
                repetitions: blockKind == .exercise && item.repetitions > 0
                    ? item.repetitions : nil,
                durationSeconds: item.minutes > 0
                    ? Double(item.minutes * 60) : nil,
                targetWeightKilograms: nil,
                loadNote: nil,
                notes: nil
            )
            block.phase = phase
            block.setCount = blockKind == .exercise && item.sets > 0
                ? item.sets : nil
            block.restBetweenSetsSeconds = blockKind == .exercise && item.restSeconds > 0
                ? Double(item.restSeconds) : nil
            if activity == "walking" && blockKind == .run {
                block.cardioActivity = .walking
            }
            blocks.append(block)

            // Run interval pauses must be real timeline steps, not discarded
            // text. An explicitly authored recovery step takes precedence.
            let nextIsRecovery = proposal.steps.indices.contains(index + 1) &&
                proposal.steps[index + 1].phase == "recovery"
            if blockKind == .run, phase == .main,
               item.restSeconds > 0, index < proposal.steps.count - 1,
               !nextIsRecovery {
                var pause = WorkoutTemplateBlock(
                    sequence: blocks.count + 1,
                    kind: .rest,
                    title: ATHLTHLocalization.choose(
                        english: "Recovery", norwegian: "Pause"
                    ),
                    exerciseSlug: nil,
                    distanceMeters: nil,
                    repetitions: nil,
                    durationSeconds: Double(item.restSeconds),
                    targetWeightKilograms: nil,
                    loadNote: nil,
                    notes: nil
                )
                pause.phase = .recovery
                blocks.append(pause)
            }
        }
        var result = PlannedSession(
            id: UUID(),
            title: String(proposal.title.prefix(110)),
            kind: kind,
            scheduledStart: nil,
            durationMinutes: proposal.durationMinutes,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil,
            exercises: [],
            notes: proposal.summary
        )
        result.workoutBlocks = blocks
        result.workoutCategory = activity
        return result
    }

    static func planSeed(_ proposal: RecoveryCoachProposal) -> AIProgramBuilderSeed? {
        guard proposal.isPlan,
              (1...52).contains(proposal.weekCount),
              (1...7).contains(proposal.sessionsPerWeek),
              (10...180).contains(proposal.durationMinutes) else { return nil }
        let days = Set(1...7)
        return AIProgramBuilderSeed(
            preferredTitle: proposal.title,
            startDate: Calendar.current.startOfDay(for: Date()),
            weekCount: proposal.weekCount,
            sessionsPerWeek: proposal.sessionsPerWeek,
            sessionDurationMinutes: max(20, proposal.durationMinutes),
            availableDays: days,
            trainingFocus: {
                switch proposal.activity {
                case "running": return .running
                case "walking": return .walking
                case "strength": return .strength
                case "hybrid": return .hybrid
                default: return .generalFitness
                }
            }(),
            gymAccess: nil,
            limitations: "",
            coachFocusNotes: proposal.summary + "\n" +
                "Training discipline: " + proposal.activity +
                ". Confirm any limitations, equipment and available days before saving.",
            selectedGoalIDs: []
        )
    }
}
