import MapKit
import SwiftUI
import UIKit

struct CommunityShowcaseShortcutStrip: View {
    let clubsCount: Int
    let challengeCount: Int
    let eventCount: Int

    var body: some View {
        HStack(spacing: 9) {
            NavigationLink {
                CommunityGroupsView()
            } label: {
                shortcut(
                    title: "Clubs",
                    value: clubsCount,
                    icon: "person.3.fill",
                    tint: .indigo
                )
            }

            NavigationLink {
                ChallengeHubView()
            } label: {
                shortcut(
                    title: "Challenges",
                    value: challengeCount,
                    icon: "trophy.fill",
                    tint: .orange
                )
            }

            NavigationLink {
                CommunityEventsView()
            } label: {
                shortcut(
                    title: "Events",
                    value: eventCount,
                    icon: "calendar",
                    tint: .purple
                )
            }
        }
        .buttonStyle(.plain)
    }

    private func shortcut(
        title: String,
        value: Int,
        icon: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(
                    tint.opacity(0.09),
                    in: RoundedRectangle(
                        cornerRadius: 11,
                        style: .continuous
                    )
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(ATHLTHTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text("\(value)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(
            ATHLTHTheme.cardWarm.opacity(0.78),
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
            .stroke(Color.white.opacity(0.75), lineWidth: 0.8)
        }
    }
}

struct CommunityChallengeSpotlightCard: View {
    let challenge: ATHLTHChallenge?
    let currentUserID: UUID
    let profiles: [SocialProfileCard]
    let onCreate: () -> Void

    var body: some View {
        Group {
            if let challenge {
                NavigationLink {
                    ChallengeDetailView(
                        challengeID: challenge.id
                    )
                } label: {
                    challengeCard(challenge)
                }
                .buttonStyle(.plain)
            } else {
                emptyChallengeCard
            }
        }
    }

    private func challengeCard(
        _ challenge: ATHLTHChallenge
    ) -> some View {
        ZStack(alignment: .bottomLeading) {
            Image(
                challenge.sport == .strength
                    ? "TrainHero"
                    : "CommunityHero"
            )
            .resizable()
            .scaledToFill()

            LinearGradient(
                colors: [
                    .black.opacity(0.08),
                    .black.opacity(0.68)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    Label(
                        spotlightLabel(challenge),
                        systemImage: "trophy.fill"
                    )
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.1)
                    .foregroundStyle(
                        ATHLTHTheme.accentDeep
                    )
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(
                        ATHLTHTheme.champagneSoft,
                        in: Capsule()
                    )

                    Spacer()

                    Text(timeRemaining(challenge))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.90))
                }

                Spacer(minLength: 0)

                HStack(alignment: .bottom, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(challenge.title)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)

                        Text(challengeSummary(challenge))
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.82))
                            .lineLimit(2)

                        HStack(spacing: -7) {
                            ForEach(
                                Array(
                                    acceptedParticipants(challenge)
                                        .prefix(4)
                                )
                            ) { participant in
                                participantAvatar(
                                    participant,
                                    size: 30
                                )
                            }

                            Text(
                                "\(acceptedParticipants(challenge).count) participating"
                            )
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.90))
                            .padding(.leading, 14)
                        }
                        .padding(.top, 4)
                    }

                    Spacer(minLength: 8)

                    progressRing(challenge)
                }
            }
            .padding(16)
        }
        .frame(height: 245)
        .frame(maxWidth: .infinity)
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
            .stroke(Color.white.opacity(0.36), lineWidth: 1)
        }
    }

    private var emptyChallengeCard: some View {
        ATHLTHCard {
            HStack(spacing: 14) {
                Image(systemName: "trophy.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                    .frame(width: 52, height: 52)
                    .background(
                        Color.orange.opacity(0.09),
                        in: RoundedRectangle(
                            cornerRadius: 15,
                            style: .continuous
                        )
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text("Start a community challenge")
                        .font(.headline)

                    Text(
                        "Create a running, route or strength challenge and invite your people."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 4)

                Button("Create") {
                    onCreate()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.orange)
            }
        }
    }

    private func acceptedParticipants(
        _ challenge: ATHLTHChallenge
    ) -> [ChallengeParticipant] {
        challenge.participants.filter {
            $0.state == .creator ||
            $0.state == .accepted
        }
    }

    private func participantAvatar(
        _ participant: ChallengeParticipant,
        size: CGFloat
    ) -> some View {
        let profile = participant.userID.flatMap { userID in
            profiles.first {
                $0.userID == userID
            }
        }

        return CommunityShowcaseAvatar(
            url: profile?.avatarURL.flatMap(URL.init(string:)),
            fallback:
                profile?.resolvedName ??
                participant.displayName,
            size: size
        )
        .overlay {
            Circle()
                .stroke(.white, lineWidth: 1.5)
        }
    }

    private func spotlightLabel(
        _ challenge: ATHLTHChallenge
    ) -> String {
        guard let endsAt = challenge.rules.endsAt else {
            return "FEATURED CHALLENGE"
        }

        let days = Calendar.current.dateComponents(
            [.day],
            from: Date(),
            to: endsAt
        ).day ?? 99

        return days <= 8
            ? "WEEKLY CHALLENGE"
            : "FEATURED CHALLENGE"
    }

    private func timeRemaining(
        _ challenge: ATHLTHChallenge
    ) -> String {
        if challenge.status == .upcoming ||
            challenge.status == .invited {
            return challenge.rules.startsAt.formatted(
                .dateTime.month(.abbreviated).day()
            )
        }

        guard let endsAt = challenge.rules.endsAt else {
            return "Open"
        }

        let days = max(
            Calendar.current.dateComponents(
                [.day],
                from: Date(),
                to: endsAt
            ).day ?? 0,
            0
        )

        return days == 0
            ? "Ends today"
            : "\(days) day\(days == 1 ? "" : "s") left"
    }

    private func challengeSummary(
        _ challenge: ATHLTHChallenge
    ) -> String {
        if let route = challenge.rules.route {
            return String(
                format:
                    "%.1f km route challenge · %@",
                route.distanceKilometers,
                challenge.rules.scoring.title
            )
        }

        if let distance = challenge.rules.targetDistanceMeters {
            return String(
                format:
                    "%.0f km · %@",
                distance / 1_000,
                challenge.rules.scoring.title
            )
        }

        return challenge.rules.scoring.title
    }

    private func progressRing(
        _ challenge: ATHLTHChallenge
    ) -> some View {
        let progress = challengeProgress(challenge)

        return ZStack {
            Circle()
                .stroke(
                    .white.opacity(0.22),
                    lineWidth: 8
                )

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    .white,
                    style: StrokeStyle(
                        lineWidth: 8,
                        lineCap: .round
                    )
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 0) {
                Text(
                    "\(Int((progress * 100).rounded()))%"
                )
                .font(
                    .system(
                        size: 19,
                        weight: .bold,
                        design: .rounded
                    )
                )

                Text("complete")
                    .font(.system(size: 8.5, weight: .medium))
            }
            .foregroundStyle(.white)
        }
        .frame(width: 78, height: 78)
    }

    private func challengeProgress(
        _ challenge: ATHLTHChallenge
    ) -> Double {
        if challenge.status == .completed {
            return 1
        }

        if challenge.status == .upcoming ||
            challenge.status == .invited {
            return 0
        }

        if let participant = challenge.participants.first(
            where: { $0.userID == currentUserID }
        ),
        let target = challenge.rules.targetDistanceMeters,
        target > 0 {
            let distance = challenge.attempts
                .filter {
                    $0.participantID == participant.id &&
                    $0.isEligible
                }
                .compactMap(\.distanceMeters)
                .reduce(0, +)

            return min(max(distance / target, 0), 1)
        }

        guard let endsAt = challenge.rules.endsAt else {
            return challenge.status == .active ? 0.18 : 0
        }

        let total = endsAt.timeIntervalSince(
            challenge.rules.startsAt
        )
        guard total > 0 else {
            return 0
        }

        let elapsed = Date().timeIntervalSince(
            challenge.rules.startsAt
        )
        return min(max(elapsed / total, 0), 1)
    }
}

struct CommunityRouteChallengeShowcaseCard: View {
    let challenge: ATHLTHChallenge?

    var body: some View {
        ATHLTHCard {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Label(
                        "Route Challenges",
                        systemImage: "map.fill"
                    )
                    .font(.title3.weight(.bold))
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )

                    Text(
                        "Take on shared routes and compare verified attempts."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                NavigationLink {
                    ChallengeHubView()
                } label: {
                    Text("View all")
                        .font(.caption.weight(.semibold))
                }
            }

            if let challenge,
               let route = challenge.rules.route {
                NavigationLink {
                    ChallengeDetailView(
                        challengeID: challenge.id
                    )
                } label: {
                    HStack(spacing: 13) {
                        CommunityRouteMapPreview(
                            coordinates: route.coordinates,
                            tint: .orange
                        )
                        .frame(width: 126, height: 108)

                        VStack(
                            alignment: .leading,
                            spacing: 5
                        ) {
                            Text(challenge.title)
                                .font(.headline)
                                .foregroundStyle(
                                    ATHLTHTheme.primaryText
                                )
                                .lineLimit(2)

                            Label(
                                String(
                                    format: "%.1f km",
                                    route.distanceKilometers
                                ),
                                systemImage: "figure.run"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)

                            Text(
                                "\(participantCount(challenge)) participants"
                            )
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(
                                ATHLTHTheme.accentDeep
                            )

                            Text("Open challenge")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.orange)
                                .padding(.top, 4)
                        }

                        Spacer(minLength: 0)

                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.top, 12)
                }
                .buttonStyle(.plain)
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "map.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.indigo)
                        .frame(width: 48, height: 48)
                        .background(
                            Color.indigo.opacity(0.08),
                            in: RoundedRectangle(
                                cornerRadius: 14,
                                style: .continuous
                            )
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Text("No route challenge is active")
                            .font(.subheadline.weight(.semibold))

                        Text(
                            "Browse community routes and turn one into your next challenge."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding(.top, 12)
            }
        }
    }

    private func participantCount(
        _ challenge: ATHLTHChallenge
    ) -> Int {
        challenge.participants.filter {
            $0.state == .creator ||
            $0.state == .accepted
        }.count
    }
}

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

                    Text("Running distance · last 7 days")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                NavigationLink {
                    SocialHubView(initialTab: .friends)
                } label: {
                    Text("View all")
                        .font(.caption.weight(.semibold))
                }
            }

            if entries.isEmpty {
                Text(
                    "Add friends to start comparing shared activity."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 14)
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
        guard activity.metadata?["kind"] == "running" ||
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

struct CommunityShowcaseActionStrip: View {
    let onCreateChallenge: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Button {
                onCreateChallenge()
            } label: {
                action(
                    title: "Create Challenge",
                    subtitle: "Run, workout or route",
                    icon: "trophy.fill",
                    tint: .orange
                )
            }

            NavigationLink {
                SocialHubView(initialTab: .discover)
            } label: {
                action(
                    title: "Invite Friends",
                    subtitle: "Grow your crew",
                    icon: "person.2.badge.plus",
                    tint: .indigo
                )
            }

            NavigationLink {
                CommunityPopularRoutesView()
            } label: {
                action(
                    title: "Browse Routes",
                    subtitle: "Discover & explore",
                    icon: "map.fill",
                    tint: .green
                )
            }
        }
        .buttonStyle(.plain)
    }

    private func action(
        title: String,
        subtitle: String,
        icon: String,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)

            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(ATHLTHTheme.primaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.76)

            Text(subtitle)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(11)
        .frame(
            maxWidth: .infinity,
            minHeight: 104,
            alignment: .leading
        )
        .background(
            tint.opacity(0.055),
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
            .stroke(tint.opacity(0.10), lineWidth: 1)
        }
    }
}

struct CommunityClubActivityShowcaseCard: View {
    @EnvironmentObject private var groups: CommunityGroupStore

    private var activity: [CommunityGroupActivityRecord] {
        groups.communityActivity.filter {
            groups.joinedGroupIDs.contains($0.groupID)
        }
    }

    var body: some View {
        ATHLTHCard {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Club Activity")
                        .font(.title3.weight(.bold))

                    Text(
                        "Latest updates from the clubs you belong to."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                NavigationLink {
                    CommunityGroupActivityCenterView()
                } label: {
                    Text("View all")
                        .font(.caption.weight(.semibold))
                }
            }

            if activity.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "bell.badge")
                        .font(.title3)
                        .foregroundStyle(.indigo)
                        .frame(width: 44, height: 44)
                        .background(
                            Color.indigo.opacity(0.08),
                            in: RoundedRectangle(
                                cornerRadius: 13,
                                style: .continuous
                            )
                        )

                    Text(
                        "Club joins, announcements, events and challenges will appear here."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Spacer()
                }
                .padding(.top, 12)
            } else {
                VStack(spacing: 10) {
                    ForEach(activity.prefix(4)) { item in
                        activityRow(item)
                    }
                }
                .padding(.top, 12)
            }
        }
    }

    private func activityRow(
        _ item: CommunityGroupActivityRecord
    ) -> some View {
        HStack(alignment: .top, spacing: 11) {
            clubIdentity(item.groupID)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if let group = groups.group(
                        for: item.groupID
                    ) {
                        Text(group.name)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(
                                ATHLTHTheme.accentDeep
                            )
                    }

                    Text("·")
                        .foregroundStyle(.tertiary)

                    Text(
                        item.createdAt,
                        style: .relative
                    )
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }

                Text(item.headline)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )

                if let detail = item.detail,
                   !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: activityIcon(item.kind))
                .font(.caption.weight(.semibold))
                .foregroundStyle(activityTint(item.kind))
                .frame(width: 30, height: 30)
                .background(
                    activityTint(item.kind).opacity(0.08),
                    in: RoundedRectangle(
                        cornerRadius: 9,
                        style: .continuous
                    )
                )
        }
        .padding(11)
        .background(
            Color.primary.opacity(0.025),
            in: RoundedRectangle(
                cornerRadius: 16,
                style: .continuous
            )
        )
    }

    @ViewBuilder
    private func clubIdentity(
        _ groupID: UUID
    ) -> some View {
        if let group = groups.group(for: groupID),
           let raw = group.imageURL,
           let url = URL(string: raw) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    clubPlaceholder
                }
            }
            .frame(width: 42, height: 42)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 12,
                    style: .continuous
                )
            )
        } else {
            clubPlaceholder
        }
    }

    private var clubPlaceholder: some View {
        RoundedRectangle(
            cornerRadius: 12,
            style: .continuous
        )
        .fill(Color.indigo.opacity(0.08))
        .frame(width: 42, height: 42)
        .overlay {
            Image(systemName: "person.3.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.indigo)
        }
    }

    private func activityIcon(
        _ kind: String
    ) -> String {
        switch kind {
        case "member_joined":
            return "person.badge.plus"
        case "announcement":
            return "megaphone.fill"
        case "event_created":
            return "calendar.badge.plus"
        case "challenge_created":
            return "trophy.fill"
        default:
            return "bell.fill"
        }
    }

    private func activityTint(
        _ kind: String
    ) -> Color {
        switch kind {
        case "member_joined":
            return .indigo
        case "announcement":
            return .orange
        case "event_created":
            return .purple
        case "challenge_created":
            return .green
        default:
            return ATHLTHTheme.accent
        }
    }
}

struct CommunityPopularRoutesShowcaseCard: View {
    let routes: [CommunityRouteRecord]

    var body: some View {
        ATHLTHCard {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Popular Routes")
                        .font(.title3.weight(.bold))

                    Text(
                        "Routes shared with the ATHLTH community."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                NavigationLink {
                    CommunityPopularRoutesView()
                } label: {
                    Text("View all")
                        .font(.caption.weight(.semibold))
                }
            }

            if routes.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "map.fill")
                        .font(.title3)
                        .foregroundStyle(.green)
                        .frame(width: 44, height: 44)
                        .background(
                            Color.green.opacity(0.08),
                            in: RoundedRectangle(
                                cornerRadius: 13,
                                style: .continuous
                            )
                        )

                    Text(
                        "Public and shared routes will appear here when they become available."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Spacer()
                }
                .padding(.top, 12)
            } else {
                ScrollView(
                    .horizontal,
                    showsIndicators: false
                ) {
                    HStack(spacing: 10) {
                        ForEach(routes.prefix(3)) { route in
                            routeCard(route)
                        }
                    }
                    .padding(.top, 12)
                }
            }
        }
    }

    private func routeCard(
        _ route: CommunityRouteRecord
    ) -> some View {
        NavigationLink {
            RouteDetailView(
                route: route.trainingRoute
            )
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                CommunityRouteMapPreview(
                    coordinates: route.coordinates,
                    tint: .orange
                )
                .frame(height: 104)

                Text(route.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )
                    .lineLimit(1)

                HStack(spacing: 9) {
                    Label(
                        String(
                            format:
                                "%.1f km",
                            route.distanceKilometers
                        ),
                        systemImage: "figure.run"
                    )

                    if let elevation =
                        route.elevationGainMeters {
                        Label(
                            "\(Int(elevation.rounded())) m",
                            systemImage: "mountain.2.fill"
                        )
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .padding(10)
            .frame(width: 210, alignment: .leading)
            .background(
                Color.primary.opacity(0.025),
                in: RoundedRectangle(
                    cornerRadius: 17,
                    style: .continuous
                )
            )
        }
        .buttonStyle(.plain)
    }
}

struct CommunityPopularRoutesView: View {
    @EnvironmentObject private var routeDiscovery: RouteDiscoveryStore

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                if routeDiscovery.isLoading &&
                    routeDiscovery.routes.isEmpty {
                    ProgressView("Loading routes…")
                        .padding(.top, 50)
                } else if routeDiscovery.routes.isEmpty {
                    ContentUnavailableView(
                        "No community routes yet",
                        systemImage: "map",
                        description: Text(
                            "Shared routes will appear here."
                        )
                    )
                    .padding(.top, 50)
                } else {
                    ForEach(routeDiscovery.routes) { route in
                        NavigationLink {
                            RouteDetailView(
                                route: route.trainingRoute
                            )
                        } label: {
                            ATHLTHCard {
                                CommunityRouteMapPreview(
                                    coordinates:
                                        route.coordinates,
                                    tint: .orange
                                )
                                .frame(height: 150)

                                HStack(alignment: .top) {
                                    VStack(
                                        alignment: .leading,
                                        spacing: 4
                                    ) {
                                        Text(route.title)
                                            .font(.headline)
                                            .foregroundStyle(
                                                ATHLTHTheme
                                                    .primaryText
                                            )

                                        HStack(spacing: 10) {
                                            Label(
                                                String(
                                                    format:
                                                        "%.1f km",
                                                    route
                                                        .distanceKilometers
                                                ),
                                                systemImage:
                                                    "figure.run"
                                            )

                                            if let elevation =
                                                route
                                                    .elevationGainMeters {
                                                Label(
                                                    "\(Int(elevation.rounded())) m",
                                                    systemImage:
                                                        "mountain.2.fill"
                                                )
                                            }
                                        }
                                        .font(.caption)
                                        .foregroundStyle(
                                            .secondary
                                        )
                                    }

                                    Spacer()

                                    Image(
                                        systemName:
                                            "chevron.right"
                                    )
                                    .font(.caption.bold())
                                    .foregroundStyle(.tertiary)
                                }
                                .padding(.top, 8)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Community Routes")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if routeDiscovery.routes.isEmpty {
                await routeDiscovery.refresh()
            }
        }
        .refreshable {
            await routeDiscovery.refresh()
        }
    }
}

private struct CommunityRouteMapPreview: View {
    let coordinates: [RouteCoordinate]
    let tint: Color

    @State private var snapshotImage: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(
                cornerRadius: 14,
                style: .continuous
            )
            .fill(Color(.secondarySystemBackground))

            if let snapshotImage {
                Image(uiImage: snapshotImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "map")
                    .font(.title2)
                    .foregroundStyle(.secondary.opacity(0.55))
            }
        }
        .clipped()
        .clipShape(
            RoundedRectangle(
                cornerRadius: 14,
                style: .continuous
            )
        )
        .task(id: snapshotKey) {
            snapshotImage =
                await CommunityRouteSnapshotRenderer.shared.image(
                    for: coordinates,
                    tint: UIColor(tint)
                )
        }
    }

    private var snapshotKey: String {
        CommunityRouteSnapshotRenderer.cacheKey(
            for: coordinates
        )
    }
}

@MainActor
private final class CommunityRouteSnapshotRenderer {
    static let shared = CommunityRouteSnapshotRenderer()

    private let cache = NSCache<NSString, UIImage>()

    private init() {
        // Keep the Community dashboard lightweight even after scrolling
        // through many routes.
        cache.countLimit = 24
        cache.totalCostLimit = 24 * 1_024 * 1_024
    }

    static func cacheKey(
        for coordinates: [RouteCoordinate]
    ) -> String {
        guard !coordinates.isEmpty else {
            return "empty-route"
        }

        let sampled = sampledCoordinates(
            coordinates,
            maximumCount: 12
        )

        return sampled.map {
            String(
                format: "%.5f,%.5f",
                $0.latitude,
                $0.longitude
            )
        }
        .joined(separator: "|")
    }

    func image(
        for coordinates: [RouteCoordinate],
        tint: UIColor
    ) async -> UIImage? {
        let key = Self.cacheKey(for: coordinates) as NSString

        if let cached = cache.object(forKey: key) {
            return cached
        }

        let values = Self.sampledCoordinates(
            coordinates,
            maximumCount: 160
        )
        guard !values.isEmpty else {
            return nil
        }

        let options = MKMapSnapshotter.Options()
        options.region = Self.region(for: values)
        options.size = CGSize(width: 420, height: 220)
        options.scale = 2
        options.mapType = .mutedStandard
        options.pointOfInterestFilter = .excludingAll
        options.traitCollection =
            UITraitCollection(userInterfaceStyle: .light)

        do {
            let snapshot =
                try await MKMapSnapshotter(
                    options: options
                )
                .start()

            let rendererFormat =
                UIGraphicsImageRendererFormat.default()
            rendererFormat.scale = 2
            rendererFormat.opaque = true

            let renderer = UIGraphicsImageRenderer(
                size: options.size,
                format: rendererFormat
            )

            let rendered = renderer.image { _ in
                snapshot.image.draw(
                    in: CGRect(
                        origin: .zero,
                        size: options.size
                    )
                )

                guard values.count >= 2 else {
                    return
                }

                let path = UIBezierPath()
                path.lineWidth = 4
                path.lineCapStyle = .round
                path.lineJoinStyle = .round

                for (index, value) in values.enumerated() {
                    let point = snapshot.point(
                        for: CLLocationCoordinate2D(
                            latitude: value.latitude,
                            longitude: value.longitude
                        )
                    )

                    if index == 0 {
                        path.move(to: point)
                    } else {
                        path.addLine(to: point)
                    }
                }

                UIColor.white
                    .withAlphaComponent(0.88)
                    .setStroke()
                path.lineWidth = 7
                path.stroke()

                tint.setStroke()
                path.lineWidth = 4
                path.stroke()
            }

            cache.setObject(
                rendered,
                forKey: key,
                cost:
                    Int(
                        rendered.size.width *
                        rendered.size.height *
                        rendered.scale *
                        rendered.scale *
                        4
                    )
            )
            return rendered
        } catch {
            return nil
        }
    }

    nonisolated static func sampledCoordinates(
        _ values: [RouteCoordinate],
        maximumCount: Int
    ) -> [RouteCoordinate] {
        guard values.count > maximumCount,
              maximumCount > 2
        else {
            return values
        }

        let lastIndex = values.count - 1
        let step =
            Double(lastIndex) /
            Double(maximumCount - 1)

        return (0..<maximumCount).map { index in
            values[
                min(
                    Int((Double(index) * step).rounded()),
                    lastIndex
                )
            ]
        }
    }

    nonisolated static func region(
        for values: [RouteCoordinate]
    ) -> MKCoordinateRegion {
        guard let first = values.first else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(
                    latitude: 59.9139,
                    longitude: 10.7522
                ),
                span: MKCoordinateSpan(
                    latitudeDelta: 0.12,
                    longitudeDelta: 0.12
                )
            )
        }

        var minLatitude = first.latitude
        var maxLatitude = first.latitude
        var minLongitude = first.longitude
        var maxLongitude = first.longitude

        for value in values.dropFirst() {
            minLatitude = min(minLatitude, value.latitude)
            maxLatitude = max(maxLatitude, value.latitude)
            minLongitude = min(minLongitude, value.longitude)
            maxLongitude = max(maxLongitude, value.longitude)
        }

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude:
                    (minLatitude + maxLatitude) / 2,
                longitude:
                    (minLongitude + maxLongitude) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: max(
                    (maxLatitude - minLatitude) * 1.45,
                    0.012
                ),
                longitudeDelta: max(
                    (maxLongitude - minLongitude) * 1.45,
                    0.012
                )
            )
        )
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
