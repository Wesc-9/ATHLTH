import MapKit
import SwiftUI

struct ATHLTHGlobalSearchView: View {
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var routes: RouteDiscoveryStore
    @EnvironmentObject private var community: CommunityEventStore
    @EnvironmentObject private var challenges: ChallengeStore

    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var normalizedQuery: String {
        query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ATHLTHPremiumCanvas(
                    accent: ATHLTHTheme.vitality.opacity(0.45)
                )

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        if normalizedQuery.isEmpty {
                            searchLanding
                        } else {
                            searchResults
                        }
                    }
                    .padding()
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Search ATHLTH")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "People, routes, events, challenges"
            )
            .focused($searchFocused)
            .task {
                async let routeRefresh: Void = routes.refresh()
                async let eventRefresh: Void = community.refresh()
                _ = await (routeRefresh, eventRefresh)
                searchFocused = true
            }
            .task(id: normalizedQuery) {
                let term = normalizedQuery

                guard term.count >= 2 else {
                    if term.isEmpty {
                        social.clearSearch()
                    }
                    return
                }

                try? await Task.sleep(for: .milliseconds(260))
                guard !Task.isCancelled else { return }
                await social.search(term)
            }
        }
    }

    private var searchLanding: some View {
        VStack(alignment: .leading, spacing: 18) {
            ATHLTHCard {
                HStack(spacing: 14) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(ATHLTHTheme.vitality)
                        .frame(width: 48, height: 48)
                        .background(
                            ATHLTHTheme.vitalitySoft,
                            in: RoundedRectangle(
                                cornerRadius: 15,
                                style: .continuous
                            )
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Find anything in ATHLTH")
                            .font(.headline)
                        Text(
                            "Search athletes, public routes, upcoming events and your challenges."
                        )
                        .font(.caption)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()
                }
            }

            if !community.upcomingEvents.isEmpty ||
                !routes.routes.isEmpty ||
                !challenges.visibleChallenges.isEmpty {
                Text("DISCOVER")
                    .font(.caption.weight(.semibold))
                    .tracking(1.8)
                    .foregroundStyle(ATHLTHTheme.mutedText)

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
    }

    @ViewBuilder
    private var searchResults: some View {
        let people = peopleResults
        let routeResults = matchingRoutes
        let eventResults = matchingEvents
        let challengeResults = matchingChallenges

        if normalizedQuery.count < 2 {
            ContentUnavailableView(
                "Keep typing",
                systemImage: "text.magnifyingglass",
                description: Text("Type at least two characters to search ATHLTH.")
            )
            .padding(.vertical, 80)
        } else if people.isEmpty &&
                    routeResults.isEmpty &&
                    eventResults.isEmpty &&
                    challengeResults.isEmpty {
            ContentUnavailableView.search(text: query)
                .padding(.vertical, 80)
        } else {
            if !people.isEmpty {
                resultSection("PEOPLE") {
                    ForEach(people.prefix(8)) { profile in
                        NavigationLink {
                            FriendProfileView(userID: profile.userID)
                        } label: {
                            HStack(spacing: 12) {
                                SocialAvatar(profile: profile, size: 46)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(profile.resolvedName)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(ATHLTHTheme.primaryText)
                                    Text(profile.usernameLabel)
                                        .font(.caption)
                                        .foregroundStyle(ATHLTHTheme.mutedText)
                                }

                                Spacer()

                                Text(
                                    social.relationshipState(
                                        with: profile.userID
                                    ) == .friends
                                        ? "Friend"
                                        : "Profile"
                                )
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(ATHLTHTheme.accentDeep)

                                Image(systemName: "chevron.right")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(12)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !routeResults.isEmpty {
                resultSection("ROUTES") {
                    ForEach(routeResults.prefix(8)) { route in
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
                    }
                }
            }

            if !eventResults.isEmpty {
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
                    }
                }
            }

            if !challengeResults.isEmpty {
                resultSection("CHALLENGES") {
                    ForEach(challengeResults.prefix(8)) { challenge in
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
                    }
                }
            }
        }
    }

    private var peopleResults: [SocialProfileCard] {
        var seen = Set<UUID>()
        let combined = social.friends + social.discoverResults

        return combined.filter {
            guard seen.insert($0.userID).inserted else { return false }

            if normalizedQuery.isEmpty { return true }

            return $0.resolvedName.lowercased().contains(normalizedQuery) ||
                $0.usernameLabel.lowercased().contains(normalizedQuery)
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
                ATHLTHTheme.card,
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
                .stroke(Color.white.opacity(0.70), lineWidth: 1)
            }
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
            ATHLTHTheme.card,
            in: RoundedRectangle(cornerRadius: 18)
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
