import Foundation

/// Executes the same chronological WorkoutTemplateBlock timeline built in
/// Plan -> From Scratch without creating a separate running editor or recorder.
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
                  return block.kind != .rest || block.durationSeconds != nil
              }) else {
            return ATHLTHLocalization.choose(
                english: "Check the distance and duration of each phase.",
                norwegian: "Kontroller distanse og varighet for hver deløkt."
            )
        }
        return nil
    }

    static func environment(for workout: PlannedSession) -> RunEnvironment {
        let runs = workout.resolvedWorkoutBlocks.filter { $0.kind == .run }
        guard runs.first?.isIndoor == true else { return .outdoor }
        return runs.contains { $0.treadmillInclinePercent != nil } ||
            workout.workoutCategory == "treadmill" ? .treadmill : .indoor
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
            switch block.resolvedPhase {
            case .warmup: phase = "warmup"
            case .main: phase = "work"
            case .recovery: phase = "recovery"
            case .cooldown: phase = "cooldown"
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
