import SwiftUI

private enum WatchShortcutDestination: Hashable {
    case routes, ghostRace, favorites, favoriteWorkouts, favoriteRoutes, sent, planned, recommendation, menu, other
}

struct WatchHomeView: View {
    @EnvironmentObject private var routeStore: WatchRouteStore
    @EnvironmentObject private var workoutManager: WatchWorkoutManager
    @State private var shortcutPath: [WatchShortcutDestination] = []
    @State private var launchError: String?

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    private var dashboard: WatchHomeDashboardTransfer? {
        guard let value = routeStore.homeDashboard,
              value.ownerID == routeStore.companionAccountID else { return nil }
        return value
    }

    private var recommendation: WatchHomeDashboardTransfer? {
        guard let dashboard, dashboard.isCurrent(for: routeStore.companionAccountID) else { return nil }
        return dashboard
    }

    private var upcoming: [WatchTodayWorkoutTransfer] {
        let start = Calendar.current.startOfDay(for: Date())
        var seen = Set<UUID>()
        return routeStore.todayWorkouts.filter {
            ($0.scheduledStart ?? Date()) >= start &&
            routeStore.canLaunchTodayWorkout($0.workoutID) &&
            seen.insert($0.workoutID).inserted
        }.sorted { ($0.scheduledStart ?? start) < ($1.scheduledStart ?? start) }
    }

    private var sent: [WatchPreparedWorkoutTransfer] {
        WatchHomeSentQueue.visible(routeStore.sentWorkouts, owner: routeStore.companionAccountID)
            .filter { $0.plannedSessionID.map { routeStore.canLaunchTodayWorkout($0) } ?? true }
    }

    var body: some View {
        NavigationStack(path: $shortcutPath) {
            GeometryReader { proxy in
                let compact = proxy.size.width < 180
                let spacing: CGFloat = compact ? 4 : 5
                let headerHeight: CGFloat = 30
                let quickHeight: CGFloat = 52
                let cardHeight = max(0, proxy.size.height - headerHeight - quickHeight - spacing * 2 - 4)
                VStack(spacing: spacing) {
                    header.frame(height: headerHeight)
                    HStack(spacing: spacing) {
                        nextCard.frame(maxWidth: .infinity)
                        shortcuts.frame(width: max(70, (proxy.size.width - 14) * 0.45))
                    }.frame(height: cardHeight)
                    quickActions(height: quickHeight)
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(WatchTheme.planCanvas.ignoresSafeArea())
                .foregroundStyle(WatchTheme.planInk)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: WatchShortcutDestination.self) { target in
                switch target {
                case .routes: WatchRoutesListView()
                case .ghostRace: WatchGhostRaceShortcutView()
                case .other: WatchWorkoutStartView(route: nil, otherActivitiesOnly: true)
                case .favorites: favoritesPage
                case .favoriteWorkouts: favoriteWorkoutsPage
                case .favoriteRoutes: favoriteRoutesPage
                case .sent: sentPage
                case .planned: plannedPage
                case .recommendation: recommendationPage
                case .menu: menuPage
                }
            }
        }
        .onAppear { routeStore.requestTodayWorkoutSnapshot() }
        .onOpenURL { url in
            guard url.scheme == "athlth-watch" else { return }
            switch url.host {
            case "home": shortcutPath.removeAll(); routeStore.requestTodayWorkoutSnapshot()
            case "today": shortcutPath = [.planned]
            case "quick-run": quickStart(.running)
            case "quick-strength": quickStart(.strength)
            case "quick-walk": quickStart(.walking)
            case "routes": shortcutPath = [.routes]
            case "ghost-race": shortcutPath = [.ghostRace]
            default: break
            }
        }
        .alert(tr("Workout", "Trening"), isPresented: Binding(
            get: { launchError != nil },
            set: { if !$0 { launchError = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(launchError ?? "") }
        .fullScreenCover(isPresented: Binding(
            get: { workoutManager.isWorkoutPresented },
            set: { presented in
                if !presented, workoutManager.state == .completed { workoutManager.reset() }
            }
        )) {
            WatchActiveWorkoutView()
                .environmentObject(workoutManager)
                .environmentObject(routeStore)
        }
    }

    private var header: some View {
        HStack(spacing: 5) {
            Button { shortcutPath.append(.menu) } label: {
                Image(systemName: workoutManager.errorMessage == nil ? "line.3.horizontal" : "exclamationmark.circle")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 30, height: 30)
                    .background(.white, in: Circle())
            }.buttonStyle(.plain).accessibilityLabel(tr("Menu", "Meny"))
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                ATHLTHMarkShape(strokeScale: 0.72)
                    .fill(Color.black).frame(width: 26, height: 21)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("ATHLTH").font(.system(size: 11, weight: .medium)).tracking(2)
                    Text(tr("READY TO MOVE", "KLAR FOR ØKT"))
                        .font(.system(size: 6, weight: .medium)).tracking(0.7)
                        .foregroundStyle(WatchTheme.planSecondary)
                }.lineLimit(1).minimumScaleFactor(0.75)
            }.foregroundStyle(.black)
            Spacer(minLength: 0)
            Circle().fill(routeStore.companionLinked ? WatchTheme.planConnected : WatchTheme.planSecondary)
                .frame(width: 5, height: 5)
                .accessibilityLabel(routeStore.companionLinked ? tr("Connected", "Tilkoblet") : tr("Offline", "Frakoblet"))
        }
    }

    private var nextCard: some View {
        Button { shortcutPath.append(.planned) } label: {
            GeometryReader { proxy in
                let next = upcoming.first
                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: 14).fill(Color(red: 0.24, green: 0.19, blue: 0.15))
                    Image(next?.kind == .strength ? "WatchHomeStrength" : next?.kind == .walking ? "WatchHomeWalking" : "WatchHomeRunning")
                        .resizable().scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height).clipped()
                    LinearGradient(colors: [.black.opacity(0.03), .black.opacity(0.24), .black.opacity(0.88)], startPoint: .top, endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 3) {
                            Image(systemName: "calendar").font(.system(size: 8))
                            Text(tr("NEXT WORKOUT", "NESTE ØKT")).font(.system(size: 7, weight: .semibold)).tracking(0.5)
                        }.foregroundStyle(Color(red: 0.99, green: 0.88, blue: 0.68))
                        Text(next?.title ?? tr("No planned workout", "Ingen planlagt økt"))
                            .font(.system(size: 12, weight: .semibold)).lineLimit(2).minimumScaleFactor(0.8)
                        if let next {
                            if let date = next.scheduledStart {
                                Text(date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(size: 8)).lineLimit(1).minimumScaleFactor(0.75)
                            }
                            HStack(spacing: 3) {
                                Text(next.durationMinutes.map { "\($0) min" } ?? next.kind.title)
                                    .font(.system(size: 8)).lineLimit(1)
                                Spacer(minLength: 0)
                                Image(systemName: "play.circle.fill").font(.system(size: 19))
                            }
                        } else {
                            Text(tr("Open schedule", "Se kalender")).font(.system(size: 8))
                        }
                    }.padding(6).foregroundStyle(.white)
                }.clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }.buttonStyle(.plain).accessibilityLabel(tr("Next planned workout", "Neste planlagte økt"))
    }

    private var shortcuts: some View {
        GeometryReader { proxy in
            VStack(spacing: 1) {
                shortcut(.favoriteWorkouts, icon: "star", title: tr("Favorite workouts", "Favorittøkter"), detail: dashboard.map { String($0.favorites.count) })
                shortcut(.favoriteRoutes, icon: "map", title: tr("Favorite routes", "Favorittruter"), detail: dashboard.map { String($0.favoriteRouteIDs.count) })
                shortcut(.sent, icon: "applewatch.and.arrow.forward", title: tr("Sent to Watch", "Sendt til klokken"), detail: sent.isEmpty ? nil : String(sent.count))
                shortcut(.recommendation, icon: "bolt.fill", title: tr("Recommended", "Anbefalt økt"), detail: nil)
            }
            .frame(height: proxy.size.height)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 13))
            .overlay { RoundedRectangle(cornerRadius: 13).strokeBorder(WatchTheme.planBorder, lineWidth: 0.6) }
        }
    }

    private func shortcut(_ destination: WatchShortcutDestination, icon: String, title: String, detail: String?) -> some View {
        Button { shortcutPath.append(destination) } label: {
            HStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color(red: 0.52, green: 0.37, blue: 0.19))
                    .frame(width: 13)
                Text(title).font(.system(size: 9, weight: .semibold))
                    .lineLimit(2).minimumScaleFactor(0.75)
                Spacer(minLength: 0)
                if let detail { Text(detail).font(.system(size: 8, weight: .bold)).foregroundStyle(WatchTheme.planAccent) }
            }.padding(.horizontal, 4).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private func quickActions(height: CGFloat) -> some View {
        HStack(spacing: 4) {
            quickTile(tr("Walk", "Gå"), "figure.walk") { quickStart(.walking) }
            quickTile(tr("Run", "Løping"), "figure.run") { quickStart(.running) }
            quickTile(tr("Strength", "Styrke"), "dumbbell.fill") { quickStart(.strength) }
            quickTile(tr("Other", "Andre økter"), "square.grid.2x2") { shortcutPath.append(.other) }
        }.frame(height: height)
    }

    private func quickTile(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 18, weight: .semibold))
                Text(title).font(.system(size: 10, weight: .semibold)).lineLimit(2)
                    .minimumScaleFactor(0.78).multilineTextAlignment(.center)
            }.foregroundStyle(.black)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(WatchTheme.planBorder, lineWidth: 0.7) }
        }.buttonStyle(.plain)
    }

    private func quickStart(_ kind: WatchWorkoutKind) {
        Task { await workoutManager.start(kind: kind) }
    }

    private func launch(_ recipe: WatchPreparedWorkoutTransfer) {
        Task {
            if await routeStore.launchPreparedWorkout(recipe, manager: workoutManager) {
                shortcutPath.removeAll()
            } else {
                launchError = tr("The workout is not ready. Check the route and active workout.", "Økten er ikke klar. Kontroller ruten og eventuell aktiv økt.")
            }
        }
    }

    private func recipeRow(_ recipe: WatchPreparedWorkoutTransfer) -> some View {
        let ready = (recipe.routeID == nil || recipe.routeID.flatMap { routeStore.route(with: $0) } != nil)
            && routeStore.automaticStartCountdownSeconds == nil && workoutManager.canAcceptPreparedWorkout()
        return Button { launch(recipe) } label: {
            HStack(spacing: 8) {
                Image(systemName: recipe.kind.systemImage).foregroundStyle(WatchTheme.planAccent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(recipe.title).font(.headline).lineLimit(2)
                    Text(recipe.summary).font(.caption2).foregroundStyle(WatchTheme.planSecondary)
                }
                Spacer(minLength: 2)
                Image(systemName: ready ? "play.circle.fill" : "arrow.triangle.2.circlepath")
            }.padding(9).watchSurface(radius: 12)
        }.buttonStyle(.plain).disabled(!ready).opacity(ready ? 1 : 0.6)
    }

    private func page<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        ScrollView { VStack(spacing: 7) { content() }.padding(6) }
            .background(WatchTheme.planCanvas.ignoresSafeArea())
            .foregroundStyle(WatchTheme.planInk).navigationTitle(title)
    }

    private func empty(_ message: String) -> some View {
        Text(message).font(.caption).multilineTextAlignment(.center).padding(12)
            .frame(maxWidth: .infinity).watchSurface()
    }

    private var plannedPage: some View {
        page(tr("Upcoming", "Planlagte økter")) {
            if upcoming.isEmpty { empty(tr("No upcoming Watch-ready workouts.", "Ingen kommende økter klare for Watch.")) }
            ForEach(upcoming, id: \.workoutID) { workout in
                if let recipe = ATHLTHWatchTodayLaunchAdapter.prepared(from: workout) {
                    if let date = workout.scheduledStart {
                        Text(date.formatted(date: .abbreviated, time: .shortened)).font(.caption2)
                    }
                    recipeRow(recipe)
                }
            }
        }
    }

    private var sentPage: some View {
        page(tr("Sent to Watch", "Sendt til klokken")) {
            if !sent.isEmpty {
                ForEach(sent, id: \.id) { workout in recipeRow(workout) }
                if let countdown = routeStore.automaticStartCountdownSeconds { Text("\(countdown)s").font(.headline) }
            } else {
                empty(tr("Send a workout from ATHLTH on your iPhone.", "Send en treningsøkt fra ATHLTH på iPhone."))
            }
        }
    }

    private var favoritesPage: some View {
        page(tr("Favorites", "Favoritter")) {
            link(.favoriteWorkouts, tr("Favorite workouts", "Favorittøkter"), "star")
            link(.favoriteRoutes, tr("Favorite routes", "Favorittruter"), "map")
            link(.sent, tr("Sent to Watch", "Sendt til klokken"), "applewatch")
        }
    }

    private var favoriteWorkoutsPage: some View {
        page(tr("Favorite workouts", "Favorittøkter")) {
            let favorites = dashboard?.favorites ?? []
            if favorites.isEmpty { empty(tr("No favorite workouts synced.", "Ingen synkroniserte favorittøkter.")) }
            ForEach(favorites) { favorite in
                if let recipe = favorite.recipe { recipeRow(recipe) }
                else {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(favorite.title).font(.headline)
                        Text(tr("Open on iPhone", "Åpne på iPhone")).font(.caption2)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(9).watchSurface()
                }
            }
        }
    }

    private var favoriteRoutesPage: some View {
        page(tr("Favorite routes", "Favorittruter")) {
            let ids = Set(dashboard?.favoriteRouteIDs ?? [])
            let routes = routeStore.routes.filter { ids.contains($0.id) }
            if routes.isEmpty { empty(tr("No favorite routes synced.", "Ingen synkroniserte favorittruter.")) }
            ForEach(routes) { route in
                NavigationLink { WatchRouteDetailView(route: route) } label: {
                    Label(route.title, systemImage: "map").font(.subheadline).padding(8).watchSurface()
                }.buttonStyle(.plain)
            }
        }
    }

    private var recommendationPage: some View {
        page(tr("Recommended", "Anbefalt økt")) {
            if let recipe = recommendation?.recommendation { recipeRow(recipe) }
            else if let title = recommendation?.recommendationTitle {
                empty(title + "\n" + (recommendation?.recommendationDetail ?? ""))
            } else { empty(tr("No current recommendation.", "Ingen aktuell anbefaling.")) }
        }
    }

    private func link(_ destination: WatchShortcutDestination, _ title: String, _ icon: String) -> some View {
        Button { shortcutPath.append(destination) } label: {
            HStack { Label(title, systemImage: icon); Spacer(); Image(systemName: "chevron.right").font(.caption2) }
                .font(.caption.weight(.semibold)).padding(9).watchSurface()
        }.buttonStyle(.plain)
    }

    private var menuPage: some View {
        page(tr("Menu", "Meny")) {
            link(.favorites, tr("Favorites", "Favoritter"), "star")
            link(.planned, tr("Planned workouts", "Planlagte økter"), "calendar")
            link(.routes, tr("All routes", "Alle ruter"), "map")
            link(.ghostRace, "Ghost Race", "figure.run")
            WatchPetSelectionButton()
            if let message = workoutManager.errorMessage { empty(message) }
            Text(routeStore.connectionText).font(.caption2)
        }
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
