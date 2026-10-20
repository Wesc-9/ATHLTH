import Foundation

/// The ordered workout timeline is the single execution recipe for new
/// advanced ATHLTH sessions. Basic may still offer an unstructured quick start.
/// Conversion below is an editor bridge for plan-generated workout suggestions,
/// not an alternative format used during execution.
enum ATHLTHUnifiedWorkout {
    static func editorBlocks(from workout: PlannedSession) -> [WorkoutTemplateBlock] {
        if !workout.resolvedWorkoutBlocks.isEmpty {
            return workout.resolvedWorkoutBlocks
        }

        var blocks: [WorkoutTemplateBlock] = []

        // A suggested strength session is expanded into individually editable
        // sets, so every load / repetition / recovery is visible on the timeline.
        for exercise in workout.exercises {
            let targets = exercise.resolvedSetTargets
            for (index, target) in targets.enumerated() {
                let work = WorkoutTemplateBlock(
                    sequence: blocks.count + 1,
                    kind: .exercise,
                    title: exercise.embeddedExercise.name,
                    exerciseSlug: nil,
                    distanceMeters: nil,
                    repetitions: target.reps ?? exercise.reps,
                    durationSeconds: target.durationSeconds.map(Double.init),
                    targetWeightKilograms:
                        target.weightKilograms ?? exercise.targetWeightKilograms,
                    loadNote: nil,
                    notes: target.notes ?? exercise.notes,
                    phase: (target.isWarmUp ?? false) ? .warmup : .main
                )
                var linkedWork = work
                linkedWork.exerciseID = exercise.exerciseID
                linkedWork.exerciseSnapshot = exercise.embeddedExercise
                blocks.append(linkedWork)

                if index < targets.count - 1 {
                    let pauseSeconds = target.restSeconds ??
                        exercise.restSeconds ?? 60
                    if pauseSeconds > 0 {
                        blocks.append(WorkoutTemplateBlock(
                            sequence: blocks.count + 1, kind: .rest,
                            title: ATHLTHLocalization.choose(
                                english: "Between sets", norwegian: "Mellom sett"
                            ),
                            exerciseSlug: nil, distanceMeters: nil,
                            repetitions: nil,
                            durationSeconds: Double(pauseSeconds),
                            targetWeightKilograms: nil,
                            loadNote: nil, notes: nil, phase: .recovery
                        ))
                    }
                }
            }
        }

        // Turn old plan-generated running intervals into the same ordered
        // structure, including per-effort overrides and explicit recoveries.
        for template in workout.resolvedRunningWorkouts {
            for interval in template.blocks {
                for repetition in 1...min(max(interval.repetitions, 1), 60) {
                    let target = interval.resolvedWork(at: repetition)
                    let phase: WorkoutPhaseKind
                    switch interval.kind {
                    case .warmup: phase = .warmup
                    case .cooldown: phase = .cooldown
                    case .recovery: phase = .recovery
                    case .work, .steady: phase = .main
                    }
                    blocks.append(step(
                        target, title: interval.title,
                        phase: phase, sequence: blocks.count + 1,
                        notes: interval.notes
                    ))
                    if let rest = interval.resolvedRecovery(after: repetition) {
                        blocks.append(step(
                            rest,
                            title: ATHLTHLocalization.choose(
                                english: "Recovery", norwegian: "Pause"
                            ),
                            phase: .recovery, sequence: blocks.count + 1
                        ))
                    }
                }
            }
        }

        if blocks.isEmpty,
           workout.kind == .running || workout.kind == .walking,
           workout.targetDistanceKilometers != nil ||
           workout.durationMinutes != nil {
            blocks.append(WorkoutTemplateBlock(
                sequence: 1, kind: .run, title: workout.kind.title,
                exerciseSlug: nil,
                distanceMeters: workout.targetDistanceKilometers.map { $0 * 1_000 },
                repetitions: nil,
                durationSeconds: workout.targetDistanceKilometers == nil
                    ? workout.durationMinutes.map { Double($0 * 60) } : nil,
                targetWeightKilograms: nil, loadNote: nil,
                notes: workout.notes, phase: .main,
                targetPaceSecondsPerKilometer: workout.targetPaceSecondsPerKilometer
            ))
        }

        return blocks
    }

    /// Strip parallel exercise and running representations when accepting a
    /// structured timeline. Nothing can be executed twice.
    static func apply(
        blocks: [WorkoutTemplateBlock],
        title: String,
        routeID: UUID?,
        estimatedMinutes: Int?,
        to workout: inout PlannedSession
    ) {
        let hasCardio = blocks.contains { $0.kind == .run }
        let hasWalking = blocks.contains {
            $0.kind == .run && $0.cardioActivity == .walking
        }
        let hasRunning = blocks.contains {
            $0.kind == .run && $0.cardioActivity != .walking
        }
        let hasStrength = blocks.contains { $0.kind == .exercise }
        let wellness = blocks.compactMap(\.wellnessKind)
        let wellnessKind: WorkoutKind = wellness.allSatisfy({ $0 == .meditation })
            ? .recovery : .mobility

        workout.workoutBlocks = blocks
        let plannedKind = workout.kind
        // Old walking sessions used .run timeline blocks without a mode tag.
        let legacyWalking = plannedKind == .walking && hasCardio && !hasWalking &&
            blocks.filter { $0.kind == .run }.allSatisfy { $0.cardioActivity == nil }
        let effectiveWalking = hasWalking || legacyWalking
        let effectiveRunning = hasRunning && !legacyWalking
        workout.kind = (hasStrength && hasCardio) || (effectiveWalking && effectiveRunning)
            ? .custom
            : effectiveWalking && !effectiveRunning ? .walking
            : effectiveRunning ? .running
            : !wellness.isEmpty ? wellnessKind
            : (plannedKind == .mobility ? .mobility : .strength)
        workout.workoutCategory = workout.kind == .custom ? "hybrid" :
            workout.kind == .walking ? "walking" :
            workout.kind == .running ? "running" :
            (workout.kind == .mobility ? "mobility" :
               workout.kind == .recovery ? "recovery" : "strength")
        workout.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty ? workout.kind.title : title
        workout.routeID = blocks.contains { $0.kind == .run && $0.isIndoor != true } ? routeID : nil
        workout.durationMinutes = estimatedMinutes ?? workout.durationMinutes
        workout.exercises = []
        workout.runningWorkout = nil
        workout.runningWorkouts = nil
        workout.targetDistanceKilometers = nil
        workout.targetPaceSecondsPerKilometer = nil
    }

    private static func step(
        _ target: RunningStepTarget,
        title: String,
        phase: WorkoutPhaseKind,
        sequence: Int,
        notes: String? = nil
    ) -> WorkoutTemplateBlock {
        WorkoutTemplateBlock(
            sequence: sequence,
            kind: target.measure == .time && phase == .recovery ? .rest : .run,
            title: title,
            exerciseSlug: nil,
            distanceMeters: target.distanceMeters,
            repetitions: nil,
            durationSeconds: target.durationSeconds,
            targetWeightKilograms: nil,
            loadNote: nil,
            notes: notes,
            phase: phase,
            targetPaceSecondsPerKilometer:
                target.intensity.paceMinSecondsPerKilometer,
            targetHeartRateZone: target.intensity.heartRateZone
        )
    }
}
