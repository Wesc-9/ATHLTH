import Foundation
import SwiftUI

enum CommunityLeaderboardScope: String, CaseIterable, Identifiable {
    case friends = "Friends"
    case community = "Community"

    var id: String { rawValue }
}

enum CommunityLeaderboardPeriod: String, CaseIterable, Identifiable {
    case week = "Week"
    case month = "Month"

    var id: String { rawValue }

    var days: Int {
        switch self {
        case .week: return 7
        case .month: return 30
        }
    }
}

enum CommunityLeaderboardMetric: String, CaseIterable, Identifiable {
    case consistency = "Consistency"
    case workouts = "Workouts"
    case running = "Running"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .consistency: return "calendar.badge.checkmark"
        case .workouts: return "dumbbell.fill"
        case .running: return "figure.run"
        }
    }

    var tint: Color {
        switch self {
        case .consistency: return ATHLTHTheme.vitality
        case .workouts: return .purple
        case .running: return .green
        }
    }

    var explanation: String {
        switch self {
        case .consistency:
            return "Training days"
        case .workouts:
            return "Completed workouts"
        case .running:
            return "Running distance"
        }
    }
}

struct CommunityLeaderboardEntry: Identifiable, Hashable {
    let id: UUID
    let displayName: String
    let username: String?
    let avatarURL: URL?
    let score: Double
    let workoutCount: Int
    let isCurrentUser: Bool
    let friend: SocialProfileCard?
}

struct CommunityPulseCard: View {
    let activeFriends: Int
    let activeChallenges: Int
    let upcomingEvents: Int

    var body: some View {
        HStack(spacing: 9) {
            pulseTile(
                value: "\(activeFriends)",
                title: "friends active",
                icon: "person.2.fill",
                tint: ATHLTHTheme.vitality
            )

            pulseTile(
                value: "\(activeChallenges)",
                title: "challenges",
                icon: "bolt.fill",
                tint: .orange
            )

            pulseTile(
                value: "\(upcomingEvents)",
                title: "events",
                icon: "calendar",
                tint: .purple
            )
        }
    }

    private func pulseTile(
        value: String,
        title: String,
        icon: String,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)

                Spacer()

                Text(value)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(ATHLTHTheme.primaryText)
                    .monospacedDigit()
            }

            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(ATHLTHTheme.mutedText)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    tint.opacity(0.085),
                    ATHLTHTheme.cardWarm.opacity(0.66)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(
                cornerRadius: 17,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 17,
                style: .continuous
            )
            .stroke(Color.white.opacity(0.72), lineWidth: 0.8)
        }
    }
}

struct CommunityLeaderboardCard: View {
    let currentUserID: UUID
    let currentDisplayName: String
    let currentUsername: String?
    let currentAvatarURL: URL?
    let friends: [SocialProfileCard]
    let visibleProfiles: [SocialProfileCard]
    let feed: [SocialFeedItem]
    let ownWorkouts: [WorkoutSummary]
    let onChallenge: (SocialProfileCard) -> Void

    @State private var scope: CommunityLeaderboardScope = .friends
    @State private var period: CommunityLeaderboardPeriod = .week
    @State private var metric: CommunityLeaderboardMetric = .consistency

    private var rankedEntries: [CommunityLeaderboardEntry] {
        let threshold = Calendar.current.date(
            byAdding: .day,
            value: -period.days,
            to: Date()
        ) ?? .distantPast

        let allowedIDs: Set<UUID>
        switch scope {
        case .friends:
            allowedIDs = Set(friends.map(\.userID)).union([currentUserID])
        case .community:
            let visible = visibleProfiles.map(\.userID)
            let actors = feed.map { $0.actor.userID }
            allowedIDs = Set(visible + actors + [currentUserID])
        }

        let friendByID = Dictionary(
            uniqueKeysWithValues: friends.map { ($0.userID, $0) }
        )

        var profilesByID = Dictionary(
            uniqueKeysWithValues:
                (visibleProfiles + friends)
                .reduce(into: [UUID: SocialProfileCard]()) {
                    $0[$1.userID] = $1
                }
                .map { ($0.key, $0.value) }
        )

        for item in feed {
            profilesByID[item.actor.userID] = item.actor
        }

        var result: [CommunityLeaderboardEntry] = []

        for userID in allowedIDs {
            if userID == currentUserID {
                let workouts = ownWorkouts.filter {
                    $0.startDate >= threshold &&
                    $0.startDate <= Date()
                }

                let score = ownScore(
                    workouts: workouts,
                    metric: metric
                )

                result.append(
                    CommunityLeaderboardEntry(
                        id: currentUserID,
                        displayName: currentDisplayName,
                        username: currentUsername,
                        avatarURL: currentAvatarURL,
                        score: score,
                        workoutCount: workouts.count,
                        isCurrentUser: true,
                        friend: nil
                    )
                )
                continue
            }

            guard let profile = profilesByID[userID] else {
                continue
            }

            let activities = feed.filter {
                $0.actor.userID == userID &&
                $0.activity.createdAt >= threshold &&
                $0.activity.createdAt <= Date()
            }

            let workoutActivities = activities.filter {
                $0.activity.kind == "workout"
            }

            result.append(
                CommunityLeaderboardEntry(
                    id: userID,
                    displayName: profile.resolvedName,
                    username: profile.username,
                    avatarURL: profile.avatarURL.flatMap(URL.init(string:)),
                    score: socialScore(
                        activities: workoutActivities,
                        metric: metric
                    ),
                    workoutCount: workoutActivities.count,
                    isCurrentUser: false,
                    friend: friendByID[userID]
                )
            )
        }

        let visibleResult = result.filter {
            scope == .friends ||
            $0.isCurrentUser ||
            $0.score > 0
        }

        return visibleResult.sorted {
            if $0.score == $1.score {
                if $0.workoutCount == $1.workoutCount {
                    return $0.displayName.localizedCaseInsensitiveCompare(
                        $1.displayName
                    ) == .orderedAscending
                }
                return $0.workoutCount > $1.workoutCount
            }
            return $0.score > $1.score
        }
    }

    var body: some View {
        ATHLTHCard {
            header
            controls

            if rankedEntries.isEmpty {
                ContentUnavailableView(
                    "No leaderboard activity yet",
                    systemImage: "trophy",
                    description: Text(
                        "Complete or share workouts to start building the leaderboard."
                    )
                )
                .padding(.vertical, 28)
            } else {
                podium
                    .padding(.top, 16)

                if rankedEntries.count > 3 {
                    Divider()
                        .padding(.vertical, 14)

                    VStack(spacing: 5) {
                        ForEach(
                            Array(rankedEntries.dropFirst(3).prefix(5).enumerated()),
                            id: \.element.id
                        ) { offset, entry in
                            leaderboardRow(
                                rank: offset + 4,
                                entry: entry
                            )
                        }
                    }
                }

                if let currentRank = currentUserRank,
                   currentRank > 8,
                   let current = rankedEntries.first(
                        where: { $0.isCurrentUser }
                   ) {
                    Divider()
                        .padding(.vertical, 12)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("YOUR POSITION")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1.2)
                            .foregroundStyle(ATHLTHTheme.mutedText)

                        leaderboardRow(
                            rank: currentRank,
                            entry: current
                        )
                    }
                }

                Text(
                    scope == .friends
                        ? "Based on your workouts and activity your friends chose to share."
                        : "Community rankings use activity that is visible to you."
                )
                .font(.caption2)
                .foregroundStyle(ATHLTHTheme.mutedText)
                .padding(.top, 12)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text("Leaderboard")
                        .font(.title3.weight(.bold))

                    Image(systemName: "trophy.fill")
                        .font(.caption)
                        .foregroundStyle(ATHLTHTheme.premiumGold)
                }

                Text(
                    "\(metric.explanation) · last \(period.days) days"
                )
                .font(.caption)
                .foregroundStyle(ATHLTHTheme.mutedText)
            }

            Spacer()

            Menu {
                ForEach(CommunityLeaderboardMetric.allCases) { item in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            metric = item
                        }
                    } label: {
                        Label(item.rawValue, systemImage: item.icon)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: metric.icon)
                    Text(metric.rawValue)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(metric.tint)
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(
                    metric.tint.opacity(0.09),
                    in: Capsule()
                )
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            Picker("Leaderboard scope", selection: $scope) {
                ForEach(CommunityLeaderboardScope.allCases) {
                    Text($0.rawValue).tag($0)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 6) {
                ForEach(CommunityLeaderboardPeriod.allCases) { item in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            period = item
                        }
                    } label: {
                        Text(item.rawValue)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(
                                period == item
                                    ? ATHLTHTheme.primaryText
                                    : ATHLTHTheme.mutedText
                            )
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                            .background {
                                if period == item {
                                    Capsule()
                                        .fill(ATHLTHTheme.cardWarm)
                                        .shadow(
                                            color:
                                                ATHLTHTheme.accentDeep
                                                .opacity(0.07),
                                            radius: 5,
                                            y: 2
                                        )
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(
                ATHLTHTheme.surfaceStone.opacity(0.80),
                in: Capsule()
            )
        }
        .padding(.top, 12)
    }

    @ViewBuilder
    private var podium: some View {
        let top = Array(rankedEntries.prefix(3))

        HStack(alignment: .bottom, spacing: 8) {
            if top.count > 1 {
                podiumEntry(
                    rank: 2,
                    entry: top[1],
                    height: 112
                )
            } else {
                Spacer(minLength: 0)
            }

            if let first = top.first {
                podiumEntry(
                    rank: 1,
                    entry: first,
                    height: 142
                )
            }

            if top.count > 2 {
                podiumEntry(
                    rank: 3,
                    entry: top[2],
                    height: 102
                )
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func podiumEntry(
        rank: Int,
        entry: CommunityLeaderboardEntry,
        height: CGFloat
    ) -> some View {
        VStack(spacing: 7) {
            ZStack(alignment: .topTrailing) {
                leaderboardAvatar(entry, size: rank == 1 ? 58 : 48)

                Text("\(rank)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 21, height: 21)
                    .background(
                        podiumTint(rank),
                        in: Circle()
                    )
                    .overlay {
                        Circle()
                            .stroke(Color.white, lineWidth: 1.5)
                    }
                    .offset(x: 3, y: -3)
            }

            Text(entry.displayName)
                .font(
                    rank == 1
                        ? .subheadline.weight(.bold)
                        : .caption.weight(.semibold)
                )
                .foregroundStyle(ATHLTHTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(scoreText(entry.score))
                .font(
                    rank == 1
                        ? .headline.weight(.bold)
                        : .subheadline.weight(.bold)
                )
                .foregroundStyle(metric.tint)
                .monospacedDigit()

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 7)
        .padding(.top, 12)
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(
            LinearGradient(
                colors: [
                    podiumTint(rank).opacity(rank == 1 ? 0.14 : 0.075),
                    ATHLTHTheme.cardWarm.opacity(0.56)
                ],
                startPoint: .top,
                endPoint: .bottom
            ),
            in: RoundedRectangle(
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
                podiumTint(rank).opacity(rank == 1 ? 0.20 : 0.10),
                lineWidth: 1
            )
        }
    }

    private func leaderboardRow(
        rank: Int,
        entry: CommunityLeaderboardEntry
    ) -> some View {
        HStack(spacing: 11) {
            Text("#\(rank)")
                .font(.caption.weight(.bold))
                .foregroundStyle(
                    entry.isCurrentUser
                        ? ATHLTHTheme.accentDeep
                        : ATHLTHTheme.mutedText
                )
                .frame(width: 28, alignment: .leading)

            leaderboardAvatar(entry, size: 40)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(entry.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.primaryText)
                        .lineLimit(1)

                    if entry.isCurrentUser {
                        Text("YOU")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                ATHLTHTheme.champagneSoft,
                                in: Capsule()
                            )
                    }
                }

                if let username = entry.username,
                   !username.isEmpty {
                    Text("@\(username)")
                        .font(.caption2)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                }
            }

            Spacer()

            if let friend = entry.friend {
                Button {
                    onChallenge(friend)
                } label: {
                    Image(systemName: "bolt.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.orange)
                        .frame(width: 31, height: 31)
                        .background(
                            Color.orange.opacity(0.09),
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    "Challenge \(entry.displayName)"
                )
            }

            Text(scoreText(entry.score))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(metric.tint)
                .monospacedDigit()
                .frame(minWidth: 62, alignment: .trailing)
        }
        .padding(.horizontal, 9)
        .frame(height: 58)
        .background(
            entry.isCurrentUser
                ? ATHLTHTheme.champagneSoft.opacity(0.65)
                : Color.clear,
            in: RoundedRectangle(
                cornerRadius: 14,
                style: .continuous
            )
        )
    }

    private func leaderboardAvatar(
        _ entry: CommunityLeaderboardEntry,
        size: CGFloat
    ) -> some View {
        AsyncImage(url: entry.avatarURL) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            default:
                Circle()
                    .fill(ATHLTHTheme.surfaceSage)
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.system(size: size * 0.36))
                            .foregroundStyle(
                                ATHLTHTheme.accentDeep.opacity(0.62)
                            )
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(Color.white.opacity(0.88), lineWidth: 1.5)
        }
    }

    private var currentUserRank: Int? {
        guard let index = rankedEntries.firstIndex(
            where: { $0.isCurrentUser }
        ) else {
            return nil
        }

        return index + 1
    }

    private func ownScore(
        workouts: [WorkoutSummary],
        metric: CommunityLeaderboardMetric
    ) -> Double {
        switch metric {
        case .consistency:
            return Double(
                Set(
                    workouts.map {
                        Calendar.current.startOfDay(
                            for: $0.startDate
                        )
                    }
                ).count
            )

        case .workouts:
            return Double(workouts.count)

        case .running:
            return workouts
                .filter { $0.activity == .running }
                .compactMap(\.distanceMeters)
                .reduce(0, +) / 1_000
        }
    }

    private func socialScore(
        activities: [SocialFeedItem],
        metric: CommunityLeaderboardMetric
    ) -> Double {
        switch metric {
        case .consistency:
            return Double(
                Set(
                    activities.map {
                        Calendar.current.startOfDay(
                            for: $0.activity.createdAt
                        )
                    }
                ).count
            )

        case .workouts:
            return Double(activities.count)

        case .running:
            return activities.reduce(0) {
                $0 + runningKilometers($1.activity)
            }
        }
    }

    private func runningKilometers(
        _ activity: SocialActivityRecord
    ) -> Double {
        guard activity.metadata?["kind"] == "running" ||
              activity.title.lowercased().contains("running")
        else {
            return 0
        }

        if let raw = activity.metadata?["distance_meters"],
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
                  let value = Double(parts[parts.index(before: index)])
            else {
                continue
            }

            return value
        }

        return 0
    }

    private func scoreText(_ score: Double) -> String {
        switch metric {
        case .consistency:
            let value = Int(score.rounded())
            return "\(value) day\(value == 1 ? "" : "s")"

        case .workouts:
            return "\(Int(score.rounded()))"

        case .running:
            return String(format: "%.1f km", score)
        }
    }

    private func podiumTint(_ rank: Int) -> Color {
        switch rank {
        case 1: return ATHLTHTheme.premiumGold
        case 2: return Color.gray.opacity(0.72)
        default: return Color.orange.opacity(0.74)
        }
    }
}

struct CommunityDiscoverPeopleCard: View {
    let profiles: [SocialProfileCard]
    let onAdd: (SocialProfileCard) -> Void
    let relationship: (UUID) -> SocialRelationshipState

    var body: some View {
        ATHLTHCard {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Discover People")
                        .font(.title3.weight(.bold))
                    Text("Find athletes to follow, train and compete with.")
                        .font(.caption)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                }

                Spacer()

                NavigationLink {
                    SocialHubView(initialTab: .discover)
                } label: {
                    Text("See All")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                }
            }

            if profiles.isEmpty {
                Text(
                    "New people will appear here when they become discoverable."
                )
                .font(.caption)
                .foregroundStyle(ATHLTHTheme.mutedText)
                .padding(.top, 12)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(profiles.prefix(8)) { profile in
                            discoverCard(profile)
                        }
                    }
                    .padding(.top, 12)
                }
            }
        }
    }

    private func discoverCard(
        _ profile: SocialProfileCard
    ) -> some View {
        VStack(spacing: 9) {
            NavigationLink {
                FriendProfileView(userID: profile.userID)
            } label: {
                VStack(spacing: 8) {
                    SocialAvatar(profile: profile, size: 58)

                    Text(profile.resolvedName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.primaryText)
                        .lineLimit(1)
                        .frame(width: 96)

                    Text(profile.usernameLabel)
                        .font(.caption2)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                        .lineLimit(1)
                        .frame(width: 96)
                }
            }
            .buttonStyle(.plain)

            let state = relationship(profile.userID)

            Button {
                if state == .none {
                    onAdd(profile)
                }
            } label: {
                Text(
                    state == .none
                        ? "Add"
                        : state == .friends
                            ? "Friends"
                            : "Pending"
                )
                .font(.caption2.weight(.semibold))
                .foregroundStyle(
                    state == .none
                        ? Color.white
                        : ATHLTHTheme.accentDeep
                )
                .frame(width: 86, height: 30)
                .background(
                    state == .none
                        ? ATHLTHTheme.accentDeep
                        : ATHLTHTheme.accentSoft,
                    in: Capsule()
                )
            }
            .buttonStyle(.plain)
            .disabled(state != .none)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .frame(width: 116)
        .background(
            LinearGradient(
                colors: [
                    ATHLTHTheme.surfaceSage.opacity(0.72),
                    ATHLTHTheme.cardWarm.opacity(0.58)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
            .stroke(Color.white.opacity(0.78), lineWidth: 0.8)
        }
    }
}
