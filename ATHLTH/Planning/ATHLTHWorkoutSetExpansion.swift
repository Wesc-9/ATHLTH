import Foundation

/// The advanced editor lets athletes tune individual sets without switching
/// workout formats. It replaces a compact exercise block with equivalent
/// executable exercise steps and explicit recovery blocks.
enum ATHLTHWorkoutSetExpansion {
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
