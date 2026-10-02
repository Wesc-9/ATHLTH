import SwiftUI

struct ATHLTHExploreView: View {
    @StateObject private var locationStore = HomeLocationStore()

    var body: some View {
        NavigationStack {
            AroundYouExploreView(
                locationStore: locationStore,
                embeddedInTab: true
            )
        }
    }
}

struct ExploreDiscoveryHubView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var groups: CommunityGroupStore
    @EnvironmentObject private var challenges: ChallengeStore
    @EnvironmentObject private var social: SocialStore

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    discoveryIntro
                    clubsSection
                    challengesSection
                    activitySection
                }
                .padding(16)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .background(ATHLTHPremiumCanvas())
            .navigationTitle("Discover")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .refreshable {
                async let groupsRefresh: Void =
                    groups.refresh(force: true)
                async let feedRefresh: Void =
                    social.refreshHomeFeed(force: true)

                _ = await (
                    groupsRefresh,
                    feedRefresh
                )
            }
            .task {
                async let groupsRefresh: Void =
                    groups.refresh()
                async let feedRefresh: Void =
                    social.refreshHomeFeed()

                _ = await (
                    groupsRefresh,
                    feedRefresh
                )
            }
        }
    }

    private var discoveryIntro: some View {
        ATHLTHCard {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(ATHLTHTheme.premiumGold)
                    .frame(width: 46, height: 46)
                    .background(
                        ATHLTHTheme.champagneSoft,
                        in: RoundedRectangle(
                            cornerRadius: 14,
                            style: .continuous
                        )
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text("More than a map")
                        .font(.headline)

                    Text(
                        "Explore connects places with people: routes and events stay on the map, while clubs, challenges and public activity live here."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
        }
    }

    private var clubsSection: some View {
        ATHLTHCard {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Clubs")
                        .font(.title3.weight(.bold))

                    Text("Groups visible to your account")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                NavigationLink {
                    CommunityGroupsView()
                } label: {
                    Text("See all")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                }
            }

            if groups.groups.isEmpty {
                emptyRow(
                    icon: "person.3.fill",
                    title: "No clubs yet",
                    detail: "Public and joined clubs will appear here as they become available."
                )
                .padding(.top, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(groups.groups.prefix(5))) { group in
                        NavigationLink {
                            CommunityGroupDetailView(group: group)
                        } label: {
                            discoveryRow(
                                icon: "person.3.fill",
                                title: group.name,
                                subtitle:
                                    group.locationName.isEmpty
                                        ? group.summary
                                        : "\(group.locationName) · \(group.summary)"
                            )
                        }
                        .buttonStyle(.plain)

                        if group.id != groups.groups.prefix(5).last?.id {
                            Divider()
                                .padding(.leading, 46)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private var challengesSection: some View {
        ATHLTHCard {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Challenges")
                        .font(.title3.weight(.bold))

                    Text("Active, upcoming and location-aware challenges")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                NavigationLink {
                    ChallengeHubView()
                } label: {
                    Text("See all")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                }
            }

            let visible = Array(
                challenges.visibleChallenges
                    .filter {
                        $0.status != .cancelled &&
                        $0.status != .completed
                    }
                    .prefix(5)
            )

            if visible.isEmpty {
                emptyRow(
                    icon: "flag.checkered",
                    title: "No active challenges",
                    detail: "Challenges will appear here when you create, join or discover them."
                )
                .padding(.top, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(visible) { challenge in
                        NavigationLink {
                            ChallengeDetailView(
                                challengeID: challenge.id
                            )
                        } label: {
                            discoveryRow(
                                icon: challenge.sport.systemImage,
                                title: challenge.title,
                                subtitle: challengeSubtitle(challenge)
                            )
                        }
                        .buttonStyle(.plain)

                        if challenge.id != visible.last?.id {
                            Divider()
                                .padding(.leading, 46)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private var activitySection: some View {
        ATHLTHCard {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Public activity")
                        .font(.title3.weight(.bold))

                    Text("A lightweight pulse from the ATHLTH community")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "waveform.path")
                    .foregroundStyle(ATHLTHTheme.vitality)
            }

            let items = Array(
                social.feed
                    .filter {
                        $0.activity.visibility ==
                            ProfileVisibility.publicProfile.rawValue
                    }
                    .prefix(5)
            )

            if items.isEmpty {
                emptyRow(
                    icon: "figure.run",
                    title: "Nothing public yet",
                    detail: "Public workouts and updates will appear here when people choose to share them."
                )
                .padding(.top, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(items) { item in
                        HStack(alignment: .top, spacing: 11) {
                            Circle()
                                .fill(ATHLTHTheme.accentSoft)
                                .frame(width: 34, height: 34)
                                .overlay {
                                    Text(
                                        String(
                                            item.actor.resolvedName
                                                .prefix(1)
                                        )
                                        .uppercased()
                                    )
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(
                                        ATHLTHTheme.accentDeep
                                    )
                                }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.activity.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(
                                        ATHLTHTheme.primaryText
                                    )

                                Text(
                                    activitySubtitle(item)
                                )
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 10)

                        if item.id != items.last?.id {
                            Divider()
                                .padding(.leading, 45)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private func discoveryRow(
        icon: String,
        title: String,
        subtitle: String
    ) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ATHLTHTheme.accentDeep)
                .frame(width: 34, height: 34)
                .background(
                    ATHLTHTheme.accentSoft,
                    in: RoundedRectangle(
                        cornerRadius: 11,
                        style: .continuous
                    )
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.primaryText)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption2.bold())
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 10)
    }

    private func emptyRow(
        icon: String,
        title: String,
        detail: String
    ) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
                .background(
                    Color.primary.opacity(0.04),
                    in: RoundedRectangle(
                        cornerRadius: 11,
                        style: .continuous
                    )
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))

                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
    }

    private func challengeSubtitle(
        _ challenge: ATHLTHChallenge
    ) -> String {
        var parts = [
            challenge.sport.title,
            challenge.status.rawValue.capitalized
        ]

        if let meetup = challenge.rules.meetup {
            parts.append(
                meetup.scheduledAt.formatted(
                    date: .abbreviated,
                    time: .shortened
                )
            )
        } else if let route = challenge.rules.route {
            parts.append(
                String(
                    format: "%.1f km route",
                    route.distanceKilometers
                )
            )
        }

        return parts.joined(separator: " · ")
    }

    private func activitySubtitle(
        _ item: SocialFeedItem
    ) -> String {
        var parts = [item.actor.resolvedName]

        if let subtitle = item.activity.subtitle,
           !subtitle.isEmpty {
            parts.append(subtitle)
        }

        parts.append(
            item.activity.createdAt.formatted(
                date: .abbreviated,
                time: .shortened
            )
        )

        return parts.joined(separator: " · ")
    }
}
