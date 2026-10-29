import SwiftUI

private enum WatchShortcutDestination: Hashable {
    case routes
    case ghostRace
}

struct WatchHomeView: View {
    @EnvironmentObject private var routeStore: WatchRouteStore
    @EnvironmentObject private var workoutManager: WatchWorkoutManager
    @State private var shortcutPath: [WatchShortcutDestination] = []

    var body: some View {
        NavigationStack(path: $shortcutPath) {
            GeometryReader { geometry in
                let compact = geometry.size.height < 205
                let hasAdditionalContent =
                    routeStore.preparedWorkout != nil ||
                    !routeStore.todayWorkouts.isEmpty ||
                    workoutManager.errorMessage != nil

                Group {
                    if hasAdditionalContent {
                        // Keep important transferred workouts and errors
                        // available; only this expanded state may scroll.
                        ScrollView {
                            VStack(spacing: 7) {
                                header
                                if let prepared = routeStore.preparedWorkout {
                                    preparedWorkoutCard(prepared)
                                }
                                ForEach(routeStore.todayWorkouts, id: \.workoutID) { today in
                                    todayWorkoutCard(today)
                                }
                                quickStartTiles(compact: compact)
                                otherWorkoutsCard
                                if let message = workoutManager.errorMessage {
                                    Label(
                                        message,
                                        systemImage: "exclamationmark.triangle.fill"
                                    )
                                    .font(.caption2)
                                    .foregroundStyle(WatchTheme.warning)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(9)
                                    .watchSurface(radius: 13)
                                }
                            }
                            .padding(.horizontal, 7)
                            .padding(.bottom, 6)
                        }
                    } else {
                        // Default state fits on a single Watch screen,
                        // including the smallest supported displays.
                        VStack(spacing: compact ? 5 : 8) {
                            header
                            Spacer(minLength: 0)
                            quickStartTiles(compact: compact)
                            otherWorkoutsCard
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, compact ? 2 : 5)
                    }
                }
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .top
                )
                .background(WatchTheme.planCanvas.ignoresSafeArea())
                .foregroundStyle(WatchTheme.planInk)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: WatchShortcutDestination.self) { target in
                switch target {
                case .routes:
                    WatchRoutesListView()
                case .ghostRace:
                    WatchGhostRaceShortcutView()
                }
            }
        }
        .onAppear {
            // Ask iPhone for the latest planned session when the Watch opens.
            // The cached snapshot remains available without a connection.
            routeStore.requestTodayWorkoutSnapshot()
        }
        .onOpenURL { url in
            guard url.scheme ==
                    "athlth-watch"
            else {
                return
            }

            switch url.host {
            case "home":
                // A Watch-face tap opens the first ATHLTH screen. Never
                // auto-start a workout or discard an active recording.
                shortcutPath.removeAll()
                routeStore.requestTodayWorkoutSnapshot()

            case "today":
                if let today = routeStore.todayWorkouts.first {
                    startTodayWorkout(today)
                }

            case "quick-run":
                Task { await workoutManager.start(kind: .running) }

            case "quick-strength":
                Task { await workoutManager.start(kind: .strength) }

            case "quick-walk":
                Task { await workoutManager.start(kind: .walking) }

            case "routes":
                shortcutPath = [.routes]

            case "ghost-race":
                // A plain run is not a Ghost Race. Navigate to the prepared
                // Ghost state rather than starting an unconfigured session.
                shortcutPath = [.ghostRace]

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
        HStack(spacing: 7) {
            ATHLTHWatchLogomark()
                .frame(width: 29, height: 29)

            VStack(alignment: .leading, spacing: 1) {
                Text("ATHLTH")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .tracking(1.1)
                    .foregroundStyle(WatchTheme.planInk)
                    .minimumScaleFactor(0.8)

                Text(ATHLTHLocalization.choose(
                    english: "READY TO MOVE",
                    norwegian: "KLAR FOR ØKT"
                ))
                .font(.system(size: 8, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(WatchTheme.planSecondary)
            }

            Spacer(minLength: 2)

            NavigationLink {
                WatchRoutesListView()
            } label: {
                Image(systemName: "map")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(WatchTheme.planInk)
                    .frame(width: 31, height: 31)
                    .background(.white, in: Circle())
                    .overlay {
                        Circle().strokeBorder(
                            WatchTheme.planBorder, lineWidth: 0.6
                        )
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(ATHLTHLocalization.choose(
                english: "Routes", norwegian: "Ruter"
            ))

            Circle()
                .fill(
                    routeStore.companionLinked
                        ? WatchTheme.planConnected
                        : WatchTheme.planSecondary
                )
                .frame(width: 7, height: 7)
                .accessibilityLabel(
                    routeStore.companionLinked
                        ? ATHLTHLocalization.choose(
                            english: "iPhone connected",
                            norwegian: "iPhone tilkoblet"
                        )
                        : ATHLTHLocalization.choose(
                            english: "Watch can record independently",
                            norwegian: "Klokken kan registrere økter alene"
                        )
                )
        }
        .padding(.horizontal, 1)
        .frame(height: 36)
    }

    private var otherWorkoutsCard: some View {
        NavigationLink {
            WatchWorkoutStartView(route: nil)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "figure.mixed.cardio")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(WatchTheme.planAccent)
                    .frame(width: 34, height: 34)
                    .background(
                        WatchTheme.planSelected,
                        in: RoundedRectangle(cornerRadius: 11)
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(ATHLTHLocalization.choose(
                        english: "Other workouts",
                        norwegian: "Andre økter"
                    ))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WatchTheme.planInk)
                    Text(ATHLTHLocalization.choose(
                        english: "Walk and more",
                        norwegian: "Gåtur og mer"
                    ))
                    .font(.system(size: 10))
                    .foregroundStyle(WatchTheme.planSecondary)
                }
                Spacer(minLength: 2)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(WatchTheme.planSecondary)
            }
            .padding(.horizontal, 9)
            .frame(height: 51)
            .background(.white, in: RoundedRectangle(cornerRadius: 15))
            .overlay {
                RoundedRectangle(cornerRadius: 15)
                    .strokeBorder(WatchTheme.planBorder, lineWidth: 0.75)
            }
        }
        .buttonStyle(.plain)
    }

    private func preparedWorkoutCard(
        _ workout:
            WatchPreparedWorkoutTransfer
    ) -> some View {
        let routeReady =
            workout.routeID == nil ||
            workout.routeID.flatMap {
                routeStore.route(with: $0)
            } != nil
        let canStart =
            routeReady &&
            routeStore.automaticStartCountdownSeconds == nil &&
            workoutManager.state !=
                .preparing

        return Button {
            startPreparedWorkout(workout)
        } label: {
            VStack(
                alignment: .leading,
                spacing: 8
            ) {
                HStack {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "READY",
                            norwegian: "KLAR"
                        ),
                        systemImage:
                            "applewatch"
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

                    Text(
                        routeStore.automaticStartCountdownSeconds.map {
                            "\($0)s"
                        } ??
                        (routeReady
                            ? "START"
                            : ATHLTHLocalization.choose(
                                english: "SYNCING",
                                norwegian: "SYNKER"
                            ))
                    )
                    .font(
                        .system(
                            size: 8,
                            weight: .black
                        )
                    )
                    .tracking(0.8)
                    .foregroundStyle(
                        routeReady
                            ? WatchTheme.accent
                            : WatchTheme.muted
                    )
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
                                .opacity(0.16)
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
                        Text(workout.title)
                            .font(
                                .system(
                                    size: 15,
                                    weight: .bold
                                )
                            )
                            .lineLimit(1)

                        Text(
                            routeReady
                                ? workout.summary
                                : ATHLTHLocalization.choose(
                                    english:
                                        "Receiving route from iPhone…",
                                    norwegian:
                                        "Mottar rute fra iPhone…"
                                )
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
                            routeReady
                                ? "play.circle.fill"
                                : "arrow.triangle.2.circlepath"
                    )
                    .font(
                        .system(
                            size: 17,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(
                        routeReady
                            ? WatchTheme.accent
                            : WatchTheme.muted
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
        .disabled(!canStart)
        .opacity(
            canStart
                ? 1
                : 0.62
        )
    }

    private func startPreparedWorkout(
        _ workout: WatchPreparedWorkoutTransfer
    ) {
        Task {
            await routeStore.launchPreparedWorkout(
                workout,
                manager: workoutManager
            )
        }
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
                        workout.scheduledStart.map {
                            Calendar.current.isDateInToday($0)
                        } ?? true
                        ? ATHLTHLocalization.choose(
                            english: "TODAY", norwegian: "I DAG")
                        : ATHLTHLocalization.choose(
                            english: "UPCOMING", norwegian: "KOMMENDE"),
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
                                date: Calendar.current.isDateInToday(start)
                                    ? .omitted : .abbreviated,
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
            workoutManager.isActive ||
            workoutManager.state == .preparing ||
            workoutManager.state == .ending
        )
        .opacity(
            workoutManager.isActive ||
            workoutManager.state == .preparing ||
            workoutManager.state == .ending
                ? 0.55
                : 1
        )
    }

    private func startTodayWorkout(
        _ workout:
            WatchTodayWorkoutTransfer
    ) {
        guard !workoutManager.isActive,
              workoutManager.state != .preparing,
              workoutManager.state != .ending else { return }
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

    private func quickStartTiles(compact: Bool) -> some View {
        HStack(spacing: 7) {
            quickStartTile(
                kind: .running,
                title: ATHLTHLocalization.choose(
                    english: "Run", norwegian: "Løp"
                ),
                icon: "figure.run",
                tint: WatchTheme.planAccent,
                fill: .white,
                compact: compact
            )
            quickStartTile(
                kind: .strength,
                title: ATHLTHLocalization.choose(
                    english: "Strength", norwegian: "Styrke"
                ),
                icon: "dumbbell.fill",
                tint: WatchTheme.planInk,
                fill: WatchTheme.planSelected,
                compact: compact
            )
        }
    }

    private func quickStartTile(
        kind: WatchWorkoutKind,
        title: String,
        icon: String,
        tint: Color,
        fill: Color,
        compact: Bool
    ) -> some View {
        Button {
            Task { await workoutManager.start(kind: kind) }
        } label: {
            VStack(spacing: compact ? 2 : 4) {
                Image(systemName: icon)
                    .font(.system(
                        size: compact ? 18 : 21,
                        weight: .semibold
                    ))
                    .foregroundStyle(tint)

                Text(title)
                    .font(.system(
                        size: compact ? 12 : 13,
                        weight: .bold
                    ))
                    .foregroundStyle(WatchTheme.planInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(ATHLTHLocalization.choose(
                    english: "Start workout", norwegian: "Start økt"
                ))
                .font(.system(size: 8))
                .foregroundStyle(WatchTheme.planSecondary)
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: compact ? 69 : 77)
            .background(
                fill,
                in: RoundedRectangle(cornerRadius: 17)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 17)
                    .strokeBorder(
                        WatchTheme.planBorder, lineWidth: 0.8
                    )
            }
        }
        .buttonStyle(.plain)
        .disabled(workoutManager.state == .preparing)
        .opacity(workoutManager.state == .preparing ? 0.55 : 1)
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

/// Reuses ATHLTH's actual vector logo from Shared/ATHLTHBrandMark.swift.
/// No watch-only brand redesign and no extra image decode/memory cost.
private struct ATHLTHWatchLogomark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(WatchTheme.planSelected)
            ATHLTHMarkShape()
                .fill(WatchTheme.planAccent)
                .frame(width: 24, height: 20)
        }
        .accessibilityHidden(true)
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
