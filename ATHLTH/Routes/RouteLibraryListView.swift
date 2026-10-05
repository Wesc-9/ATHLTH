import CoreLocation
import SwiftUI
import Supabase

enum RouteLibrarySource {
    case database, mine
}

private enum RouteLibrarySort: String, CaseIterable, Identifiable {
    case newest = "Newest"
    case nearest = "Nearest"
    case shortest = "Shortest"
    case longest = "Longest"
    case leastClimbing = "Least climbing"
    case mostClimbing = "Most climbing"
    case name = "Name A–Z"
    var id: String { rawValue }
}

private struct RouteLibraryEntry: Decodable, Identifiable {
    let id: UUID
    let title: String
    let distanceKilometers: Double
    let elevationGainMeters: Double?
    let startName: String?
    let endName: String?
    let centerLatitude: Double?
    let centerLongitude: Double?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title
        case distanceKilometers = "distance_kilometers"
        case elevationGainMeters = "elevation_gain_meters"
        case startName = "start_name"
        case endName = "end_name"
        case centerLatitude = "center_latitude"
        case centerLongitude = "center_longitude"
        case createdAt = "created_at"
    }

    init(route: TrainingRoute) {
        id = route.id
        title = route.title
        distanceKilometers = route.distanceKilometers
        elevationGainMeters = route.elevationGainMeters
        startName = route.startName
        endName = route.endName
        centerLatitude = route.discoveryCenterCoordinate?.latitude
        centerLongitude = route.discoveryCenterCoordinate?.longitude
        createdAt = route.createdAt
    }

    func distance(from location: CLLocation?) -> Double? {
        guard let location, let centerLatitude, let centerLongitude else { return nil }
        return location.distance(from: CLLocation(latitude: centerLatitude, longitude: centerLongitude)) / 1000
    }
}

struct RouteLibraryListView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var favorites: LibraryFavoritesStore
    @EnvironmentObject private var recents: LibraryRecentsStore
    @StateObject private var locationStore = HomeLocationStore()
    let source: RouteLibrarySource

    @State private var catalog: [RouteLibraryEntry] = []
    @State private var query = ""
    @State private var sort: RouteLibrarySort = .newest
    @State private var lengthFilter = 0
    @State private var favoritesOnly = false
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var hasMore = false
    @State private var catalogRequestID = UUID()

    private var catalogKey: String {
        [query, sort.rawValue, String(lengthFilter),
         String(locationStore.location?.coordinate.latitude ?? 0),
         String(locationStore.location?.coordinate.longitude ?? 0)].joined(separator: "|")
    }

    private var entries: [RouteLibraryEntry] {
        if source == .database {
            return favoritesOnly
                ? catalog.filter {
                    favorites.isFavorite(
                        .route,
                        itemID: $0.id.uuidString
                    )
                }
                : catalog
        }

        let values = session.savedRoutes.map(RouteLibraryEntry.init(route:))
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return values.filter { entry in
            let matchesSearch = search.isEmpty ||
                [entry.title, entry.startName ?? "", entry.endName ?? ""]
                    .contains { $0.localizedCaseInsensitiveContains(search) }
            let length = entry.distanceKilometers
            let matchesLength: Bool
            switch lengthFilter {
            case 1: matchesLength = length < 5
            case 2: matchesLength = length >= 5 && length < 10
            case 3: matchesLength = length >= 10 && length < 21.1
            case 4: matchesLength = length >= 21.1
            default: matchesLength = true
            }
            let favoriteMatches =
                !favoritesOnly ||
                favorites.isFavorite(
                    .route,
                    itemID: entry.id.uuidString
                )
            return matchesSearch &&
                matchesLength &&
                favoriteMatches
        }.sorted { left, right in
            func ascending(_ a: Double?, _ b: Double?, descending: Bool = false) -> Bool {
                switch (a, b) {
                case let (a?, b?) where a != b: return descending ? a > b : a < b
                case (_?, nil): return true
                case (nil, _?): return false
                default: return left.id.uuidString < right.id.uuidString
                }
            }
            switch sort {
            case .newest:
                if left.createdAt != right.createdAt { return left.createdAt > right.createdAt }
            case .nearest:
                if locationStore.location != nil {
                    return ascending(left.distance(from: locationStore.location), right.distance(from: locationStore.location))
                }
            case .shortest: return ascending(left.distanceKilometers, right.distanceKilometers)
            case .longest: return ascending(left.distanceKilometers, right.distanceKilometers, descending: true)
            case .leastClimbing: return ascending(left.elevationGainMeters, right.elevationGainMeters)
            case .mostClimbing: return ascending(left.elevationGainMeters, right.elevationGainMeters, descending: true)
            case .name: break
            }
            let comparison = left.title.localizedStandardCompare(right.title)
            return comparison == .orderedSame
                ? left.id.uuidString < right.id.uuidString
                : comparison == .orderedAscending
        }
    }

    var body: some View {
        List {
            if source == .mine {
                mineFilterCard
                    .listRowInsets(
                        EdgeInsets(
                            top: 8,
                            leading: 16,
                            bottom: 8,
                            trailing: 16
                        )
                    )
                    .listRowBackground(
                        Color.clear
                    )
                    .listRowSeparator(
                        .hidden
                    )
            } else {
                Section {
                    Picker("Sort by", selection: $sort) {
                        ForEach(RouteLibrarySort.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    Picker("Route length", selection: $lengthFilter) {
                        Text("Any length").tag(0)
                        Text("Under 5 km").tag(1)
                        Text("5–10 km").tag(2)
                        Text("10–21.1 km").tag(3)
                        Text("21.1 km and more").tag(4)
                    }

                    Toggle(isOn: $favoritesOnly) {
                        Label(
                            "Favorites only",
                            systemImage: "star.fill"
                        )
                    }
                    .tint(ATHLTHTheme.accent)

                    if sort == .nearest {
                        if locationStore.isUpdating {
                            ProgressView("Finding your location…")
                        } else if locationStore.location == nil {
                            Text("Location is unavailable. Routes are shown by name until your position is available.")
                                .font(.caption).foregroundStyle(.secondary)
                            Button("Use my location") { locationStore.refresh() }
                        }
                        Text("Nearest is the straight-line distance to the route's centre, not travel distance to its start.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).font(.caption).foregroundStyle(.red)
                    if source == .database {
                        Button("Retry") { Task { await loadCatalog() } }
                    }
                }
            }
            if loading {
                ProgressView("Loading routes…")
            }
            Section(
                hasMore
                    ? ATHLTHLocalization.format(
                        "%d routes loaded",
                        entries.count
                    )
                    : ATHLTHLocalization.format(
                        "%d routes",
                        entries.count
                    )
            ) {
                ForEach(entries) { entry in
                    routeRow(entry)
                }
                if source == .database && hasMore {
                    Button("Load more routes") { Task { await loadCatalog(reset: false) } }
                        .disabled(loading)
                }
                if entries.isEmpty && !loading && errorMessage == nil {
                    ContentUnavailableView(
                        "No routes found", systemImage: "map",
                        description: Text(
                            source == .mine
                                ? ATHLTHLocalization.string(
                                    "Create or save a route, or try another search or filter."
                                )
                                : ATHLTHLocalization.string(
                                    "Try another search or filter. Public routes appear here when shared."
                                )
                        )
                    )
                }
            }
        }
        .modifier(
            RouteLibraryGhostSurfaceModifier(
                enabled:
                    source == .mine
            )
        )
        .navigationTitle(
            source == .mine
                ? ATHLTHLocalization.string(
                    "My Routes"
                )
                : ATHLTHLocalization.string(
                    "Route Database"
                )
        )
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search route or place")
        .toolbar {
            if source == .mine {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        RunRouteBuilderView()
                    } label: {
                        Label("Create route", systemImage: "plus")
                    }
                }
            }
        }
        .task(id: catalogKey) {
            recents.refresh()
            async let favoriteRefresh: Void = favorites.refresh()
            if source == .database {
                await loadCatalog()
            }
            _ = await favoriteRefresh
        }
        .refreshable { if source == .database { await loadCatalog() } }
        .onChange(of: sort) { _, value in
            if value == .nearest { locationStore.refresh() }
        }
        .onDisappear { locationStore.stop() }
    }

    private var mineFilterCard: some View {
        ATHLTHCard {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text(
                        ATHLTHLocalization.string(
                            "Sort by"
                        )
                    )
                    .font(.body)

                    Spacer()

                    Picker(
                        "Sort by",
                        selection: $sort
                    ) {
                        ForEach(
                            RouteLibrarySort
                                .allCases
                        ) { option in
                            Text(
                                option.rawValue
                            )
                            .tag(option)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .tint(
                        ATHLTHTheme
                            .accentDeep
                    )
                }
                .padding(.vertical, 2)

                Divider()
                    .padding(.vertical, 12)

                HStack(spacing: 12) {
                    Text(
                        ATHLTHLocalization.string(
                            "Route length"
                        )
                    )

                    Spacer()

                    Picker(
                        "Route length",
                        selection:
                            $lengthFilter
                    ) {
                        Text("Any length")
                            .tag(0)
                        Text("Under 5 km")
                            .tag(1)
                        Text("5–10 km")
                            .tag(2)
                        Text("10–21.1 km")
                            .tag(3)
                        Text("21.1 km and more")
                            .tag(4)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .tint(
                        ATHLTHTheme
                            .accentDeep
                    )
                }

                Divider()
                    .padding(.vertical, 12)

                Toggle(
                    isOn:
                        $favoritesOnly
                ) {
                    Label(
                        ATHLTHLocalization.string(
                            "Favorites only"
                        ),
                        systemImage:
                            "star.fill"
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .accentDeep
                    )
                }
                .tint(
                    ATHLTHTheme.vitality
                )

                if sort == .nearest {
                    Divider()
                        .padding(.vertical, 12)

                    VStack(
                        alignment: .leading,
                        spacing: 8
                    ) {
                        if locationStore
                            .isUpdating {
                            ProgressView(
                                "Finding your location…"
                            )
                        } else if locationStore
                            .location == nil {
                            Text(
                                "Location is unavailable. Routes are shown by name until your position is available."
                            )
                            .font(.caption)
                            .foregroundStyle(
                                ATHLTHTheme
                                    .mutedText
                            )

                            Button(
                                "Use my location"
                            ) {
                                locationStore
                                    .refresh()
                            }
                            .font(
                                .subheadline
                                    .weight(
                                        .semibold
                                    )
                            )
                        }

                        Text(
                            "Nearest is the straight-line distance to the route's centre, not travel distance to its start."
                        )
                        .font(.caption)
                        .foregroundStyle(
                            ATHLTHTheme
                                .mutedText
                        )
                    }
                }
            }
        }
        .athlthLightweightCardChrome()
    }

    @ViewBuilder
    private func routeRow(
        _ entry: RouteLibraryEntry
    ) -> some View {
        if source == .mine,
           let route =
                session.savedRoutes
                    .first(
                        where: {
                            $0.id ==
                            entry.id
                        }
                    ) {
            mineRouteCard(
                entry: entry,
                route: route
            )
            .listRowInsets(
                EdgeInsets(
                    top: 8,
                    leading: 16,
                    bottom: 8,
                    trailing: 16
                )
            )
            .listRowBackground(
                Color.clear
            )
            .listRowSeparator(
                .hidden
            )
        } else {
            databaseRouteRow(
                entry
            )
        }
    }

    private func mineRouteCard(
        entry: RouteLibraryEntry,
        route: TrainingRoute
    ) -> some View {
        ATHLTHCard {
            ZStack(
                alignment: .topTrailing
            ) {
                NavigationLink {
                    RouteDetailView(
                        route: route
                    )
                } label: {
                    VStack(
                        alignment: .leading,
                        spacing: 13
                    ) {
                        RouteMapSnapshotThumbnail(
                            route: route,
                            height: 118
                        )

                        HStack(
                            alignment: .center,
                            spacing: 12
                        ) {
                            VStack(
                                alignment:
                                    .leading,
                                spacing: 5
                            ) {
                                HStack(
                                    spacing: 6
                                ) {
                                    Image(
                                        systemName:
                                            "figure.run"
                                    )
                                    .foregroundStyle(
                                        ATHLTHTheme
                                            .vitality
                                    )

                                    Text(
                                        "ROUTE"
                                    )
                                    .font(
                                        .caption2
                                            .weight(
                                                .bold
                                            )
                                    )
                                    .tracking(1.2)
                                    .foregroundStyle(
                                        ATHLTHTheme
                                            .mutedText
                                    )
                                }

                                Text(
                                    entry.title
                                )
                                .font(
                                    .headline
                                )
                                .foregroundStyle(
                                    ATHLTHTheme
                                        .primaryText
                                )
                                .lineLimit(2)

                                HStack(
                                    spacing: 8
                                ) {
                                    Text(
                                        settings
                                            .measurementPreference
                                            .distance(
                                                fromKilometers:
                                                    entry
                                                        .distanceKilometers
                                            )
                                    )

                                    if let elevation =
                                            entry
                                                .elevationGainMeters {
                                        Text("·")
                                        Text(
                                            ATHLTHLocalization
                                                .format(
                                                    "%d m ascent",
                                                    Int(
                                                        elevation
                                                    )
                                                )
                                        )
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(
                                    ATHLTHTheme
                                        .mutedText
                                )

                                if let start =
                                        entry.startName,
                                   !start.isEmpty {
                                    Text(start)
                                        .font(
                                            .caption
                                        )
                                        .foregroundStyle(
                                            ATHLTHTheme
                                                .mutedText
                                        )
                                        .lineLimit(1)
                                }

                                if sort == .nearest,
                                   let distance =
                                        entry.distance(
                                            from:
                                                locationStore
                                                    .location
                                        ) {
                                    Label(
                                        ATHLTHLocalization
                                            .format(
                                                "%@ away",
                                                settings
                                                    .measurementPreference
                                                    .distance(
                                                        fromKilometers:
                                                            distance
                                                    )
                                            ),
                                        systemImage:
                                            "location"
                                    )
                                    .font(
                                        .caption
                                    )
                                    .foregroundStyle(
                                        ATHLTHTheme
                                            .vitality
                                    )
                                }
                            }

                            Spacer(
                                minLength: 8
                            )

                            Image(
                                systemName:
                                    "chevron.right"
                            )
                            .font(
                                .subheadline
                                    .weight(
                                        .bold
                                    )
                            )
                            .foregroundStyle(
                                ATHLTHTheme
                                    .mutedText
                                    .opacity(0.65)
                            )
                        }
                    }
                }
                .buttonStyle(.plain)
                .simultaneousGesture(
                    TapGesture()
                        .onEnded {
                            markRecent(
                                entry
                            )
                        }
                )

                LibraryFavoriteButton(
                    kind: .route,
                    itemID:
                        entry.id
                            .uuidString,
                    title:
                        entry.title,
                    subtitle:
                        settings
                            .measurementPreference
                            .distance(
                                fromKilometers:
                                    entry
                                        .distanceKilometers
                            ),
                    icon: "map.fill"
                )
                .padding(10)
            }
        }
        .athlthLightweightCardChrome()
    }

    private func databaseRouteRow(
        _ entry: RouteLibraryEntry
    ) -> some View {
        HStack(spacing: 8) {
            NavigationLink {
                RouteLibraryDetailLoader(
                    routeID: entry.id
                )
            } label: {
                VStack(
                    alignment: .leading,
                    spacing: 5
                ) {
                    Text(entry.title)
                        .font(.headline)

                    HStack(spacing: 10) {
                        Text(
                            settings
                                .measurementPreference
                                .distance(
                                    fromKilometers:
                                        entry
                                            .distanceKilometers
                                )
                        )

                        if let elevation =
                                entry
                                    .elevationGainMeters {
                            Text(
                                ATHLTHLocalization
                                    .format(
                                        "%d m ascent",
                                        Int(
                                            elevation
                                        )
                                    )
                            )
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(
                        .secondary
                    )

                    if let start =
                            entry.startName,
                       !start.isEmpty {
                        Text(start)
                            .font(.caption)
                            .foregroundStyle(
                                .secondary
                            )
                    }

                    if sort == .nearest,
                       let distance =
                            entry.distance(
                                from:
                                    locationStore
                                        .location
                            ) {
                        Label(
                            ATHLTHLocalization
                                .format(
                                    "%@ away",
                                    settings
                                        .measurementPreference
                                        .distance(
                                            fromKilometers:
                                                distance
                                        )
                                ),
                            systemImage:
                                "location"
                        )
                        .font(.caption)
                        .foregroundStyle(
                            ATHLTHTheme.accent
                        )
                    }
                }
                .padding(.vertical, 5)
            }
            .simultaneousGesture(
                TapGesture()
                    .onEnded {
                        markRecent(
                            entry
                        )
                    }
            )

            LibraryFavoriteButton(
                kind: .route,
                itemID:
                    entry.id.uuidString,
                title: entry.title,
                subtitle:
                    settings
                        .measurementPreference
                        .distance(
                            fromKilometers:
                                entry
                                    .distanceKilometers
                        ),
                icon: "map.fill"
            )
        }
    }

    private func markRecent(
        _ entry: RouteLibraryEntry
    ) {
        recents.markUsed(
            .route,
            itemID:
                entry.id.uuidString,
            title:
                entry.title,
            subtitle:
                settings
                    .measurementPreference
                    .distance(
                        fromKilometers:
                            entry
                                .distanceKilometers
                    ),
            icon: "map.fill"
        )
    }

    @MainActor
    private func loadCatalog(reset: Bool = true) async {
        if !reset && loading { return }
        let requestID = UUID()
        catalogRequestID = requestID
        loading = true
        errorMessage = nil
        if reset { catalog = []; hasMore = false }
        let offset = catalog.count
        defer { if catalogRequestID == requestID { loading = false } }
        do {
            if reset { try await Task.sleep(nanoseconds: 250_000_000) }
            let params = RouteCatalogSearchParameters(
                p_query: String(query.prefix(200)),
                p_sort: sort == .nearest && locationStore.location == nil ? "Name A–Z" : sort.rawValue,
                p_length: lengthFilter,
                p_latitude: locationStore.location?.coordinate.latitude,
                p_longitude: locationStore.location?.coordinate.longitude,
                p_offset: offset
            )
            let page: [RouteLibraryEntry] = try await SupabaseEnvironment.client
                .rpc("search_route_catalog", params: params).execute().value
            try Task.checkCancellation()
            guard catalogRequestID == requestID else { return }
            catalog += page
            hasMore = page.count == 50
        } catch {
            if !Task.isCancelled && catalogRequestID == requestID {
                errorMessage = error.localizedDescription
            }
        }
    }

}

struct RouteLibraryDetailLoader: View {
    let routeID: UUID
    @State private var route: TrainingRoute?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let route {
                RouteDetailView(route: route)
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("Route unavailable", systemImage: "map")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Retry") { Task { await load() } }
                }
            } else {
                ProgressView("Loading route…")
            }
        }
        .task(id: routeID) { await load() }
    }

    @MainActor
    private func load() async {
        errorMessage = nil
        do {
            let record: CommunityRouteRecord = try await SupabaseEnvironment.client
                .from("community_routes").select()
                .eq("id", value: routeID).single().execute().value
            try Task.checkCancellation()
            route = record.trainingRoute
        } catch {
            if !Task.isCancelled { errorMessage = error.localizedDescription }
        }
    }
}

private struct RouteLibraryGhostSurfaceModifier:
    ViewModifier {
    let enabled: Bool

    @ViewBuilder
    func body(
        content: Content
    ) -> some View {
        if enabled {
            content
                .listStyle(.plain)
                .scrollContentBackground(
                    .hidden
                )
                .background(
                    LinearGradient(
                        colors: [
                            ATHLTHTheme
                                .canvasTop,
                            ATHLTHTheme
                                .canvasBottom
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()
                )
        } else {
            content
        }
    }
}

private struct RouteCatalogSearchParameters: Encodable {
    let p_query: String
    let p_sort: String
    let p_length: Int
    let p_latitude: Double?
    let p_longitude: Double?
    let p_offset: Int
}
