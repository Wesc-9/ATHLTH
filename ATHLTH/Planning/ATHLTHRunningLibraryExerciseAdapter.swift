import Foundation

/// Make the library's Running cardio exercise use the exact same run step
/// editor and execution model as 'Add running exercise'. This also upgrades
/// an older Running row when the athlete explicitly opens it for editing.
enum ATHLTHRunningLibraryExerciseAdapter {
    static func adapt(_ source: WorkoutTemplateBlock) -> WorkoutTemplateBlock {
        guard source.kind == .exercise, source.groupID == nil else { return source }
        let normalized = source.title.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let isTreadmill = [
            "treadmill", "treadmill running", "treadmill run",
            "running on a treadmill", "running (treadmill)",
            "løping på tredemølle", "løp på tredemølle", "tredemølle"
        ].contains(normalized)
        let isRunning = [
            "running", "run", "løping", "løp", "jogging", "jogg"
        ].contains(normalized)
        guard isRunning || isTreadmill else { return source }

        var block = source
        block.kind = .run
        block.cardioActivity = .running
        block.title = isTreadmill
            ? ATHLTHLocalization.choose(
                english: "Treadmill running", norwegian: "Løping på tredemølle"
            )
            : ATHLTHLocalization.choose(english: "Running", norwegian: "Løping")
        if isTreadmill {
            block.isIndoor = true
            block.treadmillInclinePercent = block.treadmillInclinePercent ?? 0
            block.targetPaceSecondsPerKilometer =
                block.targetPaceSecondsPerKilometer ?? 360
        }
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
