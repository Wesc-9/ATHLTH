import SwiftUI

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
    @State private var loadingRuns = false
    @State private var sending = false
    @State private var startingChallengeID: UUID?
    @State private var localError: String?
    @State private var captureDevice:
        WorkoutCaptureDevice = .iPhone

    var body: some View {
        List {
            Section {
                QuickStartWorkoutDeviceCard(
                    selection: $captureDevice,
                    watchConnected:
                        watchConnection.isReady &&
                        !watchConnection
                            .workoutLaunchInProgress,
                    iPhoneEnabled:
                        phoneWorkout.active == nil,
                    iPhoneSubtitle:
                        phoneWorkout.active == nil
                            ? ATHLTHLocalization.choose(
                                english:
                                    "Record the friend Ghost Race with iPhone GPS while the other device can remain a companion.",
                                norwegian:
                                    "Registrer Friend Ghost Race med GPS på iPhone, mens den andre enheten kan brukes som companion."
                            )
                            : ATHLTHLocalization.choose(
                                english:
                                    "Finish the active iPhone workout before starting a friend Ghost Race.",
                                norwegian:
                                    "Fullfør den aktive iPhone-økten før du starter Friend Ghost Race."
                            )
                )
                .listRowInsets(
                    EdgeInsets(
                        top: 6,
                        leading: 0,
                        bottom: 6,
                        trailing: 0
                    )
                )
                .listRowBackground(
                    Color.clear
                )
            }
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
                        "Reference run",
                        selection: $selectedWorkoutID
                    ) {
                        Text("Choose run")
                            .tag(UUID?.none)

                        ForEach(runs.prefix(40)) { workout in
                            Text(runTitle(workout))
                                .tag(Optional(workout.id))
                        }
                    }

                    if loadingRuns {
                        ProgressView("Loading runs…")
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
                                "Send Ghost Race",
                                systemImage: "paperplane.fill"
                            )
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ATHLTHTheme.vitality)
                    .disabled(
                        selectedFriendID == nil ||
                        selectedWorkoutID == nil ||
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
        .navigationTitle("Race a Friend")
        .navigationBarTitleDisplayMode(.inline)
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

                Button {
                    Task {
                        await start(challenge)
                    }
                } label: {
                    if startingChallengeID ==
                        challenge.id {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Label(
                            "Race this ghost",
                            systemImage:
                                "figure.run"
                        )
                        .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(ATHLTHTheme.vitality)
                .disabled(
                    startingChallengeID != nil ||
                    (
                        captureDevice == .iPhone
                            ? phoneWorkout.active != nil
                            : (
                                !watchConnection.isReady ||
                                watchConnection
                                    .workoutLaunchInProgress
                            )
                    )
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
        guard let friendID =
                selectedFriendID,
              let friend =
                social.mutualFollows.first(
                    where: {
                        $0.userID == friendID
                    }
                ),
              let workoutID =
                selectedWorkoutID,
              let workout =
                runs.first(
                    where: {
                        $0.id == workoutID
                    }
                )
        else {
            return
        }

        sending = true
        defer {
            sending = false
        }

        let detail =
            await health.workoutDetail(
                for: workout
            )

        let sent =
            await friendRaces.send(
                to: friend,
                workout: workout,
                detail: detail,
                settings: settings
            )

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

            try await GhostRaceStartService.start(
                reference:
                    challenge.reference(),
                ownerID:
                    session.profile.userID,
                comparisonRouteID:
                    challenge.id,
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
