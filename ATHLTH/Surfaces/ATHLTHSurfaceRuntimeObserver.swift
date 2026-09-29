import SwiftUI

/// Isolates high-frequency workout mirroring updates from AppRootView.
/// The main tab hierarchy no longer needs to re-evaluate every time the Watch
/// sends a live metric snapshot.
struct ATHLTHSurfaceRuntimeObserver: View {
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var goals: GoalStore
    @EnvironmentObject private var workoutMirroring: WorkoutMirroringStore
    @EnvironmentObject private var phoneWorkout: IPhoneWorkoutStore
    @EnvironmentObject private var ghostRace: GhostRaceStore
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var realtime:
        ATHLTHRealtimeSocialStore
    @EnvironmentObject private var watchConnection:
        AppleWatchConnectionStore

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .task {
                publishSurface()
            }
            .onChange(of: health.recovery) { _, _ in
                publishSurface()
            }
            .onChange(of: session.activePlan) { _, _ in
                publishSurface()
            }
            .onChange(of: goals.goals) { _, _ in
                publishSurface()
            }
            .onChange(of: workoutMirroring.snapshot) { _, snapshot in
                publishSurface()
                ATHLTHSurfaceCoordinator.syncLiveActivity(
                    with:
                        enrichedWorkoutSnapshot(
                            snapshot
                        )
                )
                ghostRace.update(with: snapshot)
            }
            .onChange(
                of:
                    phoneWorkout
                        .active?
                        .points
                        .count
            ) { _, _ in
                syncPhoneWorkoutGuidance()
            }
            .onChange(
                of:
                    phoneWorkout
                        .active?
                        .resumedAt
            ) { _, _ in
                syncPhoneWorkoutGuidance()
            }
            .onChange(of: realtime.liveLocations) { _, _ in
                guard ghostRace.reference == nil
                else {
                    return
                }

                publishSurface()
                ATHLTHSurfaceCoordinator
                    .syncLiveActivity(
                        with:
                            enrichedWorkoutSnapshot(
                                workoutMirroring
                                    .snapshot
                            )
                    )
            }
            .onChange(
                of:
                    realtime
                        .selectedLiveGhostSessionID
            ) { _, _ in
                publishSurface()
                ATHLTHSurfaceCoordinator
                    .syncLiveActivity(
                        with:
                            enrichedWorkoutSnapshot(
                                workoutMirroring
                                    .snapshot
                            )
                    )
            }
    }

    private func publishSurface() {
        ATHLTHSurfaceCoordinator.publishSnapshot(
            health: health,
            session: session,
            goals: goals,
            workout:
                enrichedWorkoutSnapshot(
                    workoutMirroring.snapshot ??
                    phoneWorkout
                        .currentLiveSnapshot()
                )
        )

        syncLiveGhostWatchContext()
    }

    private func syncPhoneWorkoutGuidance() {
        guard workoutMirroring.snapshot == nil,
              let snapshot =
                phoneWorkout
                    .currentLiveSnapshot()
        else {
            return
        }

        ghostRace.update(with: snapshot)

        if let reference =
                ghostRace.reference,
           let comparison =
                ghostRace.comparison {
            phoneWorkout.applyGhostComparison(
                comparison,
                title: reference.title,
                configuration:
                    settings
                        .ghostRaceAudioConfiguration
            )
        }

        let enriched =
            enrichedWorkoutSnapshot(
                phoneWorkout
                    .currentLiveSnapshot() ??
                snapshot
            )

        ATHLTHSurfaceCoordinator
            .syncLiveActivity(
                with: enriched
            )
        publishSurface()
    }

    private func syncLiveGhostWatchContext() {
        var context =
            ATHLTHLiveWorkoutContextStore
                .load()

        let nextLiveGhost:
            ATHLTHLiveGhostContext? = {
            guard ghostRace.reference == nil,
                  let snapshot =
                    workoutMirroring.snapshot,
                  snapshot.kind == .running,
                  let selectedSession =
                    realtime
                        .selectedLiveGhostSession,
                  let comparison =
                    realtime
                        .liveGhostComparison(
                            ownDistanceMeters:
                                snapshot
                                    .distanceMeters,
                            ownElapsedSeconds:
                                snapshot
                                    .elapsedTime
                        )
            else {
                return nil
            }

            return ATHLTHLiveGhostContext(
                title:
                    "Live · \(selectedSession.title)",
                distanceDeltaMeters:
                    comparison
                        .signedDistanceMeters,
                estimatedTimeDeltaSeconds:
                    comparison
                        .estimatedTimeDeltaSeconds,
                updatedAt:
                    comparison.updatedAt
            )
        }()

        guard context.liveGhost !=
                nextLiveGhost
        else {
            return
        }

        context.liveGhost =
            nextLiveGhost

        watchConnection
            .sendLiveSurfaceContext(
                context
            )
    }

    private func enrichedWorkoutSnapshot(
        _ snapshot:
            WatchWorkoutLiveSnapshot?
    ) -> WatchWorkoutLiveSnapshot? {
        guard var snapshot else {
            return nil
        }

        if let reference =
                ghostRace.reference,
           let comparison =
                ghostRace.comparison {
            snapshot.ghostRaceTitle =
                reference.title
            snapshot.ghostDistanceDeltaMeters =
                comparison
                    .signedDistanceMeters
            snapshot.ghostTimeDeltaSeconds =
                comparison
                    .signedTimeSeconds
            return snapshot
        }

        // Fixed Ghost comparisons are now shared by Watch and iPhone.
        // Only fall through to Live Ghost when no fixed reference is active.
        guard ghostRace.reference == nil,
              snapshot.kind == .running,
              let session =
                realtime
                    .selectedLiveGhostSession,
              let comparison =
                realtime
                    .liveGhostComparison(
                        ownDistanceMeters:
                            snapshot
                                .distanceMeters,
                        ownElapsedSeconds:
                            snapshot
                                .elapsedTime,
                        ownRouteKey:
                            snapshot
                                .routeComparisonID,
                        ownRouteProgressPercent:
                            snapshot
                                .routeProgressPercent,
                        ownRouteDeviationMeters:
                            snapshot
                                .routeDeviationMeters
                    )
        else {
            return snapshot
        }

        snapshot.ghostRaceTitle =
            "Live · \(session.title)"
        snapshot.ghostDistanceDeltaMeters =
            comparison
                .signedDistanceMeters
        snapshot.ghostTimeDeltaSeconds =
            comparison
                .estimatedTimeDeltaSeconds

        return snapshot
    }
}
