import SwiftUI

/// Isolates high-frequency workout mirroring updates from AppRootView.
/// The main tab hierarchy no longer needs to re-evaluate every time the Watch
/// sends a live metric snapshot.
struct ATHLTHSurfaceRuntimeObserver: View {
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var goals: GoalStore
    @EnvironmentObject private var workoutMirroring: WorkoutMirroringStore
    @EnvironmentObject private var ghostRace: GhostRaceStore
    @EnvironmentObject private var realtime:
        ATHLTHRealtimeSocialStore

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
                    workoutMirroring.snapshot
                )
        )
    }

    private func enrichedWorkoutSnapshot(
        _ snapshot:
            WatchWorkoutLiveSnapshot?
    ) -> WatchWorkoutLiveSnapshot? {
        guard var snapshot else {
            return nil
        }

        // Replay and Target Ghost already arrive from Watch with their own
        // fixed ghost timing fields. Only enrich snapshots for Live Ghost
        // when no fixed Ghost Race reference is active.
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
                                .elapsedTime
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
