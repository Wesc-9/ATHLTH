import Foundation
import MapKit
import SwiftUI

enum ATHLTHGlobalSearchScope: String, CaseIterable, Identifiable {
    case all = "All"
    case users = "People"
    case routes = "Routes"
    case groups = "Clubs"
    case events = "Events"
    case challenges = "Challenges"

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .all:
            return ATHLTHLocalization.string("All")
        case .users:
            return ATHLTHLocalization.string("People")
        case .routes:
            return ATHLTHLocalization.string("Routes")
        case .groups:
            return ATHLTHLocalization.string("Clubs")
        case .events:
            return ATHLTHLocalization.string("Events")
        case .challenges:
            return ATHLTHLocalization.string("Challenges")
        }
    }

    var icon: String {
        switch self {
        case .all: return "sparkles"
        case .users: return "person.2.fill"
        case .routes: return "map.fill"
        case .groups: return "person.3.fill"
        case .events: return "calendar"
        case .challenges: return "flag.checkered"
        }
    }
}

struct ATHLTHGlobalSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var routes: RouteDiscoveryStore
    @EnvironmentObject private var community: CommunityEventStore
    @EnvironmentObject private var challenges: ChallengeStore
    @EnvironmentObject private var groups: CommunityGroupStore

    @AppStorage("athlth.globalSearch.recent")
    private var recentSearchesRaw = "[]"

    @State private var query = ""
    @State private var scope: ATHLTHGlobalSearchScope = .all
    @FocusState private var searchFocused: Bool

    private var normalizedQuery: String {
        query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private var recentSearches: [String] {
        guard let data = recentSearchesRaw.data(using: .utf8),
              let values = try? JSONDecoder().decode(
                [String].self,
                from: data
              )
        else {
            return []
        }

        return values
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ATHLTHPremiumCanvas(
                    accent: ATHLTHTheme.vitality.opacity(0.34)
                )

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        searchHeader
                        premiumSearchField
                        filterBar

                        if normalizedQuery.isEmpty {
                            searchLanding
                        } else {
                            searchResults
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 34)
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .toolbar(.hidden, for: .navigationBar)
            .onSubmit(of: .search) {
                rememberSearch(query)
            }
            .task {
                async let socialRefresh: Void = social.refresh()
                async let routeRefresh: Void = routes.refresh()
                async let eventRefresh: Void = community.refresh()
                async let groupRefresh: Void = groups.refresh()
                _ = await (
                    socialRefresh,
                    routeRefresh,
                    eventRefresh,
                    groupRefresh
                )
            }
        }
    }

    private var searchHeader: some View {
        ZStack {
            Text("Search")
                .font(.system(size: 25, weight: .bold, design: .rounded))
                .foregroundStyle(ATHLTHTheme.primaryText)

            HStack {
                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(ATHLTHTheme.primaryText)
                        .frame(width: 38, height: 38)
                        .background(
                            .ultraThinMaterial,
                            in: Circle()
                        )
                        .overlay {
                            Circle()
                                .stroke(
                                    Color.primary.opacity(0.08),
                                    lineWidth: 1
                                )
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close search")
            }
        }
        .frame(height: 44)
    }

    private var premiumSearchField: some View {
        HStack(spacing: 11) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(ATHLTHTheme.accentDeep)

            TextField(
                "People, routes, clubs, events and challenges",
                text: $query
            )
            .font(.subheadline)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.search)
            .focused($searchFocused)

            if !query.isEmpty {
                Button {
                    query = ""
                    searchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .background(
            ATHLTHTheme.card,
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
                searchFocused
                    ? ATHLTHTheme.accent.opacity(0.28)
                    : Color.primary.opacity(0.07),
                lineWidth: 1
            )
        }
        .shadow(
            color: Color.black.opacity(searchFocused ? 0.07 : 0.035),
            radius: searchFocused ? 14 : 9,
            y: 5
        )
        .animation(
            .easeOut(duration: 0.16),
            value: searchFocused
        )
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ATHLTHGlobalSearchScope.allCases) { item in
                    Button {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            scope = item
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: item.icon)
                                .font(.system(size: 11, weight: .bold))
                            Text(item.rawValue)
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(
                            scope == item
                                ? Color.white
                                : ATHLTHTheme.primaryText
                        )
                        .padding(.horizontal, 13)
                        .frame(height: 38)
                        .background(
                            scope == item
                                ? ATHLTHTheme.accentDeep
                                : ATHLTHTheme.card.opacity(0.92),
                            in: Capsule()
                        )
                        .overlay {
                            if scope != item {
                                Capsule()
                                    .stroke(
                                        Color.primary.opacity(0.07),
                                        lineWidth: 1
                                    )
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var searchLanding: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !recentSearches.isEmpty {
                recentSearchesSection
            }

            if scope == .all {
                discoverSection
            } else {
                categoryLanding
            }
        }
        .padding(.top, 4)
    }

    private var recentSearchesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                searchSectionTitle("Recent")

                Spacer()

                Button("Clear") {
                    recentSearchesRaw = "[]"
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(ATHLTHTheme.accentDeep)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(recentSearches.prefix(6), id: \.self) { value in
                        Button {
                            query = value
                            searchFocused = true
                        } label: {
                            HStack(spacing: 7) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 11, weight: .semibold))
                                Text(value)
                                    .lineLimit(1)
                            }
                            .font(.caption.weight(.medium))
                            .foregroundStyle(ATHLTHTheme.primaryText)
                            .padding(.horizontal, 12)
                            .frame(height: 36)
                            .background(
                                ATHLTHTheme.card,
                                in: Capsule()
                            )
                            .overlay {
                                Capsule()
                                    .stroke(
                                        Color.primary.opacity(0.06),
                                        lineWidth: 1
                                    )
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var discoverSection: some View {
        if !community.upcomingEvents.isEmpty ||
            !routes.routes.isEmpty ||
            !challenges.visibleChallenges.isEmpty ||
            !groups.groups.isEmpty {
            Text("DISCOVER")
                .font(.caption.weight(.semibold))
                .tracking(1.8)
                .foregroundStyle(ATHLTHTheme.mutedText)

            if let group = groups.groups.first {
                NavigationLink {
                    CommunityGroupDetailView(group: group)
                } label: {
                    discoveryRow(
                        icon: "person.3.fill",
                        tint: .indigo,
                        title: group.name,
                        subtitle: group.locationName + " · Group"
                    )
                }
                .buttonStyle(.plain)
            }

            if let event = community.upcomingEvents.first {
                NavigationLink {
                    CommunityEventDetailView(eventID: event.id)
                } label: {
                    discoveryRow(
                        icon: event.event.activityType.systemImage,
                        tint: .purple,
                        title: event.event.title,
                        subtitle: "Upcoming event · " +
                            event.event.startsAt.formatted(
                                date: .abbreviated,
                                time: .shortened
                            )
                    )
                }
                .buttonStyle(.plain)
            }

            if let route = routes.routes.first {
                NavigationLink {
                    ATHLTHGlobalRouteDetailView(route: route)
                } label: {
                    discoveryRow(
                        icon: "map.fill",
                        tint: .green,
                        title: route.title,
                        subtitle: String(
                            format: "%.1f km · Public route",
                            route.distanceKilometers
                        )
                    )
                }
                .buttonStyle(.plain)
            }

            if let challenge = challenges.visibleChallenges.first {
                NavigationLink {
                    ChallengeDetailView(challengeID: challenge.id)
                } label: {
                    discoveryRow(
                        icon: challenge.sport.systemImage,
                        tint: .orange,
                        title: challenge.title,
                        subtitle: "Challenge · " + challenge.sport.title
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var categoryLanding: some View {
        VStack(alignment: .leading, spacing: 10) {
            searchSectionTitle(scope.localizedTitle)

            ATHLTHCard {
                HStack(spacing: 14) {
                    Image(systemName: scope.icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                        .frame(width: 46, height: 46)
                        .background(
                            ATHLTHTheme.accentSoft,
                            in: RoundedRectangle(
                                cornerRadius: 14,
                                style: .continuous
                            )
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Text(
                            ATHLTHLocalization.format(
                                english: "Search %@",
                                norwegian: "Søk i %@",
                                scope.localizedTitle.lowercased()
                            )
                        )
                            .font(.headline)
                        Text("Start typing to narrow ATHLTH to this category.")
                            .font(.caption)
                            .foregroundStyle(ATHLTHTheme.mutedText)
                    }

                    Spacer()
                }
            }
        }
    }

    private func searchSectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(1.7)
            .foregroundStyle(ATHLTHTheme.mutedText)
    }

    private var searchEmptyState: some View {
        ATHLTHCard {
            VStack(spacing: 13) {
                Image(systemName: "magnifyingglass.circle.fill")
                    .font(.system(size: 42, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(ATHLTHTheme.accentDeep)

                Text("Nothing found")
                    .font(.title3.weight(.bold))

                Text(
                    "Try another name, place or training term — or switch category above."
                )
                .font(.caption)
                .foregroundStyle(ATHLTHTheme.mutedText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 330)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }

    @ViewBuilder
    private var searchResults: some View {
        let users = matchingUsers
        let eventResults = matchingEvents
        let groupResults = matchingGroups
        let routeResults = matchingRoutes
        let challengeResults = matchingChallenges

        if normalizedQuery.count < 2 {
            ContentUnavailableView(
                "Keep typing",
                systemImage: "text.magnifyingglass",
                description: Text(
                    "Type at least two characters to search ATHLTH."
                )
            )
            .padding(.vertical, 80)
        } else if visibleResultCount == 0 {
            searchEmptyState
                .padding(.top, 18)
        } else {
            if (scope == .all || scope == .users) && !users.isEmpty {
                resultSection("USERS") {
                    ForEach(users.prefix(12)) { profile in
                        NavigationLink {
                            FriendProfileView(userID: profile.userID)
                        } label: {
                            HStack(spacing: 12) {
                                SocialAvatar(profile: profile, size: 46)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(profile.resolvedName)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(
                                            ATHLTHTheme.primaryText
                                        )
                                    Text(profile.usernameLabel)
                                        .font(.caption)
                                        .foregroundStyle(
                                            ATHLTHTheme.mutedText
                                        )
                                }

                                Spacer()

                                Text(userRelationshipLabel(profile))
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(
                                        ATHLTHTheme.accentDeep
                                    )

                                Image(systemName: "chevron.right")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(12)
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(
                            TapGesture().onEnded {
                                rememberSearch(query)
                            }
                        )
                    }
                }
            }

            if (scope == .all || scope == .groups) &&
                !groupResults.isEmpty {
                resultSection("GROUPS") {
                    ForEach(groupResults.prefix(8)) { group in
                        NavigationLink {
                            CommunityGroupDetailView(group: group)
                        } label: {
                            searchRow(
                                icon: "person.3.fill",
                                tint: .indigo,
                                title: group.name,
                                subtitle:
                                    group.locationName +
                                    (groups.joinedGroupIDs.contains(group.id)
                                        ? " · Joined"
                                        : " · Group")
                            )
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(
                            TapGesture().onEnded {
                                rememberSearch(query)
                            }
                        )
                    }
                }
            }

            if (scope == .all || scope == .events) &&
                !eventResults.isEmpty {
                resultSection("EVENTS") {
                    ForEach(eventResults.prefix(8)) { event in
                        NavigationLink {
                            CommunityEventDetailView(eventID: event.id)
                        } label: {
                            searchRow(
                                icon: event.event.activityType.systemImage,
                                tint: .purple,
                                title: event.event.title,
                                subtitle:
                                    event.event.startsAt.formatted(
                                        date: .abbreviated,
                                        time: .shortened
                                    ) +
                                    " · " +
                                    event.event.meetingName
                            )
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(
                            TapGesture().onEnded {
                                rememberSearch(query)
                            }
                        )
                    }
                }
            }

            if (scope == .all || scope == .routes) &&
                !routeResults.isEmpty {
                resultSection("ROUTES") {
                    ForEach(routeResults.prefix(6)) { route in
                        NavigationLink {
                            ATHLTHGlobalRouteDetailView(route: route)
                        } label: {
                            searchRow(
                                icon: "map.fill",
                                tint: .green,
                                title: route.title,
                                subtitle: routeSubtitle(route)
                            )
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(
                            TapGesture().onEnded {
                                rememberSearch(query)
                            }
                        )
                    }
                }
            }

            if (scope == .all || scope == .challenges) &&
                !challengeResults.isEmpty {
                resultSection("CHALLENGES") {
                    ForEach(challengeResults.prefix(6)) { challenge in
                        NavigationLink {
                            ChallengeDetailView(
                                challengeID: challenge.id
                            )
                        } label: {
                            searchRow(
                                icon: challenge.sport.systemImage,
                                tint: .orange,
                                title: challenge.title,
                                subtitle:
                                    challenge.sport.title +
                                    " · " +
                                    challenge.status.rawValue
                                        .replacingOccurrences(
                                            of: "_",
                                            with: " "
                                        )
                                        .capitalized
                            )
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(
                            TapGesture().onEnded {
                                rememberSearch(query)
                            }
                        )
                    }
                }
            }
        }
    }

    private var visibleResultCount: Int {
        switch scope {
        case .all:
            return matchingUsers.count +
                matchingEvents.count +
                matchingGroups.count +
                matchingRoutes.count +
                matchingChallenges.count
        case .users:
            return matchingUsers.count
        case .events:
            return matchingEvents.count
        case .groups:
            return matchingGroups.count
        case .routes:
            return matchingRoutes.count
        case .challenges:
            return matchingChallenges.count
        }
    }

    private var matchingUsers: [SocialProfileCard] {
        var seen = Set<UUID>()

        return (social.visibleProfiles + social.discoverResults)
            .filter { profile in
                guard profile.userID != social.currentUserID,
                      seen.insert(profile.userID).inserted
                else {
                    return false
                }

                return profile.resolvedName.lowercased()
                    .contains(normalizedQuery) ||
                    profile.usernameLabel.lowercased()
                    .contains(normalizedQuery)
            }
            .sorted {
                $0.resolvedName.localizedCaseInsensitiveCompare(
                    $1.resolvedName
                ) == .orderedAscending
            }
    }

    private func userRelationshipLabel(
        _ profile: SocialProfileCard
    ) -> String {
        if social.isFollowing(profile.userID) {
            return "Following"
        }

        if profile.isPrivateProfile {
            return "Private"
        }

        return "User"
    }

    private var matchingGroups: [CommunityGroupRecord] {
        groups.groups.filter {
            $0.name.lowercased().contains(normalizedQuery) ||
            $0.locationName.lowercased().contains(normalizedQuery) ||
            $0.summary.lowercased().contains(normalizedQuery)
        }
    }

    private var matchingRoutes: [CommunityRouteRecord] {
        routes.routes.filter {
            $0.title.lowercased().contains(normalizedQuery) ||
            ($0.startName?.lowercased().contains(normalizedQuery) ?? false) ||
            ($0.endName?.lowercased().contains(normalizedQuery) ?? false)
        }
    }

    private var matchingEvents: [CommunityEventItem] {
        community.upcomingEvents.filter {
            $0.event.title.lowercased().contains(normalizedQuery) ||
            $0.event.summary.lowercased().contains(normalizedQuery) ||
            $0.event.meetingName.lowercased().contains(normalizedQuery) ||
            $0.event.activityType.title.lowercased()
                .contains(normalizedQuery)
        }
    }

    private var matchingChallenges: [ATHLTHChallenge] {
        challenges.visibleChallenges.filter {
            $0.title.lowercased().contains(normalizedQuery) ||
            $0.sport.title.lowercased().contains(normalizedQuery)
        }
    }

    private func rememberSearch(_ raw: String) {
        let clean = raw.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard clean.count >= 2 else { return }

        var values = recentSearches.filter {
            $0.caseInsensitiveCompare(clean) != .orderedSame
        }
        values.insert(clean, at: 0)
        values = Array(values.prefix(6))

        guard let data = try? JSONEncoder().encode(values),
              let encoded = String(data: data, encoding: .utf8)
        else {
            return
        }

        recentSearchesRaw = encoded
    }

    @ViewBuilder
    private func resultSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .tracking(1.8)
                .foregroundStyle(ATHLTHTheme.mutedText)

            VStack(spacing: 0) {
                content()
            }
            .background(
                ATHLTHTheme.card.opacity(0.96),
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
                .stroke(Color.primary.opacity(0.055), lineWidth: 1)
            }
            .shadow(
                color: Color.black.opacity(0.035),
                radius: 12,
                y: 5
            )
        }
    }

    private func searchRow(
        icon: String,
        tint: Color,
        title: String,
        subtitle: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 42, height: 42)
                .background(
                    tint.opacity(0.09),
                    in: RoundedRectangle(cornerRadius: 13)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.primaryText)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption2.bold())
                .foregroundStyle(.tertiary)
        }
        .padding(12)
    }

    private func discoveryRow(
        icon: String,
        tint: Color,
        title: String,
        subtitle: String
    ) -> some View {
        searchRow(
            icon: icon,
            tint: tint,
            title: title,
            subtitle: subtitle
        )
        .background(
            ATHLTHTheme.card.opacity(0.96),
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
            .stroke(Color.primary.opacity(0.055), lineWidth: 1)
        }
        .shadow(
            color: Color.black.opacity(0.03),
            radius: 10,
            y: 4
        )
    }

    private func routeSubtitle(
        _ route: CommunityRouteRecord
    ) -> String {
        var parts = [
            String(format: "%.1f km", route.distanceKilometers)
        ]

        if let start = route.startName, !start.isEmpty {
            parts.append(start)
        }

        return parts.joined(separator: " · ")
    }
}

struct ATHLTHGlobalRouteDetailView: View {
    let route: CommunityRouteRecord

    private var region: MKCoordinateRegion {
        let coordinates = route.coordinates.map(\.coordinate)

        guard !coordinates.isEmpty else {
            return MKCoordinateRegion(
                center: route.centerCoordinate,
                span: MKCoordinateSpan(
                    latitudeDelta: 0.05,
                    longitudeDelta: 0.05
                )
            )
        }

        let minLat = coordinates.map(\.latitude).min() ?? route.centerLatitude
        let maxLat = coordinates.map(\.latitude).max() ?? route.centerLatitude
        let minLon = coordinates.map(\.longitude).min() ?? route.centerLongitude
        let maxLon = coordinates.map(\.longitude).max() ?? route.centerLongitude

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2,
                longitude: (minLon + maxLon) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: max((maxLat - minLat) * 1.35, 0.015),
                longitudeDelta: max((maxLon - minLon) * 1.35, 0.015)
            )
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Map(initialPosition: .region(region)) {
                    if !route.coordinates.isEmpty {
                        MapPolyline(
                            coordinates: route.coordinates.map(\.coordinate)
                        )
                        .stroke(
                            ATHLTHTheme.vitality,
                            style: StrokeStyle(
                                lineWidth: 5,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                    }
                }
                .frame(height: 280)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 24,
                        style: .continuous
                    )
                )

                ATHLTHCard {
                    Text(route.title)
                        .font(.title2.weight(.bold))

                    HStack(spacing: 18) {
                        routeMetric(
                            title: "Distance",
                            value: String(
                                format: "%.1f km",
                                route.distanceKilometers
                            )
                        )

                        if let elevation = route.elevationGainMeters {
                            routeMetric(
                                title: "Elevation",
                                value: "\(Int(elevation.rounded())) m"
                            )
                        }
                    }
                    .padding(.top, 8)

                    if let start = route.startName, !start.isEmpty {
                        Label(start, systemImage: "location.fill")
                            .font(.subheadline)
                            .foregroundStyle(ATHLTHTheme.mutedText)
                            .padding(.top, 10)
                    }
                }
            }
            .padding()
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(ATHLTHPremiumCanvas())
        .navigationTitle("Route")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func routeMetric(
        title: String,
        value: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline)
            Text(title)
                .font(.caption2)
                .foregroundStyle(ATHLTHTheme.mutedText)
        }
    }
}
