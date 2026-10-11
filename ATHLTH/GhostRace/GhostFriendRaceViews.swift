import SwiftUI

private enum GhostFriendCourseMode: String, CaseIterable, Identifiable {
    case previousWorkout
    case plannedRoute

    var id: String { rawValue }

    var title: String {
        switch self {
        case .previousWorkout:
            return ATHLTHLocalization.choose(
                english: "Previous run", norwegian: "Tidligere økt"
            )
        case .plannedRoute:
            return ATHLTHLocalization.choose(
                english: "Planned route", norwegian: "Velg rute"
            )
        }
    }
}

struct GhostFriendRaceHubView: View {
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var watchConnection: AppleWatchConnectionStore
    @EnvironmentObject private var phoneWorkout: IPhoneWorkoutStore
    @EnvironmentObject private var ghostRace: GhostRaceStore
    @EnvironmentObject private var realtime: ATHLTHRealtimeSocialStore

    @StateObject private var friendRaces =
        GhostFriendRaceStore()

    @State private var runs: [WorkoutSummary] = []
    @State private var selectedFriendID: UUID?
    @State private var selectedWorkoutID: UUID?
    @State private var selectedPlannedRoute: TrainingRoute?
    @State private var courseMode: GhostFriendCourseMode = .previousWorkout
    @State private var targetTimeText = "40:00"
    @State private var showingRoutePicker = false
    @State private var loadingRuns = false
    @State private var sending = false
    @State private var startingChallengeID: UUID?
    @State private var localError: String?
    @State private var captureDevice:
        WorkoutCaptureDevice = .iPhone

    /// Opening a duel from an active Arena 1v1 series can suggest its
    /// opponent; the existing mutual-follow and permission checks remain.
    init(
        preferredFriendID: UUID? = nil,
        preferredRoute: TrainingRoute? = nil
    ) {
        _selectedFriendID = State(initialValue: preferredFriendID)
        _selectedPlannedRoute = State(initialValue: preferredRoute)
        _courseMode = State(initialValue: preferredRoute == nil
            ? .previousWorkout : .plannedRoute)
        if let preferredRoute {
            let suggestion = preferredRoute.expectedTravelTimeSeconds ??
                max(preferredRoute.distanceKilometers * 330, 300)
            _targetTimeText = State(initialValue:
                GhostTargetTimeFormatter.string(suggestion))
        }
    }

    private var targetTime: TimeInterval? {
        guard let seconds = GhostTargetTimeFormatter.parse(targetTimeText),
              seconds.isFinite, (60...86_400).contains(seconds) else {
            return nil
        }
        return seconds
    }

    private var canSendSelectedCourse: Bool {
        switch courseMode {
        case .previousWorkout: return selectedWorkoutID != nil
        case .plannedRoute: return selectedPlannedRoute != nil && targetTime != nil
        }
    }

    var body: some View {
        List {
            Section {
                privacyCard
            }

            Section("Incoming") {
                if friendRaces.incoming.isEmpty {
                    Text("No active Ghost Race invites.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(friendRaces.incoming) { challenge in
                        incomingRow(challenge)
                    }
                }
            }

            Section("Challenge a friend") {
                if social.mutualFollows.isEmpty {
                    ContentUnavailableView(
                        "No friends yet",
                        systemImage: "person.2",
                        description: Text(
                            "Add a friend in Community before sending a Ghost Race."
                        )
                    )
                } else {
                    Picker(
                        "Friend",
                        selection: $selectedFriendID
                    ) {
                        Text("Choose friend")
                            .tag(UUID?.none)

                        ForEach(social.mutualFollows) { friend in
                            Text(friend.resolvedName)
                                .tag(Optional(friend.userID))
                        }
                    }

                    Picker(
                        ATHLTHLocalization.choose(
                            english: "Course source", norwegian: "Velg grunnlag"
                        ),
                        selection: $courseMode
                    ) {
                        ForEach(GhostFriendCourseMode.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    if courseMode == .previousWorkout {
                        Picker(
                            ATHLTHLocalization.choose(
                                english: "GPS reference run", norwegian: "GPS-økt"
                            ),
                            selection: $selectedWorkoutID
                        ) {
                            Text(ATHLTHLocalization.choose(
                                english: "Choose run", norwegian: "Velg økt"
                            ))
                            .tag(UUID?.none)

                            ForEach(runs.prefix(40)) { workout in
                                Text(runTitle(workout))
                                    .tag(Optional(workout.id))
                            }
                        }

                        if loadingRuns {
                            ProgressView(
                                ATHLTHLocalization.choose(
                                    english: "Loading past runs…",
                                    norwegian: "Henter tidligere økter…"
                                )
                            )
                        }

                        Text(ATHLTHLocalization.choose(
                            english: "The selected run's GPS course and pace are used as the reference. You choose whether to share it.",
                            norwegian: "GPS-løypen og tiden fra den valgte økten brukes som grunnlag. Du velger selv om du vil dele."
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    } else {
                        Button {
                            showingRoutePicker = true
                        } label: {
                            HStack {
                                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                                Text(selectedPlannedRoute?.title ??
                                    ATHLTHLocalization.choose(
                                        english: "Choose or create route",
                                        norwegian: "Velg eller lag rute"
                                    ))
                                Spacer(minLength: 4)
                                Image(systemName: "chevron.right")
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(ATHLTHTheme.accentDeep)

                        if let route = selectedPlannedRoute {
                            Label(
                                String(format: "%.2f km", route.distanceKilometers),
                                systemImage: "map"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }

                        HStack {
                            TextField(
                                ATHLTHLocalization.choose(
                                    english: "Target finish time (mm:ss)",
                                    norwegian: "Måltid (mm:ss)"
                                ),
                                text: $targetTimeText
                            )
                            .keyboardType(.numbersAndPunctuation)
                            Text("mm:ss")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if targetTime == nil {
                            Text(ATHLTHLocalization.choose(
                                english: "Enter a target time between 1 minute and 24 hours.",
                                norwegian: "Velg en måltid mellom 1 minutt og 24 timer."
                            ))
                            .font(.caption)
                            .foregroundStyle(.red)
                        }

                        Text(ATHLTHLocalization.choose(
                            english: "Your selected route and a synthetic pacing reference are shared with the friend; no previous workout is claimed. Both start together in the Live Ghost lobby.",
                            norwegian: "Den valgte ruten og en beregnet mål-Ghost deles med vennen, ikke en tidligere økt. Begge starter samtidig fra Live Ghost-lobbyen."
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Button {
                        Task {
                            await sendChallenge()
                        }
                    } label: {
                        if sending || friendRaces.isSending {
                            HStack {
                                ProgressView()
                                Text("Sending…")
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            Label(
                                ATHLTHLocalization.choose(
                                    english: "Invite to synchronized duel",
                                    norwegian: "Inviter til synkronisert duell"
                                ),
                                systemImage: "paperplane.fill"
                            )
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ATHLTHTheme.vitality)
                    .disabled(
                        selectedFriendID == nil ||
                        !canSendSelectedCourse ||
                        sending ||
                        friendRaces.isSending
                    )
                }
            }

            Section("Sent") {
                if friendRaces.outgoing.isEmpty {
                    Text("No active sent Ghost Races.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(friendRaces.outgoing) { challenge in
                        outgoingRow(challenge)
                    }
                }
            }

            Section {
                NavigationLink {
                    ChallengeCreationView()
                } label: {
                    Label(
                        "Create a standard challenge",
                        systemImage: "trophy.fill"
                    )
                }

                Text(
                    "Standard challenges still support distance, route and verification rules. Ghost Race is the live head-to-head mode."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(ATHLTHLocalization.choose(
            english: "Live Ghost duel", norwegian: "Live Ghost-duell"
        ))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingRoutePicker) {
            NavigationStack {
                SavedRoutesView(
                    selectionTitle: ATHLTHLocalization.choose(
                        english: "Duel route", norwegian: "Rute for duellen"
                    ),
                    onSelect: { route in
                        selectedPlannedRoute = route
                        let suggested = route.expectedTravelTimeSeconds ??
                            max(route.distanceKilometers * 330, 300)
                        targetTimeText = GhostTargetTimeFormatter.string(suggested)
                        showingRoutePicker = false
                    }
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(ATHLTHLocalization.choose(
                            english: "Close", norwegian: "Lukk"
                        )) { showingRoutePicker = false }
                    }
                }
            }
        }
        .task {
            await social.refresh()
            await friendRaces.refresh()
            await realtime.refreshOnlineUsers()
            await realtime.refreshVisibleLiveSessions()
            await loadRuns()
        }
        .refreshable {
            await social.refresh()
            await friendRaces.refresh()
            await realtime.refreshOnlineUsers()
            await realtime.refreshVisibleLiveSessions()
            await loadRuns()
        }
        .alert(
            "Race a Friend",
            isPresented: Binding(
                get: {
                    localError != nil ||
                    friendRaces.errorMessage != nil
                },
                set: { visible in
                    if !visible {
                        localError = nil
                        friendRaces.errorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(
                localError ??
                friendRaces.errorMessage ??
                ""
            )
        }
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                "Private by design",
                systemImage: "lock.shield.fill"
            )
            .font(.headline)
            .foregroundStyle(ATHLTHTheme.vitality)

            Text(
                "A friend receives only the sampled route and timing needed to replay the ghost. Heart rate, calories, HealthKit identifiers and the original workout are never shared."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)

            if settings.hideRouteStartAndEnd {
                Label(
                    "Your first and last 250 m are removed before the ghost is uploaded.",
                    systemImage: "location.slash.fill"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            } else {
                Label(
                    "Hide route start/end is off. The full selected route will be shared with the chosen friend.",
                    systemImage: "location.fill"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
    }

    private func incomingRow(
        _ challenge:
            GhostFriendRaceChallengeRecord
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(
                            profileName(
                                challenge.senderID
                            )
                        )
                        .font(.headline)

                        if realtime.isOnline(
                            challenge.senderID
                        ) {
                            Circle()
                                .fill(Color.green)
                                .frame(
                                    width: 8,
                                    height: 8
                                )
                                .accessibilityLabel(
                                    "Online"
                                )
                        }
                    }

                    Text(challenge.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                statusBadge(challenge.status)
            }

            HStack(spacing: 14) {
                Label(
                    distanceText(
                        challenge.distanceMeters
                    ),
                    systemImage: "location.fill"
                )

                Label(
                    durationText(
                        challenge
                            .referenceDurationSeconds
                    ),
                    systemImage: "stopwatch.fill"
                )

                if challenge.privacyTrimmed {
                    Label(
                        "Trimmed",
                        systemImage:
                            "lock.shield.fill"
                    )
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if challenge.status == .pending {
                HStack(spacing: 10) {
                    Button("Accept") {
                        Task {
                            await friendRaces.respond(
                                challenge,
                                status: .accepted
                            )
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ATHLTHTheme.vitality)

                    Button("Decline") {
                        Task {
                            await friendRaces.respond(
                                challenge,
                                status: .declined
                            )
                        }
                    }
                    .buttonStyle(.bordered)
                }
            } else if challenge.status == .accepted {
                if let liveSession =
                    realtime.visibleLiveSessions
                        .first(
                            where: {
                                $0.ghostChallengeID ==
                                    challenge.id
                            }
                        ) {
                    NavigationLink {
                        ATHLTHLiveWorkoutMapView(
                            session: liveSession
                        )
                    } label: {
                        Label(
                            "Open live Ghost Run",
                            systemImage:
                                "location.circle.fill"
                        )
                    }
                    .buttonStyle(.bordered)
                }

                NavigationLink {
                    LiveGhostRaceLobbyView(
                        challenge: challenge
                    )
                } label: {
                    Label(
                        ATHLTHLocalization.choose(
                            english:
                                "Open Live Ghost lobby",
                            norwegian:
                                "Åpne Live Ghost-lobby"
                        ),
                        systemImage:
                            "person.2.wave.2.fill"
                    )
                    .frame(
                        maxWidth: .infinity
                    )
                }
                .buttonStyle(
                    .borderedProminent
                )
                .tint(
                    ATHLTHTheme.vitality
                )
            }
        }
        .padding(.vertical, 5)
    }

    private func outgoingRow(
        _ challenge:
            GhostFriendRaceChallengeRecord
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(
                        profileName(
                            challenge.recipientID
                        )
                    )
                    .font(.headline)

                    Text(challenge.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                statusBadge(challenge.status)
            }

            HStack {
                Text(
                    challenge.createdAt.formatted(
                        date: .abbreviated,
                        time: .shortened
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Spacer()

                if challenge.status == .pending {
                    Button(
                        "Cancel",
                        role: .destructive
                    ) {
                        Task {
                            await friendRaces.respond(
                                challenge,
                                status: .cancelled
                            )
                        }
                    }
                    .font(.caption.weight(.semibold))
                }
            }

            if challenge.status == .accepted {
                NavigationLink {
                    LiveGhostRaceLobbyView(
                        challenge: challenge
                    )
                } label: {
                    Label(
                        ATHLTHLocalization.choose(
                            english:
                                "Open Live Ghost lobby",
                            norwegian:
                                "Åpne Live Ghost-lobby"
                        ),
                        systemImage:
                            "person.2.wave.2.fill"
                    )
                    .frame(
                        maxWidth: .infinity
                    )
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func statusBadge(
        _ status: GhostFriendRaceStatus
    ) -> some View {
        Text(statusTitle(status))
            .font(.caption2.weight(.bold))
            .foregroundStyle(
                status == .accepted
                    ? ATHLTHTheme.vitality
                    : .secondary
            )
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                (
                    status == .accepted
                        ? ATHLTHTheme.vitality
                        : Color.secondary
                ).opacity(0.10),
                in: Capsule()
            )
    }

    @MainActor
    private func sendChallenge() async {
        guard let friendID = selectedFriendID,
              let friend = social.mutualFollows.first(where: {
                  $0.userID == friendID
              }), !sending else { return }

        sending = true
        defer { sending = false }

        let sent: Bool
        switch courseMode {
        case .plannedRoute:
            guard let route = selectedPlannedRoute,
                  let seconds = targetTime else { return }
            sent = await friendRaces.sendPlannedRoute(
                to: friend,
                route: route,
                targetDurationSeconds: seconds,
                settings: settings
            )
        case .previousWorkout:
            guard let workoutID = selectedWorkoutID,
                  let workout = runs.first(where: {
                      $0.id == workoutID
                  }) else { return }
            let detail = await health.workoutDetail(for: workout)
            sent = await friendRaces.send(
                to: friend,
                workout: workout,
                detail: detail,
                settings: settings
            )
        }

        if sent {
            selectedFriendID = nil
            selectedWorkoutID = nil
        }
    }

    @MainActor
    private func start(
        _ challenge:
            GhostFriendRaceChallengeRecord
    ) async {
        guard challenge.status ==
                .accepted
        else {
            localError =
                GhostFriendRaceError
                    .notAccepted
                    .localizedDescription
            return
        }

        switch captureDevice {
        case .iPhone:
            guard phoneWorkout.active == nil
            else {
                localError =
                    "Finish the active iPhone workout before starting a friend Ghost Race."
                return
            }

        case .appleWatch:
            guard watchConnection.isReady
            else {
                localError =
                    "Connect Apple Watch or choose iPhone before starting a friend Ghost Race."
                return
            }
        }

        startingChallengeID =
            challenge.id
        defer {
            startingChallengeID = nil
        }

        do {
            realtime.selectLiveGhost(nil)

            let currentUserID =
                session.profile.userID
            let opponentUserID =
                challenge.senderID ==
                    currentUserID
                    ? challenge.recipientID
                    : challenge.senderID
            let opponent =
                profileName(
                    opponentUserID
                )

            try await GhostRaceStartService.start(
                reference:
                    challenge.reference(),
                ownerID:
                    currentUserID,
                comparisonRouteID:
                    challenge.id,
                opponentName:
                    opponent,
                ghostRace:
                    ghostRace,
                watchConnection:
                    watchConnection,
                phoneWorkout:
                    phoneWorkout,
                captureDevice:
                    captureDevice,
                settings:
                    settings
            )

            if social.privacy?
                .shareLiveWorkoutLocation ==
                true {
                _ = await realtime
                    .beginGhostSession(
                        challenge: challenge
                    )
            }
        } catch {
            localError =
                error.localizedDescription
        }
    }

    @MainActor
    private func loadRuns() async {
        loadingRuns = true
        defer {
            loadingRuns = false
        }

        let history =
            (try? await health.workoutHistory()) ??
            health.workouts

        runs =
            history
                .filter {
                    $0.activity == .running &&
                    ($0.distanceMeters ?? 0) >=
                        250
                }
                .sorted {
                    $0.startDate >
                    $1.startDate
                }
    }

    private func profileName(
        _ userID: UUID
    ) -> String {
        social.mutualFollows.first(
            where: {
                $0.userID == userID
            }
        )?.resolvedName ??
        social.visibleProfiles.first(
            where: {
                $0.userID == userID
            }
        )?.resolvedName ??
        "ATHLTH Athlete"
    }

    private func statusTitle(
        _ status: GhostFriendRaceStatus
    ) -> String {
        switch status {
        case .pending:
            return "PENDING"
        case .accepted:
            return "ACCEPTED"
        case .declined:
            return "DECLINED"
        case .cancelled:
            return "CANCELLED"
        }
    }

    private func runTitle(
        _ workout: WorkoutSummary
    ) -> String {
        let distance =
            workout.distanceKilometers.map {
                String(
                    format: "%.1f km",
                    $0
                )
            } ?? "Run"

        return
            "\(workout.startDate.formatted(date: .abbreviated, time: .omitted)) · \(distance) · \(durationText(workout.duration))"
    }

    private func distanceText(
        _ meters: Double
    ) -> String {
        String(
            format: "%.2f km",
            meters / 1_000
        )
    }

    private func durationText(
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
        let remainder =
            total % 60

        if hours > 0 {
            return String(
                format:
                    "%d:%02d:%02d",
                hours,
                minutes,
                remainder
            )
        }

        return String(
            format:
                "%d:%02d",
            minutes,
            remainder
        )
    }
}
