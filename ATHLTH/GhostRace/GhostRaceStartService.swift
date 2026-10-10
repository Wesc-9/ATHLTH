import CoreLocation
import Foundation

@MainActor
enum GhostRaceStartService {
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
        settings: AppSettingsStore
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
            settings: settings
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
        settings: AppSettingsStore
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
            settings: settings
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
        settings: AppSettingsStore
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
            settings: settings
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
        settings: AppSettingsStore
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
            settings: settings
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
        settings: AppSettingsStore
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
            settings: settings
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
        settings: AppSettingsStore
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
            settings: settings
        )
    }

    static func startLive(
        title: String,
        route: TrainingRoute? = nil,
        ghostRace: GhostRaceStore,
        watchConnection: AppleWatchConnectionStore,
        phoneWorkout: IPhoneWorkoutStore? = nil,
        captureDevice: WorkoutCaptureDevice = .appleWatch,
        settings: AppSettingsStore
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

            let liveCoach =
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

            let runningTransfer =
                WatchRunningWorkoutTransfer(
                    title:
                        "Live Ghost · \(title)",
                    steps: [],
                    routeAlerts:
                        settings
                            .routeAlertConfiguration
                )

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
        settings: AppSettingsStore
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
            let standardAudioCoach =
                settings.audioCoachConfiguration(
                    enabled:
                        settings
                            .audioCoachEnabledByDefault,
                    routeDistanceMeters:
                        raceRoute
                            .distanceKilometers *
                            1_000
                )
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

            watchConnection.sendGhostRace(
                WatchGhostRaceTransfer(
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
            )

            let runningTransfer =
                WatchRunningWorkoutTransfer(
                    title:
                        "Ghost Race · \(title)",
                    steps: [],
                    routeAlerts:
                        settings
                            .routeAlertConfiguration
                )

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
