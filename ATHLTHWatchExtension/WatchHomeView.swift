import SwiftUI

struct WatchHomeView: View {
    @EnvironmentObject private var routeStore: WatchRouteStore
    @EnvironmentObject private var workoutManager: WatchWorkoutManager

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    header

                    HStack(spacing: 8) {
                        NavigationLink {
                            WatchRoutesListView()
                        } label: {
                            actionCard(
                                title: "Routes",
                                subtitle: routeStore.routes.isEmpty
                                    ? "Explore"
                                    : "\(routeStore.routes.count) saved",
                                icon: "point.topleft.down.to.point.bottomright.curvepath"
                            )
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            WatchWorkoutStartView(route: nil)
                        } label: {
                            actionCard(
                                title: "Start Workout",
                                subtitle: workoutManager.isActive
                                    ? "Workout active"
                                    : "Run · Walk · Strength",
                                icon: "figure.run"
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Text("Today")
                                .font(.system(size: 14, weight: .bold))

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(WatchTheme.muted)
                        }

                        HStack(spacing: 0) {
                            todayMetric(
                                icon: "iphone",
                                value: routeStore.companionLinked
                                    ? "Ready"
                                    : "Waiting",
                                label: "iPhone"
                            )

                            Divider()

                            todayMetric(
                                icon: "map",
                                value: "\(routeStore.routes.count)",
                                label: "Routes"
                            )

                            Divider()

                            todayMetric(
                                icon: "applewatch",
                                value: "ATHLTH",
                                label: "Watch"
                            )
                        }
                    }
                    .padding(12)
                    .watchSurface()
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 10)
            }
            .background(WatchTheme.canvas.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(
            isPresented: Binding(
                get: { workoutManager.isWorkoutPresented },
                set: { presented in
                    if !presented, workoutManager.state == .completed {
                        workoutManager.reset()
                    }
                }
            )
        ) {
            WatchActiveWorkoutView()
                .environmentObject(workoutManager)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            ATHLTHBrandMark(size: .watch)

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(
                            routeStore.companionLinked
                                ? WatchTheme.green
                                : Color.secondary
                        )
                        .frame(width: 6, height: 6)

                    Text(
                        routeStore.companionLinked
                            ? "Connected"
                            : "Ready"
                    )
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(WatchTheme.muted)
                }

                Text("to iPhone")
                    .font(.system(size: 9))
                    .foregroundStyle(WatchTheme.muted)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }

    @ViewBuilder
    private func actionCard(
        title: String,
        subtitle: String,
        icon: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.035))
                    .frame(width: 34, height: 34)

                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(WatchTheme.green)
            }

            HStack(spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer(minLength: 2)

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(WatchTheme.muted)
            }

            Text(subtitle)
                .font(.system(size: 10))
                .foregroundStyle(WatchTheme.muted)
        }
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        .padding(11)
        .watchSurface()
    }

    @ViewBuilder
    private func todayMetric(
        icon: String,
        value: String,
        label: String
    ) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(WatchTheme.green)

            Text(value)
                .font(.system(size: 12, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(label)
                .font(.system(size: 8))
                .foregroundStyle(WatchTheme.muted)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct WatchRoutesListView: View {
    @EnvironmentObject private var routeStore: WatchRouteStore

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                if routeStore.routes.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "map")
                            .font(.title2)
                            .foregroundStyle(WatchTheme.green)

                        Text("No routes yet")
                            .font(.headline)

                        Text("Send a route from ATHLTH on iPhone.")
                            .font(.caption2)
                            .foregroundStyle(WatchTheme.muted)
                            .multilineTextAlignment(.center)
                    }
                    .padding(14)
                    .watchSurface()
                } else {
                    ForEach(routeStore.routes) { route in
                        NavigationLink {
                            WatchRouteDetailView(route: route)
                        } label: {
                            HStack(spacing: 10) {
                                ZStack {
                                    Circle()
                                        .fill(WatchTheme.green.opacity(0.10))
                                        .frame(width: 34, height: 34)

                                    Image(systemName: "map")
                                        .foregroundStyle(WatchTheme.green)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(route.title)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)

                                    Text(String(format: "%.1f km", route.distanceKilometers))
                                        .font(.system(size: 10))
                                        .foregroundStyle(WatchTheme.muted)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(WatchTheme.muted)
                            }
                            .padding(11)
                            .watchSurface()
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 10)
        }
        .background(WatchTheme.canvas.ignoresSafeArea())
        .navigationTitle("Routes")
    }
}
