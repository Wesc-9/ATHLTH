import SwiftUI
import UIKit

struct CommunityFriendsVsFriendsCard: View {
    let currentUserID: UUID
    let currentDisplayName: String
    let currentAvatarURL: URL?
    let friends: [SocialProfileCard]
    let feed: [SocialFeedItem]
    let ownWorkouts: [WorkoutSummary]

    private struct Entry: Identifiable {
        let id: UUID
        let name: String
        let avatarURL: URL?
        let score: Double
        let isCurrentUser: Bool
    }

    private var entries: [Entry] {
        let threshold = Calendar.current.date(
            byAdding: .day,
            value: -7,
            to: Date()
        ) ?? .distantPast

        var result: [Entry] = [
            Entry(
                id: currentUserID,
                name:
                    currentDisplayName.isEmpty
                        ? "You"
                        : currentDisplayName,
                avatarURL: currentAvatarURL,
                score:
                    ownWorkouts
                    .filter {
                        $0.startDate >= threshold &&
                        $0.activity == .running
                    }
                    .compactMap(\.distanceMeters)
                    .reduce(0, +) / 1_000,
                isCurrentUser: true
            )
        ]

        for friend in friends {
            let activities = feed.filter {
                $0.actor.userID == friend.userID &&
                $0.activity.createdAt >= threshold &&
                $0.activity.kind == "workout"
            }

            result.append(
                Entry(
                    id: friend.userID,
                    name: friend.resolvedName,
                    avatarURL:
                        friend.avatarURL.flatMap(URL.init(string:)),
                    score: activities.reduce(0) {
                        $0 + runningKilometers($1.activity)
                    },
                    isCurrentUser: false
                )
            )
        }

        return result
            .sorted {
                if $0.score == $1.score {
                    return $0.name
                        .localizedCaseInsensitiveCompare(
                            $1.name
                        ) == .orderedAscending
                }
                return $0.score > $1.score
            }
            .prefix(4)
            .map { $0 }
    }

    var body: some View {
        ATHLTHCard {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Friends vs Friends")
                        .font(.title3.weight(.bold))

                    Text("Your training circle · last 7 days")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !friends.isEmpty {
                    NavigationLink {
                        CommunityFriendsVsFriendsDetailView(
                            currentUserID: currentUserID,
                            currentDisplayName: currentDisplayName,
                            currentAvatarURL: currentAvatarURL,
                            friends: friends
                        )
                    } label: {
                        Text("Matchups")
                            .font(.caption.weight(.semibold))
                    }
                }
            }

            if friends.isEmpty {
                NavigationLink {
                    SocialHubView(initialTab: .discover)
                } label: {
                    HStack(spacing: 12) {
                        Image(
                            systemName:
                                "person.2.badge.plus"
                        )
                        .font(.title3)
                        .foregroundStyle(
                            ATHLTHTheme.accentDeep
                        )
                        .frame(
                            width: 42,
                            height: 42
                        )
                        .background(
                            ATHLTHTheme.accentSoft,
                            in: RoundedRectangle(
                                cornerRadius: 13,
                                style: .continuous
                            )
                        )

                        VStack(
                            alignment: .leading,
                            spacing: 3
                        ) {
                            Text(
                                "Follow each other to compete"
                            )
                            .font(
                                .subheadline
                                    .weight(.semibold)
                            )
                            .foregroundStyle(
                                ATHLTHTheme.primaryText
                            )

                            Text(
                                "Mutual follows unlock private head-to-head training matchups."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                        }

                        Spacer()

                        Image(
                            systemName:
                                "chevron.right"
                        )
                        .font(.caption.bold())
                        .foregroundStyle(.tertiary)
                    }
                    .padding(.top, 12)
                }
                .buttonStyle(.plain)
            } else {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(
                        Array(entries.enumerated()),
                        id: \.element.id
                    ) { offset, entry in
                        VStack(spacing: 6) {
                            ZStack(alignment: .topLeading) {
                                CommunityShowcaseAvatar(
                                    url: entry.avatarURL,
                                    fallback: entry.name,
                                    size: 48
                                )

                                Text("\(offset + 1)")
                                    .font(
                                        .system(
                                            size: 9,
                                            weight: .bold
                                        )
                                    )
                                    .foregroundStyle(
                                        offset == 0
                                            ? Color.white
                                            : ATHLTHTheme.primaryText
                                    )
                                    .frame(width: 19, height: 19)
                                    .background(
                                        offset == 0
                                            ? Color.orange
                                            : Color(.systemGray5),
                                        in: Circle()
                                    )
                                    .offset(x: -5, y: -5)
                            }

                            Text(
                                entry.isCurrentUser
                                    ? "You"
                                    : firstName(entry.name)
                            )
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)

                            Text(
                                String(
                                    format: "%.1f km",
                                    entry.score
                                )
                            )
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(
                                ATHLTHTheme.accentDeep
                            )
                            .monospacedDigit()

                            ProgressView(
                                value: entry.score,
                                total: max(topScore, 1)
                            )
                            .tint(
                                offset == 0
                                    ? .orange
                                    : ATHLTHTheme.accentDeep
                            )
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, 16)

                NavigationLink {
                    CommunityFriendsVsFriendsDetailView(
                        currentUserID: currentUserID,
                        currentDisplayName: currentDisplayName,
                        currentAvatarURL: currentAvatarURL,
                        friends: friends
                    )
                } label: {
                    HStack {
                        Label(
                            "Open head-to-head",
                            systemImage:
                                "person.2.gobackward"
                        )
                        .font(
                            .subheadline.weight(
                                .semibold
                            )
                        )

                        Spacer()

                        Image(
                            systemName:
                                "chevron.right"
                        )
                        .font(.caption.bold())
                    }
                    .foregroundStyle(
                        ATHLTHTheme.accentDeep
                    )
                    .padding(.horizontal, 13)
                    .frame(height: 44)
                    .background(
                        ATHLTHTheme.accentSoft,
                        in: RoundedRectangle(
                            cornerRadius: 14,
                            style: .continuous
                        )
                    )
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
        }
    }

    private var topScore: Double {
        entries.map(\.score).max() ?? 0
    }

    private func firstName(
        _ value: String
    ) -> String {
        value.split(separator: " ").first.map(String.init)
            ?? value
    }

    private func runningKilometers(
        _ activity: SocialActivityRecord
    ) -> Double {
        let kind =
            activity.metadata?["kind"]?
                .lowercased() ?? ""

        guard kind.contains("run") ||
                activity.title.lowercased().contains("run")
        else {
            return 0
        }

        if let raw =
            activity.metadata?["distance_meters"],
           let meters = Double(raw) {
            return meters / 1_000
        }

        guard let subtitle = activity.subtitle else {
            return 0
        }

        let parts = subtitle
            .replacingOccurrences(of: ",", with: ".")
            .split(separator: " ")

        for index in parts.indices {
            guard parts[index].lowercased() == "km",
                  index > parts.startIndex,
                  let value =
                    Double(
                        parts[
                            parts.index(before: index)
                        ]
                    )
            else {
                continue
            }

            return value
        }

        return 0
    }
}

private enum CommunityMatchupPeriod:
    String,
    CaseIterable,
    Identifiable {
    case week
    case month
    case allTime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .week: return "7 days"
        case .month: return "30 days"
        case .allTime: return "All-time"
        }
    }

    var threshold: Date? {
        switch self {
        case .week:
            return Calendar.current.date(
                byAdding: .day,
                value: -7,
                to: Date()
            )
        case .month:
            return Calendar.current.date(
                byAdding: .day,
                value: -30,
                to: Date()
            )
        case .allTime:
            return nil
        }
    }
}

private struct CommunityMatchupStats {
    let activityPoints: Double?
    let workouts: Double?
    let runningKilometers: Double?
    let activeMinutes: Double?
    let strengthWorkouts: Double?
    let personalRecords: Double?
    let challenges: Double?

    var calculatedActivityPoints: Double? {
        if let activityPoints {
            return activityPoints
        }

        guard let workouts else {
            return nil
        }

        // Completing a workout always counts. Duration adds a capped bonus
        // when it is available, so hidden/missing duration data does not make
        // an athlete disappear from the points matchup.
        let minutes =
            max(activeMinutes ?? 0, 0)
        let cappedMinutes =
            min(
                minutes,
                max(workouts, 0) * 120
            )

        return
            max(workouts, 0) * 20 +
            cappedMinutes / 5
    }
}

private enum CommunityDirectDuelMetric:
    String,
    CaseIterable,
    Identifiable {
    case workoutCount
    case runningDistance
    case strengthVolume

    var id: String { rawValue }

    var title: String {
        switch self {
        case .workoutCount:
            return ATHLTHLocalization.choose(
                english: "Workouts · count",
                norwegian: "Treningsøkter · antall"
            )
        case .runningDistance:
            return ATHLTHLocalization.choose(
                english: "Running · distance",
                norwegian: "Løping · distanse"
            )
        case .strengthVolume:
            return ATHLTHLocalization.choose(
                english: "Strength · volume",
                norwegian: "Styrke · volum"
            )
        }
    }

    var requestTitle: String {
        switch self {
        case .workoutCount:
            return ATHLTHLocalization.choose(
                english: "H2H · Workouts",
                norwegian: "H2H · Økter"
            )
        case .runningDistance:
            return ATHLTHLocalization.choose(
                english: "H2H · Running",
                norwegian: "H2H · Løping"
            )
        case .strengthVolume:
            return ATHLTHLocalization.choose(
                english: "H2H · Strength",
                norwegian: "H2H · Styrke"
            )
        }
    }

    var subtitle: String {
        switch self {
        case .workoutCount:
            return ATHLTHLocalization.choose(
                english: "Most completed workouts over 7 days",
                norwegian: "Flest gjennomførte treningsøkter på 7 dager"
            )
        case .runningDistance:
            return ATHLTHLocalization.choose(
                english: "Most verified distance over 7 days",
                norwegian: "Flest verifiserte kilometer på 7 dager"
            )
        case .strengthVolume:
            return ATHLTHLocalization.choose(
                english: "Highest verified strength volume over 7 days",
                norwegian: "Høyest verifisert styrkevolum på 7 dager"
            )
        }
    }

    var sport: ATHLTHChallengeSport {
        switch self {
        case .workoutCount:
            // Direct H2H workout count is evaluated by the matchup
            // view across all completed workout types. Running is only
            // used as the transport sport for the shared challenge record.
            return .running
        case .runningDistance:
            return .running
        case .strengthVolume:
            return .strength
        }
    }

    var scoring: ATHLTHChallengeScoring {
        switch self {
        case .workoutCount:
            // The direct matchup calculates count from completed workouts.
            // Keep an existing backend scoring value for challenge transport.
            return .mostDistance
        case .runningDistance:
            return .mostDistance
        case .strengthVolume:
            return .workoutVolume
        }
    }

    var systemImage: String {
        switch self {
        case .workoutCount:
            return "checkmark.circle.fill"
        case .runningDistance:
            return "figure.run"
        case .strengthVolume:
            return "dumbbell.fill"
        }
    }

    func format(
        _ score: Double?
    ) -> String {
        guard let score else {
            return "—"
        }

        switch self {
        case .workoutCount:
            return ATHLTHLocalization.format(
                english: "%d workouts",
                norwegian: "%d økter",
                Int(score.rounded())
            )
        case .runningDistance:
            return String(
                format: "%.1f km",
                score / 1_000
            )
        case .strengthVolume:
            if score >= 1_000 {
                return String(
                    format: "%.1f t",
                    score / 1_000
                )
            }
            return String(
                format: "%.0f kg",
                score
            )
        }
    }
}

private enum CommunityMatchupMetricKind {
    case workouts
    case running
    case activeTime
    case strength
    case personalRecords
    case challenges
}

private enum CommunityMatchupMetricEmphasis {
    case normal
    case highlighted
    case dimmed
}

struct CommunityFriendsVsFriendsDetailView: View {
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var challenges: ChallengeStore

    let currentUserID: UUID
    let currentDisplayName: String
    let currentAvatarURL: URL?
    let friends: [SocialProfileCard]

    @State private var selectedFriendID: UUID?
    @State private var period:
        CommunityMatchupPeriod = .week
    @State private var friendProfile:
        SocialFriendProfile?
    @State private var friendActivities:
        [SocialActivityRecord] = []
    @State private var ownActivities:
        [SocialActivityRecord] = []
    @State private var loadingFriend = false
    @State private var showingChallenge = false
    @State private var showingDirectDuelPicker = false
    @State private var creatingDirectDuel = false
    @State private var directDuelError: String?

    private var selectedFriend: SocialProfileCard? {
        guard let selectedFriendID else {
            return friends.first
        }

        return friends.first {
            $0.userID == selectedFriendID
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if friends.isEmpty {
                    ContentUnavailableView(
                        "No mutual follows yet",
                        systemImage:
                            "person.2.badge.plus",
                        description: Text(
                            "Follow each other to unlock head-to-head matchups."
                        )
                    )
                    .padding(.top, 80)
                } else {
                    friendPicker
                    matchupHero
                    primaryScoreCard
                    periodPicker
                    metricCard
                    contextCard
                    pointsExplainerCard
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 14)
            .padding(.bottom, 36)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(
            ATHLTHPremiumCanvas(
                accent:
                    ATHLTHTheme.accent
                        .opacity(0.12)
            )
        )
        .navigationTitle("Head-to-head")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if selectedFriendID == nil {
                selectedFriendID =
                    friends.first?.userID
            }

            ownActivities =
                await social
                    .loadActivitiesForMatchup(
                        currentUserID
                    )
        }
        .task(id: selectedFriendID) {
            await loadSelectedFriend()
            await social.refresh(
                challengeStore: challenges
            )
        }
        .task(
            id:
                outgoingPendingDirectDuel?
                    .id
        ) {
            guard
                outgoingPendingDirectDuel != nil
            else {
                return
            }

            while !Task.isCancelled,
                  outgoingPendingDirectDuel != nil {
                try? await Task.sleep(
                    for: .seconds(4)
                )

                guard !Task.isCancelled
                else {
                    return
                }

                await social.refresh(
                    challengeStore:
                        challenges
                )
            }
        }
        .refreshable {
            await social.refresh(
                challengeStore: challenges
            )
            await loadSelectedFriend()
        }
        .confirmationDialog(
            ATHLTHLocalization.choose(
                english: "Choose a direct duel",
                norwegian: "Velg direkte duell"
            ),
            isPresented:
                $showingDirectDuelPicker,
            titleVisibility: .visible
        ) {
            ForEach(
                CommunityDirectDuelMetric
                    .allCases
            ) { metric in
                Button(
                    metric.title
                ) {
                    Task {
                        await createDirectDuel(
                            metric
                        )
                    }
                }
            }

            Button(
                ATHLTHLocalization.choose(
                    english: "Cancel",
                    norwegian: "Avbryt"
                ),
                role: .cancel
            ) {}
        } message: {
            Text(
                ATHLTHLocalization.choose(
                    english:
                        "Your friend receives a request. Activity points remain the default until the duel is accepted.",
                    norwegian:
                        "Vennen din får en forespørsel. Aktivitetspoeng er standard helt til duellen er godtatt."
                )
            )
        }
        .alert(
            ATHLTHLocalization.choose(
                english: "Head-to-head",
                norwegian: "Head-to-head"
            ),
            isPresented:
                Binding(
                    get: {
                        directDuelError != nil
                    },
                    set: { shown in
                        if !shown {
                            directDuelError = nil
                        }
                    }
                )
        ) {
            Button("OK") {
                directDuelError = nil
            }
        } message: {
            Text(
                directDuelError ?? ""
            )
        }
        .sheet(
            isPresented:
                $showingChallenge
        ) {
            if let selectedFriend {
                ChallengeCreationView(
                    preselectedFriends: [
                        selectedFriend
                    ]
                )
            }
        }
    }

    private var friendPicker: some View {
        VStack(
            alignment: .leading,
            spacing: 9
        ) {
            Text(
                ATHLTHLocalization.choose(
                    english: "CHOOSE MATCHUP",
                    norwegian: "VELG DUELL"
                )
            )
            .font(.caption2.weight(.bold))
            .tracking(1.2)
            .foregroundStyle(
                ATHLTHTheme.mutedText
            )

            ScrollView(
                .horizontal,
                showsIndicators: false
            ) {
                HStack(spacing: 10) {
                    ForEach(friends) { friend in
                        Button {
                            selectedFriendID =
                                friend.userID
                        } label: {
                            HStack(spacing: 8) {
                                CommunityShowcaseAvatar(
                                    url:
                                        friend.avatarURL
                                            .flatMap(
                                                URL.init(string:)
                                            ),
                                    fallback:
                                        friend.resolvedName,
                                    size: 34
                                )

                                Text(
                                    firstName(
                                        friend
                                            .resolvedName
                                    )
                                )
                                .font(
                                    .caption.weight(
                                        .semibold
                                    )
                                )
                            }
                            .foregroundStyle(
                                selectedFriendID ==
                                    friend.userID
                                    ? Color.white
                                    : ATHLTHTheme
                                        .primaryText
                            )
                            .padding(
                                .horizontal,
                                11
                            )
                            .frame(height: 46)
                            .background(
                                selectedFriendID ==
                                    friend.userID
                                    ? ATHLTHTheme
                                        .accentDeep
                                    : Color.white
                                        .opacity(
                                            0.94
                                        ),
                                in: Capsule()
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var matchupHero: some View {
        VStack(spacing: 16) {
            HStack {
                Label(
                    "HEAD-TO-HEAD",
                    systemImage:
                        "bolt.horizontal.circle.fill"
                )
                .font(.caption.bold())
                .tracking(0.8)
                .foregroundStyle(
                    ATHLTHTheme.vitality
                )

                Spacer()

                Text(
                    activeDirectDuel == nil
                        ? ATHLTHLocalization.choose(
                            english: "ACTIVITY SCORE",
                            norwegian: "AKTIVITETSSCORE"
                        )
                        : ATHLTHLocalization.choose(
                            english: "DIRECT DUEL",
                            norwegian: "DIREKTE DUELL"
                        )
                )
                .font(
                    .system(
                        size: 9,
                        weight: .bold
                    )
                )
                .tracking(0.8)
                .foregroundStyle(
                    ATHLTHTheme.accentDeep
                )
                .padding(
                    .horizontal,
                    9
                )
                .padding(
                    .vertical,
                    5
                )
                .background(
                    Color.white
                        .opacity(0.74),
                    in: Capsule()
                )
            }

            HStack(spacing: 18) {
                matchupPerson(
                    name:
                        currentDisplayName
                            .isEmpty
                            ? "You"
                            : currentDisplayName,
                    avatarURL:
                        currentAvatarURL,
                    label: "YOU"
                )

                VStack(spacing: 7) {
                    Text("VS")
                        .font(
                            .system(
                                size: 18,
                                weight: .black,
                                design: .rounded
                            )
                        )
                        .foregroundStyle(
                            ATHLTHTheme
                                .accentDeep
                        )
                        .frame(
                            width: 48,
                            height: 48
                        )
                        .background(
                            Color.white
                                .opacity(0.82),
                            in: Circle()
                        )
                        .overlay {
                            Circle()
                                .stroke(
                                    ATHLTHTheme
                                        .vitality
                                        .opacity(
                                            0.20
                                        ),
                                    lineWidth: 1
                                )
                        }
                        .shadow(
                            color:
                                ATHLTHTheme
                                    .vitality
                                    .opacity(
                                        0.12
                                    ),
                            radius: 12
                        )

                    Image(
                        systemName:
                            "bolt.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme
                            .premiumGold
                    )
                }

                if let selectedFriend {
                    matchupPerson(
                        name:
                            selectedFriend
                                .resolvedName,
                        avatarURL:
                            selectedFriend
                                .avatarURL
                                .flatMap(
                                    URL.init(string:)
                                ),
                        label: "FRIEND"
                    )
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [
                    Color.white
                        .opacity(0.98),
                    ATHLTHTheme
                        .vitality
                        .opacity(0.075),
                    ATHLTHTheme
                        .accentSoft
                        .opacity(0.42)
                ],
                startPoint:
                    .topLeading,
                endPoint:
                    .bottomTrailing
            ),
            in:
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
                ATHLTHTheme
                    .vitality
                    .opacity(0.14),
                lineWidth: 0.9
            )
        }
        .shadow(
            color:
                Color.black
                    .opacity(0.045),
            radius: 16,
            y: 7
        )
    }

    private var primaryScoreCard:
        some View {
        let mine =
            primaryScoreValues.mine
        let theirs =
            primaryScoreValues.theirs

        return VStack(spacing: 12) {
            HStack {
                VStack(
                    alignment: .leading,
                    spacing: 3
                ) {
                    Text(
                        primaryScoreTitle
                    )
                    .font(
                        .caption.weight(
                            .bold
                        )
                    )
                    .tracking(0.9)
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                    )

                    Text(
                        primaryScoreSubtitle
                    )
                    .font(.caption2)
                    .foregroundStyle(
                        .secondary
                    )
                }

                Spacer()

                if activeDirectDuel != nil {
                    Text(
                        ATHLTHLocalization.choose(
                            english: "ACTIVE DUEL",
                            norwegian: "AKTIV DUELL"
                        )
                    )
                    .font(
                        .system(
                            size: 9,
                            weight: .bold
                        )
                    )
                    .tracking(0.8)
                    .foregroundStyle(
                        ATHLTHTheme
                            .vitality
                    )
                    .padding(
                        .horizontal,
                        8
                    )
                    .padding(
                        .vertical,
                        5
                    )
                    .background(
                        ATHLTHTheme
                            .vitalitySoft,
                        in: Capsule()
                    )
                }
            }

            HStack(
                alignment: .firstTextBaseline
            ) {
                Text(
                    primaryScoreText(
                        mine
                    )
                )
                .font(
                    .system(
                        size: 28,
                        weight: .bold,
                        design: .rounded
                    )
                )
                .monospacedDigit()
                .foregroundStyle(
                    scoreTint(
                        mine,
                        versus: theirs
                    )
                )

                Spacer()

                Text("VS")
                    .font(
                        .caption.weight(
                            .heavy
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                    )

                Spacer()

                Text(
                    primaryScoreText(
                        theirs
                    )
                )
                .font(
                    .system(
                        size: 28,
                        weight: .bold,
                        design: .rounded
                    )
                )
                .monospacedDigit()
                .foregroundStyle(
                    scoreTint(
                        theirs,
                        versus: mine
                    )
                )
            }

            Button {
                showingDirectDuelPicker =
                    true
            } label: {
                HStack(spacing: 8) {
                    if creatingDirectDuel {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(
                            systemName:
                                activeDirectDuel == nil
                                    ? "scope"
                                    : "arrow.triangle.2.circlepath"
                        )
                    }

                    Text(
                        directDuelButtonTitle
                    )
                    .font(
                        .subheadline
                            .weight(.semibold)
                    )

                    Spacer()

                    if !creatingDirectDuel {
                        Image(
                            systemName:
                                "chevron.right"
                        )
                        .font(
                            .caption.bold()
                        )
                    }
                }
                .foregroundStyle(
                    ATHLTHTheme
                        .accentDeep
                )
                .padding(.horizontal, 14)
                .frame(height: 46)
                .background(
                    ATHLTHTheme
                        .accentSoft,
                    in:
                        RoundedRectangle(
                            cornerRadius: 14,
                            style:
                                .continuous
                        )
                )
            }
            .buttonStyle(.plain)
            .disabled(
                selectedFriend == nil ||
                creatingDirectDuel ||
                outgoingPendingDirectDuel != nil
            )

            if let pending =
                    outgoingPendingDirectDuel,
               let metric =
                    directMetric(
                        for: pending
                    ) {
                Label(
                    ATHLTHLocalization.choose(
                        english:
                            "Request sent · waiting for \(firstName(selectedFriend?.resolvedName ?? "friend")) · \(metric.title)",
                        norwegian:
                            "Forespørsel sendt · venter på \(firstName(selectedFriend?.resolvedName ?? "venn")) · \(metric.title)"
                    ),
                    systemImage: "clock.fill"
                )
                .font(.caption)
                .foregroundStyle(
                    ATHLTHTheme
                        .mutedText
                )
            } else if let pending =
                        incomingPendingDirectDuel,
                      let metric =
                        directMetric(
                            for: pending
                        ) {
                Label(
                    ATHLTHLocalization.choose(
                        english:
                            "Incoming request · \(metric.title) · respond in Inbox",
                        norwegian:
                            "Ny forespørsel · \(metric.title) · svar i innboksen"
                    ),
                    systemImage:
                        "tray.fill"
                )
                .font(.caption)
                .foregroundStyle(
                    ATHLTHTheme
                        .premiumGold
                )
            }
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [
                    Color.white
                        .opacity(0.985),
                    activeDirectDuel == nil
                        ? ATHLTHTheme
                            .accentSoft
                            .opacity(0.34)
                        : ATHLTHTheme
                            .vitality
                            .opacity(0.10),
                    Color.white
                        .opacity(0.94)
                ],
                startPoint:
                    .topLeading,
                endPoint:
                    .bottomTrailing
            ),
            in:
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
                activeDirectDuel == nil
                    ? ATHLTHTheme
                        .accentDeep
                        .opacity(0.08)
                    : ATHLTHTheme
                        .vitality
                        .opacity(0.18),
                lineWidth: 0.9
            )
        }
        .shadow(
            color:
                Color.black.opacity(
                    0.04
                ),
            radius: 14,
            y: 6
        )
    }

    private var periodPicker: some View {
        Picker(
            "Period",
            selection: $period
        ) {
            ForEach(
                CommunityMatchupPeriod
                    .allCases
            ) { value in
                Text(value.title)
                    .tag(value)
            }
        }
        .pickerStyle(.segmented)
    }

    private var metricCard: some View {
        let mine = currentStats
        let theirs = friendStats
        let directMetric =
            activeDirectMetric

        return VStack(spacing: 0) {
                matchupHeader

                metricRow(
                    ATHLTHLocalization.choose(
                        english: "Workouts",
                        norwegian: "Økter"
                    ),
                    icon:
                        "figure.run.circle.fill",
                    mine: mine.workouts,
                    theirs: theirs.workouts,
                    format: countText,
                    emphasis:
                        metricEmphasis(
                            for: .workouts
                        )
                )

                Divider()
                    .opacity(
                        directMetric == nil
                            ? 1
                            : 0.36
                    )

                if directMetric ==
                    .runningDistance {
                    metricRow(
                        ATHLTHLocalization.choose(
                            english:
                                "Running · duel",
                            norwegian:
                                "Løping · duell"
                        ),
                        icon: "figure.run",
                        mine:
                            primaryScoreValues
                                .mine
                                .map {
                                    $0 / 1_000
                                },
                        theirs:
                            primaryScoreValues
                                .theirs
                                .map {
                                    $0 / 1_000
                                },
                        format: distanceText,
                        emphasis:
                            .highlighted
                    )
                } else {
                    metricRow(
                        ATHLTHLocalization.choose(
                            english: "Running",
                            norwegian: "Løping"
                        ),
                        icon: "figure.run",
                        mine:
                            mine.runningKilometers,
                        theirs:
                            theirs
                                .runningKilometers,
                        format: distanceText,
                        emphasis:
                            metricEmphasis(
                                for: .running
                            )
                    )
                }

                Divider()
                    .opacity(
                        directMetric == nil
                            ? 1
                            : 0.36
                    )

                metricRow(
                    ATHLTHLocalization.choose(
                        english: "Active time",
                        norwegian: "Aktiv tid"
                    ),
                    icon: "clock.fill",
                    mine:
                        mine.activeMinutes,
                    theirs:
                        theirs.activeMinutes,
                    format: minutesText,
                    emphasis:
                        metricEmphasis(
                            for: .activeTime
                        )
                )

                if period != .allTime ||
                    directMetric ==
                        .strengthVolume {
                    Divider()
                        .opacity(
                            directMetric == nil
                                ? 1
                                : 0.36
                        )

                    if directMetric ==
                        .strengthVolume {
                        metricRow(
                            ATHLTHLocalization.choose(
                                english:
                                    "Strength volume · duel",
                                norwegian:
                                    "Styrkevolum · duell"
                            ),
                            icon:
                                "dumbbell.fill",
                            mine:
                                primaryScoreValues
                                    .mine,
                            theirs:
                                primaryScoreValues
                                    .theirs,
                            format:
                                strengthVolumeText,
                            emphasis:
                                .highlighted
                        )
                    } else {
                        metricRow(
                            ATHLTHLocalization.choose(
                                english: "Strength",
                                norwegian: "Styrke"
                            ),
                            icon:
                                "dumbbell.fill",
                            mine:
                                mine.strengthWorkouts,
                            theirs:
                                theirs
                                    .strengthWorkouts,
                            format: countText,
                            emphasis:
                                metricEmphasis(
                                    for: .strength
                                )
                        )
                    }
                }

                if period != .allTime {
                    Divider()
                        .opacity(
                            directMetric == nil
                                ? 1
                                : 0.36
                        )

                    metricRow(
                        "PRs",
                        icon: "bolt.fill",
                        mine:
                            mine.personalRecords,
                        theirs:
                            theirs
                                .personalRecords,
                        format: countText,
                        emphasis:
                            metricEmphasis(
                                for:
                                    .personalRecords
                            )
                    )

                    Divider()
                        .opacity(
                            directMetric == nil
                                ? 1
                                : 0.36
                        )

                    metricRow(
                        ATHLTHLocalization.choose(
                            english: "Challenges",
                            norwegian: "Challenges"
                        ),
                        icon: "trophy.fill",
                        mine:
                            mine.challenges,
                        theirs:
                            theirs.challenges,
                        format: countText,
                        emphasis:
                            metricEmphasis(
                                for: .challenges
                            )
                    )
                }
            }
        .padding(18)
        .background(
            LinearGradient(
                colors: [
                    Color.white
                        .opacity(0.97),
                    ATHLTHTheme
                        .surfaceStone
                        .opacity(0.72)
                ],
                startPoint:
                    .topLeading,
                endPoint:
                    .bottomTrailing
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
                Color.black.opacity(0.045),
                lineWidth: 0.8
            )
        }
        .shadow(
            color: Color.black.opacity(0.03),
            radius: 12,
            y: 5
        )
    }

    private var matchupHeader: some View {
        HStack {
            Text("YOU")
                .font(.caption2.bold())
                .tracking(1.2)
                .foregroundStyle(
                    ATHLTHTheme.accentDeep
                )

            Spacer()

            Text(period.title.uppercased())
                .font(.caption2.bold())
                .tracking(1.0)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )

            Spacer()

            Text("FRIEND")
                .font(.caption2.bold())
                .tracking(1.2)
                .foregroundStyle(
                    ATHLTHTheme.accentDeep
                )
        }
        .padding(.bottom, 12)
    }

    private var contextCard: some View {
        VStack(
            alignment: .leading,
            spacing: 11
        ) {
                HStack {
                    VStack(
                        alignment: .leading,
                        spacing: 3
                    ) {
                        Text("Keep it going")
                            .font(
                                .headline
                            )

                        Text(
                            "Turn the comparison into a direct challenge."
                        )
                        .font(.caption)
                        .foregroundStyle(
                            .secondary
                        )
                    }

                    Spacer()

                    if loadingFriend {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if period == .allTime &&
                    friendProfile?
                        .performance == nil {
                    Label(
                        "Some all-time metrics are hidden by this athlete’s privacy settings.",
                        systemImage:
                            "lock.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                    )
                }

                Button {
                    showingChallenge = true
                } label: {
                    Label(
                        "Challenge " +
                            firstName(
                                selectedFriend?
                                    .resolvedName ??
                                    "friend"
                            ),
                        systemImage:
                            "trophy.fill"
                    )
                    .font(
                        .subheadline.weight(
                            .bold
                        )
                    )
                    .foregroundStyle(.white)
                    .frame(
                        maxWidth: .infinity
                    )
                    .frame(height: 46)
                    .background(
                        ATHLTHTheme.accentDeep,
                        in: RoundedRectangle(
                            cornerRadius: 15,
                            style: .continuous
                        )
                    )
                }
                .buttonStyle(.plain)
                .disabled(
                    selectedFriend == nil
                )
            }
        .padding(18)
        .background(
            Color.white.opacity(0.94),
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
                Color.black.opacity(0.045),
                lineWidth: 0.8
            )
        }
        .shadow(
            color: Color.black.opacity(0.03),
            radius: 12,
            y: 5
        )
    }

    private var pointsExplainerCard:
        some View {
        ATHLTHCard {
            VStack(
                alignment: .leading,
                spacing: 12
            ) {
                HStack {
                    Label(
                        ATHLTHLocalization.choose(
                            english:
                                "HOW ACTIVITY POINTS WORK",
                            norwegian:
                                "SLIK FÅR DU AKTIVITETSPOENG"
                        ),
                        systemImage:
                            "bolt.fill"
                    )
                    .font(
                        .caption.weight(
                            .bold
                        )
                    )
                    .tracking(0.8)
                    .foregroundStyle(
                        ATHLTHTheme
                            .vitality
                    )

                    Spacer()
                }

                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "Activity points are the default Head-to-head score, so running, strength, walking and other workouts can compete on the same scale.",
                        norwegian:
                            "Aktivitetspoeng er standardscoren i Head-to-head, slik at løping, styrke, gange og andre økter kan konkurrere på samme skala."
                    )
                )
                .font(.subheadline)
                .foregroundStyle(
                    ATHLTHTheme
                        .primaryText
                )
                .fixedSize(
                    horizontal: false,
                    vertical: true
                )

                pointRuleRow(
                    icon:
                        "checkmark.circle.fill",
                    value:
                        "+20",
                    detail:
                        ATHLTHLocalization.choose(
                            english:
                                "points per completed workout",
                            norwegian:
                                "poeng per gjennomført økt"
                        )
                )

                pointRuleRow(
                    icon: "clock.fill",
                    value: "+1",
                    detail:
                        ATHLTHLocalization.choose(
                            english:
                                "point for every 5 active minutes",
                            norwegian:
                                "poeng per 5 aktive minutter"
                        )
                )

                Label(
                    ATHLTHLocalization.choose(
                        english:
                            "The time bonus is capped at 120 active minutes per workout.",
                        norwegian:
                            "Tidsbonusen stopper ved 120 aktive minutter per økt."
                    ),
                    systemImage:
                        "hourglass.bottomhalf.filled"
                )
                .font(.caption)
                .foregroundStyle(
                    ATHLTHTheme
                        .mutedText
                )

                if activeDirectDuel != nil {
                    Divider()

                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "A confirmed direct duel replaces the headline score with the selected category. Activity points are still calculated in the background.",
                            norwegian:
                                "En godkjent direkte duell erstatter hovedscoren med valgt gren. Aktivitetspoengene beregnes fortsatt i bakgrunnen."
                        )
                    )
                    .font(
                        .caption.weight(
                            .semibold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .accentDeep
                    )
                }
            }
        }
        .overlay {
            RoundedRectangle(
                cornerRadius:
                    ATHLTHTheme
                        .cornerRadius,
                style: .continuous
            )
            .stroke(
                ATHLTHTheme
                    .vitality
                    .opacity(0.10),
                lineWidth: 0.8
            )
        }
    }

    private func pointRuleRow(
        icon: String,
        value: String,
        detail: String
    ) -> some View {
        HStack(spacing: 11) {
            Image(
                systemName: icon
            )
            .font(
                .system(
                    size: 14,
                    weight: .bold
                )
            )
            .foregroundStyle(
                ATHLTHTheme.vitality
            )
            .frame(
                width: 34,
                height: 34
            )
            .background(
                ATHLTHTheme
                    .vitalitySoft,
                in:
                    RoundedRectangle(
                        cornerRadius: 11,
                        style:
                            .continuous
                    )
            )

            Text(value)
                .font(
                    .headline
                        .monospacedDigit()
                        .weight(.bold)
                )
                .foregroundStyle(
                    ATHLTHTheme
                        .primaryText
                )
                .frame(
                    width: 42,
                    alignment: .leading
                )

            Text(detail)
                .font(.caption)
                .foregroundStyle(
                    ATHLTHTheme
                        .mutedText
                )

            Spacer(minLength: 0)
        }
    }

    private var directDuelChallenges:
        [ATHLTHChallenge] {
        guard let selectedFriend else {
            return []
        }

        return challenges
            .visibleChallenges
            .filter { challenge in
                guard
                    challenge.status !=
                        .cancelled,
                    challenge.status !=
                        .completed,
                    challenge.rules
                        .headToHeadMetricRaw !=
                        nil
                else {
                    return false
                }

                let userIDs =
                    Set(
                        challenge
                            .participants
                            .compactMap(
                                \.userID
                            )
                    )

                return userIDs.contains(
                    currentUserID
                ) &&
                    userIDs.contains(
                        selectedFriend.userID
                    )
            }
            .sorted {
                $0.createdAt >
                    $1.createdAt
            }
    }

    private var activeDirectDuel:
        ATHLTHChallenge? {
        guard let selectedFriend else {
            return nil
        }

        return directDuelChallenges
            .first { challenge in
                let mine =
                    challenge.participants
                        .first {
                            $0.userID ==
                                currentUserID
                        }
                let theirs =
                    challenge.participants
                        .first {
                            $0.userID ==
                                selectedFriend
                                    .userID
                        }

                return
                    (mine?.state ==
                        .creator ||
                     mine?.state ==
                        .accepted) &&
                    (theirs?.state ==
                        .creator ||
                     theirs?.state ==
                        .accepted)
            }
    }

    private var outgoingPendingDirectDuel:
        ATHLTHChallenge? {
        guard let selectedFriend else {
            return nil
        }

        return directDuelChallenges
            .first { challenge in
                challenge.creatorID ==
                    currentUserID &&
                challenge.participants
                    .contains {
                        $0.userID ==
                            selectedFriend
                                .userID &&
                        $0.state ==
                            .invited
                    }
            }
    }

    private var incomingPendingDirectDuel:
        ATHLTHChallenge? {
        guard let selectedFriend else {
            return nil
        }

        return directDuelChallenges
            .first { challenge in
                challenge.creatorID ==
                    selectedFriend
                        .userID &&
                challenge.participants
                    .contains {
                        $0.userID ==
                            currentUserID &&
                        $0.state ==
                            .invited
                    }
            }
    }

    private var primaryScoreValues:
        (mine: Double?, theirs: Double?) {
        guard let duel =
                activeDirectDuel
        else {
            return (
                currentStats
                    .calculatedActivityPoints,
                friendStats
                    .calculatedActivityPoints
            )
        }

        let leaderboard =
            challenges.leaderboard(
                for: duel.id
            )

        return (
            leaderboard
                .first {
                    $0.participant
                        .userID ==
                        currentUserID
                }?
                .score,
            leaderboard
                .first {
                    $0.participant
                        .userID ==
                        selectedFriend?
                            .userID
                }?
                .score
        )
    }

    private var primaryScoreTitle:
        String {
        guard let duel =
                activeDirectDuel,
              let metric =
                directMetric(
                    for: duel
                )
        else {
            return ATHLTHLocalization.choose(
                english:
                    "ACTIVITY POINTS",
                norwegian:
                    "AKTIVITETSPOENG"
            )
        }

        return metric.title
            .uppercased()
    }

    private var primaryScoreSubtitle:
        String {
        if let duel =
                activeDirectDuel,
           let endsAt =
                duel.rules.endsAt {
            return ATHLTHLocalization.choose(
                english:
                    "Direct duel · until \(endsAt.formatted(date: .abbreviated, time: .omitted))",
                norwegian:
                    "Direkte duell · til \(endsAt.formatted(date: .abbreviated, time: .omitted))"
            )
        }

        return ATHLTHLocalization.choose(
            english:
                "\(period.title) · all workout types count",
            norwegian:
                "\(period.title) · alle treningsformer teller"
        )
    }

    private var activeDirectMetric:
        CommunityDirectDuelMetric? {
        guard let duel =
                activeDirectDuel
        else {
            return nil
        }

        return directMetric(
            for: duel
        )
    }

    private func metricEmphasis(
        for kind:
            CommunityMatchupMetricKind
    ) -> CommunityMatchupMetricEmphasis {
        guard let metric =
                activeDirectMetric
        else {
            return .normal
        }

        switch (metric, kind) {
        case (
            .runningDistance,
            .running
        ):
            return .highlighted

        case (
            .strengthVolume,
            .strength
        ):
            return .highlighted

        default:
            return .dimmed
        }
    }

    private var directDuelButtonTitle:
        String {
        if outgoingPendingDirectDuel != nil {
            return ATHLTHLocalization.choose(
                english:
                    "Request sent · waiting",
                norwegian:
                    "Forespørsel sendt · venter"
            )
        }

        if activeDirectDuel != nil {
            return ATHLTHLocalization.choose(
                english:
                    "Request another duel category",
                norwegian:
                    "Be om en annen duellgren"
            )
        }

        return ATHLTHLocalization.choose(
            english:
                "Duel in a specific category",
            norwegian:
                "Dueller på en bestemt gren"
        )
    }

    private func directMetric(
        for challenge:
            ATHLTHChallenge
    ) -> CommunityDirectDuelMetric? {
        guard let raw =
                challenge.rules
                    .headToHeadMetricRaw
        else {
            return nil
        }

        return
            CommunityDirectDuelMetric(
                rawValue: raw
            )
    }

    private func primaryScoreText(
        _ value: Double?
    ) -> String {
        if let duel =
                activeDirectDuel,
           let metric =
                directMetric(
                    for: duel
                ) {
            return metric.format(
                value
            )
        }

        return pointsText(
            value
        )
    }

    private func scoreTint(
        _ value: Double?,
        versus other: Double?
    ) -> Color {
        guard let value,
              let other,
              value > other
        else {
            return ATHLTHTheme
                .primaryText
        }

        return ATHLTHTheme
            .vitality
    }

    @MainActor
    private func createDirectDuel(
        _ metric:
            CommunityDirectDuelMetric
    ) async {
        guard
            !creatingDirectDuel,
            let selectedFriend
        else {
            return
        }

        if outgoingPendingDirectDuel != nil {
            directDuelError =
                ATHLTHLocalization.choose(
                    english:
                        "A direct duel request is already waiting for this athlete.",
                    norwegian:
                        "En direkte duellforespørsel venter allerede på svar fra denne utøveren."
                )
            return
        }

        creatingDirectDuel = true
        defer {
            creatingDirectDuel = false
        }

        let now = Date()
        let end =
            Calendar.current.date(
                byAdding: .day,
                value: 7,
                to: now
            ) ??
            now.addingTimeInterval(
                7 * 86_400
            )

        let creator =
            ChallengeParticipant(
                userID:
                    currentUserID,
                displayName:
                    currentDisplayName
                        .isEmpty
                        ? ATHLTHLocalization.choose(
                            english: "You",
                            norwegian: "Deg"
                        )
                        : currentDisplayName,
                state: .creator
            )

        let invitee =
            ChallengeParticipant(
                userID:
                    selectedFriend
                        .userID,
                username:
                    selectedFriend
                        .username,
                displayName:
                    selectedFriend
                        .resolvedName,
                state: .invited
            )

        let rules =
            ATHLTHChallengeRules(
                scoring:
                    metric.scoring,
                verificationPolicy:
                    .verifiedRequired,
                targetDistanceMeters:
                    nil,
                targetDurationSeconds:
                    nil,
                timeBasis: .elapsed,
                route: nil,
                gpsRequired: false,
                minimumRouteMatchPercent:
                    nil,
                distanceTolerancePercent:
                    nil,
                startFinishToleranceMeters:
                    nil,
                routeDirection: nil,
                attemptPolicy: .best,
                maximumAttempts: nil,
                allowTreadmill: true,
                allowTargetGhost: false,
                allowLiveGhost: false,
                exerciseName: nil,
                fixedWeightKilograms:
                    nil,
                heartRateZone: nil,
                heartRateAggregation:
                    nil,
                summary:
                    metric.subtitle,
                coverArtworkName:
                    nil,
                coverImageURL: nil,
                headToHeadMetricRaw:
                    metric.rawValue,
                startsAt: now,
                endsAt: end,
                allowMultipleAttempts:
                    true,
                lockRulesAtStart: true,
                meetup: nil
            )

        let challenge =
            ATHLTHChallenge(
                creatorID:
                    currentUserID,
                title:
                    metric.requestTitle,
                sport:
                    metric.sport,
                participants: [
                    creator,
                    invitee
                ],
                rules: rules,
                visibility: .friends
            )

        challenges.add(
            challenge
        )

        let synced =
            await social.syncChallenge(
                challenge
            )

        guard synced else {
            challenges.remove(
                challenge.id
            )
            directDuelError =
                social.errorMessage ??
                ATHLTHLocalization.choose(
                    english:
                        "The duel request could not be sent.",
                    norwegian:
                        "Duellforespørselen kunne ikke sendes."
                )
            return
        }

        await social.refresh(
            challengeStore:
                challenges
        )
    }

    private var currentStats:
        CommunityMatchupStats {
        if period == .allTime {
            let workouts = health.workouts

            return CommunityMatchupStats(
                activityPoints: nil,
                workouts:
                    Double(workouts.count),
                runningKilometers:
                    workouts
                        .filter {
                            $0.activity ==
                                .running
                        }
                        .compactMap(
                            \.distanceMeters
                        )
                        .reduce(0, +) /
                        1_000,
                activeMinutes:
                    workouts
                        .reduce(0) {
                            $0 + $1.duration
                        } / 60,
                strengthWorkouts: nil,
                personalRecords: nil,
                challenges: nil
            )
        }

        let threshold =
            period.threshold ??
            .distantPast
        let workouts =
            health.workouts.filter {
                $0.startDate >= threshold
            }
        let socialRows =
            ownActivities.filter {
                $0.createdAt >= threshold
            }

        return CommunityMatchupStats(
            activityPoints: nil,
            workouts:
                Double(workouts.count),
            runningKilometers:
                workouts
                    .filter {
                        $0.activity == .running
                    }
                    .compactMap(
                        \.distanceMeters
                    )
                    .reduce(0, +) /
                    1_000,
            activeMinutes:
                workouts
                    .reduce(0) {
                        $0 + $1.duration
                    } / 60,
            strengthWorkouts:
                Double(
                    workouts.filter {
                        $0.activity ==
                            .strength
                    }.count
                ),
            personalRecords:
                Double(
                    socialRows.filter {
                        $0.kind ==
                            "personal_record"
                    }.count
                ),
            challenges:
                Double(
                    socialRows.filter {
                        $0.kind ==
                            "challenge"
                    }.count
                )
        )
    }

    private var friendStats:
        CommunityMatchupStats {
        if period == .allTime {
            guard let performance =
                    friendProfile?
                        .performance
            else {
                return CommunityMatchupStats(
                    activityPoints: nil,
                    workouts: nil,
                    runningKilometers: nil,
                    activeMinutes: nil,
                    strengthWorkouts: nil,
                    personalRecords: nil,
                    challenges: nil
                )
            }

            return CommunityMatchupStats(
                activityPoints: nil,
                workouts:
                    Double(
                        performance
                            .totalWorkoutCount
                    ),
                runningKilometers:
                    performance
                        .totalRunningDistanceMeters /
                    1_000,
                activeMinutes:
                    performance
                        .totalTrainingSeconds /
                    60,
                strengthWorkouts: nil,
                personalRecords: nil,
                challenges: nil
            )
        }

        let threshold =
            period.threshold ??
            .distantPast
        let rows =
            friendActivities.filter {
                $0.createdAt >= threshold
            }
        let workouts =
            rows.filter {
                $0.kind == "workout"
            }
        let durationValues =
            workouts.compactMap {
                durationSeconds($0)
            }

        return CommunityMatchupStats(
            activityPoints: nil,
            workouts:
                Double(workouts.count),
            runningKilometers:
                workouts.reduce(0) {
                    $0 +
                        runningKilometers(
                            $1
                        )
                },
            activeMinutes:
                durationValues.isEmpty &&
                    !workouts.isEmpty
                    ? nil
                    : durationValues
                        .reduce(0, +) /
                        60,
            strengthWorkouts:
                Double(
                    workouts.filter {
                        isStrength($0)
                    }.count
                ),
            personalRecords:
                Double(
                    rows.filter {
                        $0.kind ==
                            "personal_record"
                    }.count
                ),
            challenges:
                Double(
                    rows.filter {
                        $0.kind ==
                            "challenge"
                    }.count
                )
        )
    }

    private func matchupPerson(
        name: String,
        avatarURL: URL?,
        label: String
    ) -> some View {
        VStack(spacing: 7) {
            CommunityShowcaseAvatar(
                url: avatarURL,
                fallback: name,
                size: 64
            )

            Text(firstName(name))
                .font(
                    .subheadline.weight(
                        .bold
                    )
                )
                .lineLimit(1)

            Text(label)
                .font(.system(
                    size: 9,
                    weight: .bold
                ))
                .tracking(1.1)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
        }
        .frame(maxWidth: .infinity)
    }

    private func metricRow(
        _ title: String,
        icon: String,
        mine: Double?,
        theirs: Double?,
        format: (Double?) -> String,
        emphasis:
            CommunityMatchupMetricEmphasis =
                .normal
    ) -> some View {
        HStack(spacing: 10) {
            Text(format(mine))
                .font(
                    emphasis == .highlighted
                        ? .headline
                            .monospacedDigit()
                            .weight(.bold)
                        : .subheadline
                            .monospacedDigit()
                            .weight(.bold)
                )
                .foregroundStyle(
                    emphasis == .highlighted
                        ? ATHLTHTheme
                            .vitality
                        : metricTint(
                            mine,
                            versus: theirs
                        )
                )
                .frame(
                    width: 82,
                    alignment: .leading
                )

            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(
                        .caption.weight(
                            .semibold
                        )
                    )
                    .foregroundStyle(
                        emphasis == .highlighted
                            ? ATHLTHTheme
                                .vitality
                            : ATHLTHTheme
                                .accentDeep
                    )

                Text(title)
                    .font(
                        emphasis == .highlighted
                            ? .caption
                                .weight(.bold)
                            : .caption
                    )
                    .foregroundStyle(
                        emphasis == .highlighted
                            ? ATHLTHTheme
                                .primaryText
                            : Color.secondary
                    )
            }
            .frame(
                maxWidth: .infinity
            )

            Text(format(theirs))
                .font(
                    emphasis == .highlighted
                        ? .headline
                            .monospacedDigit()
                            .weight(.bold)
                        : .subheadline
                            .monospacedDigit()
                            .weight(.bold)
                )
                .foregroundStyle(
                    emphasis == .highlighted
                        ? ATHLTHTheme
                            .vitality
                        : metricTint(
                            theirs,
                            versus: mine
                        )
                )
                .frame(
                    width: 82,
                    alignment: .trailing
                )
        }
        .padding(
            .horizontal,
            emphasis == .highlighted
                ? 10
                : 0
        )
        .padding(.vertical, 11)
        .background {
            if emphasis == .highlighted {
                RoundedRectangle(
                    cornerRadius: 14,
                    style: .continuous
                )
                .fill(
                    ATHLTHTheme
                        .vitalitySoft
                        .opacity(0.78)
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: 14,
                        style:
                            .continuous
                    )
                    .stroke(
                        ATHLTHTheme
                            .vitality
                            .opacity(
                                0.16
                            ),
                        lineWidth: 0.8
                    )
                }
            }
        }
        .opacity(
            emphasis == .dimmed
                ? 0.38
                : 1
        )
    }

    private func metricTint(
        _ value: Double?,
        versus other: Double?
    ) -> Color {
        guard let value,
              let other,
              value > other
        else {
            return ATHLTHTheme
                .primaryText
        }

        return ATHLTHTheme
            .accentDeep
    }

    private func pointsText(
        _ value: Double?
    ) -> String {
        guard let value else {
            return "—"
        }

        return "\(Int(value.rounded())) p"
    }

    private func countText(
        _ value: Double?
    ) -> String {
        guard let value else {
            return "—"
        }

        return "\(Int(value.rounded()))"
    }

    private func distanceText(
        _ value: Double?
    ) -> String {
        guard let value else {
            return "—"
        }

        return String(
            format: "%.1f km",
            value
        )
    }

    private func strengthVolumeText(
        _ value: Double?
    ) -> String {
        guard let value else {
            return "—"
        }

        if value >= 1_000 {
            return String(
                format:
                    "%.1f t",
                value / 1_000
            )
        }

        return String(
            format: "%.0f kg",
            value
        )
    }

    private func minutesText(
        _ value: Double?
    ) -> String {
        guard let value else {
            return "—"
        }

        let total =
            max(Int(value.rounded()), 0)
        let hours = total / 60
        let minutes = total % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }

        return "\(minutes)m"
    }

    private func runningKilometers(
        _ activity: SocialActivityRecord
    ) -> Double {
        let kind =
            activity.metadata?["kind"]?
                .lowercased() ?? ""

        guard kind.contains("run") ||
                activity.title
                    .lowercased()
                    .contains("run")
        else {
            return 0
        }

        if let raw =
                activity.metadata?[
                    "distance_meters"
                ],
           let meters = Double(raw) {
            return meters / 1_000
        }

        guard let subtitle =
                activity.subtitle
        else {
            return 0
        }

        let parts = subtitle
            .replacingOccurrences(
                of: ",",
                with: "."
            )
            .split(separator: " ")

        for index in parts.indices {
            guard parts[index]
                    .lowercased() == "km",
                  index >
                    parts.startIndex,
                  let value =
                    Double(
                        parts[
                            parts.index(
                                before: index
                            )
                        ]
                    )
            else {
                continue
            }

            return value
        }

        return 0
    }

    private func durationSeconds(
        _ activity: SocialActivityRecord
    ) -> Double? {
        guard let raw =
                activity.metadata?[
                    "duration_seconds"
                ],
              let value = Double(raw)
        else {
            return nil
        }

        return max(value, 0)
    }

    private func isStrength(
        _ activity: SocialActivityRecord
    ) -> Bool {
        let kind =
            activity.metadata?["kind"]?
                .lowercased() ?? ""

        return kind.contains(
            "strength"
        ) ||
            activity.title
                .lowercased()
                .contains("strength")
    }

    private func firstName(
        _ value: String
    ) -> String {
        value.split(separator: " ")
            .first
            .map(String.init) ??
            value
    }

    @MainActor
    private func loadSelectedFriend()
        async {
        guard let selectedFriend else {
            friendProfile = nil
            friendActivities = []
            return
        }

        loadingFriend = true
        defer {
            loadingFriend = false
        }

        async let profileTask =
            social.loadFriendProfile(
                selectedFriend.userID
            )
        async let activitiesTask =
            social.loadActivitiesForMatchup(
                selectedFriend.userID
            )

        let (
            loadedProfile,
            loadedActivities
        ) = await (
            profileTask,
            activitiesTask
        )

        guard
            selectedFriendID ==
                selectedFriend.userID
        else {
            return
        }

        friendProfile = loadedProfile
        friendActivities =
            loadedActivities
    }
}

private struct CommunityShowcaseAvatar: View {
    let url: URL?
    let fallback: String
    let size: CGFloat

    var body: some View {
        Group {
            if let url {
                ATHLTHStorageImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var placeholder: some View {
        Circle()
            .fill(ATHLTHTheme.surfaceSage)
            .overlay {
                Text(initials)
                    .font(
                        .system(
                            size: max(size * 0.25, 9),
                            weight: .bold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.accentDeep
                    )
            }
    }

    private var initials: String {
        let parts = fallback
            .split(separator: " ")
            .prefix(2)

        let value = parts.compactMap {
            $0.first.map(String.init)
        }
        .joined()

        return value.isEmpty ? "A" : value.uppercased()
    }
}
