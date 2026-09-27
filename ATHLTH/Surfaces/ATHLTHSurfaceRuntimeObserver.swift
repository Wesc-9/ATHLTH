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
                    with: snapshot
                )
                ghostRace.update(with: snapshot)
            }
    }

    private func publishSurface() {
        ATHLTHSurfaceCoordinator.publishSnapshot(
            health: health,
            session: session,
            goals: goals,
            workout: workoutMirroring.snapshot
        )
    }
}
