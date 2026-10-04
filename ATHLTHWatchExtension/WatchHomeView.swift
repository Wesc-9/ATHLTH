import SwiftUI

struct WatchHomeView: View {
    @EnvironmentObject private var routeStore: WatchRouteStore
    @EnvironmentObject private var workoutManager: WatchWorkoutManager

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 9) {
                    header

                    if let today =
                            routeStore.todayWorkout {
                        todayWorkoutCard(today)
                    }

                    quickStartTiles

                    if let errorMessage =
                            workoutManager
                                .errorMessage {
                        HStack(
                            alignment: .top,
                            spacing: 7
                        ) {
                            Image(
                                systemName:
                                    "exclamationmark.triangle.fill"
                            )
                            .foregroundStyle(
                                WatchTheme.warning
                            )

                            Text(errorMessage)
                                .font(
                                    .system(
                                        size: 9,
                                        weight: .semibold
                                    )
                                )
                                .foregroundStyle(
                                    WatchTheme
                                        .textSecondary
                                )
                                .multilineTextAlignment(
                                    .leading
                                )

                            Spacer(
                                minLength: 0
                            )
                        }
                        .padding(9)
                        .watchSurface(
                            radius: 15
                        )
                    }

                    NavigationLink {
                        WatchWorkoutStartView(route: nil)
                    } label: {
                        menuCard(
                            title: "Other workouts",
                            subtitle:
                                Text(
                                    "Walk · Strength"
                                ),
                            icon: "figure.mixed.cardio",
                            accent: false
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        WatchRoutesListView()
                    } label: {
                        menuCard(
                            title: "Routes",
                            subtitle:
                                routeStore.routes.isEmpty
                                    ? Text(
                                        "Send a route from iPhone"
                                    )
                                    : Text(
                                        ATHLTHLocalization.format(
                                            "%d saved",
                                            routeStore
                                                .routes
                                                .count
                                        )
                                    ),
                            icon: "map.fill",
                            accent: false
                        )
                    }
                    .buttonStyle(.plain)

                    connectionRow
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
            .background(
                WatchTheme.canvas
                    .ignoresSafeArea()
            )
            .foregroundStyle(
                WatchTheme.textPrimary
            )
            .toolbar(
                .hidden,
                for: .navigationBar
            )
        }
        .onOpenURL { url in
            guard url.scheme ==
                    "athlth-watch"
            else {
                return
            }

            switch url.host {
            case "today":
                if let today =
                        routeStore
                            .todayWorkout {
                    startTodayWorkout(
                        today
                    )
                }

            case "quick-run":
                Task {
                    await workoutManager
                        .start(
                            kind:
                                .running
                        )
                }

            default:
                break
            }
        }
        .fullScreenCover(
            isPresented: Binding(
                get: {
                    workoutManager
                        .isWorkoutPresented
                },
                set: { presented in
                    if !presented,
                       workoutManager.state ==
                        .completed {
                        workoutManager.reset()
                    }
                }
            )
        ) {
            WatchActiveWorkoutView()
                .environmentObject(
                    workoutManager
                )
                .environmentObject(
                    routeStore
                )
        }
    }

    private var header: some View {
        HStack {
            VStack(
                alignment: .leading,
                spacing: 1
            ) {
                Text("ATHLTH")
                    .font(
                        .system(
                            size: 18,
                            weight: .black,
                            design: .rounded
                        )
                    )
                    .tracking(1.2)

                Text("READY TO MOVE")
                    .font(
                        .system(
                            size: 8,
                            weight: .bold
                        )
                    )
                    .tracking(1.1)
                    .foregroundStyle(
                        WatchTheme.muted
                    )
            }

            Spacer()

            Circle()
                .fill(
                    routeStore.companionLinked
                        ? WatchTheme.accent
                        : WatchTheme.muted
                )
                .frame(
                    width: 8,
                    height: 8
                )
        }
        .padding(.horizontal, 3)
        .padding(.top, 3)
        .padding(.bottom, 2)
    }

    private func todayWorkoutCard(
        _ workout:
            WatchTodayWorkoutTransfer
    ) -> some View {
        Button {
            startTodayWorkout(workout)
        } label: {
            VStack(
                alignment: .leading,
                spacing: 8
            ) {
                HStack {
                    Label(
                        "TODAY",
                        systemImage:
                            "calendar.badge.clock"
                    )
                    .font(
                        .system(
                            size: 8,
                            weight: .bold
                        )
                    )
                    .tracking(1)
                    .foregroundStyle(
                        WatchTheme.accent
                    )

                    Spacer()

                    if let start =
                            workout
                                .scheduledStart {
                        Text(
                            start.formatted(
                                date: .omitted,
                                time: .shortened
                            )
                        )
                        .font(
                            .system(
                                size: 9,
                                weight:
                                    .semibold
                            )
                        )
                        .foregroundStyle(
                            WatchTheme.muted
                        )
                    }
                }

                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(
                            cornerRadius: 13,
                            style: .continuous
                        )
                        .fill(
                            WatchTheme
                                .accent
                                .opacity(0.14)
                        )
                        .frame(
                            width: 42,
                            height: 42
                        )

                        Image(
                            systemName:
                                workout
                                    .kind
                                    .systemImage
                        )
                        .font(
                            .system(
                                size: 20,
                                weight: .bold
                            )
                        )
                        .foregroundStyle(
                            WatchTheme.accent
                        )
                    }

                    VStack(
                        alignment: .leading,
                        spacing: 2
                    ) {
                        Text(
                            workout.title
                        )
                        .font(
                            .system(
                                size: 15,
                                weight: .bold
                            )
                        )
                        .lineLimit(1)

                        Text(
                            workout.summary
                        )
                        .font(
                            .system(
                                size: 9
                            )
                        )
                        .foregroundStyle(
                            WatchTheme
                                .textSecondary
                        )
                        .lineLimit(2)
                    }

                    Spacer(
                        minLength: 2
                    )

                    Image(
                        systemName:
                            "play.fill"
                    )
                    .font(
                        .system(
                            size: 12,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(
                        WatchTheme.accent
                    )
                }
            }
            .padding(11)
            .frame(
                maxWidth: .infinity
            )
            .watchSurface(
                radius: 19
            )
        }
        .buttonStyle(.plain)
        .disabled(
            workoutManager.state ==
                .preparing
        )
        .opacity(
            workoutManager.state ==
                .preparing
                ? 0.55
                : 1
        )
    }

    private func startTodayWorkout(
        _ workout:
            WatchTodayWorkoutTransfer
    ) {
        let route =
            workout.routeID.flatMap {
                routeStore.route(
                    with: $0
                )
            }

        workoutManager
            .configurePlannedRoute(
                route
            )
        workoutManager
            .configureAudioCoach(
                workout.audioCoach ??
                    .disabled
            )

        if let running =
                workout.runningWorkout {
            workoutManager
                .configureRunningWorkout(
                    running
                )
        } else if workout.kind ==
                    .running ||
                    workout.kind ==
                    .walking {
            workoutManager
                .configureRunningWorkout(
                    WatchRunningWorkoutTransfer(
                        title:
                            workout.title,
                        steps: [],
                        routeAlerts:
                            .standard
                    )
                )
        }

        if workout.kind == .strength,
           let strength =
                workout.strengthWorkout {
            workoutManager
                .configureStrengthSession(
                    strength
                )
        }

        Task {
            await workoutManager
                .startPreparedWorkout(
                    kind:
                        workout.kind,
                    route: route
                )
        }
    }

    private var quickStartTiles: some View {
        HStack(spacing: 8) {
            quickStartTile(
                kind: .running,
                title: ATHLTHLocalization.choose(
                    english: "Run",
                    norwegian: "Løp"
                ),
                icon: "figure.run",
                tint: WatchTheme.accent,
                fill: WatchTheme.accentSoft
            )

            quickStartTile(
                kind: .strength,
                title: ATHLTHLocalization.choose(
                    english: "Strength",
                    norwegian: "Styrke"
                ),
                icon: "dumbbell.fill",
                tint: WatchTheme.slate,
                fill: WatchTheme.slateSoft
            )
        }
    }

    private func quickStartTile(
        kind: WatchWorkoutKind,
        title: String,
        icon: String,
        tint: Color,
        fill: Color
    ) -> some View {
        Button {
            Task {
                await workoutManager.start(
                    kind: kind
                )
            }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(
                        .system(
                            size: 22,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(tint)

                Text(title)
                    .font(
                        .system(
                            size: 13,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(
                        WatchTheme.textPrimary
                    )

                Text(
                    ATHLTHLocalization.choose(
                        english: "Start workout",
                        norwegian: "Start økt"
                    )
                )
                .font(.system(size: 8))
                .foregroundStyle(
                    WatchTheme.textSecondary
                )
            }
            .frame(
                maxWidth: .infinity,
                minHeight: 76
            )
            .background(
                fill,
                in: RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
                .stroke(
                    tint.opacity(0.16),
                    lineWidth: 0.75
                )
            }
        }
        .buttonStyle(.plain)
        .disabled(
            workoutManager.state ==
                .preparing
        )
        .opacity(
            workoutManager.state ==
                .preparing
                ? 0.55
                : 1
        )
    }

    private func menuCard(
        title: LocalizedStringKey,
        subtitle: Text,
        icon: String,
        accent: Bool
    ) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(
                    cornerRadius: 12,
                    style: .continuous
                )
                .fill(
                    WatchTheme
                        .cardRaised
                )
                .frame(
                    width: 38,
                    height: 38
                )

                Image(
                    systemName: icon
                )
                .font(
                    .system(
                        size: 16,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    accent
                        ? WatchTheme.accent
                        : WatchTheme
                            .textPrimary
                )
            }

            VStack(
                alignment: .leading,
                spacing: 2
            ) {
                Text(title)
                    .font(
                        .system(
                            size: 13,
                            weight: .semibold
                        )
                    )

                subtitle
                    .font(
                        .system(size: 9)
                    )
                    .foregroundStyle(
                        WatchTheme.muted
                    )
                    .lineLimit(1)
            }

            Spacer()

            Image(
                systemName:
                    "chevron.right"
            )
            .font(
                .system(
                    size: 9,
                    weight: .bold
                )
            )
            .foregroundStyle(
                WatchTheme.muted
            )
        }
        .padding(10)
        .watchSurface(
            radius: 17
        )
    }

    private var connectionRow: some View {
        HStack(spacing: 6) {
            Image(
                systemName:
                    routeStore
                        .companionLinked
                    ? "iphone.radiowaves.left.and.right"
                    : "iphone.slash"
            )
            .font(
                .system(size: 10)
            )

            Group {
                if routeStore
                    .companionLinked {
                    Text(
                        "iPhone connected"
                    )
                } else {
                    Text(
                        "Watch can record independently"
                    )
                }
            }
            .font(
                .system(
                    size: 9,
                    weight: .medium
                )
            )
            .lineLimit(1)
        }
        .foregroundStyle(
            WatchTheme.muted
        )
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }
}

private struct WatchRoutesListView: View {
    @EnvironmentObject private var routeStore: WatchRouteStore

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                if routeStore.routes.isEmpty {
                    VStack(spacing: 8) {
                        Image(
                            systemName: "map"
                        )
                        .font(.title2)
                        .foregroundStyle(
                            WatchTheme.accent
                        )

                        Text("No routes yet")
                            .font(.headline)

                        Text(
                            "Send a route from ATHLTH on iPhone."
                        )
                        .font(.caption2)
                        .foregroundStyle(
                            WatchTheme.muted
                        )
                        .multilineTextAlignment(
                            .center
                        )
                    }
                    .padding(14)
                    .watchSurface()
                } else {
                    ForEach(
                        routeStore.routes
                    ) { route in
                        NavigationLink {
                            WatchRouteDetailView(
                                route: route
                            )
                        } label: {
                            HStack(
                                spacing: 10
                            ) {
                                ZStack {
                                    Circle()
                                        .fill(
                                            WatchTheme
                                                .accent
                                                .opacity(
                                                    0.14
                                                )
                                        )
                                        .frame(
                                            width: 36,
                                            height: 36
                                        )

                                    Image(
                                        systemName:
                                            "map.fill"
                                    )
                                    .foregroundStyle(
                                        WatchTheme
                                            .accent
                                    )
                                }

                                VStack(
                                    alignment:
                                        .leading,
                                    spacing: 2
                                ) {
                                    Text(
                                        route.title
                                    )
                                    .font(
                                        .system(
                                            size: 13,
                                            weight:
                                                .semibold
                                        )
                                    )
                                    .lineLimit(1)

                                    Text(
                                        String(
                                            format:
                                                "%.1f km",
                                            route
                                                .distanceKilometers
                                        )
                                    )
                                    .font(
                                        .system(
                                            size: 10
                                        )
                                    )
                                    .foregroundStyle(
                                        WatchTheme
                                            .muted
                                    )
                                }

                                Spacer()

                                Image(
                                    systemName:
                                        "chevron.right"
                                )
                                .font(
                                    .system(
                                        size: 9,
                                        weight:
                                            .semibold
                                    )
                                )
                                .foregroundStyle(
                                    WatchTheme.muted
                                )
                            }
                            .padding(10)
                            .watchSurface()
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 10)
        }
        .background(
            WatchTheme.canvas
                .ignoresSafeArea()
        )
        .foregroundStyle(
            WatchTheme.textPrimary
        )
        .navigationTitle("Routes")
    }
}
