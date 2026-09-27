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
    @StateObject private var locationStore = HomeLocationStore()
    let source: RouteLibrarySource

    @State private var catalog: [RouteLibraryEntry] = []
    @State private var query = ""
    @State private var sort: RouteLibrarySort = .newest
    @State private var lengthFilter = 0
    @State private var loading = false
    @State private var errorMessage: String?

    private var entries: [RouteLibraryEntry] {
        let values = source == .mine
            ? session.savedRoutes.map(RouteLibraryEntry.init(route:))
            : catalog
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
            return matchesSearch && matchesLength
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

            if let errorMessage {
                Section {
                    Text(errorMessage).font(.caption).foregroundStyle(.red)
                    Button("Retry") { Task { await loadCatalog() } }
                }
            }
            if loading {
                ProgressView("Loading routes…")
            }
            Section("\(entries.count) routes") {
                ForEach(entries) { entry in
                    NavigationLink {
                        if source == .mine,
                           let route = session.savedRoutes.first(where: { $0.id == entry.id }) {
                            RouteDetailView(route: route)
                        } else {
                            RouteLibraryDetailLoader(routeID: entry.id)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(entry.title).font(.headline)
                            HStack(spacing: 10) {
                                Text(settings.measurementPreference.distance(fromKilometers: entry.distanceKilometers))
                                if let elevation = entry.elevationGainMeters {
                                    Text("\(Int(elevation)) m ascent")
                                }
                            }
                            .font(.caption).foregroundStyle(.secondary)
                            if let start = entry.startName, !start.isEmpty {
                                Text(start).font(.caption).foregroundStyle(.secondary)
                            }
                            if sort == .nearest, let distance = entry.distance(from: locationStore.location) {
                                Label("\(settings.measurementPreference.distance(fromKilometers: distance)) away", systemImage: "location")
                                    .font(.caption).foregroundStyle(ATHLTHTheme.accent)
                            }
                        }
                        .padding(.vertical, 5)
                    }
                }
                if entries.isEmpty && !loading && errorMessage == nil {
                    ContentUnavailableView(
                        "No routes found", systemImage: "map",
                        description: Text(source == .mine
                            ? "Create or save a route, or try another search or filter."
                            : "Try another search or filter. Public routes appear here when shared.")
                    )
                }
            }
        }
        .navigationTitle(source == .mine ? "My Routes" : "Route Database")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search route or place")
        .toolbar {
            if source == .mine {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { RunRouteBuilderView() } label: {
                        Label("Create route", systemImage: "plus")
                    }
                }
            }
        }
        .task { if source == .database { await loadCatalog() } }
        .refreshable { if source == .database { await loadCatalog() } }
        .onChange(of: sort) { _, value in
            if value == .nearest { locationStore.refresh() }
        }
        .onDisappear { locationStore.stop() }
    }

    @MainActor
    private func loadCatalog() async {
        guard !loading else { return }
        loading = true
        errorMessage = nil
        defer { loading = false }
        do {
            var loaded: [RouteLibraryEntry] = []
            var offset = 0
            // Fetch only lightweight metadata, not every route's GPS polyline.
            // Page through the catalogue so nearest sorting isn't limited to
            // the small, newest-only discovery window used by the Home map.
            while true {
                try Task.checkCancellation()
                let page: [RouteLibraryEntry] = try await SupabaseEnvironment.client
                    .from("community_routes")
                    .select("id,title,distance_kilometers,elevation_gain_meters,start_name,end_name,center_latitude,center_longitude,created_at")
                    .eq("visibility", value: "public")
                    .order("id", ascending: true)
                    .range(from: offset, to: offset + 199)
                    .execute().value
                loaded.append(contentsOf: page)
                if page.count < 200 { break }
                offset += page.count
            }
            try Task.checkCancellation()
            var seen = Set<UUID>()
            catalog = loaded.filter { seen.insert($0.id).inserted }
        } catch {
            if !Task.isCancelled { errorMessage = error.localizedDescription }
        }
    }
}

private struct RouteLibraryDetailLoader: View {
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
