import CoreLocation
import MapKit
import SwiftUI

// Route selection deliberately shares the Plan workspace's visual language.
// Preferences are local, persistent, and independent of the current workout.
private enum SavedRouteSort: String, CaseIterable, Identifiable {
    case nearest, newest, shortest, longest, leastClimbing, mostClimbing, name
    var id: String { rawValue }

    var title: String {
        switch self {
        case .nearest: return ATHLTHLocalization.choose(english: "Nearest start", norwegian: "Nærmest start")
        case .newest: return ATHLTHLocalization.choose(english: "Newest", norwegian: "Nyeste")
        case .shortest: return ATHLTHLocalization.choose(english: "Shortest", norwegian: "Korteste")
        case .longest: return ATHLTHLocalization.choose(english: "Longest", norwegian: "Lengste")
        case .leastClimbing: return ATHLTHLocalization.choose(english: "Least climbing", norwegian: "Minst stigning")
        case .mostClimbing: return ATHLTHLocalization.choose(english: "Most climbing", norwegian: "Mest stigning")
        case .name: return "A–Å"
        }
    }
}

private enum SavedRouteFilter: String, CaseIterable, Identifiable {
    case all, favorites, privateOnly, friends, publicProfile
    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return ATHLTHLocalization.choose(english: "All", norwegian: "Alle")
        case .favorites: return ATHLTHLocalization.choose(english: "Favorites", norwegian: "Favoritter")
        case .privateOnly: return ATHLTHLocalization.choose(english: "Private", norwegian: "Privat")
        case .friends: return ATHLTHLocalization.choose(english: "Friends", norwegian: "Venner")
        case .publicProfile: return ATHLTHLocalization.choose(english: "Public", norwegian: "Offentlig")
        }
    }

    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .favorites: return "star.fill"
        case .privateOnly: return "lock.fill"
        case .friends: return "person.2.fill"
        case .publicProfile: return "globe.europe.africa.fill"
        }
    }
}

private struct PositionedSavedRoute {
    let route: TrainingRoute
    let startDistanceKilometers: Double?
}

struct SavedRoutesView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var watchConnection: AppleWatchConnectionStore
    @EnvironmentObject private var favorites: LibraryFavoritesStore
    @EnvironmentObject private var recents: LibraryRecentsStore
    @EnvironmentObject private var health: HealthKitManager
    @StateObject private var locationStore = HomeLocationStore()

    let selectionTitle: String?
    let onSelect: ((TrainingRoute) -> Void)?

    @AppStorage("athlth.routes.picker.sort.v1") private var sortPreference = SavedRouteSort.nearest.rawValue
    @AppStorage("athlth.routes.picker.visibility.v1") private var visibilityPreference = SavedRouteFilter.all.rawValue
    @AppStorage("athlth.routes.picker.length.v1") private var lengthPreference = 0
    @AppStorage("athlth.routes.picker.minLength.v1") private var minLength = 0.0
    @AppStorage("athlth.routes.picker.maxLength.v1") private var maxLength = 20.0
    @AppStorage("athlth.routes.picker.runPace.v1") private var manualRunSecondsPerKm = 0
    @AppStorage("athlth.routes.browse.viewMode.v1")
    private var savedViewMode = ATHLTHRouteBrowseMode.cards.rawValue

    private var viewMode: ATHLTHRouteBrowseMode {
        ATHLTHRouteBrowseMode(rawValue: savedViewMode) ?? .cards
    }

    private var viewModeBinding: Binding<ATHLTHRouteBrowseMode> {
        Binding(
            get: { viewMode },
            set: { savedViewMode = $0.rawValue }
        )
    }

    @State private var search = ""
    @State private var showingCustomLength = false
    @State private var previewRoute: TrainingRoute?
    @State private var watchMessage: String?
    @State private var watchError: String?

    init(selectionTitle: String? = nil, onSelect: ((TrainingRoute) -> Void)? = nil) {
        self.selectionTitle = selectionTitle
        self.onSelect = onSelect
    }

    private var sort: SavedRouteSort {
        SavedRouteSort(rawValue: sortPreference) ?? .nearest
    }

    private var filter: SavedRouteFilter {
        SavedRouteFilter(rawValue: visibilityPreference) ?? .all
    }

    private var hasLocation: Bool { locationStore.location != nil }

    private func startDistance(for route: TrainingRoute) -> Double? {
        guard let current = locationStore.location,
              let start = route.coordinates.min(by: { $0.sequence < $1.sequence })?.coordinate
        else { return nil }
        return current.distance(from: CLLocation(latitude: start.latitude, longitude: start.longitude)) / 1_000
    }

    private func matchesLength(_ kilometers: Double) -> Bool {
        switch lengthPreference {
        case 1: return kilometers < 3
        case 2: return kilometers >= 3 && kilometers < 5
        case 3: return kilometers >= 5 && kilometers < 10
        case 4: return kilometers >= 10 && kilometers < 20
        case 5: return kilometers >= 20
        case 6: return kilometers >= minLength && kilometers <= maxLength
        default: return true
        }
    }

    private var visibleRoutes: [PositionedSavedRoute] {
        let needle = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = session.savedRoutes.filter { route in
            let visible: Bool
            switch filter {
            case .all: visible = true
            case .favorites: visible = favorites.isFavorite(.route, itemID: route.id.uuidString)
            case .privateOnly: visible = route.visibility == .privateOnly
            case .friends: visible = route.visibility == .friends
            case .publicProfile: visible = route.visibility == .publicProfile
            }
            let matchesSearch = needle.isEmpty ||
                [route.title, route.startName ?? "", route.endName ?? ""]
                    .contains { $0.localizedCaseInsensitiveContains(needle) }
            return visible && matchesLength(route.distanceKilometers) && matchesSearch
        }
        let located = candidates.map {
            PositionedSavedRoute(route: $0, startDistanceKilometers: startDistance(for: $0))
        }
        return located.sorted { lhs, rhs in
            let left = lhs.route
            let right = rhs.route
            switch sort {
            case .nearest:
                if let a = lhs.startDistanceKilometers, let b = rhs.startDistanceKilometers,
                   abs(a - b) > 0.001 { return a < b }
                if lhs.startDistanceKilometers != nil && rhs.startDistanceKilometers == nil { return true }
                if lhs.startDistanceKilometers == nil && rhs.startDistanceKilometers != nil { return false }
            case .newest: break
            case .shortest:
                if left.distanceKilometers != right.distanceKilometers {
                    return left.distanceKilometers < right.distanceKilometers
                }
            case .longest:
                if left.distanceKilometers != right.distanceKilometers {
                    return left.distanceKilometers > right.distanceKilometers
                }
            case .leastClimbing:
                if let a = left.elevationGainMeters, let b = right.elevationGainMeters, a != b {
                    return a < b
                }
                if left.elevationGainMeters != nil && right.elevationGainMeters == nil { return true }
                if left.elevationGainMeters == nil && right.elevationGainMeters != nil { return false }
            case .mostClimbing:
                if let a = left.elevationGainMeters, let b = right.elevationGainMeters, a != b {
                    return a > b
                }
                if left.elevationGainMeters != nil && right.elevationGainMeters == nil { return true }
                if left.elevationGainMeters == nil && right.elevationGainMeters != nil { return false }
            case .name:
                let comparison = left.title.localizedStandardCompare(right.title)
                if comparison != .orderedSame { return comparison == .orderedAscending }
            }
            if left.createdAt != right.createdAt { return left.createdAt > right.createdAt }
            return left.id.uuidString < right.id.uuidString
        }
    }

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }

    private var lengthTitle: String {
        switch lengthPreference {
        case 1: return "< 3 km"
        case 2: return "3–5 km"
        case 3: return "5–10 km"
        case 4: return "10–20 km"
        case 5: return "20+ km"
        case 6: return String(format: "%.0f–%.0f km", minLength, maxLength)
        default: return tr("All lengths", "Alle lengder")
        }
    }

    private func recentPace(for activity: WorkoutActivity, fallback: Double) -> Double {
        // Completed Health workouts only; reject tiny samples and unrealistic paces.
        let paces = health.workouts
            .filter { $0.activity == activity && ($0.distanceMeters ?? 0) >= 1_000 }
            .sorted { $0.startDate > $1.startDate }
            .prefix(10)
            .compactMap { $0.paceMinutesPerKilometer }
            .filter { pace in
                activity == .running ? (pace >= 3 && pace <= 12) : (pace >= 8 && pace <= 22)
            }
            .sorted()
        guard paces.count >= 3 else { return fallback }
        return paces[paces.count / 2]
    }

    private var walkPaceMinutes: Double {
        recentPace(for: .walking, fallback: 12)
    }

    private var runPaceMinutes: Double {
        manualRunSecondsPerKm > 0
            ? Double(manualRunSecondsPerKm) / 60
            : recentPace(for: .running, fallback: 6)
    }

    private func markRecent(_ route: TrainingRoute) {
        recents.markUsed(
            .route,
            itemID: route.id.uuidString,
            title: route.title,
            subtitle: String(format: "%.1f km", route.distanceKilometers),
            icon: "map.fill"
        )
    }

    private func durationText(kilometers: Double, paceMinutes: Double) -> String {
        let minutes = max(1, Int((kilometers * paceMinutes).rounded()))
        if minutes >= 60 {
            let hours = minutes / 60
            let remainder = minutes % 60
            return remainder == 0 ? "\(hours) t" : "\(hours) t \(remainder) min"
        }
        return "\(minutes) min"
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                heroHeader
                if !session.savedRoutes.isEmpty {
                    searchAndFilters
                    if sort == .nearest && !hasLocation { locationExplanation }
                    resultsHeader
                    if viewMode == .map && !visibleRoutes.isEmpty { overviewMap }
                }

                if session.savedRoutes.isEmpty {
                    emptyState
                } else if visibleRoutes.isEmpty {
                    filteredEmptyState
                } else {
                    ForEach(visibleRoutes, id: \.route.id) { entry in
                        if viewMode == .cards {
                            routeCard(entry)
                        } else {
                            compactRouteRow(entry)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 80)
            .frame(maxWidth: ATHLTHPlanDesign.maxContentWidth)
            .frame(maxWidth: .infinity)
        }
        .background(ATHLTHPlanDesign.warmCanvas.ignoresSafeArea())
        .navigationTitle(selectionTitle ?? tr("My routes", "Mine ruter"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await favorites.refresh()
            if sort == .nearest { locationStore.start() }
        }
        .onChange(of: sortPreference) { _, value in
            if value == SavedRouteSort.nearest.rawValue { locationStore.refresh() }
        }
        .onDisappear { locationStore.stop() }
        .sheet(isPresented: $showingCustomLength) { customLengthSheet }
        .fullScreenCover(item: $previewRoute) { route in
            SavedRouteFullscreenMap(route: route)
        }
        .alert("ATHLTH", isPresented: Binding(
            get: { watchMessage != nil || watchError != nil },
            set: { if !$0 { watchMessage = nil; watchError = nil } }
        )) {
            Button("OK", role: .cancel) { watchMessage = nil; watchError = nil }
        } message: {
            Text(watchError ?? watchMessage ?? "")
        }
    }

    private var heroHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("ATHLTH  /  " + tr("ROUTES", "RUTER"))
                    .font(.system(size: 10, weight: .bold))
                    .tracking(2.0)
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                Text(selectionTitle == nil ? tr("Find your next route", "Finn din neste rute") : tr("Choose a route", "Velg en rute"))
                    .font(.system(size: 27, weight: .semibold, design: .serif))
                    .foregroundStyle(ATHLTHPlanDesign.ink)
                Text(tr("\(session.savedRoutes.count) saved routes", "\(session.savedRoutes.count) lagrede ruter"))
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            }
            Spacer(minLength: 4)
            NavigationLink {
                RunRouteBuilderView()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(Color.white)
                    .frame(width: 48, height: 48)
                    .background(ATHLTHTheme.accentDeep, in: RoundedRectangle(cornerRadius: 16))
            }
            .accessibilityLabel(tr("Create route", "Opprett rute"))
        }
        .padding(.vertical, 8)
    }

    private var searchAndFilters: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                TextField(tr("Search routes or places", "Søk etter ruter eller steder"), text: $search)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.subheadline)
                if !search.isEmpty {
                    Button { search = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    }
                    .accessibilityLabel(tr("Clear search", "Tøm søk"))
                }
            }
            .padding(14)
            .background(ATHLTHPlanDesign.surface, in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(ATHLTHPlanDesign.outline))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(SavedRouteFilter.allCases) { option in
                        Button { visibilityPreference = option.rawValue } label: {
                            Label(option.title, systemImage: option.icon)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 13)
                                .frame(height: 36)
                                .foregroundStyle(filter == option ? Color.white : ATHLTHPlanDesign.ink)
                                .background(filter == option ? ATHLTHTheme.accentDeep : ATHLTHPlanDesign.warmSurface,
                                            in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(filter == option ? .isSelected : [])
                    }
                }
            }

            HStack(spacing: 10) {
                Menu {
                    ForEach(SavedRouteSort.allCases) { option in
                        Button {
                            sortPreference = option.rawValue
                        } label: {
                            if sort == option {
                                Label(option.title, systemImage: "checkmark")
                            } else {
                                Text(option.title)
                            }
                        }
                    }
                } label: {
                    filterControl(title: sort.title, icon: "arrow.up.arrow.down")
                }
                Menu {
                    ForEach(0..<6, id: \.self) { option in
                        Button {
                            lengthPreference = option
                        } label: {
                            Text(lengthLabel(option))
                        }
                    }
                    Divider()
                    Button {
                        showingCustomLength = true
                    } label: {
                        Label(tr("Custom range", "Egendefinert lengde"), systemImage: "slider.horizontal.3")
                    }
                } label: {
                    filterControl(title: lengthTitle, icon: "ruler")
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
                        .background(ATHLTHPlanDesign.warmSurface, in: RoundedRectangle(cornerRadius: 12))
                }
                .accessibilityLabel(tr("Change estimated running pace", "Endre estimert løpetempo"))
            }
        }
        .padding(16)
        .athlthPlanCard()
    }

    private func filterControl(title: String, icon: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
            Text(title).lineLimit(1)
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(ATHLTHPlanDesign.ink)
        .padding(.horizontal, 10)
        .frame(height: 40)
        .background(ATHLTHPlanDesign.warmSurface, in: RoundedRectangle(cornerRadius: 11))
    }

    private func lengthLabel(_ value: Int) -> String {
        switch value {
        case 1: return "< 3 km"
        case 2: return "3–5 km"
        case 3: return "5–10 km"
        case 4: return "10–20 km"
        case 5: return "20+ km"
        default: return tr("All lengths", "Alle lengder")
        }
    }

    private var locationExplanation: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "location.slash")
                .foregroundStyle(ATHLTHPlanDesign.accentInk)
            VStack(alignment: .leading, spacing: 5) {
                Text(locationStore.isUpdating
                    ? tr("Finding your position…", "Henter posisjonen din …")
                    : tr("Nearest needs location access", "Nærmest krever posisjonstilgang"))
                    .font(.subheadline.weight(.semibold))
                Text(tr("Showing newest first until your position is available. Distance is measured directly to the route's start, not driving distance.",
                        "Viser nyeste først til posisjonen er tilgjengelig. Avstand måles i luftlinje til rutens start, ikke kjøreavstand."))
                    .font(.caption)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                if !locationStore.isUpdating {
                    Button(tr("Try location again", "Prøv posisjon på nytt")) {
                        locationStore.start()
                    }
                    .font(.caption.weight(.semibold))
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ATHLTHPlanDesign.selectedSurface, in: RoundedRectangle(cornerRadius: 14))
    }

    private var resultsHeader: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(tr("\(visibleRoutes.count) routes", "\(visibleRoutes.count) ruter"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ATHLTHPlanDesign.ink)

            ATHLTHRouteBrowseModePicker(selection: viewModeBinding)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 3)
    }

    private func compactRouteRow(_ entry: PositionedSavedRoute) -> some View {
        let route = entry.route
        return HStack(spacing: 12) {
            NavigationLink {
                RouteDetailView(route: route)
            } label: {
                HStack(spacing: 12) {
                    RouteMapSnapshotThumbnail(route: route, height: 82)
                        .frame(width: 104, height: 82)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(route.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ATHLTHPlanDesign.ink)
                            .lineLimit(2)
                        Text(String(format: "%.1f km", route.distanceKilometers))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(ATHLTHPlanDesign.accentInk)
                        if let start = route.startName, !start.isEmpty {
                            Text(start)
                                .font(.caption2)
                                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                }
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded {
                markRecent(route)
            })

            if let onSelect {
                Button {
                    markRecent(route)
                    onSelect(route)
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                        .frame(width: 38, height: 42)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tr("Use route", "Bruk rute"))
            } else if settings.trainingDeviceProvider == .appleWatch {
                Button {
                    markRecent(route)
                    sendToWatch(route)
                } label: {
                    Image(systemName: "applewatch")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(ATHLTHPlanDesign.accentInk)
                        .frame(width: 32, height: 42)
                }
                .buttonStyle(.plain)
                .disabled(!watchConnection.isReady)
                .accessibilityLabel(tr("Send to Apple Watch", "Send til Apple Watch"))
            }
            LibraryFavoriteButton(
                kind: .route, itemID: route.id.uuidString,
                title: route.title,
                subtitle: String(format: "%.1f km", route.distanceKilometers),
                icon: "map.fill"
            )
        }
        .padding(11)
        .athlthPlanCard()
    }

    private var overviewMap: some View {
        VStack(alignment: .leading, spacing: 6) {
            SavedRouteOverviewMap(routes: Array(visibleRoutes.prefix(30).map(\.route))) { route in
                previewRoute = route
            }
            .frame(height: 270)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            if visibleRoutes.count > 30 {
                Text(tr("Map shows the first 30 filtered routes. All routes remain in the list.",
                        "Kartet viser de 30 første filtrerte rutene. Alle vises i listen."))
                    .font(.caption2)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            }
        }
    }

    private var customLengthSheet: some View {
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
                    lengthPreference = 6
                    showingCustomLength = false
                }
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 52)
                .foregroundStyle(.white)
                .background(ATHLTHTheme.accentDeep, in: RoundedRectangle(cornerRadius: 15))
            }
            .padding(22)
            .background(ATHLTHPlanDesign.warmCanvas.ignoresSafeArea())
            .navigationTitle(tr("Filter", "Filter"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(tr("Done", "Ferdig")) {
                        if maxLength < minLength { maxLength = minLength }
                        lengthPreference = 6
                        showingCustomLength = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func routeCard(_ entry: PositionedSavedRoute) -> some View {
        let route = entry.route
        return VStack(alignment: .leading, spacing: 13) {
            Button {
                markRecent(route)
                previewRoute = route
            } label: {
                ZStack(alignment: .bottomTrailing) {
                    RouteMapSnapshotThumbnail(route: route, height: 174)
                    Label(tr("Explore", "Utforsk"), systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(ATHLTHPlanDesign.ink)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(.regularMaterial, in: Capsule())
                        .padding(10)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(tr("Explore map for \(route.title)", "Utforsk kart for \(route.title)"))

            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(route.title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(ATHLTHPlanDesign.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if let start = route.startName, !start.isEmpty {
                        Text([start, route.endName].compactMap { $0 }.joined(separator: " → "))
                            .font(.caption)
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 4)
                Menu {
                    if settings.trainingDeviceProvider == .appleWatch {
                        Button { sendToWatch(route) } label: {
                            Label(tr("Send to Apple Watch", "Send til Apple Watch"), systemImage: "applewatch")
                        }
                        .disabled(!watchConnection.isReady)
                    }
                    NavigationLink {
                        ChallengeCreationView(preselectedRouteID: route.id)
                    } label: {
                        Label(tr("Create challenge", "Opprett utfordring"), systemImage: "trophy.fill")
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
                Label(visibilityLabel(route.visibility), systemImage: visibilityIcon(route.visibility))
                if let proximity = entry.startDistanceKilometers {
                    Label(String(format: "%.1f km %@", proximity, tr("to start", "til start")),
                          systemImage: "location")
                }
                if let climb = route.elevationGainMeters {
                    Label("\(Int(climb.rounded())) hm", systemImage: "mountain.2")
                }
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            .lineLimit(1)
            .minimumScaleFactor(0.8)

            HStack(spacing: 0) {
                metric(value: String(format: "%.1f km", route.distanceKilometers),
                       caption: tr("DISTANCE", "DISTANSE"), icon: "point.topleft.down.to.point.bottomright.curvepath")
                Divider().frame(height: 35)
                metric(value: durationText(kilometers: route.distanceKilometers, paceMinutes: walkPaceMinutes),
                       caption: tr("EST. WALK", "EST. GANGE"), icon: "figure.walk")
                Divider().frame(height: 35)
                metric(value: durationText(kilometers: route.distanceKilometers, paceMinutes: runPaceMinutes),
                       caption: tr("EST. RUN", "EST. LØPING"), icon: "figure.run")
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
                    RouteDetailView(route: route)
                } label: {
                    Label(tr("Details", "Detaljer"), systemImage: "arrow.up.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHPlanDesign.accentInk)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .simultaneousGesture(TapGesture().onEnded {
                    markRecent(route)
                })

                if let onSelect {
                    Button {
                        markRecent(route)
                        onSelect(route)
                    } label: {
                        Label(tr("Use route", "Bruk rute"), systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(ATHLTHTheme.accentDeep, in: RoundedRectangle(cornerRadius: 13))
                    }
                    .buttonStyle(.plain)
                } else if settings.trainingDeviceProvider == .appleWatch {
                    Button {
                        markRecent(route)
                        sendToWatch(route)
                    } label: {
                        Label(tr("Send to Watch", "Send til Watch"), systemImage: "applewatch")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(ATHLTHTheme.accentDeep, in: RoundedRectangle(cornerRadius: 13))
                    }
                    .buttonStyle(.plain)
                    .disabled(!watchConnection.isReady)
                    .opacity(watchConnection.isReady ? 1 : 0.45)
                }
            }
        }
        .padding(14)
        .athlthPlanCard()
    }

    private func metric(value: String, caption: String, icon: String) -> some View {
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

    private var filteredEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 28))
                .foregroundStyle(ATHLTHPlanDesign.accentInk)
            Text(tr("No matching routes", "Ingen ruter matcher"))
                .font(.headline)
            Text(tr("Try another search or filter.", "Prøv et annet søk eller filter."))
                .font(.subheadline)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            Button(tr("Clear filters", "Nullstill filtre")) {
                search = ""
                visibilityPreference = SavedRouteFilter.all.rawValue
                lengthPreference = 0
            }
            .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .athlthPlanCard()
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "map")
                .font(.system(size: 32))
                .foregroundStyle(ATHLTHPlanDesign.accentInk)
            Text(tr("Your routes start here", "Rutene dine starter her"))
                .font(.system(size: 23, weight: .semibold, design: .serif))
            Text(tr("Create a route to see its map, distance and estimated walking and running time.",
                    "Opprett en rute for å se kart, distanse og estimert tid for gange og løping."))
                .font(.subheadline)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                .multilineTextAlignment(.center)
            NavigationLink {
                RunRouteBuilderView()
            } label: {
                Label(tr("Create route", "Opprett rute"), systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(height: 46)
                    .background(ATHLTHTheme.accentDeep, in: Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(22)
        .athlthPlanCard()
    }

    private func visibilityLabel(_ visibility: ProfileVisibility) -> String {
        switch visibility {
        case .privateOnly: return tr("Private", "Privat")
        case .friends: return tr("Friends", "Venner")
        case .publicProfile: return tr("Public", "Offentlig")
        }
    }

    private func visibilityIcon(_ visibility: ProfileVisibility) -> String {
        switch visibility {
        case .privateOnly: return "lock.fill"
        case .friends: return "person.2.fill"
        case .publicProfile: return "globe.europe.africa.fill"
        }
    }

    private func sendToWatch(_ route: TrainingRoute) {
        guard watchConnection.isReady else { return }
        do {
            try watchConnection.sendRoute(route)
            watchMessage = tr("Route sent to Apple Watch.", "Ruten er sendt til Apple Watch.")
        } catch {
            watchError = error.localizedDescription
        }
    }
}

// The map/list toggle only draws a bounded number of routes at once so a
// growing library doesn't incur hundreds of MapKit overlays in one frame.
struct SavedRouteOverviewMap: View {
    let routes: [TrainingRoute]
    let onOpen: (TrainingRoute) -> Void

    var body: some View {
        Map(initialPosition: .automatic) {
            ForEach(routes) { route in
                let points = route.coordinates.sorted { $0.sequence < $1.sequence }.map(\.coordinate)
                if points.count >= 2 {
                    MapPolyline(coordinates: points)
                        .stroke(ATHLTHTheme.vitality, lineWidth: 3)
                    if let start = points.first {
                        Annotation(route.title, coordinate: start, anchor: .bottom) {
                            Button { onOpen(route) } label: {
                                Image(systemName: "figure.run")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 30, height: 30)
                                    .background(ATHLTHTheme.accentDeep, in: Circle())
                            }
                            .accessibilityLabel(route.title)
                        }
                    }
                }
            }
        }
    }
}

struct SavedRouteFullscreenMap: View {
    @Environment(\.dismiss) private var dismiss
    let route: TrainingRoute

    private var points: [CLLocationCoordinate2D] {
        route.coordinates.sorted { $0.sequence < $1.sequence }.map(\.coordinate)
    }

    private var region: MKCoordinateRegion {
        guard !points.isEmpty else {
            return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 63.43, longitude: 10.4),
                                      span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05))
        }
        let latitudes = points.map(\.latitude)
        let longitudes = points.map(\.longitude)
        let lowLat = latitudes.min() ?? points[0].latitude
        let highLat = latitudes.max() ?? points[0].latitude
        let lowLong = longitudes.min() ?? points[0].longitude
        let highLong = longitudes.max() ?? points[0].longitude
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (lowLat + highLat) / 2,
                                           longitude: (lowLong + highLong) / 2),
            span: MKCoordinateSpan(latitudeDelta: max(0.008, (highLat - lowLat) * 1.55),
                                   longitudeDelta: max(0.008, (highLong - lowLong) * 1.55))
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if points.count >= 2 {
                    Map(initialPosition: .region(region)) {
                        MapPolyline(coordinates: points)
                            .stroke(ATHLTHTheme.vitality, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        if let first = points.first {
                            Annotation("Start", coordinate: first) {
                                Image(systemName: "figure.run.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(ATHLTHTheme.accentDeep)
                                    .background(.white, in: Circle())
                            }
                        }
                        if let last = points.last {
                            Annotation("Mål", coordinate: last) {
                                Image(systemName: "flag.checkered.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(ATHLTHTheme.vitality)
                                    .background(.white, in: Circle())
                            }
                        }
                    }
                    .mapControls {
                        MapCompass()
                        MapScaleView()
                    }
                } else {
                    ContentUnavailableView("Kart ikke tilgjengelig", systemImage: "map",
                                           description: Text("Ruten mangler kartkoordinater."))
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text(route.title)
                        .font(.system(size: 23, weight: .semibold, design: .serif))
                        .foregroundStyle(ATHLTHPlanDesign.ink)
                    HStack(spacing: 16) {
                        Label(String(format: "%.1f km", route.distanceKilometers),
                              systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        if let climb = route.elevationGainMeters {
                            Label("\(Int(climb.rounded())) hm", systemImage: "mountain.2")
                        }
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    if let start = points.first {
                        Button {
                            let destination = MKMapItem(placemark: MKPlacemark(coordinate: start))
                            destination.name = route.startName ?? route.title
                            destination.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
                        } label: {
                            Label(ATHLTHLocalization.choose(english: "Directions to start", norwegian: "Veibeskrivelse til start"),
                                  systemImage: "location.north.line")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(ATHLTHPlanDesign.accentInk)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background(ATHLTHPlanDesign.warmCanvas)
            }
            .navigationTitle(ATHLTHLocalization.choose(english: "Route map", norwegian: "Rutekart"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(ATHLTHLocalization.choose(english: "Done", norwegian: "Ferdig")) {
                        dismiss()
                    }
                }
            }
        }
    }
}