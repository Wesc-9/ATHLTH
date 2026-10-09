import CoreLocation
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
            return ATHLTHLocalization.format(
                english: "All",
                norwegian: "Alle"
            )
        case .users:
            return ATHLTHLocalization.format(
                english: "People",
                norwegian: "Personer"
            )
        case .routes:
            return ATHLTHLocalization.format(
                english: "Routes",
                norwegian: "Ruter"
            )
        case .groups:
            return ATHLTHLocalization.format(
                english: "Clubs",
                norwegian: "Klubber"
            )
        case .events:
            return ATHLTHLocalization.format(
                english: "Events",
                norwegian: "Arrangementer"
            )
        case .challenges:
            return ATHLTHLocalization.format(
                english: "Challenges",
                norwegian: "Utfordringer"
            )
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

    @StateObject private var searchLocation = ChallengeLocationStore()

    @AppStorage("athlth.globalSearch.recent")
    private var recentSearchesRaw = "[]"

    @State private var query = ""
    @State private var scope: ATHLTHGlobalSearchScope = .all
    @State private var initialLoadFinished = false
    @State private var nearbyLocation: CLLocation?
    @State private var isSearchingRemote = false
    @FocusState private var searchFocused: Bool

    private var cleanQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var searchGraphite: Color {
        Color(
            red: 0.12,
            green: 0.14,
            blue: 0.18
        )
    }

    private var searchCoolAccent: Color {
        Color(
            red: 0.36,
            green: 0.64,
            blue: 0.82
        )
    }

    private var searchSocialAccent: Color {
        Color(
            red: 0.39,
            green: 0.35,
            blue: 0.74
        )
    }

    private var searchRouteAccent: Color {
        Color(
            red: 0.23,
            green: 0.67,
            blue: 0.49
        )
    }

    private var searchWarmAccent: Color {
        Color(
            red: 0.70,
            green: 0.53,
            blue: 0.25
        )
    }

    private var normalizedQuery: String {
        searchKey(cleanQuery)
    }

    private var remoteSearchTaskID: String {
        scope.rawValue + "|" + cleanQuery
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

    private var landingContentEmpty: Bool {
        social.visibleProfiles.isEmpty &&
            routes.routes.isEmpty &&
            community.upcomingEvents.isEmpty &&
            challenges.visibleChallenges.isEmpty &&
            groups.groups.isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color(red: 0.975, green: 0.971, blue: 0.961)
                    .ignoresSafeArea()

                // Hero stays within a fixed viewport: no aspect-fill layout overflow.
                GeometryReader { viewport in
                    Image("HomeHero")
                        .resizable()
                        .scaledToFill()
                        .frame(width: viewport.size.width, height: 390)
                        .clipped()
                        .overlay {
                            LinearGradient(
                                stops: [
                                    .init(color: .black.opacity(0.26), location: 0),
                                    .init(color: .black.opacity(0.02), location: 0.28),
                                    .init(color: Color(red: 0.975, green: 0.971, blue: 0.961).opacity(0.76), location: 0.72),
                                    .init(color: Color(red: 0.975, green: 0.971, blue: 0.961), location: 1)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        }
                        .frame(maxHeight: .infinity, alignment: .top)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        searchHeader
                        premiumSearchField
                        filterBar

                        if cleanQuery.isEmpty {
                            searchLanding
                        } else {
                            searchResults
                        }
                    }
                    .padding(.horizontal, 17)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
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

                switch searchLocation.authorizationStatus {
                case .authorizedAlways, .authorizedWhenInUse:
                    nearbyLocation =
                        await searchLocation.requestCurrentLocation()
                default:
                    break
                }

                initialLoadFinished = true
            }
            .task(id: remoteSearchTaskID) {
                await refreshRemoteSearch()
            }
            // Don't present the keyboard over the discovery dashboard by default.
            // The user opens it only by tapping the search field.
        }
    }

    private var searchHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("ATHLTH")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(3.0)
                    .foregroundStyle(.white.opacity(0.86))

                Text(
                    ATHLTHLocalization.format(
                        english: "Search",
                        norwegian: "Søk"
                    )
                )
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.22), radius: 6, y: 2)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 45, height: 45)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay {
                        Circle()
                            .stroke(.white.opacity(0.78), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                ATHLTHLocalization.format(
                    english: "Close search",
                    norwegian: "Lukk søk"
                )
            )
        }
        .frame(height: 112, alignment: .bottom)
        .padding(.bottom, 5)
    }

    private var premiumSearchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(searchGraphite)

            TextField(
                ATHLTHLocalization.format(
                    english: "Search people, routes, clubs and events",
                    norwegian: "Søk etter personer, ruter, klubber og arrangementer"
                ),
                text: $query
            )
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(ATHLTHTheme.primaryText)
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
                        .foregroundStyle(ATHLTHTheme.mutedText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    ATHLTHLocalization.format(
                        english: "Clear search",
                        norwegian: "Tøm søk"
                    )
                )
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 59)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.97),
                            .white.opacity(0.56),
                            searchCoolAccent.opacity(0.16)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: searchFocused ? 1.5 : 1
                )
        }
        .shadow(color: searchGraphite.opacity(0.09), radius: 16, y: 7)
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                ForEach(ATHLTHGlobalSearchScope.allCases) { item in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            scope = item
                            searchFocused = false
                        }
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: item.icon)
                                .font(.system(size: 12, weight: .semibold))
                            Text(item.localizedTitle)
                                .lineLimit(1)
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(
                            scope == item ? .white : searchGraphite
                        )
                        .padding(.horizontal, 14)
                        .frame(height: 39)
                        .background {
                            Capsule()
                                .fill(
                                    scope == item
                                        ? searchGraphite.opacity(0.96)
                                        : Color.white.opacity(0.46)
                                )
                        }
                        .overlay {
                            Capsule()
                                .stroke(.white.opacity(0.82), lineWidth: 0.85)
                        }
                        .shadow(color: .black.opacity(0.055), radius: 7, y: 3)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 3)
        }
        .contentMargins(.trailing, 5)
    }

    private var searchLanding: some View {
        VStack(alignment: .leading, spacing: 23) {
            if scope == .all {
                exploreShortcutGrid
                if !recentSearches.isEmpty {
                    recentSearchesSection
                }

                if !initialLoadFinished && landingContentEmpty {
                    landingSkeleton
                } else {
                    discoverSection
                    routeDiscoverySection
                }
            } else {
                categoryLanding
            }
        }
        .padding(.top, 9)
    }

    // 2×2 exploration tiles keep the discovery start screen useful even
    // before account and remote results have loaded.
    private var exploreShortcutGrid: some View {
        VStack(alignment: .leading, spacing: 11) {
            searchSectionTitle(
                ATHLTHLocalization.format(
                    english: "Explore",
                    norwegian: "Utforsk"
                )
            )

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 10
            ) {
                explorationTile(
                    .users,
                    subtitle: ATHLTHLocalization.format(
                        english: "Discover people",
                        norwegian: "Finn nye folk"
                    ),
                    artwork: "CommunityHero",
                    tint: searchSocialAccent
                )
                explorationTile(
                    .routes,
                    subtitle: ATHLTHLocalization.format(
                        english: "Discover routes",
                        norwegian: "Utforsk nye ruter"
                    ),
                    artwork: "GoalRunning",
                    tint: searchRouteAccent
                )
                explorationTile(
                    .groups,
                    subtitle: ATHLTHLocalization.format(
                        english: "Find your crew",
                        norwegian: "Finn din gjeng"
                    ),
                    artwork: "HomeHero",
                    tint: Color(red: 0.78, green: 0.41, blue: 0.27)
                )
                explorationTile(
                    .events,
                    subtitle: ATHLTHLocalization.format(
                        english: "What's happening",
                        norwegian: "Se hva som skjer"
                    ),
                    artwork: "GoalEvent",
                    tint: searchWarmAccent
                )
            }
        }
    }

    private func explorationTile(
        _ item: ATHLTHGlobalSearchScope,
        subtitle: String,
        artwork: String,
        tint: Color
    ) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                scope = item
                searchFocused = false
            }
        } label: {
            ZStack(alignment: .leading) {
                GeometryReader { viewport in
                    Image(artwork)
                        .resizable()
                        .scaledToFill()
                        .frame(
                            width: viewport.size.width,
                            height: viewport.size.height
                        )
                        .clipped()
                        .opacity(0.38)
                }
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.94),
                        Color.white.opacity(0.65),
                        tint.opacity(0.15)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                HStack(spacing: 10) {
                    Image(systemName: item.icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 40, height: 40)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.localizedTitle)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(searchGraphite)
                            .lineLimit(1)
                            .minimumScaleFactor(0.83)

                        Text(subtitle)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(searchGraphite.opacity(0.72))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 11)
            }
            .frame(height: 105)
            .clipShape(RoundedRectangle(cornerRadius: 21, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 21, style: .continuous)
                    .stroke(.white.opacity(0.92), lineWidth: 1)
            }
            .shadow(color: searchGraphite.opacity(0.07), radius: 13, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityHint(
            ATHLTHLocalization.format(
                english: "Show \(item.localizedTitle.lowercased())",
                norwegian: "Vis \(item.localizedTitle.lowercased())"
            )
        )
    }

    private var recentSearchesSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                searchSectionTitle(
                    ATHLTHLocalization.format(
                        english: "Recently searched",
                        norwegian: "Nylig søkt"
                    )
                )

                Spacer()

                Button(
                    ATHLTHLocalization.format(
                        english: "Clear",
                        norwegian: "Tøm"
                    )
                ) {
                    recentSearchesRaw = "[]"
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(ATHLTHTheme.accentDeep)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(recentSearches.prefix(6), id: \.self) { value in
                        recentSearchChip(value)
                    }
                }
            }
        }
    }

    private func recentSearchChip(_ value: String) -> some View {
        HStack(spacing: 4) {
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
            }
            .buttonStyle(.plain)

            Button {
                removeRecentSearch(value)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(ATHLTHTheme.mutedText)
                    .frame(width: 22, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                ATHLTHLocalization.format(
                    english: "Remove recent search",
                    norwegian: "Fjern nylig søk"
                )
            )
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .frame(height: 39)
        .background(
            Color.white
                .opacity(0.69),
            in: Capsule()
        )
        .overlay {
            Capsule()
                .stroke(
                    Color.white
                        .opacity(0.80),
                    lineWidth: 0.8
                )
        }
        .shadow(
            color:
                Color.black
                    .opacity(0.018),
            radius: 9,
            y: 3
        )
    }

    @ViewBuilder
    private var discoverSection: some View {
        let hasDiscovery =
            !groups.groups.isEmpty ||
            !community.upcomingEvents.isEmpty ||
            !challenges.visibleChallenges.isEmpty

        if hasDiscovery {
            VStack(alignment: .leading, spacing: 11) {
                searchSectionTitle(
                    ATHLTHLocalization.format(
                        english: "For you",
                        norwegian: "For deg"
                    )
                )

                if let group = groups.groups.first {
                    NavigationLink {
                        CommunityGroupDetailView(group: group)
                    } label: {
                        discoveryRow(
                            icon: "person.3.fill",
                            tint: searchSocialAccent,
                            title: group.name,
                            subtitle: groupSubtitle(group),
                            artwork: "CommunityHero"
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
                            tint: searchWarmAccent,
                            title: event.event.title,
                            subtitle:
                                ATHLTHLocalization.format(
                                    english: "Upcoming event",
                                    norwegian: "Kommende arrangement"
                                ) + " · " +
                                event.event.startsAt.formatted(
                                    date: .abbreviated,
                                    time: .shortened
                                ),
                            artwork: "GoalEvent"
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
                            tint: searchCoolAccent,
                            title: challenge.title,
                            subtitle:
                                ATHLTHLocalization.format(
                                    english: "Challenge",
                                    norwegian: "Utfordring"
                                ) + " · " + challenge.sport.title,
                            artwork: "GoalRunning"
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var routeDiscoverySection: some View {
        let nearby = nearbyLocation.map {
            routes.nearbyRoutes(from: $0, radiusKilometers: 35)
        } ?? []

        let useNearby = !nearby.isEmpty
        let visibleRoutes = useNearby
            ? Array(nearby.prefix(2))
            : Array(routes.routes.prefix(2))

        if !visibleRoutes.isEmpty {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    searchSectionTitle(
                        useNearby
                            ? ATHLTHLocalization.format(
                                english: "Routes nearby",
                                norwegian: "Ruter i nærheten"
                            )
                            : ATHLTHLocalization.format(
                                english: "Routes to explore",
                                norwegian: "Ruter å utforske"
                            )
                    )

                    Spacer()

                    if routes.routes.count > 2 {
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                scope = .routes
                            }
                        } label: {
                            Label(
                                ATHLTHLocalization.format(
                                    english: "See all",
                                    norwegian: "Se alle"
                                ),
                                systemImage: "chevron.right"
                            )
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(searchGraphite.opacity(0.72))
                        }
                        .buttonStyle(.plain)
                    }
                }

                ForEach(visibleRoutes) { route in
                    NavigationLink {
                        ATHLTHGlobalRouteDetailView(route: route)
                    } label: {
                        featuredRouteRow(
                            route,
                            subtitle: routeDiscoverySubtitle(
                                route,
                                location: useNearby ? nearbyLocation : nil
                            )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func featuredRouteRow(
        _ route: CommunityRouteRecord,
        subtitle: String
    ) -> some View {
        HStack(spacing: 12) {
            RouteMapSnapshotThumbnail(
                route: route.trainingRoute,
                height: 92
            )
            .frame(width: 104, height: 92)
            .clipShape(RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 6) {
                Text(route.title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(searchGraphite)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(ATHLTHTheme.mutedText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(searchGraphite.opacity(0.75))
                .frame(width: 29, height: 29)
                .background(Color.white.opacity(0.54), in: Circle())
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 21))
        .overlay {
            RoundedRectangle(cornerRadius: 21)
                .stroke(.white.opacity(0.86), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.055), radius: 13, y: 6)
    }

    @ViewBuilder
    private var categoryLanding: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch scope {
            case .all:
                EmptyView()

            case .users:
                let profiles = Array(
                    social.visibleProfiles
                        .filter { $0.userID != social.currentUserID }
                        .prefix(6)
                )

                if profiles.isEmpty {
                    categoryHint
                } else {
                    resultSection(
                        scope.localizedTitle,
                        count: social.visibleProfiles.count,
                        previewLimit: 6
                    ) {
                        ForEach(profiles) { profile in
                            NavigationLink {
                                FriendProfileView(userID: profile.userID)
                            } label: {
                                userRow(profile)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

            case .routes:
                let items = Array(routes.routes.prefix(6))

                if items.isEmpty {
                    categoryHint
                } else {
                    resultSection(
                        scope.localizedTitle,
                        count: routes.routes.count,
                        previewLimit: 6
                    ) {
                        ForEach(items) { route in
                            NavigationLink {
                                ATHLTHGlobalRouteDetailView(route: route)
                            } label: {
                                searchRow(
                                    icon: "map.fill",
                                    tint: .green,
                                    title: route.title,
                                    subtitle: routeDiscoverySubtitle(
                                        route,
                                        location: nearbyLocation
                                    )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

            case .groups:
                let items = Array(groups.groups.prefix(6))

                if items.isEmpty {
                    categoryHint
                } else {
                    resultSection(
                        scope.localizedTitle,
                        count: groups.groups.count,
                        previewLimit: 6
                    ) {
                        ForEach(items) { group in
                            NavigationLink {
                                CommunityGroupDetailView(group: group)
                            } label: {
                                searchRow(
                                    icon: "person.3.fill",
                                    tint: .indigo,
                                    title: group.name,
                                    subtitle: groupSubtitle(group)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

            case .events:
                let items = Array(community.upcomingEvents.prefix(6))

                if items.isEmpty {
                    categoryHint
                } else {
                    resultSection(
                        scope.localizedTitle,
                        count: community.upcomingEvents.count,
                        previewLimit: 6
                    ) {
                        ForEach(items) { event in
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

            case .challenges:
                let items = Array(challenges.visibleChallenges.prefix(6))

                if items.isEmpty {
                    categoryHint
                } else {
                    resultSection(
                        scope.localizedTitle,
                        count: challenges.visibleChallenges.count,
                        previewLimit: 6
                    ) {
                        ForEach(items) { challenge in
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
    }

    private var categoryHint: some View {
        ATHLTHCard {
            HStack(spacing: 14) {
                Image(systemName: scope.icon)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                    .frame(width: 44, height: 44)
                    .background(
                        ATHLTHTheme.accentSoft,
                        in: RoundedRectangle(
                            cornerRadius: 13,
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

                    Text(
                        ATHLTHLocalization.format(
                            english: "Start typing to narrow ATHLTH to this category.",
                            norwegian: "Begynn å skrive for å søke i denne kategorien."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                }

                Spacer()
            }
        }
    }

    private var landingSkeleton: some View {
        VStack(alignment: .leading, spacing: 9) {
            searchSectionTitle(
                ATHLTHLocalization.format(
                    english: "Loading",
                    norwegian: "Laster"
                )
            )

            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 13)
                        .frame(width: 42, height: 42)

                    VStack(alignment: .leading, spacing: 7) {
                        RoundedRectangle(cornerRadius: 4)
                            .frame(width: 150, height: 12)
                        RoundedRectangle(cornerRadius: 4)
                            .frame(width: 210, height: 9)
                    }

                    Spacer()
                }
                .padding(12)
                .background(
                    ATHLTHTheme.card.opacity(0.94),
                    in: RoundedRectangle(
                        cornerRadius: 18,
                        style: .continuous
                    )
                )
                .redacted(reason: .placeholder)
            }
        }
        .allowsHitTesting(false)
    }

    private func searchSectionTitle(
        _ title: String
    ) -> some View {
        Text(
            title.uppercased()
        )
        .font(
            .system(
                size: 10.5,
                weight: .bold
            )
        )
        .tracking(1.9)
        .foregroundStyle(
            ATHLTHTheme
                .mutedText
        )
    }

    private var searchEmptyState: some View {
        ATHLTHCard {
            VStack(spacing: 13) {
                Image(systemName: "magnifyingglass.circle.fill")
                    .font(.system(size: 42, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(ATHLTHTheme.accentDeep)

                Text(
                    ATHLTHLocalization.format(
                        english: "Nothing found",
                        norwegian: "Ingen treff"
                    )
                )
                .font(.title3.weight(.bold))

                Text(
                    ATHLTHLocalization.format(
                        english: "Try another name, place or training term — or switch category above.",
                        norwegian: "Prøv et annet navn, sted eller treningsord – eller bytt kategori over."
                    )
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
                ATHLTHLocalization.format(
                    english: "Keep typing",
                    norwegian: "Skriv litt mer"
                ),
                systemImage: "text.magnifyingglass",
                description: Text(
                    ATHLTHLocalization.format(
                        english: "Type at least two characters to search ATHLTH.",
                        norwegian: "Skriv minst to tegn for å søke i ATHLTH."
                    )
                )
            )
            .padding(.vertical, 70)
        } else if visibleResultCount == 0 && isSearchingRemote {
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.regular)

                Text(
                    ATHLTHLocalization.format(
                        english: "Searching ATHLTH…",
                        norwegian: "Søker i ATHLTH…"
                    )
                )
                .font(.caption)
                .foregroundStyle(ATHLTHTheme.mutedText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 64)
        } else if visibleResultCount == 0 {
            searchEmptyState
                .padding(.top, 14)
        } else {
            if (scope == .all || scope == .users) && !users.isEmpty {
                resultSection(
                    ATHLTHGlobalSearchScope.users.localizedTitle,
                    count: users.count,
                    showAllScope: .users,
                    previewLimit: 12
                ) {
                    ForEach(users.prefix(12)) { profile in
                        NavigationLink {
                            FriendProfileView(userID: profile.userID)
                        } label: {
                            userRow(profile)
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
                resultSection(
                    ATHLTHGlobalSearchScope.groups.localizedTitle,
                    count: groupResults.count,
                    showAllScope: .groups,
                    previewLimit: 8
                ) {
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
                                        ? " · " +
                                            ATHLTHLocalization.format(
                                                english: "Joined",
                                                norwegian: "Medlem"
                                            )
                                        : " · " +
                                            ATHLTHLocalization.format(
                                                english: "Club",
                                                norwegian: "Klubb"
                                            ))
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
                resultSection(
                    ATHLTHGlobalSearchScope.events.localizedTitle,
                    count: eventResults.count,
                    showAllScope: .events,
                    previewLimit: 8
                ) {
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
                resultSection(
                    ATHLTHGlobalSearchScope.routes.localizedTitle,
                    count: routeResults.count,
                    showAllScope: .routes,
                    previewLimit: 6
                ) {
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
                resultSection(
                    ATHLTHGlobalSearchScope.challenges.localizedTitle,
                    count: challengeResults.count,
                    showAllScope: .challenges,
                    previewLimit: 6
                ) {
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

                return searchScore([
                    profile.resolvedName,
                    profile.usernameLabel
                ]) < Int.max
            }
            .sorted { lhs, rhs in
                let lhsScore = searchScore([
                    lhs.resolvedName,
                    lhs.usernameLabel
                ])
                let rhsScore = searchScore([
                    rhs.resolvedName,
                    rhs.usernameLabel
                ])

                if lhsScore != rhsScore {
                    return lhsScore < rhsScore
                }

                return lhs.resolvedName.localizedCaseInsensitiveCompare(
                    rhs.resolvedName
                ) == .orderedAscending
            }
    }

    private func userRelationshipLabel(
        _ profile: SocialProfileCard
    ) -> String {
        if social.isFollowing(profile.userID) {
            return ATHLTHLocalization.format(
                english: "Following",
                norwegian: "Følger"
            )
        }

        if profile.isPrivateProfile {
            return ATHLTHLocalization.format(
                english: "Private",
                norwegian: "Privat"
            )
        }

        return ATHLTHLocalization.format(
            english: "User",
            norwegian: "Bruker"
        )
    }

    private var matchingGroups: [CommunityGroupRecord] {
        var seen = Set<UUID>()

        return (groups.groups + groups.searchResults)
            .filter {
                guard seen.insert($0.id).inserted else {
                    return false
                }

                return searchScore([
                    $0.name,
                    $0.locationName,
                    $0.summary
                ]) < Int.max
            }
            .sorted { lhs, rhs in
                let lhsScore = searchScore([
                    lhs.name,
                    lhs.locationName,
                    lhs.summary
                ])
                let rhsScore = searchScore([
                    rhs.name,
                    rhs.locationName,
                    rhs.summary
                ])

                if lhsScore != rhsScore {
                    return lhsScore < rhsScore
                }

                return lhs.name.localizedCaseInsensitiveCompare(
                    rhs.name
                ) == .orderedAscending
            }
    }

    private var matchingRoutes: [CommunityRouteRecord] {
        var seen = Set<UUID>()

        return (routes.routes + routes.searchResults)
            .filter {
                guard seen.insert($0.id).inserted else {
                    return false
                }

                return searchScore([
                    $0.title,
                    $0.startName ?? "",
                    $0.endName ?? ""
                ]) < Int.max
            }
            .sorted { lhs, rhs in
                let lhsScore = searchScore([
                    lhs.title,
                    lhs.startName ?? "",
                    lhs.endName ?? ""
                ])
                let rhsScore = searchScore([
                    rhs.title,
                    rhs.startName ?? "",
                    rhs.endName ?? ""
                ])

                if lhsScore != rhsScore {
                    return lhsScore < rhsScore
                }

                if let nearbyLocation {
                    let lhsDistance = CLLocation(
                        latitude: lhs.centerLatitude,
                        longitude: lhs.centerLongitude
                    )
                    .distance(from: nearbyLocation)

                    let rhsDistance = CLLocation(
                        latitude: rhs.centerLatitude,
                        longitude: rhs.centerLongitude
                    )
                    .distance(from: nearbyLocation)

                    if abs(lhsDistance - rhsDistance) > 1 {
                        return lhsDistance < rhsDistance
                    }
                }

                return lhs.title.localizedCaseInsensitiveCompare(
                    rhs.title
                ) == .orderedAscending
            }
    }

    private var matchingEvents: [CommunityEventItem] {
        var seen = Set<UUID>()

        return (community.upcomingEvents + community.searchResults)
            .filter {
                guard seen.insert($0.id).inserted else {
                    return false
                }

                return searchScore([
                    $0.event.title,
                    $0.event.summary,
                    $0.event.meetingName,
                    $0.event.meetingDetails ?? "",
                    $0.event.routeTitle ?? "",
                    $0.event.activityType.title
                ]) < Int.max
            }
            .sorted { lhs, rhs in
                let lhsScore = searchScore([
                    lhs.event.title,
                    lhs.event.summary,
                    lhs.event.meetingName,
                    lhs.event.meetingDetails ?? "",
                    lhs.event.routeTitle ?? "",
                    lhs.event.activityType.title
                ])
                let rhsScore = searchScore([
                    rhs.event.title,
                    rhs.event.summary,
                    rhs.event.meetingName,
                    rhs.event.meetingDetails ?? "",
                    rhs.event.routeTitle ?? "",
                    rhs.event.activityType.title
                ])

                if lhsScore != rhsScore {
                    return lhsScore < rhsScore
                }

                return lhs.event.startsAt < rhs.event.startsAt
            }
    }

    private var matchingChallenges: [ATHLTHChallenge] {
        var seen = Set<UUID>()

        return (
            challenges.visibleChallenges +
            social.challengeSearchResults
        )
        .filter {
            guard seen.insert($0.id).inserted else {
                return false
            }

            return searchScore([
                $0.title,
                $0.sport.title
            ]) < Int.max
        }
        .sorted { lhs, rhs in
            let lhsScore = searchScore([
                lhs.title,
                lhs.sport.title
            ])
            let rhsScore = searchScore([
                rhs.title,
                rhs.sport.title
            ])

            if lhsScore != rhsScore {
                return lhsScore < rhsScore
            }

            return lhs.title.localizedCaseInsensitiveCompare(
                rhs.title
            ) == .orderedAscending
        }
    }

    private func searchKey(_ value: String) -> String {
        value
            .folding(
                options: [
                    .caseInsensitive,
                    .diacriticInsensitive,
                    .widthInsensitive
                ],
                locale: .current
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(
                of: #"\s+"#,
                with: " ",
                options: .regularExpression
            )
    }

    private func searchScore(_ values: [String]) -> Int {
        let needle = normalizedQuery
        guard needle.count >= 2 else { return Int.max }

        var best = Int.max

        for value in values {
            let candidate = searchKey(value)
            guard !candidate.isEmpty else { continue }

            if candidate == needle {
                best = min(best, 0)
                continue
            }

            if candidate.hasPrefix(needle) {
                best = min(best, 1)
                continue
            }

            if candidate
                .split(separator: " ")
                .contains(where: {
                    $0.hasPrefix(Substring(needle))
                }) {
                best = min(best, 2)
                continue
            }

            if candidate.contains(needle) {
                best = min(best, 3)
            }
        }

        return best
    }

    @MainActor
    private func refreshRemoteSearch() async {
        let requestedQuery = cleanQuery
        let requestedScope = scope

        guard requestedQuery.count >= 2 else {
            isSearchingRemote = false
            clearRemoteSearchResults()
            return
        }

        do {
            try await Task.sleep(
                nanoseconds: 300_000_000
            )
        } catch {
            return
        }

        guard !Task.isCancelled else { return }

        isSearchingRemote = true

        switch requestedScope {
        case .all:
            async let peopleSearch: Void =
                social.search(requestedQuery)
            async let routeSearch: Void =
                routes.search(requestedQuery)
            async let groupSearch: Void =
                groups.search(requestedQuery)
            async let eventSearch: Void =
                community.search(requestedQuery)
            async let challengeSearch: Void =
                social.searchChallenges(requestedQuery)

            _ = await (
                peopleSearch,
                routeSearch,
                groupSearch,
                eventSearch,
                challengeSearch
            )

            challenges.mergeRemoteChallenges(
                social.challengeSearchResults
            )

        case .users:
            await social.search(requestedQuery)

        case .routes:
            await routes.search(requestedQuery)

        case .groups:
            await groups.search(requestedQuery)

        case .events:
            await community.search(requestedQuery)

        case .challenges:
            await social.searchChallenges(requestedQuery)
            challenges.mergeRemoteChallenges(
                social.challengeSearchResults
            )
        }

        guard !Task.isCancelled else { return }

        if cleanQuery.caseInsensitiveCompare(
            requestedQuery
        ) == .orderedSame,
           scope == requestedScope {
            isSearchingRemote = false
        }
    }

    private func clearRemoteSearchResults() {
        social.clearSearch()
        social.clearChallengeSearch()
        routes.clearSearch()
        groups.clearSearch()
        community.clearSearch()
        isSearchingRemote = false
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

        persistRecentSearches(values)
    }

    private func removeRecentSearch(_ value: String) {
        let values = recentSearches.filter {
            $0.caseInsensitiveCompare(value) != .orderedSame
        }

        persistRecentSearches(values)
    }

    private func persistRecentSearches(_ values: [String]) {
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
        count: Int,
        showAllScope: ATHLTHGlobalSearchScope? = nil,
        previewLimit: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                searchSectionTitle("\(title) · \(count)")

                Spacer()

                if scope == .all,
                   let showAllScope,
                   count > previewLimit {
                    Button {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            scope = showAllScope
                        }
                    } label: {
                        Text(
                            ATHLTHLocalization.format(
                                english: "See all \(count)",
                                norwegian: "Se alle \(count)"
                            )
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(spacing: 0) {
                content()
            }
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
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
            }
            .shadow(
                color: Color.black.opacity(0.025),
                radius: 9,
                y: 4
            )
        }
    }

    private func userRow(
        _ profile: SocialProfileCard
    ) -> some View {
        HStack(spacing: 12) {
            SocialAvatar(profile: profile, size: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(profile.resolvedName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.primaryText)

                Text(profile.usernameLabel)
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
            }

            Spacer()

            Text(userRelationshipLabel(profile))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(ATHLTHTheme.accentDeep)

            Image(systemName: "chevron.right")
                .font(.caption2.bold())
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 62)
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
                .frame(width: 40, height: 40)
                .background(
                    tint.opacity(0.09),
                    in: RoundedRectangle(cornerRadius: 12)
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
        .padding(.horizontal, 12)
        .frame(minHeight: 62)
    }

    private func discoveryRow(
        icon: String,
        tint: Color,
        title: String,
        subtitle: String,
        artwork: String
    ) -> some View {
        ZStack(alignment: .leading) {
            GeometryReader { viewport in
                Image(artwork)
                    .resizable()
                    .scaledToFill()
                    .frame(width: viewport.size.width, height: viewport.size.height)
                    .clipped()
                    .opacity(0.49)
            }

            LinearGradient(
                colors: [
                    Color.white.opacity(0.97),
                    Color.white.opacity(0.88),
                    Color.white.opacity(0.15)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )

            HStack(spacing: 13) {
                Image(systemName: icon)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 51, height: 51)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(searchGraphite)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(searchGraphite.opacity(0.71))
                        .lineLimit(1)
                }

                Spacer(minLength: 2)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(searchGraphite)
                    .frame(width: 30, height: 30)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding(.horizontal, 15)
        }
        .frame(height: 91)
        .clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 23, style: .continuous)
                .stroke(.white.opacity(0.90), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.065), radius: 15, y: 6)
    }

    private func groupSubtitle(
        _ group: CommunityGroupRecord
    ) -> String {
        let clubLabel = ATHLTHLocalization.format(
            english: "Club",
            norwegian: "Klubb"
        )

        guard !group.locationName.isEmpty else {
            return clubLabel
        }

        return group.locationName + " · " + clubLabel
    }

    private func routeSubtitle(
        _ route: CommunityRouteRecord
    ) -> String {
        var parts = [
            String(format: "%.1f km", route.distanceKilometers)
        ]

        if let elevation = route.elevationGainMeters {
            parts.append("\(Int(elevation.rounded())) m ↑")
        }

        if let start = route.startName, !start.isEmpty {
            parts.append(start)
        }

        return parts.joined(separator: " · ")
    }

    private func routeDiscoverySubtitle(
        _ route: CommunityRouteRecord,
        location: CLLocation?
    ) -> String {
        var parts = [
            String(format: "%.1f km", route.distanceKilometers)
        ]

        if let elevation = route.elevationGainMeters {
            parts.append("\(Int(elevation.rounded())) m ↑")
        }

        if let location {
            let routeLocation = CLLocation(
                latitude: route.centerLatitude,
                longitude: route.centerLongitude
            )
            let distanceMeters = routeLocation.distance(from: location)

            if distanceMeters < 1_000 {
                parts.append(
                    ATHLTHLocalization.format(
                        english: "\(Int(distanceMeters.rounded())) m away",
                        norwegian: "\(Int(distanceMeters.rounded())) m unna"
                    )
                )
            } else {
                let kilometers = distanceMeters / 1_000
                parts.append(
                    ATHLTHLocalization.format(
                        english: String(format: "%.1f km away", kilometers),
                        norwegian: String(format: "%.1f km unna", kilometers)
                    )
                )
            }
        } else if let start = route.startName, !start.isEmpty {
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
