import SwiftUI

private enum WatchShortcutDestination: Hashable {
    case routes, ghostRace, favoriteWorkouts, favoriteRoutes, sent, planned, recommendation, dailyForm, connection, walking, running, other
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

    private var dailyForm: WatchDailyFormTransfer? {
        guard let form = dashboard?.dailyForm, form.isCurrent() else { return nil }
        return form
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
                case .favoriteWorkouts: favoriteWorkoutsPage
                case .favoriteRoutes: favoriteRoutesPage
                case .sent: sentPage
                case .planned: plannedPage
                case .recommendation: recommendationPage
                case .dailyForm: dailyFormPage
                case .connection: connectionPage
                case .walking: activityPage(.walking)
                case .running: activityPage(.running)
                }
            }
        }
        .onAppear { routeStore.requestTodayWorkoutSnapshot() }
        .onOpenURL { url in
            guard url.scheme == "athlth-watch" else { return }
            switch url.host {
            case "home": shortcutPath.removeAll(); routeStore.requestTodayWorkoutSnapshot()
            case "today": shortcutPath = [.planned]
            case "daily-form": shortcutPath = [.dailyForm]; routeStore.requestTodayWorkoutSnapshot()
            case "sent": shortcutPath = [.sent]
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
        .onChange(of: workoutManager.state) { _, state in
            if state == .completed || state == .idle { shortcutPath.removeAll() }
        }
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
            Button { shortcutPath.append(.dailyForm) } label: {
                ZStack {
                    Circle().fill(WatchTheme.planSelected)
                    Circle().strokeBorder(WatchTheme.planBorder, lineWidth: 2)
                    if let score = dailyForm?.validScore {
                        Circle().trim(from: 0, to: CGFloat(score) / 100)
                            .stroke(formTint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .rotationEffect(.degrees(-90)).padding(1)
                    }
                    Text(dailyForm?.validScore.map(String.init) ?? "–")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(formTint)
                        .monospacedDigit()
                }.frame(width: 30, height: 30)
            }.buttonStyle(.plain)
            .accessibilityLabel(tr("Daily form", "Dagens form"))
            .accessibilityValue(dailyForm?.validScore.map { String($0) + " / 100" } ?? tr("Unavailable", "Ikke tilgjengelig"))
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
            Button { shortcutPath.append(.connection) } label: {
                Group {
                    if workoutManager.errorMessage != nil {
                        Image(systemName: "exclamationmark.circle").font(.system(size: 12))
                            .foregroundStyle(WatchTheme.warning)
                    } else {
                        Circle().fill(routeStore.companionLinked ? WatchTheme.planConnected : WatchTheme.planSecondary)
                            .frame(width: 6, height: 6)
                    }
                }.frame(width: 26, height: 30).contentShape(Rectangle())
            }.buttonStyle(.plain)
            .accessibilityLabel(tr("Connection and status", "Tilkobling og status"))
            .accessibilityValue(routeStore.companionLinked ? tr("Connected", "Tilkoblet") : tr("Offline", "Frakoblet"))
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
            quickTile(tr("Walk", "Gå"), "figure.walk") { shortcutPath.append(.walking) }
            quickTile(tr("Run", "Løping"), "figure.run") { shortcutPath.append(.running) }
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
            link(.routes, tr("All routes", "Alle ruter"), "map")
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

    private var formTint: Color {
        switch dailyForm?.state {
        case "recover": return WatchTheme.danger
        case "takeItEasy": return WatchTheme.warning
        default: return Color(red: 0.52, green: 0.37, blue: 0.19)
        }
    }

    private func formStateTitle(_ state: String) -> String {
        switch state {
        case "ready": return tr("Ready", "God form")
        case "balanced": return tr("Balanced", "Balansert")
        case "takeItEasy": return tr("Take it easier", "Ta det roligere")
        case "recover": return tr("Prioritize recovery", "Prioriter restitusjon")
        default: return tr("Building baseline", "Bygger grunnlag")
        }
    }

    private func formMetric(_ title: String, _ value: String, _ icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(WatchTheme.planAccent).frame(width: 18)
            Text(title).font(.caption)
            Spacer(minLength: 2)
            Text(value).font(.caption.weight(.semibold)).monospacedDigit()
        }.padding(8).watchSurface(radius: 11)
    }

    private func formNumber(_ value: Double?, suffix: String) -> String {
        guard let value, value.isFinite, value > 0, value < Double(Int.max) else { return "–" }
        return "\(Int(value.rounded())) \(suffix)"
    }

    private func sleepText(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds > 0, seconds < 48 * 3600 else { return "–" }
        let minutes = Int(seconds / 60)
        return "\(minutes / 60)t \(minutes % 60)m"
    }

    private var dailyFormPage: some View {
        page(tr("Daily form", "Dagens form")) {
            if let form = dailyForm {
                VStack(spacing: 5) {
                    ZStack {
                        Circle().stroke(WatchTheme.planBorder, lineWidth: 5)
                        if let score = form.validScore {
                            Circle().trim(from: 0, to: CGFloat(score) / 100)
                                .stroke(formTint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                        }
                        VStack(spacing: 0) {
                            Text(form.validScore.map(String.init) ?? "–")
                                .font(.system(size: 32, weight: .semibold, design: .rounded))
                            Text("/100").font(.caption2).foregroundStyle(WatchTheme.planSecondary)
                        }
                    }.frame(width: 74, height: 74)
                    Text(formStateTitle(form.state)).font(.headline).multilineTextAlignment(.center)
                    if let advice = form.advice { Text(advice).font(.caption2).multilineTextAlignment(.center) }
                }.frame(maxWidth: .infinity).padding(10).watchSurface(radius: 15)
                formMetric(tr("Recovery", "Restitusjon"), form.measuredScore.map { "\($0)/100" } ?? "–", "heart.fill")
                formMetric(tr("Sleep", "Søvn"), sleepText(form.sleepSeconds), "moon.zzz.fill")
                formMetric("HRV", formNumber(form.hrvMilliseconds, suffix: "ms"), "waveform.path.ecg")
                formMetric(tr("Resting HR", "Hvilepuls"), formNumber(form.restingHeartRate, suffix: "bpm"), "heart")
                formMetric(tr("Training load", "Belastning"), form.trainingLoadRatio.flatMap { $0.isFinite && $0 > 0 ? String(format: "%.2f×", $0) : nil } ?? "–", "chart.bar.fill")
                if form.validScore == nil {
                    empty(tr("Not enough current data for a score.", "Ikke nok aktuelle data til en score."))
                }
                if let explanation = form.explanation { empty(explanation) }
                Text(tr("Updated", "Oppdatert") + " " + form.updatedAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption2).foregroundStyle(WatchTheme.planSecondary)
            } else {
                empty(tr("Today's form is not available yet. Open ATHLTH on iPhone to sync.", "Dagens form er ikke tilgjengelig ennå. Åpne ATHLTH på iPhone for å synkronisere."))
            }
            Button { routeStore.requestTodayWorkoutSnapshot() } label: {
                Label(tr("Refresh", "Oppdater"), systemImage: "arrow.clockwise")
            }.font(.caption)
        }
    }

    private func activityPage(_ kind: WatchWorkoutKind) -> some View {
        page(kind == .walking ? tr("Walk", "Gå") : tr("Run", "Løping")) {
            Button { quickStart(kind) } label: {
                Label(tr("Start workout", "Start økt"), systemImage: "play.fill")
                    .font(.headline).frame(maxWidth: .infinity).padding(10)
                    .background(WatchTheme.planSelected, in: RoundedRectangle(cornerRadius: 13))
            }.buttonStyle(.plain)
            WatchPetSelectionButton()
            link(.favoriteRoutes, tr("Favorite routes", "Favorittruter"), "star")
            link(.routes, tr("All routes", "Alle ruter"), "map")
            if kind == .running { link(.ghostRace, "Ghost Race", "figure.run") }
            if let message = workoutManager.errorMessage { empty(message) }
        }
    }

    private var connectionPage: some View {
        page(tr("Connection", "Tilkobling")) {
            empty(routeStore.companionLinked ? tr("iPhone connected", "iPhone tilkoblet") : tr("Watch ready for standalone workouts", "Klokken kan registrere økter alene"))
            if let message = workoutManager.errorMessage { empty(message) }
            Button { routeStore.requestTodayWorkoutSnapshot() } label: {
                Label(tr("Sync with iPhone", "Synkroniser med iPhone"), systemImage: "arrow.clockwise")
            }.font(.caption)
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
