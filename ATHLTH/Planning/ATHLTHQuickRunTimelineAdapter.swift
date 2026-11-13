import Foundation

/// Executes the same chronological WorkoutTemplateBlock timeline built in
/// Plan -> From Scratch without creating a separate running editor or recorder.
/// Translates Basic goals to the same persisted workout timeline as
/// Advanced. A pace/zone goal remains open-ended until athlete finishes it.
enum ATHLTHBasicRunGoalRecipe {
    static func make(
        id: UUID,
        title: String,
        kind: ATHLTHBasicRunGoalKind,
        distanceKilometers: Int,
        timeMinutes: Int,
        paceSecondsPerKilometer: Int,
        heartRateZone: Int,
        environment: RunEnvironment,
        selectedGoals: Set<ATHLTHBasicRunGoalKind>? = nil
    ) -> PlannedSession {
        // Preserve the original single-goal API used by saved workouts.
        // Multiple simultaneous goals use the same one-step recording engine.
        let goals = selectedGoals?.isEmpty == false ? selectedGoals! : Set([kind])
        var step = WorkoutTemplateBlock(
            sequence: 1, kind: .run,
            title: ATHLTHLocalization.choose(
                english: "Goal-based run", norwegian: "Målstyrt løping"
            ),
            exerciseSlug: nil,
            distanceMeters: goals.contains(.distance)
                ? Double(max(1, distanceKilometers) * 1_000) : nil,
            repetitions: nil,
            durationSeconds: goals.contains(.time)
                ? TimeInterval(max(1, timeMinutes) * 60) : nil,
            targetWeightKilograms: nil, loadNote: nil, notes: nil,
            phase: .main
        )
        step.cardioActivity = .running
        if goals.contains(.distance) && goals.contains(.time) {
            step.notes = ATHLTHLocalization.format(
                english: "Target time: %d minutes. Distance ends this phase.",
                norwegian: "Tidsmål: %d minutter. Distanse avslutter denne delen.",
                max(1, timeMinutes)
            )
        }
        if goals.contains(.pace) {
            step.targetPaceSecondsPerKilometer =
                Double(min(max(180, paceSecondsPerKilometer), 900))
        }
        if goals.contains(.heartRateZone) {
            step.targetHeartRateZone = min(max(heartRateZone, 1), 5)
        }
        var result = PlannedSession(
            id: id, title: title.isEmpty ? step.title : title,
            kind: .running, scheduledStart: nil,
            durationMinutes: goals.contains(.time) ? max(1, timeMinutes) : nil,
            targetDistanceKilometers: goals.contains(.distance)
                ? Double(max(1, distanceKilometers)) : nil,
            targetPaceSecondsPerKilometer: step.targetPaceSecondsPerKilometer,
            routeID: nil, exercises: [], notes: nil
        )
        result.workoutBlocks = [step]
        return ATHLTHQuickRunTimelineAdapter.withEnvironment(
            result, environment: environment
        )
    }
}

enum ATHLTHQuickRunTimelineAdapter {
    /// A library run is projected only to seed the shared studio; its
    /// source template is never mutated unless the user saves a new one.
    static func editorBlocks(from template: RunningWorkoutTemplate) -> [WorkoutTemplateBlock] {
        var source = PlannedSession(
            id: UUID(), title: template.title, kind: .running,
            scheduledStart: nil, durationMinutes: nil,
            targetDistanceKilometers: nil, targetPaceSecondsPerKilometer: nil,
            routeID: template.routeID, exercises: [], notes: nil
        )
        source.runningWorkout = template
        source.runningWorkouts = [template]
        return ATHLTHUnifiedWorkout.editorBlocks(from: source)
    }

    static func validationError(for workout: PlannedSession) -> String? {
        let blocks = workout.resolvedWorkoutBlocks
        let runs = blocks.filter { $0.kind == .run }
        guard !runs.isEmpty else {
            return ATHLTHLocalization.choose(
                english: "Add a running phase before starting.",
                norwegian: "Legg til en løpedel før du starter."
            )
        }
        guard blocks.allSatisfy({ $0.kind == .run || $0.kind == .rest }),
              runs.allSatisfy({
                  $0.cardioActivity != .walking && $0.activityTag != "cycling"
              }) else {
            return ATHLTHLocalization.choose(
                english: "Quick Train Running supports running and recovery. Mixed workouts belong in Plan.",
                norwegian: "Quick Train Løping støtter løping og pauser. Kombinasjonsøkter startes fra Plan."
            )
        }
        guard Set(runs.map { $0.isIndoor == true }).count == 1 else {
            return ATHLTHLocalization.choose(
                english: "Use only outdoor or indoor running phases in one run.",
                norwegian: "Bruk enten ute- eller innendørs løping i én økt."
            )
        }
        let expanded = blocks.expandedForExecution()
        guard !expanded.isEmpty, expanded.count <= 1000,
              expanded.allSatisfy({ block in
                  if let distance = block.distanceMeters,
                     (!distance.isFinite || distance <= 0) { return false }
                  if let seconds = block.durationSeconds,
                     (!seconds.isFinite || seconds <= 0) { return false }
                  // WatchRunningStepMeasure.open intentionally requires the
                  // athlete to press Next. Hills, partner recovery and test
                  // phases must not receive invented pause lengths.
                  return true
              }) else {
            return ATHLTHLocalization.choose(
                english: "Check the distance and duration of each phase.",
                norwegian: "Kontroller distanse og varighet for hver deløkt."
            )
        }
        return nil
    }

    static func environment(for workout: PlannedSession) -> RunEnvironment {
        if workout.workoutCategory == "treadmill" { return .treadmill }
        if workout.workoutCategory == "indoor" { return .indoor }
        let runs = workout.resolvedWorkoutBlocks.filter { $0.kind == .run }
        guard runs.contains(where: { $0.isIndoor == true }) else { return .outdoor }
        return runs.contains(where: { $0.treadmillInclinePercent != nil })
            ? .treadmill : .indoor
    }

    /// Apply the choice from Workout Details to the full ordered running
    /// recipe before iPhone/Watch transfer. The selected library template
    /// remains unchanged. Outdoor routes/route Ghost cannot follow indoors.
    static func withEnvironment(
        _ workout: PlannedSession,
        environment: RunEnvironment
    ) -> PlannedSession {
        var copy = workout
        var recipe = workout.resolvedWorkoutBlocks
        for index in recipe.indices where recipe[index].kind == .run {
            recipe[index].isIndoor = environment != .outdoor
            recipe[index].treadmillInclinePercent = environment == .treadmill
                ? (recipe[index].treadmillInclinePercent ?? 0) : nil
            if environment != .outdoor {
                recipe[index].routeID = nil
            }
        }
        copy.workoutBlocks = recipe
        switch environment {
        case .outdoor: copy.workoutCategory = "running"
        case .indoor: copy.workoutCategory = "indoor"
        case .treadmill: copy.workoutCategory = "treadmill"
        }
        if environment != .outdoor {
            copy.routeID = nil
            copy.routeAlertConfiguration = nil
            copy.ghostTargetDurationSeconds = nil
            copy.ghostUpdates = nil
        }
        return copy
    }

    static func transfer(
        from workout: PlannedSession,
        title: String,
        routeAlerts: WatchRouteAlertConfiguration,
        autoPauseEnabled: Bool
    ) -> WatchRunningWorkoutTransfer? {
        guard validationError(for: workout) == nil else { return nil }

        let steps = workout.resolvedWorkoutBlocks.expandedForExecution().map { block in
            let measure: WatchRunningStepMeasure =
                block.distanceMeters != nil ? .distance :
                block.durationSeconds != nil ? .time : .open
            let phase: String
            if block.isRestOrActiveRecovery || block.resolvedPhase == .recovery {
                phase = "recovery"
            } else {
                switch block.resolvedPhase {
                case .warmup: phase = "warmup"
                case .main: phase = "work"
                case .recovery: phase = "recovery"
                case .cooldown: phase = "cooldown"
                }
            }
            let pace = block.targetPaceSecondsPerKilometer
            let effort = block.targetEffortRPE.map { "RPE \($0)" }
            let coachText = [block.notes, effort]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: ". ")
            return WatchRunningWorkoutStep(
                id: UUID(),
                title: block.title,
                measure: measure,
                distanceMeters: block.distanceMeters,
                durationSeconds: block.durationSeconds,
                intensityText: effort,
                targetPaceMinSecondsPerKilometer: pace,
                targetPaceMaxSecondsPerKilometer: pace,
                phase: phase,
                targetHeartRateZone: block.targetHeartRateZone,
                targetTreadmillInclinePercent: block.treadmillInclinePercent,
                coachBrief: coachText.isEmpty ? nil : coachText
            )
        }
        var result = WatchRunningWorkoutTransfer(
            title: title,
            steps: steps,
            sourceWorkoutID: workout.id,
            routeAlerts: routeAlerts,
            autoPauseEnabled: autoPauseEnabled
        )
        // Timed steps advance normally. The shared running engine exposes
        // manual Next independently for every open-ended step.
        result.autoAdvanceTimedSteps = true
        // An open warm-up must always expose the manual transition button.
        result.autoStartMainAfterWarmup = !steps.contains {
            $0.phase == "warmup" && $0.measure == .open
        }
        return result
    }
}
