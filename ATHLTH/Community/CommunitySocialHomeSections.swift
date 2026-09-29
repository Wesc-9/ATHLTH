import SwiftUI

struct CommunityClubPulseCard: View {
    @EnvironmentObject private var groups: CommunityGroupStore

    private var joinedActivity: [CommunityGroupActivityRecord] {
        let joined = groups.joinedGroupIDs

        let all = groups.communityActivity
            .filter { joined.contains($0.groupID) }
            .sorted { $0.createdAt > $1.createdAt }

        let meaningful = all.filter {
            $0.kind != "member_joined"
        }

        return meaningful.isEmpty
            ? all
            : meaningful
    }

    var body: some View {
        ATHLTHCard {
            header

            if joinedActivity.isEmpty {
                emptyState
                    .padding(.top, 14)
            } else {
                VStack(spacing: 0) {
                    ForEach(
                        Array(
                            joinedActivity
                                .prefix(4)
                                .enumerated()
                        ),
                        id: \.element.id
                    ) { index, activity in
                        pulseRow(activity)

                        if index <
                            min(
                                joinedActivity.count,
                                4
                            ) - 1 {
                            Divider()
                                .padding(.leading, 58)
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    private var header: some View {
        HStack(
            alignment: .firstTextBaseline,
            spacing: 12
        ) {
            VStack(
                alignment: .leading,
                spacing: 3
            ) {
                HStack(spacing: 7) {
                    Text("Club Pulse")
                        .font(
                            .title3
                                .weight(.bold)
                        )

                    Circle()
                        .fill(
                            ATHLTHTheme
                                .vitality
                        )
                        .frame(
                            width: 7,
                            height: 7
                        )
                }

                Text(
                    "What is happening in your clubs."
                )
                .font(.caption)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
            }

            Spacer()

            NavigationLink {
                CommunityGroupActivityCenterView()
            } label: {
                HStack(spacing: 5) {
                    Text("All activity")
                    Image(
                        systemName:
                            "chevron.right"
                    )
                    .font(.caption2.bold())
                }
                .font(
                    .caption
                        .weight(.semibold)
                )
                .foregroundStyle(
                    ATHLTHTheme.accentDeep
                )
            }
        }
    }

    @ViewBuilder
    private func pulseRow(
        _ item: CommunityGroupActivityRecord
    ) -> some View {
        if let group =
            groups.group(
                for: item.groupID
            ) {
            NavigationLink {
                CommunityGroupDetailView(
                    group: group
                )
            } label: {
                HStack(
                    alignment: .top,
                    spacing: 12
                ) {
                    clubAvatar(
                        group
                    )

                    VStack(
                        alignment: .leading,
                        spacing: 4
                    ) {
                        HStack(
                            spacing: 6
                        ) {
                            Text(
                                group.name
                            )
                            .font(
                                .caption
                                    .weight(
                                        .bold
                                    )
                            )
                            .foregroundStyle(
                                ATHLTHTheme
                                    .accentDeep
                            )
                            .lineLimit(1)

                            Text("·")
                                .foregroundStyle(
                                    .tertiary
                                )

                            Text(
                                item.createdAt,
                                style: .relative
                            )
                            .font(
                                .caption2
                            )
                            .foregroundStyle(
                                .tertiary
                            )
                            .lineLimit(1)
                        }

                        Text(
                            item.headline
                        )
                        .font(
                            .subheadline
                                .weight(
                                    .semibold
                                )
                        )
                        .foregroundStyle(
                            ATHLTHTheme
                                .primaryText
                        )
                        .fixedSize(
                            horizontal:
                                false,
                            vertical:
                                true
                        )

                        if let detail =
                                item.detail,
                           !detail.isEmpty {
                            Text(detail)
                                .font(
                                    .caption
                                )
                                .foregroundStyle(
                                    .secondary
                                )
                                .lineLimit(2)
                        }
                    }

                    Spacer(
                        minLength: 4
                    )

                    activityBadge(
                        item.kind
                    )
                }
                .padding(
                    .vertical,
                    11
                )
                .contentShape(
                    Rectangle()
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func clubAvatar(
        _ group:
            CommunityGroupRecord
    ) -> some View {
        Group {
            if let raw =
                    group.imageURL,
               let url =
                    URL(
                        string: raw
                    ) {
                AsyncImage(
                    url: url
                ) { phase in
                    switch phase {
                    case .success(
                        let image
                    ):
                        image
                            .resizable()
                            .scaledToFill()

                    default:
                        clubPlaceholder
                    }
                }
            } else {
                clubPlaceholder
            }
        }
        .frame(
            width: 46,
            height: 46
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 14,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 14,
                style: .continuous
            )
            .stroke(
                Color.white
                    .opacity(0.82),
                lineWidth: 1
            )
        }
    }

    private var clubPlaceholder:
        some View {
        RoundedRectangle(
            cornerRadius: 14,
            style: .continuous
        )
        .fill(
            LinearGradient(
                colors: [
                    Color.indigo
                        .opacity(0.13),
                    ATHLTHTheme
                        .champagneSoft
                        .opacity(0.70)
                ],
                startPoint:
                    .topLeading,
                endPoint:
                    .bottomTrailing
            )
        )
        .overlay {
            Image(
                systemName:
                    "person.3.fill"
            )
            .font(
                .system(
                    size: 16,
                    weight: .semibold
                )
            )
            .foregroundStyle(
                .indigo
            )
        }
    }

    private func activityBadge(
        _ kind: String
    ) -> some View {
        let visual =
            activityVisual(
                kind
            )

        return Image(
            systemName:
                visual.icon
        )
        .font(
            .system(
                size: 13,
                weight: .semibold
            )
        )
        .foregroundStyle(
            visual.tint
        )
        .frame(
            width: 34,
            height: 34
        )
        .background(
            visual.tint
                .opacity(0.09),
            in:
                RoundedRectangle(
                    cornerRadius: 11,
                    style: .continuous
                )
        )
    }

    private func activityVisual(
        _ kind: String
    ) -> (
        icon: String,
        tint: Color
    ) {
        switch kind {
        case "announcement":
            return (
                "megaphone.fill",
                .orange
            )

        case "event_created":
            return (
                "calendar.badge.plus",
                .purple
            )

        case "challenge_created":
            return (
                "trophy.fill",
                .green
            )

        case "member_joined":
            return (
                "person.badge.plus",
                .indigo
            )

        default:
            return (
                "sparkles",
                ATHLTHTheme
                    .accentDeep
            )
        }
    }

    private var emptyState:
        some View {
        HStack(
            spacing: 13
        ) {
            Image(
                systemName:
                    "person.3.sequence.fill"
            )
            .font(.title3)
            .foregroundStyle(
                .indigo
            )
            .frame(
                width: 46,
                height: 46
            )
            .background(
                Color.indigo
                    .opacity(0.08),
                in:
                    RoundedRectangle(
                        cornerRadius: 14,
                        style: .continuous
                    )
            )

            VStack(
                alignment: .leading,
                spacing: 3
            ) {
                Text(
                    groups.joinedGroups
                        .isEmpty
                        ? "Join your first club"
                        : "Your clubs are quiet right now"
                )
                .font(
                    .subheadline
                        .weight(.semibold)
                )

                Text(
                    groups.joinedGroups
                        .isEmpty
                        ? "Announcements, events and challenges will show up here."
                        : "New announcements, events and challenges will appear here."
                )
                .font(.caption)
                .foregroundStyle(
                    .secondary
                )
            }

            Spacer()
        }
    }
}

struct CommunityYourClubsSection:
    View {
    @EnvironmentObject private var groups:
        CommunityGroupStore

    private var clubs:
        [CommunityGroupRecord] {
        groups.joinedGroups
            .sorted {
                latestActivityDate(
                    for: $0
                ) >
                latestActivityDate(
                    for: $1
                )
            }
    }

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 11
        ) {
            HStack(
                alignment:
                    .firstTextBaseline
            ) {
                VStack(
                    alignment: .leading,
                    spacing: 3
                ) {
                    Text("Your Clubs")
                        .font(
                            .title3
                                .weight(
                                    .bold
                                )
                        )

                    Text(
                        "Jump back into the people you train with."
                    )
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                    )
                }

                Spacer()

                NavigationLink {
                    CommunityGroupsView()
                } label: {
                    HStack(
                        spacing: 5
                    ) {
                        Text("All clubs")
                        Image(
                            systemName:
                                "chevron.right"
                        )
                        .font(
                            .caption2
                                .bold()
                        )
                    }
                    .font(
                        .caption
                            .weight(
                                .semibold
                            )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .accentDeep
                    )
                }
            }
            .padding(
                .horizontal,
                2
            )

            if clubs.isEmpty {
                emptyClubCard
            } else {
                ScrollView(
                    .horizontal,
                    showsIndicators: false
                ) {
                    LazyHStack(
                        spacing: 11
                    ) {
                        ForEach(
                            clubs.prefix(6)
                        ) { group in
                            clubCard(
                                group
                            )
                        }
                    }
                    .padding(
                        .horizontal,
                        1
                    )
                }
            }
        }
    }

    private func clubCard(
        _ group:
            CommunityGroupRecord
    ) -> some View {
        NavigationLink {
            CommunityGroupDetailView(
                group: group
            )
        } label: {
            ZStack(
                alignment:
                    .bottomLeading
            ) {
                cover(
                    group
                )

                LinearGradient(
                    colors: [
                        .clear,
                        .black
                            .opacity(
                                0.68
                            )
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(
                    alignment: .leading,
                    spacing: 5
                ) {
                    HStack(
                        spacing: 6
                    ) {
                        Circle()
                            .fill(
                                ATHLTHTheme
                                    .vitality
                            )
                            .frame(
                                width: 7,
                                height: 7
                            )

                        Text(
                            roleLabel(
                                group
                            )
                        )
                        .font(
                            .system(
                                size: 9,
                                weight: .bold
                            )
                        )
                        .tracking(
                            0.8
                        )
                        .textCase(
                            .uppercase
                        )
                    }
                    .foregroundStyle(
                        .white
                            .opacity(
                                0.92
                            )
                    )

                    Spacer()

                    Text(
                        group.name
                    )
                    .font(
                        .headline
                            .weight(.bold)
                    )
                    .foregroundStyle(
                        .white
                    )
                    .lineLimit(2)

                    if let latest =
                            latestActivity(
                                for:
                                    group
                            ) {
                        Text(
                            latest.headline
                        )
                        .font(
                            .caption
                        )
                        .foregroundStyle(
                            .white
                                .opacity(
                                    0.80
                                )
                        )
                        .lineLimit(1)
                    } else if !group
                        .locationName
                        .isEmpty {
                        Text(
                            group.locationName
                        )
                        .font(
                            .caption
                        )
                        .foregroundStyle(
                            .white
                                .opacity(
                                    0.80
                                )
                        )
                        .lineLimit(1)
                    }

                    HStack(
                        spacing: 4
                    ) {
                        Text(
                            latestActivityText(
                                for:
                                    group
                            )
                        )

                        Spacer()

                        Image(
                            systemName:
                                "arrow.up.right"
                        )
                    }
                    .font(
                        .caption2
                            .weight(
                                .semibold
                            )
                    )
                    .foregroundStyle(
                        .white
                            .opacity(
                                0.78
                            )
                    )
                }
                .padding(14)
            }
            .frame(
                width: 224,
                height: 170
            )
            .clipShape(
                RoundedRectangle(
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
                    Color.white
                        .opacity(0.42),
                    lineWidth: 0.8
                )
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func cover(
        _ group:
            CommunityGroupRecord
    ) -> some View {
        if let raw =
                group.imageURL,
           let url =
                URL(
                    string: raw
                ) {
            AsyncImage(
                url: url
            ) { phase in
                switch phase {
                case .success(
                    let image
                ):
                    image
                        .resizable()
                        .scaledToFill()

                default:
                    fallbackCover
                }
            }
        } else {
            fallbackCover
        }
    }

    private var fallbackCover:
        some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.indigo
                        .opacity(0.78),
                    ATHLTHTheme
                        .accentDeep
                ],
                startPoint:
                    .topLeading,
                endPoint:
                    .bottomTrailing
            )

            Image(
                systemName:
                    "person.3.fill"
            )
            .font(
                .system(
                    size: 52,
                    weight: .semibold
                )
            )
            .foregroundStyle(
                .white
                    .opacity(0.24)
            )
            .offset(
                x: 54,
                y: -25
            )
        }
    }

    private var emptyClubCard:
        some View {
        NavigationLink {
            CommunityGroupsView()
        } label: {
            HStack(
                spacing: 14
            ) {
                Image(
                    systemName:
                        "person.3.fill"
                )
                .font(.title2)
                .foregroundStyle(
                    .indigo
                )
                .frame(
                    width: 52,
                    height: 52
                )
                .background(
                    Color.indigo
                        .opacity(0.08),
                    in:
                        RoundedRectangle(
                            cornerRadius: 16,
                            style:
                                .continuous
                        )
                )

                VStack(
                    alignment:
                        .leading,
                    spacing: 4
                ) {
                    Text(
                        "Find your people"
                    )
                    .font(
                        .headline
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .primaryText
                    )

                    Text(
                        "Join a club to get shared activity, events and challenges here."
                    )
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
                .font(
                    .caption.bold()
                )
                .foregroundStyle(
                    .tertiary
                )
            }
            .padding(16)
            .background(
                ATHLTHTheme
                    .cardWarm
                    .opacity(0.78),
                in:
                    RoundedRectangle(
                        cornerRadius: 22,
                        style:
                            .continuous
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func latestActivity(
        for group:
            CommunityGroupRecord
    ) -> CommunityGroupActivityRecord? {
        groups.communityActivity
            .filter {
                $0.groupID ==
                    group.id
            }
            .max {
                $0.createdAt <
                    $1.createdAt
            }
    }

    private func latestActivityDate(
        for group:
            CommunityGroupRecord
    ) -> Date {
        latestActivity(
            for: group
        )?
        .createdAt ??
        group.updatedAt
    }

    private func latestActivityText(
        for group:
            CommunityGroupRecord
    ) -> String {
        guard let activity =
                latestActivity(
                    for: group
                )
        else {
            return group
                .locationName
                .isEmpty
                ? "Open club"
                : group.locationName
        }

        return activity
            .createdAt
            .formatted(
                .relative(
                    presentation:
                        .named
                )
            )
    }

    private func roleLabel(
        _ group:
            CommunityGroupRecord
    ) -> String {
        switch groups.role(
            in: group
        ) {
        case "owner":
            return "Owner"

        case "admin":
            return "Admin"

        case "contributor":
            return "Contributor"

        default:
            return "Member"
        }
    }
}
