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
    @AppStorage("athlth.routes.browse.viewMode.v1")
    private var savedViewMode = ATHLTHRouteBrowseMode.cards.rawValue
    @State private var hydratedRoutes: [UUID: TrainingRoute] = [:]
    @State private var loadingDetails: Set<UUID> = []
    @State private var showingMapRoute: TrainingRoute?

    private var viewMode: ATHLTHRouteBrowseMode {
        ATHLTHRouteBrowseMode(rawValue: savedViewMode) ?? .cards
    }

    private var viewModeBinding: Binding<ATHLTHRouteBrowseMode> {
        Binding(get: { viewMode }, set: { savedViewMode = $0.rawValue })
    }

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

    @ViewBuilder
    var body: some View {
        if source == .mine {
            // My Routes and Choose Route now use exactly the same browsing
            // component and underlying saved-route store, not a duplicate UI.
            SavedRoutesView()
        } else {
            databaseBrowseView
        }
    }

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    private var databaseBrowseView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 15) {
                databaseHeader
                databaseFilters

                if sort == .nearest && locationStore.location == nil {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "location.slash")
                            .foregroundStyle(ATHLTHPlanDesign.accentInk)
                        Text(tr(
                            "Location unavailable. Showing routes by name. Distance is measured to the route's centre, not driving distance.",
                            "Posisjon er ikke tilgjengelig. Viser ruter etter navn. Avstand måles til rutens midtpunkt i luftlinje."))
                            .font(.caption)
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    }
                    .padding(12)
                    .athlthPlanCard()
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                    Button(tr("Try again", "Prøv igjen")) {
                        Task { await loadCatalog() }
                    }
                    .font(.subheadline.weight(.semibold))
                }

                HStack(alignment: .center, spacing: 12) {
                    Text(hasMore
                         ? tr("\(entries.count) routes loaded", "\(entries.count) ruter lastet inn")
                         : tr("\(entries.count) routes", "\(entries.count) ruter"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHPlanDesign.ink)
                    Spacer(minLength: 0)
                }

                ATHLTHRouteBrowseModePicker(selection: viewModeBinding)

                if loading && catalog.isEmpty {
                    ProgressView(tr("Loading routes…", "Henter ruter …"))
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else if entries.isEmpty && errorMessage == nil {
                    ContentUnavailableView(
                        tr("No matching routes", "Ingen ruter matcher"),
                        systemImage: "map",
                        description: Text(tr(
                            "Try a different search or adjust your filters.",
                            "Prøv et annet søk eller juster filtrene."))
                    )
                    .padding(.vertical, 20)
                } else {
                    if viewMode == .map {
                        databaseMap
                    }

                    ForEach(entries) { entry in
                        if viewMode == .cards {
                            databasePremiumCard(entry)
                        } else {
                            databaseCompactRow(entry)
                        }
                    }
                }

                if hasMore {
                    Button {
                        Task { await loadCatalog(reset: false) }
                    } label: {
                        HStack {
                            Spacer()
                            if loading { ProgressView().tint(ATHLTHPlanDesign.accentInk) }
                            Text(tr("Load more routes", "Last flere ruter"))
                            Image(systemName: "arrow.down.circle")
                            Spacer()
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHPlanDesign.accentInk)
                        .frame(minHeight: 48)
                        .athlthPlanCard()
                    }
                    .buttonStyle(.plain)
                    .disabled(loading)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 76)
            .frame(maxWidth: ATHLTHPlanDesign.maxContentWidth)
            .frame(maxWidth: .infinity)
        }
        .background(ATHLTHPlanDesign.warmCanvas.ignoresSafeArea())
        .navigationTitle(tr("Route database", "Rutedatabase"))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await loadCatalog() }
        .task(id: catalogKey) {
            recents.refresh()
            async let favoriteRefresh: Void = favorites.refresh()
            await loadCatalog()
            _ = await favoriteRefresh
        }
        .onChange(of: sort) { _, value in
            if value == .nearest { locationStore.refresh() }
        }
        .task(id: viewMode == .map
              ? catalogKey + "|map|" + entries.prefix(20)
                  .map { $0.id.uuidString }.joined(separator: ",")
                  + "|favorites:\(favoritesOnly)"
              : "") {
            if viewMode == .map { await loadMapRouteGeometry() }
        }
        .onChange(of: favoritesOnly) { _, _ in
            // Favorites filter is local; server sorting and pagination persist.
            if viewMode == .map {
                Task { await loadMapRouteGeometry() }
            }
        }
        .onDisappear { locationStore.stop() }
        .fullScreenCover(item: $showingMapRoute) { route in
            SavedRouteFullscreenMap(route: route)
        }
    }

    private var databaseHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("ATHLTH  /  " + tr("ROUTES", "RUTER"))
                    .font(.system(size: 10, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                Text(tr("Explore routes", "Utforsk ruter"))
                    .font(.system(size: 27, weight: .semibold, design: .serif))
                    .foregroundStyle(ATHLTHPlanDesign.ink)
                Text(tr("Discover routes shared with the community",
                        "Oppdag ruter som er delt med fellesskapet"))
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            }
            Spacer(minLength: 4)
            NavigationLink {
                RunRouteBuilderView()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 47, height: 47)
                    .background(ATHLTHTheme.accentDeep,
                                in: RoundedRectangle(cornerRadius: 15))
            }
            .accessibilityLabel(tr("Create route", "Opprett rute"))
        }
        .padding(.vertical, 8)
    }

    private var databaseFilters: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                TextField(tr("Search routes or places", "Søk etter ruter eller steder"),
                          text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.subheadline)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    }
                    .accessibilityLabel(tr("Clear search", "Tøm søk"))
                }
            }
            .padding(13)
            .background(ATHLTHPlanDesign.surface,
                        in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15)
                .strokeBorder(ATHLTHPlanDesign.outline))

            HStack(spacing: 9) {
                ForEach([false, true], id: \.self) { onlyFavorites in
                    Button { favoritesOnly = onlyFavorites } label: {
                        Label(onlyFavorites ? tr("Favorites", "Favoritter") :
                              tr("All", "Alle"),
                              systemImage: onlyFavorites ? "star.fill" :
                              "square.grid.2x2")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 14)
                            .frame(height: 35)
                            .foregroundStyle(favoritesOnly == onlyFavorites
                                ? Color.white : ATHLTHPlanDesign.ink)
                            .background(favoritesOnly == onlyFavorites
                                ? ATHLTHTheme.accentDeep : ATHLTHPlanDesign.warmSurface,
                                in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(favoritesOnly == onlyFavorites ? [.isSelected] : [])
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Menu {
                    ForEach(RouteLibrarySort.allCases) { option in
                        Button {
                            sort = option
                        } label: {
                            if sort == option {
                                Label(routeSortLabel(option), systemImage: "checkmark")
                            } else {
                                Text(routeSortLabel(option))
                            }
                        }
                    }
                } label: {
                    catalogFilterChip(routeSortLabel(sort), icon: "arrow.up.arrow.down")
                }
                Menu {
                    ForEach(0...4, id: \.self) { choice in
                        Button {
                            lengthFilter = choice
                        } label: {
                            if lengthFilter == choice {
                                Label(catalogLengthLabel(choice),
                                      systemImage: "checkmark")
                            } else {
                                Text(catalogLengthLabel(choice))
                            }
                        }
                    }
                } label: {
                    catalogFilterChip(catalogLengthLabel(lengthFilter),
                                      icon: "ruler")
                }
                Spacer(minLength: 0)
            }
        }
        .padding(15)
        .athlthPlanCard()
    }

    private func catalogFilterChip(_ title: String, icon: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
            Text(title).lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .semibold))
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(ATHLTHPlanDesign.ink)
        .padding(.horizontal, 10)
        .frame(height: 39)
        .background(ATHLTHPlanDesign.warmSurface,
                    in: RoundedRectangle(cornerRadius: 11))
    }

    private func catalogLengthLabel(_ option: Int) -> String {
        switch option {
        case 1: return tr("Under 5 km", "Under 5 km")
        case 2: return "5–10 km"
        case 3: return "10–21,1 km"
        case 4: return "21,1+ km"
        default: return tr("All lengths", "Alle lengder")
        }
    }

    private func routeSortLabel(_ value: RouteLibrarySort) -> String {
        switch value {
        case .newest: return tr("Newest", "Nyeste")
        case .nearest: return tr("Nearest", "Nærmest")
        case .shortest: return tr("Shortest", "Korteste")
        case .longest: return tr("Longest", "Lengste")
        case .leastClimbing: return tr("Least climbing", "Minst stigning")
        case .mostClimbing: return tr("Most climbing", "Mest stigning")
        case .name: return "A–Å"
        }
    }

    private func databasePremiumCard(_ entry: RouteLibraryEntry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Group {
                if let route = hydratedRoutes[entry.id] {
                    Button {
                        showingMapRoute = route
                    } label: {
                        ZStack(alignment: .bottomTrailing) {
                            RouteMapSnapshotThumbnail(route: route, height: 173)
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 17))
                            Label(tr("Explore", "Utforsk"),
                                  systemImage: "arrow.up.left.and.arrow.down.right")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(ATHLTHPlanDesign.ink)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(.regularMaterial, in: Capsule())
                                .padding(10)
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 17)
                            .fill(ATHLTHPlanDesign.selectedSurface)
                        VStack(spacing: 6) {
                            Image(systemName: "map")
                                .font(.title2)
                                .foregroundStyle(ATHLTHPlanDesign.accentInk)
                            Text(tr("Loading route preview", "Henter rutekart"))
                                .font(.caption2)
                                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        }
                    }
                    .frame(height: 173)
                }
            }
            .task(id: entry.id) { await loadRouteDetail(entry.id) }

            HStack(alignment: .top, spacing: 10) {
                NavigationLink {
                    RouteLibraryDetailLoader(routeID: entry.id)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.title)
                            .font(.headline)
                            .foregroundStyle(ATHLTHPlanDesign.ink)
                            .multilineTextAlignment(.leading)
                        let endpoints = [entry.startName, entry.endName]
                            .compactMap { $0 }
                            .filter { !$0.isEmpty }
                        if !endpoints.isEmpty {
                            Text(endpoints.joined(separator: " → "))
                                .font(.caption)
                                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                                .lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                LibraryFavoriteButton(
                    kind: .route, itemID: entry.id.uuidString,
                    title: entry.title,
                    subtitle: String(format: "%.1f km", entry.distanceKilometers),
                    icon: "map.fill")
            }

            HStack(spacing: 10) {
                Label(String(format: "%.1f km", entry.distanceKilometers),
                      systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                if let climb = entry.elevationGainMeters {
                    Label("\(Int(climb.rounded())) hm", systemImage: "mountain.2")
                }
                if let distance = entry.distance(from: locationStore.location) {
                    Label(String(format: "%.1f km", distance),
                          systemImage: "location")
                }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            .lineLimit(1)
            .minimumScaleFactor(0.78)

            HStack(spacing: 12) {
                NavigationLink {
                    RouteLibraryDetailLoader(routeID: entry.id)
                } label: {
                    Label(tr("Details", "Detaljer"), systemImage: "arrow.up.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHPlanDesign.accentInk)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                Button {
                    if let route = hydratedRoutes[entry.id] {
                        showingMapRoute = route
                    }
                } label: {
                    Label(tr("Explore map", "Utforsk kart"),
                          systemImage: "map.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 45)
                        .background(ATHLTHTheme.accentDeep,
                                    in: RoundedRectangle(cornerRadius: 13))
                }
                .buttonStyle(.plain)
                .disabled(hydratedRoutes[entry.id] == nil)
                .opacity(hydratedRoutes[entry.id] == nil ? 0.45 : 1)
            }
            .simultaneousGesture(TapGesture().onEnded { markRecent(entry) })
        }
        .padding(14)
        .athlthPlanCard()
    }

    private func databaseCompactRow(_ entry: RouteLibraryEntry) -> some View {
        HStack(spacing: 10) {
            NavigationLink {
                RouteLibraryDetailLoader(routeID: entry.id)
            } label: {
                HStack(spacing: 10) {
                    if let route = hydratedRoutes[entry.id] {
                        RouteMapSnapshotThumbnail(route: route, height: 80)
                            .frame(width: 100, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        Image(systemName: "map")
                            .foregroundStyle(ATHLTHPlanDesign.accentInk)
                            .frame(width: 100, height: 80)
                            .background(ATHLTHPlanDesign.selectedSurface,
                                        in: RoundedRectangle(cornerRadius: 12))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ATHLTHPlanDesign.ink)
                            .lineLimit(2)
                        Text(String(format: "%.1f km", entry.distanceKilometers))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(ATHLTHPlanDesign.accentInk)
                        if let start = entry.startName, !start.isEmpty {
                            Text(start)
                                .font(.caption2)
                                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                }
            }
            .buttonStyle(.plain)
            LibraryFavoriteButton(
                kind: .route, itemID: entry.id.uuidString,
                title: entry.title,
                subtitle: String(format: "%.1f km", entry.distanceKilometers),
                icon: "map.fill"
            )
        }
        .padding(11)
        .athlthPlanCard()
    }

    private var databaseMap: some View {
        VStack(alignment: .leading, spacing: 9) {
            let routes = entries.prefix(20).compactMap { hydratedRoutes[$0.id] }
            if routes.isEmpty {
                ProgressView(tr("Loading route map…", "Henter rutekart …"))
                    .frame(maxWidth: .infinity, minHeight: 250)
                    .background(ATHLTHPlanDesign.selectedSurface,
                                in: RoundedRectangle(cornerRadius: 17))
            } else {
                SavedRouteOverviewMap(routes: routes) { route in
                    showingMapRoute = route
                }
                .frame(height: 310)
                .clipShape(RoundedRectangle(cornerRadius: 19))
            }
            Text(tr(
                "Map displays up to 20 currently loaded routes. The list below shows every filtered result.",
                "Kartet viser inntil 20 innlastede ruter. Listen under viser alle filtrerte treff."))
                .font(.caption2)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
        }
    }

    @MainActor
    private func loadRouteDetail(_ id: UUID) async {
        guard hydratedRoutes[id] == nil, !loadingDetails.contains(id) else { return }
        loadingDetails.insert(id)
        defer { loadingDetails.remove(id) }
        do {
            let record: CommunityRouteRecord = try await SupabaseEnvironment.client
                .from("community_routes")
                .select()
                .eq("id", value: id)
                .single()
                .execute().value
            guard !Task.isCancelled else { return }
            hydratedRoutes[id] = record.trainingRoute
        } catch {
            // A route may be removed or made private while the list is open.
            // The metadata card remains usable via its normal details loader.
        }
    }

    @MainActor
    private func loadMapRouteGeometry() async {
        for entry in entries.prefix(20) {
            guard !Task.isCancelled, viewMode == .map else { return }
            await loadRouteDetail(entry.id)
        }
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
