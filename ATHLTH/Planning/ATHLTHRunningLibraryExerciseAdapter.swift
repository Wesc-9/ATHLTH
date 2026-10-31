import Foundation

/// Make the library's Running cardio exercise use the exact same run step
/// editor and execution model as 'Add running exercise'. This also upgrades
/// an older Running row when the athlete explicitly opens it for editing.
enum ATHLTHRunningLibraryExerciseAdapter {
    static func adapt(_ source: WorkoutTemplateBlock) -> WorkoutTemplateBlock {
        guard source.kind == .exercise, source.groupID == nil else { return source }
        let normalized = source.title.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard normalized == "running" || normalized == "løping" else { return source }

        var block = source
        block.kind = .run
        block.cardioActivity = .running
        block.title = ATHLTHLocalization.choose(english: "Running", norwegian: "Løping")
        block.setCount = nil
        block.restBetweenSetsSeconds = nil
        block.repetitions = nil
        block.targetWeightKilograms = nil
        block.loadNote = nil
        if block.durationSeconds == nil && block.distanceMeters == nil {
            block.durationSeconds = 600
        }
        // Retain exerciseID, exerciseSlug and shareable exerciseSnapshot:
        // the user's original library selection is not lost.
        return block
    }
}
