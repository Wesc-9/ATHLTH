import MapKit
import SwiftUI

private enum SavedRouteSort:
    String,
    CaseIterable,
    Identifiable {
    case newest = "Newest"
    case shortest = "Shortest"
    case longest = "Longest"
    case name = "Name A–Z"

    var id: String { rawValue }
}

private enum SavedRouteFilter:
    String,
    CaseIterable,
    Identifiable {
    case all
    case favorites
    case privateOnly
    case friends
    case publicProfile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return ATHLTHLocalization.choose(
                english: "All",
                norwegian: "Alle"
            )
        case .favorites:
            return ATHLTHLocalization.choose(
                english: "Favorites",
                norwegian: "Favoritter"
            )
        case .privateOnly:
            return ATHLTHLocalization.choose(
                english: "Private",
                norwegian: "Privat"
            )
        case .friends:
            return ATHLTHLocalization.choose(
                english: "Friends",
                norwegian: "Venner"
            )
        case .publicProfile:
            return ATHLTHLocalization.choose(
                english: "Public",
                norwegian: "Offentlig"
            )
        }
    }

    var icon: String {
        switch self {
        case .all:
            return "line.3.horizontal.decrease.circle.fill"
        case .favorites:
            return "star.fill"
        case .privateOnly:
            return "lock.fill"
        case .friends:
            return "person.2.fill"
        case .publicProfile:
            return "globe.europe.africa.fill"
        }
    }
}

struct SavedRoutesView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var watchConnection: AppleWatchConnectionStore
    @EnvironmentObject private var favorites: LibraryFavoritesStore

    let selectionTitle: String?
    let onSelect: ((TrainingRoute) -> Void)?

    @State private var watchMessage: String?
    @State private var watchError: String?
    @State private var routeFilter:
        SavedRouteFilter = .all
    @State private var routeSort:
        SavedRouteSort = .newest
    @State private var lengthFilter = 0

    init(
        selectionTitle: String? = nil,
        onSelect: ((TrainingRoute) -> Void)? = nil
    ) {
        self.selectionTitle = selectionTitle
        self.onSelect = onSelect
    }

    private var visibleRoutes:
        [TrainingRoute] {
        session.savedRoutes
            .filter { route in
                let filterMatches: Bool

                switch routeFilter {
                case .all:
                    filterMatches = true
                case .favorites:
                    filterMatches =
                        favorites.isFavorite(
                            .route,
                            itemID:
                                route.id
                                    .uuidString
                        )
                case .privateOnly:
                    filterMatches =
                        route.visibility ==
                        .privateOnly
                case .friends:
                    filterMatches =
                        route.visibility ==
                        .friends
                case .publicProfile:
                    filterMatches =
                        route.visibility ==
                        .publicProfile
                }

                let lengthMatches:
                    Bool
                switch lengthFilter {
                case 1:
                    lengthMatches =
                        route
                            .distanceKilometers <
                        5
                case 2:
                    lengthMatches =
                        route
                            .distanceKilometers >=
                            5 &&
                        route
                            .distanceKilometers <
                            10
                case 3:
                    lengthMatches =
                        route
                            .distanceKilometers >=
                            10
                default:
                    lengthMatches = true
                }

                return filterMatches &&
                    lengthMatches
            }
            .sorted { left, right in
                switch routeSort {
                case .newest:
                    if left.createdAt !=
                        right.createdAt {
                        return left.createdAt >
                            right.createdAt
                    }
                case .shortest:
                    if left
                        .distanceKilometers !=
                        right
                            .distanceKilometers {
                        return left
                            .distanceKilometers <
                            right
                                .distanceKilometers
                    }
                case .longest:
                    if left
                        .distanceKilometers !=
                        right
                            .distanceKilometers {
                        return left
                            .distanceKilometers >
                            right
                                .distanceKilometers
                    }
                case .name:
                    break
                }

                return left.title
                    .localizedStandardCompare(
                        right.title
                    ) ==
                    .orderedAscending
            }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                routesHeader

                if !session
                    .savedRoutes.isEmpty {
                    routeFilters
                }

                if session.savedRoutes.isEmpty {
                    emptyState
                } else if visibleRoutes.isEmpty {
                    filteredEmptyState
                } else {
                    ForEach(visibleRoutes) { route in
                        routeCard(route)
                    }
                }
            }
            .padding()
            .padding(.bottom, 60)
        }
        .background(
            LinearGradient(
                colors: [
                    ATHLTHTheme.canvasTop,
                    ATHLTHTheme.canvasBottom
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .navigationTitle(selectionTitle ?? "Routes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    RunRouteBuilderView()
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Create route")
            }
        }
        .task {
            await favorites.refresh()
        }
        .alert(
            "ATHLTH",
            isPresented: Binding(
                get: { watchMessage != nil || watchError != nil },
                set: { presented in
                    if !presented {
                        watchMessage = nil
                        watchError = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                watchMessage = nil
                watchError = nil
            }
        } message: {
            Text(watchError ?? watchMessage ?? "")
        }
    }

    private var routesHeader: some View {
        ATHLTHCard {
            HStack(
                alignment: .center,
                spacing: 12
            ) {
                Image(
                    systemName: "map.fill"
                )
                .font(.headline)
                .foregroundStyle(
                    ATHLTHTheme
                        .accentDeep
                )
                .frame(
                    width: 38,
                    height: 38
                )
                .background(
                    ATHLTHTheme
                        .accentSoft,
                    in:
                        RoundedRectangle(
                            cornerRadius: 12,
                            style: .continuous
                        )
                )

                VStack(
                    alignment: .leading,
                    spacing: 2
                ) {
                    Text(
                        ATHLTHLocalization
                            .choose(
                                english:
                                    "My Routes",
                                norwegian:
                                    "Mine ruter"
                            )
                    )
                    .font(
                        .headline
                    )

                    Text(
                        ATHLTHLocalization
                            .format(
                                english:
                                    "%d saved routes",
                                norwegian:
                                    "%d lagrede ruter",
                                session
                                    .savedRoutes
                                    .count
                            )
                    )
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                    )
                }

                Spacer()

                NavigationLink {
                    RunRouteBuilderView()
                } label: {
                    Label(
                        ATHLTHLocalization
                            .choose(
                                english:
                                    "Create",
                                norwegian:
                                    "Opprett"
                            ),
                        systemImage: "plus"
                    )
                }
                .buttonStyle(
                    .borderedProminent
                )
                .controlSize(.small)
                .tint(
                    ATHLTHTheme.accent
                )
            }
        }
        .athlthLightweightCardChrome()
    }

    private var routeFilters:
        some View {
        ATHLTHCard {
            VStack(
                alignment: .leading,
                spacing: 12
            ) {
                ScrollView(
                    .horizontal,
                    showsIndicators: false
                ) {
                    HStack(spacing: 8) {
                        ForEach(
                            SavedRouteFilter
                                .allCases
                        ) { filter in
                            Button {
                                routeFilter =
                                    filter
                            } label: {
                                Label(
                                    filter.title,
                                    systemImage:
                                        filter.icon
                                )
                                .font(
                                    .caption
                                        .weight(
                                            .semibold
                                        )
                                )
                                .padding(
                                    .horizontal,
                                    11
                                )
                                .padding(
                                    .vertical,
                                    8
                                )
                                .foregroundStyle(
                                    routeFilter ==
                                        filter
                                        ? Color.white
                                        : ATHLTHTheme
                                            .accentDeep
                                )
                                .background(
                                    routeFilter ==
                                        filter
                                        ? ATHLTHTheme
                                            .accentDeep
                                        : ATHLTHTheme
                                            .surfaceStone,
                                    in: Capsule()
                                )
                            }
                            .buttonStyle(
                                .plain
                            )
                        }
                    }
                }

                HStack(spacing: 10) {
                    Menu {
                        Picker(
                            "Sort by",
                            selection:
                                $routeSort
                        ) {
                            ForEach(
                                SavedRouteSort
                                    .allCases
                            ) { option in
                                Text(
                                    option
                                        .rawValue
                                )
                                .tag(option)
                            }
                        }
                    } label: {
                        Label(
                            routeSort.rawValue,
                            systemImage:
                                "arrow.up.arrow.down"
                        )
                        .font(
                            .caption
                                .weight(
                                    .semibold
                                )
                        )
                    }

                    Spacer()

                    Menu {
                        Picker(
                            "Route length",
                            selection:
                                $lengthFilter
                        ) {
                            Text(
                                ATHLTHLocalization
                                    .choose(
                                        english:
                                            "Any length",
                                        norwegian:
                                            "Alle lengder"
                                    )
                            )
                            .tag(0)
                            Text("< 5 km")
                                .tag(1)
                            Text("5–10 km")
                                .tag(2)
                            Text("10+ km")
                                .tag(3)
                        }
                    } label: {
                        Label(
                            lengthFilterTitle,
                            systemImage:
                                "ruler"
                        )
                        .font(
                            .caption
                                .weight(
                                    .semibold
                                )
                        )
                    }
                }
                .foregroundStyle(
                    ATHLTHTheme
                        .accentDeep
                )
            }
        }
        .athlthLightweightCardChrome()
    }

    private var lengthFilterTitle:
        String {
        switch lengthFilter {
        case 1:
            return "< 5 km"
        case 2:
            return "5–10 km"
        case 3:
            return "10+ km"
        default:
            return ATHLTHLocalization
                .choose(
                    english:
                        "Any length",
                    norwegian:
                        "Alle lengder"
                )
        }
    }

    private var filteredEmptyState:
        some View {
        ATHLTHCard {
            HStack(spacing: 12) {
                Image(
                    systemName:
                        "line.3.horizontal.decrease.circle"
                )
                .font(.title2)
                .foregroundStyle(
                    ATHLTHTheme
                        .vitality
                )

                VStack(
                    alignment: .leading,
                    spacing: 3
                ) {
                    Text(
                        ATHLTHLocalization
                            .choose(
                                english:
                                    "No matching routes",
                                norwegian:
                                    "Ingen ruter matcher"
                            )
                    )
                    .font(
                        .headline
                    )

                    Text(
                        ATHLTHLocalization
                            .choose(
                                english:
                                    "Try another filter or route length.",
                                norwegian:
                                    "Prøv et annet filter eller en annen rutelengde."
                            )
                    )
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                    )
                }

                Spacer()
            }
        }
        .athlthLightweightCardChrome()
    }

    private var emptyState: some View {
        ATHLTHCard {
            VStack(spacing: 14) {
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(ATHLTHTheme.accent)
                    .frame(width: 70, height: 70)
                    .background(
                        ATHLTHTheme.accentSoft,
                        in: Circle()
                    )

                Text("Create your first route")
                    .font(.title3.weight(.bold))

                Text(
                    "Choose a start and finish, compare route alternatives and save the route for future runs or Apple Watch."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

                NavigationLink {
                    RunRouteBuilderView()
                } label: {
                    Label("Create Route", systemImage: "map.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(ATHLTHTheme.accent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
    }

    private func routeCard(
        _ route: TrainingRoute
    ) -> some View {
        ATHLTHCard {
            VStack(
                alignment: .leading,
                spacing: 10
            ) {
                if route.coordinates
                    .count >= 2 {
                    NavigationLink {
                        RouteDetailView(
                            route: route
                        )
                    } label: {
                        RouteMapSnapshotThumbnail(
                            route: route,
                            height: 102
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        ATHLTHLocalization
                            .format(
                                english:
                                    "Open %@",
                                norwegian:
                                    "Åpne %@",
                                route.title
                            )
                    )
                }

                HStack(
                    alignment: .top,
                    spacing: 10
                ) {
                    NavigationLink {
                        RouteDetailView(
                            route: route
                        )
                    } label: {
                        VStack(
                            alignment: .leading,
                            spacing: 5
                        ) {
                            HStack(
                                alignment:
                                    .firstTextBaseline,
                                spacing: 8
                            ) {
                                Text(
                                    route.title
                                )
                                .font(
                                    .headline
                                )
                                .foregroundStyle(
                                    ATHLTHTheme
                                        .primaryText
                                )
                                .lineLimit(2)

                                Spacer(
                                    minLength: 4
                                )

                                visibilityBadge(
                                    route.visibility
                                )
                            }

                            if let start =
                                    route.startName,
                               let end =
                                    route.endName {
                                Text(
                                    "\(start) → \(end)"
                                )
                                .font(.caption)
                                .foregroundStyle(
                                    ATHLTHTheme
                                        .mutedText
                                )
                                .lineLimit(1)
                            }

                            HStack(
                                spacing: 10
                            ) {
                                Label(
                                    String(
                                        format:
                                            "%.1f km",
                                        route
                                            .distanceKilometers
                                    ),
                                    systemImage:
                                        "figure.run"
                                )

                                if let elevation =
                                        route
                                            .elevationGainMeters {
                                    Label(
                                        "\(Int(elevation.rounded())) m",
                                        systemImage:
                                            "mountain.2.fill"
                                    )
                                }
                            }
                            .font(
                                .caption2
                                    .weight(
                                        .medium
                                    )
                            )
                            .foregroundStyle(
                                ATHLTHTheme
                                    .mutedText
                            )
                        }
                    }
                    .buttonStyle(.plain)

                    Menu {
                        if settings
                            .trainingDeviceProvider ==
                            .appleWatch {
                            Button {
                                sendToWatch(
                                    route
                                )
                            } label: {
                                Label(
                                    "Send to Apple Watch",
                                    systemImage:
                                        "applewatch"
                                )
                            }
                            .disabled(
                                !watchConnection
                                    .isReady
                            )
                        }

                        NavigationLink {
                            ChallengeCreationView(
                                preselectedRouteID:
                                    route.id
                            )
                        } label: {
                            Label(
                                "Create Challenge",
                                systemImage:
                                    "trophy.fill"
                            )
                        }
                    } label: {
                        Image(
                            systemName:
                                "ellipsis.circle"
                        )
                        .font(.title3)
                        .foregroundStyle(
                            ATHLTHTheme
                                .accentDeep
                        )
                    }
                }

                if let onSelect {
                    HStack {
                        Spacer()

                        Button {
                            onSelect(route)
                        } label: {
                            Label(
                                ATHLTHLocalization
                                    .choose(
                                        english:
                                            "Use route",
                                        norwegian:
                                            "Bruk rute"
                                    ),
                                systemImage:
                                    "checkmark.circle.fill"
                            )
                            .font(
                                .subheadline
                                    .weight(
                                        .semibold
                                    )
                            )
                        }
                        .buttonStyle(
                            .borderedProminent
                        )
                        .controlSize(.small)
                        .tint(
                            ATHLTHTheme
                                .accent
                        )
                    }
                } else if settings
                    .trainingDeviceProvider ==
                    .appleWatch {
                    Button {
                        sendToWatch(route)
                    } label: {
                        Label(
                            watchConnection
                                .isReady
                                ? "Send to Apple Watch"
                                : "Apple Watch unavailable",
                            systemImage:
                                "applewatch"
                        )
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(
                        !watchConnection
                            .isReady
                    )
                }
            }
        }
        .athlthLightweightCardChrome()
    }

    private func visibilityBadge(
        _ visibility:
            ProfileVisibility
    ) -> some View {
        Image(
            systemName:
                visibilityIcon(
                    visibility
                )
        )
        .font(
            .caption2
                .weight(.bold)
        )
        .foregroundStyle(
            visibilityTint(
                visibility
            )
        )
        .frame(
            width: 26,
            height: 26
        )
        .background(
            visibilityTint(
                visibility
            )
            .opacity(0.11),
            in: Circle()
        )
        .accessibilityLabel(
            visibilityLabel(
                visibility
            )
        )
    }

    private func visibilityTint(
        _ visibility:
            ProfileVisibility
    ) -> Color {
        switch visibility {
        case .privateOnly:
            return ATHLTHTheme
                .accentDeep
        case .friends:
            return ATHLTHTheme
                .recoveryBlue
        case .publicProfile:
            return ATHLTHTheme
                .vitality
        }
    }

    private func sendToWatch(_ route: TrainingRoute) {
        guard watchConnection.isReady else { return }

        do {
            try watchConnection.sendRoute(route)
            watchMessage = "Sent \(route.title) to Apple Watch."
        } catch {
            watchError = error.localizedDescription
        }
    }

    private func visibilityLabel(
        _ visibility: ProfileVisibility
    ) -> String {
        switch visibility {
        case .privateOnly:
            return "Only me"
        case .friends:
            return "Friends"
        case .publicProfile:
            return "Public"
        }
    }

    private func visibilityIcon(
        _ visibility: ProfileVisibility
    ) -> String {
        switch visibility {
        case .privateOnly:
            return "lock.fill"
        case .friends:
            return "person.2.fill"
        case .publicProfile:
            return "globe.europe.africa.fill"
        }
    }
}
