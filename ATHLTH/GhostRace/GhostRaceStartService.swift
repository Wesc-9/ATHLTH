import CoreLocation
import Foundation

/// A route-free Ghost uses the normal structured run transfer and shared
/// virtual pacer. No fabricated map, route ID, or second workout clock.
struct ATHLTHSoloGhostTemplate: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let paceSeconds: Double
    let distanceMeters: Double?
    let durationSeconds: Double?

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            ATHLTHSoloGhostPacePolicy.transfer(paceSeconds: paceSeconds,
                distanceMeters: distanceMeters, durationSeconds: durationSeconds) != nil
    }
}

enum ATHLTHSoloGhostTemplateStore {
    private static let name = "soloGhostTemplates"

    static func load(userID: UUID) -> [ATHLTHSoloGhostTemplate] {
        (AccountLocalStorage.read([ATHLTHSoloGhostTemplate].self, name: name, userID: userID) ?? [])
            .filter(\.isValid)
    }

    static func save(_ template: ATHLTHSoloGhostTemplate, userID: UUID) {
        guard template.isValid else { return }
        var values = load(userID: userID)
        values.removeAll {
            $0.id == template.id || ($0.paceSeconds == template.paceSeconds &&
                $0.distanceMeters == template.distanceMeters && $0.durationSeconds == template.durationSeconds &&
                $0.name == template.name)
        }
        values.insert(template, at: 0)
        AccountLocalStorage.write(Array(values.prefix(50)), name: name, userID: userID)
    }

    static func remove(_ id: UUID, userID: UUID) {
        AccountLocalStorage.write(load(userID: userID).filter { $0.id != id }, name: name, userID: userID)
    }
}

enum ATHLTHSoloGhostPacePolicy {
    struct Preset {
        let title: String
        let meters: Double
    }
    static let presets: [Preset] = [
        .init(title: "1 km", meters: 1_000), .init(title: "2 km", meters: 2_000),
        .init(title: "5 km", meters: 5_000), .init(title: "10 km", meters: 10_000),
        .init(title: "Halvmaraton", meters: 21_097.5), .init(title: "Maraton", meters: 42_195)
    ]

    static func transfer(paceSeconds: Double, distanceMeters: Double?,
                         durationSeconds: Double?) -> WatchRunningWorkoutTransfer? {
        guard paceSeconds.isFinite, (120...1_800).contains(paceSeconds),
              distanceMeters == nil || durationSeconds == nil else { return nil }
        if let distanceMeters, !distanceMeters.isFinite || !(200...100_000).contains(distanceMeters) { return nil }
        if let durationSeconds, !durationSeconds.isFinite || !(60...86_400).contains(durationSeconds) { return nil }
        let step = WatchRunningWorkoutStep(
            id: UUID(), title: "Ghost Race",
            measure: distanceMeters != nil ? .distance : durationSeconds != nil ? .time : .open,
            distanceMeters: distanceMeters, durationSeconds: durationSeconds,
            intensityText: nil, phase: "work", ghostPaceSecondsPerKilometer: paceSeconds)
        var configuration = ATHLTHIntervalGhostPacer.WorkoutConfiguration()
        configuration.isEnabled = true
        configuration.defaultPaceSecondsPerKilometer = paceSeconds
        configuration.coverage = .entireWorkout
        var transfer = WatchRunningWorkoutTransfer(title: "Ghost Race", steps: [step])
        transfer.intervalGhostConfiguration = configuration
        transfer.soloGhostRace = true
        transfer.autoAdvanceTimedSteps = true
        return transfer
    }
}

@MainActor
enum GhostRaceStartService {
    static func startSoloPace(
        paceSeconds: Double, distanceMeters: Double?, durationSeconds: Double?,
        ghostRace: GhostRaceStore, realtime: ATHLTHRealtimeSocialStore,
        watchConnection: AppleWatchConnectionStore, phoneWorkout: IPhoneWorkoutStore,
        captureDevice: WorkoutCaptureDevice, settings: AppSettingsStore,
        maximumHeartRateBPM: Double? = nil
    ) async throws {
        func failure(_ message: String) -> NSError {
            NSError(domain: "ATHLTH.SoloGhost", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: message])
        }
        guard var transfer = ATHLTHSoloGhostPacePolicy.transfer(
            paceSeconds: paceSeconds, distanceMeters: distanceMeters, durationSeconds: durationSeconds
        ) else { throw failure("Velg en gyldig målfart og distanse.") }
        guard phoneWorkout.active == nil, !phoneWorkout.hasPendingLaunch,
              !watchConnection.workoutLaunchInProgress else {
            throw failure("Avslutt den aktive treningsøkten før du starter Ghost Race.")
        }
        if captureDevice == .iPhone && !phoneWorkout.canStartSynchronizedOutdoorWorkout {
            phoneWorkout.requestLiveGhostLocationPermissionIfNeeded()
            throw failure("Gi ATHLTH stedstilgang og prøv å starte igjen.")
        }
        if captureDevice == .appleWatch && !watchConnection.isReady {
            throw failure("Apple Watch er ikke klar til å starte.")
        }
        try await watchConnection.requireNoActiveWatchWorkout()
        guard phoneWorkout.active == nil, !phoneWorkout.hasPendingLaunch,
              !watchConnection.hasActiveIPhoneWorkout,
              !watchConnection.workoutLaunchInProgress else {
            throw failure("En annen treningsøkt er aktiv eller i ferd med å starte.")
        }
        transfer.heartRateZoneMaximumBPM = maximumHeartRateBPM
        var audio = settings.audioCoachConfiguration(enabled: settings.audioCoachEnabledByDefault,
                                                    routeDistanceMeters: distanceMeters)
        if captureDevice == .appleWatch {
            audio.preferIPhoneAudioWhenReachable = false
            audio.useAcknowledgedVoiceLease = false
        }
        // Reset only stale route Ghost state; the workout owns all pace progress.
        realtime.selectLiveGhost(nil)
        ghostRace.cancel()
        watchConnection.sendWorkoutRouteSelection(nil)
        watchConnection.clearGhostRace()
        if captureDevice == .iPhone {
            phoneWorkout.start(walking: false, title: transfer.title,
                               audioCoach: audio, structuredWorkout: transfer)
            guard phoneWorkout.active != nil else {
                throw failure("Ghost Race kunne ikke starte. Kontroller stedstilgang og aktiv økt.")
            }
        } else {
            watchConnection.sendAudioCoachConfiguration(audio)
            watchConnection.sendRunningWorkout(transfer)
            try await watchConnection.startWorkoutOnWatch(.running)
            watchConnection.sendWorkoutRouteSelection(nil)
            watchConnection.clearGhostRace()
            watchConnection.sendAudioCoachConfiguration(audio)
            watchConnection.sendRunningWorkout(transfer)
        }
    }

    static func start(
        workoutID: UUID,
        title: String,
        activity: WorkoutActivity,
        startedAt: Date,
        duration: TimeInterval,
        distanceMeters: Double?,
        route: [CLLocation],
        ownerID: UUID,
        ghostRace: GhostRaceStore,
        watchConnection: AppleWatchConnectionStore,
        phoneWorkout: IPhoneWorkoutStore? = nil,
        captureDevice: WorkoutCaptureDevice = .appleWatch,
        settings: AppSettingsStore,
        maximumHeartRateBPM: Double? = nil
    ) async throws {
        try ghostRace.prepare(
            workoutID: workoutID,
            title: title,
            activity: activity,
            startedAt: startedAt,
            duration: duration,
            distanceMeters: distanceMeters,
            route: route
        )

        try await launchPrepared(
            title: title,
            ownerID: ownerID,
            ghostRace: ghostRace,
            watchConnection: watchConnection,
            phoneWorkout: phoneWorkout,
            captureDevice: captureDevice,
            settings: settings,
            maximumHeartRateBPM: maximumHeartRateBPM
        )
    }

    static func start(
        reference: GhostRaceReference,
        ownerID: UUID,
        comparisonRouteID: UUID? = nil,
        opponentName: String? = nil,
        ghostRace: GhostRaceStore,
        watchConnection: AppleWatchConnectionStore,
        phoneWorkout: IPhoneWorkoutStore? = nil,
        captureDevice: WorkoutCaptureDevice = .appleWatch,
        settings: AppSettingsStore,
        maximumHeartRateBPM: Double? = nil
    ) async throws {
        try ghostRace.prepare(
            reference: reference
        )

        try await launchPrepared(
            title: reference.title,
            ownerID: ownerID,
            comparisonRouteID:
                comparisonRouteID,
            opponentName:
                opponentName,
            ghostRace: ghostRace,
            watchConnection: watchConnection,
            phoneWorkout: phoneWorkout,
            captureDevice: captureDevice,
            settings: settings,
            maximumHeartRateBPM: maximumHeartRateBPM
        )
    }

    static func startTarget(
        route: TrainingRoute,
        targetDurationSeconds: TimeInterval,
        strategy: GhostTargetPacingStrategy = .even,
        ownerID: UUID,
        ghostRace: GhostRaceStore,
        watchConnection: AppleWatchConnectionStore,
        phoneWorkout: IPhoneWorkoutStore? = nil,
        captureDevice: WorkoutCaptureDevice = .appleWatch,
        settings: AppSettingsStore,
        maximumHeartRateBPM: Double? = nil
    ) async throws {
        try ghostRace.prepareTarget(
            route: route,
            targetDurationSeconds: targetDurationSeconds,
            strategy: strategy
        )

        try await launchPrepared(
            title:
                "Target · \(route.title)",
            ownerID: ownerID,
            ghostRace: ghostRace,
            watchConnection:
                watchConnection,
            phoneWorkout: phoneWorkout,
            captureDevice: captureDevice,
            settings: settings,
            maximumHeartRateBPM: maximumHeartRateBPM
        )
    }

    static func start(
        workout: WorkoutSummary,
        detail: WorkoutDetail,
        ownerID: UUID,
        ghostRace: GhostRaceStore,
        watchConnection: AppleWatchConnectionStore,
        phoneWorkout: IPhoneWorkoutStore? = nil,
        captureDevice: WorkoutCaptureDevice = .appleWatch,
        settings: AppSettingsStore,
        maximumHeartRateBPM: Double? = nil
    ) async throws {
        try await start(
            workoutID: workout.id,
            title: workout.activity.rawValue,
            activity: workout.activity,
            startedAt: workout.startDate,
            duration: workout.duration,
            distanceMeters:
                workout.distanceMeters,
            route: detail.route,
            ownerID: ownerID,
            ghostRace: ghostRace,
            watchConnection: watchConnection,
            phoneWorkout: phoneWorkout,
            captureDevice: captureDevice,
            settings: settings,
            maximumHeartRateBPM: maximumHeartRateBPM
        )
    }

    static func start(
        workout: SocialPublishableWorkout,
        detail: WorkoutDetail,
        ownerID: UUID,
        ghostRace: GhostRaceStore,
        watchConnection: AppleWatchConnectionStore,
        phoneWorkout: IPhoneWorkoutStore? = nil,
        captureDevice: WorkoutCaptureDevice = .appleWatch,
        settings: AppSettingsStore,
        maximumHeartRateBPM: Double? = nil
    ) async throws {
        try await start(
            workoutID: workout.id,
            title: workout.title,
            activity: workout.activity,
            startedAt: workout.startDate,
            duration: workout.duration,
            distanceMeters:
                workout.distanceMeters,
            route: detail.route,
            ownerID: ownerID,
            ghostRace: ghostRace,
            watchConnection: watchConnection,
            phoneWorkout: phoneWorkout,
            captureDevice: captureDevice,
            settings: settings,
            maximumHeartRateBPM: maximumHeartRateBPM
        )
    }

    static func start(
        attempt: RouteAttemptRecord,
        route: TrainingRoute,
        health: HealthKitManager,
        ownerID: UUID,
        ghostRace: GhostRaceStore,
        watchConnection: AppleWatchConnectionStore,
        phoneWorkout: IPhoneWorkoutStore? = nil,
        captureDevice: WorkoutCaptureDevice = .appleWatch,
        settings: AppSettingsStore,
        maximumHeartRateBPM: Double? = nil
    ) async throws {
        let detail =
            await health.workoutDetail(
                for: attempt.workoutID
            )

        try await start(
            workoutID:
                attempt.workoutID,
            title:
                route.title,
            activity: .running,
            startedAt:
                attempt.startedAt,
            duration:
                attempt.durationSeconds,
            distanceMeters:
                attempt.distanceMeters,
            route:
                detail.route,
            ownerID: ownerID,
            ghostRace: ghostRace,
            watchConnection: watchConnection,
            phoneWorkout: phoneWorkout,
            captureDevice: captureDevice,
            settings: settings,
            maximumHeartRateBPM: maximumHeartRateBPM
        )
    }

    static func startLive(
        title: String,
        route: TrainingRoute? = nil,
        ghostRace: GhostRaceStore,
        watchConnection: AppleWatchConnectionStore,
        phoneWorkout: IPhoneWorkoutStore? = nil,
        captureDevice: WorkoutCaptureDevice = .appleWatch,
        settings: AppSettingsStore,
        maximumHeartRateBPM: Double? = nil
    ) async throws {
        // Live Ghost compares a fresh cloud opponent instead of a fixed
        // timing profile. When both athletes share a stable route key, load
        // that route on Watch so progress can be compared along the course.
        ghostRace.cancel()
        watchConnection.clearGhostRace()

        do {
            if captureDevice == .iPhone {
                guard let phoneWorkout else {
                    throw NSError(
                        domain: "ATHLTH.GhostRace",
                        code: 20,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                "iPhone workout recorder is unavailable."
                        ]
                    )
                }

                guard phoneWorkout.active == nil else {
                    throw NSError(
                        domain: "ATHLTH.GhostRace",
                        code: 21,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                "Finish the active iPhone workout before starting Ghost Race."
                        ]
                    )
                }

                guard phoneWorkout.canStartSynchronizedOutdoorWorkout else {
                    throw NSError(
                        domain: "ATHLTH.GhostRace",
                        code: 22,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                ATHLTHLocalization.choose(
                                    english: "Allow iPhone location access and sign in before starting a synchronized race.",
                                    norwegian: "Tillat stedstilgang på iPhone og logg inn før du starter en synkronisert duell."
                                )
                        ]
                    )
                }

                var coach =
                    settings.audioCoachConfiguration(
                        enabled:
                            settings
                                .audioCoachEnabledByDefault,
                        routeDistanceMeters:
                            route.map {
                                max(
                                    $0.distanceKilometers *
                                        1_000,
                                    0
                                )
                            }
                    )

                let ghostAudio =
                    coexistingGhostAudio(
                        settings
                            .ghostRaceAudioConfiguration,
                        audioCoach: coach
                    )

                phoneWorkout.start(
                    walking: false,
                    route: route,
                    title:
                        "Live Ghost · \(title)",
                    audioCoach: coach,
                    routeAlerts:
                        settings
                            .routeAlertConfiguration,
                    ghostUpdates:
                        ghostAudio
                )
                // start() may reject recording without throwing (for
                // example when a previous workout is still saving). A
                // synchronized duel must not claim a successful local
                // launch until the recorder actually exists.
                guard phoneWorkout.active != nil else {
                    throw NSError(
                        domain: "ATHLTH.GhostRace",
                        code: 23,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                ATHLTHLocalization.choose(
                                    english: "The iPhone workout could not begin. Check location permission and try again before the countdown.",
                                    norwegian: "iPhone-økten kunne ikke starte. Kontroller stedstilgang og prøv igjen før nedtellingen."
                                )
                        ]
                    )
                }
                return
            }

            if let route {
                try watchConnection.sendRoute(
                    route
                )
                watchConnection
                    .sendWorkoutRouteSelection(
                        route.id
                    )
            } else {
                watchConnection
                    .sendWorkoutRouteSelection(
                        nil
                    )
            }

            var liveCoach = settings.audioCoachConfiguration(
                enabled: settings.audioCoachEnabledByDefault,
                routeDistanceMeters: route.map {
                    max($0.distanceKilometers * 1_000, 0)
                }
            )
            // Watch-owned Ghost voices must not be split between speakers.
            liveCoach.preferIPhoneAudioWhenReachable = false
            liveCoach.useAcknowledgedVoiceLease = false

            var runningTransfer =
                WatchRunningWorkoutTransfer(
                    title:
                        "Live Ghost · \(title)",
                    steps: [],
                    routeAlerts:
                        settings
                            .routeAlertConfiguration
                )

            runningTransfer.heartRateZoneMaximumBPM = maximumHeartRateBPM

            // Send ATHLTH guidance before HealthKit starts the Watch session.
            // This removes the launch race where the first kilometre could
            // begin with the Watch still holding an older/disabled coach config.
            watchConnection
                .sendAudioCoachConfiguration(
                    liveCoach
                )
            watchConnection
                .sendRunningWorkout(
                    runningTransfer
                )

            try await watchConnection
                .startWorkoutOnWatch(
                    .running
                )

            // Re-send after launch as a durable fallback while WCSession
            // reachability is settling.
            watchConnection
                .sendAudioCoachConfiguration(
                    liveCoach
                )
            watchConnection
                .sendRunningWorkout(
                    runningTransfer
                )
        } catch {
            watchConnection
                .sendWorkoutRouteSelection(nil)
            throw error
        }
    }

    static func coexistingGhostAudio(
        _ ghostAudio:
            WatchGhostRaceAudioConfiguration?,
        audioCoach:
            WatchAudioCoachConfiguration
    ) -> WatchGhostRaceAudioConfiguration? {
        guard var ghostAudio
        else {
            return nil
        }

        let coachHasPeriodicCue =
            audioCoach.enabled &&
            (
                (audioCoach
                    .distanceIntervalMeters ??
                    0) > 0 ||
                (audioCoach
                    .timeIntervalSeconds ??
                    0) > 0
            )

        if coachHasPeriodicCue,
           ghostAudio.enabled,
           ghostAudio
            .resolvedPeriodicDelivery
            .usesVoice {
            // If both fire on the same kilometre the higher-priority Ghost
            // cue wins and the user's ordinary Audio Coach metric cue gets
            // dropped by the guidance priority gate. Keep Ghost's periodic
            // awareness as a haptic, while lead changes and important race
            // events keep their configured voice/haptic delivery.
            ghostAudio.periodicDelivery =
                .haptic
        }

        return ghostAudio
    }

    static func preparedTransfer(
        ghostRace: GhostRaceStore,
        audio:
            WatchGhostRaceAudioConfiguration
    ) -> WatchGhostRaceTransfer? {
        guard let reference =
                ghostRace.reference
        else {
            return nil
        }

        let pointStep =
            max(
                reference.points.count /
                    320,
                1
            )
        var points =
            reference.points
                .enumerated()
                .compactMap {
                    index,
                    point
                    -> WatchGhostRaceTimingPoint? in

                    guard index % pointStep == 0 ||
                            index ==
                            reference.points.count - 1
                    else {
                        return nil
                    }

                    return WatchGhostRaceTimingPoint(
                        elapsedTime:
                            point.elapsedTime,
                        cumulativeMeters:
                            point.cumulativeMeters
                    )
                }

        if let final =
                reference.points.last,
           points.last?.cumulativeMeters !=
                final.cumulativeMeters {
            points.append(
                WatchGhostRaceTimingPoint(
                    elapsedTime:
                        final.elapsedTime,
                    cumulativeMeters:
                        final.cumulativeMeters
                )
            )
        }

        return WatchGhostRaceTransfer(
            title: reference.title,
            referenceDuration:
                reference.durationSeconds,
            routeDistanceMeters:
                reference.routeDistanceMeters,
            points: points,
            audio: audio
        )
    }

    private static func launchPrepared(
        title: String,
        ownerID: UUID,
        comparisonRouteID: UUID? = nil,
        opponentName: String? = nil,
        ghostRace: GhostRaceStore,
        watchConnection: AppleWatchConnectionStore,
        phoneWorkout: IPhoneWorkoutStore?,
        captureDevice: WorkoutCaptureDevice,
        settings: AppSettingsStore,
        maximumHeartRateBPM: Double? = nil
    ) async throws {
        guard let raceRoute =
                ghostRace.temporaryRoute(
                    ownerID: ownerID,
                    comparisonRouteID:
                        comparisonRouteID
                ),
              let reference =
                ghostRace.reference
        else {
            ghostRace.cancel()
            throw GhostRacePreparationError
                .missingRoute
        }

        do {
            var standardAudioCoach =
                settings.audioCoachConfiguration(
                    enabled:
                        settings
                            .audioCoachEnabledByDefault,
                    routeDistanceMeters:
                        raceRoute
                            .distanceKilometers *
                            1_000
                )
            if captureDevice == .appleWatch {
                standardAudioCoach.preferIPhoneAudioWhenReachable = false
                standardAudioCoach.useAcknowledgedVoiceLease = false
            }
            let ghostAudio =
                coexistingGhostAudio(
                    settings
                        .ghostRaceAudioConfiguration,
                    audioCoach:
                        standardAudioCoach
                )

            if captureDevice == .iPhone {
                guard let phoneWorkout else {
                    throw NSError(
                        domain: "ATHLTH.GhostRace",
                        code: 22,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                "iPhone workout recorder is unavailable."
                        ]
                    )
                }

                guard phoneWorkout.active == nil else {
                    throw NSError(
                        domain: "ATHLTH.GhostRace",
                        code: 23,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                "Finish the active iPhone workout before starting Ghost Race."
                        ]
                    )
                }

                phoneWorkout.start(
                    walking: false,
                    route: raceRoute,
                    title:
                        "Ghost Race · \(title)",
                    audioCoach:
                        standardAudioCoach,
                    routeAlerts:
                        settings
                            .routeAlertConfiguration,
                    ghostUpdates:
                        ghostAudio
                )
                guard phoneWorkout.active != nil else {
                    throw NSError(
                        domain: "ATHLTH.GhostRace",
                        code: 24,
                        userInfo: [NSLocalizedDescriptionKey:
                            ATHLTHLocalization.choose(
                                english: "Ghost Race could not start recording on iPhone. Check location access and try again.",
                                norwegian: "Ghost Race fikk ikke startet registreringen på iPhone. Kontroller stedstilgang og prøv igjen."
                            )]
                    )
                }
                phoneWorkout
                    .configureGhostOpponentName(
                        opponentName
                    )
                return
            }

            try watchConnection.sendRoute(
                raceRoute
            )
            watchConnection
                .sendWorkoutRouteSelection(
                    raceRoute.id
                )

            let watchPointStep =
                max(
                    reference.points.count /
                        320,
                    1
                )

            var watchPoints =
                reference.points
                    .enumerated()
                    .compactMap {
                        index,
                        point
                        -> WatchGhostRaceTimingPoint? in

                        guard index %
                                    watchPointStep ==
                                    0 ||
                                index ==
                                    reference
                                        .points
                                        .count -
                                    1
                        else {
                            return nil
                        }

                        return WatchGhostRaceTimingPoint(
                            elapsedTime:
                                point.elapsedTime,
                            cumulativeMeters:
                                point
                                    .cumulativeMeters
                        )
                    }

            if let final =
                    reference.points.last,
               watchPoints.last?
                .cumulativeMeters !=
                    final.cumulativeMeters {
                watchPoints.append(
                    WatchGhostRaceTimingPoint(
                        elapsedTime:
                            final.elapsedTime,
                        cumulativeMeters:
                            final.cumulativeMeters
                    )
                )
            }

            let ghostTransfer = WatchGhostRaceTransfer(
                    title: reference.title,
                    referenceDuration:
                        reference
                            .durationSeconds,
                    routeDistanceMeters:
                        reference
                            .routeDistanceMeters,
                    points: watchPoints,
                    audio:
                        ghostAudio,
                    opponentName:
                        opponentName
                )
            watchConnection.sendGhostRace(ghostTransfer)

            var runningTransfer =
                WatchRunningWorkoutTransfer(
                    title: "Ghost Race · \(title)",
                    steps: [],
                    routeAlerts: settings.routeAlertConfiguration
                )
            runningTransfer.heartRateZoneMaximumBPM = maximumHeartRateBPM

            // Audio Coach owns the user's requested periodic metric cadence.
            // Ghost keeps haptic periodic status plus important lead-change
            // alerts so the two systems do not talk over one another.
            watchConnection
                .sendAudioCoachConfiguration(
                    standardAudioCoach
                )
            watchConnection
                .sendRunningWorkout(
                    runningTransfer
                )

            try await watchConnection
                .startWorkoutOnWatch(
                    .running
                )

            // A HealthKit remote launch can start before queued WCSession data
            // reaches Watch. Refresh the fixed Ghost after startup as well,
            // otherwise the workout may run with no opponent.
            watchConnection.sendWorkoutRouteSelection(raceRoute.id)
            watchConnection.sendGhostRace(ghostTransfer)
            watchConnection
                .sendAudioCoachConfiguration(
                    standardAudioCoach
                )
            watchConnection
                .sendRunningWorkout(
                    runningTransfer
                )
        } catch {
            ghostRace.cancel()
            watchConnection
                .sendWorkoutRouteSelection(nil)
            watchConnection
                .clearGhostRace()
            throw error
        }
    }
}
