import Foundation
import SwiftUI

// Community V4 is intentionally a social overview rather than another
// scrolling content feed. Weekly Challenge and Friends vs Friends are the two
// retained Community concepts. Everything else is rebuilt around the current
// Follow / Following, messaging, live-training, Clubs and Events models.
struct ATHLTHCommunityV4View: View {
    @EnvironmentObject private var community: CommunityEventStore
    @EnvironmentObject private var officialChallenges: OfficialWeeklyChallengeStore
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var challenges: ChallengeStore
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var groups: CommunityGroupStore
    @EnvironmentObject private var messaging: MessagingStore
    @EnvironmentObject private var realtime: ATHLTHRealtimeSocialStore

    @State private var refreshError: String?
    @State private var showingPeopleSearch = false
    @State private var peopleSearchText = ""
    @State private var searchingPeople = false
    @FocusState private var peopleSearchFocused: Bool

    private var mutuals: [SocialProfileCard] {
        social.mutualFollows
    }

    private var circleFeed: [SocialFeedItem] {
        social.feed
            .filter {
                $0.actor.userID != session.profile.userID
            }
            .sorted {
                $0.activity.createdAt >
                $1.activity.createdAt
            }
    }

    private var activeChallenges: [ATHLTHChallenge] {
        challenges
            .trainingChallenges(
                for: session.profile.userID
            )
            .sorted {
                $0.rules.startsAt <
                $1.rules.startsAt
            }
    }

    private var challengeInvites: [ATHLTHChallenge] {
        challenges.incomingInvitations(
            for: session.profile.userID
        )
    }

    private var onlineFollowing: [SocialProfileCard] {
        social.following.filter {
            realtime.isOnline($0.userID)
        }
    }

    private var visibleCircleLiveSessions:
        [ATHLTHLiveWorkoutSession] {
        realtime.visibleLiveSessions.filter { live in
            live.ownerID != session.profile.userID &&
            (
                social.followingIDs.contains(
                    live.ownerID
                ) ||
                social.followerIDs.contains(
                    live.ownerID
                )
            )
        }
    }

    private var upcomingGroupEvents:
        [CommunityGroupEventRecord] {
        groups.calendarEvents.filter {
            $0.status != "cancelled" &&
            $0.startsAt >= Date()
        }
    }

    private var socialEventCount: Int {
        community.upcomingEvents.count +
        upcomingGroupEvents.count
    }

    private var joinedUpcomingEvents:
        [CommunityEventItem] {
        community.upcomingEvents.filter { item in
            item.event.creatorID ==
                session.profile.userID ||
            item.participantRows.contains {
                $0.userID ==
                    session.profile.userID &&
                (
                    $0.attendanceStatus == .going ||
                    $0.attendanceStatus == .maybe
                )
            }
        }
    }

    private var joinedUpcomingChallenges:
        [ATHLTHChallenge] {
        activeChallenges.filter {
            $0.status == .active ||
            $0.status == .upcoming
        }
    }

    private var discoveryGroups:
        [CommunityGroupRecord] {
        let joined = groups.groups.filter {
            groups.joinedGroupIDs.contains($0.id)
        }
        let publicUnjoined = publicDiscoveryGroups

        return Array(
            (joined + publicUnjoined)
                .reduce(
                    into: [CommunityGroupRecord]()
                ) { result, group in
                    if !result.contains(
                        where: { $0.id == group.id }
                    ) {
                        result.append(group)
                    }
                }
                .prefix(5)
        )
    }

    private var publicDiscoveryGroups:
        [CommunityGroupRecord] {
        groups…85414 tokens truncated…
                        Text("Impersonation").tag("impersonation")
                        Text("Unsafe content").tag("unsafe_content")
                        Text("Other").tag("other")
                    }

                    TextField(
                        "Additional details (optional)",
                        text: $details,
                        axis: .vertical
                    )
                    .lineLimit(3...7)
                }

                Section {
                    Button("Submit Report") {
                        Task {
                            submitting = true
                            let success = await social.report(
                                profile.userID,
                                reason: reason,
                                details: details
                            )
                            submitting = false
                            if success { dismiss() }
                        }
                    }
                    .disabled(submitting)
                }
            }
            .navigationTitle("Report User")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

struct SocialAvatar: View {
    let profile: SocialProfileCard
    let size: CGFloat

    var body: some View {
        Group {
            if let avatarURL = profile.avatarURL,
               let url = URL(string: avatarURL) {
                ATHLTHStorageImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var fallback: some View {
        Circle()
            .fill(ATHLTHTheme.accent.opacity(0.12))
            .overlay {
                Text(profile.resolvedName.prefix(1).uppercased())
                    .font(.system(size: size * 0.34, weight: .bold))
                    .foregroundStyle(ATHLTHTheme.accent)
            }
    }
}

private struct SocialProfileRow<Accessory: View>: View {
    let profile: SocialProfileCard
    let accessory: Accessory

    init(
        profile: SocialProfileCard,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.profile = profile
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 12) {
            SocialAvatar(profile: profile, size: 48)

            VStack(alignment: .leading, spacing: 2) {
                Text(profile.resolvedName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                if !profile.usernameLabel.isEmpty {
                    Text(profile.usernameLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            accessory
        }
        .padding(12)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 17)
        )
    }
}

private extension View {
    func socialCard() -> some View {
        self
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)
            }
    }
}


struct WorkoutInviteLaunchSheet: View {
    @Environment(\.dismiss) private var dismiss

    @EnvironmentObject private var session:
        AppSessionStore
    @EnvironmentObject private var settings:
        AppSettingsStore
    @EnvironmentObject private var social:
        SocialStore
    @EnvironmentObject private var strengthWorkout:
        StrengthWorkoutStore
    @EnvironmentObject private var watchConnection:
        AppleWatchConnectionStore
    @EnvironmentObject private var spotify:
        SpotifyPlaybackStore
    @EnvironmentObject private var gear:
        ProfileGearStore
    @EnvironmentObject private var phoneWorkout:
        IPhoneWorkoutStore
    @EnvironmentObject private var ghostRace:
        GhostRaceStore

    let invite: SocialWorkoutInviteDisplay

    @State private var captureDevice:
        WorkoutCaptureDevice

    init(invite: SocialWorkoutInviteDisplay) {
        self.invite = invite
        _captureDevice = State(
            initialValue:
                invite.participant.captureDevice ==
                    "apple_watch"
                    ? .appleWatch
                    : .iPhone
        )
    }
    @State private var isStarting = false
    @State private var launchError: String?
    @State private var showingStrengthWorkout = false

    private var appleWatchSelectable: Bool {
        ATHLTHDeviceRole.isIPad ||
            watchConnection.isReady
    }

    private var payload:
        SocialWorkoutInvitePayload? {
        invite.session.invitePayload
    }

    private var copiedWorkout:
        PlannedSession? {
        guard let payload else {
            return nil
        }

        var copy = payload.recipientCopy()
        copy.sharedSourceOwnerID =
            invite.session.creatorID
        copy.sharedSourceSessionID =
            payload.workout.id
        return copy
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    introCard

                    if let copiedWorkout {
                        workoutSummary(
                            copiedWorkout
                        )
                        devicePicker

                        lobbyStatusCard

                        Button {
                            readyAndWait(
                                copiedWorkout
                            )
                        } label: {
                            HStack(spacing: 9) {
                                if isStarting {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Image(
                                        systemName:
                                            captureDevice ==
                                                .appleWatch
                                            ? "applewatch"
                                            : "iphone"
                                    )
                                }

                                Text(
                                    startButtonTitle
                                )
                                .font(
                                    .headline.weight(
                                        .semibold
                                    )
                                )
                            }
                            .frame(
                                maxWidth: .infinity
                            )
                        }
                        .buttonStyle(
                            .borderedProminent
                        )
                        .controlSize(.large)
                        .tint(ATHLTHTheme.accent)
                        .disabled(
                            isStarting ||
                            (
                                captureDevice ==
                                    .appleWatch &&
                                !appleWatchSelectable
                            )
                        )
                    } else {
                        ContentUnavailableView(
                            ATHLTHLocalization.choose(
                                english:
                                    "Workout copy unavailable",
                                norwegian:
                                    "Øktkopien er ikke tilgjengelig"
                            ),
                            systemImage:
                                "exclamationmark.triangle",
                            description:
                                Text(
                                    ATHLTHLocalization.choose(
                                        english:
                                            "Ask the sender to send a new Train Together invitation.",
                                        norwegian:
                                            "Be avsenderen sende en ny Tren sammen-invitasjon."
                                    )
                                )
                        )
                        .padding(.vertical, 28)
                    }

                    if let launchError {
                        Text(launchError)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(
                                .center
                            )
                    }
                }
                .padding(16)
            }
            .background(
                ATHLTHPremiumCanvas(
                    accent:
                        ATHLTHTheme.accent
                            .opacity(0.18)
                )
            )
            .navigationTitle(
                ATHLTHLocalization.choose(
                    english: "Train Together",
                    norwegian: "Tren sammen"
                )
            )
            .navigationBarTitleDisplayMode(
                .inline
            )
            .toolbar {
                ToolbarItem(
                    placement:
                        .cancellationAction
                ) {
                    Button(
                        role:
                            isStarting
                                ? .destructive
                                : nil
                    ) {
                        if isStarting {
                            Task {
                                await social
                                    .declineWorkoutInvite(
                                        invite
                                    )
                                dismiss()
                            }
                        } else {
                            dismiss()
                        }
                    } label: {
                        Text(
                            isStarting
                                ? ATHLTHLocalization.choose(
                                    english:
                                        "Leave",
                                    norwegian:
                                        "Forlat"
                                )
                                : ATHLTHLocalization.choose(
                                    english:
                                        "Not now",
                                    norwegian:
                                        "Ikke nå"
                                )
                        )
                    }
                }
            }
        }
        .interactiveDismissDisabled(
            isStarting
        )
        .fullScreenCover(
            isPresented:
                $showingStrengthWorkout
        ) {
            ActiveStrengthWorkoutView()
                .environmentObject(
                    strengthWorkout
                )
                .environmentObject(
                    session
                )
        }
    }

    private var introCard: some View {
        ATHLTHCard {
            HStack(spacing: 12) {
                if let creator =
                        invite.creator {
                    SocialAvatar(
                        profile: creator,
                        size: 48
                    )
                } else {
                    Image(
                        systemName:
                            "person.2.fill"
                    )
                    .font(.title3)
                    .foregroundStyle(
                        ATHLTHTheme.accent
                    )
                    .frame(
                        width: 48,
                        height: 48
                    )
                    .background(
                        ATHLTHTheme
                            .accent
                            .opacity(0.10),
                        in: Circle()
                    )
                }

                VStack(
                    alignment: .leading,
                    spacing: 3
                ) {
                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Invitation accepted",
                            norwegian:
                                "Invitasjonen er godtatt"
                        )
                    )
                    .font(
                        .subheadline
                            .weight(.semibold)
                    )

                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "You get your own copy of the sender's workout.",
                            norwegian:
                                "Du får din egen kopi av økten til avsenderen."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()
            }
        }
    }

    private func workoutSummary(
        _ workout: PlannedSession
    ) -> some View {
        ATHLTHCard {
            VStack(
                alignment: .leading,
                spacing: 10
            ) {
                HStack {
                    Label(
                        workout.title,
                        systemImage:
                            workout.kind
                                .systemImage
                    )
                    .font(
                        .headline.weight(
                            .semibold
                        )
                    )

                    Spacer()
                }

                if workout.kind ==
                    .strength {
                    Text(
                        ATHLTHLocalization.format(
                            english:
                                "%d exercises copied",
                            norwegian:
                                "%d øvelser kopiert",
                            workout.exercises.count
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else if let route =
                            payload?.route {
                    Text(
                        String(
                            format:
                                "%.1f km · %@",
                            route
                                .distanceKilometers,
                            ATHLTHLocalization.choose(
                                english:
                                    "route copied",
                                norwegian:
                                    "rute kopiert"
                            )
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else if let running =
                            workout
                                .resolvedRunningWorkouts
                                .first {
                    Text(running.title)
                        .font(.caption)
                        .foregroundStyle(
                            .secondary
                        )
                }

                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "Device, gear and music stay personal to you.",
                        norwegian:
                            "Enhet, utstyr og musikk velger du selv."
                    )
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var devicePicker: some View {
        ATHLTHCard {
            VStack(
                alignment: .leading,
                spacing: 10
            ) {
                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "Where do you want to train?",
                        norwegian:
                            "Hvor vil du trene?"
                    )
                )
                .font(
                    .subheadline
                        .weight(.semibold)
                )

                HStack(spacing: 10) {
                    deviceButton(
                        device: .iPhone,
                        title: "iPhone",
                        icon: "iphone",
                        enabled: true
                    )

                    deviceButton(
                        device: .appleWatch,
                        title: "Apple Watch",
                        icon: "applewatch",
                        enabled:
                            appleWatchSelectable
                    )
                }

                if ATHLTHDeviceRole.isIPad {
                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "iPad sends your choice to iPhone. Apple Watch starts through the paired iPhone.",
                            norwegian:
                                "iPad sender valget ditt til iPhone. Apple Watch startes via den parede iPhonen."
                        )
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                } else if !watchConnection.isReady {
                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Apple Watch is unavailable right now. You can still start the copied workout on iPhone.",
                            norwegian:
                                "Apple Watch er ikke tilgjengelig akkurat nå. Du kan fortsatt starte øktkopien på iPhone."
                        )
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func deviceButton(
        device: WorkoutCaptureDevice,
        title: String,
        icon: String,
        enabled: Bool
    ) -> some View {
        Button {
            guard enabled else { return }
            captureDevice = device
        } label: {
            VStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.title3)

                Text(title)
                    .font(
                        .caption
                            .weight(.semibold)
                    )
            }
            .foregroundStyle(
                captureDevice == device
                    ? Color.white
                    : ATHLTHTheme
                        .primaryText
            )
            .frame(
                maxWidth: .infinity,
                minHeight: 72
            )
            .background(
                captureDevice == device
                    ? ATHLTHTheme.accent
                    : Color(
                        .secondarySystemGroupedBackground
                    ),
                in: RoundedRectangle(
                    cornerRadius: 16,
                    style: .continuous
                )
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }

    private var startButtonTitle:
        String {
        if isStarting {
            return ATHLTHLocalization.choose(
                english: "Waiting for shared start…",
                norwegian: "Venter på felles start…"
            )
        }

        if ATHLTHDeviceRole.isIPad &&
            captureDevice == .appleWatch {
            return ATHLTHLocalization.choose(
                english:
                    "Ready · Watch via iPhone",
                norwegian:
                    "Klar · Watch via iPhone"
            )
        }

        return ATHLTHLocalization.choose(
            english:
                captureDevice == .appleWatch
                    ? "Ready on Apple Watch"
                    : "Ready on iPhone",
            norwegian:
                captureDevice == .appleWatch
                    ? "Klar på Apple Watch"
                    : "Klar på iPhone"
        )
    }

    private var lobbyStatusCard: some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(
                    ATHLTHLocalization.choose(
                        english: "Shared start",
                        norwegian: "Felles start"
                    )
                )
                .font(.subheadline.weight(.semibold))

                let participants =
                    social.workoutParticipants
                        .filter {
                            $0.sessionID ==
                                invite.session.id
                        }

                ForEach(participants) { participant in
                    HStack(spacing: 9) {
                        Circle()
                            .fill(
                                participant.launchFailedAt != nil
                                    ? Color.red
                                    : participant.workoutStartedAt != nil
                                        ? ATHLTHTheme.accent
                                        : participant.readyAt != nil
                                            ? Color.green
                                            : Color.orange
                            )
                            .frame(width: 8, height: 8)

                        Text(participant.displayNameSnapshot)
                            .font(.caption.weight(.semibold))

                        Spacer()

                        Text(
                            participant.launchFailedAt != nil
                                ? ATHLTHLocalization.choose(
                                    english: "Couldn’t start",
                                    norwegian: "Kunne ikke starte"
                                )
                                : participant.workoutStartedAt != nil
                                    ? ATHLTHLocalization.choose(
                                        english: "Training",
                                        norwegian: "Trener"
                                    )
                                    : participant.readyAt != nil
                                        ? ATHLTHLocalization.choose(
                                            english: "Ready",
                                            norwegian: "Klar"
                                        )
                                        : participant.state == .accepted
                                            ? ATHLTHLocalization.choose(
                                                english: "Accepted",
                                                norwegian: "Godtatt"
                                            )
                                            : ATHLTHLocalization.choose(
                                                english: "Invited",
                                                norwegian: "Invitert"
                                            )
                        )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }

                if let startAt =
                        social.workoutSessions
                            .first(
                                where: {
                                    $0.id ==
                                        invite.session.id
                                }
                            )?
                            .coordinatedStartAt {
                    TimelineView(
                        .periodic(
                            from: .now,
                            by: 0.2
                        )
                    ) { context in
                        let remaining =
                            max(
                                startAt
                                    .timeIntervalSince(
                                        context.date
                                    ),
                                0
                            )
                        let count =
                            max(
                                Int(
                                    ceil(remaining)
                                ),
                                0
                            )

                        HStack {
                            Spacer()

                            Text(
                                count > 0
                                    ? "\(count)"
                                    : ATHLTHLocalization.choose(
                                        english: "GO",
                                        norwegian: "KJØR"
                                    )
                            )
                            .font(
                                .system(
                                    size: 42,
                                    weight: .black,
                                    design: .rounded
                                )
                            )
                            .foregroundStyle(
                                ATHLTHTheme.accent
                            )

                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }

                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "When the sender starts the group, ATHLTH counts down 3–2–1 and starts your copied workout on your chosen device.",
                        norwegian:
                            "Når avsender starter gruppen, teller ATHLTH ned 3–2–1 og starter øktkopien på enheten du valgte."
                    )
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .task {
            try? await social.refreshWorkoutLobby(
                sessionID: invite.session.id
            )
        }
    }

    private func readyAndWait(
        _ workout: PlannedSession
    ) {
        guard !isStarting else { return }

        isStarting = true
        launchError = nil

        Task { @MainActor in
            guard await social.markCurrentUserReady(
                sessionID: invite.session.id,
                captureDevice: captureDevice
            ) else {
                launchError =
                    social.errorMessage ??
                    ATHLTHLocalization.choose(
                        english: "Could not mark you as ready.",
                        norwegian: "Kunne ikke markere deg som klar."
                    )
                isStarting = false
                return
            }

            guard await social.waitForCoordinatedWorkoutStart(
                sessionID: invite.session.id
            ) else {
                launchError =
                    social.errorMessage ??
                    ATHLTHLocalization.choose(
                        english: "The shared workout was cancelled.",
                        norwegian: "Fellesøkten ble avbrutt."
                    )
                isStarting = false
                return
            }

            isStarting = false
            start(workout)
        }
    }

    private func start(
        _ workout: PlannedSession
    ) {
        guard !isStarting else { return }

        isStarting = true
        launchError = nil

        Task { @MainActor in
            do {
                switch workout.kind {
                case .strength:
                    let trackingMode =
                        payload?
                            .strengthTrackingMode ??
                        (
                            workout.exercises
                                .isEmpty
                                ? .simple
                                : .advanced
                        )

                    var advanced =
                        payload?
                            .strengthAdvancedConfiguration ??
                        .standard
                    advanced.spotifyPlaylist = nil
                    advanced.spotifyAutoplay = false

                    let audioCoach =
                        workout
                            .audioCoachConfiguration ??
                        advanced
                            .audioCoach
                            .watchConfiguration

                    let didStart =
                        try await WorkoutLaunchCoordinator
                            .startStrength(
                            workout: workout,
                            captureDevice:
                                captureDevice,
                            trackingMode:
                                trackingMode,
                            selectedFriends: [],
                            audioCoach:
                                audioCoach,
                            advancedConfiguration:
                                advanced,
                            session: session,
                            settings: settings,
                            social: social,
                            strengthWorkout:
                                strengthWorkout,
                            watchConnection:
                                watchConnection,
                            spotify: spotify
                        )

                    guard didStart else {
                        if ATHLTHDeviceRole.isIPad {
                            _ = await social
                                .confirmCurrentJoinedWorkoutStarted()
                            dismiss()
                        }
                        isStarting = false
                        return
                    }

                    showingStrengthWorkout =
                        true

                case .running:
                    let runningWorkout =
                        workout
                            .resolvedRunningWorkouts
                            .first
                    let route =
                        payload?.route
                    let mode:
                        RunQuickStartMode =
                        runningWorkout != nil
                            ? .structured
                            : route != nil
                                ? .route
                                : .free

                    try await WorkoutLaunchCoordinator
                        .startRunQuick(
                            configuration:
                                RunQuickStartConfiguration(
                                    mode: mode,
                                    route: route,
                                    workout:
                                        runningWorkout,
                                    captureDevice:
                                        captureDevice,
                                    environment:
                                        .outdoor,
                                    treadmillInclinePercent:
                                        nil,
                                    audioCoach:
                                        workout
                                            .audioCoachConfiguration ??
                                        .disabled,
                                    routeAlerts:
                                        payload?
                                            .routeAlerts ??
                                        settings
                                            .routeAlertConfiguration,
                                    ghostTargetDurationSeconds:
                                        nil,
                                    ghostUpdates:
                                        nil,
                                    autoPauseEnabled:
                                        workout
                                            .autoPauseEnabled ??
                                        settings
                                            .autoPauseOutdoorWorkouts,
                                    spotifyPlaylist: nil,
                                    spotifyAutoplay: false,
                                    friends: [],
                                    gearIDs: []
                                ),
                            session: session,
                            settings: settings,
                            gear: gear,
                            phoneWorkout:
                                phoneWorkout,
                            watchConnection:
                                watchConnection,
                            spotify: spotify,
                            ghostRace:
                                ghostRace
                        )
                    _ = await social
                        .confirmCurrentJoinedWorkoutStarted()
                    dismiss()

                case .walking:
                    try await WorkoutLaunchCoordinator
                        .startWalkQuick(
                            configuration:
                                WalkQuickStartConfiguration(
                                    captureDevice:
                                        captureDevice,
                                    audioCoach:
                                        workout
                                            .audioCoachConfiguration ??
                                        .disabled,
                                    autoPauseEnabled:
                                        workout
                                            .autoPauseEnabled ??
                                        settings
                                            .autoPauseOutdoorWorkouts,
                                    spotifyPlaylist: nil,
                                    spotifyAutoplay: false,
                                    friends: [],
                                    gearIDs: []
                                ),
                            settings: settings,
                            gear: gear,
                            phoneWorkout:
                                phoneWorkout,
                            watchConnection:
                                watchConnection,
                            spotify: spotify
                        )
                    _ = await social
                        .confirmCurrentJoinedWorkoutStarted()
                    dismiss()

                case .mobility,
                     .recovery,
                     .custom:
                    throw NSError(
                        domain:
                            "ATHLTH.TrainTogether",
                        code: 1,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                ATHLTHLocalization.choose(
                                    english:
                                        "This copied workout type cannot be launched yet.",
                                    norwegian:
                                        "Denne typen øktkopi kan ikke startes ennå."
                                )
                        ]
                    )
                }
            } catch {
                await social
                    .markCurrentJoinedWorkoutLaunchFailed()
                launchError =
                    error.localizedDescription
            }

            isStarting = false
        }
    }
}
