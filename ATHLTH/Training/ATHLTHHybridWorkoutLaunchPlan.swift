import Foundation

/// Safe bridge from the unified planner to the existing one-session hybrid
/// strength recorder. Each part is appended to ONE parent StrengthWorkoutLog;
/// parts are not separate HealthKit workouts. GPS/distance-only runs are
/// intentionally unsupported until a single HealthKit capture coordinator
/// can cover outdoor and strength metrics reliably.
enum ATHLTHHybridWorkoutLaunchPlan {
    static func isCandidate(_ workout: PlannedSession) -> Bool {
        let projected = ATHLTHUnifiedWorkout.editorBlocks(from: workout)
        return projected.contains(where: { $0.kind == .run }) &&
            projected.contains(where: { $0.kind == .exercise })
    }

    static func parts(for workout: PlannedSession) -> [PlannedSession]? {
        guard isCandidate(workout),
              workout.routeID == nil,
              workout.resolvedRunningWorkouts.allSatisfy({ $0.routeID == nil })
        else { return nil }

        // No silent outdoor->treadmill conversion: a clear treadmill marker
        // is required before the user can start a mixed live recording.
        let sourceBlocks = workout.resolvedWorkoutBlocks
        let explicitlyIndoor = workout.workoutCategory == "treadmill" ||
            sourceBlocks.filter({ $0.kind == .run })
                .allSatisfy({ $0.isIndoor == true }) &&
            sourceBlocks.contains(where: { $0.kind == .run })
        guard explicitlyIndoor else { return nil }

        let result: [PlannedSession]
        if !sourceBlocks.isEmpty {
            // Advanced blocks already describe the exact ordering.
            // Keep contiguous movement types as one component, retaining
            // recovery with the preceding motor.
            guard !sourceBlocks.contains(where: { $0.kind == .note }) else {
                return nil
            }
            var groups: [[WorkoutTemplateBlock]] = []
            var mode: WorkoutTemplateBlockKind?
            for block in sourceBlocks {
                let nextMode: WorkoutTemplateBlockKind =
                    block.kind == .rest ? (mode ?? .rest) : block.kind
                if !groups.isEmpty && nextMode == mode {
                    groups[groups.count - 1].append(block)
                } else {
                    groups.append([block])
                    mode = nextMode
                }
            }
            // A leading standalone pause cannot be represented faithfully.
            guard groups.allSatisfy({
                $0.contains(where: { $0.kind == .run || $0.kind == .exercise })
            }) else { return nil }
            result = groups.map { group in
                var part = stripped(workout)
                part.workoutBlocks = group
                part.kind = group.contains(where: { $0.kind == .run })
                    ? .running : .strength
                return part
            }
        } else {
            // Legacy planner stores interval templates and PlannedExercise
            // independently. Project them into the same canonical phase order
            // without replacing per-set data with derived snapshots.
            let projected = ATHLTHUnifiedWorkout.editorBlocks(from: workout)
            var parts: [PlannedSession] = []
            for phase: WorkoutPhaseKind in [.warmup, .main, .cooldown] {
                let phaseExercises = workout.exercises.filter { exercise in
                    (exercise.workoutPhase ??
                        (exercise.isWarmUpExercise ? .warmup : .main)) == phase
                }
                let runBlocks = projected.filter { block in
                    (block.kind == .run || block.kind == .rest) &&
                    (phase == .main
                        ? block.resolvedPhase == .main ||
                            block.resolvedPhase == .recovery
                        : block.resolvedPhase == phase)
                }

                // Warm-up strength before run warm-up; main/cooldown run
                // before supplementary strength in the same phase.
                if phase == .warmup && !phaseExercises.isEmpty {
                    parts.append(strengthPart(workout, exercises: phaseExercises))
                }
                if !runBlocks.isEmpty {
                    var part = stripped(workout)
                    part.kind = .running
                    part.workoutBlocks = runBlocks
                    parts.append(part)
                }
                if phase != .warmup && !phaseExercises.isEmpty {
                    parts.append(strengthPart(workout, exercises: phaseExercises))
                }
            }
            result = parts
        }

        guard !result.isEmpty,
              result.contains(where: { $0.kind == .running }),
              result.contains(where: { $0.kind == .strength })
        else { return nil }

        // Validate ALL parts before starting HealthKit, not after opening
        // a Watch session. The embedded running motor only supports timed
        // treadmill steps; no GPS or estimated distance substitution.
        for part in result where part.kind == .running {
            guard let blocks = part.workoutBlocks,
                  !blocks.isEmpty,
                  blocks.contains(where: { $0.kind == .run }),
                  blocks.allSatisfy({
                      ($0.kind == .run || $0.kind == .rest) &&
                      $0.distanceMeters == nil &&
                      $0.isIndoor != false &&
                      $0.durationSeconds.map {
                          $0.isFinite && (15...7_200).contains($0)
                      } == true
                  }) else { return nil }
        }
        return result
    }

    private static func stripped(_ workout: PlannedSession) -> PlannedSession {
        var part = workout
        part.exercises = []
        part.runningWorkout = nil
        part.runningWorkouts = nil
        part.workoutBlocks = nil
        part.routeID = nil
        part.targetDistanceKilometers = nil
        part.targetPaceSecondsPerKilometer = nil
        return part
    }

    private static func strengthPart(
        _ workout: PlannedSession,
        exercises: [PlannedExercise]
    ) -> PlannedSession {
        var part = stripped(workout)
        part.kind = .strength
        part.exercises = exercises
        return part
    }
}
