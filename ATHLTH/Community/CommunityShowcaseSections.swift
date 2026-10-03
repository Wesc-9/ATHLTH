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
        guard let workouts,
              let activeMinutes else {
            return nil
        }

        // Balanced across training types: completing a workout matters,
        // while duration contributes with a per-workout cap so long sessions
        // cannot dominate the matchup.
        let cappedMinutes =
            min(
                max(activeMinutes, 0),
                max(workouts, 0) * 120
            )

        return
            max(workouts, 0) * 20 +
            cappedMinutes / 5
    }
}

struct CommunityFriendsVsFriendsDetailView: View {
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var health: HealthKitManager

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
                    periodPicker
                    metricCard
                    contextCard
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

            VStack(spacing: 6) {
                Text("VS")
                    .font(
                        .system(
                            size: 18,
                            weight: .black,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.accentDeep
                    )

                Image(
                    systemName:
                        "bolt.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
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
        .padding(.vertical, 18)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
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
            color: Color.black.opacity(0.035),
            radius: 12,
            y: 5
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

        return VStack(spacing: 0) {
                matchupHeader

                metricRow(
                    ATHLTHLocalization.choose(
                        english: "Activity points",
                        norwegian: "Aktivitetspoeng"
                    ),
                    icon: "bolt.circle.fill",
                    mine:
                        mine.calculatedActivityPoints,
                    theirs:
                        theirs.calculatedActivityPoints,
                    format: pointsText
                )

                Divider()

                metricRow(
                    "Workouts",
                    icon:
                        "figure.run.circle.fill",
                    mine: mine.workouts,
                    theirs: theirs.workouts,
                    format: countText
                )

                Divider()

                metricRow(
                    "Running",
                    icon: "figure.run",
                    mine:
                        mine.runningKilometers,
                    theirs:
                        theirs
                            .runningKilometers,
                    format: distanceText
                )

                Divider()

                metricRow(
                    "Active time",
                    icon: "clock.fill",
                    mine:
                        mine.activeMinutes,
                    theirs:
                        theirs.activeMinutes,
                    format: minutesText
                )

                if period != .allTime {
                    Divider()

                    metricRow(
                        "Strength",
                        icon:
                            "dumbbell.fill",
                        mine:
                            mine.strengthWorkouts,
                        theirs:
                            theirs
                                .strengthWorkouts,
                        format: countText
                    )

                    Divider()

                    metricRow(
                        "PRs",
                        icon: "bolt.fill",
                        mine:
                            mine.personalRecords,
                        theirs:
                            theirs
                                .personalRecords,
                        format: countText
                    )

                    Divider()

                    metricRow(
                        "Challenges",
                        icon: "trophy.fill",
                        mine:
                            mine.challenges,
                        theirs:
                            theirs.challenges,
                        format: countText
                    )
                }
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
        format: (Double?) -> String
    ) -> some View {
        HStack(spacing: 10) {
            Text(format(mine))
                .font(
                    .subheadline
                        .monospacedDigit()
                        .weight(.bold)
                )
                .foregroundStyle(
                    metricTint(
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
                        ATHLTHTheme
                            .accentDeep
                    )

                Text(title)
                    .font(.caption)
                    .foregroundStyle(
                        .secondary
                    )
            }
            .frame(
                maxWidth: .infinity
            )

            Text(format(theirs))
                .font(
                    .subheadline
                        .monospacedDigit()
                        .weight(.bold)
                )
                .foregroundStyle(
                    metricTint(
                        theirs,
                        versus: mine
                    )
                )
                .frame(
                    width: 82,
                    alignment: .trailing
                )
        }
        .padding(.vertical, 11)
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
                AsyncImage(url: url) { phase in
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
