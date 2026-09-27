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
            settings: settings
        )
    }

    static func start(
        reference: GhostRaceReference,
        ownerID: UUID,
        ghostRace: GhostRaceStore,
        watchConnection: AppleWatchConnectionStore,
        settings: AppSettingsStore
    ) async throws {
        try ghostRace.prepare(
            reference: reference
        )

        try await launchPrepared(
            title: reference.title,
            ownerID: ownerID,
            ghostRace: ghostRace,
            watchConnection: watchConnection,
            settings: settings
        )
    }

    static func start(
        workout: WorkoutSummary,
        detail: WorkoutDetail,
        ownerID: UUID,
        ghostRace: GhostRaceStore,
        watchConnection: AppleWatchConnectionStore,
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
            settings: settings
        )
    }

    static func start(
        workout: SocialPublishableWorkout,
        detail: WorkoutDetail,
        ownerID: UUID,
        ghostRace: GhostRaceStore,
        watchConnection: AppleWatchConnectionStore,
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
            settings: settings
        )
    }

    private static func launchPrepared(
        title: String,
        ownerID: UUID,
        ghostRace: GhostRaceStore,
        watchConnection: AppleWatchConnectionStore,
        settings: AppSettingsStore
    ) async throws {
        guard let raceRoute =
                ghostRace.temporaryRoute(
                    ownerID: ownerID
                ),
              let reference =
                ghostRace.reference
        else {
            ghostRace.cancel()
            throw GhostRacePreparationError
                .missingRoute
        }

        do {
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
                        settings
                            .ghostRaceAudioConfiguration
                )
            )

            try await watchConnection
                .startWorkoutOnWatch(
                    .running
                )

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

            // Ghost Race has its own cadence. Keep the selected language
            // available on Watch, but avoid overlapping spoken intervals.
            if settings.ghostRaceAudioEnabled {
                standardAudioCoach.enabled = false
            }

            watchConnection
                .sendAudioCoachConfiguration(
                    standardAudioCoach
                )

            watchConnection
                .sendRunningWorkout(
                    WatchRunningWorkoutTransfer(
                        title:
                            "Ghost Race · \(title)",
                        steps: [],
                        routeAlerts:
                            settings
                                .routeAlertConfiguration
                    )
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
