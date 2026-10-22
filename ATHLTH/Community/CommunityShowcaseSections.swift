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
    @State private var showingFriendSelector = false
    @State private var showingPointRules = false
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
                    periodPicker
                    matchupHero
                    comparisonInsightCard
                    metricCard
                    trendCard
                    duelActionCard
                    pointsExplainerCard
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 14)
            .padding(.bottom, 36)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background {
            ATHLTHPremiumCanvas(
                accent: ATHLTHTheme.champagneSoft.opacity(0.34)
            )
            .ignoresSafeArea()
        }
        .navigationTitle("Head-to-head")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if selectedFriend != nil {
                    ShareLink(item: matchupShareText) {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                    }
                    .accessibilityLabel(
                        ATHLTHLocalization.choose(
                            english: "Share comparison",
                            norwegian: "Del sammenligning"
                        )
                    )
                }
            }
        }
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
            ownActivities = await social.loadActivitiesForMatchup(
                currentUserID
            )
            await loadSelectedFriend()
        }
        .sheet(isPresented: $showingFriendSelector) {
            NavigationStack {
                List(friends) { friend in
                    Button {
                        selectedFriendID = friend.userID
                        showingFriendSelector = false
                    } label: {
                        HStack(spacing: 13) {
                            CommunityShowcaseAvatar(
                                url: friend.avatarURL.flatMap(URL.init(string:)),
                                fallback: friend.resolvedName,
                                size: 42
                            )
                            Text(friend.resolvedName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(ATHLTHTheme.primaryText)
                            Spacer()
                            if selectedFriend?.userID == friend.userID {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(ATHLTHTheme.premiumGold)
                            }
                        }
                        .padding(.vertical, 5)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(ATHLTHTheme.card)
                }
                .listStyle(.plain)
                .background(ATHLTHTheme.canvasTop)
                .navigationTitle(
                    ATHLTHLocalization.choose(
                        english: "Choose opponent",
                        norwegian: "Velg motstander"
                    )
                )
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(
                            ATHLTHLocalization.choose(
                                english: "Done",
                                norwegian: "Ferdig"
                            )
                        ) { showingFriendSelector = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(
            isPresented:
                $showingDirectDuelPicker
        ) {
            directDuelPickerSheet
                .presentationDetents([
                    .height(430)
                ])
                .presentationDragIndicator(
                    .visible
                )
                .presentationCornerRadius(
                    30
                )
                .presentationBackground(
                    .ultraThinMaterial
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

    private var directDuelPickerSheet:
        some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        ATHLTHTheme
                            .canvasTop,
                        ATHLTHTheme
                            .canvasBottom
                    ],
                    startPoint:
                        .topLeading,
                    endPoint:
                        .bottomTrailing
                )
                .ignoresSafeArea()

                Circle()
                    .fill(
                        ATHLTHTheme
                            .vitality
                            .opacity(0.11)
                    )
                    .frame(
                        width: 230,
                        height: 230
                    )
                    .blur(radius: 38)
                    .offset(
                        x: 135,
                        y: -145
                    )

                VStack(
                    alignment: .leading,
                    spacing: 14
                ) {
                    HStack(
                        alignment: .top,
                        spacing: 12
                    ) {
                        Image(
                            systemName:
                                "bolt.horizontal.circle.fill"
                        )
                        .font(.title2)
                        .foregroundStyle(
                            ATHLTHTheme
                                .vitality
                        )
                        .frame(
                            width: 46,
                            height: 46
                        )
                        .background(
                            ATHLTHTheme
                                .vitalitySoft,
                            in: Circle()
                        )

                        VStack(
                            alignment: .leading,
                            spacing: 4
                        ) {
                            Text(
                                ATHLTHLocalization
                                    .choose(
                                        english:
                                            "Choose direct duel",
                                        norwegian:
                                            "Velg direkte duell"
                                    )
                            )
                            .font(
                                .title3
                                    .weight(.bold)
                            )
                            .foregroundStyle(
                                ATHLTHTheme
                                    .primaryText
                            )

                            Text(
                                ATHLTHLocalization
                                    .choose(
                                        english:
                                            "Seven days. One category. Your friend receives a request before the duel becomes active.",
                                        norwegian:
                                            "Syv dager. Én gren. Vennen din får en forespørsel før duellen blir aktiv."
                                    )
                            )
                            .font(.caption)
                            .foregroundStyle(
                                ATHLTHTheme
                                    .mutedText
                            )
                            .fixedSize(
                                horizontal: false,
                                vertical: true
                            )
                        }

                        Spacer()
                    }

                    VStack(spacing: 9) {
                        ForEach(
                            CommunityDirectDuelMetric
                                .allCases
                        ) { metric in
                            directDuelOption(
                                metric
                            )
                        }
                    }

                    Text(
                        ATHLTHLocalization
                            .choose(
                                english:
                                    "Activity points remain the default score until the request is accepted.",
                                norwegian:
                                    "Aktivitetspoeng er fortsatt standardscoren frem til forespørselen er godtatt."
                            )
                    )
                    .font(.caption2)
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                    )
                    .padding(
                        .horizontal,
                        2
                    )
                }
                .padding(
                    .horizontal,
                    18
                )
                .padding(.top, 10)
                .padding(
                    .bottom,
                    18
                )
            }
            .toolbar {
                ToolbarItem(
                    placement:
                        .topBarTrailing
                ) {
                    Button {
                        showingDirectDuelPicker =
                            false
                    } label: {
                        Image(
                            systemName:
                                "xmark"
                        )
                        .font(.caption.bold())
                        .foregroundStyle(
                            ATHLTHTheme
                                .primaryText
                        )
                        .frame(
                            width: 32,
                            height: 32
                        )
                        .background(
                            Color.white
                                .opacity(0.74),
                            in: Circle()
                        )
                    }
                }
            }
            .toolbarBackground(
                .hidden,
                for: .navigationBar
            )
        }
    }

    private func directDuelOption(
        _ metric:
            CommunityDirectDuelMetric
    ) -> some View {
        Button {
            showingDirectDuelPicker =
                false

            Task {
                await createDirectDuel(
                    metric
                )
            }
        } label: {
            HStack(spacing: 12) {
                Image(
                    systemName:
                        metric.systemImage
                )
                .font(
                    .system(
                        size: 17,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme
                        .vitality
                )
                .frame(
                    width: 42,
                    height: 42
                )
                .background(
                    ATHLTHTheme
                        .vitalitySoft,
                    in:
                        RoundedRectangle(
                            cornerRadius: 13,
                            style: .continuous
                        )
                )

                VStack(
                    alignment: .leading,
                    spacing: 3
                ) {
                    Text(metric.title)
                        .font(
                            .subheadline
                                .weight(.bold)
                        )
                        .foregroundStyle(
                            ATHLTHTheme
                                .primaryText
                        )

                    Text(metric.subtitle)
                        .font(.caption2)
                        .foregroundStyle(
                            ATHLTHTheme
                                .mutedText
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(
                            0.82
                        )
                }

                Spacer()

                Image(
                    systemName:
                        "chevron.right"
                )
                .font(.caption.bold())
                .foregroundStyle(
                    ATHLTHTheme
                        .vitality
                )
            }
            .padding(
                .horizontal,
                13
            )
            .frame(height: 62)
            .background(
                LinearGradient(
                    colors: [
                        Color.white
                            .opacity(0.95),
                        ATHLTHTheme
                            .vitalitySoft
                            .opacity(0.62)
                    ],
                    startPoint:
                        .leading,
                    endPoint:
                        .trailing
                ),
                in:
                    RoundedRectangle(
                        cornerRadius: 18,
                        style: .continuous
                    )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
                .stroke(
                    ATHLTHTheme
                        .vitality
                        .opacity(0.12),
                    lineWidth: 0.8
                )
            }
        }
        .buttonStyle(.plain)
        .disabled(
            creatingDirectDuel
        )
    }

    /// Keep the selected opponent visible without occupying a row of pills.
    /// The list sheet scales to an arbitrary number of mutual follows.
    private var friendPicker: some View {
        Button {
            showingFriendSelector = true
        } label: {
            HStack(spacing: 12) {
                if let friend = selectedFriend {
                    CommunityShowcaseAvatar(
                        url: friend.avatarURL.flatMap(URL.init(string:)),
                        fallback: friend.resolvedName,
                        size: 38
                    )
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(ATHLTHLocalization.choose(
                        english: "OPPONENT",
                        norwegian: "MOTSTANDER"
                    ))
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(ATHLTHTheme.mutedText)

                    Text(selectedFriend?.resolvedName ?? "—")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(ATHLTHTheme.primaryText)
                        .lineLimit(1)
                }
                Spacer()
                Text(ATHLTHLocalization.choose(
                    english: "Change",
                    norwegian: "Bytt"
                ))
                .font(.caption.weight(.semibold))
                .foregroundStyle(ATHLTHTheme.accentDeep)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(ATHLTHTheme.card, in: RoundedRectangle(
                cornerRadius: 19, style: .continuous
            ))
            .overlay {
                RoundedRectangle(cornerRadius: 19, style: .continuous)
                    .stroke(ATHLTHTheme.border, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint(ATHLTHLocalization.choose(
            english: "Select a friend to compare workouts",
            norwegian: "Velg en venn for å sammenligne treningen"
        ))
    }

    /// A single scoreboard replaces the duplicated matchup and score cards.
    private var matchupHero: some View {
        let mine = primaryScoreValues.mine
        let theirs = primaryScoreValues.theirs

        return VStack(spacing: 18) {
            HStack(spacing: 8) {
                ATHLTHMarkShape()
                    .fill(ATHLTHTheme.premiumGold)
                    .frame(width: 25, height: 19)
                    .accessibilityHidden(true)

                Text("HEAD-TO-HEAD")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1.8)
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                Spacer()
                Text(activeDirectDuel == nil
                    ? ATHLTHLocalization.choose(
                        english: "ACTIVITY", norwegian: "AKTIVITET")
                    : ATHLTHLocalization.choose(
                        english: "ACTIVE DUEL", norwegian: "AKTIV DUELL")
                )
                .font(.system(size: 9, weight: .bold))
                .tracking(1)
                .foregroundStyle(ATHLTHTheme.accentDeep)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    ATHLTHTheme.champagneSoft,
                    in: Capsule()
                )
            }

            HStack(spacing: 12) {
                matchupPerson(
                    name: currentDisplayName.isEmpty
                        ? ATHLTHLocalization.choose(
                            english: "You", norwegian: "Deg")
                        : currentDisplayName,
                    avatarURL: currentAvatarURL,
                    label: ATHLTHLocalization.choose(
                        english: "YOU", norwegian: "DU"
                    )
                )

                VStack(spacing: 5) {
                    Image(systemName: "bolt.horizontal.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(ATHLTHTheme.premiumGold)
                    Text("VS")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .tracking(1)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                }
                .frame(width: 38)

                if let selectedFriend {
                    matchupPerson(
                        name: selectedFriend.resolvedName,
                        avatarURL: selectedFriend.avatarURL.flatMap(URL.init(string:)),
                        label: ATHLTHLocalization.choose(
                            english: "FRIEND", norwegian: "VENN"
                        )
                    )
                }
            }

            Rectangle()
                .fill(ATHLTHTheme.divider)
                .frame(height: 1)

            VStack(spacing: 8) {
                Text(primaryScoreTitle)
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.35)
                    .foregroundStyle(ATHLTHTheme.mutedText)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(primaryScoreText(mine))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .foregroundStyle(scoreTint(mine, versus: theirs))
                    Text("–")
                        .font(.title2.weight(.light))
                        .foregroundStyle(ATHLTHTheme.mutedText)
                    Text(primaryScoreText(theirs))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(scoreTint(theirs, versus: mine))
                }
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.62)
                .lineLimit(1)
                .contentTransition(.numericText())

                GeometryReader { geometry in
                    let share = CommunityMatchupVisualPolicy.share(
                        mine: mine,
                        theirs: theirs
                    )
                    HStack(spacing: 0) {
                        ATHLTHTheme.premiumGold
                            .frame(width: geometry.size.width * share)
                        ATHLTHTheme.accentDeep.opacity(0.34)
                    }
                    .clipShape(Capsule())
                }
                .frame(height: 6)
                .background(ATHLTHTheme.surfaceStone, in: Capsule())

                Text(matchupLeadText)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(ATHLTHTheme.primaryText)
                    .multilineTextAlignment(.center)

                Text(primaryScoreSubtitle)
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(21)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(LinearGradient(
                    colors: [
                        ATHLTHTheme.card,
                        ATHLTHTheme.cardWarm.opacity(0.55),
                        ATHLTHTheme.canvasTop
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(ATHLTHTheme.premiumGold.opacity(0.24), lineWidth: 1)
        }
        .shadow(color: ATHLTHTheme.accentDeep.opacity(0.085), radius: 19, y: 9)
        .accessibilityElement(children: .combine)
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

    // MARK: - Rivalry breakdown

    private var metricCard: some View {
        let mine = currentStats
        let theirs = friendStats
        let duelMetric = activeDirectMetric

        return VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline) {
                Text(ATHLTHLocalization.choose(
                    english: "The details", norwegian: "Sammenligningen"
                ))
                .font(.title3.weight(.bold))
                .foregroundStyle(ATHLTHTheme.primaryText)
                Spacer()
                Text(period.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.mutedText)
            }
            .padding(.bottom, 2)

            metricRow(
                ATHLTHLocalization.choose(english: "Workouts", norwegian: "Økter"),
                icon: "checkmark.circle.fill",
                mine: duelMetric == .workoutCount
                    ? primaryScoreValues.mine : mine.workouts,
                theirs: duelMetric == .workoutCount
                    ? primaryScoreValues.theirs : theirs.workouts,
                format: countText,
                emphasis: metricEmphasis(for: .workouts)
            )
            metricRow(
                ATHLTHLocalization.choose(english: "Running distance", norwegian: "Løping"),
                icon: "figure.run",
                mine: duelMetric == .runningDistance
                    ? primaryScoreValues.mine.map { $0 / 1_000 }
                    : mine.runningKilometers,
                theirs: duelMetric == .runningDistance
                    ? primaryScoreValues.theirs.map { $0 / 1_000 }
                    : theirs.runningKilometers,
                format: distanceText,
                emphasis: metricEmphasis(for: .running)
            )
            metricRow(
                ATHLTHLocalization.choose(english: "Active time", norwegian: "Aktiv tid"),
                icon: "clock",
                mine: mine.activeMinutes,
                theirs: theirs.activeMinutes,
                format: minutesText,
                emphasis: metricEmphasis(for: .activeTime)
            )

            if period != .allTime || duelMetric == .strengthVolume {
                metricRow(
                    duelMetric == .strengthVolume
                        ? ATHLTHLocalization.choose(
                            english: "Strength volume", norwegian: "Styrkevolum"
                        )
                        : ATHLTHLocalization.choose(
                            english: "Strength workouts", norwegian: "Styrkeøkter"
                        ),
                    icon: "dumbbell.fill",
                    mine: duelMetric == .strengthVolume
                        ? primaryScoreValues.mine : mine.strengthWorkouts,
                    theirs: duelMetric == .strengthVolume
                        ? primaryScoreValues.theirs : theirs.strengthWorkouts,
                    format: duelMetric == .strengthVolume
                        ? strengthVolumeText : countText,
                    emphasis: metricEmphasis(for: .strength)
                )
            }

            if period != .allTime {
                metricRow(
                    ATHLTHLocalization.choose(
                        english: "Personal records", norwegian: "Personlige rekorder"
                    ),
                    icon: "sparkles",
                    mine: mine.personalRecords,
                    theirs: theirs.personalRecords,
                    format: countText,
                    emphasis: metricEmphasis(for: .personalRecords)
                )
                metricRow(
                    ATHLTHLocalization.choose(
                        english: "Challenges", norwegian: "Utfordringer"
                    ),
                    icon: "trophy.fill",
                    mine: mine.challenges,
                    theirs: theirs.challenges,
                    format: countText,
                    emphasis: metricEmphasis(for: .challenges)
                )
            }

            Label(ATHLTHLocalization.choose(
                english: "Only workouts available to you are included. A dash means data is not shared.",
                norwegian: "Kun tilgjengelige økter er med. En strek betyr at data ikke er delt."
            ), systemImage: "lock.shield")
            .font(.caption2)
            .foregroundStyle(ATHLTHTheme.mutedText)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 5)
        }
        .padding(16)
        .background(ATHLTHTheme.card, in: RoundedRectangle(
            cornerRadius: 25, style: .continuous
        ))
        .overlay {
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .stroke(ATHLTHTheme.border, lineWidth: 1)
        }
    }

    /// Interpretation is based only on the values currently available.
    /// Avoid claiming a friend did not exercise when their sharing is empty.
    private var matchupLeadText: String {
        let mine = primaryScoreValues.mine
        let theirs = primaryScoreValues.theirs
        switch CommunityMatchupVisualPolicy.standing(mine: mine, theirs: theirs) {
        case .unavailable:
            return ATHLTHLocalization.choose(
                english: "Not enough shared data yet",
                norwegian: "Ikke nok delte data ennå"
            )
        case .tied:
            return ATHLTHLocalization.choose(
                english: "It's level so far",
                norwegian: "Foreløpig helt jevnt"
            )
        case .leading:
            return ATHLTHLocalization.choose(
                english: "You're ahead on available data",
                norwegian: "Du leder med tilgjengelige data"
            )
        case .trailing:
            return ATHLTHLocalization.choose(
                english: "\(firstName(selectedFriend?.resolvedName ?? "Friend")) is ahead",
                norwegian: "\(firstName(selectedFriend?.resolvedName ?? "Vennen")) leder"
            )
        }
    }

    private var matchupInsightText: String {
        if loadingFriend {
            return ATHLTHLocalization.choose(
                english: "Updating the shared workout data…",
                norwegian: "Oppdaterer tilgjengelige treningsdata …"
            )
        }
        if period == .allTime && friendProfile?.performance == nil {
            return ATHLTHLocalization.choose(
                english: "All-time totals are not shared by this athlete. Private data never counts as zero.",
                norwegian: "Denne utøveren deler ikke totalstatistikk. Private data regnes aldri som null."
            )
        }
        if friendStats.workouts == 0, activeDirectDuel == nil {
            return ATHLTHLocalization.choose(
                english: "No shared workouts for this opponent in the selected period. They may have trained privately.",
                norwegian: "Ingen delte økter fra motstanderen i valgt periode. Private økter vises ikke."
            )
        }
        let own = currentStats
        let friend = friendStats
        if let w1 = own.workouts, let w2 = friend.workouts,
           w1 != w2 {
            return w1 > w2
                ? ATHLTHLocalization.choose(
                    english: "You've completed more workouts in this period.",
                    norwegian: "Du har registrert flere økter i denne perioden."
                )
                : ATHLTHLocalization.choose(
                    english: "Your opponent has more shared workouts in this period.",
                    norwegian: "Motstanderen har flere delte økter i denne perioden."
                )
        }
        if let t1 = own.activeMinutes, let t2 = friend.activeMinutes,
           t1 != t2 {
            return t1 > t2
                ? ATHLTHLocalization.choose(
                    english: "Your active time gives you an edge.",
                    norwegian: "Du har fordelen på aktiv treningstid."
                )
                : ATHLTHLocalization.choose(
                    english: "Your opponent has the edge in active time.",
                    norwegian: "Motstanderen har fordelen på aktiv treningstid."
                )
        }
        return ATHLTHLocalization.choose(
            english: "Compare the details below or start a direct duel.",
            norwegian: "Se detaljene nedenfor, eller start en direkte duell."
        )
    }

    private var comparisonInsightCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(ATHLTHTheme.premiumGold)
                .frame(width: 38, height: 38)
                .background(
                    ATHLTHTheme.premiumGoldSoft,
                    in: RoundedRectangle(cornerRadius: 12)
                )
            VStack(alignment: .leading, spacing: 5) {
                Text(ATHLTHLocalization.choose(
                    english: "MATCHUP INSIGHT", norwegian: "DUELLINNSIKT"
                ))
                .font(.system(size: 10, weight: .bold))
                .tracking(1.3)
                .foregroundStyle(ATHLTHTheme.accentDeep)
                Text(matchupInsightText)
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if loadingFriend {
                ProgressView().controlSize(.small)
            }
        }
        .padding(16)
        .background(ATHLTHTheme.cardWarm.opacity(0.50),
                    in: RoundedRectangle(cornerRadius: 21))
        .overlay {
            RoundedRectangle(cornerRadius: 21)
                .stroke(ATHLTHTheme.premiumGold.opacity(0.18), lineWidth: 1)
        }
    }

    // MARK: - Visible recent activity: no guessed or private training

    private var recentDays: [Date] {
        let today = Calendar.current.startOfDay(for: Date())
        return (0..<7).compactMap {
            Calendar.current.date(byAdding: .day, value: $0 - 6, to: today)
        }
    }

    private func ownWorkoutCount(on day: Date) -> Int {
        health.workouts.filter {
            Calendar.current.isDate($0.startDate, inSameDayAs: day)
        }.count
    }

    private func sharedWorkoutCount(on day: Date) -> Int {
        friendActivities.filter {
            $0.kind == "workout" &&
            Calendar.current.isDate($0.createdAt, inSameDayAs: day)
        }.count
    }

    private var trendCard: some View {
        let days = recentDays
        let high = max(1, days.map {
            max(ownWorkoutCount(on: $0), sharedWorkoutCount(on: $0))
        }.max() ?? 1)
        let hasTraining = days.contains {
            ownWorkoutCount(on: $0) > 0 || sharedWorkoutCount(on: $0) > 0
        }

        return VStack(alignment: .leading, spacing: 13) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(ATHLTHLocalization.choose(
                        english: "Recent momentum", norwegian: "Aktivitet siste uke"
                    ))
                    .font(.headline)
                    .foregroundStyle(ATHLTHTheme.primaryText)
                    Text(ATHLTHLocalization.choose(
                        english: "Completed workouts · last 7 days",
                        norwegian: "Registrerte økter · siste 7 dager"
                    ))
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                }
                Spacer()
                Image(systemName: "chart.bar.xaxis")
                    .foregroundStyle(ATHLTHTheme.premiumGold)
            }
            if hasTraining {
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(days, id: \.self) { day in
                        let own = ownWorkoutCount(on: day)
                        let shared = sharedWorkoutCount(on: day)
                        VStack(spacing: 7) {
                            HStack(alignment: .bottom, spacing: 3) {
                                Capsule()
                                    .fill(ATHLTHTheme.premiumGold)
                                    .frame(height: own == 0 ? 3 :
                                        CGFloat(own) / CGFloat(high) * 58)
                                Capsule()
                                    .fill(ATHLTHTheme.accentDeep.opacity(0.48))
                                    .frame(height: shared == 0 ? 3 :
                                        CGFloat(shared) / CGFloat(high) * 58)
                            }
                            .frame(height: 61, alignment: .bottom)
                            Text(day, format: .dateTime.weekday(.narrow))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(ATHLTHTheme.mutedText)
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(
                            "\(day.formatted(date: .abbreviated, time: .omitted)), \(own) / \(shared)"
                        )
                    }
                }
                HStack(spacing: 17) {
                    legend(color: ATHLTHTheme.premiumGold,
                           title: ATHLTHLocalization.choose(
                            english: "You", norwegian: "Du"))
                    legend(color: ATHLTHTheme.accentDeep.opacity(0.48),
                           title: firstName(selectedFriend?.resolvedName ?? "Friend"))
                }
            } else {
                Label(ATHLTHLocalization.choose(
                    english: "No visible workouts in the last 7 days.",
                    norwegian: "Ingen synlige økter siste 7 dager."
                ), systemImage: "calendar")
                .font(.subheadline)
                .foregroundStyle(ATHLTHTheme.mutedText)
                .padding(.vertical, 8)
            }
        }
        .padding(17)
        .background(ATHLTHTheme.card, in: RoundedRectangle(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .stroke(ATHLTHTheme.border, lineWidth: 1)
        }
    }

    private func legend(color: Color, title: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(ATHLTHTheme.mutedText)
                .lineLimit(1)
        }
    }

    // MARK: - Real challenge actions

    private var duelActionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "scope")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.premiumGold)
                    .frame(width: 42, height: 42)
                    .background(
                        ATHLTHTheme.premiumGoldSoft,
                        in: RoundedRectangle(cornerRadius: 13)
                    )
                VStack(alignment: .leading, spacing: 4) {
                    Text(ATHLTHLocalization.choose(
                        english: "Take on a new challenge",
                        norwegian: "Gjør sammenligningen til en duell"
                    ))
                    .font(.headline)
                    .foregroundStyle(ATHLTHTheme.primaryText)
                    Text(ATHLTHLocalization.choose(
                        english: "Choose a category. The opponent must accept.",
                        norwegian: "Velg en gren. Motstanderen må godta."
                    ))
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                }
                Spacer(minLength: 0)
            }

            Button {
                showingDirectDuelPicker = true
            } label: {
                HStack {
                    if creatingDirectDuel {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "bolt.fill")
                    }
                    Text(directDuelButtonTitle)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(height: 50)
                .background(
                    ATHLTHTheme.accentDeep,
                    in: RoundedRectangle(cornerRadius: 15)
                )
            }
            .buttonStyle(.plain)
            .disabled(
                selectedFriend == nil || creatingDirectDuel ||
                outgoingPendingDirectDuel != nil
            )

            Button {
                showingChallenge = true
            } label: {
                HStack {
                    Image(systemName: "trophy")
                    Text(ATHLTHLocalization.choose(
                        english: "Other challenge types",
                        norwegian: "Andre utfordringer"
                    ))
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ATHLTHTheme.accentDeep)
                .padding(.horizontal, 16)
                .frame(height: 44)
                .background(
                    ATHLTHTheme.surfaceStone,
                    in: RoundedRectangle(cornerRadius: 15)
                )
            }
            .buttonStyle(.plain)
            .disabled(selectedFriend == nil)

            if outgoingPendingDirectDuel != nil {
                Label(ATHLTHLocalization.choose(
                    english: "Invitation sent. Waiting for a reply.",
                    norwegian: "Invitasjonen er sendt. Venter på svar."
                ), systemImage: "clock")
                .font(.caption)
                .foregroundStyle(ATHLTHTheme.mutedText)
            } else if incomingPendingDirectDuel != nil {
                Label(ATHLTHLocalization.choose(
                    english: "You have an invitation. Reply in Inbox.",
                    norwegian: "Du har en invitasjon. Svar i innboksen."
                ), systemImage: "tray.full")
                .font(.caption)
                .foregroundStyle(ATHLTHTheme.premiumGold)
            }
        }
        .padding(18)
        .background(ATHLTHTheme.card, in: RoundedRectangle(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .stroke(ATHLTHTheme.premiumGold.opacity(0.23), lineWidth: 1)
        }
    }

    private var pointsExplainerCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showingPointRules.toggle()
                }
            } label: {
                HStack(spacing: 11) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(ATHLTHTheme.premiumGold)
                    Text(ATHLTHLocalization.choose(
                        english: "How the score is calculated",
                        norwegian: "Slik beregnes aktivitetspoengene"
                    ))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.primaryText)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption.bold())
                        .rotationEffect(.degrees(showingPointRules ? 180 : 0))
                        .foregroundStyle(ATHLTHTheme.mutedText)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showingPointRules {
                Divider().padding(.vertical, 13)
                Text(ATHLTHLocalization.choose(
                    english: "20 points per registered workout + 1 point for each 5 active minutes, with a cap of 120 minutes per workout in the total calculation. Missing duration does not count as zero workouts.",
                    norwegian: "20 poeng per registrerte økt + 1 poeng for hver 5. aktive minutt. Tidsbonusen er begrenset i beregningen til maksimalt 120 minutter per økt. Manglende varighet fjerner ikke øktpoengene."
                ))
                .font(.caption)
                .foregroundStyle(ATHLTHTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)

                if let own = CommunityMatchupVisualPolicy.pointsBreakdown(
                    workouts: currentStats.workouts,
                    activeMinutes: currentStats.activeMinutes
                ), let friend = CommunityMatchupVisualPolicy.pointsBreakdown(
                    workouts: friendStats.workouts,
                    activeMinutes: friendStats.activeMinutes
                ) {
                    VStack(spacing: 9) {
                        scoreDetailRow(
                            ATHLTHLocalization.choose(
                                english: "Workout points", norwegian: "Øktpoeng"),
                            mine: own.workoutPoints,
                            theirs: friend.workoutPoints
                        )
                        scoreDetailRow(
                            ATHLTHLocalization.choose(
                                english: "Time bonus", norwegian: "Tidsbonus"),
                            mine: own.timePoints,
                            theirs: friend.timePoints
                        )
                    }
                    .padding(.top, 12)
                }
                if activeDirectDuel != nil {
                    Label(ATHLTHLocalization.choose(
                        english: "The accepted duel uses its chosen category for the headline score.",
                        norwegian: "En godtatt duell bruker valgt gren som hovedscore."
                    ), systemImage: "checkmark.shield")
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                    .padding(.top, 9)
                }
            }
        }
        .padding(16)
        .background(ATHLTHTheme.surfaceStone.opacity(0.56),
                    in: RoundedRectangle(cornerRadius: 20))
    }

    private func scoreDetailRow(
        _ title: String, mine: Double, theirs: Double
    ) -> some View {
        HStack {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(ATHLTHTheme.primaryText)
            Spacer()
            Text("\(Int(mine.rounded())) – \(Int(theirs.rounded())) p")
                .font(.caption.monospacedDigit())
                .foregroundStyle(ATHLTHTheme.accentDeep)
        }
    }

    private var matchupShareText: String {
        let friend = selectedFriend?.resolvedName ?? "Friend"
        return "ATHLTH · Head-to-head\n" +
            "\(currentDisplayName) vs \(friend)\n" +
            "\(primaryScoreTitle): " +
            "\(primaryScoreText(primaryScoreValues.mine)) – " +
            "\(primaryScoreText(primaryScoreValues.theirs))\n" +
            primaryScoreSubtitle
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

        if directMetric(
            for: duel
        ) == .workoutCount {
            return directWorkoutCountValues(
                for: duel
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
            .workoutCount,
            .workouts
        ):
            return .highlighted

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

    private func directWorkoutCountValues(
        for duel:
            ATHLTHChallenge
    ) -> (
        mine: Double?,
        theirs: Double?
    ) {
        let start =
            duel.rules.startsAt
        let end =
            duel.rules.endsAt ??
            Date.distantFuture

        let myCount =
            health.workouts
                .filter {
                    $0.startDate >= start &&
                    $0.startDate <= end
                }
                .count

        let friendCount =
            friendActivities
                .filter {
                    $0.kind == "workout" &&
                    $0.createdAt >= start &&
                    $0.createdAt <= end
                }
                .count

        return (
            Double(myCount),
            Double(friendCount)
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
