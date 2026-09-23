import MapKit
import SwiftUI

struct RunRouteBuilderView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var watchConnection: AppleWatchConnectionStore

    @StateObject private var startSearch = RunRouteLocationSearchModel()
    @StateObject private var endSearch = RunRouteLocationSearchModel()

    @State private var startItem: MKMapItem?
    @State private var endItem: MKMapItem?
    @State private var alternatives: [RunRouteAlternative] = []
    @State private var selectedAlternativeID: UUID?
    @State private var mapPosition: MapCameraPosition = .automatic

    @State private var title = ""
    @State private var visibility: ProfileVisibility = .privateOnly
    @State private var sendToWatchAfterSaving = false
    @State private var isCalculating = false
    @State private var errorMessage: String?
    @State private var savedMessage: String?

    private var selectedAlternative: RunRouteAlternative? {
        alternatives.first { $0.id == selectedAlternativeID }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                hero
                endpointsCard

                if isCalculating {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Building running route…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }

                if !alternatives.isEmpty {
                    routeMap
                    alternativesCard
                    routeDetailsCard
                    saveCard
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Create Running Route")
        .navigationBarTitleDisplayMode(.inline)
        .alert("ATHLTH", isPresented: Binding(
            get: { errorMessage != nil || savedMessage != nil },
            set: { presented in
                if !presented {
                    errorMessage = nil
                    savedMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {
                errorMessage = nil
                savedMessage = nil
            }
        } message: {
            Text(errorMessage ?? savedMessage ?? "")
        }
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [
                    ATHLTHTheme.accent.opacity(0.92),
                    Color.black.opacity(0.94)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            ATHLTHMarkShape()
                .fill(.white.opacity(0.10))
                .frame(width: 190, height: 140)
                .rotationEffect(.degrees(-12))
                .offset(x: 185, y: -38)

            VStack(alignment: .leading, spacing: 6) {
                Text("ATHLTH ROUTE BUILDER")
                    .font(.caption2.bold())
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.72))

                Text("Plan A → B")
                    .font(.system(size: 31, weight: .bold))
                    .foregroundStyle(.white)

                Text(routeBuilderSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.76))
            }
            .padding(20)
        }
        .frame(height: 205)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private var endpointsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Route")
                .font(.title3.bold())

            RunRouteSearchField(
                title: "From",
                icon: "circle.fill",
                model: startSearch,
                selectedItem: startItem
            ) { item in
                startItem = item
                startSearch.clear()
                inferTitle()
                Task { await calculateRoutesIfReady() }
            }

            HStack {
                Rectangle()
                    .fill(.secondary.opacity(0.25))
                    .frame(width: 2, height: 24)
                    .padding(.leading, 12)

                Spacer()

                Button {
                    let oldStart = startItem
                    startItem = endItem
                    endItem = oldStart
                    inferTitle()
                    Task { await calculateRoutesIfReady() }
                } label: {
                    Label("Swap", systemImage: "arrow.up.arrow.down")
                        .font(.caption.weight(.semibold))
                }
            }

            RunRouteSearchField(
                title: "To",
                icon: "mappin.circle.fill",
                model: endSearch,
                selectedItem: endItem
            ) { item in
                endItem = item
                endSearch.clear()
                inferTitle()
                Task { await calculateRoutesIfReady() }
            }

            Button {
                Task { await calculateRoutesIfReady(force: true) }
            } label: {
                Label("Build Route", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(ATHLTHTheme.accent)
            .disabled(startItem == nil || endItem == nil || isCalculating)

            Text("ATHLTH uses Apple Maps walking directions as the route network for running. You choose the final route before saving it.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .routeBuilderCard()
    }

    private var routeMap: some View {
        Group {
            if let selectedAlternative {
                Map(position: $mapPosition) {
                    if let startItem {
                        Marker(
                            startItem.name ?? "Start",
                            coordinate: startItem.placemark.coordinate
                        )
                        .tint(ATHLTHTheme.accent)
                    }

                    if let endItem {
                        Marker(
                            endItem.name ?? "Finish",
                            coordinate: endItem.placemark.coordinate
                        )
                        .tint(.red)
                    }

                    MapPolyline(coordinates: selectedAlternative.coordinates)
                        .stroke(ATHLTHTheme.accent, lineWidth: 6)
                }
                .frame(height: 310)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(alignment: .topLeading) {
                    Label(
                        String(format: "%.2f km", selectedAlternative.distanceMeters / 1_000),
                        systemImage: "figure.run"
                    )
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(12)
                }
            }
        }
    }

    private var alternativesCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text("Choose Route")
                    .font(.headline)
                Spacer()
                Text("\(alternatives.count) option\(alternatives.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(alternatives) { alternative in
                Button {
                    selectedAlternativeID = alternative.id
                    updateMapRegion(for: alternative)
                } label: {
                    HStack(spacing: 12) {
                        Image(
                            systemName: selectedAlternativeID == alternative.id
                                ? "checkmark.circle.fill"
                                : "circle"
                        )
                        .foregroundStyle(
                            selectedAlternativeID == alternative.id
                                ? ATHLTHTheme.accent
                                : .secondary
                        )

                        VStack(alignment: .leading, spacing: 3) {
                            Text(alternative.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)

                            Text(
                                String(
                                    format: "%.2f km · %@ walking-route estimate",
                                    alternative.distanceMeters / 1_000,
                                    alternative.expectedTravelTime.routeBuilderDuration
                                )
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .padding(12)
                    .background(
                        selectedAlternativeID == alternative.id
                            ? ATHLTHTheme.accent.opacity(0.07)
                            : Color.clear,
                        in: RoundedRectangle(cornerRadius: 15)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .routeBuilderCard()
    }

    private var routeDetailsCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("Route Details")
                .font(.headline)

            if let selectedAlternative {
                routeDetailRow(
                    icon: "point.topleft.down.to.point.bottomright.curvepath",
                    title: "Distance",
                    value: String(format: "%.2f km", selectedAlternative.distanceMeters / 1_000)
                )

                routeDetailRow(
                    icon: "location.fill",
                    title: "Start",
                    value: startDisplayName
                )

                routeDetailRow(
                    icon: "flag.checkered",
                    title: "Finish",
                    value: endDisplayName
                )

                routeDetailRow(
                    icon: settings.trainingDeviceProvider.systemImage,
                    title: settings.trainingDeviceProvider.title,
                    value: routeDeviceStatus
                )

                routeDetailRow(
                    icon: "trophy.fill",
                    title: "Challenges",
                    value: "Challenge-ready"
                )
            }
        }
        .padding()
        .routeBuilderCard()
    }

    private var saveCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Save Route")
                .font(.headline)

            TextField("Route name", text: $title)
                .textFieldStyle(.roundedBorder)

            Picker("Visibility", selection: $visibility) {
                Text("Private").tag(ProfileVisibility.privateOnly)
                Text("Friends").tag(ProfileVisibility.friends)
                Text("Public").tag(ProfileVisibility.publicProfile)
            }

            if visibility == .publicProfile {
                Label(
                    "Public routes are marked for future route discovery and public challenges.",
                    systemImage: "globe.europe.africa.fill"
                )
                .font(.caption)
                .foregroundStyle(ATHLTHTheme.accent)
            }

            if settings.trainingDeviceProvider == .appleWatch {
                Toggle(
                    "Send to Apple Watch after saving",
                    isOn: $sendToWatchAfterSaving
                )
                .disabled(!watchConnection.isReady)

                if !watchConnection.isReady {
                    Text(watchConnection.state.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if settings.trainingDeviceProvider == .garmin {
                Label(
                    "Garmin route sync is prepared and will unlock after authorization approval.",
                    systemImage: "watch.analog"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                Label(
                    "The route will stay available on this iPhone.",
                    systemImage: "iphone"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Button {
                saveRoute()
            } label: {
                Label("Save Running Route", systemImage: "square.and.arrow.down.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(ATHLTHTheme.accent)
            .disabled(
                selectedAlternative == nil ||
                title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
        }
        .padding()
        .routeBuilderCard()
    }

    private var startDisplayName: String {
        RunRouteLocationSearchModel.displayName(for: startItem)
    }

    private var endDisplayName: String {
        RunRouteLocationSearchModel.displayName(for: endItem)
    }

    @MainActor
    private func calculateRoutesIfReady(force: Bool = false) async {
        guard let startItem, let endItem else { return }

        if !force,
           !alternatives.isEmpty,
           alternatives.first?.startCoordinate.latitude == startItem.placemark.coordinate.latitude,
           alternatives.first?.endCoordinate.latitude == endItem.placemark.coordinate.latitude {
            return
        }

        isCalculating = true
        errorMessage = nil
        defer { isCalculating = false }

        do {
            let request = MKDirections.Request()
            request.source = startItem
            request.destination = endItem
            request.transportType = .walking
            request.requestsAlternateRoutes = true

            let response = try await MKDirections(request: request).calculate()

            let mapped = response.routes
                .prefix(3)
                .enumerated()
                .map { index, route in
                    RunRouteAlternative(
                        name: route.name.isEmpty
                            ? "Route \(index + 1)"
                            : route.name,
                        distanceMeters: route.distance,
                        expectedTravelTime: route.expectedTravelTime,
                        coordinates: route.polyline.routeBuilderCoordinates,
                        startCoordinate: startItem.placemark.coordinate,
                        endCoordinate: endItem.placemark.coordinate
                    )
                }
                .filter { $0.coordinates.count >= 2 }

            guard !mapped.isEmpty else {
                throw RunRouteBuilderError.noRoute
            }

            alternatives = mapped
            selectedAlternativeID = mapped.first?.id

            if let first = mapped.first {
                updateMapRegion(for: first)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func inferTitle() {
        guard title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              startItem != nil,
              endItem != nil
        else {
            return
        }

        title = "\(startDisplayName) → \(endDisplayName)"
    }

    private func updateMapRegion(for alternative: RunRouteAlternative) {
        guard !alternative.coordinates.isEmpty else { return }

        let lats = alternative.coordinates.map(\.latitude)
        let longs = alternative.coordinates.map(\.longitude)

        guard let minLat = lats.min(),
              let maxLat = lats.max(),
              let minLong = longs.min(),
              let maxLong = longs.max()
        else {
            return
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLong + maxLong) / 2
        )

        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.35, 0.01),
            longitudeDelta: max((maxLong - minLong) * 1.35, 0.01)
        )

        mapPosition = .region(
            MKCoordinateRegion(
                center: center,
                span: span
            )
        )
    }

    private func saveRoute() {
        guard let selectedAlternative else { return }

        let coordinates = selectedAlternative.coordinates.enumerated().map {
            RouteCoordinate(
                latitude: $0.element.latitude,
                longitude: $0.element.longitude,
                altitude: nil,
                sequence: $0.offset
            )
        }

        let route = TrainingRoute(
            id: UUID(),
            ownerID: session.profile.userID,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            visibility: visibility,
            coordinates: coordinates,
            distanceKilometers: selectedAlternative.distanceMeters / 1_000,
            elevationGainMeters: nil,
            importedFilename: nil,
            createdAt: Date(),
            startName: startDisplayName,
            endName: endDisplayName,
            expectedTravelTimeSeconds: selectedAlternative.expectedTravelTime,
            routeSource: "apple_maps_walking"
        )

        session.addImportedRoute(route)

        if sendToWatchAfterSaving &&
            settings.trainingDeviceProvider == .appleWatch &&
            watchConnection.isReady {
            do {
                try watchConnection.sendRoute(route)
                savedMessage = "Route saved and sent to Apple Watch."
            } catch {
                savedMessage = "Route saved. Apple Watch transfer failed: \(error.localizedDescription)"
            }
        } else {
            savedMessage = "Route saved to ATHLTH."
        }

        dismiss()
    }

    private var routeBuilderSubtitle: String {
        switch settings.trainingDeviceProvider {
        case .appleWatch:
            return "Search two places, choose a route, save it and optionally send it to Apple Watch."
        case .garmin:
            return "Search two places, choose a route and save it. Garmin route sync is prepared for later authorization."
        case .none:
            return "Search two places, choose a route and keep it available in ATHLTH on iPhone."
        }
    }

    private var routeDeviceStatus: String {
        switch settings.trainingDeviceProvider {
        case .appleWatch:
            return watchConnection.isReady ? "Route-ready" : "Setup required"
        case .garmin:
            return "Sync planned"
        case .none:
            return "iPhone route"
        }
    }

    private func routeDetailRow(
        icon: String,
        title: String,
        value: String
    ) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .foregroundStyle(ATHLTHTheme.accent)
                .frame(width: 28)

            Text(title)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }
}

private struct RunRouteSearchField: View {
    let title: String
    let icon: String
    @ObservedObject var model: RunRouteLocationSearchModel
    let selectedItem: MKMapItem?
    let onSelect: (MKMapItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(title == "From" ? ATHLTHTheme.accent : .red)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)

                    TextField(
                        selectedItem.map {
                            RunRouteLocationSearchModel.displayName(for: $0)
                        } ?? "Search address or place",
                        text: $model.query
                    )
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                }

                if !model.query.isEmpty {
                    Button {
                        model.clear()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12)
            .background(
                Color(.tertiarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 15)
            )

            if !model.suggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(model.suggestions.prefix(6)) { suggestion in
                        Button {
                            Task {
                                if let item = await model.resolve(suggestion) {
                                    onSelect(item)
                                }
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(suggestion.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)

                                if !suggestion.subtitle.isEmpty {
                                    Text(suggestion.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 9)
                            .padding(.horizontal, 12)
                        }
                        .buttonStyle(.plain)

                        if suggestion.id != model.suggestions.prefix(6).last?.id {
                            Divider()
                        }
                    }
                }
                .background(
                    Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 15)
                )
            }
        }
    }
}

final class RunRouteLocationSearchModel: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var query = "" {
        didSet {
            completer.queryFragment = query
        }
    }

    @Published private(set) var suggestions: [RunRouteLocationSuggestion] = []

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let mapped = completer.results.prefix(12).map {
            RunRouteLocationSuggestion(
                completion: $0,
                title: $0.title,
                subtitle: $0.subtitle
            )
        }

        DispatchQueue.main.async { [weak self] in
            self?.suggestions = mapped
        }
    }

    func completer(
        _ completer: MKLocalSearchCompleter,
        didFailWithError error: Error
    ) {
        DispatchQueue.main.async { [weak self] in
            self?.suggestions = []
        }
    }

    func clear() {
        query = ""
        suggestions = []
    }

    func resolve(_ suggestion: RunRouteLocationSuggestion) async -> MKMapItem? {
        let request = MKLocalSearch.Request(completion: suggestion.completion)

        return await withCheckedContinuation { continuation in
            MKLocalSearch(request: request).start { response, _ in
                continuation.resume(returning: response?.mapItems.first)
            }
        }
    }

    static func displayName(for item: MKMapItem?) -> String {
        guard let item else { return "—" }

        if let name = item.name, !name.isEmpty {
            return name
        }

        let placemark = item.placemark
        return [
            placemark.thoroughfare,
            placemark.locality
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }
}

struct RunRouteLocationSuggestion: Identifiable {
    let id = UUID()
    let completion: MKLocalSearchCompletion
    let title: String
    let subtitle: String
}

private struct RunRouteAlternative: Identifiable {
    let id = UUID()
    let name: String
    let distanceMeters: CLLocationDistance
    let expectedTravelTime: TimeInterval
    let coordinates: [CLLocationCoordinate2D]
    let startCoordinate: CLLocationCoordinate2D
    let endCoordinate: CLLocationCoordinate2D
}

private enum RunRouteBuilderError: LocalizedError {
    case noRoute

    var errorDescription: String? {
        switch self {
        case .noRoute:
            return "Apple Maps could not find a walkable route between those points."
        }
    }
}

private extension MKPolyline {
    var routeBuilderCoordinates: [CLLocationCoordinate2D] {
        var result = Array(
            repeating: CLLocationCoordinate2D(),
            count: pointCount
        )
        getCoordinates(
            &result,
            range: NSRange(location: 0, length: pointCount)
        )
        return result
    }
}

private extension TimeInterval {
    var routeBuilderDuration: String {
        let minutes = max(Int((self / 60).rounded()), 1)
        let hours = minutes / 60
        let remainder = minutes % 60

        if hours > 0 {
            return "\(hours)h \(remainder)m"
        }

        return "\(minutes) min"
    }
}

private extension View {
    func routeBuilderCard() -> some View {
        self
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)
            }
    }
}
