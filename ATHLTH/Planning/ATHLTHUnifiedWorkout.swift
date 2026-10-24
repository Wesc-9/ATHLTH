import Foundation

/// The ordered workout timeline is the single execution recipe for new
/// advanced ATHLTH sessions. Basic may still offer an unstructured quick start.
/// Conversion below is an editor bridge for plan-generated workout suggestions,
/// not an alternative format used during execution.
enum ATHLTHUnifiedWorkout {
    /// Every planner produces the same chronological phases. The run
    /// template continues to own its intervals, recovery, zone and pace
    /// targets; complementary exercises are inserted without modifying it.
    /// This is a non-destructive projection for previews and future engine
    /// handoffs. We do not run both a projected timeline and its source
    /// template as two separate recordings.
    static func editorBlocks(from workout: PlannedSession) -> [WorkoutTemplateBlock] {
        if !workout.resolvedWorkoutBlocks.isEmpty {
            return workout.resolvedWorkoutBlocks
        }

        var blocks: [WorkoutTemplateBlock] = []
        let runTemplates = workout.resolvedRunningWorkouts

        appendExercises(
            workout.exercises, phase: .warmup, to: &blocks
        )
        appendRunning(
            runTemplates, phase: .warmup, to: &blocks
        )
        appendRunning(
            runTemplates, phase: .main, to: &blocks
        )
        appendExercises(
            workout.exercises, phase: .main, to: &blocks
        )
        appendRunning(
            runTemplates, phase: .cooldown, to: &blocks
        )
        appendExercises(
            workout.exercises, phase: .cooldown, to: &blocks
        )

        if blocks.isEmpty,
           (workout.kind == .running || workout.kind == .walking),
           (workout.targetDistanceKilometers != nil ||
            workout.durationMinutes != nil) {
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

    private static func appendExercises(
        _ exercises: [PlannedExercise],
        phase: WorkoutPhaseKind,
        to blocks: inout [WorkoutTemplateBlock]
    ) {
        for exercise in exercises {
            let assigned = exercise.workoutPhase ??
                (exercise.isWarmUpExercise ? .warmup : .main)
            guard assigned == phase else { continue }
            let targets = exercise.resolvedSetTargets
            for (index, target) in targets.enumerated() {
                let setPhase: WorkoutPhaseKind = (target.isWarmUp == true ||
                    target.setType == .warmUp) ? .warmup : phase
                var work = WorkoutTemplateBlock(
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
                    phase: setPhase
                )
                work.exerciseID = exercise.exerciseID
                work.exerciseSnapshot = exercise.embeddedExercise
                blocks.append(work)

                if index < targets.count - 1 {
                    let restSeconds = target.restSeconds ??
                        exercise.restSeconds ?? 60
                    if restSeconds > 0 {
                        blocks.append(WorkoutTemplateBlock(
                            sequence: blocks.count + 1,
                            kind: .rest,
                            title: ATHLTHLocalization.choose(
                                english: "Between sets", norwegian: "Mellom sett"
                            ),
                            exerciseSlug: nil, distanceMeters: nil,
                            repetitions: nil,
                            durationSeconds: Double(restSeconds),
                            targetWeightKilograms: nil,
                            loadNote: nil, notes: nil, phase: .recovery
                        ))
                    }
                }
            }
        }
    }

    private static func appendRunning(
        _ templates: [RunningWorkoutTemplate],
        phase: WorkoutPhaseKind,
        to blocks: inout [WorkoutTemplateBlock]
    ) {
        for template in templates {
            for interval in template.blocks {
                let blockPhase: WorkoutPhaseKind
                switch interval.kind {
                case .warmup: blockPhase = .warmup
                case .cooldown: blockPhase = .cooldown
                case .recovery, .work, .steady: blockPhase = .main
                }
                guard blockPhase == phase else { continue }
                for repetition in 1...min(max(interval.repetitions, 1), 60) {
                    let target = interval.resolvedWork(at: repetition)
                    let stepPhase: WorkoutPhaseKind =
                        interval.kind == .recovery ? .recovery : blockPhase
                    blocks.append(step(
                        target, title: interval.title,
                        phase: stepPhase, sequence: blocks.count + 1,
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
        let hasCycling = blocks.contains { $0.activityTag == "cycling" }
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
        // A cycling step is a timed non-running activity, not a strength
        // exercise. Until WorkoutKind has a dedicated cycling case, use
        // custom with an explicit cycling category instead of mislabelling it.
        let cyclingOnly = hasCycling && !hasCardio && !hasStrength && wellness.isEmpty
        workout.kind = hasCycling || (hasStrength && hasCardio) ||
            (effectiveWalking && effectiveRunning)
            ? .custom
            : effectiveWalking && !effectiveRunning ? .walking
            : effectiveRunning ? .running
            : !wellness.isEmpty ? wellnessKind
            : (plannedKind == .mobility ? .mobility : .strength)
        workout.workoutCategory = cyclingOnly ? "cycling" :
            workout.kind == .custom ? "hybrid" :
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
        var block = WorkoutTemplateBlock(
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
        block.treadmillInclinePercent = target.treadmillInclinePercent
        if target.treadmillInclinePercent != nil { block.isIndoor = true }
        return block
    }
}
