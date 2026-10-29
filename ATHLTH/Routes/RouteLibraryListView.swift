import CoreLocation
import SwiftUI
import Supabase

enum RouteLibrarySource {
    case database, mine
}

/// The library has two explicit data sources. Public discovery must never
/// be treated as the user's private, locally saved route collection.
enum RouteLibraryCollection: String, CaseIterable, Identifiable {
    case publicRoutes
    case savedRoutes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .publicRoutes:
            return ATHLTHLocalization.choose(
                english: "Public routes", norwegian: "Offentlige")
        case .savedRoutes:
            return ATHLTHLocalization.choose(
                english: "My saved routes", norwegian: "Mine lagrede")
        }
    }

    var symbol: String {
        switch self {
        case .publicRoutes: return "globe.europe.africa"
        case .savedRoutes: return "bookmark.fill"
        }
    }
}

// Shared visual language with My Routes, with public-only content in Routes.
// Friends means mutually followed route owners, never friends-only visibility.
enum PublicRouteBrowseFilter: String, CaseIterable, Identifiable {
    case all, favorites, friends
    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return ATHLTHLocalization.choose(english: "All", norwegian: "Alle")
        case .favorites:
            return ATHLTHLocalization.choose(english: "Favorites", norwegian: "Favoritter")
        case .friends:
            return ATHLTHLocalization.choose(english: "Friends", norwegian: "Venner")
        }
    }
    var symbol: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .favorites: return "star.fill"
        case .friends: return "person.2.fill"
        }
    }
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

struct RouteLibraryEntry: Decodable, Identifiable {
    let id: UUID
    let ownerID: UUID
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
        case ownerID = "owner_id"
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
        ownerID = route.ownerID
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
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var watchConnection: AppleWatchConnectionStore
    @EnvironmentObject private var favorites: LibraryFavoritesStore
    @EnvironmentObject private var recents: LibraryRecentsStore
    @StateObject private var locationStore = HomeLocationStore()
    let source: RouteLibrarySource

    @State private var selectedCollection: RouteLibraryCollection = .publicRoutes
    @State private var didSaveRouteInBuilder = false
    @State private var catalog: [RouteLibraryEntry] = []
    @State private var query = ""
    @State private var sort: RouteLibrarySort = .nearest
    @State private var lengthFilter = 0
    @State private var showingCustomLength = false
    @AppStorage("athlth.routes.picker.minLength.v1") private var minLength = 0.0
    @AppStorage("athlth.routes.picker.maxLength.v1") private var maxLength = 20.0
    @State private var publicFilter: PublicRouteBrowseFilter = .all
    // Retained only for the legacy, non-rendered mine helpers below.
    @State private var favoritesOnly = false
    @AppStorage("athlth.routes.picker.runPace.v1")
    private var manualRunSecondsPerKm = 0
    @State private var watchMessage: String?
    @State private var watchError: String?
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
         lengthFilter == 6 ? String(minLength) : "",
         lengthFilter == 6 ? String(maxLength) : "",
         String(publicFilter == .friends),
         String(locationStore.location?.coordinate.latitude ?? 0),
         String(locationStore.location?.coordinate.longitude ?? 0)].joined(separator: "|")
    }

    private var entries: [RouteLibraryEntry] {
        if source == .database {
            return publicFilter == .favorites
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
            VStack(spacing: 0) {
                routeCollectionPicker
                if selectedCollection == .publicRoutes {
                    databaseBrowseView
                } else {
                    // The same owned-route view already used in the rest of
                    // ATHLTH. It includes private and public saved routes,
                    // without uploading private routes to public discovery.
                    SavedRoutesView()
                }
            }
            .background(ATHLTHPlanDesign.warmCanvas.ignoresSafeArea())
        }
    }

    private var routeCollectionPicker: some View {
        HStack(spacing: 8) {
            ForEach(RouteLibraryCollection.allCases) { collection in
                let isSelected = selectedCollection == collection
                Button {
                    selectedCollection = collection
                } label: {
                    Label(collection.title, systemImage: collection.symbol)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(isSelected ? .white : ATHLTHPlanDesign.ink)
                        .background(
                            isSelected ? ATHLTHTheme.accentDeep
                                : ATHLTHPlanDesign.warmSurface,
                            in: RoundedRectangle(cornerRadius: 15)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 3)
        .frame(maxWidth: ATHLTHPlanDesign.maxContentWidth)
        .frame(maxWidth: .infinity)
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
                            "Location unavailable. Showing routes by name until distance can be calculated.",
                            "Posisjon er ikke tilgjengelig. Viser ruter etter navn til avstand kan beregnes."))
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
                            publicFilter == .friends
                                ? "Only public routes shared by mutual friends appear here."
                                : "Try a different search or adjust your filters.",
                            publicFilter == .friends
                                ? "Her vises bare offentlige ruter fra venner som følger hverandre."
                                : "Prøv et annet søk eller juster filtrene."))
                    )
                    .padding(.vertical, 20)
                    if publicFilter != .all || lengthFilter != 0 || !query.isEmpty {
                        Button(tr("Clear filters", "Nullstill filtre")) {
                            query = ""
                            lengthFilter = 0
                            publicFilter = .all
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHPlanDesign.accentInk)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .athlthPlanCard()
                    }
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
        .navigationTitle(tr("Routes", "Ruter"))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await loadCatalog() }
        .task(id: catalogKey) {
            recents.refresh()
            if sort == .nearest { locationStore.start() }
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
                  + "|filter:\(publicFilter.rawValue)"
              : "") {
            if viewMode == .map { await loadMapRouteGeometry() }
        }
        .onChange(of: publicFilter) { _, _ in
            // Favorites filter is local; server sorting and pagination persist.
            if viewMode == .map {
                Task { await loadMapRouteGeometry() }
            }
        }
        .onDisappear { locationStore.stop() }
        .sheet(isPresented: $showingCustomLength) { publicCustomLengthSheet }
        .fullScreenCover(item: $showingMapRoute) { route in
            SavedRouteFullscreenMap(route: route)
        }
        .alert("ATHLTH", isPresented: Binding(
            get: { watchMessage != nil || watchError != nil },
            set: { if !$0 { watchMessage = nil; watchError = nil } }
        )) {
            Button("OK", role: .cancel) {
                watchMessage = nil
                watchError = nil
            }
        } message: {
            Text(watchError ?? watchMessage ?? "")
        }
    }

    private var databaseHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("ATHLTH  /  " + tr("ROUTES", "RUTER"))
                    .font(.system(size: 10, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                Text(tr("Find new routes", "Finn nye ruter"))
                    .font(.system(size: 27, weight: .semibold, design: .serif))
                    .foregroundStyle(ATHLTHPlanDesign.ink)
                Text(tr("Public routes from ATHLTH members",
                        "Offentlige ruter fra ATHLTH-fellesskapet"))
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            }
            Spacer(minLength: 4)
            NavigationLink {
                RunRouteBuilderView(onRouteSaved: {
                    didSaveRouteInBuilder = true
                })
                .onDisappear {
                    guard didSaveRouteInBuilder else { return }
                    didSaveRouteInBuilder = false
                    // A newly saved private route will never appear in
                    // public search. Reveal it in the owned-route library.
                    // Reset any persistent restrictive filters once so the
                    // new route is actually visible, newest first.
                    UserDefaults.standard.set(
                        "all", forKey: "athlth.routes.picker.visibility.v1"
                    )
                    UserDefaults.standard.set(
                        0, forKey: "athlth.routes.picker.length.v1"
                    )
                    UserDefaults.standard.set(
                        "newest", forKey: "athlth.routes.picker.sort.v1"
                    )
                    selectedCollection = .savedRoutes
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(ATHLTHTheme.accentDeep,
                                in: RoundedRectangle(cornerRadius: 16))
            }
            .accessibilityLabel(tr("Create route", "Opprett rute"))
        }
        .padding(.vertical, 8)
    }

    private var databaseFilters: some View {
        VStack(alignment: .leading, spacing: 14) {
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
            .padding(14)
            .background(ATHLTHPlanDesign.surface,
                        in: RoundedRectangle(cornerRadius: 15))
            .overlay {
                RoundedRectangle(cornerRadius: 15)
                    .stroke(ATHLTHPlanDesign.outline)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(PublicRouteBrowseFilter.allCases) { option in
                        Button {
                            publicFilter = option
                        } label: {
                            Label(option.title, systemImage: option.symbol)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 13)
                                .frame(height: 36)
                                .foregroundStyle(publicFilter == option
                                                 ? .white : ATHLTHPlanDesign.ink)
                                .background(publicFilter == option
                                            ? ATHLTHTheme.accentDeep
                                            : ATHLTHPlanDesign.warmSurface,
                                            in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(publicFilter == option ? [.isSelected] : [])
                    }
                }
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
                    ForEach(0..<6, id: \.self) { option in
                        Button { lengthFilter = option } label: {
                            if lengthFilter == option {
                                Label(catalogLengthLabel(option), systemImage: "checkmark")
                            } else {
                                Text(catalogLengthLabel(option))
                            }
                        }
                    }
                    Divider()
                    Button {
                        showingCustomLength = true
                    } label: {
                        Label(tr("Custom range", "Egendefinert lengde"),
                              systemImage: "slider.horizontal.3")
                    }
                } label: {
                    catalogFilterChip(catalogLengthLabel(lengthFilter), icon: "ruler")
                }
                Spacer(minLength: 0)
                Menu {
                    Text(tr("Running pace", "Løpetempo"))
                    Button(tr("Automatic / my workouts", "Automatisk / mine økter")) {
                        manualRunSecondsPerKm = 0
                    }
                    ForEach([300, 360, 420, 480], id: \.self) { seconds in
                        Button("\(seconds / 60):00 min/km") {
                            manualRunSecondsPerKm = seconds
                        }
                    }
                } label: {
                    Image(systemName: "figure.run.circle")
                        .font(.system(size: 21))
                        .foregroundStyle(ATHLTHPlanDesign.accentInk)
                        .frame(width: 42, height: 40)
                        .background(ATHLTHPlanDesign.warmSurface,
                                    in: RoundedRectangle(cornerRadius: 12))
                }
                .accessibilityLabel(tr("Change estimated running pace",
                                       "Endre estimert løpetempo"))
            }
        }
        .padding(16)
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
        case 1: return "< 3 km"
        case 2: return "3–5 km"
        case 3: return "5–10 km"
        case 4: return "10–20 km"
        case 5: return "20+ km"
        case 6: return String(format: "%.0f–%.0f km", minLength, maxLength)
        default: return tr("All lengths", "Alle lengder")
        }
    }

    private func routeSortLabel(_ value: RouteLibrarySort) -> String {
        switch value {
        case .newest: return tr("Newest", "Nyeste")
        case .nearest: return tr("Nearest route", "Nærmest rute")
        case .shortest: return tr("Shortest", "Korteste")
        case .longest: return tr("Longest", "Lengste")
        case .leastClimbing: return tr("Least climbing", "Minst stigning")
        case .mostClimbing: return tr("Most climbing", "Mest stigning")
        case .name: return "A–Å"
        }
    }

    private var publicCustomLengthSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text(tr("Route length", "Rutelengde"))
                    .font(.system(size: 25, weight: .semibold, design: .serif))
                Text(tr("Choose the range of distances you want to see.",
                        "Velg lengdeintervallet for rutene du vil se."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 6) {
                    Text(tr("From \(Int(minLength)) km", "Fra \(Int(minLength)) km"))
                    Slider(value: $minLength, in: 0...100, step: 1)
                        .tint(ATHLTHPlanDesign.accentInk)
                        .onChange(of: minLength) { _, value in
                            if value > maxLength { maxLength = value }
                        }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(tr("To \(Int(maxLength)) km", "Til \(Int(maxLength)) km"))
                    Slider(value: $maxLength, in: 0...100, step: 1)
                        .tint(ATHLTHPlanDesign.accentInk)
                        .onChange(of: maxLength) { _, value in
                            if value < minLength { minLength = value }
                        }
                }
                Spacer()
                Button(tr("Show routes", "Vis ruter")) {
                    if maxLength < minLength { maxLength = minLength }
                    lengthFilter = 6
                    showingCustomLength = false
                }
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 52)
                .foregroundStyle(.white)
                .background(ATHLTHTheme.accentDeep,
                            in: RoundedRectangle(cornerRadius: 15))
            }
            .padding(22)
            .background(ATHLTHPlanDesign.warmCanvas.ignoresSafeArea())
            .navigationTitle(tr("Filter", "Filter"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(tr("Done", "Ferdig")) {
                        if maxLength < minLength { maxLength = minLength }
                        lengthFilter = 6
                        showingCustomLength = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func recentPace(for activity: WorkoutActivity, fallback: Double) -> Double {
        let paces = health.workouts
            .filter { $0.activity == activity && ($0.distanceMeters ?? 0) >= 1_000 }
            .sorted { $0.startDate > $1.startDate }
            .prefix(10)
            .compactMap { $0.paceMinutesPerKilometer }
            .filter { pace in
                activity == .running ? (pace >= 3 && pace <= 12) : (pace >= 8 && pace <= 22)
            }
            .sorted()
        return paces.count >= 3 ? paces[paces.count / 2] : fallback
    }

    private var walkPaceMinutes: Double { recentPace(for: .walking, fallback: 12) }
    private var runPaceMinutes: Double {
        manualRunSecondsPerKm > 0
            ? Double(manualRunSecondsPerKm) / 60
            : recentPace(for: .running, fallback: 6)
    }

    private func estimatedDuration(kilometers: Double, paceMinutes: Double) -> String {
        let minutes = max(1, Int((kilometers * paceMinutes).rounded()))
        if minutes >= 60 {
            let hours = minutes / 60
            let remainder = minutes % 60
            return remainder == 0 ? "\(hours) t" : "\(hours) t \(remainder) min"
        }
        return "\(minutes) min"
    }

    private func publicRouteMetric(value: String, caption: String, icon: String) -> some View {
        VStack(spacing: 5) {
            Label(caption, systemImage: icon)
                .font(.system(size: 9, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(ATHLTHPlanDesign.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
    }

    private func publicStartDistance(for route: TrainingRoute) -> Double? {
        guard let current = locationStore.location,
              let start = route.coordinates.min(by: { $0.sequence < $1.sequence })?.coordinate
        else { return nil }
        return current.distance(
            from: CLLocation(latitude: start.latitude, longitude: start.longitude)
        ) / 1_000
    }

    private func authorLabel(for entry: RouteLibraryEntry) -> String {
        if let friend = social.mutualFollows.first(where: { $0.userID == entry.ownerID }) {
            return friend.resolvedName
        }
        return tr("Public", "Offentlig")
    }

    private func sendPublicRouteToWatch(_ route: TrainingRoute) {
        guard watchConnection.isReady else { return }
        do {
            try watchConnection.sendRoute(route)
            watchMessage = tr("Route sent to Apple Watch.", "Ruten er sendt til Apple Watch.")
        } catch {
            watchError = error.localizedDescription
        }
    }

    private func databasePremiumCard(_ entry: RouteLibraryEntry) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Group {
                if let route = hydratedRoutes[entry.id] {
                    Button {
                        markRecent(entry)
                        showingMapRoute = route
                    } label: {
                        ZStack(alignment: .bottomTrailing) {
                            RouteMapSnapshotThumbnail(route: route, height: 174)
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
                    .accessibilityLabel(tr("Explore map for \(entry.title)",
                                           "Utforsk kart for \(entry.title)"))
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
                    .frame(height: 174)
                }
            }
            .task(id: entry.id) { await loadRouteDetail(entry.id) }

            HStack(alignment: .top, spacing: 10) {
                NavigationLink {
                    RouteLibraryDetailLoader(routeID: entry.id)
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(entry.title)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(ATHLTHPlanDesign.ink)
                            .fixedSize(horizontal: false, vertical: true)
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
                    kind: .route,
                    itemID: entry.id.uuidString,
                    title: entry.title,
                    subtitle: String(format: "%.1f km", entry.distanceKilometers),
                    icon: "map.fill"
                )
                Menu {
                    if settings.trainingDeviceProvider == .appleWatch {
                        Button {
                            if let route = hydratedRoutes[entry.id] {
                                sendPublicRouteToWatch(route)
                            }
                        } label: {
                            Label(tr("Send to Apple Watch", "Send til Apple Watch"),
                                  systemImage: "applewatch")
                        }
                        .disabled(!watchConnection.isReady || hydratedRoutes[entry.id] == nil)
                    }
                    if hydratedRoutes[entry.id] != nil {
                        NavigationLink {
                            ChallengeCreationView(preselectedRouteID: entry.id)
                        } label: {
                            Label(tr("Create challenge", "Opprett utfordring"),
                                  systemImage: "trophy.fill")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.headline)
                        .foregroundStyle(ATHLTHPlanDesign.ink)
                        .frame(width: 36, height: 36)
                        .background(ATHLTHPlanDesign.warmSurface, in: Circle())
                }
            }

            HStack(spacing: 7) {
                Label(authorLabel(for: entry),
                      systemImage: publicFilter == .friends
                          ? "person.2.fill" : "globe.europe.africa.fill")
                if let route = hydratedRoutes[entry.id],
                   let proximity = publicStartDistance(for: route) {
                    Label(String(format: "%.1f km %@", proximity,
                                 tr("to start", "til start")),
                          systemImage: "location")
                }
                if let climb = entry.elevationGainMeters {
                    Label("\(Int(climb.rounded())) hm", systemImage: "mountain.2")
                }
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            .lineLimit(1)
            .minimumScaleFactor(0.8)

            HStack(spacing: 0) {
                publicRouteMetric(
                    value: String(format: "%.1f km", entry.distanceKilometers),
                    caption: tr("DISTANCE", "DISTANSE"),
                    icon: "point.topleft.down.to.point.bottomright.curvepath"
                )
                Divider().frame(height: 35)
                publicRouteMetric(
                    value: estimatedDuration(kilometers: entry.distanceKilometers,
                                             paceMinutes: walkPaceMinutes),
                    caption: tr("EST. WALK", "EST. GANGE"),
                    icon: "figure.walk"
                )
                Divider().frame(height: 35)
                publicRouteMetric(
                    value: estimatedDuration(kilometers: entry.distanceKilometers,
                                             paceMinutes: runPaceMinutes),
                    caption: tr("EST. RUN", "EST. LØPING"),
                    icon: "figure.run"
                )
            }
            .padding(.vertical, 12)
            .background(ATHLTHPlanDesign.warmSurface.opacity(0.7),
                        in: RoundedRectangle(cornerRadius: 14))

            Text(tr("Time estimates use your recent workouts or a standard pace; elevation and stops may affect actual time.",
                    "Tidsanslagene bruker dine siste økter eller standardtempo. Stigning og stopp kan endre faktisk tid."))
                .font(.system(size: 10))
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)

            HStack(spacing: 12) {
                NavigationLink {
                    RouteLibraryDetailLoader(routeID: entry.id)
                } label: {
                    Label(tr("Details", "Detaljer"), systemImage: "arrow.up.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHPlanDesign.accentInk)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .simultaneousGesture(TapGesture().onEnded {
                    markRecent(entry)
                })
                if settings.trainingDeviceProvider == .appleWatch {
                    Button {
                        if let route = hydratedRoutes[entry.id] {
                            markRecent(entry)
                            sendPublicRouteToWatch(route)
                        }
                    } label: {
                        Label(tr("Send to Watch", "Send til Watch"),
                              systemImage: "applewatch")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(ATHLTHTheme.accentDeep,
                                        in: RoundedRectangle(cornerRadius: 13))
                    }
                    .buttonStyle(.plain)
                    .disabled(!watchConnection.isReady || hydratedRoutes[entry.id] == nil)
                    .opacity(!watchConnection.isReady || hydratedRoutes[entry.id] == nil ? 0.45 : 1)
                }
            }
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
        // One RLS-protected batch instead of twenty sequential round-trips.
        // The catalogue RPC returns metadata only; detailed polylines are
        // fetched on demand for the visible map and capped for MapKit memory.
        guard viewMode == .map, !Task.isCancelled else { return }
        let ids = entries.prefix(20).map(\.id)
            .filter { hydratedRoutes[$0] == nil }
        guard !ids.isEmpty else { return }
        do {
            let records: [CommunityRouteRecord] = try await SupabaseEnvironment.client
                .from("community_routes")
                .select()
                .in("id", values: ids.map(\.uuidString))
                .execute().value
            guard !Task.isCancelled, viewMode == .map else { return }
            let requested = Set(ids)
            for record in records where requested.contains(record.id) {
                hydratedRoutes[record.id] = record.trainingRoute
            }
        } catch {
            // Server permission or transient failure: all rows remain
            // navigable through RouteLibraryDetailLoader.
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
                p_offset: offset,
                p_friends_only: publicFilter == .friends,
                p_min_length: minLength,
                p_max_length: maxLength
            )
            let page: [RouteLibraryEntry] = try await SupabaseEnvironment.client
                .rpc("search_public_route_catalog", params: params).execute().value
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

struct RouteCatalogSearchParameters: Encodable {
    let p_query: String
    let p_sort: String
    let p_length: Int
    let p_latitude: Double?
    let p_longitude: Double?
    let p_offset: Int
    let p_friends_only: Bool
    let p_min_length: Double
    let p_max_length: Double
}
