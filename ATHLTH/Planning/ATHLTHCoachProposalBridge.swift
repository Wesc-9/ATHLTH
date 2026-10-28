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

        let blocks: [WorkoutTemplateBlock] = proposal.steps.enumerated().compactMap {
            index, item in
            guard !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let phase = WorkoutPhaseKind(rawValue: item.phase),
                  (0...180).contains(item.minutes),
                  (0...20).contains(item.sets),
                  (0...100).contains(item.repetitions),
                  (0...600).contains(item.restSeconds) else { return nil }
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
            var block = WorkoutTemplateBlock(
                sequence: index + 1,
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
            if activity == "walking", blockKind == .run {
                block.cardioActivity = .walking
            }
            return block
        }
        guard blocks.count == proposal.steps.count else { return nil }
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
            trainingFocus: .generalFitness,
            gymAccess: nil,
            limitations: "",
            coachFocusNotes: proposal.summary + "\n" +
                "Training discipline: " + proposal.activity +
                ". Confirm any limitations, equipment and available days before saving.",
            selectedGoalIDs: []
        )
    }
}
