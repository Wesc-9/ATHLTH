import SwiftUI

/// Destination for the Ghost Race Watch-face complication.
///
/// A Ghost race cannot safely be created from a plain .running workout.
/// The iPhone must first transfer a Ghost configuration, opponent timing
/// and any required route to the Watch. Without that configuration we show
/// setup instructions rather than silently starting an ordinary run.
struct WatchGhostRaceShortcutView: View {
    @EnvironmentObject private var routeStore: WatchRouteStore
    @EnvironmentObject private var workoutManager: WatchWorkoutManager

    private var preparedGhost: WatchPreparedWorkoutTransfer? {
        guard let workout = routeStore.preparedWorkout,
              workout.kind == .running,
              workout.ghostRace != nil else { return nil }
        return workout
    }

    private var routeAvailable: Bool {
        guard let ghost = preparedGhost else { return false }
        return ghost.routeID == nil || ghost.routeID.flatMap {
            routeStore.route(with: $0)
        } != nil
    }

    private var startControlledOnWatch: Bool {
        guard let mode = preparedGhost?.startMode else { return true }
        return mode == .onWatch
    }

    private var canStart: Bool {
        preparedGhost != nil &&
        routeAvailable &&
        startControlledOnWatch &&
        !workoutManager.isActive &&
        workoutManager.state != .preparing &&
        workoutManager.state != .ending
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 10) {
                    Image(systemName: "scope")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(WatchTheme.accent)
                        .frame(width: 40, height: 40)
                        .background(WatchTheme.accentSoft, in: Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ghost Race")
                            .font(.system(size: 17, weight: .bold))
                        Text(ATHLTHLocalization.choose(
                            english: "Race your ghost",
                            norwegian: "Løp mot Ghosten"
                        ))
                        .font(.system(size: 10))
                        .foregroundStyle(WatchTheme.textSecondary)
                    }
                }

                if let preparedGhost {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(preparedGhost.title)
                            .font(.system(size: 14, weight: .bold))
                        Text(preparedGhost.summary)
                            .font(.system(size: 11))
                            .foregroundStyle(WatchTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if !routeAvailable {
                            Label(
                                ATHLTHLocalization.choose(
                                    english: "Waiting for route from iPhone",
                                    norwegian: "Venter på rute fra iPhone"
                                ),
                                systemImage: "arrow.triangle.2.circlepath"
                            )
                            .font(.system(size: 10))
                            .foregroundStyle(WatchTheme.warning)
                        } else if !startControlledOnWatch {
                            Text(ATHLTHLocalization.choose(
                                english: "Start is controlled by iPhone. Wait for the transfer or select start on Watch on your phone.",
                                norwegian: "Start styres fra iPhone. Vent på overføringen, eller velg start på klokken på telefonen."
                            ))
                            .font(.system(size: 10))
                            .foregroundStyle(WatchTheme.textSecondary)
                        }

                        Button {
                            guard let candidate = self.preparedGhost,
                                  canStart else { return }
                            Task {
                                await routeStore.launchPreparedWorkout(
                                    candidate,
                                    manager: workoutManager
                                )
                            }
                        } label: {
                            Label(
                                ATHLTHLocalization.choose(
                                    english: "Start Ghost Race",
                                    norwegian: "Start Ghost Race"
                                ),
                                systemImage: "play.fill"
                            )
                            .font(.system(size: 13, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(WatchTheme.accent)
                        .disabled(!canStart)
                    }
                    .padding(11)
                    .watchSurface(radius: 17)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(ATHLTHLocalization.choose(
                            english: "Prepare a Ghost Race on iPhone",
                            norwegian: "Klargjør Ghost Race på iPhone"
                        ))
                        .font(.system(size: 13, weight: .semibold))

                        Text(ATHLTHLocalization.choose(
                            english: "Choose Live, Replay or Target in ATHLTH on your phone, then select Apple Watch as the workout device.",
                            norwegian: "Velg Live, Replay eller Mål i ATHLTH på telefonen, og velg deretter Apple Watch som treningsenhet."
                        ))
                        .font(.system(size: 11))
                        .foregroundStyle(WatchTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                        Label(
                            ATHLTHLocalization.choose(
                                english: "No race has been prepared",
                                norwegian: "Ingen Ghost-økt er klargjort"
                            ),
                            systemImage: "info.circle"
                        )
                        .font(.system(size: 10))
                        .foregroundStyle(WatchTheme.accent)
                    }
                    .padding(12)
                    .watchSurface(radius: 17)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(WatchTheme.canvas.ignoresSafeArea())
        .navigationTitle("Ghost Race")
        .navigationBarTitleDisplayMode(.inline)
    }
}
