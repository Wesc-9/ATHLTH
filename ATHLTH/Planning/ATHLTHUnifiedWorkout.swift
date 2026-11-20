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

        // Earlier simple plan versions represented timed workouts with
        // category + duration only. Adapt all explicitly supported non-run
        // activities to the SAME timeline, preserving the saved source ID
        // and labeling every measurement as manual/timed on iPhone.
        if blocks.isEmpty, let minutes = workout.durationMinutes,
           (1...240).contains(minutes) {
            let savedCategory = workout.workoutCategory?
                .trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            // Older simple mobility/recovery plans sometimes have only
            // WorkoutKind + duration, without an explicit category.
            let category: String
            switch savedCategory {
            case "" where workout.kind == .mobility:
                category = "mobility"
            case "" where workout.kind == .recovery:
                category = "recovery"
            case "stair_climbing":
                category = "stairclimber"
            case "stretching":
                category = "mobility"
            default:
                category = savedCategory
            }
            let taggedCategories = [
                "cycling", "rowing", "stairclimber", "hiit",
                "circuit", "functional", "sports", "other"
            ]
            let timedCategory = taggedCategories.contains(category) ||
                ["yoga", "meditation", "mobility", "recovery"].contains(category)
            if timedCategory {
                var timed = WorkoutTemplateBlock(
                    sequence: 1, kind: .note, title: workout.title,
                    exerciseSlug: nil, distanceMeters: nil,
                    repetitions: nil, durationSeconds: Double(minutes * 60),
                    targetWeightKilograms: nil, loadNote: nil,
                    notes: workout.notes, phase: .main
                )
                switch category {
                case "cycling", "rowing", "stairclimber", "hiit",
                     "circuit", "functional", "sports", "other":
                    timed.activityTag = category
                case "meditation", "recovery":
                    timed.wellnessKind = .meditation
                case "yoga": timed.wellnessKind = .yoga
                default: timed.wellnessKind = .mobility
                }
                blocks.append(timed)
            }
        }
        return blocks
    }

    /// A legacy simple cycling/rowing/HIIT/mobility/etc. plan may have a title,
    /// kind and duration but no encoded timeline. Project its timing into
    /// the shared structured player without changing the saved plan, its ID
    /// or creating a second HealthKit/Watch workout.
    ///
    /// All sensor values stay absent; iPhone marks this as a timed/manual
    /// structured completion. Other activity types keep their own recorder.
    static func timedNonCardioProjection(
        from workout: PlannedSession
    ) -> PlannedSession? {
        guard !workout.isStructuredWorkout else { return nil }
        let category = ATHLTHUnifiedActivityProfile.category(for: workout)
        guard [
            "cycling", "rowing", "stairclimber", "hiit", "circuit",
            "functional", "sports", "other", "mobility", "recovery"
        ].contains(category) else {
            return nil
        }
        let projectedBlocks = editorBlocks(from: workout)
        guard !projectedBlocks.isEmpty,
              projectedBlocks.allSatisfy({
                  $0.kind == .note || $0.kind == .rest
              }) else { return nil }
        var projected = workout
        projected.workoutBlocks = projectedBlocks
        // Keep the original workoutCategory and duration in persisted data.
        // The projection is used only during the selected live session.
        return projected
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
                // The single ATHLTH timeline must retain the AI strength
                // effort target on every set, not only in discarded prose.
                work.targetEffortRPE = (target.targetRPE ??
                    exercise.targetRPE).flatMap {
                        $0.isFinite && (1...10).contains($0) ? Int($0.rounded()) : nil
                    }
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
        // The same classifier now powers Plan Studio, Coach blueprints,
        // library filters and older saved workouts. Multiple activities
        // remain a single structured recipe with one immutable workout ID.
        let profile = ATHLTHUnifiedActivityProfile(
            blocks: blocks, fallbackKind: workout.kind
        )
        workout.workoutBlocks = blocks
        workout.kind = profile.workoutKind
        workout.workoutCategory = profile.category
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
