import MapKit
import SwiftUI

struct GhostRaceHubView: View {
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var watchConnection: AppleWatchConnectionStore
    @EnvironmentObject private var ghostRace: GhostRaceStore

    @State private var recentRuns: [WorkoutSummary] = []
    @State private var loading = false
    @State private var startingWorkoutID: UUID?
    @State private var errorMessage: String?

    private var canStartRace: Bool {
        settings.trainingDeviceProvider == .appleWatch &&
        watchConnection.isReady &&
        !watchConnection.workoutLaunchInProgress
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                hero
                modeOverview
                audioCoachCard
                pastSelfSection
                routeSection
                friendSection
            }
            .padding()
            .padding(.bottom, 36)
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
        .navigationTitle("Ghost Race")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadRuns()
        }
        .refreshable {
            await loadRuns()
        }
        .alert(
            "Ghost Race",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { visible in
                    if !visible {
                        errorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var hero: some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("RACE YOURSELF")
                            .font(.caption2.weight(.bold))
                            .tracking(2)
                            .foregroundStyle(ATHLTHTheme.vitality)

                        Text("Same roads. A faster you.")
                            .font(.system(
                                size: 30,
                                weight: .bold,
                                design: .rounded
                            ))
                            .foregroundStyle(ATHLTHTheme.primaryText)
                    }

                    Spacer()

                    Image(systemName: "figure.run.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(ATHLTHTheme.vitality)
                }

                Text(
                    "Turn a previous outdoor run into a live ghost. ATHLTH follows your position on the same route and shows who is ahead while you run."
                )
                .font(.subheadline)
                .foregroundStyle(ATHLTHTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    statusChip(
                        title: "Live GPS",
                        icon: "location.fill"
                    )
                    statusChip(
                        title: "Watch",
                        icon: "applewatch"
                    )
                    statusChip(
                        title: "Past self",
                        icon: "clock.arrow.circlepath"
                    )
                }

                if !canStartRace {
                    Label(
                        watchRequirementText,
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.top, 2)
                }
            }
        }
    }

    private var modeOverview: some View {
        HStack(spacing: 10) {
            modeTile(
                title: "Past self",
                subtitle: "Replay a run",
                icon: "person.fill.viewfinder"
            )

            modeTile(
                title: "Your best",
                subtitle: "Saved routes",
                icon: "medal.fill"
            )

            modeTile(
                title: "Friends",
                subtitle: "Challenge",
                icon: "person.2.fill"
            )
        }
    }

    private var audioCoachCard: some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Ghost Audio Coach")
                            .font(.headline)

                        Text(
                            "Hear your lead without looking at the screen."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Toggle(
                        "",
                        isOn:
                            $settings
                                .ghostRaceAudioEnabled
                    )
                    .labelsHidden()
                }

                if settings.ghostRaceAudioEnabled {
                    Toggle(
                        "Announce every distance",
                        isOn:
                            $settings
                                .ghostRaceAudioUseDistance
                    )

                    if settings
                        .ghostRaceAudioUseDistance {
                        HStack {
                            Text("Distance interval")
                            Spacer()
                            Picker(
                                "Distance interval",
                                selection:
                                    $settings
                                        .ghostRaceAudioDistanceIntervalKilometers
                            ) {
                                Text("0.5 km")
                                    .tag(0.5)
                                Text("1 km")
                                    .tag(1.0)
                                Text("2 km")
                                    .tag(2.0)
                            }
                            .pickerStyle(.menu)
                        }
                    }

                    Toggle(
                        "Announce every time interval",
                        isOn:
                            $settings
                                .ghostRaceAudioUseTime
                    )

                    if settings
                        .ghostRaceAudioUseTime {
                        HStack {
                            Text("Time interval")
                            Spacer()
                            Picker(
                                "Time interval",
                                selection:
                                    $settings
                                        .ghostRaceAudioTimeIntervalMinutes
                            ) {
                                Text("2 min")
                                    .tag(2)
                                Text("5 min")
                                    .tag(5)
                                Text("10 min")
                                    .tag(10)
                            }
                            .pickerStyle(.menu)
                        }
                    }

                    Toggle(
                        "Announce meaningful lead changes",
                        isOn:
                            $settings
                                .ghostRaceAudioAnnounceLeadChanges
                    )

                    if settings
                        .ghostRaceAudioAnnounceLeadChanges {
                        HStack {
                            Text("Lead-change threshold")
                            Spacer()
                            Picker(
                                "Lead-change threshold",
                                selection:
                                    $settings
                                        .ghostRaceAudioLeadChangeMeters
                            ) {
                                Text("15 m")
                                    .tag(15.0)
                                Text("25 m")
                                    .tag(25.0)
                                Text("50 m")
                                    .tag(50.0)
                                Text("100 m")
                                    .tag(100.0)
                            }
                            .pickerStyle(.menu)
                        }
                    }

                    HStack {
                        Text("Delivery")
                        Spacer()
                        Picker(
                            "Delivery",
                            selection:
                                $settings
                                    .ghostRaceAudioDelivery
                        ) {
                            ForEach(
                                WatchAlertDelivery
                                    .allCases
                            ) { delivery in
                                Text(delivery.title)
                                    .tag(delivery)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    Text(
                        "Voice uses your existing Audio Coach language setting. Lead-change alerts have a cooldown so ATHLTH does not talk constantly during close races."
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var pastSelfSection: some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Race past self")
                            .font(.headline)
                        Text("Choose a previous GPS run to use as the ghost.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if loading {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if recentRuns.isEmpty && !loading {
                    ContentUnavailableView(
                        "No running history",
                        systemImage: "figure.run",
                        description: Text(
                            "Outdoor runs from Apple Health will appear here when a GPS route is available."
                        )
                    )
                    .frame(minHeight: 150)
                } else {
                    VStack(spacing: 0) {
                        ForEach(recentRuns.prefix(8)) { workout in
                            runRow(workout)

                            if workout.id !=
                                recentRuns.prefix(8).last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }

    private var routeSection: some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Race your best")
                            .font(.headline)
                        Text(
                            "Open one of your saved routes and race your best or latest matched attempt."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    NavigationLink {
                        RouteLibraryListView(
                            source: .mine
                        )
                    } label: {
                        Text("All routes")
                            .font(.caption.weight(.semibold))
                    }
                }

                if session.savedRoutes.isEmpty {
                    Text(
                        "Save or create a route first. ATHLTH will match your Apple Health attempts to it."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                } else {
                    ForEach(
                        session.savedRoutes
                            .sorted {
                                $0.createdAt >
                                $1.createdAt
                            }
                            .prefix(4)
                    ) { route in
                        NavigationLink {
                            RouteDetailView(route: route)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "map.fill")
                                    .foregroundStyle(ATHLTHTheme.vitality)
                                    .frame(width: 40, height: 40)
                                    .background(
                                        ATHLTHTheme.vitalitySoft,
                                        in: RoundedRectangle(
                                            cornerRadius: 12
                                        )
                                    )

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(route.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(ATHLTHTheme.primaryText)

                                    Text(
                                        String(
                                            format: "%.2f km",
                                            route.distanceKilometers
                                        )
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption.bold())
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 5)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var friendSection: some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "person.2.fill")
                        .font(.title3)
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                        .frame(width: 44, height: 44)
                        .background(
                            ATHLTHTheme.accentSoft,
                            in: RoundedRectangle(
                                cornerRadius: 13
                            )
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Challenge a friend")
                            .font(.headline)

                        Text(
                            "Use ATHLTH Challenges for route, distance and verified GPS rules."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()
                }

                NavigationLink {
                    ChallengeCreationView()
                } label: {
                    Label(
                        "Create running challenge",
                        systemImage: "trophy.fill"
                    )
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
    }

    private func runRow(
        _ workout: WorkoutSummary
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "figure.run")
                .font(.headline)
                .foregroundStyle(ATHLTHTheme.vitality)
                .frame(width: 42, height: 42)
                .background(
                    ATHLTHTheme.vitalitySoft,
                    in: RoundedRectangle(
                        cornerRadius: 12
                    )
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(
                    workout.startDate.formatted(
                        date: .abbreviated,
                        time: .shortened
                    )
                )
                .font(.subheadline.weight(.semibold))

                HStack(spacing: 8) {
                    if let distance =
                        workout.distanceKilometers {
                        Text(
                            String(
                                format: "%.2f km",
                                distance
                            )
                        )
                    }

                    Text(clock(workout.duration))

                    if let pace =
                        workout.paceMinutesPerKilometer {
                        Text(paceText(pace))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task {
                    await start(workout)
                }
            } label: {
                if startingWorkoutID == workout.id {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 54)
                } else {
                    Text("Race")
                        .font(.caption.weight(.bold))
                        .frame(width: 54)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(ATHLTHTheme.vitality)
            .disabled(
                !canStartRace ||
                startingWorkoutID != nil
            )
        }
        .padding(.vertical, 8)
    }

    private func start(
        _ workout: WorkoutSummary
    ) async {
        guard canStartRace else {
            errorMessage = watchRequirementText
            return
        }

        startingWorkoutID = workout.id
        defer {
            startingWorkoutID = nil
        }

        let detail =
            await health.workoutDetail(
                for: workout
            )

        do {
            try await GhostRaceStartService.start(
                workout: workout,
                detail: detail,
                ownerID: session.profile.userID,
                ghostRace: ghostRace,
                watchConnection: watchConnection,
                settings: settings
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadRuns() async {
        loading = true
        defer {
            loading = false
        }

        guard health.hasRequestedAuthorization else {
            recentRuns = []
            return
        }

        let history =
            (try? await health.workoutHistory()) ??
            health.workouts

        recentRuns =
            history
                .filter {
                    $0.activity == .running &&
                    ($0.distanceMeters ?? 0) >= 250
                }
                .sorted {
                    $0.startDate >
                    $1.startDate
                }
    }

    private var watchRequirementText: String {
        if settings.trainingDeviceProvider != .appleWatch {
            return "Ghost Race live comparison currently requires Apple Watch."
        }

        if !watchConnection.isReady {
            return "Connect Apple Watch before starting a Ghost Race."
        }

        if watchConnection.workoutLaunchInProgress {
            return "Apple Watch is already preparing a workout."
        }

        return "Apple Watch is not ready."
    }

    private func statusChip(
        title: String,
        icon: String
    ) -> some View {
        Label(title, systemImage: icon)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(ATHLTHTheme.primaryText)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                ATHLTHTheme.surfaceSage,
                in: Capsule()
            )
    }

    private func modeTile(
        title: String,
        subtitle: String,
        icon: String
    ) -> some View {
        VStack(spacing: 7) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(ATHLTHTheme.vitality)

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(ATHLTHTheme.primaryText)

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            ATHLTHTheme.card,
            in: RoundedRectangle(
                cornerRadius: 17,
                style: .continuous
            )
        )
    }

    private func clock(
        _ seconds: TimeInterval
    ) -> String {
        let total = max(
            Int(seconds.rounded()),
            0
        )
        let hours = total / 3_600
        let minutes =
            (total % 3_600) / 60
        let remainder = total % 60

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

    private func paceText(
        _ minutesPerKilometer: Double
    ) -> String {
        let seconds =
            max(
                Int(
                    (
                        minutesPerKilometer *
                        60
                    ).rounded()
                ),
                0
            )

        return String(
            format: "%d:%02d /km",
            seconds / 60,
            seconds % 60
        )
    }
}

struct GhostRaceLivePanel: View {
    @EnvironmentObject private var ghostRace: GhostRaceStore

    let snapshot: WatchWorkoutLiveSnapshot

    var body: some View {
        if let reference = ghostRace.reference {
            VStack(spacing: 14) {
                statusCard(
                    reference: reference
                )

                if let comparison =
                    ghostRace.comparison {
                    mapCard(
                        reference: reference,
                        comparison: comparison
                    )
                    metrics(
                        comparison: comparison
                    )
                    progressCard(
                        comparison: comparison
                    )
                } else if ghostRace.result == nil {
                    ATHLTHCard {
                        HStack(spacing: 12) {
                            ProgressView()
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Waiting for live GPS")
                                    .font(.subheadline.weight(.semibold))
                                Text(
                                    "ATHLTH will place you and your ghost on the route as soon as Apple Watch sends the first GPS point."
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                }

                if let result =
                    ghostRace.result {
                    resultCard(
                        result
                    )
                }
            }
        }
    }

    private func statusCard(
        reference: GhostRaceReference
    ) -> some View {
        ATHLTHCard {
            HStack(spacing: 13) {
                Image(systemName: "figure.run")
                    .font(.title2)
                    .foregroundStyle(ATHLTHTheme.vitality)
                    .frame(width: 48, height: 48)
                    .background(
                        ATHLTHTheme.vitalitySoft,
                        in: Circle()
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text("GHOST RACE")
                        .font(.caption2.weight(.bold))
                        .tracking(1.5)
                        .foregroundStyle(ATHLTHTheme.mutedText)

                    Text(mainStatus)
                        .font(.headline)
                        .foregroundStyle(ATHLTHTheme.primaryText)

                    Text(
                        reference.startedAt.formatted(
                            date: .abbreviated,
                            time: .shortened
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Text(
                    snapshot.state == .paused
                        ? "PAUSED"
                        : "LIVE"
                )
                .font(.caption2.weight(.bold))
                .foregroundStyle(
                    snapshot.state == .paused
                        ? .orange
                        : ATHLTHTheme.vitality
                )
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(
                    (
                        snapshot.state == .paused
                            ? Color.orange
                            : ATHLTHTheme.vitality
                    ).opacity(0.11),
                    in: Capsule()
                )
            }
        }
    }

    private func mapCard(
        reference: GhostRaceReference,
        comparison: GhostRaceComparison
    ) -> some View {
        ATHLTHCard {
            Map(
                initialPosition:
                    .region(
                        region(
                            reference: reference
                        )
                    )
            ) {
                MapPolyline(
                    coordinates:
                        reference.points.map(
                            \.coordinate
                        )
                )
                .stroke(
                    ATHLTHTheme.vitality
                        .opacity(0.45),
                    lineWidth: 5
                )

                Annotation(
                    "You",
                    coordinate:
                        comparison
                            .userCoordinate
                ) {
                    ZStack {
                        Circle()
                            .fill(
                                ATHLTHTheme
                                    .accentDeep
                            )
                            .frame(
                                width: 24,
                                height: 24
                            )
                        Circle()
                            .stroke(
                                .white,
                                lineWidth: 3
                            )
                            .frame(
                                width: 24,
                                height: 24
                            )
                    }
                }

                Annotation(
                    "Ghost",
                    coordinate:
                        comparison
                            .ghostCoordinate
                ) {
                    Image(systemName: "figure.run")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(
                            ATHLTHTheme.vitality,
                            in: Circle()
                        )
                        .overlay {
                            Circle()
                                .stroke(
                                    .white,
                                    lineWidth: 2
                                )
                        }
                }
            }
            .mapStyle(.standard(
                elevation: .flat
            ))
            .frame(height: 250)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 19,
                    style: .continuous
                )
            )

            if comparison.routeDeviationMeters > 80 {
                Label(
                    "You are about \(Int(comparison.routeDeviationMeters.rounded())) m from the ghost route.",
                    systemImage: "location.slash.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                .padding(.top, 10)
            }
        }
    }

    private func metrics(
        comparison: GhostRaceComparison
    ) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ],
            spacing: 10
        ) {
            ghostMetric(
                title: "Distance",
                value: String(
                    format: "%.2f km",
                    snapshot.distanceMeters /
                    1_000
                ),
                icon: "location.fill"
            )

            ghostMetric(
                title: "Elapsed",
                value:
                    clock(
                        snapshot.elapsedTime
                    ),
                icon: "stopwatch.fill"
            )

            ghostMetric(
                title: "Avg pace",
                value:
                    averagePaceText,
                icon: "gauge.with.dots.needle.50percent"
            )

            ghostMetric(
                title: "Vs ghost",
                value:
                    signedTimeText(
                        comparison
                            .signedTimeSeconds
                    ),
                icon:
                    comparison
                        .signedTimeSeconds >= 0
                        ? "arrow.down.right"
                        : "arrow.up.right"
            )
        }
    }

    private func progressCard(
        comparison: GhostRaceComparison
    ) -> some View {
        ATHLTHCard {
            VStack(spacing: 13) {
                progressRow(
                    title: "You",
                    progress:
                        comparison.userProgress,
                    detail:
                        String(
                            format: "%.0f%%",
                            comparison
                                .userProgress *
                                100
                        ),
                    tint:
                        ATHLTHTheme.accentDeep
                )

                Divider()

                progressRow(
                    title: "Ghost",
                    progress:
                        comparison.ghostProgress,
                    detail:
                        distanceDeltaText(
                            comparison
                                .signedDistanceMeters
                        ),
                    tint:
                        ATHLTHTheme.vitality
                )
            }
        }
    }

    private func resultCard(
        _ result: GhostRaceResult
    ) -> some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 9) {
                Label(
                    resultTitle(result),
                    systemImage:
                        result.beatGhost == true
                            ? "trophy.fill"
                            : "flag.checkered"
                )
                .font(.headline)
                .foregroundStyle(
                    result.beatGhost == true
                        ? ATHLTHTheme.vitality
                        : ATHLTHTheme.primaryText
                )

                Text(
                    resultSubtitle(result)
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var mainStatus: String {
        guard let comparison =
                ghostRace.comparison
        else {
            return "Finding your position…"
        }

        let meters =
            Int(
                abs(
                    comparison
                        .signedDistanceMeters
                ).rounded()
            )

        if meters < 8 {
            return "Neck and neck"
        }

        if comparison.userIsAhead {
            return "You are \(meters) m ahead"
        }

        return "Ghost is \(meters) m ahead"
    }

    private var averagePaceText: String {
        guard snapshot.distanceMeters >= 100,
              snapshot.elapsedTime > 0
        else {
            return "— /km"
        }

        let seconds =
            snapshot.elapsedTime /
            (snapshot.distanceMeters / 1_000)

        let total =
            max(Int(seconds.rounded()), 0)

        return String(
            format: "%d:%02d /km",
            total / 60,
            total % 60
        )
    }

    private func ghostMetric(
        title: String,
        value: String,
        icon: String
    ) -> some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 7) {
                Image(systemName: icon)
                    .foregroundStyle(ATHLTHTheme.vitality)

                Text(value)
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.75)
                    .lineLimit(1)

                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
        }
    }

    private func progressRow(
        title: String,
        progress: Double,
        detail: String,
        tint: Color
    ) -> some View {
        VStack(spacing: 7) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))

                Spacer()

                Text(detail)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            ProgressView(
                value:
                    min(max(progress, 0), 1)
            )
            .tint(tint)
        }
    }

    private func distanceDeltaText(
        _ meters: Double
    ) -> String {
        let rounded =
            Int(abs(meters).rounded())

        if rounded < 8 {
            return "even"
        }

        return meters >= 0
            ? "+\(rounded) m you"
            : "+\(rounded) m ghost"
    }

    private func signedTimeText(
        _ seconds: TimeInterval
    ) -> String {
        let rounded =
            Int(abs(seconds).rounded())
        let prefix =
            seconds >= 0 ? "−" : "+"
        return prefix +
            clock(
                TimeInterval(rounded)
            )
    }

    private func resultTitle(
        _ result: GhostRaceResult
    ) -> String {
        guard result.completedRoute,
              let beat = result.beatGhost
        else {
            return "Ghost Race finished"
        }

        return beat
            ? "You beat your ghost"
            : "Ghost wins this one"
    }

    private func resultSubtitle(
        _ result: GhostRaceResult
    ) -> String {
        guard result.completedRoute,
              let delta =
                result.signedTimeSeconds
        else {
            return "ATHLTH could not confirm enough of the route to compare the finish time reliably."
        }

        let amount =
            clock(abs(delta))

        if abs(delta) < 1 {
            return "You matched your previous time."
        }

        return delta > 0
            ? "You reached the finish \(amount) faster than the reference run."
            : "The reference run reached the finish \(amount) faster."
    }

    private func clock(
        _ seconds: TimeInterval
    ) -> String {
        let total =
            max(
                Int(seconds.rounded()),
                0
            )
        let hours = total / 3_600
        let minutes =
            (total % 3_600) / 60
        let remainder = total % 60

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

    private func region(
        reference: GhostRaceReference
    ) -> MKCoordinateRegion {
        let coordinates =
            reference.points.map(
                \.coordinate
            )

        guard let first =
                coordinates.first
        else {
            return MKCoordinateRegion(
                center:
                    CLLocationCoordinate2D(
                        latitude: 0,
                        longitude: 0
                    ),
                span:
                    MKCoordinateSpan(
                        latitudeDelta: 0.02,
                        longitudeDelta: 0.02
                    )
            )
        }

        let latitudes =
            coordinates.map(\.latitude)
        let longitudes =
            coordinates.map(\.longitude)

        let minLatitude =
            latitudes.min() ??
            first.latitude
        let maxLatitude =
            latitudes.max() ??
            first.latitude
        let minLongitude =
            longitudes.min() ??
            first.longitude
        let maxLongitude =
            longitudes.max() ??
            first.longitude

        return MKCoordinateRegion(
            center:
                CLLocationCoordinate2D(
                    latitude:
                        (
                            minLatitude +
                            maxLatitude
                        ) / 2,
                    longitude:
                        (
                            minLongitude +
                            maxLongitude
                        ) / 2
                ),
            span:
                MKCoordinateSpan(
                    latitudeDelta:
                        max(
                            (
                                maxLatitude -
                                minLatitude
                            ) * 1.35,
                            0.008
                        ),
                    longitudeDelta:
                        max(
                            (
                                maxLongitude -
                                minLongitude
                            ) * 1.35,
                            0.008
                        )
                )
        )
    }
}
