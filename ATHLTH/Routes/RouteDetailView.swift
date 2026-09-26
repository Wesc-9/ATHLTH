import MapKit
import SwiftUI

struct RouteDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var watchConnection: AppleWatchConnectionStore
    @EnvironmentObject private var health: HealthKitManager

    @StateObject private var attempts = RouteAttemptStore()
    @StateObject private var discovery = RouteDiscoveryStore()

    let route: TrainingRoute

    @State private var showingDeleteConfirmation = false
    @State private var showingFullLeaderboard = false
    @State private var editingTitle = false
    @State private var draftTitle = ""
    @State private var watchMessage: String?
    @State private var watchError: String?
    @State private var startingRoute = false

    private var currentRoute: TrainingRoute {
        session.savedRoutes.first {
            $0.id == route.id
        } ?? route
    }

    private var isOwner: Bool {
        currentRoute.ownerID == session.profile.userID
    }

    private var savedCopy: TrainingRoute? {
        if isOwner {
            return currentRoute
        }

        return session.savedRoutes.first {
            $0.sharedSourceRouteID == currentRoute.id
        }
    }

    private var leaderboard: [RouteAttemptRecord] {
        attempts.leaderboard()
    }

    private var topThree: [RouteAttemptRecord] {
        Array(leaderboard.prefix(3))
    }

    private var ownAttempts: [RouteAttemptRecord] {
        attempts.attempts(for: session.profile.userID)
    }

    private var ownBest: RouteAttemptRecord? {
        attempts.bestAttempt(for: session.profile.userID)
    }

    private var ownLatest: RouteAttemptRecord? {
        attempts.latestAttempt(for: session.profile.userID)
    }

    private var ownRank: Int? {
        guard let index = leaderboard.firstIndex(
            where: { $0.userID == session.profile.userID }
        ) else {
            return nil
        }

        return index + 1
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                mapCard
                overviewCard

                if isOwner {
                    privacyCard
                }

                performanceCard
                leaderboardCard
                attemptsCard
                actionsCard
            }
            .padding()
            .padding(.bottom, 80)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(
            LinearGradient(
                colors: [
                    ATHLTHTheme.canvasTop,
                    ATHLTHTheme.canvasBottom
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .navigationTitle(currentRoute.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isOwner {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            draftTitle = currentRoute.title
                            editingTitle = true
                        } label: {
                            Label(
                                "Rename Route",
                                systemImage: "pencil"
                            )
                        }

                        NavigationLink {
                            ChallengeCreationView(
                                preselectedRouteID: currentRoute.id
                            )
                        } label: {
                            Label(
                                "Create Challenge",
                                systemImage: "trophy.fill"
                            )
                        }

                        Divider()

                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Label(
                                "Delete Route",
                                systemImage: "trash"
                            )
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .task(id: currentRoute.id) {
            await prepareRouteData()
        }
        .refreshable {
            await prepareRouteData(forceHealthSync: true)
        }
        .confirmationDialog(
            "Delete \(currentRoute.title)?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Route", role: .destructive) {
                Task {
                    await deleteRoute()
                }
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "The saved route will be removed. Planned workouts keep their workout data, but the deleted route will no longer be attached."
            )
        }
        .alert(
            "Rename Route",
            isPresented: $editingTitle
        ) {
            TextField("Route name", text: $draftTitle)

            Button("Save") {
                updateTitle()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose the name shown in Routes and challenges.")
        }
        .sheet(isPresented: $showingFullLeaderboard) {
            NavigationStack {
                fullLeaderboard
                    .navigationTitle("Leaderboard")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                showingFullLeaderboard = false
                            }
                        }
                    }
            }
        }
        .alert(
            "ATHLTH",
            isPresented: Binding(
                get: {
                    watchMessage != nil ||
                    watchError != nil ||
                    attempts.errorMessage != nil ||
                    discovery.errorMessage != nil
                },
                set: { visible in
                    if !visible {
                        watchMessage = nil
                        watchError = nil
                        attempts.errorMessage = nil
                        discovery.errorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(
                watchError ??
                attempts.errorMessage ??
                discovery.errorMessage ??
                watchMessage ??
                ""
            )
        }
    }

    private var mapCard: some View {
        ATHLTHCard {
            if currentRoute.coordinates.count >= 2 {
                Map(
                    initialPosition: .region(
                        region(for: currentRoute)
                    )
                ) {
                    MapPolyline(
                        coordinates:
                            currentRoute.coordinates.map(\.coordinate)
                    )
                    .stroke(
                        ATHLTHTheme.accent,
                        lineWidth: 6
                    )

                    if let first = currentRoute.coordinates.first {
                        Marker(
                            currentRoute.startName ?? "Start",
                            coordinate: first.coordinate
                        )
                        .tint(ATHLTHTheme.accent)
                    }

                    if let last = currentRoute.coordinates.last {
                        Marker(
                            currentRoute.endName ?? "Finish",
                            coordinate: last.coordinate
                        )
                        .tint(.red)
                    }
                }
                .frame(height: 270)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 20,
                        style: .continuous
                    )
                )
            }
        }
    }

    private var overviewCard: some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(currentRoute.title)
                            .font(.title2.weight(.bold))

                        if let start = currentRoute.startName,
                           let end = currentRoute.endName {
                            Text("\(start) → \(end)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    visibilityBadge(currentRoute.visibility)
                }

                LazyVGrid(
                    columns: [
                        GridItem(.adaptive(minimum: 130), spacing: 10)
                    ],
                    spacing: 10
                ) {
                    metric(
                        title: "Distance",
                        value: String(
                            format: "%.2f km",
                            currentRoute.distanceKilometers
                        ),
                        icon: "figure.run"
                    )

                    metric(
                        title: "Elevation",
                        value: currentRoute.elevationGainMeters.map {
                            "\(Int($0.rounded())) m"
                        } ?? "—",
                        icon: "mountain.2.fill"
                    )

                    metric(
                        title: "Attempts",
                        value: "\(attempts.attempts.count)",
                        icon: "arrow.trianglehead.2.clockwise.rotate.90"
                    )

                    metric(
                        title: "Leaderboard",
                        value: "\(leaderboard.count)",
                        icon: "trophy.fill"
                    )
                }
            }
        }
    }

    private var privacyCard: some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Route visibility")
                    .font(.headline)

                Text(
                    "Choose who can discover this route and appear with you on its leaderboard."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Picker(
                    "Visibility",
                    selection: Binding(
                        get: { currentRoute.visibility },
                        set: { updateVisibility($0) }
                    )
                ) {
                    Label(
                        "Only me",
                        systemImage: "lock.fill"
                    )
                    .tag(ProfileVisibility.privateOnly)

                    Label(
                        "Friends",
                        systemImage: "person.2.fill"
                    )
                    .tag(ProfileVisibility.friends)

                    Label(
                        "Public",
                        systemImage: "globe.europe.africa.fill"
                    )
                    .tag(ProfileVisibility.publicProfile)
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var performanceCard: some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Your performance")
                            .font(.headline)

                        Text(
                            "GPS route adherence from your latest matched attempt."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if attempts.isSyncingHealth {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if let latest = ownLatest {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ],
                        spacing: 10
                    ) {
                        metric(
                            title: "Route followed",
                            value: String(
                                format: "%.0f%%",
                                latest.routeMatchPercent
                            ),
                            icon: "checkmark.circle.fill",
                            tint: routeMatchTint(
                                latest.routeMatchPercent
                            )
                        )

                        metric(
                            title: "Deviation",
                            value: String(
                                format: "%.0f%%",
                                latest.deviationPercent
                            ),
                            icon: "arrow.triangle.branch",
                            tint: latest.deviationPercent <= 15
                                ? ATHLTHTheme.vitality
                                : .orange
                        )

                        metric(
                            title: "Avg off route",
                            value: latest.averageDeviationMeters.map {
                                "\(Int($0.rounded())) m"
                            } ?? "—",
                            icon: "ruler"
                        )

                        metric(
                            title: "Time",
                            value: clock(latest.durationSeconds),
                            icon: "stopwatch.fill"
                        )
                    }

                    if let best = ownBest {
                        HStack {
                            Label(
                                "Best: \(clock(best.durationSeconds))",
                                systemImage: "medal.fill"
                            )

                            Spacer()

                            if let ownRank {
                                Text("#\(ownRank)")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(ATHLTHTheme.accent)
                            }
                        }
                        .font(.caption.weight(.semibold))
                        .padding(.top, 2)
                    }

                    if latest.routeMatchPercent < 85 {
                        Label(
                            "85% route match is required for leaderboard ranking.",
                            systemImage: "info.circle"
                        )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                } else {
                    HStack(spacing: 12) {
                        Image(systemName: "location.magnifyingglass")
                            .font(.title3)
                            .foregroundStyle(ATHLTHTheme.accent)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("No matched attempt yet")
                                .font(.subheadline.weight(.semibold))

                            Text(
                                "Run or walk this route with GPS. ATHLTH will compare the recorded path with the saved route."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var leaderboardCard: some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Leaderboard")
                            .font(.headline)

                        Text(
                            leaderboardSubtitle
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if leaderboard.count > 3 {
                        Button("View all") {
                            showingFullLeaderboard = true
                        }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.plain)
                        .foregroundStyle(ATHLTHTheme.accent)
                    }
                }

                if topThree.isEmpty {
                    Text(
                        "No qualifying route attempts yet. Be the first to complete at least 85% of the route."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
                } else {
                    VStack(spacing: 0) {
                        ForEach(
                            Array(topThree.enumerated()),
                            id: \.element.id
                        ) { index, attempt in
                            leaderboardRow(
                                attempt,
                                rank: index + 1
                            )

                            if index < topThree.count - 1 {
                                Divider()
                            }
                        }
                    }

                    if let ownRank,
                       ownRank > 3,
                       let ownBest {
                        Divider()

                        leaderboardRow(
                            ownBest,
                            rank: ownRank,
                            emphasize: true
                        )
                    }
                }
            }
        }
    }

    private var attemptsCard: some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Your attempts")
                        .font(.headline)

                    Spacer()

                    Text("\(ownAttempts.count)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(ATHLTHTheme.accent)
                }

                if ownAttempts.isEmpty {
                    Text("No attempts recorded on this route yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(
                        Array(ownAttempts.prefix(5).enumerated()),
                        id: \.element.id
                    ) { index, attempt in
                        attemptRow(attempt)

                        if index < min(ownAttempts.count, 5) - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private var actionsCard: some View {
        ATHLTHCard {
            VStack(spacing: 10) {
                if !isOwner && savedCopy == nil {
                    Button {
                        session.saveSharedRoute(
                            currentRoute,
                            sourceOwnerID: currentRoute.ownerID,
                            sourceRouteID: currentRoute.id
                        )
                        watchMessage = "Route saved to My Routes."
                    } label: {
                        Label(
                            "Save Route",
                            systemImage: "bookmark.fill"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ATHLTHTheme.accent)
                    .controlSize(.large)
                }

                if settings.trainingDeviceProvider == .appleWatch {
                    Button {
                        Task {
                            await startRouteOnWatch()
                        }
                    } label: {
                        if startingRoute {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Label(
                                "Start Route",
                                systemImage: "play.fill"
                            )
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ATHLTHTheme.accent)
                    .controlSize(.large)
                    .disabled(
                        startingRoute ||
                        !watchConnection.isReady
                    )
                }

                if let challengeRoute = isOwner
                    ? Optional(currentRoute)
                    : savedCopy {
                    NavigationLink {
                        ChallengeCreationView(
                            preselectedRouteID:
                                challengeRoute.id
                        )
                    } label: {
                        Label(
                            "Challenge Friends",
                            systemImage: "trophy.fill"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }
        }
    }

    private var fullLeaderboard: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if leaderboard.isEmpty {
                    ContentUnavailableView(
                        "No leaderboard yet",
                        systemImage: "trophy",
                        description: Text(
                            "Qualifying attempts need at least 85% route match."
                        )
                    )
                    .padding(.top, 60)
                } else {
                    ForEach(
                        Array(leaderboard.enumerated()),
                        id: \.element.id
                    ) { index, attempt in
                        leaderboardRow(
                            attempt,
                            rank: index + 1
                        )
                        .padding(.horizontal)

                        Divider()
                            .padding(.leading, 70)
                    }
                }
            }
            .padding(.vertical)
        }
        .background(ATHLTHTheme.canvasTop)
    }

    private func leaderboardRow(
        _ attempt: RouteAttemptRecord,
        rank: Int,
        emphasize: Bool = false
    ) -> some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(
                    rank <= 3
                        ? ATHLTHTheme.accent
                        : ATHLTHTheme.mutedText
                )
                .frame(width: 28)

            routeAttemptAvatar(attempt)

            VStack(alignment: .leading, spacing: 2) {
                Text(
                    attempt.userID == session.profile.userID
                        ? "You"
                        : attempt.athleteName
                )
                .font(.subheadline.weight(.semibold))

                Text(
                    String(
                        format: "%.0f%% route · %.2f km",
                        attempt.routeMatchPercent,
                        attempt.distanceMeters / 1_000
                    )
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(clock(attempt.durationSeconds))
                    .font(.subheadline.monospacedDigit().weight(.bold))

                Text(pace(attempt))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 11)
        .padding(.horizontal, emphasize ? 10 : 0)
        .background(
            emphasize
                ? ATHLTHTheme.accentSoft.opacity(0.45)
                : Color.clear,
            in: RoundedRectangle(cornerRadius: 14)
        )
    }

    private func attemptRow(
        _ attempt: RouteAttemptRecord
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "figure.run")
                .foregroundStyle(
                    routeMatchTint(
                        attempt.routeMatchPercent
                    )
                )
                .frame(width: 34, height: 34)
                .background(
                    routeMatchTint(
                        attempt.routeMatchPercent
                    )
                    .opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 10)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(
                    attempt.startedAt.formatted(
                        date: .abbreviated,
                        time: .shortened
                    )
                )
                .font(.subheadline.weight(.semibold))

                Text(
                    String(
                        format: "%.0f%% followed · %.0f%% deviation",
                        attempt.routeMatchPercent,
                        attempt.deviationPercent
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Text(clock(attempt.durationSeconds))
                .font(.caption.monospacedDigit().weight(.semibold))
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func routeAttemptAvatar(
        _ attempt: RouteAttemptRecord
    ) -> some View {
        if let avatar = attempt.avatarURL,
           let url = URL(string: avatar) {
            AsyncImage(url: url) { phase in
                if case .success(let image) = phase {
                    image
                        .resizable()
                        .scaledToFill()
                } else {
                    avatarFallback
                }
            }
            .frame(width: 38, height: 38)
            .clipShape(Circle())
        } else {
            avatarFallback
                .frame(width: 38, height: 38)
        }
    }

    private var avatarFallback: some View {
        Circle()
            .fill(ATHLTHTheme.accentSoft)
            .overlay {
                Image(systemName: "person.fill")
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.accent)
            }
    }

    private func metric(
        title: String,
        value: String,
        icon: String,
        tint: Color = ATHLTHTheme.accent
    ) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(
                    tint.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 10)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text(title)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            Color.primary.opacity(0.025),
            in: RoundedRectangle(cornerRadius: 14)
        )
    }

    private func visibilityBadge(
        _ visibility: ProfileVisibility
    ) -> some View {
        Label(
            visibilityLabel(visibility),
            systemImage: visibilityIcon(visibility)
        )
        .font(.caption2.weight(.semibold))
        .foregroundStyle(ATHLTHTheme.accentDeep)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            ATHLTHTheme.accentSoft,
            in: Capsule()
        )
    }

    private var leaderboardSubtitle: String {
        switch currentRoute.visibility {
        case .privateOnly:
            return "Only your qualifying attempts are visible."
        case .friends:
            return "Best qualifying times from you and friends."
        case .publicProfile:
            return "Best qualifying times from the ATHLTH community."
        }
    }

    private func prepareRouteData(
        forceHealthSync: Bool = false
    ) async {
        if isOwner {
            await discovery.publish(currentRoute)
        }

        if forceHealthSync || health.hasRequestedAuthorization {
            await attempts.syncHealthAttempts(
                for: currentRoute,
                userID: session.profile.userID,
                health: health
            )
        } else {
            await attempts.refresh(routeID: currentRoute.id)
        }
    }

    private func updateVisibility(
        _ visibility: ProfileVisibility
    ) {
        guard isOwner,
              visibility != currentRoute.visibility
        else {
            return
        }

        session.updateSavedRoute(
            currentRoute.id,
            visibility: visibility
        )

        if let updated = session.savedRoutes.first(
            where: { $0.id == currentRoute.id }
        ) {
            Task {
                await discovery.publish(updated)
                await attempts.refresh(routeID: updated.id)
            }
        }
    }

    private func updateTitle() {
        let clean = draftTitle.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !clean.isEmpty else {
            return
        }

        session.updateSavedRoute(
            currentRoute.id,
            title: clean
        )

        if let updated = session.savedRoutes.first(
            where: { $0.id == currentRoute.id }
        ) {
            Task {
                await discovery.publish(updated)
            }
        }
    }

    private func deleteRoute() async {
        guard isOwner else {
            return
        }

        await discovery.remove(routeID: currentRoute.id)

        guard discovery.errorMessage == nil else {
            return
        }

        session.deleteSavedRoute(currentRoute.id)
        dismiss()
    }

    private func startRouteOnWatch() async {
        guard watchConnection.isReady else {
            watchError = "Apple Watch is not ready."
            return
        }

        startingRoute = true
        defer { startingRoute = false }

        do {
            try watchConnection.sendRoute(currentRoute)
            watchConnection.sendWorkoutRouteSelection(
                currentRoute.id
            )
            try await watchConnection.startWorkoutOnWatch(
                .running
            )
            watchConnection.sendRunningWorkout(
                WatchRunningWorkoutTransfer(
                    title: currentRoute.title,
                    steps: [],
                    routeAlerts:
                        settings.routeAlertConfiguration
                )
            )
            watchMessage =
                "\(currentRoute.title) started on Apple Watch."
        } catch {
            watchError = error.localizedDescription
        }
    }

    private func routeMatchTint(
        _ match: Double
    ) -> Color {
        if match >= 90 {
            return ATHLTHTheme.vitality
        }

        if match >= 75 {
            return .orange
        }

        return .red
    }

    private func visibilityLabel(
        _ visibility: ProfileVisibility
    ) -> String {
        switch visibility {
        case .privateOnly:
            return "Only me"
        case .friends:
            return "Friends"
        case .publicProfile:
            return "Public"
        }
    }

    private func visibilityIcon(
        _ visibility: ProfileVisibility
    ) -> String {
        switch visibility {
        case .privateOnly:
            return "lock.fill"
        case .friends:
            return "person.2.fill"
        case .publicProfile:
            return "globe.europe.africa.fill"
        }
    }

    private func clock(
        _ duration: TimeInterval
    ) -> String {
        let seconds = max(Int(duration.rounded()), 0)
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainder = seconds % 60

        if hours > 0 {
            return String(
                format: "%d:%02d:%02d",
                hours,
                minutes,
                remainder
            )
        }

        return String(
            format: "%d:%02d",
            minutes,
            remainder
        )
    }

    private func pace(
        _ attempt: RouteAttemptRecord
    ) -> String {
        guard attempt.distanceMeters > 0 else {
            return "— /km"
        }

        let secondsPerKilometer =
            attempt.durationSeconds /
            (attempt.distanceMeters / 1_000)
        let minutes = Int(secondsPerKilometer) / 60
        let seconds = Int(secondsPerKilometer) % 60

        return String(
            format: "%d:%02d /km",
            minutes,
            seconds
        )
    }

    private func region(
        for route: TrainingRoute
    ) -> MKCoordinateRegion {
        let coordinates = route.coordinates.map(\.coordinate)

        guard let first = coordinates.first else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(
                    latitude: 63.43,
                    longitude: 10.40
                ),
                span: MKCoordinateSpan(
                    latitudeDelta: 0.08,
                    longitudeDelta: 0.08
                )
            )
        }

        let lats = coordinates.map(\.latitude)
        let longs = coordinates.map(\.longitude)
        let minLat = lats.min() ?? first.latitude
        let maxLat = lats.max() ?? first.latitude
        let minLong = longs.min() ?? first.longitude
        let maxLong = longs.max() ?? first.longitude

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2,
                longitude: (minLong + maxLong) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: max(
                    (maxLat - minLat) * 1.35,
                    0.01
                ),
                longitudeDelta: max(
                    (maxLong - minLong) * 1.35,
                    0.01
                )
            )
        )
    }
}
