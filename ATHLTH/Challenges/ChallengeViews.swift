import CoreLocation
import MapKit
import PhotosUI
import SwiftUI
import UIKit

struct ProfileChallengesSection: View {
    @EnvironmentObject private var challenges: ChallengeStore

    @State private var showingCreate = false

    private var highlighted: [ATHLTHChallenge] {
        Array(
            challenges.visibleChallenges
                .filter {
                    $0.status == .active ||
                    $0.status == .upcoming ||
                    $0.status == .invited
                }
                .prefix(2)
        )
    }

    var body: some View {
        ATHLTHCard {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Challenges")
                        .font(.title3.weight(.bold))
                    Text("Compete, train together and settle it with data.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                NavigationLink {
                    ChallengeHubView()
                } label: {
                    Text("View All")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.accent)
                }

                Button {
                    showingCreate = true
                } label: {
                    Image(systemName: "plus")
                        .font(.caption.bold())
                        .frame(width: 32, height: 32)
                        .background(ATHLTHTheme.accent.opacity(0.10), in: Circle())
                }
                .buttonStyle(.plain)
            }

            if highlighted.isEmpty {
                HStack(spacing: 13) {
                    Image(systemName: "person.2.badge.plus")
                        .font(.title2)
                        .foregroundStyle(ATHLTHTheme.accent)
                        .frame(width: 42, height: 42)
                        .background(ATHLTHTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Challenge your friends")
                            .font(.subheadline.weight(.semibold))
                        Text("Running, routes, strength and meet-up sessions.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding(.top, 12)
            } else {
                VStack(spacing: 10) {
                    ForEach(highlighted) { challenge in
                        NavigationLink {
                            ChallengeDetailView(challengeID: challenge.id)
                        } label: {
                            ChallengeCompactRow(challenge: challenge)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 12)
            }
        }
        .sheet(isPresented: $showingCreate) {
            ChallengeCreationView()
        }
    }
}

struct ChallengeCompactRow: View {
    let challenge: ATHLTHChallenge

    var body: some View {
        HStack(spacing: 12) {
            ChallengeCoverArtworkView(
                sport: challenge.sport,
                artworkName: challenge.rules.coverArtworkName,
                remoteURL: challenge.rules.coverImageURL
            )
            .frame(width: 44, height: 44)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 13,
                    style: .continuous
                )
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(challenge.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Text(challenge.rules.scoring.title)
                    Text("·")
                    Text(statusText(challenge.status))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text("\(challenge.participants.count)")
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
                Text("people")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Image(systemName: "chevron.right")
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
        }
        .padding(11)
        .background(
            ATHLTHTheme.accent.opacity(0.035),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }

    private func statusText(_ status: ATHLTHChallengeStatus) -> String {
        switch status {
        case .draft: return "Draft"
        case .invited: return "Invited"
        case .upcoming: return "Upcoming"
        case .active: return "Live"
        case .completed: return "Finished"
        case .cancelled: return "Cancelled"
        }
    }
}

struct ChallengeHubView: View {
    @EnvironmentObject private var challenges: ChallengeStore
    @EnvironmentObject private var officialChallenges: OfficialWeeklyChallengeStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var session: AppSessionStore

    @State private var showingCreate = false

    private var invitations: [ATHLTHChallenge] {
        challenges.incomingInvitations(
            for: session.profile.userID
        )
    }

    private var currentPersonal: [ATHLTHChallenge] {
        challenges.trainingChallenges(
            for: session.profile.userID
        )
    }

    private var finishedPersonal: [ATHLTHChallenge] {
        challenges.visibleChallenges.filter {
            $0.status == .completed ||
            $0.status == .cancelled
        }
    }

    private var officialHistory: [OfficialWeeklyChallenge] {
        officialChallenges.challenges
            .filter { $0.endsAt <= Date() }
            .sorted { $0.endsAt > $1.endsAt }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("ATHLTH Challenges")
                            .font(.largeTitle.bold())

                        Text(
                            "Weekly community goals, friend challenges and routes."
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        showingCreate = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.headline)
                            .frame(width: 44, height: 44)
                            .background(
                                ATHLTHTheme.accent.opacity(0.12),
                                in: Circle()
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Create challenge")
                }

                if let weekly = officialChallenges.activeChallenge {
                    sectionTitle("ATHLTH Weekly")

                    OfficialWeeklyChallengeCard(
                        challenge: weekly,
                        profiles:
                            social.visibleProfiles +
                            social.mutualFollows
                    )
                }

                if !officialChallenges.upcomingChallenges.isEmpty {
                    sectionTitle("Coming Up")

                    VStack(spacing: 10) {
                        ForEach(
                            officialChallenges.upcomingChallenges.prefix(4)
                        ) { challenge in
                            NavigationLink {
                                OfficialWeeklyChallengeDetailView(
                                    challengeID: challenge.id
                                )
                            } label: {
                                officialRow(
                                    challenge,
                                    status: "Upcoming"
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !invitations.isEmpty {
                    sectionTitle("Invitations")

                    ForEach(invitations) { challenge in
                        NavigationLink {
                            ChallengeDetailView(
                                challengeID: challenge.id
                            )
                        } label: {
                            ChallengeHeroCard(
                                challenge: challenge
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !currentPersonal.isEmpty {
                    sectionTitle("Your Challenges")

                    ForEach(currentPersonal) { challenge in
                        NavigationLink {
                            ChallengeDetailView(
                                challengeID: challenge.id
                            )
                        } label: {
                            ChallengeHeroCard(
                                challenge: challenge
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !officialHistory.isEmpty ||
                    !finishedPersonal.isEmpty {
                    sectionTitle("History")

                    VStack(spacing: 10) {
                        ForEach(officialHistory.prefix(8)) {
                            challenge in
                            NavigationLink {
                                OfficialWeeklyChallengeDetailView(
                                    challengeID: challenge.id
                                )
                            } label: {
                                officialRow(
                                    challenge,
                                    status:
                                        officialChallenges.isCompleted(
                                            challenge.id
                                        )
                                        ? "Completed"
                                        : "Finished"
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        ForEach(finishedPersonal) { challenge in
                            NavigationLink {
                                ChallengeDetailView(
                                    challengeID: challenge.id
                                )
                            } label: {
                                ChallengeCompactRow(
                                    challenge: challenge
                                )
                                .padding()
                                .background(
                                    Color(
                                        .secondarySystemGroupedBackground
                                    ),
                                    in: RoundedRectangle(
                                        cornerRadius: 20
                                    )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if officialChallenges.challenges.isEmpty &&
                    challenges.visibleChallenges.isEmpty {
                    ContentUnavailableView(
                        "No challenges yet",
                        systemImage: "figure.run.circle",
                        description: Text(
                            "The next ATHLTH Weekly challenge will appear here. You can also create a challenge with friends."
                        )
                    )
                    .padding(.vertical, 50)
                }
            }
            .padding()
        }
        .background(
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
        )
        .navigationTitle("Challenges")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            challenges.refreshStatuses()
            await officialChallenges.refresh()
            await officialChallenges.syncCompletionState(
                workouts: health.workouts
            )
        }
        .task(id: health.workouts.map(\.id)) {
            await officialChallenges.syncCompletionState(
                workouts: health.workouts
            )
        }
        .sheet(isPresented: $showingCreate) {
            ChallengeCreationView()
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption2.bold())
            .tracking(1.3)
            .foregroundStyle(.secondary)
    }

    private func officialRow(
        _ challenge: OfficialWeeklyChallenge,
        status: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: challenge.kind.icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 42, height: 42)
                .background(
                    Color.orange.opacity(0.09),
                    in: RoundedRectangle(
                        cornerRadius: 12,
                        style: .continuous
                    )
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(challenge.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(
                    challenge.kind.targetText(
                        challenge.targetValue
                    )
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(status)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(
                        status == "Completed"
                            ? Color.green
                            : Color.orange
                    )

                Text(
                    challenge.startsAt.formatted(
                        .dateTime.month(.abbreviated).day()
                    )
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Image(systemName: "chevron.right")
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
        )
    }
}

struct ChallengeHeroCard: View {
    let challenge: ATHLTHChallenge

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ChallengeCoverArtworkView(
                sport: challenge.sport,
                artworkName: challenge.rules.coverArtworkName,
                remoteURL: challenge.rules.coverImageURL
            )

            LinearGradient(
                colors: [.clear, .clear, .black.opacity(0.46)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(
                        challenge.status == .active
                            ? "LIVE"
                            : challenge.status.rawValue.uppercased(),
                        systemImage:
                            challenge.status == .active
                                ? "dot.radiowaves.left.and.right"
                                : "calendar"
                    )
                    .font(.caption2.bold())
                    .tracking(1)

                    Spacer()

                    if challenge.rulesAreLocked {
                        Label("RULES LOCKED", systemImage: "lock.fill")
                            .font(.caption2.bold())
                    }
                }

                Spacer()

                Text(challenge.title)
                    .font(.title2.bold())
                    .lineLimit(2)

                if let summary = challenge.rules.summary,
                   !summary.isEmpty {
                    Text(summary)
                        .font(.caption)
                        .lineLimit(2)
                        .foregroundStyle(.white.opacity(0.86))
                }

                HStack {
                    Label(
                        challenge.rules.scoring.title,
                        systemImage: challenge.sport.systemImage
                    )
                    Spacer()
                    Label(
                        "\(challenge.participants.count)",
                        systemImage: "person.2.fill"
                    )
                }
                .font(.caption)
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.24), radius: 5, y: 2)
            .padding(18)
        }
        .frame(height: 205)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

struct ChallengeCoverArtworkView: View {
    let sport: ATHLTHChallengeSport
    let artworkName: String?
    let remoteURL: String?

    var body: some View {
        GeometryReader { proxy in
            Group {
                if let remoteURL,
                   let url = URL(string: remoteURL) {
                    ATHLTHStorageImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            coverImage(image, size: proxy.size)
                        case .empty:
                            ZStack {
                                fallback
                                ProgressView().tint(.white)
                            }
                        case .failure:
                            fallback
                        @unknown default:
                            fallback
                        }
                    }
                } else if let artworkName,
                          UIImage(named: artworkName) != nil {
                    coverImage(Image(artworkName), size: proxy.size)
                } else {
                    fallback
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .clipped()
    }

    private func coverImage(
        _ image: Image,
        size: CGSize
    ) -> some View {
        image
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .scaledToFill()
            .frame(width: size.width, height: size.height)
            .clipped()
    }

    private var fallback: some View {
        LinearGradient(
            colors: {
                switch sport {
                case .running:
                    return [
                        Color(red: 0.20, green: 0.26, blue: 0.36),
                        Color(red: 0.34, green: 0.43, blue: 0.57)
                    ]
                case .strength:
                    return [
                        Color(red: 0.26, green: 0.27, blue: 0.31),
                        Color(red: 0.43, green: 0.37, blue: 0.31)
                    ]
                case .heartRate:
                    return [
                        Color(red: 0.28, green: 0.31, blue: 0.40),
                        Color(red: 0.42, green: 0.30, blue: 0.38)
                    ]
                }
            }(),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct ChallengeCreationView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var challenges: ChallengeStore
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var messaging: MessagingStore

    let preselectedFriends: [SocialProfileCard]
    let preselectedRouteID: UUID?

    init(
        preselectedFriends: [SocialProfileCard] = [],
        preselectedRouteID: UUID? = nil
    ) {
        self.preselectedFriends = preselectedFriends
        self.preselectedRouteID = preselectedRouteID

        _selectedRouteID = State(initialValue: preselectedRouteID)

        if preselectedRouteID != nil {
            _step = State(initialValue: 0)
            _sport = State(initialValue: .running)
            _scoring = State(initialValue: .fastestDistance)
            _usesSpecificRoute = State(initialValue: true)
            _gpsRequired = State(initialValue: true)
            _verificationPolicy = State(
                initialValue: .verifiedRequired
            )
        }
    }

    @State private var step = 0
    @State private var sport: ATHLTHChallengeSport = .running
    @State private var scoring: ATHLTHChallengeScoring = .fastestDistance
    @State private var title = ""
    @State private var challengeSummary = ""
    @State private var selectedCoverArtworkName = "GoalRunning"
    @State private var selectedCoverPhoto: PhotosPickerItem?
    @State private var selectedCoverImageData: Data?
    @State private var coverWasManuallySelected = false

    @State private var targetDistanceKm = 5.0
    @State private var targetDurationMinutes = 60.0
    @State private var timeBasis: ChallengeTimeBasis = .elapsed
    @State private var selectedRouteID: UUID?
    @State private var usesSpecificRoute = false
    @State private var gpsRequired = true
    @State private var routeMatchPercent = 90.0
    @State private var distanceTolerancePercent = 2.0
    @State private var startFinishToleranceMeters = 100.0
    @State private var routeDirection:
        ChallengeRouteDirection = .sameDirection
    @State private var attemptPolicy:
        ChallengeAttemptPolicy = .best
    @State private var attemptLimit = 0
    @State private var allowTreadmill = false
    @State private var allowTargetGhost = true
    @State private var advancedRules = false

    @State private var heartRateZone = 5
    @State private var heartRateAggregation:
        ChallengeHeartRateAggregation = .totalChallenge

    @State private var exerciseName = "Bench Press"
    @State private var requiredWeightEnabled = false
    @State private var requiredWeightKg = 80.0
    @State private var verificationPolicy: ChallengeVerificationPolicy = .verifiedPreferredManualAllowed

    @State private var startsAt = Date()
    @State private var hasEnd = true
    @State private var endsAt = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var allowMultipleAttempts = true

    @State private var invitees: [ChallengeParticipant] = []

    @State private var meetupEnabled = false
    @State private var meetupPlaceName = ""
    @State private var meetupAt = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    @State private var meetupCoordinate: CLLocationCoordinate2D?
    @State private var mapPosition: MapCameraPosition = .automatic

    @State private var visibility: ProfileVisibility = .friends
    @State private var shareToCommunity = true
    @State private var creatingChallenge = false
    @State private var createError: String?
    @State private var showingInvitePicker = false

    private var clubForest: Color {
        Color(red: 0.20, green: 0.26, blue: 0.36)
    }

    private var clubEmerald: Color {
        Color(red: 0.34, green: 0.43, blue: 0.57)
    }

    private var clubMint: Color {
        Color(red: 0.91, green: 0.94, blue: 0.98)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ATHLTHPremiumCanvas(
                    accent:
                        clubEmerald.opacity(0.14)
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        creationHero
                        creationChallengeSection
                        creationRulesSection
                        creationParticipantsSection
                        creationCommunitySection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(
                    .interactively
                )
            }
            .navigationTitle(
                preselectedRouteID == nil
                    ? ATHLTHLocalization.choose(
                        english: "Create Challenge",
                        norwegian: "Opprett utfordring"
                    )
                    : ATHLTHLocalization.choose(
                        english: "Challenge Route",
                        norwegian: "Challenge-rute"
                    )
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(
                    placement:
                        .cancellationAction
                ) {
                    Button(
                        ATHLTHLocalization.choose(
                            english: "Cancel",
                            norwegian: "Avbryt"
                        )
                    ) {
                        dismiss()
                    }
                    .foregroundStyle(
                        clubForest
                    )
                }

                ToolbarItem(
                    placement:
                        .confirmationAction
                ) {
                    Button {
                        Task {
                            await createChallenge()
                        }
                    } label: {
                        Text(
                            creatingChallenge
                                ? ATHLTHLocalization.choose(
                                    english: "Creating…",
                                    norwegian: "Oppretter…"
                                )
                                : ATHLTHLocalization.choose(
                                    english: "Create",
                                    norwegian: "Opprett"
                                )
                        )
                        .font(
                            .subheadline
                                .weight(.semibold)
                        )
                    }
                    .disabled(
                        !creationIsValid ||
                        creatingChallenge
                    )
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    Divider()
                        .opacity(0.32)

                    Button {
                        Task {
                            await createChallenge()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if creatingChallenge {
                                ProgressView()
                                    .tint(.white)
                            }

                            Text(
                                creatingChallenge
                                    ? ATHLTHLocalization.choose(
                                        english: "Creating…",
                                        norwegian: "Oppretter…"
                                    )
                                    : ATHLTHLocalization.choose(
                                        english: "Create challenge",
                                        norwegian: "Opprett utfordring"
                                    )
                            )
                            .font(.headline)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(
                            LinearGradient(
                                colors: [
                                    clubForest,
                                    clubEmerald
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            in: Capsule(
                                style: .continuous
                            )
                        )
                        .opacity(
                            creationIsValid &&
                            !creatingChallenge
                                ? 1
                                : 0.34
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(
                        !creationIsValid ||
                        creatingChallenge
                    )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .background(.ultraThinMaterial)
            }
            .task {
                if social.mutualFollows.isEmpty {
                    await social.refresh()
                }

                if invitees.isEmpty &&
                    !preselectedFriends.isEmpty {
                    let mutualIDs =
                        Set(
                            social.mutualFollows
                                .map(\.userID)
                        )
                    let eligibleFriends =
                        preselectedFriends.filter {
                            mutualIDs.contains(
                                $0.userID
                            )
                        }

                    invitees =
                        eligibleFriends.map(
                            challengeParticipant
                        )

                    if eligibleFriends.count !=
                        preselectedFriends.count {
                        createError =
                            ATHLTHLocalization.choose(
                                english:
                                    "Follow each other before sending a challenge.",
                                norwegian:
                                    "Dere må følge hverandre før du kan sende en utfordring."
                            )
                    }
                }
            }
            .onChange(of: sport) { _, newSport in
                if !coverWasManuallySelected &&
                    selectedCoverImageData == nil {
                    selectedCoverArtworkName =
                        defaultCoverArtwork(
                            for: newSport
                        )
                }

                switch newSport {
                case .running:
                    scoring =
                        .fastestDistance
                    verificationPolicy =
                        .verifiedRequired

                case .strength:
                    scoring =
                        .heaviestWeight
                    usesSpecificRoute =
                        false
                    selectedRouteID = nil
                    verificationPolicy =
                        .verifiedPreferredManualAllowed

                case .heartRate:
                    scoring =
                        .heartRateZoneTime
                    usesSpecificRoute =
                        false
                    selectedRouteID = nil
                    gpsRequired = false
                    verificationPolicy =
                        .verifiedRequired
                    allowMultipleAttempts =
                        true
                }
            }
            .onChange(
                of: selectedCoverPhoto
            ) { _, item in
                guard let item else {
                    return
                }

                Task {
                    guard let data =
                            try? await item
                                .loadTransferable(
                                    type: Data.self
                                ),
                          let image =
                            UIImage(data: data),
                          let jpeg =
                            image.jpegData(
                                compressionQuality:
                                    0.86
                            )
                    else {
                        await MainActor.run {
                            createError =
                                ATHLTHLocalization.choose(
                                    english:
                                        "The selected image could not be read.",
                                    norwegian:
                                        "Det valgte bildet kunne ikke leses."
                                )
                        }
                        return
                    }

                    await MainActor.run {
                        selectedCoverImageData =
                            jpeg
                        coverWasManuallySelected =
                            true
                    }
                }
            }
            .sensoryFeedback(
                .selection,
                trigger: sport
            )
            .sensoryFeedback(
                .selection,
                trigger: scoring
            )
            .onChange(
                of: scoring
            ) { _, newScoring in
                guard sport == .running
                else {
                    return
                }

                verificationPolicy =
                    .verifiedRequired

                if newScoring !=
                    .fastestDistance {
                    usesSpecificRoute =
                        false
                    selectedRouteID = nil
                }
            }
            .onChange(
                of: usesSpecificRoute
            ) { _, enabled in
                if enabled {
                    gpsRequired = true
                    allowTreadmill =
                        false
                    allowTargetGhost =
                        true
                } else {
                    selectedRouteID =
                        nil
                }
            }
            .onChange(
                of: gpsRequired
            ) { _, required in
                if required {
                    allowTreadmill =
                        false
                }
            }
            .onChange(
                of: heartRateAggregation
            ) { _, aggregation in
                if aggregation ==
                    .totalChallenge {
                    allowMultipleAttempts =
                        true
                }
            }
            .onChange(
                of: selectedRouteID
            ) { _, routeID in
                guard
                    let routeID,
                    let route =
                        session.savedRoutes
                            .first(
                                where: {
                                    $0.id ==
                                        routeID
                                }
                            ),
                    let first =
                        route.coordinates
                            .first
                else {
                    return
                }

                meetupCoordinate =
                    CLLocationCoordinate2D(
                        latitude:
                            first.latitude,
                        longitude:
                            first.longitude
                    )
                mapPosition = .region(
                    MKCoordinateRegion(
                        center:
                            meetupCoordinate!,
                        span:
                            MKCoordinateSpan(
                                latitudeDelta:
                                    0.02,
                                longitudeDelta:
                                    0.02
                            )
                    )
                )
            }
            .sheet(
                isPresented:
                    $showingInvitePicker
            ) {
                creationInvitePicker
            }
            .alert(
                ATHLTHLocalization.choose(
                    english:
                        "Could not complete challenge",
                    norwegian:
                        "Kunne ikke fullføre utfordringen"
                ),
                isPresented: Binding(
                    get: {
                        createError != nil
                    },
                    set: { shown in
                        if !shown {
                            createError = nil
                        }
                    }
                )
            ) {
                Button(
                    "OK",
                    role: .cancel
                ) {
                    createError = nil
                }
            } message: {
                Text(createError ?? "")
            }
        }
    }

    private var creationHero: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let data =
                        selectedCoverImageData,
                   let image =
                        UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    ChallengeCoverArtworkView(
                        sport: sport,
                        artworkName:
                            selectedCoverArtworkName,
                        remoteURL: nil
                    )
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 160)
            .clipped()

            LinearGradient(
                colors: [
                    .clear,
                    .clear,
                    .black.opacity(0.34)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            Label(
                creationHeroLabel,
                systemImage:
                    sport.systemImage
            )
            .font(
                .caption.weight(.semibold)
            )
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                .ultraThinMaterial,
                in: Capsule()
            )
            .padding(14)
        }
        .frame(height: 160)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
            .stroke(
                Color.white.opacity(0.32),
                lineWidth: 0.8
            )
        }
        .overlay(
            alignment: .topTrailing
        ) {
            HStack(spacing: 8) {
                Menu {
                    ForEach(
                        challengeCoverArtworkOptions,
                        id: \.self
                    ) { artwork in
                        Button {
                            selectedCoverArtworkName =
                                artwork
                            selectedCoverImageData =
                                nil
                            selectedCoverPhoto =
                                nil
                            coverWasManuallySelected =
                                true
                        } label: {
                            Label(
                                artwork
                                    .replacingOccurrences(
                                        of: "Goal",
                                        with: ""
                                    ),
                                systemImage:
                                    selectedCoverArtworkName ==
                                        artwork &&
                                    selectedCoverImageData ==
                                        nil
                                        ? "checkmark.circle.fill"
                                        : "photo"
                            )
                        }
                    }
                } label: {
                    Image(
                        systemName:
                            "photo.stack.fill"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .frame(
                        width: 36,
                        height: 36
                    )
                    .background(
                        .ultraThinMaterial,
                        in: Circle()
                    )
                }

                PhotosPicker(
                    selection:
                        $selectedCoverPhoto,
                    matching: .images
                ) {
                    Image(
                        systemName:
                            "photo.badge.plus"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .frame(
                        width: 36,
                        height: 36
                    )
                    .background(
                        .ultraThinMaterial,
                        in: Circle()
                    )
                }
            }
            .padding(12)
        }
        .shadow(
            color:
                Color.black.opacity(0.06),
            radius: 12,
            y: 5
        )
    }

    private var creationHeroLabel: String {
        switch sport {
        case .running:
            return ATHLTHLocalization.choose(
                english: "Running challenge",
                norwegian: "Løpechallenge"
            )
        case .strength:
            return ATHLTHLocalization.choose(
                english: "Strength challenge",
                norwegian: "Styrkechallenge"
            )
        case .heartRate:
            return ATHLTHLocalization.choose(
                english: "Heart-rate challenge",
                norwegian: "Pulschallenge"
            )
        }
    }

    private var creationChallengeSection:
        some View {
        creationSection(
            title:
                ATHLTHLocalization.choose(
                    english: "Challenge",
                    norwegian: "Utfordring"
                ),
            icon: "trophy.fill"
        ) {
            creationTextField(
                title:
                    ATHLTHLocalization.choose(
                        english: "Challenge name",
                        norwegian: "Navn på utfordring"
                    ),
                placeholder:
                    ATHLTHLocalization.choose(
                        english:
                            "Optional name",
                        norwegian:
                            "Valgfritt navn"
                    ),
                text: Binding(
                    get: { title },
                    set: {
                        title =
                            String(
                                $0.prefix(60)
                            )
                    }
                ),
                icon: "textformat"
            )

            if title
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )
                .isEmpty {
                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "If left empty, ATHLTH uses “\(automaticTitle)”.",
                        norwegian:
                            "Står feltet tomt, brukes «\(automaticTitle)»."
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 50)
            }

            creationDivider

            creationTextField(
                title:
                    ATHLTHLocalization.choose(
                        english: "Description",
                        norwegian: "Beskrivelse"
                    ),
                placeholder:
                    ATHLTHLocalization.choose(
                        english: "Optional",
                        norwegian: "Valgfritt"
                    ),
                text: Binding(
                    get: {
                        challengeSummary
                    },
                    set: {
                        challengeSummary =
                            String(
                                $0.prefix(160)
                            )
                    }
                ),
                icon: "text.alignleft",
                axis: .vertical
            )

            creationDivider

            Menu {
                ForEach(
                    ATHLTHChallengeSport
                        .allCases
                ) { option in
                    Button {
                        sport = option
                    } label: {
                        Label(
                            option.title,
                            systemImage:
                                option.systemImage
                        )
                    }
                }
            } label: {
                creationSelectionRow(
                    title:
                        ATHLTHLocalization.choose(
                            english: "Activity",
                            norwegian: "Aktivitet"
                        ),
                    value: sport.title,
                    icon: sport.systemImage
                )
            }
            .buttonStyle(.plain)

            creationDivider

            Menu {
                ForEach(
                    scoringOptions
                ) { option in
                    Button {
                        scoring = option
                    } label: {
                        Label(
                            option.title,
                            systemImage:
                                scoringIcon(
                                    option
                                )
                        )
                    }
                }
            } label: {
                creationSelectionRow(
                    title:
                        ATHLTHLocalization.choose(
                            english: "Scoring",
                            norwegian: "Poengberegning"
                        ),
                    value:
                        effectiveScoring.title,
                    icon:
                        scoringIcon(
                            effectiveScoring
                        ),
                    subtitle:
                        scoringSubtitle(
                            effectiveScoring
                        )
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var creationRulesSection:
        some View {
        creationSection(
            title:
                ATHLTHLocalization.choose(
                    english: "Rules",
                    norwegian: "Regler"
                ),
            icon: "gearshape.fill"
        ) {
            switch sport {
            case .running:
                creationRunningRules
            case .strength:
                creationStrengthRules
            case .heartRate:
                creationHeartRateRules
            }

            creationDivider

            VStack(
                alignment: .leading,
                spacing: 8
            ) {
                Text(
                    ATHLTHLocalization.choose(
                        english: "Period",
                        norwegian: "Periode"
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    creationDateControl(
                        title:
                            ATHLTHLocalization.choose(
                                english: "Starts",
                                norwegian: "Starter"
                            ),
                        selection: $startsAt,
                        range:
                            Date()...Date.distantFuture
                    )

                    if hasEnd {
                        creationDateControl(
                            title:
                                ATHLTHLocalization.choose(
                                    english: "Ends",
                                    norwegian: "Slutter"
                                ),
                            selection: $endsAt,
                            range:
                                startsAt...Date.distantFuture
                        )
                    }
                }

                Toggle(
                    ATHLTHLocalization.choose(
                        english: "Set an end date",
                        norwegian: "Sett sluttdato"
                    ),
                    isOn: $hasEnd
                )
                .font(.subheadline)
                .tint(clubForest)
            }

            creationDivider

            DisclosureGroup(
                isExpanded:
                    $advancedRules
            ) {
                creationAdvancedRules
                    .padding(.top, 12)
            } label: {
                Label(
                    ATHLTHLocalization.choose(
                        english: "Advanced rules",
                        norwegian: "Avanserte regler"
                    ),
                    systemImage:
                        "slider.horizontal.3"
                )
                .font(
                    .subheadline
                        .weight(.semibold)
                )
                .foregroundStyle(
                    clubForest
                )
            }

            creationDivider

            DisclosureGroup(
                isExpanded:
                    $meetupEnabled
            ) {
                VStack(
                    alignment: .leading,
                    spacing: 12
                ) {
                    creationTextField(
                        title:
                            ATHLTHLocalization.choose(
                                english: "Meetup name",
                                norwegian: "Møtested"
                            ),
                        placeholder:
                            ATHLTHLocalization.choose(
                                english: "Optional",
                                norwegian: "Valgfritt"
                            ),
                        text:
                            $meetupPlaceName,
                        icon:
                            "mappin.and.ellipse"
                    )

                    DatePicker(
                        ATHLTHLocalization.choose(
                            english: "Meet at",
                            norwegian: "Møtetid"
                        ),
                        selection:
                            $meetupAt,
                        in: Date()...,
                        displayedComponents: [
                            .date,
                            .hourAndMinute
                        ]
                    )
                    .datePickerStyle(.compact)

                    MeetupLocationPicker(
                        coordinate:
                            $meetupCoordinate,
                        position:
                            $mapPosition
                    )

                    if selectedRouteID !=
                        nil {
                        Button {
                            guard
                                let routeID =
                                    selectedRouteID,
                                let route =
                                    session
                                        .savedRoutes
                                        .first(
                                            where: {
                                                $0.id ==
                                                    routeID
                                            }
                                        ),
                                let first =
                                    route
                                        .coordinates
                                        .first
                            else {
                                return
                            }

                            let coordinate =
                                CLLocationCoordinate2D(
                                    latitude:
                                        first.latitude,
                                    longitude:
                                        first.longitude
                                )

                            meetupCoordinate =
                                coordinate
                            mapPosition =
                                .region(
                                    MKCoordinateRegion(
                                        center:
                                            coordinate,
                                        span:
                                            MKCoordinateSpan(
                                                latitudeDelta:
                                                    0.015,
                                                longitudeDelta:
                                                    0.015
                                            )
                                    )
                                )
                        } label: {
                            Label(
                                ATHLTHLocalization.choose(
                                    english:
                                        "Use route start",
                                    norwegian:
                                        "Bruk rutestart"
                                ),
                                systemImage:
                                    "location.fill"
                            )
                        }
                        .buttonStyle(.bordered)
                    }

                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Check-in is explicit. ATHLTH does not continuously share participants’ live location.",
                            norwegian:
                                "Innsjekking er aktiv. ATHLTH deler ikke deltakernes posisjon kontinuerlig."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(
                        .secondary
                    )
                }
                .padding(.top, 12)
            } label: {
                Label(
                    ATHLTHLocalization.choose(
                        english: "Meet and train together",
                        norwegian: "Møtes og trene sammen"
                    ),
                    systemImage:
                        "person.2.wave.2"
                )
                .font(
                    .subheadline
                        .weight(.semibold)
                )
                .foregroundStyle(
                    clubForest
                )
            }
        }
    }

    @ViewBuilder
    private var creationRunningRules:
        some View {
        if scoring ==
            .fastestDistance {
            Menu {
                Button {
                    usesSpecificRoute =
                        false
                } label: {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Run anywhere",
                            norwegian: "Løp hvor som helst"
                        ),
                        systemImage:
                            "figure.run"
                    )
                }

                Button {
                    usesSpecificRoute =
                        true
                } label: {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Specific route",
                            norwegian: "Bestemt rute"
                        ),
                        systemImage:
                            "point.topleft.down.to.point.bottomright.curvepath"
                    )
                }
            } label: {
                creationSelectionRow(
                    title:
                        ATHLTHLocalization.choose(
                            english: "Course",
                            norwegian: "Løype"
                        ),
                    value:
                        usesSpecificRoute
                            ? ATHLTHLocalization.choose(
                                english: "Specific route",
                                norwegian: "Bestemt rute"
                            )
                            : ATHLTHLocalization.choose(
                                english: "Run anywhere",
                                norwegian: "Løp hvor som helst"
                            ),
                    icon:
                        "point.topleft.down.to.point.bottomright.curvepath"
                )
            }
            .buttonStyle(.plain)

            creationDivider

            if usesSpecificRoute {
                creationRoutePicker
            } else {
                creationNumberRow(
                    title:
                        ATHLTHLocalization.choose(
                            english: "Distance",
                            norwegian: "Distanse"
                        ),
                    value:
                        $targetDistanceKm,
                    suffix: "km",
                    icon: "mappin"
                )
            }
        }

        if scoring ==
            .farthestInTime {
            creationNumberRow(
                title:
                    ATHLTHLocalization.choose(
                        english: "Time window",
                        norwegian: "Tidsvindu"
                    ),
                value:
                    $targetDurationMinutes,
                suffix:
                    ATHLTHLocalization.choose(
                        english: "min",
                        norwegian: "min"
                    ),
                icon: "clock.fill"
            )
        }

        if scoring !=
            .fastestDistance ||
            !usesSpecificRoute {
            creationDivider

            HStack(spacing: 12) {
                Image(
                    systemName:
                        "location.fill"
                )
                .foregroundStyle(
                    clubEmerald
                )
                .frame(
                    width: 38,
                    height: 38
                )
                .background(
                    clubMint,
                    in: RoundedRectangle(
                        cornerRadius: 12,
                        style:
                            .continuous
                    )
                )

                VStack(
                    alignment: .leading,
                    spacing: 2
                ) {
                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "GPS verification",
                            norwegian:
                                "GPS-verifisering"
                        )
                    )
                    .font(
                        .subheadline
                            .weight(.semibold)
                    )

                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Running results must come from ATHLTH or a qualifying Apple Health workout.",
                            norwegian:
                                "Løperesultater må komme fra ATHLTH eller en godkjent Apple Health-økt."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(
                        .secondary
                    )
                }

                Spacer()

                Toggle(
                    "",
                    isOn: $gpsRequired
                )
                .labelsHidden()
                .tint(clubForest)
            }
        } else {
            creationDivider

            creationSelectionRow(
                title:
                    ATHLTHLocalization.choose(
                        english: "Verification",
                        norwegian: "Verifisering"
                    ),
                value:
                    ATHLTHLocalization.choose(
                        english:
                            "GPS / verified run",
                        norwegian:
                            "GPS / registrert løp"
                    ),
                icon:
                    "checkmark.shield.fill",
                subtitle:
                    ATHLTHLocalization.choose(
                        english:
                            "Specific-route attempts always require GPS.",
                        norwegian:
                            "Forsøk på bestemt rute krever alltid GPS."
                    )
            )
        }
    }

    @ViewBuilder
    private var creationStrengthRules:
        some View {
        if scoring != .workoutVolume {
            creationTextField(
                title:
                    ATHLTHLocalization.choose(
                        english: "Exercise",
                        norwegian: "Øvelse"
                    ),
                placeholder:
                    ATHLTHLocalization.choose(
                        english: "Exercise",
                        norwegian: "Øvelse"
                    ),
                text: $exerciseName,
                icon: "dumbbell.fill"
            )

            creationDivider
        }

        if scoring == .mostReps {
            HStack {
                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "Require a specific weight",
                        norwegian:
                            "Krev en bestemt vekt"
                    )
                )
                .font(.subheadline)
                Spacer()
                Toggle(
                    "",
                    isOn:
                        $requiredWeightEnabled
                )
                .labelsHidden()
                .tint(clubForest)
            }

            if requiredWeightEnabled {
                creationDivider

                creationNumberRow(
                    title:
                        ATHLTHLocalization.choose(
                            english:
                                "Required weight",
                            norwegian:
                                "Påkrevd vekt"
                        ),
                    value:
                        $requiredWeightKg,
                    suffix: "kg",
                    icon:
                        "scalemass.fill"
                )
            }

            creationDivider
        }

        Menu {
            ForEach(
                ChallengeVerificationPolicy
                    .allCases
            ) { policy in
                Button {
                    verificationPolicy =
                        policy
                } label: {
                    Text(policy.title)
                }
            }
        } label: {
            creationSelectionRow(
                title:
                    ATHLTHLocalization.choose(
                        english: "Verification",
                        norwegian: "Verifisering"
                    ),
                value:
                    verificationPolicy.title,
                icon:
                    "checkmark.shield.fill",
                subtitle:
                    verificationPolicy
                        .subtitle
            )
        }
        .buttonStyle(.plain)
    }

    private var creationHeartRateRules:
        some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            Text(
                ATHLTHLocalization.choose(
                    english: "Heart-rate zone",
                    norwegian: "Pulssone"
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(spacing: 7) {
                ForEach(
                    1...5,
                    id: \.self
                ) { zone in
                    Button {
                        heartRateZone = zone
                    } label: {
                        VStack(spacing: 3) {
                            Text("Z\(zone)")
                                .font(
                                    .subheadline
                                        .weight(.bold)
                                )
                            Text(
                                heartRateZonePercentText(
                                    zone
                                )
                            )
                            .font(
                                .system(
                                    size: 9,
                                    weight: .medium
                                )
                            )
                        }
                        .foregroundStyle(
                            heartRateZone ==
                                zone
                                ? Color.white
                                : clubForest
                        )
                        .frame(
                            maxWidth:
                                .infinity,
                            minHeight: 54
                        )
                        .background(
                            heartRateZone ==
                                zone
                                ? clubForest
                                : clubMint,
                            in:
                                RoundedRectangle(
                                    cornerRadius:
                                        14,
                                    style:
                                        .continuous
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            if let maximumHeartRateBPM {
                Text(
                    ATHLTHLocalization.format(
                        english:
                            "Zone %d · %@",
                        norwegian:
                            "Sone %d · %@",
                        heartRateZone,
                        heartRateZoneBPMText(
                            zone:
                                heartRateZone,
                            maxHR:
                                maximumHeartRateBPM
                        )
                    )
                )
                .font(
                    .caption
                        .weight(.semibold)
                )
                .foregroundStyle(
                    .secondary
                )
            } else {
                NavigationLink {
                    PersonalHealthProfileView()
                } label: {
                    Label(
                        ATHLTHLocalization.choose(
                            english:
                                "Set maximum heart rate",
                            norwegian:
                                "Sett makspuls"
                        ),
                        systemImage:
                            "heart.text.square"
                    )
                    .frame(
                        maxWidth: .infinity
                    )
                }
                .buttonStyle(
                    .borderedProminent
                )
                .tint(clubForest)
            }

            creationDivider

            Picker(
                ATHLTHLocalization.choose(
                    english: "Leaderboard",
                    norwegian: "Toppliste"
                ),
                selection:
                    $heartRateAggregation
            ) {
                ForEach(
                    ChallengeHeartRateAggregation
                        .allCases
                ) { aggregation in
                    Text(
                        aggregation.title
                    )
                    .tag(aggregation)
                }
            }
            .pickerStyle(.segmented)

            Text(
                heartRateAggregation
                    .subtitle
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var creationAdvancedRules:
        some View {
        switch sport {
        case .running:
            VStack(
                alignment: .leading,
                spacing: 14
            ) {
                if scoring ==
                    .fastestDistance {
                    Text(
                        ATHLTHLocalization.choose(
                            english: "Timing",
                            norwegian: "Tidtaking"
                        )
                    )
                    .font(
                        .subheadline
                            .weight(.semibold)
                    )

                    Picker(
                        "Timing",
                        selection:
                            $timeBasis
                    ) {
                        ForEach(
                            ChallengeTimeBasis
                                .allCases
                        ) { basis in
                            Text(basis.title)
                                .tag(basis)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if scoring ==
                    .fastestDistance &&
                    !usesSpecificRoute {
                    VStack(
                        alignment: .leading,
                        spacing: 7
                    ) {
                        HStack {
                            Text(
                                ATHLTHLocalization.choose(
                                    english:
                                        "Distance tolerance",
                                    norwegian:
                                        "Distanseavvik"
                                )
                            )
                            Spacer()
                            Text(
                                "±\(distanceTolerancePercent.formatted(.number.precision(.fractionLength(0...1))))%"
                            )
                            .monospacedDigit()
                        }
                        .font(
                            .subheadline
                        )

                        Slider(
                            value:
                                $distanceTolerancePercent,
                            in: 0.5...5,
                            step: 0.5
                        )
                    }
                }

                if scoring ==
                    .fastestDistance &&
                    usesSpecificRoute {
                    VStack(
                        alignment: .leading,
                        spacing: 8
                    ) {
                        HStack {
                            Text(
                                ATHLTHLocalization.choose(
                                    english:
                                        "Allowed route deviation",
                                    norwegian:
                                        "Tillatt ruteavvik"
                                )
                            )
                            Spacer()
                            Text(
                                "\(Int(allowedRouteDeviationPercent))%"
                            )
                            .monospacedDigit()
                        }

                        Slider(
                            value:
                                allowedRouteDeviationBinding,
                            in: 2...20,
                            step: 1
                        )

                        HStack {
                            Text(
                                ATHLTHLocalization.choose(
                                    english:
                                        "Start / finish tolerance",
                                    norwegian:
                                        "Start-/måltoleranse"
                                )
                            )
                            Spacer()
                            Text(
                                "\(Int(startFinishToleranceMeters)) m"
                            )
                            .monospacedDigit()
                        }

                        Slider(
                            value:
                                $startFinishToleranceMeters,
                            in: 25...500,
                            step: 25
                        )

                        Picker(
                            ATHLTHLocalization.choose(
                                english:
                                    "Route direction",
                                norwegian:
                                    "Ruteretning"
                            ),
                            selection:
                                $routeDirection
                        ) {
                            ForEach(
                                ChallengeRouteDirection
                                    .allCases
                            ) { direction in
                                Text(
                                    direction.title
                                )
                                .tag(direction)
                            }
                        }
                        .pickerStyle(
                            .segmented
                        )

                        Toggle(
                            ATHLTHLocalization.choose(
                                english:
                                    "Allow target ghost",
                                norwegian:
                                    "Tillat Target Ghost"
                            ),
                            isOn:
                                $allowTargetGhost
                        )
                    }
                }

                if !usesSpecificRoute {
                    Toggle(
                        ATHLTHLocalization.choose(
                            english:
                                "Allow treadmill",
                            norwegian:
                                "Tillat tredemølle"
                        ),
                        isOn:
                            $allowTreadmill
                    )
                    .disabled(gpsRequired)
                }

                creationAttemptControls

                Button {
                    resetRunningAdvancedRules()
                } label: {
                    Label(
                        ATHLTHLocalization.choose(
                            english:
                                "Reset to recommended",
                            norwegian:
                                "Tilbakestill til anbefalt"
                        ),
                        systemImage:
                            "arrow.counterclockwise"
                    )
                    .frame(
                        maxWidth: .infinity
                    )
                }
                .buttonStyle(.bordered)
            }

        case .strength:
            creationAttemptControls

        case .heartRate:
            VStack(
                alignment: .leading,
                spacing: 10
            ) {
                Label(
                    ATHLTHLocalization.choose(
                        english: "Personal zones",
                        norwegian: "Personlige soner"
                    ),
                    systemImage:
                        "person.crop.circle.badge.checkmark"
                )
                .font(
                    .subheadline
                        .weight(.semibold)
                )

                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "Each participant is scored against their own private maximum heart rate.",
                        norwegian:
                            "Hver deltaker måles mot sin egen private makspuls."
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                if heartRateAggregation !=
                    .totalChallenge {
                    creationAttemptControls
                }
            }
        }
    }

    private var creationAttemptControls:
        some View {
        VStack(
            alignment: .leading,
            spacing: 10
        ) {
            Toggle(
                ATHLTHLocalization.choose(
                    english:
                        "Allow multiple attempts",
                    norwegian:
                        "Tillat flere forsøk"
                ),
                isOn:
                    $allowMultipleAttempts
            )

            if allowMultipleAttempts &&
                sport == .running {
                Picker(
                    ATHLTHLocalization.choose(
                        english:
                            "Attempt policy",
                        norwegian:
                            "Hvilket forsøk teller"
                    ),
                    selection:
                        $attemptPolicy
                ) {
                    ForEach(
                        ChallengeAttemptPolicy
                            .allCases
                    ) { policy in
                        Text(
                            policy.title
                        )
                        .tag(policy)
                    }
                }
                .pickerStyle(.segmented)

                Picker(
                    ATHLTHLocalization.choose(
                        english:
                            "Maximum attempts",
                        norwegian:
                            "Maks forsøk"
                    ),
                    selection:
                        $attemptLimit
                ) {
                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Unlimited",
                            norwegian:
                                "Ubegrenset"
                        )
                    )
                    .tag(0)
                    Text("3")
                        .tag(3)
                    Text("5")
                        .tag(5)
                }
            }
        }
    }

    private var creationRoutePicker:
        some View {
        VStack(
            alignment: .leading,
            spacing: 10
        ) {
            if let route =
                    selectedRoute {
                if route.coordinates.count >=
                    2 {
                    Map(
                        initialPosition:
                            .region(
                                challengeRegion(
                                    for: route
                                )
                            )
                    ) {
                        MapPolyline(
                            coordinates:
                                route.coordinates
                                    .map(
                                        \.coordinate
                                    )
                        )
                        .stroke(
                            clubForest,
                            lineWidth: 5
                        )
                    }
                    .allowsHitTesting(false)
                    .frame(height: 130)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 17,
                            style:
                                .continuous
                        )
                    )
                }

                HStack(spacing: 10) {
                    VStack(
                        alignment: .leading,
                        spacing: 2
                    ) {
                        Text(route.title)
                            .font(
                                .subheadline
                                    .weight(
                                        .semibold
                                    )
                            )

                        Text(
                            String(
                                format:
                                    "%.1f km",
                                route
                                    .distanceKilometers
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(
                            .secondary
                        )
                    }

                    Spacer()

                    NavigationLink {
                        ChallengeRouteSelectionView(
                            selectedRouteID:
                                $selectedRouteID
                        )
                    } label: {
                        Text(
                            ATHLTHLocalization.choose(
                                english: "Change",
                                norwegian: "Bytt"
                            )
                        )
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                NavigationLink {
                    ChallengeRouteSelectionView(
                        selectedRouteID:
                            $selectedRouteID
                    )
                } label: {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Choose route",
                            norwegian: "Velg rute"
                        ),
                        systemImage: "map.fill"
                    )
                    .frame(
                        maxWidth: .infinity
                    )
                }
                .buttonStyle(
                    .borderedProminent
                )
                .tint(clubForest)
            }
        }
    }

    private var creationParticipantsSection:
        some View {
        creationSection(
            title:
                ATHLTHLocalization.choose(
                    english: "Participants",
                    norwegian: "Deltakere"
                ),
            icon: "person.2.fill"
        ) {
            Button {
                showingInvitePicker =
                    true
            } label: {
                HStack(spacing: 12) {
                    Image(
                        systemName:
                            "person.badge.plus"
                    )
                    .font(
                        .system(
                            size: 17,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        clubForest
                    )
                    .frame(
                        width: 38,
                        height: 38
                    )
                    .background(
                        clubMint,
                        in: RoundedRectangle(
                            cornerRadius: 12,
                            style:
                                .continuous
                        )
                    )

                    VStack(
                        alignment: .leading,
                        spacing: 2
                    ) {
                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "Invite friends",
                                norwegian:
                                    "Inviter venner"
                            )
                        )
                        .font(
                            .subheadline
                                .weight(.semibold)
                        )
                        .foregroundStyle(
                            .primary
                        )

                        Text(
                            invitees.isEmpty
                                ? (
                                    visibility == .publicProfile
                                        ? ATHLTHLocalization.choose(
                                            english:
                                                "Optional · public users can join",
                                            norwegian:
                                                "Valgfritt · offentlige brukere kan bli med"
                                        )
                                        : ATHLTHLocalization.choose(
                                            english:
                                                "Choose at least one participant",
                                            norwegian:
                                                "Velg minst én deltaker"
                                        )
                                )
                                : (
                                    invitees.count == 1
                                        ? ATHLTHLocalization.choose(
                                            english: "1 invited",
                                            norwegian: "1 invitert"
                                        )
                                        : ATHLTHLocalization.format(
                                            english: "%d invited",
                                            norwegian: "%d invitert",
                                            invitees.count
                                        )
                                )
                        )
                        .font(.caption)
                        .foregroundStyle(
                            .secondary
                        )
                    }

                    Spacer()

                    creationInviteeAvatars

                    Image(
                        systemName:
                            "chevron.right"
                    )
                    .font(.caption.bold())
                    .foregroundStyle(
                        .secondary
                    )
                }
            }
            .buttonStyle(.plain)

            creationDivider

            Menu {
                Button {
                    visibility =
                        .publicProfile
                } label: {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Public",
                            norwegian: "Offentlig"
                        ),
                        systemImage: "globe"
                    )
                }

                Button {
                    visibility =
                        .friends
                } label: {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Followers",
                            norwegian: "Følgere"
                        ),
                        systemImage:
                            "person.2.fill"
                    )
                }

                Button {
                    visibility =
                        .privateOnly
                } label: {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Private",
                            norwegian: "Privat"
                        ),
                        systemImage:
                            "lock.fill"
                    )
                }
            } label: {
                creationSelectionRow(
                    title:
                        ATHLTHLocalization.choose(
                            english:
                                "Who can see it",
                            norwegian:
                                "Hvem kan se det"
                        ),
                    value:
                        creationVisibilityTitle,
                    icon:
                        creationVisibilityIcon,
                    subtitle:
                        creationVisibilitySubtitle
                )
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var creationInviteeAvatars:
        some View {
        if invitees.isEmpty {
            Circle()
                .fill(
                    clubMint
                )
                .frame(
                    width: 34,
                    height: 34
                )
                .overlay {
                    Image(
                        systemName: "plus"
                    )
                    .font(.caption.bold())
                    .foregroundStyle(
                        clubForest
                    )
                }
        } else {
            HStack(spacing: -9) {
                ForEach(
                    Array(
                        invitees.prefix(3)
                    )
                ) { participant in
                    if let profile =
                        social.mutualFollows
                            .first(
                                where: {
                                    $0.userID ==
                                        participant
                                            .userID
                                }
                            ) {
                        SocialAvatar(
                            profile: profile,
                            size: 34
                        )
                        .overlay {
                            Circle()
                                .stroke(
                                    Color.white,
                                    lineWidth: 2
                                )
                        }
                    } else {
                        Circle()
                            .fill(
                                clubMint
                            )
                            .frame(
                                width: 34,
                                height: 34
                            )
                            .overlay {
                                Text(
                                    participant
                                        .displayName
                                        .prefix(1)
                                        .uppercased()
                                )
                                .font(
                                    .caption
                                        .bold()
                                )
                                .foregroundStyle(
                                    clubForest
                                )
                            }
                            .overlay {
                                Circle()
                                    .stroke(
                                        Color.white,
                                        lineWidth: 2
                                    )
                            }
                    }
                }

                if invitees.count > 3 {
                    Circle()
                        .fill(
                            clubForest
                        )
                        .frame(
                            width: 34,
                            height: 34
                        )
                        .overlay {
                            Text(
                                "+\(invitees.count - 3)"
                            )
                            .font(
                                .caption2
                                    .bold()
                            )
                            .foregroundStyle(
                                .white
                            )
                        }
                        .overlay {
                            Circle()
                                .stroke(
                                    Color.white,
                                    lineWidth: 2
                                )
                        }
                }
            }
        }
    }

    private var creationCommunitySection:
        some View {
        creationSection(
            title:
                ATHLTHLocalization.choose(
                    english: "Community",
                    norwegian: "Fellesskap"
                ),
            icon: "person.3.fill"
        ) {
            HStack(spacing: 12) {
                Image(
                    systemName:
                        "megaphone.fill"
                )
                .font(
                    .system(
                        size: 17,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    clubForest
                )
                .frame(
                    width: 38,
                    height: 38
                )
                .background(
                    clubMint,
                    in: RoundedRectangle(
                        cornerRadius: 12,
                        style:
                            .continuous
                    )
                )

                VStack(
                    alignment: .leading,
                    spacing: 3
                ) {
                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Share to Community activity",
                            norwegian:
                                "Del til Community-aktivitet"
                        )
                    )
                    .font(
                        .subheadline
                            .weight(.semibold)
                    )

                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "People who can see the challenge can also discover it in Community.",
                            norwegian:
                                "Utfordringen kan vises i Community for dem som har tilgang."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(
                        .secondary
                    )
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )
                }

                Spacer(
                    minLength: 8
                )

                Toggle(
                    "",
                    isOn:
                        $shareToCommunity
                )
                .labelsHidden()
                .tint(clubForest)
            }
        }
    }

    private var creationVisibilityTitle:
        String {
        switch visibility {
        case .publicProfile:
            return ATHLTHLocalization.choose(
                english: "Public",
                norwegian: "Offentlig"
            )
        case .friends:
            return ATHLTHLocalization.choose(
                english: "Followers",
                norwegian: "Følgere"
            )
        case .privateOnly:
            return ATHLTHLocalization.choose(
                english: "Private",
                norwegian: "Privat"
            )
        }
    }

    private var creationVisibilityIcon:
        String {
        switch visibility {
        case .publicProfile:
            return "globe"
        case .friends:
            return "person.2.fill"
        case .privateOnly:
            return "lock.fill"
        }
    }

    private var creationVisibilitySubtitle:
        String {
        switch visibility {
        case .publicProfile:
            return ATHLTHLocalization.choose(
                english:
                    "Signed-in ATHLTH users can discover the challenge.",
                norwegian:
                    "Innloggede ATHLTH-brukere kan oppdage utfordringen."
            )
        case .friends:
            return ATHLTHLocalization.choose(
                english:
                    "Limited to your ATHLTH network.",
                norwegian:
                    "Begrenset til ATHLTH-nettverket ditt."
            )
        case .privateOnly:
            return ATHLTHLocalization.choose(
                english:
                    "Only invited participants can access it.",
                norwegian:
                    "Kun inviterte deltakere får tilgang."
            )
        }
    }

    private var creationIsValid: Bool {
        guard !creatingChallenge else {
            return false
        }

        if ChallengeCreationPolicy
            .requiresDirectInvite(
                visibility: visibility
            ) &&
            invitees.isEmpty {
            return false
        }

        if hasEnd &&
            endsAt <= startsAt {
            return false
        }

        if meetupEnabled &&
            meetupCoordinate == nil {
            return false
        }

        switch sport {
        case .running:
            if scoring ==
                .fastestDistance {
                return usesSpecificRoute
                    ? selectedRouteID != nil
                    : targetDistanceKm > 0
            }

            if scoring ==
                .farthestInTime {
                return targetDurationMinutes >
                    0
            }

            return true

        case .strength:
            if scoring !=
                .workoutVolume &&
                exerciseName
                    .trimmingCharacters(
                        in:
                            .whitespacesAndNewlines
                    )
                    .isEmpty {
                return false
            }

            return true

        case .heartRate:
            return maximumHeartRateBPM !=
                nil &&
                (1...5).contains(
                    heartRateZone
                )
        }
    }

    private var creationInvitePicker:
        some View {
        NavigationStack {
            List {
                if social.mutualFollows
                    .isEmpty {
                    ContentUnavailableView(
                        ATHLTHLocalization.choose(
                            english:
                                "No people available",
                            norwegian:
                                "Ingen å invitere ennå"
                        ),
                        systemImage:
                            "person.2.slash",
                        description: Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "Follow each other before sending a challenge.",
                                norwegian:
                                    "Dere må følge hverandre før du kan sende en challenge."
                            )
                        )
                    )

                    NavigationLink {
                        SocialHubView(
                            initialTab:
                                .discover
                        )
                    } label: {
                        Label(
                            ATHLTHLocalization.choose(
                                english:
                                    "Find people",
                                norwegian:
                                    "Finn personer"
                            ),
                            systemImage:
                                "person.badge.plus"
                        )
                    }
                } else {
                    ForEach(
                        social.mutualFollows
                    ) { friend in
                        Button {
                            toggleFriend(friend)
                        } label: {
                            HStack(
                                spacing: 12
                            ) {
                                SocialAvatar(
                                    profile:
                                        friend,
                                    size: 42
                                )

                                VStack(
                                    alignment:
                                        .leading,
                                    spacing: 2
                                ) {
                                    Text(
                                        friend
                                            .resolvedName
                                    )
                                    .font(
                                        .subheadline
                                            .weight(
                                                .semibold
                                            )
                                    )
                                    .foregroundStyle(
                                        .primary
                                    )

                                    Text(
                                        friend
                                            .usernameLabel
                                    )
                                    .font(.caption)
                                    .foregroundStyle(
                                        .secondary
                                    )
                                }

                                Spacer()

                                Image(
                                    systemName:
                                        invitees
                                            .contains(
                                                where: {
                                                    $0.userID ==
                                                        friend
                                                            .userID
                                                }
                                            )
                                            ? "checkmark.circle.fill"
                                            : "circle"
                                )
                                .font(.title3)
                                .foregroundStyle(
                                    invitees
                                        .contains(
                                            where: {
                                                $0.userID ==
                                                    friend
                                                        .userID
                                            }
                                        )
                                        ? clubForest
                                        : .secondary
                                )
                            }
                            .contentShape(
                                Rectangle()
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle(
                ATHLTHLocalization.choose(
                    english:
                        "Invite friends",
                    norwegian:
                        "Inviter venner"
                )
            )
            .navigationBarTitleDisplayMode(
                .inline
            )
            .toolbar {
                ToolbarItem(
                    placement:
                        .confirmationAction
                ) {
                    Button(
                        ATHLTHLocalization.choose(
                            english: "Done",
                            norwegian: "Ferdig"
                        )
                    ) {
                        showingInvitePicker =
                            false
                    }
                }
            }
        }
    }

    private func creationSection<
        Content: View
    >(
        title: String,
        icon: String,
        @ViewBuilder content:
            () -> Content
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            Label(
                title,
                systemImage: icon
            )
            .font(.headline)
            .foregroundStyle(
                clubForest
            )

            content()
        }
        .padding(16)
        .background(
            Color.white.opacity(0.93),
            in: RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
            .stroke(
                Color.black.opacity(0.045),
                lineWidth: 0.8
            )
        }
        .shadow(
            color:
                Color.black.opacity(0.025),
            radius: 9,
            y: 3
        )
    }

    private var creationDivider:
        some View {
        Divider()
            .opacity(0.42)
            .padding(.leading, 50)
    }

    private func creationTextField(
        title: String,
        placeholder: String,
        text: Binding<String>,
        icon: String,
        axis: Axis = .horizontal
    ) -> some View {
        HStack(
            alignment:
                axis == .vertical
                    ? .top
                    : .center,
            spacing: 12
        ) {
            Image(
                systemName: icon
            )
            .font(
                .system(
                    size: 17,
                    weight: .semibold
                )
            )
            .foregroundStyle(
                clubForest
            )
            .frame(
                width: 38,
                height: 38
            )
            .background(
                clubMint,
                in: RoundedRectangle(
                    cornerRadius: 12,
                    style: .continuous
                )
            )

            VStack(
                alignment: .leading,
                spacing: 3
            ) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(
                        .secondary
                    )

                TextField(
                    placeholder,
                    text: text,
                    axis: axis
                )
                .font(.body)
                .lineLimit(
                    axis == .vertical
                        ? 2...4
                        : 1...1
                )
            }
        }
        .padding(.vertical, 2)
    }

    private func creationSelectionRow(
        title: String,
        value: String,
        icon: String,
        subtitle: String? = nil
    ) -> some View {
        HStack(spacing: 12) {
            Image(
                systemName: icon
            )
            .font(
                .system(
                    size: 17,
                    weight: .semibold
                )
            )
            .foregroundStyle(
                clubForest
            )
            .frame(
                width: 38,
                height: 38
            )
            .background(
                clubMint,
                in: RoundedRectangle(
                    cornerRadius: 12,
                    style: .continuous
                )
            )

            VStack(
                alignment: .leading,
                spacing: 2
            ) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(
                        .primary
                    )

                if let subtitle,
                   !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(
                            .secondary
                        )
                        .lineLimit(2)
                }
            }

            Spacer()

            HStack(spacing: 7) {
                Text(value)
                    .font(
                        .subheadline
                            .weight(.semibold)
                    )
                    .lineLimit(1)

                Image(
                    systemName:
                        "chevron.down"
                )
                .font(.caption.bold())
            }
            .foregroundStyle(
                clubForest
            )
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(
                clubMint,
                in: Capsule()
            )
        }
    }

    private func creationNumberRow(
        title: String,
        value: Binding<Double>,
        suffix: String,
        icon: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(
                systemName: icon
            )
            .font(
                .system(
                    size: 17,
                    weight: .semibold
                )
            )
            .foregroundStyle(
                clubForest
            )
            .frame(
                width: 38,
                height: 38
            )
            .background(
                clubMint,
                in: RoundedRectangle(
                    cornerRadius: 12,
                    style: .continuous
                )
            )

            Text(title)
                .font(.subheadline)

            Spacer()

            HStack(spacing: 5) {
                TextField(
                    "0",
                    value: value,
                    format:
                        .number
                            .precision(
                                .fractionLength(
                                    0...2
                                )
                            )
                )
                .keyboardType(
                    .decimalPad
                )
                .multilineTextAlignment(
                    .trailing
                )
                .frame(width: 70)

                Text(suffix)
                    .font(.subheadline)
                    .foregroundStyle(
                        .secondary
                    )
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(
                clubMint,
                in: Capsule()
            )
        }
    }

    private func creationDateControl(
        title: String,
        selection: Binding<Date>,
        range: ClosedRange<Date>
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 5
        ) {
            Text(title)
                .font(.caption)
                .foregroundStyle(
                    .secondary
                )

            DatePicker(
                "",
                selection: selection,
                in: range,
                displayedComponents: [
                    .date,
                    .hourAndMinute
                ]
            )
            .labelsHidden()
            .datePickerStyle(.compact)
        }
        .padding(12)
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .background(
            Color.primary.opacity(0.035),
            in: RoundedRectangle(
                cornerRadius: 15,
                style: .continuous
            )
        )
    }

    private var typeStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text(
                    ATHLTHLocalization.choose(
                        english: "Challenge name",
                        norwegian: "Navn på utfordring"
                    )
                )
                .font(.title3.bold())

                HStack(spacing: 10) {
                    TextField(
                        ATHLTHLocalization.choose(
                            english: "Optional name",
                            norwegian: "Valgfritt navn"
                        ),
                        text: Binding(
                            get: { title },
                            set: { title = String($0.prefix(60)) }
                        )
                    )
                    .textInputAutocapitalization(.words)
                    .font(.body.weight(.medium))

                    if !title.isEmpty {
                        Button {
                            title = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 15)
                .frame(height: 54)
                .background(
                    Color.white.opacity(0.96),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.primary.opacity(0.09), lineWidth: 0.8)
                }

                Text(
                    title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? ATHLTHLocalization.choose(
                            english: "Optional · if left empty, ATHLTH uses “\(automaticTitle)”.",
                            norwegian: "Valgfritt · står feltet tomt, brukes «\(automaticTitle)»."
                        )
                        : ATHLTHLocalization.choose(
                            english: "\(title.count)/60 characters",
                            norwegian: "\(title.count)/60 tegn"
                        )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(
                    ATHLTHLocalization.choose(
                        english: "Short description",
                        norwegian: "Kort beskrivelse"
                    )
                )
                .font(.headline)

                TextField(
                    ATHLTHLocalization.choose(
                        english: "Optional · tell participants what the challenge is about",
                        norwegian: "Valgfritt · fortell deltakerne hva utfordringen går ut på"
                    ),
                    text: Binding(
                        get: { challengeSummary },
                        set: { challengeSummary = String($0.prefix(160)) }
                    ),
                    axis: .vertical
                )
                .lineLimit(2...4)
                .padding(14)
                .background(
                    Color.white.opacity(0.96),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.8)
                }

                HStack {
                    Text(
                        ATHLTHLocalization.choose(
                            english: "Shown on challenge cards and invitations.",
                            norwegian: "Vises på challenge-kort og invitasjoner."
                        )
                    )
                    Spacer()
                    Text("\(challengeSummary.count)/160")
                        .monospacedDigit()
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 11) {
                Text(
                    ATHLTHLocalization.choose(
                        english: "Challenge image",
                        norwegian: "Challenge-bilde"
                    )
                )
                .font(.headline)

                Text(
                    ATHLTHLocalization.choose(
                        english: "Choose an ATHLTH image or upload your own.",
                        norwegian: "Velg et ATHLTH-bilde eller last opp ditt eget."
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(challengeCoverArtworkOptions, id: \.self) { artwork in
                            Button {
                                selectedCoverArtworkName = artwork
                                selectedCoverImageData = nil
                                selectedCoverPhoto = nil
                                coverWasManuallySelected = true
                            } label: {
                                Image(artwork)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 96, height: 62)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                                            .stroke(
                                                selectedCoverImageData == nil &&
                                                selectedCoverArtworkName == artwork
                                                    ? clubEmerald
                                                    : Color.primary.opacity(0.08),
                                                lineWidth:
                                                    selectedCoverImageData == nil &&
                                                    selectedCoverArtworkName == artwork
                                                        ? 2
                                                        : 0.8
                                            )
                                    }
                                    .overlay(alignment: .topTrailing) {
                                        if selectedCoverImageData == nil &&
                                           selectedCoverArtworkName == artwork {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.caption)
                                                .foregroundStyle(.white)
                                                .padding(6)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(artwork)
                        }

                        PhotosPicker(
                            selection: $selectedCoverPhoto,
                            matching: .images
                        ) {
                            ZStack {
                                if let data = selectedCoverImageData,
                                   let image = UIImage(data: data) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                } else {
                                    VStack(spacing: 5) {
                                        Image(systemName: "photo.badge.plus")
                                            .font(.title3)
                                        Text(
                                            ATHLTHLocalization.choose(
                                                english: "Own",
                                                norwegian: "Eget"
                                            )
                                        )
                                        .font(.caption2.weight(.semibold))
                                    }
                                    .foregroundStyle(clubForest)
                                }
                            }
                            .frame(width: 96, height: 62)
                            .background(clubMint.opacity(0.72))
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 15, style: .continuous)
                                    .stroke(
                                        selectedCoverImageData != nil
                                            ? clubEmerald
                                            : Color.primary.opacity(0.08),
                                        lineWidth: selectedCoverImageData != nil ? 2 : 0.8
                                    )
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 2)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text(
                    ATHLTHLocalization.choose(
                        english: "What are you competing in?",
                        norwegian: "Hva konkurrerer dere i?"
                    )
                )
                .font(.title2.bold())

                HStack(spacing: 10) {
                    sportButton(.running)
                    sportButton(.strength)
                    sportButton(.heartRate)
                }
            }

            VStack(alignment: .leading, spacing: 11) {
                Text(
                    ATHLTHLocalization.choose(
                        english: "Scoring",
                        norwegian: "Poengberegning"
                    )
                )
                .font(.title3.bold())

                ForEach(scoringOptions) { option in
                    let selected = scoring == option

                    Button {
                        scoring = option
                    } label: {
                        HStack(spacing: 13) {
                            Image(systemName: scoringIcon(option))
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(selected ? clubEmerald : clubForest)
                                .frame(width: 44, height: 44)
                                .background(
                                    selected ? clubMint : Color.primary.opacity(0.045),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                                )

                            VStack(alignment: .leading, spacing: 4) {
                                Text(option.title)
                                    .font(.headline)
                                    .foregroundStyle(.primary)

                                Text(scoringSubtitle(option))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 8)

                            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(selected ? clubEmerald : Color.secondary.opacity(0.72))
                        }
                        .padding(14)
                        .background(
                            selected ? clubMint.opacity(0.72) : Color.white.opacity(0.96),
                            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(
                                    selected ? clubEmerald.opacity(0.52) : Color.primary.opacity(0.07),
                                    lineWidth: selected ? 1.1 : 0.8
                                )
                        }
                        .shadow(
                            color: Color.black.opacity(selected ? 0.045 : 0.022),
                            radius: 9,
                            y: 4
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var rulesStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Set the rules")
                    .font(.title2.bold())

                Spacer()

                Text(advancedRules ? "ADVANCED" : "BASIC")
                    .font(.caption2.weight(.bold))
                    .tracking(1.1)
                    .foregroundStyle(ATHLTHTheme.accent)
            }

            Picker(
                "Rule detail",
                selection: $advancedRules
            ) {
                Text("Basic").tag(false)
                Text("Advanced").tag(true)
            }
            .pickerStyle(.segmented)

            switch sport {
            case .running:
                runningRules
            case .strength:
                strengthRules
            case .heartRate:
                heartRateRules
            }

            if advancedRules &&
                sport != .running &&
                !(sport == .heartRate &&
                  heartRateAggregation == .totalChallenge) {
                Toggle(
                    "Allow multiple attempts",
                    isOn: $allowMultipleAttempts
                )
                .padding()
                .challengeCard()
            }

            VStack(alignment: .leading, spacing: 7) {
                Label(
                    "Rules lock when the challenge starts",
                    systemImage: "lock.fill"
                )
                .font(.subheadline.weight(.semibold))

                Text(
                    "Once live, target, route, verification and scoring cannot be changed."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding()
            .challengeCard()
        }
    }

    private var runningRules: some View {
        VStack(alignment: .leading, spacing: 14) {
            if scoring == .fastestDistance {
                VStack(alignment: .leading, spacing: 9) {
                    Text("Course")
                        .font(.headline)

                    HStack(spacing: 12) {
                        routeRequirementButton(
                            title: "Run Anywhere",
                            subtitle: "Choose a distance",
                            icon: "figure.run",
                            selected: !usesSpecificRoute,
                            disabled: false
                        ) {
                            usesSpecificRoute = false
                        }

                        routeRequirementButton(
                            title: "Specific Route",
                            subtitle: "Same course",
                            icon:
                                "point.topleft.down.to.point.bottomright.curvepath",
                            selected: usesSpecificRoute,
                            disabled: false
                        ) {
                            usesSpecificRoute = true
                        }
                    }

                    Text(
                        usesSpecificRoute
                            ? "Everyone competes on the same saved route."
                            : "Everyone runs the same distance, but may choose their own course."
                    )
                    .challengeHint()
                }

                if usesSpecificRoute {
                    routeSelectionCard
                } else {
                    numberField(
                        title: "Distance",
                        suffix: "km",
                        value: $targetDistanceKm
                    )
                }
            }

            if scoring == .farthestInTime {
                numberField(
                    title: "Time",
                    suffix: "min",
                    value: $targetDurationMinutes
                )
            }

            if scoring == .fastestDistance &&
                usesSpecificRoute {
                HStack(spacing: 10) {
                    Image(systemName: "location.fill")
                        .foregroundStyle(.green)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("GPS verification required")
                            .font(.subheadline.weight(.semibold))
                        Text(
                            "Specific-route challenges must include GPS data."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                }
                .padding()
                .challengeCard()
            } else {
                Toggle(
                    "Require GPS verification",
                    isOn: $gpsRequired
                )
                .padding()
                .challengeCard()
            }

            HStack(spacing: 10) {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundStyle(ATHLTHTheme.accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Verified running only")
                        .font(.subheadline.weight(.semibold))

                    Text(
                        "Running results must come from ATHLTH or a qualifying Apple Health workout. Manual entries are not accepted."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .padding()
            .challengeCard()

            if advancedRules {
                if scoring == .fastestDistance {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Timing")
                            .font(.headline)

                        Picker(
                            "Timing",
                            selection: $timeBasis
                        ) {
                            ForEach(
                                ChallengeTimeBasis.allCases
                            ) { basis in
                                Text(basis.title)
                                    .tag(basis)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text(
                            timeBasis == .elapsed
                                ? "Elapsed time includes pauses."
                                : "Moving time excludes detected stops."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding()
                    .challengeCard()
                }

                if scoring == .fastestDistance &&
                    !usesSpecificRoute {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Text("Distance tolerance")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(
                                "±\(distanceTolerancePercent.formatted(.number.precision(.fractionLength(0...1))))%"
                            )
                            .font(.subheadline.bold())
                            .monospacedDigit()
                        }

                        Slider(
                            value: $distanceTolerancePercent,
                            in: 0.5...5,
                            step: 0.5
                        )

                        Text(
                            distanceToleranceDescription
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding()
                    .challengeCard()
                }

                if scoring == .fastestDistance &&
                    usesSpecificRoute {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Text("Allowed route deviation")
                                .font(.subheadline.weight(.semibold))

                            Spacer()

                            Text(
                                "\(Int(allowedRouteDeviationPercent))%"
                            )
                            .font(.subheadline.bold())
                            .monospacedDigit()
                        }

                        Slider(
                            value: allowedRouteDeviationBinding,
                            in: 2...20,
                            step: 1
                        )

                        Text(
                            ATHLTHLocalization.format(
                                english: "Participants must match at least %d%% of the selected route.",
                                norwegian: "Deltakere må matche minst %d %% av den valgte ruten.",
                                Int(routeMatchPercent)
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        Divider()

                        HStack {
                            Text("Start & finish tolerance")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(
                                "\(Int(startFinishToleranceMeters)) m"
                            )
                            .font(.subheadline.bold())
                            .monospacedDigit()
                        }

                        Slider(
                            value: $startFinishToleranceMeters,
                            in: 25...500,
                            step: 25
                        )

                        Text(
                            "The attempt must start and finish within this distance of the saved route endpoints."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        Divider()

                        Text("Route direction")
                            .font(.subheadline.weight(.semibold))

                        Picker(
                            "Route direction",
                            selection: $routeDirection
                        ) {
                            ForEach(
                                ChallengeRouteDirection.allCases
                            ) { direction in
                                Text(direction.title)
                                    .tag(direction)
                            }
                        }
                        .pickerStyle(.segmented)

                        Divider()

                        Toggle(
                            "Allow target ghost",
                            isOn: $allowTargetGhost
                        )

                        Text(
                            allowTargetGhost
                                ? "Participants may use a synthetic pace ghost to target a chosen finish time on this route."
                                : "Participants must run the challenge route without a synthetic target-time pacer."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding()
                    .challengeCard()
                }

                if !usesSpecificRoute {
                    VStack(alignment: .leading, spacing: 7) {
                        Toggle(
                            "Allow treadmill",
                            isOn: $allowTreadmill
                        )
                        .disabled(gpsRequired)

                        Text(
                            gpsRequired
                                ? "Turn off GPS verification to allow indoor treadmill runs."
                                : "When enabled, verified indoor runs may qualify without a GPS route."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding()
                    .challengeCard()
                }

                VStack(alignment: .leading, spacing: 10) {
                    Toggle(
                        "Allow multiple attempts",
                        isOn: $allowMultipleAttempts
                    )

                    if allowMultipleAttempts {
                        Divider()

                        Text("Attempt policy")
                            .font(.subheadline.weight(.semibold))

                        Picker(
                            "Attempt policy",
                            selection: $attemptPolicy
                        ) {
                            ForEach(
                                ChallengeAttemptPolicy.allCases
                            ) { policy in
                                Text(policy.title)
                                    .tag(policy)
                            }
                        }
                        .pickerStyle(.segmented)

                        Picker(
                            "Maximum attempts",
                            selection: $attemptLimit
                        ) {
                            Text("Unlimited").tag(0)
                            Text("3").tag(3)
                            Text("5").tag(5)
                        }
                    } else {
                        Text(
                            "Only the first qualifying attempt is recorded."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .challengeCard()

                Button {
                    resetRunningAdvancedRules()
                } label: {
                    Label(
                        "Reset to Recommended",
                        systemImage: "arrow.counterclockwise"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder
    private var routeSelectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let route = selectedRoute {
                if route.coordinates.count >= 2 {
                    Map(
                        initialPosition: .region(
                            challengeRegion(for: route)
                        )
                    ) {
                        MapPolyline(
                            coordinates:
                                route.coordinates.map(\.coordinate)
                        )
                        .stroke(
                            ATHLTHTheme.accent,
                            style: StrokeStyle(
                                lineWidth: 5,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )

                        if let first = route.coordinates.first {
                            Marker(
                                route.startName ?? "Start",
                                coordinate: first.coordinate
                            )
                            .tint(ATHLTHTheme.accent)
                        }

                        if let last = route.coordinates.last {
                            Marker(
                                route.endName ?? "Finish",
                                coordinate: last.coordinate
                            )
                            .tint(.red)
                        }
                    }
                    .allowsHitTesting(false)
                    .frame(height: 170)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 18,
                            style: .continuous
                        )
                    )
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text(route.title)
                        .font(.headline)

                    if let start = route.startName,
                       let end = route.endName {
                        Text("\(start) → \(end)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    HStack(spacing: 12) {
                        Label(
                            String(
                                format: "%.1f km",
                                route.distanceKilometers
                            ),
                            systemImage: "figure.run"
                        )

                        if let elevation = route.elevationGainMeters {
                            Label(
                                "\(Int(elevation.rounded())) m",
                                systemImage: "mountain.2.fill"
                            )
                        }

                        Label(
                            "\(route.coordinates.count) points",
                            systemImage: "point.3.connected.trianglepath.dotted"
                        )
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    NavigationLink {
                        ChallengeRouteSelectionView(
                            selectedRouteID: $selectedRouteID
                        )
                    } label: {
                        Label(
                            "Change Route",
                            systemImage: "map"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    NavigationLink {
                        RunRouteBuilderView()
                    } label: {
                        Label(
                            "New Route",
                            systemImage: "plus"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "map.fill")
                        .font(.title2)
                        .foregroundStyle(ATHLTHTheme.accent)
                        .frame(width: 50, height: 50)
                        .background(
                            ATHLTHTheme.accentSoft,
                            in: RoundedRectangle(
                                cornerRadius: 14,
                                style: .continuous
                            )
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Choose a route")
                            .font(.headline)

                        Text(
                            session.savedRoutes.isEmpty
                                ? "You do not have any saved routes yet."
                                : "Select one of your saved routes or create a new one."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()
                }

                HStack(spacing: 10) {
                    if !session.savedRoutes.isEmpty {
                        NavigationLink {
                            ChallengeRouteSelectionView(
                                selectedRouteID: $selectedRouteID
                            )
                        } label: {
                            Label(
                                "My Routes",
                                systemImage: "map"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(ATHLTHTheme.accent)
                    }

                    if session.savedRoutes.isEmpty {
                        NavigationLink {
                            RunRouteBuilderView()
                        } label: {
                            Label(
                                "Create New",
                                systemImage: "plus"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(ATHLTHTheme.accent)
                    } else {
                        NavigationLink {
                            RunRouteBuilderView()
                        } label: {
                            Label(
                                "Create New",
                                systemImage: "plus"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(ATHLTHTheme.accent)
                    }
                }
            }
        }
        .padding()
        .challengeCard()
    }

    private var heartRateRules: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Heart-rate zone")
                    .font(.headline)

                HStack(spacing: 7) {
                    ForEach(1...5, id: \.self) { zone in
                        Button {
                            heartRateZone = zone
                        } label: {
                            VStack(spacing: 4) {
                                Text("Z\(zone)")
                                    .font(.subheadline.weight(.bold))
                                Text(heartRateZonePercentText(zone))
                                    .font(.system(size: 9, weight: .medium))
                                    .minimumScaleFactor(0.8)
                            }
                            .foregroundStyle(
                                heartRateZone == zone
                                    ? .white
                                    : ATHLTHTheme.primaryText
                            )
                            .frame(maxWidth: .infinity, minHeight: 58)
                            .background(
                                heartRateZone == zone
                                    ? ATHLTHTheme.accent
                                    : Color(.secondarySystemGroupedBackground),
                                in: RoundedRectangle(
                                    cornerRadius: 14,
                                    style: .continuous
                                )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let maximumHeartRateBPM {
                    HStack(spacing: 11) {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(.pink)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(
                                ATHLTHLocalization.format(
                                    english: "Zone %d · %@",
                                    norwegian: "Sone %d · %@",
                                    heartRateZone,
                                    heartRateZoneBPMText(
                                        zone: heartRateZone,
                                        maxHR: maximumHeartRateBPM
                                    )
                                )
                            )
                            .font(.subheadline.weight(.semibold))

                            Text(
                                ATHLTHLocalization.format(
                                    english: "Calculated from your private max HR of %d bpm.",
                                    norwegian: "Beregnet fra din private makspuls på %d bpm.",
                                    maximumHeartRateBPM
                                )
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .padding()
                    .challengeCard()
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(
                            "Maximum heart rate required",
                            systemImage: "heart.slash"
                        )
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)

                        Text(
                            "ATHLTH compares time in a personal heart-rate zone. Add your maximum heart rate before creating this challenge."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        NavigationLink {
                            PersonalHealthProfileView()
                        } label: {
                            Label(
                                "Set Maximum Heart Rate",
                                systemImage: "heart.text.square"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(ATHLTHTheme.accent)
                    }
                    .padding()
                    .challengeCard()
                }
            }

            VStack(alignment: .leading, spacing: 9) {
                Text("Leaderboard")
                    .font(.headline)

                Picker(
                    "Leaderboard",
                    selection: $heartRateAggregation
                ) {
                    ForEach(
                        ChallengeHeartRateAggregation.allCases
                    ) { aggregation in
                        Text(aggregation.title)
                            .tag(aggregation)
                    }
                }
                .pickerStyle(.segmented)

                Text(heartRateAggregation.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .challengeCard()

            HStack(spacing: 10) {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundStyle(ATHLTHTheme.accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Verified heart-rate data only")
                        .font(.subheadline.weight(.semibold))

                    Text(
                        "Any qualifying workout can count when it contains Apple Health heart-rate samples. Manual heart-rate results are never accepted."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding()
            .challengeCard()

            if advancedRules {
                VStack(alignment: .leading, spacing: 6) {
                    Label(
                        "Personal zones",
                        systemImage: "person.crop.circle.badge.checkmark"
                    )
                    .font(.subheadline.weight(.semibold))

                    Text(
                        "Every participant is scored against their own private maximum heart rate. ATHLTH never exposes that value to the challenge or leaderboard."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding()
                .challengeCard()
            }
        }
    }

    private var strengthRules: some View {
        VStack(alignment: .leading, spacing: 14) {
            if scoring != .workoutVolume {
                TextField("Exercise", text: $exerciseName)
                    .textFieldStyle(.roundedBorder)
            }

            if scoring == .mostReps {
                Toggle("Require a specific weight", isOn: $requiredWeightEnabled)

                if requiredWeightEnabled {
                    numberField(
                        title: "Required weight",
                        suffix: "kg",
                        value: $requiredWeightKg
                    )
                }
            }

            if advancedRules {
                Picker(
                    "Result verification",
                    selection: $verificationPolicy
                ) {
                    ForEach(
                        ChallengeVerificationPolicy.allCases
                    ) { policy in
                        Text(policy.title).tag(policy)
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    Label(
                        verificationPolicy.title,
                        systemImage:
                            verificationPolicy ==
                                .verifiedRequired
                                ? "checkmark.seal.fill"
                                : "hand.tap.fill"
                    )
                    .font(.subheadline.weight(.semibold))

                    Text(verificationPolicy.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .challengeCard()
            }

            Text(
                "Manual strength submissions stay clearly labelled Manual. ATHLTH-tracked sets are labelled ATHLTH Verified."
            )
            .challengeHint()
        }
    }

    private var peopleStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Who are you challenging?")
                .font(.title2.bold())

            if let route = selectedRoute {
                HStack(spacing: 10) {
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.accent)
                        .frame(width: 34, height: 34)
                        .background(
                            ATHLTHTheme.accentSoft,
                            in: RoundedRectangle(
                                cornerRadius: 10,
                                style: .continuous
                            )
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Route Challenge")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Text(route.title)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Text(
                        String(
                            format: "%.1f km",
                            route.distanceKilometers
                        )
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                }
                .padding()
                .challengeCard()
            }

            participantRow(
                name: session.profile.displayName,
                username: session.profile.username,
                state: "You · Creator"
            )

            if !invitees.isEmpty {
                Text("SELECTED")
                    .font(.caption2.bold())
                    .tracking(1.1)
                    .foregroundStyle(.secondary)

                ForEach(invitees) { participant in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(ATHLTHTheme.accent.opacity(0.10))
                            .frame(width: 42, height: 42)
                            .overlay {
                                Image(systemName: "person.fill")
                                    .foregroundStyle(ATHLTHTheme.accent)
                            }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(participant.displayName)
                                .font(.subheadline.weight(.semibold))
                            if let username = participant.username, !username.isEmpty {
                                Text("@\(username)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        Button {
                            invitees.removeAll { $0.userID == participant.userID }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding()
                    .challengeCard()
                }
            }

            Text("FRIENDS")
                .font(.caption2.bold())
                .tracking(1.1)
                .foregroundStyle(.secondary)

            if social.mutualFollows.isEmpty {
                VStack(spacing: 10) {
                    Text("Add friends before sending a challenge.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    NavigationLink {
                        SocialHubView(initialTab: .discover)
                    } label: {
                        Label("Find Friends", systemImage: "person.badge.plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ATHLTHTheme.accent)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .challengeCard()
            } else {
                ForEach(social.mutualFollows) { friend in
                    Button {
                        toggleFriend(friend)
                    } label: {
                        HStack(spacing: 12) {
                            SocialAvatar(profile: friend, size: 42)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(friend.resolvedName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(friend.usernameLabel)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(
                                systemName: invitees.contains(where: { $0.userID == friend.userID })
                                    ? "checkmark.circle.fill"
                                    : "circle"
                            )
                            .foregroundStyle(
                                invitees.contains(where: { $0.userID == friend.userID })
                                    ? ATHLTHTheme.accent
                                    : .secondary
                            )
                        }
                        .padding()
                        .challengeCard()
                    }
                    .buttonStyle(.plain)
                }
            }

            Picker("Visibility", selection: $visibility) {
                Text("Friends").tag(ProfileVisibility.friends)
                Text("Private").tag(ProfileVisibility.privateOnly)
                Text("Public").tag(ProfileVisibility.publicProfile)
            }
        }
    }

    private var scheduleStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("When does it count?")
                .font(.title2.bold())

            DatePicker(
                "Starts",
                selection: $startsAt,
                in: Date()...,
                displayedComponents: [.date, .hourAndMinute]
            )

            Toggle("Set an end time", isOn: $hasEnd)

            if hasEnd {
                DatePicker(
                    "Ends",
                    selection: $endsAt,
                    in: startsAt...,
                    displayedComponents: [.date, .hourAndMinute]
                )
            }

            Toggle("Meet and train together", isOn: $meetupEnabled)

            if meetupEnabled {
                TextField("Meetup name", text: $meetupPlaceName)
                    .textFieldStyle(.roundedBorder)

                DatePicker(
                    "Meet at",
                    selection: $meetupAt,
                    in: Date()...,
                    displayedComponents: [.date, .hourAndMinute]
                )

                Text("Tap the map to set the meetup point.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                MeetupLocationPicker(
                    coordinate: $meetupCoordinate,
                    position: $mapPosition
                )

                if selectedRouteID != nil {
                    Button("Use route start") {
                        guard let routeID = selectedRouteID,
                              let route = session.savedRoutes.first(where: { $0.id == routeID }),
                              let first = route.coordinates.first
                        else {
                            return
                        }

                        let coordinate = CLLocationCoordinate2D(
                            latitude: first.latitude,
                            longitude: first.longitude
                        )
                        meetupCoordinate = coordinate
                        mapPosition = .region(
                            MKCoordinateRegion(
                                center: coordinate,
                                span: MKCoordinateSpan(
                                    latitudeDelta: 0.015,
                                    longitudeDelta: 0.015
                                )
                            )
                        )
                    }
                    .font(.caption.weight(.semibold))
                }

                Text("Check-in is explicit. ATHLTH does not continuously share participants’ live location.")
                    .challengeHint()
            }
        }
    }

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Ready to challenge")
                .font(.title2.bold())

            ChallengeReviewCard(
                title: resolvedTitle,
                summary: resolvedSummary,
                sport: sport,
                scoring: effectiveScoring,
                verification:
                    sport == .running
                        ? .verifiedRequired
                        : verificationPolicy,
                coverArtworkName:
                    selectedCoverImageData == nil
                        ? selectedCoverArtworkName
                        : nil,
                customImageData: selectedCoverImageData,
                startsAt: startsAt,
                endsAt: hasEnd ? endsAt : nil,
                participantCount: invitees.count + 1
            )

            reviewRow("Starts", startsAt.formatted(date: .abbreviated, time: .shortened))

            if hasEnd {
                reviewRow("Ends", endsAt.formatted(date: .abbreviated, time: .shortened))
            }

            reviewRow(
                "Participants",
                "\(invitees.count + 1)"
            )

            reviewRow(
                "Attempts",
                runningAttemptSummary
            )

            if sport == .running &&
                scoring == .fastestDistance {
                if let route = selectedRoute,
                   usesSpecificRoute {
                    reviewRow("Course", "Specific Route")
                    reviewRow("Route", route.title)

                    if advancedRules {
                        reviewRow(
                            "Route deviation",
                            "\(Int(allowedRouteDeviationPercent))%"
                        )
                        reviewRow(
                            "Start/finish",
                            "Within \(Int(startFinishToleranceMeters)) m"
                        )
                        reviewRow(
                            "Direction",
                            routeDirection.title
                        )
                        reviewRow(
                            "Target ghost",
                            allowTargetGhost
                                ? "Allowed"
                                : "Disabled"
                        )
                    }
                } else {
                    reviewRow("Course", "Run Anywhere")
                    reviewRow(
                        "Distance",
                        String(
                            format:
                                "%.1f km",
                            targetDistanceKm
                        )
                    )

                    if advancedRules {
                        reviewRow(
                            "Distance tolerance",
                            "±\(distanceTolerancePercent.formatted(.number.precision(.fractionLength(0...1))))%"
                        )
                        reviewRow(
                            "Treadmill",
                            allowTreadmill
                                ? "Allowed"
                                : "Not allowed"
                        )
                    }
                }

                if advancedRules {
                    reviewRow("Timing", timeBasis.title)
                    reviewRow(
                        "GPS",
                        usesSpecificRoute || gpsRequired
                            ? "Required"
                            : "Optional"
                    )
                }
            }

            if sport == .heartRate {
                reviewRow(
                    "Zone",
                    "Zone \(heartRateZone) · \(heartRateZonePercentText(heartRateZone))"
                )
                reviewRow(
                    "Leaderboard",
                    heartRateAggregation.title
                )
                reviewRow(
                    "Verification",
                    "Verified HR samples only"
                )
            } else if sport == .running {
                reviewRow(
                    "Verification",
                    "Verified only · no manual results"
                )
            } else if sport == .strength {
                reviewRow("Verification", verificationPolicy.title)
            }

            if meetupEnabled {
                reviewRow(
                    "Meetup",
                    meetupPlaceName.isEmpty ? "Pinned location" : meetupPlaceName
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                Label("Community activity", systemImage: "person.2.wave.2.fill")
                    .font(.headline)
                    .foregroundStyle(ATHLTHTheme.accent)

                Toggle(
                    "Share this challenge to Community",
                    isOn: $shareToCommunity
                )

                Text(
                    "People who can see the challenge will get a compact challenge card in their Community feed."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding()
            .challengeCard()

            VStack(alignment: .leading, spacing: 6) {
                Label("Fair-play rules", systemImage: "checkmark.shield.fill")
                    .font(.headline)
                    .foregroundStyle(ATHLTHTheme.accent)
                Text("Only attempts inside the challenge window count. Rules lock at start. Verified and Manual strength results stay visibly different.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .challengeCard()
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if step > 0 {
                Button {
                    withAnimation {
                        step -= 1
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline)
                        .foregroundStyle(clubForest)
                        .frame(width: 54, height: 54)
                        .background(
                            Color.white.opacity(0.94),
                            in: RoundedRectangle(
                                cornerRadius: 22,
                                style: .continuous
                            )
                        )
                }
                .buttonStyle(.plain)
            }

            Button {
                if step == 4 {
                    Task {
                        await createChallenge()
                    }
                } else {
                    withAnimation {
                        step += 1
                    }
                }
            } label: {
                HStack(spacing: 9) {
                    if creatingChallenge {
                        ProgressView()
                            .tint(.white)
                    }

                    Text(
                        step == 4
                            ? (
                                creatingChallenge
                                    ? ATHLTHLocalization.choose(
                                        english: "Sending…",
                                        norwegian: "Sender…"
                                    )
                                    : ATHLTHLocalization.choose(
                                        english: "Send Challenge",
                                        norwegian: "Send utfordring"
                                    )
                            )
                            : ATHLTHLocalization.choose(
                                english: "Continue",
                                norwegian: "Fortsett"
                            )
                    )
                    .font(.headline)

                    if step < 4 && !creatingChallenge {
                        Image(systemName: "arrow.right")
                            .font(.subheadline.bold())
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    LinearGradient(
                        colors: [
                            clubForest,
                            clubEmerald
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: Capsule(style: .continuous)
                )
                .opacity(
                    canContinue && !creatingChallenge
                        ? 1
                        : 0.34
                )
            }
            .buttonStyle(.plain)
            .disabled(
                !canContinue ||
                creatingChallenge
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    private var scoringOptions: [ATHLTHChallengeScoring] {
        switch sport {
        case .running:
            return [.fastestDistance, .farthestInTime, .mostDistance]
        case .strength:
            return [.heaviestWeight, .mostReps, .exerciseVolume, .workoutVolume]
        case .heartRate:
            return [.heartRateZoneTime]
        }
    }

    private var stepTitle: String {
        [
            ATHLTHLocalization.choose(
                english: "Basics",
                norwegian: "Grunnoppsett"
            ),
            ATHLTHLocalization.choose(
                english: "Rules",
                norwegian: "Regler"
            ),
            ATHLTHLocalization.choose(
                english: "People",
                norwegian: "Personer"
            ),
            ATHLTHLocalization.choose(
                english: "Schedule",
                norwegian: "Tid"
            ),
            ATHLTHLocalization.choose(
                english: "Review",
                norwegian: "Se over"
            )
        ][step]
    }

    private var canContinue: Bool {
        switch step {
        case 0:
            return true
        case 1:
            if sport == .running {
                if scoring == .fastestDistance {
                    if usesSpecificRoute {
                        return selectedRouteID != nil
                    }

                    return targetDistanceKm > 0
                }

                if scoring == .farthestInTime &&
                    targetDurationMinutes <= 0 {
                    return false
                }

                return true
            }

            if sport == .heartRate {
                return maximumHeartRateBPM != nil &&
                    (1...5).contains(heartRateZone)
            }

            if scoring != .workoutVolume &&
                exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return false
            }

            return true

        case 2:
            return !invitees.isEmpty

        case 3:
            if hasEnd && endsAt <= startsAt { return false }
            if meetupEnabled && meetupCoordinate == nil { return false }
            return true

        default:
            return true
        }
    }

    private var selectedRoute: TrainingRoute? {
        guard let selectedRouteID else { return nil }
        return session.savedRoutes.first { $0.id == selectedRouteID }
    }

    private var effectiveScoring: ATHLTHChallengeScoring {
        if sport == .running &&
            scoring == .fastestDistance &&
            usesSpecificRoute {
            return .fastestRoute
        }

        return scoring
    }

    private var automaticTitle: String {
        ChallengeCreationPolicy
            .automaticTitle(
                sport: sport,
                scoring: effectiveScoring
            )
    }

    private var resolvedTitle: String {
        ChallengeCreationPolicy
            .resolvedTitle(
                title,
                sport: sport,
                scoring: effectiveScoring
            )
    }

    private var resolvedSummary: String? {
        let clean =
            challengeSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        return String(clean.prefix(160))
    }

    private var challengeCoverArtworkOptions: [String] {
        [
            "GoalRunning",
            "GoalSprint",
            "GoalStrength",
            "GoalEndurance",
            "GoalMountain",
            "GoalEvent",
            "GoalAdventure",
            "GoalConsistency",
            "GoalProgress",
            "GoalRecovery",
            "GoalRelax",
            "GoalWalking"
        ]
    }

    private func defaultCoverArtwork(
        for sport: ATHLTHChallengeSport
    ) -> String {
        switch sport {
        case .running: return "GoalRunning"
        case .strength: return "GoalStrength"
        case .heartRate: return "GoalEndurance"
        }
    }

    private func challengeParticipant(_ friend: SocialProfileCard) -> ChallengeParticipant {
        ChallengeParticipant(
            userID: friend.userID,
            username: friend.username,
            displayName: friend.resolvedName,
            state: .invited
        )
    }

    private func toggleFriend(_ friend: SocialProfileCard) {
        if invitees.contains(where: { $0.userID == friend.userID }) {
            invitees.removeAll { $0.userID == friend.userID }
        } else {
            invitees.append(challengeParticipant(friend))
        }
    }

    @MainActor
    private func createChallenge() async {
        creatingChallenge = true
        createError = nil

        let inviteeIDs =
            Set(
                invitees.compactMap(
                    \.userID
                )
            )

        if !inviteeIDs.isEmpty,
           let duplicate =
                challenges.visibleChallenges.first(
                    where: { existing in
                        existing.creatorID ==
                            session.profile.userID &&
                        existing.status != .completed &&
                        existing.status != .cancelled &&
                        existing.title
                            .localizedCaseInsensitiveCompare(
                                resolvedTitle
                            ) == .orderedSame &&
                        existing.sport == sport &&
                        existing.rules.scoring ==
                            effectiveScoring &&
                        abs(
                            existing.rules.startsAt
                                .timeIntervalSince(
                                    startsAt
                                )
                        ) <= 900 &&
                        existing.participants
                            .contains {
                                guard
                                    let userID =
                                        $0.userID
                                else {
                                    return false
                                }

                                return inviteeIDs
                                    .contains(
                                        userID
                                    ) &&
                                    $0.state ==
                                        .invited
                            }
                    }
                ) {
            creatingChallenge = false

            let waitingName =
                duplicate.participants
                    .first(
                        where: {
                            guard
                                let userID =
                                    $0.userID
                            else {
                                return false
                            }

                            return inviteeIDs
                                .contains(
                                    userID
                                ) &&
                                $0.state ==
                                    .invited
                        }
                    )?
                    .displayName

            createError =
                ATHLTHLocalization.choose(
                    english:
                        waitingName.map {
                            "A matching challenge invite to \($0) is already waiting for a response."
                        } ??
                        "A matching challenge invite is already waiting for a response.",
                    norwegian:
                        waitingName.map {
                            "En tilsvarende challenge til \($0) venter allerede på svar."
                        } ??
                        "En tilsvarende challenge venter allerede på svar."
                )
            return
        }

        let challengeID = UUID()
        var uploadedCoverURL: String?

        if let selectedCoverImageData {
            guard let imageURL =
                    await social.uploadChallengeCover(
                        challengeID: challengeID,
                        jpegData: selectedCoverImageData
                    )
            else {
                creatingChallenge = false
                createError =
                    social.errorMessage ??
                    ATHLTHLocalization.choose(
                        english: "The challenge image could not be uploaded.",
                        norwegian: "Challenge-bildet kunne ikke lastes opp."
                    )
                return
            }

            uploadedCoverURL = imageURL
        }

        let creator = ChallengeParticipant(
            userID: session.profile.userID,
            username: session.profile.username,
            displayName: session.profile.displayName,
            state: .creator
        )

        let routeSnapshot = selectedRoute.map {
            ChallengeRouteSnapshot(
                routeID: $0.id,
                title: $0.title,
                distanceKilometers: $0.distanceKilometers,
                coordinates: $0.coordinates
            )
        }

        let meetup: ChallengeMeetup?
        if meetupEnabled, let meetupCoordinate {
            meetup = ChallengeMeetup(
                placeName: meetupPlaceName.isEmpty
                    ? "Meetup point"
                    : meetupPlaceName,
                latitude: meetupCoordinate.latitude,
                longitude: meetupCoordinate.longitude,
                scheduledAt: meetupAt,
                checkInRadiusMeters: 150
            )
        } else {
            meetup = nil
        }

        let rules = ATHLTHChallengeRules(
            scoring: effectiveScoring,
            verificationPolicy:
                sport == .strength
                    ? verificationPolicy
                    : .verifiedRequired,
            targetDistanceMeters:
                scoring == .fastestDistance &&
                !usesSpecificRoute
                    ? targetDistanceKm * 1_000
                    : nil,
            targetDurationSeconds: scoring == .farthestInTime
                ? targetDurationMinutes * 60
                : nil,
            timeBasis: timeBasis,
            route: routeSnapshot,
            gpsRequired:
                usesSpecificRoute ? true : gpsRequired,
            minimumRouteMatchPercent:
                usesSpecificRoute
                    ? routeMatchPercent
                    : nil,
            distanceTolerancePercent:
                sport == .running &&
                scoring == .fastestDistance &&
                !usesSpecificRoute
                    ? distanceTolerancePercent
                    : nil,
            startFinishToleranceMeters:
                sport == .running &&
                usesSpecificRoute
                    ? startFinishToleranceMeters
                    : nil,
            routeDirection:
                sport == .running &&
                usesSpecificRoute
                    ? routeDirection
                    : nil,
            attemptPolicy:
                sport == .running
                    ? (allowMultipleAttempts
                        ? attemptPolicy
                        : .first)
                    : nil,
            maximumAttempts:
                sport == .running
                    ? (allowMultipleAttempts
                        ? (attemptLimit == 0
                            ? nil
                            : attemptLimit)
                        : 1)
                    : nil,
            allowTreadmill:
                sport == .running &&
                !usesSpecificRoute
                    ? allowTreadmill
                    : nil,
            allowTargetGhost:
                sport == .running &&
                usesSpecificRoute
                    ? allowTargetGhost
                    : nil,
            exerciseName: sport == .strength && scoring != .workoutVolume
                ? exerciseName.trimmingCharacters(in: .whitespacesAndNewlines)
                : nil,
            fixedWeightKilograms: sport == .strength &&
                scoring == .mostReps &&
                requiredWeightEnabled
                ? requiredWeightKg
                : nil,
            heartRateZone:
                sport == .heartRate
                    ? heartRateZone
                    : nil,
            heartRateAggregation:
                sport == .heartRate
                    ? heartRateAggregation
                    : nil,
            summary: resolvedSummary,
            coverArtworkName:
                selectedCoverImageData == nil
                    ? selectedCoverArtworkName
                    : nil,
            coverImageURL: uploadedCoverURL,
            startsAt: startsAt,
            endsAt: hasEnd ? endsAt : nil,
            allowMultipleAttempts: allowMultipleAttempts,
            lockRulesAtStart: true,
            meetup: meetup
        )

        let challenge = ATHLTHChallenge(
            id: challengeID,
            creatorID: session.profile.userID,
            title: resolvedTitle,
            sport: sport,
            participants: [creator] + invitees,
            rules: rules,
            visibility: visibility
        )

        challenges.add(challenge)

        let synced =
            await social.syncChallenge(challenge)

        creatingChallenge = false

        guard synced else {
            challenges.remove(challenge.id)

            if selectedCoverImageData != nil {
                await social.removeChallengeCover(
                    challengeID: challenge.id
                )
            }

            createError =
                social.errorMessage ??
                ATHLTHLocalization.choose(
                    english: "This athlete may not be accepting challenge requests.",
                    norwegian: "Denne brukeren tar kanskje ikke imot challenge-forespørsler."
                )
            return
        }

        await shareChallengeInMessages(
            challenge
        )

        if shareToCommunity {
            _ = await social
                .shareChallengeToCommunity(
                    challenge
                )
        }

        dismiss()
    }

    @MainActor
    private func shareChallengeInMessages(
        _ challenge: ATHLTHChallenge
    ) async {
        guard
            let draft = try? MessageShareDraft(
                kind: .challenge,
                title: challenge.title,
                subtitle:
                    "\(challenge.sport.title) · \(challenge.rules.scoring.title)",
                snapshot: challenge,
                sourceObjectID: challenge.id,
                sourceOwnerID: challenge.creatorID
            )
        else {
            return
        }

        let mutualIDs =
            Set(
                social.mutualFollows
                    .map(\.userID)
            )

        for participant in challenge.participants {
            guard
                participant.state == .invited,
                let recipientID = participant.userID,
                mutualIDs.contains(recipientID)
            else {
                continue
            }

            do {
                let conversationID =
                    try await messaging
                        .openConversation(
                            with: recipientID
                        )

                guard
                    let conversation =
                        messaging.conversation(
                            with: recipientID
                        ),
                    conversation.id == conversationID,
                    conversation.requestStatus == .accepted
                else {
                    continue
                }

                _ = await messaging.send(
                    to: recipientID,
                    conversationID: conversationID,
                    body: nil,
                    attachment: draft
                )
            } catch {
                // The backend challenge invite remains authoritative.
                // Messaging is an additional presentation channel only.
                continue
            }
        }
    }

    private var runningAttemptSummary: String {
        guard sport == .running else {
            return allowMultipleAttempts
                ? "Multiple · best counts"
                : "One"
        }

        guard allowMultipleAttempts else {
            return "One · first counts"
        }

        let limitText =
            attemptLimit == 0
                ? "Unlimited"
                : "Max \(attemptLimit)"

        return "\(limitText) · \(attemptPolicy.shortTitle)"
    }

    private var distanceToleranceDescription: String {
        let target = targetDistanceKm
        let tolerance =
            target * distanceTolerancePercent / 100
        let lower = max(target - tolerance, 0)
        let upper = target + tolerance

        return String(
            format:
                "A %.1f km challenge accepts approximately %.2f–%.2f km.",
            target,
            lower,
            upper
        )
    }

    private func resetRunningAdvancedRules() {
        timeBasis = .elapsed
        distanceTolerancePercent = 2
        routeMatchPercent = 90
        startFinishToleranceMeters = 100
        routeDirection = .sameDirection
        allowMultipleAttempts = true
        attemptPolicy = .best
        attemptLimit = 0
        allowTreadmill = false

        if usesSpecificRoute {
            gpsRequired = true
        } else {
            gpsRequired = true
        }
    }

    private var maximumHeartRateBPM: Int? {
        session.onboardingProfile?.maximumHeartRateBPM
    }

    private func heartRateZonePercentText(
        _ zone: Int
    ) -> String {
        switch zone {
        case 1: return "50–60%"
        case 2: return "60–70%"
        case 3: return "70–80%"
        case 4: return "80–90%"
        default: return "90%+"
        }
    }

    private func heartRateZoneBPMText(
        zone: Int,
        maxHR: Int
    ) -> String {
        let lowerFactor: Double
        let upperFactor: Double

        switch zone {
        case 1:
            lowerFactor = 0.50
            upperFactor = 0.60
        case 2:
            lowerFactor = 0.60
            upperFactor = 0.70
        case 3:
            lowerFactor = 0.70
            upperFactor = 0.80
        case 4:
            lowerFactor = 0.80
            upperFactor = 0.90
        default:
            lowerFactor = 0.90
            upperFactor = 1.00
        }

        let lower = Int(
            ceil(Double(maxHR) * lowerFactor)
        )
        let upper = Int(
            floor(Double(maxHR) * upperFactor)
        )

        return "\(lower)–\(upper) bpm"
    }

    private var allowedRouteDeviationPercent: Double {
        max(0, 100 - routeMatchPercent)
    }

    private var allowedRouteDeviationBinding:
        Binding<Double> {
        Binding(
            get: {
                allowedRouteDeviationPercent
            },
            set: { newValue in
                routeMatchPercent =
                    max(80, min(98, 100 - newValue))
            }
        )
    }

    private func routeRequirementButton(
        title: String,
        subtitle: String,
        icon: String,
        selected: Bool,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.title3)

                Text(title)
                    .font(.subheadline.weight(.bold))

                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(
                        selected
                            ? Color.white.opacity(0.80)
                            : .secondary
                    )
            }
            .foregroundStyle(
                selected ? .white : .primary
            )
            .frame(maxWidth: .infinity, minHeight: 92)
            .background(
                selected
                    ? ATHLTHTheme.accent
                    : Color(
                        .secondarySystemGroupedBackground
                    ),
                in: RoundedRectangle(
                    cornerRadius: 20,
                    style: .continuous
                )
            )
            .opacity(disabled ? 0.42 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private func challengeRegion(
        for route: TrainingRoute
    ) -> MKCoordinateRegion {
        let coordinates =
            route.coordinates.map(\.coordinate)

        guard let first = coordinates.first else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(
                    latitude: 59.91,
                    longitude: 10.75
                ),
                span: MKCoordinateSpan(
                    latitudeDelta: 0.08,
                    longitudeDelta: 0.08
                )
            )
        }

        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)

        let minLatitude =
            latitudes.min() ?? first.latitude
        let maxLatitude =
            latitudes.max() ?? first.latitude
        let minLongitude =
            longitudes.min() ?? first.longitude
        let maxLongitude =
            longitudes.max() ?? first.longitude

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude:
                    (minLatitude + maxLatitude) / 2,
                longitude:
                    (minLongitude + maxLongitude) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: max(
                    (maxLatitude - minLatitude) * 1.35,
                    0.01
                ),
                longitudeDelta: max(
                    (maxLongitude - minLongitude) * 1.35,
                    0.01
                )
            )
        )
    }

    private func sportButton(
        _ option: ATHLTHChallengeSport
    ) -> some View {
        let selected = sport == option

        return Button {
            sport = option
        } label: {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 10) {
                    Image(systemName: option.systemImage)
                        .font(.system(size: 24, weight: .semibold))

                    Text(option.title)
                        .font(.subheadline.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
                .foregroundStyle(
                    selected
                        ? Color.white
                        : clubForest
                )
                .frame(maxWidth: .infinity)
                .frame(height: 112)
                .background(
                    selected
                        ? AnyShapeStyle(
                            LinearGradient(
                                colors: [
                                    clubForest,
                                    clubEmerald
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        : AnyShapeStyle(
                            Color.white.opacity(0.96)
                        ),
                    in: RoundedRectangle(
                        cornerRadius: 22,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: 22,
                        style: .continuous
                    )
                    .stroke(
                        selected
                            ? clubEmerald.opacity(0.58)
                            : Color.primary.opacity(0.07),
                        lineWidth: selected ? 1.1 : 0.8
                    )
                }

                if selected {
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                        .foregroundStyle(clubForest)
                        .frame(width: 26, height: 26)
                        .background(
                            Color.white.opacity(0.94),
                            in: Circle()
                        )
                        .padding(9)
                }
            }
            .shadow(
                color: Color.black.opacity(
                    selected ? 0.07 : 0.025
                ),
                radius: 10,
                y: 4
            )
        }
        .buttonStyle(.plain)
    }

    private func numberField(
        title: String,
        suffix: String,
        value: Binding<Double>
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(
                "0",
                value: value,
                format: .number.precision(.fractionLength(0...3))
            )
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .frame(width: 100)

            Text(suffix)
                .foregroundStyle(.secondary)
        }
        .padding()
        .challengeCard()
    }

    private func participantRow(
        name: String,
        username: String,
        state: String
    ) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(ATHLTHTheme.accent.opacity(0.10))
                .frame(width: 42, height: 42)
                .overlay {
                    Image(systemName: "person.fill")
                        .foregroundStyle(ATHLTHTheme.accent)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline.weight(.semibold))
                if !username.isEmpty && name != "@\(username)" {
                    Text("@\(username)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(state)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding()
        .challengeCard()
    }

    private func scoringSubtitle(_ scoring: ATHLTHChallengeScoring) -> String {
        switch scoring {
        case .fastestDistance:
            return ATHLTHLocalization.choose(
                english: "Fastest qualifying time wins. Choose your course setup in the next step.",
                norwegian: "Raskeste godkjente tid vinner. Velg løypeoppsett i neste steg."
            )
        case .farthestInTime:
            return ATHLTHLocalization.choose(
                english: "Choose a time window. Furthest verified distance wins.",
                norwegian: "Registrer aktivitet innenfor en tidsperiode. Lengste godkjente distanse vinner."
            )
        case .mostDistance:
            return ATHLTHLocalization.choose(
                english: "Every qualifying run adds to the total.",
                norwegian: "Hver godkjente løpetur legges til totalen. Lengst samlet distanse vinner."
            )
        case .fastestRoute:
            return ATHLTHLocalization.choose(
                english: "Fastest qualifying time on a specific route.",
                norwegian: "Raskeste godkjente tid på en bestemt rute vinner."
            )
        case .heaviestWeight:
            return ATHLTHLocalization.choose(
                english: "Highest qualifying completed set wins.",
                norwegian: "Tyngste godkjente fullførte sett vinner."
            )
        case .mostReps:
            return ATHLTHLocalization.choose(
                english: "Most reps, optionally at a required weight.",
                norwegian: "Flest repetisjoner vinner, eventuelt med et valgt minimum av vekt."
            )
        case .exerciseVolume:
            return ATHLTHLocalization.choose(
                english: "Highest reps × weight volume for one exercise.",
                norwegian: "Høyest repetisjoner × vekt for én øvelse vinner."
            )
        case .workoutVolume:
            return ATHLTHLocalization.choose(
                english: "Highest total volume in one strength workout.",
                norwegian: "Høyest totalvolum i én styrkeøkt vinner."
            )
        case .heartRateZoneTime:
            return ATHLTHLocalization.choose(
                english: "Compete on verified time spent in a personal heart-rate zone.",
                norwegian: "Konkurrer på verifisert tid i en personlig pulssone."
            )
        }
    }

    private func scoringIcon(
        _ scoring: ATHLTHChallengeScoring
    ) -> String {
        switch scoring {
        case .fastestDistance, .fastestRoute:
            return "trophy.fill"
        case .farthestInTime:
            return "clock.fill"
        case .mostDistance:
            return "point.topleft.down.to.point.bottomright.curvepath"
        case .heaviestWeight:
            return "dumbbell.fill"
        case .mostReps:
            return "repeat"
        case .exerciseVolume, .workoutVolume:
            return "chart.bar.fill"
        case .heartRateZoneTime:
            return "heart.fill"
        }
    }

    private func reviewRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }
}

private struct ChallengeRouteSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore

    @Binding var selectedRouteID: UUID?

    var body: some View {
        List {
            if session.savedRoutes.isEmpty {
                ContentUnavailableView(
                    "No saved routes",
                    systemImage: "map",
                    description: Text(
                        "Create a route first, then return here to use it in the challenge."
                    )
                )
            } else {
                Section("My Routes") {
                    ForEach(session.savedRoutes) { route in
                        Button {
                            selectedRouteID = route.id
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "map.fill")
                                    .foregroundStyle(
                                        ATHLTHTheme.accent
                                    )
                                    .frame(width: 34)

                                VStack(
                                    alignment: .leading,
                                    spacing: 3
                                ) {
                                    Text(route.title)
                                        .font(
                                            .subheadline
                                                .weight(.semibold)
                                        )
                                        .foregroundStyle(.primary)

                                    HStack(spacing: 8) {
                                        Text(
                                            String(
                                                format:
                                                    "%.1f km",
                                                route
                                                    .distanceKilometers
                                            )
                                        )

                                        if let elevation =
                                            route
                                                .elevationGainMeters {
                                            Text(
                                                "· \(Int(elevation.rounded())) m ↑"
                                            )
                                        }
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Image(
                                    systemName:
                                        selectedRouteID ==
                                            route.id
                                            ? "checkmark.circle.fill"
                                            : "circle"
                                )
                                .foregroundStyle(
                                    selectedRouteID ==
                                        route.id
                                        ? ATHLTHTheme.accent
                                        : .secondary
                                )
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section {
                NavigationLink {
                    RunRouteBuilderView()
                } label: {
                    Label(
                        "Create New Route",
                        systemImage: "plus.circle.fill"
                    )
                }
            }
        }
        .navigationTitle("Choose Route")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct MeetupLocationPicker: View {
    @Binding var coordinate: CLLocationCoordinate2D?
    @Binding var position: MapCameraPosition

    var body: some View {
        MapReader { proxy in
            Map(position: $position) {
                if let coordinate {
                    Marker("Meet here", coordinate: coordinate)
                        .tint(ATHLTHTheme.accent)
                }
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .onTapGesture { point in
                if let location = proxy.convert(point, from: .local) {
                    coordinate = location
                }
            }
        }
    }
}

private struct ChallengeReviewCard: View {
    let title: String
    let summary: String?
    let sport: ATHLTHChallengeSport
    let scoring: ATHLTHChallengeScoring
    let verification: ChallengeVerificationPolicy
    let coverArtworkName: String?
    let customImageData: Data?
    let startsAt: Date
    let endsAt: Date?
    let participantCount: Int

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let customImageData,
                   let image = UIImage(data: customImageData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    ChallengeCoverArtworkView(
                        sport: sport,
                        artworkName: coverArtworkName,
                        remoteURL: nil
                    )
                }
            }
            .frame(maxWidth: .infinity)
            .clipped()

            LinearGradient(
                colors: [.clear, .clear, .black.opacity(0.48)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 6) {
                Label("ATHLTH CHALLENGE", systemImage: sport.systemImage)
                    .font(.caption2.bold())
                    .tracking(1.2)

                Text(title)
                    .font(.title2.bold())
                    .lineLimit(2)

                if let summary, !summary.isEmpty {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.86))
                        .lineLimit(2)
                }

                Text("\(scoring.title) · \(verification.title)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.76))

                HStack(spacing: 12) {
                    Label(
                        startsAt.formatted(
                            date: .abbreviated,
                            time: .omitted
                        ),
                        systemImage: "calendar"
                    )

                    if let endsAt {
                        Text("–")
                        Text(
                            endsAt.formatted(
                                date: .abbreviated,
                                time: .omitted
                            )
                        )
                    }

                    Spacer()

                    Label(
                        "\(participantCount)",
                        systemImage: "person.2.fill"
                    )
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.84))
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.24), radius: 4, y: 2)
            .padding()
        }
        .frame(height: 205)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

struct ChallengeDetailView: View {
    @EnvironmentObject private var challenges: ChallengeStore
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var watchConnection: AppleWatchConnectionStore
    @EnvironmentObject private var ghostRace: GhostRaceStore
    @StateObject private var locationStore = ChallengeLocationStore()

    let challengeID: UUID

    @State private var showingManualStrengthAttempt = false
    @State private var showingCancel = false
    @State private var showingChallengeTargetGhost = false

    private var challenge: ATHLTHChallenge? {
        challenges.challenge(id: challengeID)
    }

    private var currentParticipant: ChallengeParticipant? {
        challenge?.participants.first {
            $0.userID == session.profile.userID
        }
    }

    var body: some View {
        Group {
            if let challenge {
                ScrollView {
                    LazyVStack(spacing: 18) {
                        detailHero(challenge)

                        if currentParticipant?.state == .invited {
                            invitationResponseCard(challenge)
                        } else if currentParticipant == nil &&
                                    challenge.visibility == .publicProfile &&
                                    challenge.creatorID != session.profile.userID &&
                                    challenge.status != .completed &&
                                    challenge.status != .cancelled {
                            publicJoinCard(challenge)
                        }

                        if challenge.sport == .heartRate &&
                            session.onboardingProfile?.maximumHeartRateBPM == nil {
                            heartRateProfileRequiredCard
                        }

                        leaderboardCard(challenge)
                        rulesCard(challenge)

                        if challenge.sport == .running,
                           challenge.rules.route != nil,
                           challenge.rules.targetGhostAllowed,
                           challenge.status == .active,
                           (
                               currentParticipant?.state == .creator ||
                               currentParticipant?.state == .accepted
                           ) {
                            targetGhostCard(challenge)
                        }

                        if let meetup = challenge.rules.meetup {
                            meetupCard(challenge, meetup: meetup)
                        }

                        participantsCard(challenge)
                        attemptsCard(challenge)

                        if challenge.sport == .strength,
                           challenge.rules.verificationPolicy.allowsManual,
                           challenge.status == .active {
                            Button {
                                showingManualStrengthAttempt = true
                            } label: {
                                Label(
                                    ATHLTHLocalization.choose(
                                        english: "Submit Manual Strength Result",
                                        norwegian: "Registrer styrkeresultat"
                                    ),
                                    systemImage: "hand.tap.fill"
                                )
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(ATHLTHTheme.vitality)
                            .controlSize(.large)
                        }

                        if challenge.creatorID == session.profile.userID &&
                           challenge.status != .completed &&
                           challenge.status != .cancelled {
                            Button(
                                ATHLTHLocalization.choose(
                                    english: "Cancel Challenge",
                                    norwegian: "Avlys challenge"
                                ),
                                role: .destructive
                            ) {
                                showingCancel = true
                            }
                            .font(.caption.weight(.semibold))
                        }
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
                .navigationTitle("Challenge")
                .navigationBarTitleDisplayMode(.inline)
                .task {
                    challenges.refreshStatuses()

                    if challenge.sport == .heartRate,
                       let maxHR =
                        session.onboardingProfile?.maximumHeartRateBPM {
                        await challenges.syncHeartRateHealthWorkouts(
                            health: health,
                            userID: session.profile.userID,
                            displayName: session.profile.displayName,
                            maximumHeartRateBPM: maxHR
                        )
                    }
                }
                .onChange(
                    of: session.onboardingProfile?.maximumHeartRateBPM
                ) { _, maxHR in
                    guard challenge.sport == .heartRate,
                          let maxHR
                    else {
                        return
                    }

                    Task {
                        await challenges.syncHeartRateHealthWorkouts(
                            health: health,
                            userID: session.profile.userID,
                            displayName: session.profile.displayName,
                            maximumHeartRateBPM: maxHR
                        )
                    }
                }
                .sheet(
                    isPresented:
                        $showingChallengeTargetGhost
                ) {
                    if let route =
                        targetGhostRoute(
                            challenge
                        ) {
                        NavigationStack {
                            TargetGhostSetupView(
                                route: route,
                                challengeTitle:
                                    challenge.title
                            )
                        }
                    }
                }
                .sheet(isPresented: $showingManualStrengthAttempt) {
                    if let currentParticipant {
                        ManualStrengthAttemptView(
                            challengeID: challenge.id,
                            participant: currentParticipant
                        )
                    }
                }
                .confirmationDialog(
                    "Cancel this challenge?",
                    isPresented: $showingCancel,
                    titleVisibility: .visible
                ) {
                    Button("Cancel Challenge", role: .destructive) {
                        challenges.cancel(challenge.id)
                    }
                    Button("Keep Challenge", role: .cancel) {}
                }
            } else {
                ContentUnavailableView(
                    "Challenge unavailable",
                    systemImage: "person.2.slash"
                )
            }
        }
    }

    private var heartRateProfileRequiredCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                "Set your maximum heart rate",
                systemImage: "heart.text.square"
            )
            .font(.headline)
            .foregroundStyle(.orange)

            Text(
                "This challenge uses personal heart-rate zones. Your max HR stays private and is used only to calculate your own zone boundaries."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            NavigationLink {
                PersonalHealthProfileView()
            } label: {
                Text("Open Health Profile")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(ATHLTHTheme.accent)
        }
        .padding()
        .challengeCard()
    }

    private func publicJoinCard(
        _ challenge: ATHLTHChallenge
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            Label(
                ATHLTHLocalization.choose(
                    english: "Open challenge",
                    norwegian: "Åpen challenge"
                ),
                systemImage:
                    "person.badge.plus"
            )
            .font(.headline)

            Text(
                ATHLTHLocalization.choose(
                    english:
                        "This public challenge is open to ATHLTH users. Join to enter the leaderboard and submit qualifying results.",
                    norwegian:
                        "Denne offentlige challengen er åpen for ATHLTH-brukere. Bli med for å komme på resultatlisten og registrere tellende resultater."
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Button {
                Task {
                    let joined =
                        await social
                            .joinPublicChallenge(
                                challenge.id
                            )

                    if joined {
                        await social.refresh(
                            challengeStore:
                                challenges
                        )
                    }
                }
            } label: {
                Label(
                    ATHLTHLocalization.choose(
                        english: "Join challenge",
                        norwegian: "Bli med"
                    ),
                    systemImage:
                        "person.crop.circle.badge.plus"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(ATHLTHTheme.accent)
        }
        .padding()
        .challengeCard()
    }

    private func invitationResponseCard(
        _ challenge: ATHLTHChallenge
    ) -> some View {
        ATHLTHCard {
            VStack(
                alignment: .leading,
                spacing: 16
            ) {
                challengeSectionHeader(
                    title:
                        ATHLTHLocalization.choose(
                            english: "You’ve been challenged",
                            norwegian: "Du har blitt utfordret"
                        ),
                    trailing: nil
                )

                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "Accept to join the leaderboard. If you decline, you are removed from this challenge.",
                        norwegian:
                            "Godta for å bli med på leaderboardet. Hvis du avslår, fjernes du fra denne challengen."
                    )
                )
                .font(.subheadline)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
                .fixedSize(
                    horizontal: false,
                    vertical: true
                )

                HStack(spacing: 10) {
                    Button(
                        ATHLTHLocalization.choose(
                            english: "Decline",
                            norwegian: "Avslå"
                        )
                    ) {
                        respondToInvitation(
                            challenge,
                            accept: false
                        )
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)

                    Button(
                        ATHLTHLocalization.choose(
                            english: "Accept Challenge",
                            norwegian: "Godta challenge"
                        )
                    ) {
                        respondToInvitation(
                            challenge,
                            accept: true
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ATHLTHTheme.vitality)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func respondToInvitation(
        _ challenge: ATHLTHChallenge,
        accept: Bool
    ) {
        guard let participant =
                currentParticipant,
              participant.state == .invited
        else {
            return
        }

        challenges.setParticipantState(
            challengeID: challenge.id,
            participantID: participant.id,
            state:
                accept
                    ? .accepted
                    : .declined
        )

        guard let updated =
                challenges.challenge(
                    id: challenge.id
                )
        else {
            return
        }

        Task {
            let synced =
                await social.syncChallenge(
                    updated
                )

            if !synced {
                challenges.setParticipantState(
                    challengeID: challenge.id,
                    participantID:
                        participant.id,
                    state: .invited
                )
            } else {
                await social.markChallengeInviteRead(
                    challengeID: challenge.id
                )
            }
        }
    }

    private func detailHero(
        _ challenge: ATHLTHChallenge
    ) -> some View {
        ZStack(alignment: .bottomLeading) {
            ChallengeCoverArtworkView(
                sport: challenge.sport,
                artworkName: challenge.rules.coverArtworkName,
                remoteURL: challenge.rules.coverImageURL
            )

            LinearGradient(
                colors: [.clear, .clear, .black.opacity(0.50)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("ATHLTH CHALLENGE")
                        .font(.caption2.bold())
                        .tracking(1.5)

                    Spacer()

                    if challenge.rulesAreLocked {
                        Label("LOCKED", systemImage: "lock.fill")
                            .font(.caption2.bold())
                    }
                }

                Spacer()

                Text(challenge.title)
                    .font(.system(size: 31, weight: .bold))
                    .lineLimit(2)

                if let summary = challenge.rules.summary,
                   !summary.isEmpty {
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.86))
                        .lineLimit(2)
                }

                HStack {
                    Label(
                        challenge.rules.scoring.title,
                        systemImage: challenge.sport.systemImage
                    )
                    Spacer()
                    Text(timeText(challenge))
                }
                .font(.caption)
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.24), radius: 5, y: 2)
            .padding(20)
        }
        .frame(height: 250)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func leaderboardCard(_ challenge: ATHLTHChallenge) -> some View {
        let board = challenges.leaderboard(for: challenge.id)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Leaderboard")
                    .font(.title3.bold())
                Spacer()
                Text(
                                ATHLTHLocalization.counted(
                                    board.count,
                                    englishSingular: "competitor",
                                    englishPlural: "competitors",
                                    norwegianSingular: "deltaker",
                                    norwegianPlural: "deltakere"
                                )
                            )
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(board) { entry in
                HStack(spacing: 12) {
                    Text(entry.rank.map { "#\($0)" } ?? "—")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(entry.rank == 1 ? ATHLTHTheme.accent : .secondary)
                        .frame(width: 34)

                    Circle()
                        .fill(ATHLTHTheme.accent.opacity(0.10))
                        .frame(width: 38, height: 38)
                        .overlay {
                            Text(entry.participant.displayName.prefix(1).uppercased())
                                .font(.caption.bold())
                                .foregroundStyle(ATHLTHTheme.accent)
                        }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.participant.displayName)
                            .font(.subheadline.weight(.semibold))

                        if let attempt = entry.bestAttempt {
                            HStack(spacing: 5) {
                                Label(
                                    attempt.verification.title,
                                    systemImage: attempt.verification.systemImage
                                )
                                if entry.attemptCount > 1 {
                                    Text(
                                            "· " +
                                            ATHLTHLocalization.counted(
                                                entry.attemptCount,
                                                englishSingular: "attempt",
                                                englishPlural: "attempts",
                                                norwegianSingular: "forsøk",
                                                norwegianPlural: "forsøk"
                                            )
                                        )
                                }
                            }
                            .font(.caption2)
                            .foregroundStyle(
                                attempt.verification == .manual
                                    ? .orange
                                    : ATHLTHTheme.accent
                            )
                        } else {
                            Text("No result yet")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Text(leaderboardValue(entry, challenge: challenge))
                        .font(.headline.monospacedDigit())
                }
                .padding(.vertical, 4)

                if entry.id != board.last?.id {
                    Divider().opacity(0.45)
                }
            }
        }
        .padding()
        .challengeCard()
    }

    private func targetGhostCard(
        _ challenge: ATHLTHChallenge
    ) -> some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(
                        systemName:
                            "timer.circle.fill"
                    )
                    .font(.title2)
                    .foregroundStyle(
                        ATHLTHTheme.vitality
                    )

                    VStack(
                        alignment: .leading,
                        spacing: 3
                    ) {
                        Text("Target Ghost")
                            .font(.headline)

                        Text(
                            "Set your own finish time and follow a synthetic pacer around the challenge route."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()
                }

                Button {
                    showingChallengeTargetGhost = true
                } label: {
                    Label(
                        "Set target time",
                        systemImage:
                            "figure.run"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(ATHLTHTheme.vitality)
                .disabled(
                    settings.trainingDeviceProvider !=
                        .appleWatch ||
                    !watchConnection.isReady
                )
            }
        }
    }

    private func targetGhostRoute(
        _ challenge: ATHLTHChallenge
    ) -> TrainingRoute? {
        guard let snapshot =
                challenge.rules.route,
              snapshot.coordinates.count >= 2
        else {
            return nil
        }

        return TrainingRoute(
            id:
                snapshot.routeID ??
                challenge.id,
            ownerID:
                challenge.creatorID,
            title:
                snapshot.title,
            visibility:
                challenge.visibility,
            coordinates:
                snapshot.coordinates,
            distanceKilometers:
                snapshot.distanceKilometers,
            elevationGainMeters: nil,
            importedFilename: nil,
            createdAt:
                challenge.createdAt,
            startName:
                "Challenge start",
            endName:
                "Challenge finish",
            expectedTravelTimeSeconds:
                nil,
            routeSource:
                "challenge_target_ghost",
            sharedSourceOwnerID:
                challenge.creatorID,
            sharedSourceRouteID:
                snapshot.routeID
        )
    }

    private func rulesCard(_ challenge: ATHLTHChallenge) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text("Rules")
                    .font(.headline)
                Spacer()
                Label(
                    challenge.rulesAreLocked ? "Locked" : "Locks at start",
                    systemImage: challenge.rulesAreLocked ? "lock.fill" : "lock.open.fill"
                )
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            }

            ruleRow("Scoring", challenge.rules.scoring.title)
            ruleRow("Verification", challenge.rules.verificationPolicy.title)

            if let target = challenge.rules.targetDistanceMeters {
                ruleRow("Distance", String(format: "%.2f km", target / 1_000))
            }

            if let duration = challenge.rules.targetDurationSeconds {
                ruleRow("Time", challengeDuration(duration))
            }

            if let route = challenge.rules.route {
                ruleRow("Route", route.title)
                ruleRow(
                    "Match required",
                    "\(Int(challenge.rules.minimumRouteMatchPercent ?? 90))%"
                )

                if let tolerance =
                    challenge.rules.startFinishToleranceMeters {
                    ruleRow(
                        "Start/finish",
                        "Within \(Int(tolerance)) m"
                    )
                }

                if let direction =
                    challenge.rules.routeDirection {
                    ruleRow(
                        "Direction",
                        direction.title
                    )
                }

                ruleRow(
                    "Target ghost",
                    challenge.rules.targetGhostAllowed
                        ? "Allowed"
                        : "Disabled by creator"
                )
            } else if challenge.sport == .running {
                ruleRow("Course", "Run Anywhere")

                if let tolerance =
                    challenge.rules.distanceTolerancePercent,
                   challenge.rules.scoring == .fastestDistance {
                    ruleRow(
                        "Distance tolerance",
                        "±\(tolerance.formatted(.number.precision(.fractionLength(0...1))))%"
                    )
                }

                if let allowTreadmill =
                    challenge.rules.allowTreadmill {
                    ruleRow(
                        "Treadmill",
                        allowTreadmill
                            ? "Allowed"
                            : "Not allowed"
                    )
                }
            }

            if challenge.sport == .running {
                ruleRow(
                    "Timing",
                    challenge.rules.timeBasis.title
                )
                ruleRow(
                    "GPS",
                    challenge.rules.gpsRequired
                        ? "Required"
                        : "Optional"
                )

                let attemptPolicy =
                    challenge.rules.attemptPolicy ??
                    .best
                let maxAttempts =
                    challenge.rules.maximumAttempts

                if challenge.rules.allowMultipleAttempts {
                    ruleRow(
                        "Attempt policy",
                        attemptPolicy.title
                    )
                    ruleRow(
                        "Attempt limit",
                        maxAttempts.map(String.init)
                            ?? "Unlimited"
                    )
                } else {
                    ruleRow("Attempts", "One")
                }
            }

            if challenge.sport == .heartRate {
                let zone = min(
                    max(challenge.rules.heartRateZone ?? 5, 1),
                    5
                )
                ruleRow("Zone", "Zone \(zone)")
                ruleRow(
                    "Zone range",
                    challengeHeartRateZonePercentText(zone)
                )
                ruleRow(
                    "Leaderboard",
                    (
                        challenge.rules.heartRateAggregation ??
                        .totalChallenge
                    ).title
                )
                ruleRow(
                    "Heart-rate source",
                    "Verified Apple Health"
                )
            }

            if let exercise = challenge.rules.exerciseName {
                ruleRow("Exercise", exercise)
            }

            if let required = challenge.rules.fixedWeightKilograms {
                ruleRow("Required weight", String(format: "%.1f kg", required))
            }

            ruleRow("Starts", challenge.rules.startsAt.formatted(date: .abbreviated, time: .shortened))

            if let endsAt = challenge.rules.endsAt {
                ruleRow("Ends", endsAt.formatted(date: .abbreviated, time: .shortened))
            }
        }
        .padding()
        .challengeCard()
    }

    private func meetupCard(
        _ challenge: ATHLTHChallenge,
        meetup: ChallengeMeetup
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Meet & Train", systemImage: "mappin.and.ellipse")
                    .font(.headline)
                Spacer()
                Text(meetup.scheduledAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(meetup.placeName)
                .font(.title3.weight(.semibold))

            Map(
                initialPosition: .region(
                    MKCoordinateRegion(
                        center: CLLocationCoordinate2D(
                            latitude: meetup.latitude,
                            longitude: meetup.longitude
                        ),
                        span: MKCoordinateSpan(
                            latitudeDelta: 0.012,
                            longitudeDelta: 0.012
                        )
                    )
                )
            ) {
                Marker(
                    meetup.placeName,
                    coordinate: CLLocationCoordinate2D(
                        latitude: meetup.latitude,
                        longitude: meetup.longitude
                    )
                )
                .tint(ATHLTHTheme.accent)
            }
            .frame(height: 170)
            .clipShape(RoundedRectangle(cornerRadius: 16))

            if let participant = currentParticipant {
                let checkIn = challenge.checkIns.first {
                    $0.participantID == participant.id
                }

                if let checkIn {
                    Label(
                        checkIn.verifiedNearMeetup
                            ? "Checked in · location verified"
                            : "Checked in",
                        systemImage: checkIn.verifiedNearMeetup
                            ? "checkmark.seal.fill"
                            : "checkmark.circle.fill"
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.accent)
                } else {
                    Button {
                        Task {
                            let location = await locationStore.requestCurrentLocation()
                            challenges.checkIn(
                                challengeID: challenge.id,
                                participantID: participant.id,
                                currentLocation: location
                            )
                        }
                    } label: {
                        HStack {
                            if locationStore.isLocating {
                                ProgressView()
                                    .tint(.white)
                            }
                            Label(
                                locationStore.isLocating ? "Checking location…" : "I'm here",
                                systemImage: "mappin.circle.fill"
                            )
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ATHLTHTheme.accent)
                    .disabled(locationStore.isLocating)
                }
            }

            if let error = locationStore.lastError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            Text("Check-in is explicit. ATHLTH requests a one-time location only when you press “I'm here”; it does not continuously expose your live location to other participants.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
        .challengeCard()
    }

    private func participantsCard(_ challenge: ATHLTHChallenge) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Participants")
                .font(.headline)

            ForEach(challenge.participants) { participant in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(participant.displayName)
                            .font(.subheadline.weight(.semibold))
                        if let username = participant.username {
                            Text("@\(username)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Text(participantState(participant.state))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(
                            participant.state == .accepted ||
                            participant.state == .creator
                                ? ATHLTHTheme.accent
                                : .secondary
                        )
                }
            }
        }
        .padding()
        .challengeCard()
    }

    private func attemptsCard(_ challenge: ATHLTHChallenge) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Attempts")
                .font(.headline)

            if challenge.attempts.isEmpty {
                Text("No attempts yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(challenge.attempts.sorted { $0.submittedAt > $1.submittedAt }.prefix(10)) { attempt in
                    HStack(alignment: .top, spacing: 10) {
                        Image(
                            systemName: attempt.isEligible
                                ? attempt.verification.systemImage
                                : "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(
                            attempt.isEligible
                                ? (attempt.verification == .manual ? .orange : ATHLTHTheme.accent)
                                : .orange
                        )
                        .frame(width: 24)

                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(attempt.participantName)
                                    .font(.subheadline.weight(.semibold))
                                Text("·")
                                    .foregroundStyle(.secondary)
                                Text(attempt.verification.title)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(
                                        attempt.verification == .manual
                                            ? .orange
                                            : ATHLTHTheme.accent
                                    )
                            }

                            Text(attempt.detail)
                                .font(.caption)

                            if let reason = attempt.ineligibilityReason {
                                Text(reason)
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }

                            if let match = attempt.routeMatchPercent {
                                Text("Route match \(match, specifier: "%.0f")%")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        Text(attempt.submittedAt, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Divider().opacity(0.45)
                }
            }
        }
        .padding()
        .challengeCard()
    }

    private func leaderboardValue(
        _ entry: ChallengeLeaderboardEntry,
        challenge: ATHLTHChallenge
    ) -> String {
        guard let score = entry.score else { return "—" }

        switch challenge.rules.scoring {
        case .fastestDistance, .fastestRoute:
            return challengeDuration(score)
        case .farthestInTime, .mostDistance:
            return String(format: "%.2f km", score / 1_000)
        case .heaviestWeight:
            return String(format: "%.1f kg", score)
        case .mostReps:
            return "\(Int(score.rounded())) reps"
        case .exerciseVolume, .workoutVolume:
            return String(format: "%.0f kg", score)
        case .heartRateZoneTime:
            return challengeDuration(score)
        }
    }

    private func challengeHeartRateZonePercentText(
        _ zone: Int
    ) -> String {
        switch zone {
        case 1: return "50–60% of personal max HR"
        case 2: return "60–70% of personal max HR"
        case 3: return "70–80% of personal max HR"
        case 4: return "80–90% of personal max HR"
        default: return "90%+ of personal max HR"
        }
    }

    private func ruleRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }

    private func timeText(_ challenge: ATHLTHChallenge) -> String {
        if challenge.status == .active, let end = challenge.rules.endsAt {
            return end.formatted(.relative(presentation: .named))
        }

        if challenge.status == .upcoming || challenge.status == .invited {
            return "Starts " + challenge.rules.startsAt.formatted(date: .abbreviated, time: .shortened)
        }

        return challenge.status.rawValue.capitalized
    }

    private func participantState(_ state: ChallengeParticipantState) -> String {
        switch state {
        case .creator: return "Creator"
        case .invited: return "Invited"
        case .accepted: return "Accepted"
        case .declined: return "Declined"
        case .withdrawn:
            return ATHLTHLocalization.choose(
                english: "Withdrawn",
                norwegian: "Trukket tilbake"
            )
        }
    }
}

struct ManualStrengthAttemptView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var challenges: ChallengeStore

    let challengeID: UUID
    let participant: ChallengeParticipant

    @State private var weightKg = 0.0
    @State private var reps = 0
    @State private var volumeKg = 0.0
    @State private var note = ""
    @State private var error: String?

    private var challenge: ATHLTHChallenge? {
        challenges.challenge(id: challengeID)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let challenge {
                    Section("Result") {
                        switch challenge.rules.scoring {
                        case .heaviestWeight:
                            numericField(
                                title: "Weight",
                                suffix: "kg",
                                value: $weightKg
                            )
                            Stepper(
                                "Reps: \(reps)",
                                value: $reps,
                                in: 0...200
                            )

                        case .mostReps:
                            if let fixed = challenge.rules.fixedWeightKilograms {
                                LabeledContent("Required weight") {
                                    Text("\(fixed, specifier: "%.1f") kg")
                                }
                            } else {
                                numericField(
                                    title: "Weight",
                                    suffix: "kg",
                                    value: $weightKg
                                )
                            }

                            Stepper(
                                "Reps: \(reps)",
                                value: $reps,
                                in: 0...500
                            )

                        case .exerciseVolume, .workoutVolume:
                            numericField(
                                title: "Total volume",
                                suffix: "kg",
                                value: $volumeKg
                            )

                        default:
                            EmptyView()
                        }
                    }

                    Section("Manual verification") {
                        Label("Manual result", systemImage: "hand.tap.fill")
                            .foregroundStyle(.orange)

                        Text("This attempt will be visible in the leaderboard with a Manual label.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        TextField("Note or context (optional)", text: $note, axis: .vertical)
                    }
                }

                if let error {
                    Section {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Submit Result")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") {
                        submit()
                    }
                }
            }
        }
    }

    private func numericField(
        title: String,
        suffix: String,
        value: Binding<Double>
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(
                "0",
                value: value,
                format: .number.precision(.fractionLength(0...2))
            )
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .frame(width: 100)
            Text(suffix)
                .foregroundStyle(.secondary)
        }
    }

    private var effectiveWeight: Double? {
        guard let challenge else {
            return weightKg > 0 ? weightKg : nil
        }

        if challenge.rules.scoring == .mostReps,
           let fixed = challenge.rules.fixedWeightKilograms {
            return fixed
        }

        return weightKg > 0 ? weightKg : nil
    }

    private func submit() {
        do {
            try challenges.submitManualStrengthAttempt(
                challengeID: challengeID,
                participantID: participant.id,
                participantName: participant.displayName,
                weightKilograms: effectiveWeight,
                reps: reps > 0 ? reps : nil,
                volumeKilograms: volumeKg > 0 ? volumeKg : nil,
                note: note
            )
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private func challengeDuration(_ value: TimeInterval) -> String {
    let seconds = max(Int(value.rounded()), 0)
    let hours = seconds / 3_600
    let minutes = (seconds % 3_600) / 60
    let remaining = seconds % 60

    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, remaining)
    }

    return String(format: "%d:%02d", minutes, remaining)
}

private extension View {
    func challengeCard() -> some View {
        self
            .background(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.98),
                        Color(
                            red: 0.91,
                            green: 0.94,
                            blue: 0.98
                        )
                        .opacity(0.42)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(
                    cornerRadius: 20,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 20,
                    style: .continuous
                )
                .stroke(
                    Color(
                        red: 0.79,
                        green: 0.83,
                        blue: 0.90
                    )
                    .opacity(0.50),
                    lineWidth: 0.8
                )
            }
            .shadow(
                color: Color.black.opacity(0.025),
                radius: 8,
                y: 3
            )
    }

    func challengeHint() -> some View {
        self
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ATHLTHTheme.accent.opacity(0.06),
                in: RoundedRectangle(cornerRadius: 14)
            )
    }
}

private extension Double {
    var cleanChallengeNumber: String {
        if abs(self - rounded()) < 0.001 {
            return String(Int(rounded()))
        }
        return String(format: "%.1f", self)
    }
}
