import Foundation

/// The advanced editor lets athletes tune individual sets without switching
/// workout formats. It replaces a compact exercise block with equivalent
/// executable exercise steps and explicit recovery blocks.
enum ATHLTHWorkoutSetExpansion {

    /// Maintain one exercise in the recipe, with a target for each set.
    /// Increasing the set count keeps earlier manual adjustments intact.
    static func targets(for block: WorkoutTemplateBlock) -> [ATHLTHStrengthSetTarget] {
        let count = min(max(block.setCount ?? 1, 1), 20)
        let existing = block.individualSetTargets ?? []
        return (0..<count).map { index in
            if existing.indices.contains(index) { return existing[index] }
            return ATHLTHStrengthSetTarget(
                repetitions: block.repetitions,
                weightKilograms: block.targetWeightKilograms
            )
        }
    }

    /// Older "Customize each set" drafts contained a sequence of independent
    /// exercise / between-sets rest blocks. Restore only that explicit pattern;
    /// adjacent exercises without matching rest markers remain independent.
    static func collapsingLegacySets(
        in blocks: [WorkoutTemplateBlock]
    ) -> [WorkoutTemplateBlock] {
        var result: [WorkoutTemplateBlock] = []
        var cursor = 0
        var changed = false
        while cursor < blocks.count {
            let first = blocks[cursor]
            guard first.kind == .exercise, first.groupID == nil,
                  first.setCount == nil else {
                result.append(first)
                cursor += 1
                continue
            }
            var sets = [first]
            var next = cursor + 1
            var restSeconds: TimeInterval?
            while next + 1 < blocks.count {
                let rest = blocks[next]
                let exercise = blocks[next + 1]
                let expectedRest = rest.kind == .rest &&
                    (rest.title == "Between sets" || rest.title == "Mellom sett")
                guard expectedRest, rest.groupID == nil,
                      exercise.kind == .exercise, exercise.groupID == nil,
                      exercise.setCount == nil,
                      exercise.exerciseSlug == first.exerciseSlug,
                      exercise.exerciseID == first.exerciseID,
                      exercise.title == first.title,
                      exercise.resolvedPhase == first.resolvedPhase,
                      exercise.durationSeconds == first.durationSeconds,
                      exercise.loadNote == first.loadNote,
                      exercise.notes == first.notes,
                      exercise.targetHeartRateZone == first.targetHeartRateZone,
                      exercise.targetEffortRPE == first.targetEffortRPE,
                      exercise.exerciseSnapshot == first.exerciseSnapshot,
                      sets.count < 20,
                      let seconds = rest.durationSeconds, seconds > 0,
                      restSeconds == nil || restSeconds == seconds else { break }
                restSeconds = seconds
                sets.append(exercise)
                next += 2
            }
            if sets.count > 1 {
                changed = true
                var parent = first
                parent.setCount = sets.count
                parent.restBetweenSetsSeconds = restSeconds
                parent.individualSetTargets = sets.map {
                    ATHLTHStrengthSetTarget(
                        repetitions: $0.repetitions,
                        weightKilograms: $0.targetWeightKilograms
                    )
                }
                result.append(parent)
                cursor = next
            } else {
                result.append(first)
                cursor += 1
            }
        }
        guard changed else { return blocks }
        return result.enumerated().map {
            ATHLTHWorkoutPhasePlacement.renumbered($0.element, sequence: $0.offset + 1)
        }
    }
    static func separateSets(in block: WorkoutTemplateBlock) -> [WorkoutTemplateBlock] {
        guard block.kind == .exercise,
              block.groupID == nil,
              let count = block.setCount,
              count > 1 else { return [block] }

        let repetitions = min(max(count, 1), 20)
        let recovery = max(block.restBetweenSetsSeconds ?? 0, 0)
        var steps: [WorkoutTemplateBlock] = []

        for index in 0..<repetitions {
            // Use one independently editable strength step per set.
            let set = WorkoutTemplateBlock(
                sequence: steps.count + 1,
                kind: .exercise,
                title: block.title,
                exerciseSlug: block.exerciseSlug,
                distanceMeters: block.distanceMeters,
                repetitions: block.repetitions,
                durationSeconds: block.durationSeconds,
                targetWeightKilograms: block.targetWeightKilograms,
                loadNote: block.loadNote,
                notes: block.notes,
                phase: block.phase,
                targetPaceSecondsPerKilometer: block.targetPaceSecondsPerKilometer,
                targetHeartRateZone: block.targetHeartRateZone
            )
            steps.append(set)

            if index < repetitions - 1 && recovery > 0 {
                steps.append(WorkoutTemplateBlock(
                    sequence: steps.count + 1,
                    kind: .rest,
                    title: ATHLTHLocalization.choose(
                        english: "Between sets", norwegian: "Mellom sett"
                    ),
                    exerciseSlug: nil, distanceMeters: nil,
                    repetitions: nil, durationSeconds: recovery,
                    targetWeightKilograms: nil, loadNote: nil,
                    notes: nil, phase: .recovery
                ))
            }
        }
        return steps
    }
}
