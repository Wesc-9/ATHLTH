import Foundation

struct PlannedWorkoutWatchBuilder {
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
                routeAlerts: routeAlerts,
                targetAlerts:
                    workout.targetAlertConfiguration,
                autoPauseEnabled:
                    autoPauseEnabled ??
                    workout.autoPauseEnabled
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
            routeAlerts: routeAlerts,
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
            routeAlerts: routeAlerts,
            autoPauseEnabled: autoPauseEnabled
        )
    }

    private static func runningSteps(
        from template: RunningWorkoutTemplate
    ) -> [WatchRunningWorkoutStep] {
        template.blocks.flatMap { block in
            let repetitions = max(
                block.repetitions,
                1
            )
            var result:
                [WatchRunningWorkoutStep] = []

            for repetition in 0..<repetitions {
                result.append(
                    runningStep(
                        title:
                            repetitions > 1
                                ? "\(block.title) \(repetition + 1)/\(repetitions)"
                                : block.title,
                        target: block.work
                    )
                )

                if repetition < repetitions - 1,
                   let recovery = block.recovery {
                    result.append(
                        runningStep(
                            title: "Recovery",
                            target: recovery
                        )
                    )
                }
            }

            return result
        }
    }

    private static func runningStep(
        title: String,
        target: RunningStepTarget
    ) -> WatchRunningWorkoutStep {
        let measure: WatchRunningStepMeasure

        switch target.measure {
        case .distance:
            measure = .distance
        case .time:
            measure = .time
        case .open:
            measure = .open
        }

        return WatchRunningWorkoutStep(
            id: UUID(),
            title: title,
            measure: measure,
            distanceMeters: target.distanceMeters,
            durationSeconds: target.durationSeconds,
            intensityText:
                runningIntensityText(
                    target.intensity
                ),
            targetPaceMinSecondsPerKilometer:
                target.intensity
                    .paceMinSecondsPerKilometer,
            targetPaceMaxSecondsPerKilometer:
                target.intensity
                    .paceMaxSecondsPerKilometer
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
            WorkoutMirroringStore? = nil
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
                        configuration.audioCoach,
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

        var resolvedAudioCoach =
            configuration.audioCoach

        if configuration
            .ghostTargetDurationSeconds != nil,
           configuration.ghostUpdates != nil {
            // Ghost owns recurring race cadence. Keep Audio Coach active for
            // structured-step and critical guidance without duplicate periodic
            // metric announcements.
            resolvedAudioCoach
                .distanceIntervalMeters = nil
            resolvedAudioCoach
                .timeIntervalSeconds = nil
        }

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
            }

        if configuration.captureDevice == .iPhone {
            workoutMirroring?
                .clearIPhoneAudioCoach()
            gear.prepareNextWorkoutGear(
                configuration.gearIDs
            )
            phoneWorkout.start(
                walking: false,
                route: selectedRoute,
                title: configuration.title,
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
                    configuration
                        .ghostUpdates,
                autoPauseEnabled:
                    configuration
                        .autoPauseEnabled
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
                        "Apple Watch is not ready to start this run."
                ]
            )
        }

        if let selectedRoute {
            try watchConnection.sendRoute(
                selectedRoute
            )
            watchConnection
                .sendWorkoutRouteSelection(
                    selectedRoute.id
                )
        } else {
            watchConnection
                .sendWorkoutRouteSelection(nil)
        }

        if let ghostRace,
           configuration
                .ghostTargetDurationSeconds != nil,
           let transfer =
                GhostRaceStartService
                    .preparedTransfer(
                        ghostRace: ghostRace,
                        audio:
                            configuration
                                .ghostUpdates ??
                            .disabled
                    ) {
            watchConnection
                .sendGhostRace(transfer)
        }

        let watchRunningWorkout =
            structuredWorkout ??
            WatchRunningWorkoutTransfer(
                title: "",
                steps: [],
                routeAlerts:
                    configuration
                        .routeAlerts,
                autoPauseEnabled:
                    configuration
                        .autoPauseEnabled
            )

        // A Watch-owned workout launched from iPhone still uses iPhone as the
        // Audio Coach owner. This keeps spoken guidance on the same system
        // route as Spotify/AirPods while Watch remains authoritative for
        // workout capture. Direct Watch-started workouts keep Watch audio.
        let iPhoneOwnsAudioCoach =
            workoutMirroring != nil &&
            resolvedAudioCoach.enabled

        if iPhoneOwnsAudioCoach {
            workoutMirroring?
                .prepareIPhoneAudioCoach(
                    resolvedAudioCoach
                )
        } else {
            workoutMirroring?
                .clearIPhoneAudioCoach()
        }

        let watchAudioCoach:
            WatchAudioCoachConfiguration =
                iPhoneOwnsAudioCoach
                    ? .disabled
                    : resolvedAudioCoach

        // Deliver ATHLTH-specific run state before asking HealthKit to launch
        // the Watch. This avoids a launch race where the workout session starts
        // before intervals or alerts have arrived.
        watchConnection
            .sendAudioCoachConfiguration(
                watchAudioCoach
            )
        watchConnection
            .sendRunningWorkout(
                watchRunningWorkout
            )

        do {
            try await watchConnection
                .startWorkoutOnWatch(
                    .running,
                    indoor:
                        configuration.environment ==
                        .treadmill
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

        // Launch can briefly change WCSession reachability. Re-send the small
        // configuration payload after launch; the connection store queues a
        // durable fallback if the immediate message cannot be delivered.
        watchConnection
            .sendAudioCoachConfiguration(
                watchAudioCoach
            )
        watchConnection
            .sendRunningWorkout(
                watchRunningWorkout
            )

        if let selectedRoute {
            watchConnection
                .sendWorkoutRouteSelection(
                    selectedRoute.id
                )
        } else {
            watchConnection
                .sendWorkoutRouteSelection(nil)
        }
    }

    static func startWalkQuick(
        configuration: WalkQuickStartConfiguration,
        settings: AppSettingsStore,
        gear: ProfileGearStore,
        phoneWorkout: IPhoneWorkoutStore,
        watchConnection: AppleWatchConnectionStore,
        spotify: SpotifyPlaybackStore,
        workoutMirroring:
            WorkoutMirroringStore? = nil
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
                        configuration.audioCoach,
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
                    configuration.audioCoach,
                routeAlerts:
                    settings.routeAlertConfiguration,
                autoPauseEnabled:
                    configuration.autoPauseEnabled
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

        let iPhoneOwnsAudioCoach =
            workoutMirroring != nil &&
            configuration.audioCoach.enabled

        if iPhoneOwnsAudioCoach {
            workoutMirroring?
                .prepareIPhoneAudioCoach(
                    configuration.audioCoach
                )
        } else {
            workoutMirroring?
                .clearIPhoneAudioCoach()
        }

        let watchAudioCoach:
            WatchAudioCoachConfiguration =
                iPhoneOwnsAudioCoach
                    ? .disabled
                    : configuration.audioCoach

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
        var inviteAdvancedConfiguration =
            advancedConfiguration
        inviteAdvancedConfiguration.spotifyPlaylist = nil
        inviteAdvancedConfiguration.spotifyAutoplay = false

        if !selectedFriends.isEmpty {
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
                            trackingMode == .advanced
                                ? inviteAdvancedConfiguration
                                : nil
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
                        trackingMode == .advanced
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
                trackingMode == .advanced
                    ? advancedConfiguration
                    : nil
        )

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
