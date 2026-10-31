import Foundation

struct PlannedWorkoutWatchBuilder {
    static func strengthSnapshot(
        _ workout: PlannedSession
    ) -> WatchStrengthSessionSnapshot? {
        guard workout.kind == .strength,
              !workout.exercises.isEmpty
        else {
            return nil
        }

        let queue =
            workout.exercises
                .enumerated()
                .map {
                    index,
                    planned in

                    let setTargets =
                        planned
                            .resolvedSetTargets
                    let setCount =
                        setTargets.count
                    let plans =
                        Array(
                            setTargets.enumerated()
                        )
                        .map {
                            index,
                            target in

                            WatchStrengthSetPlan(
                                setNumber:
                                    index + 1,
                                reps:
                                    planned
                                        .resolvedTargetKind ==
                                        .reps
                                        ? target.reps
                                        : nil,
                                durationSeconds:
                                    planned
                                        .resolvedTargetKind ==
                                        .time
                                        ? target
                                            .durationSeconds
                                        : nil,
                                weightKilograms:
                                    planned
                                        .resolvedLoadKind ==
                                        .weightKilograms
                                        ? target
                                            .weightKilograms
                                        : nil,
                                resistanceLevel:
                                    planned
                                        .resolvedLoadKind ==
                                        .resistanceLevel
                                        ? target
                                            .resistanceLevel
                                        : nil,
                                restSeconds:
                                    target
                                        .restSeconds,
                                targetRPE:
                                    target
                                        .targetRPE,
                                targetRIR:
                                    target
                                        .targetRIR,
                                isWarmUp:
                                    target
                                        .isWarmUp
                            )
                        }

                    return WatchStrengthExerciseSummary(
                        index: index,
                        name:
                            planned
                                .embeddedExercise
                                .name,
                        primaryMuscles:
                            planned
                                .embeddedExercise
                                .primaryMuscles,
                        setCount:
                            setCount,
                        instructions:
                            planned
                                .embeddedExercise
                                .instructions,
                        secondaryMuscles:
                            planned
                                .embeddedExercise
                                .secondaryMuscles,
                        equipment:
                            planned
                                .embeddedExercise
                                .equipment,
                        setPlans:
                            plans
                    )
                }

        guard let first =
                queue.first,
              let firstPlan =
                first.setPlans?.first
        else {
            return nil
        }

        return WatchStrengthSessionSnapshot(
            workoutID:
                workout.id,
            title:
                workout.title,
            exerciseIndex: 0,
            exerciseCount:
                queue.count,
            exerciseName:
                first.name,
            primaryMuscles:
                first.primaryMuscles,
            setIndex: 0,
            setCount:
                first.setCount,
            setNumber: 1,
            completedSets: 0,
            totalSets:
                queue.reduce(0) {
                    $0 + $1.setCount
                },
            draftReps:
                firstPlan.reps ?? 8,
            draftWeightKilograms:
                firstPlan
                    .weightKilograms ??
                20,
            draftRestSeconds:
                firstPlan.restSeconds ??
                90,
            draftDurationSeconds:
                firstPlan
                    .durationSeconds,
            draftResistanceLevel:
                firstPlan
                    .resistanceLevel,
            targetKindRaw:
                firstPlan
                    .durationSeconds != nil
                    ? "time"
                    : "reps",
            loadKindRaw:
                firstPlan
                    .resistanceLevel != nil
                    ? "resistanceLevel"
                    : "weightKilograms",
            isResting: false,
            restEndsAt: nil,
            currentExerciseComplete:
                false,
            hasNextExercise:
                queue.count > 1,
            allExercisesComplete:
                false,
            updatedAt: Date(),
            inputMode:
                .appleWatch,
            draftRPE:
                plannedDefaultRPE(
                    workout
                ),
            draftRIR:
                plannedDefaultRIR(
                    workout
                ),
            isWarmUp:
                firstPlan.isWarmUp,
            effortMetricRaw:
                "rpe",
            exerciseQueue:
                queue,
            startedAt: nil,
            plannedSessionID:
                workout.id,
            allowsLiveExerciseBuilding:
                false
        )
    }

    private static func plannedDefaultRPE(
        _ workout: PlannedSession
    ) -> Double? {
        workout.exercises
            .first?
            .resolvedSetTargets
            .first?
            .targetRPE ??
        workout.exercises
            .first?
            .targetRPE ??
        8
    }

    private static func plannedDefaultRIR(
        _ workout: PlannedSession
    ) -> Double? {
        workout.exercises
            .first?
            .resolvedSetTargets
            .first?
            .targetRIR ??
        workout.exercises
            .first?
            .targetRIR ??
        2
    }


    static func watchKind(
        for kind: WorkoutKind
    ) -> WatchWorkoutKind? {
        switch kind {
        case .running:
            return .running
        case .walking:
            return .walking
        case .strength:
            return .strength
        case .mobility, .recovery, .custom:
            return nil
        }
    }

    static func route(
        for workout: PlannedSession,
        routes: [TrainingRoute]
    ) -> TrainingRoute? {
        guard let routeID = workout.routeID else {
            return nil
        }

        return routes.first { $0.id == routeID }
    }

    static func audioCoachConfiguration(
        for workout: PlannedSession,
        selectedRoute: TrainingRoute?,
        defaultConfiguration: WatchAudioCoachConfiguration
    ) -> WatchAudioCoachConfiguration {
        var configuration =
            workout.audioCoachConfiguration ??
            defaultConfiguration
        // Saved workouts from older builds inherit the athlete's current
        // motivation and landmark profile without losing workout overrides.
        if configuration.smartPrompts == nil {
            configuration.smartPrompts = defaultConfiguration.smartPrompts
        }

        // A saved workout may override other Audio Coach preferences,
        // but fuel voice reminders follow the current athlete's opt-in.
        configuration.fuelReminderIntervalMinutes =
            configuration.enabled
                ? defaultConfiguration.fuelReminderIntervalMinutes : nil
        configuration.fuelReminderDurationMinutes =
            configuration.enabled
                ? defaultConfiguration.fuelReminderDurationMinutes : nil
        configuration.fuelCarbohydrateGramsPerHour =
            configuration.enabled
                ? defaultConfiguration.fuelCarbohydrateGramsPerHour : nil
        configuration.fuelFluidMLPerHour =
            configuration.enabled
                ? defaultConfiguration.fuelFluidMLPerHour : nil

        configuration.routeDistanceMeters =
            selectedRoute.map {
                $0.distanceKilometers * 1_000
            }
            ?? workout.targetDistanceKilometers.map {
                $0 * 1_000
            }

        return configuration
    }

    static func runningTransfer(
        from workout: PlannedSession,
        routeAlerts: WatchRouteAlertConfiguration,
        autoPauseEnabled: Bool? = nil
    ) -> WatchRunningWorkoutTransfer {
        let structured = workout.resolvedRunningWorkouts

        if !structured.isEmpty {
            return WatchRunningWorkoutTransfer(
                title: workout.title,
                steps: structured.flatMap {
                    runningSteps(from: $0)
                },
                sourceWorkoutID: workout.id,
                routeAlerts:
                    workout.routeAlertConfiguration ??
                    routeAlerts,
                targetAlerts:
                    workout.targetAlertConfiguration,
                autoPauseEnabled:
                    autoPauseEnabled ??
                    workout.autoPauseEnabled,
                autoAdvanceTimedSteps:
                    structured.allSatisfy { $0.autoAdvanceTimedSteps != false },
                autoStartMainAfterWarmup: structured.first?.autoStartMainAfterWarmup,
                intervalCoachCueEverySeconds: structured.first?.intervalCoachCueEverySeconds,
                intervalCoachCountdownSeconds: structured.first?.intervalCoachCountdownSeconds
            )
        }

        let fallback: WatchRunningWorkoutStep

        if let distance =
                workout.targetDistanceKilometers,
           distance > 0 {
            fallback = WatchRunningWorkoutStep(
                id: UUID(),
                title: workout.title,
                measure: .distance,
                distanceMeters: distance * 1_000,
                durationSeconds: nil,
                intensityText: plannedPaceText(workout),
                targetPaceMinSecondsPerKilometer:
                    workout.targetPaceSecondsPerKilometer,
                targetPaceMaxSecondsPerKilometer:
                    workout.targetPaceSecondsPerKilometer
            )
        } else if let minutes = workout.durationMinutes,
                  minutes > 0 {
            fallback = WatchRunningWorkoutStep(
                id: UUID(),
                title: workout.title,
                measure: .time,
                distanceMeters: nil,
                durationSeconds:
                    TimeInterval(minutes * 60),
                intensityText: plannedPaceText(workout),
                targetPaceMinSecondsPerKilometer:
                    workout.targetPaceSecondsPerKilometer,
                targetPaceMaxSecondsPerKilometer:
                    workout.targetPaceSecondsPerKilometer
            )
        } else {
            fallback = WatchRunningWorkoutStep(
                id: UUID(),
                title: workout.title,
                measure: .open,
                distanceMeters: nil,
                durationSeconds: nil,
                intensityText: plannedPaceText(workout),
                targetPaceMinSecondsPerKilometer:
                    workout.targetPaceSecondsPerKilometer,
                targetPaceMaxSecondsPerKilometer:
                    workout.targetPaceSecondsPerKilometer
            )
        }

        return WatchRunningWorkoutTransfer(
            title: workout.title,
            steps: [fallback],
            sourceWorkoutID: workout.id,
            routeAlerts:
                workout.routeAlertConfiguration ??
                routeAlerts,
            targetAlerts:
                workout.targetAlertConfiguration,
            autoPauseEnabled:
                autoPauseEnabled ??
                workout.autoPauseEnabled
        )
    }

    static func runningTransfer(
        from workout: RunningWorkoutTemplate,
        routeAlerts: WatchRouteAlertConfiguration,
        autoPauseEnabled: Bool? = nil
    ) -> WatchRunningWorkoutTransfer {
        WatchRunningWorkoutTransfer(
            title: workout.title,
            steps: runningSteps(from: workout),
            sourceWorkoutID: workout.id,
            routeAlerts: routeAlerts,
            autoPauseEnabled: autoPauseEnabled,
            autoAdvanceTimedSteps: workout.autoAdvanceTimedSteps,
            autoStartMainAfterWarmup: workout.autoStartMainAfterWarmup,
            intervalCoachCueEverySeconds: workout.intervalCoachCueEverySeconds,
            intervalCoachCountdownSeconds: workout.intervalCoachCountdownSeconds
        )
    }

    private static func runningSteps(
        from template: RunningWorkoutTemplate
    ) -> [WatchRunningWorkoutStep] {
        template.blocks.flatMap { (block: RunningWorkoutBlock) -> [WatchRunningWorkoutStep] in
            // A manual Start main section replaces an old post-warm-up
            // preparation pause; the athlete chooses the exact wait time.
            if template.autoStartMainAfterWarmup != true,
               block.kind == .recovery,
               (block.title == "Pause før hoveddel" ||
                block.title == "Recovery after warm-up") { return [] }
            let count = max(block.repetitions, 1)
            var steps: [WatchRunningWorkoutStep] = []

            for position in 1...count {
                let resolved = block.resolvedWork(at: position)
                let override = block.override(for: position)
                let title = count > 1
                    ? "\(block.title) \(position)/\(count)" : block.title
                let working = block.kind == .work
                // Notes are spoken as guidance, not substituted for the
                // interval's actual title on the Watch and iPhone.
                let guidance = [template.coachBrief, block.notes, override?.notes]
                    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: ". ")
                steps.append(runningStep(
                    title: title, target: resolved,
                    phase: block.kind.rawValue,
                    ghostPace: working
                        ? (override?.ghostPaceSecondsPerKilometer ??
                           template.intervalGhostPaceSecondsPerKilometer)
                        : nil,
                    coachBrief: working && !guidance.isEmpty ? guidance : nil
                ))

                if let recovery = block.resolvedRecovery(after: position) {
                    steps.append(runningStep(
                        title: ATHLTHLocalization.choose(
                            english: "Recovery \(position)",
                            norwegian: "Pause \(position)"
                        ),
                        target: recovery,
                        phase: RunningBlockKind.recovery.rawValue,
                        ghostPace: template.intervalGhostFollowRecovery == true
                            ? template.intervalGhostPaceSecondsPerKilometer : nil,
                        ghostFollowsRecovery:
                            template.intervalGhostFollowRecovery == true &&
                            template.intervalGhostPaceSecondsPerKilometer != nil,
                        slowdownPercent: template.intervalGhostRecoverySlowdownPercent
                    ))
                }
            }
            return steps
        }
    }

    private static func runningStep(
        title: String,
        target: RunningStepTarget,
        phase: String,
        ghostPace: Double? = nil,
        ghostFollowsRecovery: Bool? = nil,
        slowdownPercent: Int? = nil,
        coachBrief: String? = nil
    ) -> WatchRunningWorkoutStep {
        let measure: WatchRunningStepMeasure
        switch target.measure {
        case .distance: measure = .distance
        case .time: measure = .time
        case .open: measure = .open
        }
        return WatchRunningWorkoutStep(
            id: UUID(),
            title: title,
            measure: measure,
            distanceMeters: target.distanceMeters,
            durationSeconds: target.durationSeconds,
            intensityText: runningIntensityText(target.intensity),
            targetPaceMinSecondsPerKilometer: target.intensity.paceMinSecondsPerKilometer,
            targetPaceMaxSecondsPerKilometer: target.intensity.paceMaxSecondsPerKilometer,
            phase: phase,
            targetHeartRateZone: target.intensity.heartRateZone,
            targetTreadmillInclinePercent: target.treadmillInclinePercent,
            ghostPaceSecondsPerKilometer: ghostPace,
            ghostFollowsRecovery: ghostFollowsRecovery,
            ghostRecoverySlowdownPercent: slowdownPercent,
            coachBrief: coachBrief
        )
    }

    private static func runningIntensityText(
        _ intensity: RunningIntensityTarget
    ) -> String? {
        switch intensity.kind {
        case .none:
            return nil
        case .easy:
            return "Easy effort"
        case .pace:
            if let minimum =
                    intensity
                        .paceMinSecondsPerKilometer,
               let maximum =
                    intensity
                        .paceMaxSecondsPerKilometer {
                return
                    "\(paceText(minimum))–\(paceText(maximum)) /km"
            }

            if let pace =
                    intensity
                        .paceMinSecondsPerKilometer ??
                    intensity
                        .paceMaxSecondsPerKilometer {
                return "\(paceText(pace)) /km"
            }

            return "Pace target"
        case .heartRateZone:
            if let zone = intensity.heartRateZone {
                return "Heart-rate zone \(zone)"
            }
            return "Heart-rate target"
        case .rpe:
            if let rpe = intensity.rpe {
                return String(
                    format: "RPE %.1f",
                    rpe
                )
            }
            return "RPE target"
        }
    }

    private static func plannedPaceText(
        _ workout: PlannedSession
    ) -> String? {
        guard let pace =
                workout
                    .targetPaceSecondsPerKilometer,
              pace > 0
        else {
            return nil
        }

        return "\(paceText(pace)) /km"
    }

    private static func paceText(
        _ secondsPerKilometer: Double
    ) -> String {
        let total = max(
            Int(secondsPerKilometer.rounded()),
            0
        )

        return String(
            format: "%d:%02d",
            total / 60,
            total % 60
        )
    }
}

@MainActor
enum WorkoutLaunchCoordinator {
    static func resolvedSpotifyPlaylist(
        workout: PlannedSession,
        session: AppSessionStore
    ) -> SpotifyPlaylistReference? {
        if let workoutAutoplay =
                workout.spotifyAutoplayOnStart {
            guard workoutAutoplay else {
                return nil
            }

            return workout.spotifyPlaylist
        }

        // Legacy plans stored Spotify at program level. Keep that behavior
        // only when the workout has no explicit Spotify override.
        guard
            let plan =
                session.trainingPlan(
                    containingSessionID:
                        workout.id
                ),
            plan.spotifyAutoplayOnWorkoutStart
        else {
            return nil
        }

        return plan.spotifyPlaylist
    }

    static func startLinkedSpotifyIfNeeded(
        workout: PlannedSession,
        session: AppSessionStore,
        settings: AppSettingsStore,
        spotify: SpotifyPlaybackStore
    ) {
        let hasWorkoutOverride =
            workout.spotifyAutoplayOnStart != nil

        guard
            (
                hasWorkoutOverride ||
                settings.spotifyAutoplayLinkedPlaylists
            ),
            let playlist =
                resolvedSpotifyPlaylist(
                    workout: workout,
                    session: session
                )
        else {
            return
        }

        Task { @MainActor in
            await spotify.startLinkedPlaylist(
                playlist,
                settings: settings,
                respectGlobalAutoplay:
                    !hasWorkoutOverride
            )
        }
    }

    private static func startQuickSpotifyIfNeeded(
        playlist: SpotifyPlaylistReference?,
        autoplay: Bool,
        settings: AppSettingsStore,
        spotify: SpotifyPlaybackStore
    ) {
        guard autoplay,
              let playlist
        else {
            return
        }

        Task { @MainActor in
            await spotify.startLinkedPlaylist(
                playlist,
                settings: settings,
                respectGlobalAutoplay: false
            )
        }
    }

    static func startRunQuick(
        configuration: RunQuickStartConfiguration,
        session: AppSessionStore,
        settings: AppSettingsStore,
        gear: ProfileGearStore,
        phoneWorkout: IPhoneWorkoutStore,
        watchConnection: AppleWatchConnectionStore,
        spotify: SpotifyPlaybackStore,
        ghostRace: GhostRaceStore? = nil,
        workoutMirroring:
            WorkoutMirroringStore? = nil,
        plannedPlanID: UUID? = nil,
        plannedSessionID: UUID? = nil
    ) async throws {
        if ATHLTHDeviceRole.isIPad {
            let envelope =
                WorkoutDeviceRelayEnvelope(
                    kind: .run,
                    target:
                        WorkoutDeviceRelayTarget(
                            captureDevice:
                                configuration
                                    .captureDevice
                        ),
                    workoutPayload:
                        configuration
                            .trainTogetherInvitePayload(
                                savedRoutes:
                                    session.savedRoutes
                            ),
                    watchAudioCoach:
                        settings.applyingFuelVoice(
                            to: configuration.audioCoach,
                            userID: session.profile.userID
                        ),
                    ghostTargetDurationSeconds:
                        configuration
                            .ghostTargetDurationSeconds,
                    ghostUpdates:
                        configuration
                            .ghostUpdates,
                    runEnvironment:
                        configuration.environment,
                    treadmillInclinePercent:
                        configuration
                            .treadmillInclinePercent,
                    spotifyPlaylist:
                        configuration
                            .spotifyPlaylist,
                    spotifyAutoplay:
                        configuration
                            .spotifyAutoplay,
                    gearIDs:
                        Array(
                            configuration.gearIDs
                        )
                )

            try await WorkoutDeviceRelayStore
                .shared
                .enqueue(envelope)
            return
        }

        try await watchConnection.requireNoActiveWatchWorkout()

        let selectedRoute: TrainingRoute? = {
            if let route = configuration.route {
                return route
            }

            guard
                let workout = configuration.workout,
                let routeID = workout.routeID
            else {
                return nil
            }

            return session.savedRoutes.first {
                $0.id == routeID
            }
        }()

        let resolvedAudioCoach = settings.applyingFuelVoice(
            to: configuration.audioCoach,
            userID: session.profile.userID
        )
        let resolvedGhostUpdates =
            GhostRaceStartService
                .coexistingGhostAudio(
                    configuration
                        .ghostUpdates,
                    audioCoach:
                        resolvedAudioCoach
                )

        if let targetDuration =
                configuration
                    .ghostTargetDurationSeconds {
            guard let selectedRoute,
                  let ghostRace
            else {
                throw NSError(
                    domain: "ATHLTH.RunLaunch",
                    code: 3,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Choose a route before starting a Ghost run."
                    ]
                )
            }

            try ghostRace.prepareTarget(
                route: selectedRoute,
                targetDurationSeconds:
                    targetDuration
            )
        } else {
            ghostRace?.cancel()
            watchConnection.clearGhostRace()
        }

        // A simple planned run may have a distance or duration target
        // without a library template. Carry that target into the existing
        // iPhone/Watch running transfer rather than launching an untargeted
        // Free Run. The plan/session IDs come from an explicit plan launch.
        let plannedRunningWorkout: PlannedSession? = {
            guard let planID = plannedPlanID,
                  let workoutID = plannedSessionID,
                  let plan = session.trainingPlan(withID: planID)
            else { return nil }
            return plan.weeks.flatMap(\.days).flatMap(\.sessions)
                .first(where: {
                    $0.id == workoutID && $0.kind == .running
                })
        }()

        let structuredWorkout =
            configuration.workout.map {
                PlannedWorkoutWatchBuilder
                    .runningTransfer(
                        from: $0,
                        routeAlerts:
                            configuration
                                .routeAlerts,
                        autoPauseEnabled:
                            configuration
                                .autoPauseEnabled
                    )
            } ?? plannedRunningWorkout.map {
                PlannedWorkoutWatchBuilder.runningTransfer(
                    from: $0,
                    routeAlerts: configuration.routeAlerts,
                    autoPauseEnabled: configuration.autoPauseEnabled
                )
            } ?? (
                configuration.mode == .route
                    ? configuration.routeWarmup.runningTransfer(
                        title: configuration.title,
                        routeAlerts: configuration.routeAlerts,
                        autoPauseEnabled: configuration.autoPauseEnabled
                    )
                    : nil
            )

        if configuration.captureDevice == .iPhone {
            workoutMirroring?
                .clearIPhoneAudioCoach()
            gear.prepareNextWorkoutGear(
                configuration.gearIDs
            )
            phoneWorkout.start(
                walking: false,
                route: selectedRoute,
                title: plannedRunningWorkout?.title ?? configuration.title,
                environment:
                    configuration.environment,
                treadmillInclinePercent:
                    configuration
                        .treadmillInclinePercent,
                audioCoach:
                    resolvedAudioCoach,
                structuredWorkout:
                    structuredWorkout,
                routeAlerts:
                    configuration
                        .routeAlerts,
                ghostUpdates:
                    resolvedGhostUpdates,
                autoPauseEnabled:
                    configuration
                        .autoPauseEnabled,
                plannedPlanID: plannedPlanID,
                plannedSessionID: plannedSessionID
            )
            watchConnection
                .updateLocalWorkoutActivity(
                    isActive: true,
                    title: plannedRunningWorkout?.title ?? configuration.title
                )
            startQuickSpotifyIfNeeded(
                playlist:
                    configuration.spotifyPlaylist,
                autoplay:
                    configuration.spotifyAutoplay,
                settings: settings,
                spotify: spotify
            )
            return
        }

        guard watchConnection.isReady else {
            throw NSError(
                domain: "ATHLTH.RunLaunch",
                code: 2,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Apple Watch is not ready to receive this run."
                ]
            )
        }

        // Keep route geometry on the existing file-transfer path. The Watch
        // keeps the prepared workout card disabled until a referenced route
        // has actually arrived, so START can never launch with missing route
        // data.
        if let selectedRoute {
            try watchConnection.sendRoute(
                selectedRoute
            )
        }

        let preparedGhostRace:
            WatchGhostRaceTransfer? = {
            guard let ghostRace,
                  configuration
                    .ghostTargetDurationSeconds != nil
            else {
                return nil
            }

            return GhostRaceStartService
                .preparedTransfer(
                    ghostRace: ghostRace,
                    audio:
                        resolvedGhostUpdates ??
                        .disabled
                )
        }()

        var watchRunningWorkout =
            structuredWorkout ??
            WatchRunningWorkoutTransfer(
                title: configuration.title,
                steps: [],
                routeAlerts:
                    configuration
                        .routeAlerts,
                autoPauseEnabled:
                    configuration
                        .autoPauseEnabled
            )

        watchRunningWorkout
            .treadmillInclinePercent =
                configuration.environment ==
                    .treadmill
                    ? min(
                        max(
                            configuration
                                .treadmillInclinePercent ??
                            0,
                            0
                        ),
                        20
                    )
                    : nil

        // The configuration is stored with the prepared workout. If iPhone is
        // still reachable after START, Audio Coach may use the phone audio
        // route; Watch remains the fallback when the phone is unavailable.
        var watchAudioCoach =
            resolvedAudioCoach

        if workoutMirroring != nil,
           resolvedAudioCoach.enabled {
            watchAudioCoach
                .preferIPhoneAudioWhenReachable =
                    true
            watchAudioCoach
                .useAcknowledgedVoiceLease = true
            workoutMirroring?
                .prepareIPhoneAudioCoach(
                    watchAudioCoach
                )
        } else {
            workoutMirroring?
                .clearIPhoneAudioCoach()
        }

        let preparedSummary: String = {
            if let workout =
                    configuration.workout {
                return workout.summary
            }
            if let planned = plannedRunningWorkout,
               let minutes = planned.durationMinutes,
               minutes > 0 {
                return "\(minutes) min"
            }
            if let planned = plannedRunningWorkout,
               let distance = planned.targetDistanceKilometers,
               distance > 0 {
                return String(format: "%.1f km", distance)
            }

            if let selectedRoute {
                return String(
                    format: "%.1f km",
                    selectedRoute
                        .distanceKilometers
                )
            }

            return ATHLTHLocalization.choose(
                english:
                    configuration.environment ==
                        .treadmill
                        ? "Treadmill · ready to start"
                        : "Outdoor · ready to start",
                norwegian:
                    configuration.environment ==
                        .treadmill
                        ? "Tredemølle · klar til start"
                        : "Utendørs · klar til start"
            )
        }()

        // Gear belongs to the next Watch workout. HealthKit, elapsed
        // time and distance recording remain completely idle here.
        gear.prepareNextWorkoutGear(
            configuration.gearIDs
        )

        watchConnection.sendPreparedWorkout(
            WatchPreparedWorkoutTransfer(
                id: UUID(),
                title: plannedRunningWorkout?.title ?? configuration.title,
                summary: preparedSummary,
                kind: .running,
                routeID:
                    selectedRoute?.id,
                runningWorkout:
                    watchRunningWorkout,
                audioCoach:
                    watchAudioCoach,
                ghostRace:
                    preparedGhostRace,
                indoor:
                    configuration.environment ==
                    .treadmill,
                startMode: configuration.watchStartMode,
                updatedAt: Date()
            )
        )

        // For automatic start, launch the Watch workout via HealthKit.
        // The prepared payload carries the start mode and full route/coach
        // context; the Watch applies it before starting its session.
        // Manual mode retains the existing ready-to-start Watch card.
        if configuration.watchStartMode != .onWatch {
            try await watchConnection.startWorkoutOnWatch(
                .running,
                indoor: configuration.environment == .treadmill
            )
        }

        // Preserve the existing Quick Run music behavior. This is independent
        // of HealthKit workout timing and does not start the workout itself.
        startQuickSpotifyIfNeeded(
            playlist:
                configuration.spotifyPlaylist,
            autoplay:
                configuration.spotifyAutoplay,
            settings: settings,
            spotify: spotify
        )
    }

    static func startWalkQuick(
        configuration: WalkQuickStartConfiguration,
        settings: AppSettingsStore,
        gear: ProfileGearStore,
        phoneWorkout: IPhoneWorkoutStore,
        watchConnection: AppleWatchConnectionStore,
        spotify: SpotifyPlaybackStore,
        workoutMirroring:
            WorkoutMirroringStore? = nil,
        plannedPlanID: UUID? = nil,
        plannedSessionID: UUID? = nil
    ) async throws {
        if ATHLTHDeviceRole.isIPad {
            let envelope =
                WorkoutDeviceRelayEnvelope(
                    kind: .walk,
                    target:
                        WorkoutDeviceRelayTarget(
                            captureDevice:
                                configuration
                                    .captureDevice
                        ),
                    workoutPayload:
                        configuration
                            .trainTogetherInvitePayload,
                    watchAudioCoach:
                        settings.applyingFuelVoice(
                            to: configuration.audioCoach
                        ),
                    ghostTargetDurationSeconds:
                        nil,
                    ghostUpdates: nil,
                    spotifyPlaylist:
                        configuration
                            .spotifyPlaylist,
                    spotifyAutoplay:
                        configuration
                            .spotifyAutoplay,
                    gearIDs:
                        Array(
                            configuration.gearIDs
                        )
                )

            try await WorkoutDeviceRelayStore
                .shared
                .enqueue(envelope)
            return
        }

        try await watchConnection.requireNoActiveWatchWorkout()

        if configuration.captureDevice == .iPhone {
            workoutMirroring?
                .clearIPhoneAudioCoach()
            gear.prepareNextWorkoutGear(
                configuration.gearIDs
            )
            phoneWorkout.start(
                walking: true,
                title:
                    ATHLTHLocalization.choose(
                        english: "Walk",
                        norwegian: "Gåtur"
                    ),
                audioCoach:
                    settings.applyingFuelVoice(
                        to: configuration.audioCoach
                    ),
                routeAlerts:
                    settings.routeAlertConfiguration,
                autoPauseEnabled:
                    configuration.autoPauseEnabled,
                plannedPlanID: plannedPlanID,
                plannedSessionID: plannedSessionID
            )
            watchConnection
                .updateLocalWorkoutActivity(
                    isActive: true,
                    title:
                        ATHLTHLocalization.choose(
                            english: "Walk",
                            norwegian: "Gåtur"
                        )
                )
            startQuickSpotifyIfNeeded(
                playlist:
                    configuration.spotifyPlaylist,
                autoplay:
                    configuration.spotifyAutoplay,
                settings: settings,
                spotify: spotify
            )
            return
        }

        guard watchConnection.isReady else {
            throw NSError(
                domain: "ATHLTH.WalkLaunch",
                code: 2,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Apple Watch is not ready to start this walk."
                ]
            )
        }

        let watchWorkout =
            WatchRunningWorkoutTransfer(
                title: "",
                steps: [],
                routeAlerts:
                    settings.routeAlertConfiguration,
                autoPauseEnabled:
                    configuration.autoPauseEnabled
            )

        watchConnection
            .sendWorkoutRouteSelection(nil)

        var watchAudioCoach = settings.applyingFuelVoice(
            to: configuration.audioCoach
        )

        if workoutMirroring != nil,
           configuration.audioCoach.enabled {
            watchAudioCoach
                .preferIPhoneAudioWhenReachable =
                    true
            watchAudioCoach
                .useAcknowledgedVoiceLease = true
            workoutMirroring?
                .prepareIPhoneAudioCoach(
                    watchAudioCoach
                )
        } else {
            workoutMirroring?
                .clearIPhoneAudioCoach()
        }

        watchConnection
            .sendAudioCoachConfiguration(
                watchAudioCoach
            )
        watchConnection
            .sendRunningWorkout(
                watchWorkout
            )

        do {
            try await watchConnection
                .startWorkoutOnWatch(
                    .walking
                )
        } catch {
            workoutMirroring?
                .clearIPhoneAudioCoach()
            throw error
        }

        gear.prepareNextWorkoutGear(
            configuration.gearIDs
        )
        startQuickSpotifyIfNeeded(
            playlist:
                configuration.spotifyPlaylist,
            autoplay:
                configuration.spotifyAutoplay,
            settings: settings,
            spotify: spotify
        )

        watchConnection
            .sendAudioCoachConfiguration(
                watchAudioCoach
            )
        watchConnection
            .sendRunningWorkout(
                watchWorkout
            )
    }

    static func startStrength(
        workout: PlannedSession,
        captureDevice: WorkoutCaptureDevice,
        trackingMode: StrengthTrackingMode,
        selectedFriends: [SocialProfileCard],
        participationMode:
            SocialWorkoutParticipationMode =
                .physical,
        audioCoach: WatchAudioCoachConfiguration,
        advancedConfiguration:
            StrengthAdvancedConfiguration,
        session: AppSessionStore,
        settings: AppSettingsStore,
        social: SocialStore,
        strengthWorkout: StrengthWorkoutStore,
        watchConnection: AppleWatchConnectionStore,
        spotify: SpotifyPlaybackStore
    ) async throws -> Bool {
        try await watchConnection.requireNoActiveWatchWorkout()

        // Basic tracking can still opt into voice guidance. Keep the
        // selected coach in all workout and invitation payloads without
        // enabling advanced tracking metrics or Spotify by accident.
        let includeCoachConfiguration =
            trackingMode == .advanced ||
            advancedConfiguration.audioCoach.enabled

        var inviteAdvancedConfiguration =
            advancedConfiguration
        inviteAdvancedConfiguration.spotifyPlaylist = nil
        inviteAdvancedConfiguration.spotifyAutoplay = false

        if selectedFriends.isEmpty {
            // An unstarted social invitation must never claim this solo workout.
            social.prepareForAnotherWorkout()
        } else {
            guard await social.beginWorkoutWithFriends(
                title: workout.title,
                kind: .strength,
                friends: selectedFriends,
                creatorName:
                    session.profile.displayName,
                creatorUsername:
                    session.profile.username,
                invitePayload:
                    SocialWorkoutInvitePayload(
                        workout: workout,
                        strengthTrackingMode:
                            trackingMode,
                        strengthAdvancedConfiguration:
                            includeCoachConfiguration
                                ? inviteAdvancedConfiguration
                                : nil,
                        participationMode:
                            participationMode,
                        maxParticipants:
                            min(
                                max(
                                    selectedFriends
                                        .count + 1,
                                    2
                                ),
                                6
                            )
                    ),
                creatorCaptureDevice: captureDevice
            ) else {
                return false
            }
        }

        if ATHLTHDeviceRole.isIPad {
            let relayPayload =
                SocialWorkoutInvitePayload(
                    workout: workout,
                    strengthTrackingMode:
                        trackingMode,
                    strengthAdvancedConfiguration:
                        includeCoachConfiguration
                            ? advancedConfiguration
                            : nil
                )

            let envelope =
                WorkoutDeviceRelayEnvelope(
                    kind: .strength,
                    target:
                        WorkoutDeviceRelayTarget(
                            captureDevice:
                                captureDevice
                        ),
                    workoutPayload:
                        relayPayload,
                    watchAudioCoach:
                        audioCoach,
                    ghostTargetDurationSeconds:
                        nil,
                    ghostUpdates: nil,
                    spotifyPlaylist:
                        trackingMode == .advanced
                            ? advancedConfiguration
                                .spotifyPlaylist
                            : resolvedSpotifyPlaylist(
                                workout: workout,
                                session: session
                            ),
                    spotifyAutoplay:
                        trackingMode == .advanced
                            ? advancedConfiguration
                                .spotifyAutoplay
                            : (
                                resolvedSpotifyPlaylist(
                                    workout: workout,
                                    session: session
                                ) != nil
                            ),
                    gearIDs:
                        workout.gearIDs ?? []
                )

            try await WorkoutDeviceRelayStore
                .shared
                .enqueue(envelope)

            // A relayed workout must not open a second local strength session
            // on iPad. The iPhone becomes the authoritative workout device.
            return false
        }

        let watchSessionID: UUID?

        if captureDevice == .appleWatch {
            do {
                // Deliver coach settings before HealthKit launches the Watch
                // app so the first spoken cue cannot race the configuration.
                watchConnection
                    .sendAudioCoachConfiguration(
                        audioCoach
                    )

                try await watchConnection
                    .startWorkoutOnWatch(.strength)
                watchSessionID = UUID()
            } catch {
                await social
                    .markCurrentJoinedWorkoutLaunchFailed()
                throw error
            }
        } else {
            watchSessionID = nil
        }

        session.beginTrainingStatus(
            for: workout
        )

        strengthWorkout.start(
            session: workout,
            watchSessionID: watchSessionID,
            trackingMode: trackingMode,
            captureDevice: captureDevice,
            advancedConfiguration:
                includeCoachConfiguration
                    ? advancedConfiguration
                    : nil
        )

        if captureDevice == .iPhone {
            watchConnection
                .updateLocalWorkoutActivity(
                    isActive: true,
                    title: workout.title
                )
        }

        if captureDevice == .appleWatch {
            // The iPhone strength log is authoritative for exercise/set state.
            // Push it immediately instead of waiting for a SwiftUI observer so
            // Watch launch and iPhone view construction cannot race each other.
            if let snapshot =
                    strengthWorkout.watchSnapshot {
                watchConnection
                    .sendStrengthSnapshot(
                        snapshot
                    )
            }

            // Launch can briefly change reachability; re-send the small coach
            // payload after local strength state exists.
            watchConnection
                .sendAudioCoachConfiguration(
                    audioCoach
                )
        }

        if trackingMode == .advanced {
            if advancedConfiguration
                .spotifyAutoplay,
               let playlist =
                    advancedConfiguration
                        .spotifyPlaylist {
                Task { @MainActor in
                    await spotify.startLinkedPlaylist(
                        playlist,
                        settings: settings,
                        respectGlobalAutoplay: false
                    )
                }
            }
        } else {
            startLinkedSpotifyIfNeeded(
                workout: workout,
                session: session,
                settings: settings,
                spotify: spotify
            )
        }

        _ = await social
            .confirmCurrentJoinedWorkoutStarted()

        return true
    }
}
