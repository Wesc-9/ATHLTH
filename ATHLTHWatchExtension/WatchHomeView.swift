import SwiftUI

struct WatchHomeView: View {
    @EnvironmentObject private var routeStore: WatchRouteStore
    @EnvironmentObject private var workoutManager: WatchWorkoutManager

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    header

                    NavigationLink {
                        WatchWorkoutStartView(route: nil)
                    } label: {
                        primaryCard(
                            title: "Start Workout",
                            subtitle: "Run · Walk · Strength",
                            icon: "play.fill"
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        WatchRoutesListView()
                    } label: {
                        compactCard(
                            title: "Routes",
                            subtitle:
                                routeStore.routes.isEmpty
                                    ? "No saved routes"
                                    : "\(routeStore.routes.count) saved",
                            icon: "point.topleft.down.to.point.bottomright.curvepath",
                            showsChevron: true
                        )
                    }
                    .buttonStyle(.plain)

                    compactCard(
                        title: "iPhone",
                        subtitle: connectionSubtitle,
                        icon:
                            routeStore.companionLinked
                                ? "iphone.radiowaves.left.and.right"
                                : "iphone.slash",
                        showsChevron: false
                    )
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
                    if !presented,
                       workoutManager.state == .completed {
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
        VStack(spacing: 5) {
            ATHLTHBrandMark(size: .watch)

            HStack(spacing: 5) {
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
                        : "Watch ready"
                )
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(WatchTheme.muted)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
        .padding(.bottom, 2)
    }

    private var connectionSubtitle: String {
        if routeStore.companionLinked {
            return "Connected to ATHLTH on iPhone"
        }

        return routeStore.connectionText
    }

    private func primaryCard(
        title: String,
        subtitle: String,
        icon: String
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(
                    cornerRadius: 14,
                    style: .continuous
                )
                .fill(WatchTheme.green.opacity(0.12))
                .frame(width: 46, height: 46)

                Image(systemName: icon)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(WatchTheme.green)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(WatchTheme.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(WatchTheme.muted)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 72)
        .watchSurface(radius: 18)
    }

    private func compactCard(
        title: String,
        subtitle: String,
        icon: String,
        showsChevron: Bool
    ) -> some View {
        HStack(spacing: 11) {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.035))
                    .frame(width: 38, height: 38)

                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(
                        title == "iPhone" &&
                        !routeStore.companionLinked
                            ? WatchTheme.muted
                            : WatchTheme.green
                    )
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.system(size: 9))
                    .foregroundStyle(WatchTheme.muted)
                    .lineLimit(2)
            }

            Spacer(minLength: 4)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(WatchTheme.muted)
            } else {
                Circle()
                    .fill(
                        routeStore.companionLinked
                            ? WatchTheme.green
                            : Color.secondary
                    )
                    .frame(width: 7, height: 7)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, minHeight: 60)
        .watchSurface(radius: 17)
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
