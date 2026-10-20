@preconcurrency import MapKit
import SwiftUI

struct RunRouteBuilderView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var watchConnection: AppleWatchConnectionStore
    @EnvironmentObject private var routeDiscovery: RouteDiscoveryStore

    @StateObject private var startSearch = RunRouteLocationSearchModel()
    @StateObject private var endSearch = RunRouteLocationSearchModel()
    @StateObject private var viaSearch = RunRouteLocationSearchModel()
    var initialSearchCenter: CLLocationCoordinate2D? = nil
    @StateObject private var searchLocation = HomeLocationStore()
    @State private var searchMapCenter: CLLocationCoordinate2D?

    @State private var startItem: MKMapItem?
    @State private var endItem: MKMapItem?
    @State private var viaPoints: [RunRouteViaPoint] = []
    @State private var showingViaSearch = false
    @State private var mapPointMode: RunRouteMapPointMode = .automatic
    @State private var mapUndoStack: [RunRouteMapSnapshot] = []
    @State private var mapInitiallyCentered = false
    @State private var routeCalculationID = UUID()
    @State private var returnOnSamePath = false
    @State private var alternatives: [RunRouteAlternative] = []
    @State private var selectedAlternativeID: UUID?
    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var lastCalculatedSignature = ""

    @State private var title = ""
    @State private var visibility: ProfileVisibility = .privateOnly
    @State private var isCalculating = false
    @State private var errorMessage: String?
    @State private var savedMessage: String?

    private var selectedAlternative: RunRouteAlternative? {
        guard let outbound = alternatives.first(where: { $0.id == selectedAlternativeID })
        else { return nil }
        guard returnOnSamePath, outbound.coordinates.count >= 2 else { return outbound }
        // A → B → A: retrace the *same verified walking path*, rather than
        // drawing an unvalidated straight line or inventing a new road.
        return RunRouteAlternative(
            name: outbound.name,
            distanceMeters: outbound.distanceMeters * 2,
            expectedTravelTime: outbound.expectedTravelTime * 2,
            coordinates: outbound.coordinates +
                Array(outbound.coordinates.dropLast().reversed()),
            startCoordinate: outbound.startCoordinate,
            endCoordinate: outbound.startCoordinate
        )
    }

    private var canOfferReturn: Bool {
        guard let start = startItem?.placemark.coordinate,
              let finish = endItem?.placemark.coordinate else { return false }
        return CLLocation(latitude: start.latitude, longitude: start.longitude)
            .distance(from: CLLocation(latitude: finish.latitude,
                                       longitude: finish.longitude)) > 50
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                hero
                routeNameCard
                endpointsCard
                // Map-first planning must work with no address selection.
                routeMap

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
                    if canOfferReturn {
                        outAndBackChoice
                    }
                    if alternatives.count > 1 {
                        alternativesCard
                    }
                    routeDetailsCard
                }
            }
            .padding()
            .padding(.bottom, 10)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if selectedAlternative != nil {
                saveRouteFooter
            }
        }
        .task {
            if let initialSearchCenter {
                centerMapInitially(on: initialSearchCenter)
            }
            searchLocation.start()
        }
        .onChange(of: searchLocation.location?.coordinate.latitude) { _, _ in
            if let coordinate = searchLocation.location?.coordinate {
                centerMapInitially(on: coordinate)
            }
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

    // Training Plan's ink, champagne accents, light panels and serif heading.
    private var hero: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(ATHLTHPlanDesign.accentInk)
                .frame(width: 52, height: 52)
                .background(
                    ATHLTHPlanDesign.selectedSurface,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 6) {
                Text(ATHLTHLocalization.choose(
                    english: "ATHLTH ROUTE PLANNER",
                    norwegian: "ATHLTH RUTEBYGGER"
                ))
                .font(.caption2.weight(.bold))
                .tracking(1.6)
                .foregroundStyle(ATHLTHPlanDesign.accentInk)

                HStack(spacing: 8) {
                    Text(ATHLTHLocalization.choose(
                        english: "Build your route",
                        norwegian: "Bygg ruten din"
                    ))
                    .font(.system(size: 25, weight: .semibold, design: .serif))
                    .foregroundStyle(ATHLTHPlanDesign.ink)
                    Text("A → B")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(ATHLTHPlanDesign.accentInk)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            ATHLTHPlanDesign.selectedSurface,
                            in: Capsule()
                        )
                }
                Text(routeBuilderSubtitle)
                    .font(.caption)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .routeBuilderCard()
    }

    private var effectiveRouteTitle:
        String {
        let custom =
            title.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        if !custom.isEmpty {
            return custom
        }

        if startItem != nil,
           endItem != nil {
            return returnOnSamePath
                ? "\(startDisplayName) → \(endDisplayName) → \(startDisplayName)"
                : "\(startDisplayName) → \(endDisplayName)"
        }

        return ATHLTHLocalization.choose(
            english: "Running route",
            norwegian: "Løperute"
        )
    }

    private var automaticRouteTitle:
        String? {
        guard startItem != nil,
              endItem != nil
        else {
            return nil
        }

        return "\(startDisplayName) → \(endDisplayName)"
    }

    private var routeNameCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "character.cursor.ibeam")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                    .frame(width: 34, height: 34)
                    .background(ATHLTHPlanDesign.selectedSurface,
                                in: RoundedRectangle(cornerRadius: 10))

                Text(ATHLTHLocalization.choose(
                    english: "Route name", norwegian: "Rutenavn"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHPlanDesign.ink)
                Text(ATHLTHLocalization.choose(
                    english: "Optional", norwegian: "Valgfritt"))
                    .font(.caption2)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                Spacer(minLength: 0)
                Menu {
                    Picker(ATHLTHLocalization.choose(
                        english: "Visibility", norwegian: "Synlighet"),
                        selection: $visibility) {
                        Label(ATHLTHLocalization.choose(
                            english: "Private", norwegian: "Privat"),
                            systemImage: "lock.fill").tag(ProfileVisibility.privateOnly)
                        Label(ATHLTHLocalization.choose(
                            english: "Friends", norwegian: "Venner"),
                            systemImage: "person.2").tag(ProfileVisibility.friends)
                        Label(ATHLTHLocalization.choose(
                            english: "Public", norwegian: "Offentlig"),
                            systemImage: "globe").tag(ProfileVisibility.publicProfile)
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: visibility == .privateOnly ? "lock.fill"
                              : visibility == .friends ? "person.2" : "globe")
                        Text(visibility == .privateOnly
                             ? ATHLTHLocalization.choose(english: "Private", norwegian: "Privat")
                             : visibility == .friends
                             ? ATHLTHLocalization.choose(english: "Friends", norwegian: "Venner")
                             : ATHLTHLocalization.choose(english: "Public", norwegian: "Offentlig"))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(ATHLTHPlanDesign.selectedSurface, in: Capsule())
                }
            }

            TextField(ATHLTHLocalization.choose(
                english: "Give the route a name", norwegian: "Gi ruten et navn"),
                text: $title)
                .textInputAutocapitalization(.words)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(ATHLTHPlanDesign.selectedSurface,
                            in: RoundedRectangle(cornerRadius: 13))

            if title.isEmpty, let automaticRouteTitle {
                Text(automaticRouteTitle)
                    .font(.caption2)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if visibility == .publicProfile {
                Text(ATHLTHLocalization.choose(
                    english: "Public routes may appear in Explore.",
                    norwegian: "Offentlige ruter kan vises i Utforsk."))
                    .font(.caption2)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            }
        }
        .padding(15)
        .routeBuilderCard()
    }

    private var endpointsCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(ATHLTHLocalization.choose(
                    english: "Route", norwegian: "Rute"))
                    .font(.headline.weight(.bold))
                    .foregroundStyle(ATHLTHPlanDesign.ink)
                Spacer()
                Button {
                    rememberMapState()
                    let oldStart = startItem
                    startItem = endItem
                    endItem = oldStart
                    viaPoints.reverse()
                    invalidateCalculatedRoute()
                    Task { await calculateRoutesIfReady(force: true) }
                } label: {
                    Label(ATHLTHLocalization.choose(
                        english: "Swap", norwegian: "Bytt"),
                        systemImage: "arrow.up.arrow.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHPlanDesign.ink)
                        .padding(.horizontal, 11)
                        .frame(height: 32)
                        .background(ATHLTHPlanDesign.selectedSurface, in: Capsule())
                }
                .buttonStyle(.plain)
            }

            RunRouteSearchField(
                title: "Start",
                icon: "circle.fill",
                tint: ATHLTHPlanDesign.accentInk,
                model: startSearch,
                selectedItem: startItem,
                referenceCoordinate: searchLocation.location?.coordinate
                    ?? searchMapCenter ?? initialSearchCenter
            ) { item in
                rememberMapState()
                startItem = item
                startSearch.clear()
                invalidateCalculatedRoute()
                Task { await calculateRoutesIfReady(force: true) }
            }

            routeConnector

            ForEach(Array(viaPoints.enumerated()), id: \.element.id) { index, point in
                viaPointRow(point, index: index)
                routeConnector
            }

            if showingViaSearch {
                RunRouteSearchField(
                    title: "Via",
                    icon: "mappin.and.ellipse",
                    tint: ATHLTHTheme.premiumGold,
                    model: viaSearch,
                    selectedItem: nil,
                    referenceCoordinate: startItem?.placemark.coordinate
                        ?? searchLocation.location?.coordinate
                        ?? searchMapCenter ?? initialSearchCenter
                ) { item in
                    addViaPoint(item)
                }
                routeConnector
            }

            RunRouteSearchField(
                title: ATHLTHLocalization.choose(
                    english: "Finish", norwegian: "Mål"),
                icon: "flag.checkered",
                tint: ATHLTHPlanDesign.accentInk,
                model: endSearch,
                selectedItem: endItem,
                referenceCoordinate: startItem?.placemark.coordinate
                    ?? searchLocation.location?.coordinate
                    ?? searchMapCenter ?? initialSearchCenter
            ) { item in
                rememberMapState()
                endItem = item
                endSearch.clear()
                invalidateCalculatedRoute()
                Task { await calculateRoutesIfReady(force: true) }
            }

            HStack(spacing: 9) {
                Button {
                    showingViaSearch.toggle()
                    if !showingViaSearch { viaSearch.clear() }
                } label: {
                    Label(showingViaSearch
                          ? ATHLTHLocalization.choose(english: "Done", norwegian: "Ferdig")
                          : ATHLTHLocalization.choose(english: "Via point", norwegian: "Via-punkt"),
                          systemImage: showingViaSearch ? "checkmark" : "plus")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHPlanDesign.accentInk)
                        .padding(.horizontal, 11)
                        .frame(height: 35)
                        .background(ATHLTHPlanDesign.selectedSurface, in: Capsule())
                }
                .buttonStyle(.plain)
                Spacer()
                if startItem != nil && endItem != nil {
                    Button {
                        Task { await calculateRoutesIfReady(force: true) }
                    } label: {
                        Label(selectedAlternative == nil
                            ? ATHLTHLocalization.choose(english: "Build route", norwegian: "Bygg rute")
                            : ATHLTHLocalization.choose(english: "Update route", norwegian: "Oppdater rute"),
                            systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .frame(height: 35)
                            .background(ATHLTHPlanDesign.accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isCalculating)
                }
            }
            .padding(.top, 2)
        }
        .padding(15)
        .routeBuilderCard()
    }

    private var routeMap: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: "map.fill")
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                    .frame(width: 33, height: 33)
                    .background(ATHLTHPlanDesign.selectedSurface,
                                in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 3) {
                    Text(ATHLTHLocalization.choose(
                        english: "Build on the map", norwegian: "Tegn ruten i kartet"
                    ))
                    .font(.headline)
                    .foregroundStyle(ATHLTHPlanDesign.ink)
                    Text(mapInstruction)
                        .font(.caption)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                }
                Spacer(minLength: 0)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    modeButton(.automatic,
                        text: ATHLTHLocalization.choose(english: "Automatic", norwegian: "Automatisk"),
                        icon: "hand.tap")
                    modeButton(.start, text: "Start", icon: "circle.fill")
                    modeButton(.finish,
                        text: ATHLTHLocalization.choose(english: "Finish", norwegian: "Mål"),
                        icon: "flag.checkered")
                    modeButton(.via, text: "Via",
                               icon: "point.3.connected.trianglepath.dotted")
                }
            }

            MapReader { proxy in
                Map(position: $mapPosition) {
                    if let route = selectedAlternative,
                       route.coordinates.count >= 2 {
                        MapPolyline(coordinates: route.coordinates)
                            .stroke(ATHLTHTheme.vitality, lineWidth: 5)
                    }
                    if let startItem {
                        Annotation("Start", coordinate: startItem.placemark.coordinate) {
                            Image(systemName: "figure.run")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(ATHLTHPlanDesign.accentInk, in: Circle())
                                .overlay(Circle().stroke(.white, lineWidth: 2))
                        }
                    }
                    ForEach(Array(viaPoints.enumerated()), id: \.element.id) { index, point in
                        Annotation("Via \(index + 1)", coordinate: point.item.placemark.coordinate) {
                            Text("\(index + 1)")
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                                .frame(width: 27, height: 27)
                                .background(ATHLTHTheme.premiumGold, in: Circle())
                                .overlay(Circle().stroke(.white, lineWidth: 2))
                        }
                    }
                    if let endItem {
                        Annotation("Mål", coordinate: endItem.placemark.coordinate) {
                            Image(systemName: "flag.checkered")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(Color.red, in: Circle())
                                .overlay(Circle().stroke(.white, lineWidth: 2))
                        }
                    }
                }
                .mapStyle(.standard(elevation: .realistic))
                .mapControls {
                    MapCompass()
                    MapScaleView()
                }
                .onMapCameraChange(frequency: .onEnd) { context in
                    searchMapCenter = context.region.center
                }
                .onTapGesture { point in
                    guard let coordinate = proxy.convert(point, from: .local),
                          CLLocationCoordinate2DIsValid(coordinate) else { return }
                    handleMapTap(at: coordinate)
                }
            }
            .frame(height: 345)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20)
                .stroke(ATHLTHPlanDesign.warmDivider, lineWidth: 1))
            .overlay(alignment: .topLeading) {
                if let route = selectedAlternative {
                    Label(String(format: "%.2f km", route.distanceMeters / 1_000),
                          systemImage: "figure.run")
                        .font(.caption.bold())
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                        .padding(12)
                }
            }
            .overlay(alignment: .bottom) {
                if !isCalculating && selectedAlternative == nil {
                    Text(mapInstruction)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHPlanDesign.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                        .allowsHitTesting(false)
                }
            }

            HStack(spacing: 8) {
                Button {
                    undoMapEdit()
                } label: {
                    Label(ATHLTHLocalization.choose(english: "Undo", norwegian: "Angre"),
                          systemImage: "arrow.uturn.backward")
                }
                .disabled(mapUndoStack.isEmpty)

                Button {
                    clearMapPoints()
                } label: {
                    Label(ATHLTHLocalization.choose(english: "Clear", norwegian: "Nullstill"),
                          systemImage: "trash")
                }
                .disabled(startItem == nil && endItem == nil && viaPoints.isEmpty)
                Spacer(minLength: 0)
                if let coordinate = searchLocation.location?.coordinate,
                   CLLocationCoordinate2DIsValid(coordinate) {
                    Button {
                        rememberMapState()
                        startItem = mapItem(coordinate, name: ATHLTHLocalization.choose(
                            english: "My position", norwegian: "Min posisjon"))
                        startSearch.clear()
                        invalidateCalculatedRoute()
                        Task { await calculateRoutesIfReady(force: true) }
                    } label: {
                        Label(ATHLTHLocalization.choose(
                            english: "My location", norwegian: "Min posisjon"),
                              systemImage: "location.fill")
                    }
                }
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.bordered)
            .tint(ATHLTHPlanDesign.accentInk)
        }
        .padding(15)
        .routeBuilderCard()
    }

    private var mapInstruction: String {
        switch mapPointMode {
        case .automatic:
            if startItem == nil {
                return ATHLTHLocalization.choose(
                    english: "Tap the map to choose a starting point",
                    norwegian: "Trykk i kartet for å velge startpunkt")
            }
            if endItem == nil {
                return ATHLTHLocalization.choose(
                    english: "Tap the map to choose a finish",
                    norwegian: "Trykk i kartet for å velge mål")
            }
            return ATHLTHLocalization.choose(
                english: "Tap the map to add a via point",
                norwegian: "Trykk i kartet for å legge til et via-punkt")
        case .start:
            return ATHLTHLocalization.choose(english: "Tap for start", norwegian: "Trykk for startpunkt")
        case .finish:
            return ATHLTHLocalization.choose(english: "Tap for finish", norwegian: "Trykk for mål")
        case .via:
            return ATHLTHLocalization.choose(english: "Tap for via point", norwegian: "Trykk for via-punkt")
        }
    }

    private func modeButton(
        _ mode: RunRouteMapPointMode, text: String, icon: String
    ) -> some View {
        Button { mapPointMode = mode } label: {
            Label(text, systemImage: icon)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 11)
                .frame(height: 36)
                .foregroundStyle(mapPointMode == mode ? Color.white : ATHLTHPlanDesign.ink)
                .background(mapPointMode == mode
                    ? ATHLTHPlanDesign.accentInk : ATHLTHPlanDesign.warmSurface,
                    in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(mapPointMode == mode ? .isSelected : [])
    }

    private func centerMapInitially(on coordinate: CLLocationCoordinate2D) {
        guard !mapInitiallyCentered, CLLocationCoordinate2DIsValid(coordinate)
        else { return }
        mapInitiallyCentered = true
        mapPosition = .region(MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.025, longitudeDelta: 0.025)
        ))
    }

    private func rememberMapState() {
        mapUndoStack.append(RunRouteMapSnapshot(
            start: startItem, finish: endItem, via: viaPoints))
        if mapUndoStack.count > 30 { mapUndoStack.removeFirst() }
    }

    private func invalidateCalculatedRoute() {
        routeCalculationID = UUID()
        lastCalculatedSignature = ""
        alternatives = []
        selectedAlternativeID = nil
        isCalculating = false
        returnOnSamePath = false
        errorMessage = nil
    }

    private func mapItem(_ coordinate: CLLocationCoordinate2D, name: String) -> MKMapItem {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = name
        return item
    }

    private func handleMapTap(at coordinate: CLLocationCoordinate2D) {
        let action = RunRouteMapPointMode.resolve(
            mode: mapPointMode, hasStart: startItem != nil, hasFinish: endItem != nil)
        if action == .via && (startItem == nil || endItem == nil) {
            errorMessage = ATHLTHLocalization.choose(
                english: "Choose start and finish before adding via points.",
                norwegian: "Velg start og mål før du legger til via-punkter.")
            return
        }
        rememberMapState()
        switch action {
        case .start:
            startItem = mapItem(coordinate, name:
                ATHLTHLocalization.choose(english: "Map start", norwegian: "Start fra kart"))
            startSearch.clear()
        case .finish:
            endItem = mapItem(coordinate, name:
                ATHLTHLocalization.choose(english: "Map finish", norwegian: "Mål fra kart"))
            endSearch.clear()
        case .via:
            viaPoints.append(RunRouteViaPoint(
                item: mapItem(coordinate, name: "Via \(viaPoints.count + 1)")))
        case .automatic:
            break
        }
        invalidateCalculatedRoute()
        Task { await calculateRoutesIfReady(force: true) }
    }

    private func undoMapEdit() {
        guard let previous = mapUndoStack.popLast() else { return }
        startItem = previous.start
        endItem = previous.finish
        viaPoints = previous.via
        startSearch.clear()
        endSearch.clear()
        viaSearch.clear()
        invalidateCalculatedRoute()
        Task { await calculateRoutesIfReady(force: true) }
    }

    private func clearMapPoints() {
        guard startItem != nil || endItem != nil || !viaPoints.isEmpty else { return }
        rememberMapState()
        startItem = nil
        endItem = nil
        viaPoints = []
        startSearch.clear()
        endSearch.clear()
        viaSearch.clear()
        mapPointMode = .automatic
        invalidateCalculatedRoute()
    }

    private var outAndBackChoice: some View {
        Toggle(isOn: $returnOnSamePath) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.uturn.backward")
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                    .frame(width: 35, height: 35)
                    .background(
                        ATHLTHPlanDesign.selectedSurface,
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                VStack(alignment: .leading, spacing: 3) {
                    Text(ATHLTHLocalization.choose(
                        english: "Run back to start", norwegian: "Løp tilbake til start"
                    ))
                    .font(.subheadline.weight(.semibold))
                    Text(ATHLTHLocalization.choose(
                        english: "Retrace the same route after reaching B.",
                        norwegian: "Følg den samme ruten tilbake etter punkt B."
                    ))
                    .font(.caption)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                }
            }
        }
        .tint(ATHLTHPlanDesign.accentInk)
        .padding(14)
        .routeBuilderCard()
        .onChange(of: returnOnSamePath) { _, _ in
            if let selectedAlternative {
                updateMapRegion(for: selectedAlternative)
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
        VStack(alignment: .leading, spacing: 12) {
            Text(ATHLTHLocalization.choose(
                english: "Route overview", norwegian: "Ruteoversikt"))
                .font(.headline)
                .foregroundStyle(ATHLTHPlanDesign.ink)

            if let route = selectedAlternative {
                HStack(spacing: 8) {
                    routeMetric(
                        icon: "point.topleft.down.to.point.bottomright.curvepath",
                        value: String(format: "%.2f km",
                                      route.distanceMeters / 1_000),
                        label: ATHLTHLocalization.choose(
                            english: "Distance", norwegian: "Distanse")
                    )
                    routeMetric(
                        icon: "clock",
                        value: "\(max(1, Int(ceil(route.distanceMeters / 1_000 * 6)))) min",
                        label: ATHLTHLocalization.choose(
                            english: "Running time", norwegian: "Løpetid")
                    )
                    routeMetric(
                        icon: "mappin.and.ellipse",
                        value: "\(viaPoints.count)",
                        label: "Via"
                    )
                }
                Label(ATHLTHLocalization.choose(
                    english: "Running time at 6:00 min/km; Apple Maps uses walkable paths.",
                    norwegian: "Løpetid ved 6:00 min/km. Apple Maps beregner gangbare traséer."),
                    systemImage: "info.circle")
                    .font(.caption2)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(15)
        .routeBuilderCard()
    }

    private func routeMetric(
        icon: String, value: String, label: String
    ) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ATHLTHPlanDesign.accentInk)
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .foregroundStyle(ATHLTHPlanDesign.ink)
            Text(label)
                .font(.caption2)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
        }
        .frame(maxWidth: .infinity, minHeight: 76)
        .padding(.vertical, 5)
        .background(ATHLTHPlanDesign.selectedSurface,
                    in: RoundedRectangle(cornerRadius: 14))
    }

    private var saveRouteFooter: some View {
        VStack(spacing: 0) {
            Divider().overlay(ATHLTHPlanDesign.warmDivider)
            Button(action: saveRoute) {
                Label(
                    ATHLTHLocalization.choose(
                        english: "Save Running Route",
                        norwegian: "Lagre løperute"
                    ),
                    systemImage: "square.and.arrow.down.fill"
                )
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(
                    ATHLTHPlanDesign.accent,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 8)
        }
        .background(ATHLTHPlanDesign.canvas)
    }

    private var startDisplayName: String {
        RunRouteLocationSearchModel.displayName(for: startItem)
    }

    private var endDisplayName: String {
        RunRouteLocationSearchModel.displayName(for: endItem)
    }

    @MainActor
    private func calculateRoutesIfReady(
        force: Bool = false
    ) async {
        guard let startItem,
              let endItem
        else {
            return
        }

        let signature = routeSignature

        if !force,
           !alternatives.isEmpty,
           signature == lastCalculatedSignature {
            return
        }

        let calculationID = UUID()
        routeCalculationID = calculationID
        isCalculating = true
        errorMessage = nil
        defer {
            if routeCalculationID == calculationID { isCalculating = false }
        }

        do {
            let mapped: [RunRouteAlternative]

            if viaPoints.isEmpty {
                let request = MKDirections.Request()
                request.source = startItem
                request.destination = endItem
                request.transportType = .walking
                request.requestsAlternateRoutes = true

                let response =
                    try await MKDirections(
                        request: request
                    )
                    .calculate()

                mapped = response.routes
                    .prefix(3)
                    .enumerated()
                    .map { index, route in
                        RunRouteAlternative(
                            name: route.name.isEmpty
                                ? "Route \(index + 1)"
                                : route.name,
                            distanceMeters: route.distance,
                            expectedTravelTime:
                                route.expectedTravelTime,
                            coordinates:
                                route.polyline
                                    .routeBuilderCoordinates,
                            startCoordinate:
                                startItem.placemark.coordinate,
                            endCoordinate:
                                endItem.placemark.coordinate
                        )
                    }
                    .filter {
                        $0.coordinates.count >= 2
                    }
            } else {
                mapped = [
                    try await calculateRouteThroughViaPoints(
                        start: startItem,
                        finish: endItem
                    )
                ]
            }

            // Stale MapKit requests must not overwrite newer point selections.
            guard routeCalculationID == calculationID,
                  signature == routeSignature else { return }
            guard !mapped.isEmpty else { throw RunRouteBuilderError.noRoute }

            alternatives = mapped
            selectedAlternativeID = mapped.first?.id
            lastCalculatedSignature = signature

            if let first = mapped.first {
                updateMapRegion(for: first)
            }
        } catch {
            if routeCalculationID == calculationID {
                alternatives = []
                selectedAlternativeID = nil
                errorMessage = error.localizedDescription
            }
        }
    }

    private var routeConnector: some View {
        Rectangle()
            .fill(.secondary.opacity(0.22))
            .frame(width: 2, height: 10)
            .padding(.leading, 19)
    }

    private func viaPointRow(
        _ point: RunRouteViaPoint,
        index: Int
    ) -> some View {
        HStack(spacing: 10) {
            Text("\(index + 1)")
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(
                    ATHLTHTheme.premiumGold,
                    in: Circle()
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("Via \(index + 1)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(viaDisplayName(point))
                    .font(.subheadline)
                    .lineLimit(1)
            }

            Spacer()

            if viaPoints.count > 1 {
                Button {
                    moveViaPoint(
                        from: index,
                        offset: -1
                    )
                } label: {
                    Image(systemName: "chevron.up")
                }
                .disabled(index == 0)

                Button {
                    moveViaPoint(
                        from: index,
                        offset: 1
                    )
                } label: {
                    Image(systemName: "chevron.down")
                }
                .disabled(
                    index == viaPoints.count - 1
                )
            }

            Button(role: .destructive) {
                removeViaPoint(point.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .padding(12)
        .background(
            ATHLTHTheme.surfaceStone.opacity(0.78),
            in: RoundedRectangle(
                cornerRadius: 15,
                style: .continuous
            )
        )
    }

    private func addViaPoint(
        _ item: MKMapItem
    ) {
        rememberMapState()
        viaPoints.append(RunRouteViaPoint(item: item))
        invalidateCalculatedRoute()
        viaSearch.clear()
        showingViaSearch = false

        Task {
            await calculateRoutesIfReady(force: true)
        }
    }

    private func addViaPoint(
        at coordinate: CLLocationCoordinate2D
    ) {
        let placemark = MKPlacemark(
            coordinate: coordinate
        )
        let item = MKMapItem(placemark: placemark)
        item.name = "Map point \(viaPoints.count + 1)"
        addViaPoint(item)
    }

    private func removeViaPoint(
        _ id: UUID
    ) {
        rememberMapState()
        viaPoints.removeAll { $0.id == id }
        invalidateCalculatedRoute()

        Task {
            await calculateRoutesIfReady(force: true)
        }
    }

    private func moveViaPoint(
        from index: Int,
        offset: Int
    ) {
        let destination = index + offset

        guard viaPoints.indices.contains(index),
              viaPoints.indices.contains(destination)
        else {
            return
        }

        rememberMapState()
        viaPoints.swapAt(index, destination)
        invalidateCalculatedRoute()

        Task {
            await calculateRoutesIfReady(force: true)
        }
    }

    private func viaDisplayName(
        _ point: RunRouteViaPoint
    ) -> String {
        RunRouteLocationSearchModel.displayName(
            for: point.item
        )
    }

    private var routeSignature: String {
        var items: [MKMapItem] = []

        if let startItem {
            items.append(startItem)
        }

        items.append(contentsOf: viaPoints.map(\.item))

        if let endItem {
            items.append(endItem)
        }

        return items
            .map { item in
                let coordinate =
                    item.placemark.coordinate
                return String(
                    format: "%.6f,%.6f",
                    coordinate.latitude,
                    coordinate.longitude
                )
            }
            .joined(separator: "|")
    }

    @MainActor
    private func calculateRouteThroughViaPoints(
        start: MKMapItem,
        finish: MKMapItem
    ) async throws -> RunRouteAlternative {
        let points =
            [start] +
            viaPoints.map(\.item) +
            [finish]

        var coordinates:
            [CLLocationCoordinate2D] = []
        var distance: CLLocationDistance = 0
        var travelTime: TimeInterval = 0

        for index in 0..<(points.count - 1) {
            let request = MKDirections.Request()
            request.source = points[index]
            request.destination = points[index + 1]
            request.transportType = .walking
            request.requestsAlternateRoutes = false

            let response =
                try await MKDirections(
                    request: request
                )
                .calculate()

            guard let route = response.routes.first
            else {
                throw RunRouteBuilderError.noRoute
            }

            let segment =
                route.polyline.routeBuilderCoordinates

            guard segment.count >= 2 else {
                throw RunRouteBuilderError.noRoute
            }

            if coordinates.isEmpty {
                coordinates.append(
                    contentsOf: segment
                )
            } else {
                coordinates.append(
                    contentsOf: segment.dropFirst()
                )
            }

            distance += route.distance
            travelTime += route.expectedTravelTime
        }

        return RunRouteAlternative(
            name: viaPoints.count == 1
                ? "Via route"
                : "Via route · \(viaPoints.count) points",
            distanceMeters: distance,
            expectedTravelTime: travelTime,
            coordinates: coordinates,
            startCoordinate:
                start.placemark.coordinate,
            endCoordinate:
                finish.placemark.coordinate
        )
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
            title: effectiveRouteTitle,
            visibility: visibility,
            coordinates: coordinates,
            distanceKilometers: selectedAlternative.distanceMeters / 1_000,
            elevationGainMeters: nil,
            importedFilename: nil,
            createdAt: Date(),
            startName: startDisplayName,
            endName: returnOnSamePath ? startDisplayName : endDisplayName,
            expectedTravelTimeSeconds: selectedAlternative.expectedTravelTime,
            routeSource: returnOnSamePath
                ? "apple_maps_walking_out_and_back" : "apple_maps_walking"
        )

        session.addImportedRoute(route)

        Task {
            await routeDiscovery.publish(route)
        }

        savedMessage = ATHLTHLocalization.choose(
            english: "Route saved to ATHLTH.",
            norwegian: "Ruten er lagret i ATHLTH."
        )

        dismiss()
    }

    private var routeBuilderSubtitle: String {
        ATHLTHLocalization.choose(
            english: "Search by address or tap the map to shape your running route.",
            norwegian: "Søk etter adresser, eller trykk i kartet for å bygge løperuten."
        )
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
    let tint: Color
    @ObservedObject var model: RunRouteLocationSearchModel
    let selectedItem: MKMapItem?
    let referenceCoordinate: CLLocationCoordinate2D?
    let onSelect: (MKMapItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(tint)
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
                ATHLTHTheme.surfaceStone.opacity(0.78),
                in: RoundedRectangle(
                    cornerRadius: 15,
                    style: .continuous
                )
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
                            HStack(spacing: 8) {
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
                                Spacer(minLength: 6)
                                if let distance = model.distanceLabel(for: suggestion) {
                                    Text(distance)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(ATHLTHPlanDesign.accentInk)
                                        .monospacedDigit()
                                        .fixedSize(horizontal: true, vertical: false)
                                        .accessibilityLabel(
                                            ATHLTHLocalization.choose(
                                                english: "Distance \(distance)",
                                                norwegian: "Avstand \(distance)"
                                            )
                                        )
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
                    ATHLTHTheme.card,
                    in: RoundedRectangle(
                        cornerRadius: 15,
                        style: .continuous
                    )
                )
            }
        }
        .onAppear {
            model.setReferenceCoordinate(referenceCoordinate)
        }
        .onChange(of: referenceCoordinate?.latitude) { _, _ in
            model.setReferenceCoordinate(referenceCoordinate)
        }
        .onChange(of: referenceCoordinate?.longitude) { _, _ in
            model.setReferenceCoordinate(referenceCoordinate)
        }
    }
}

private struct RunRouteResolvedLocation: Sendable {
    let latitude: Double
    let longitude: Double
    let name: String
}

@MainActor
final class RunRouteLocationSearchModel:
    NSObject,
    ObservableObject,
    MKLocalSearchCompleterDelegate
{
    @Published var query = "" {
        didSet {
            distanceTask?.cancel()
            suggestionDistances = [:]
            completer.queryFragment = query
        }
    }

    @Published private(set) var suggestions:
        [RunRouteLocationSuggestion] = []
    @Published private(set) var suggestionDistances: [String: CLLocationDistance] = [:]

    private let completer = MKLocalSearchCompleter()
    private var referenceCoordinate: CLLocationCoordinate2D?
    private var distanceTask: Task<Void, Never>?

    func setReferenceCoordinate(_ coordinate: CLLocationCoordinate2D?) {
        if let coordinate, let current = referenceCoordinate {
            let movement = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                .distance(from: CLLocation(latitude: current.latitude, longitude: current.longitude))
            if movement < 25 { return }
        } else if coordinate == nil && referenceCoordinate == nil {
            return
        }
        referenceCoordinate = coordinate
        refreshSuggestionDistances()
    }

    func distanceLabel(for suggestion: RunRouteLocationSuggestion) -> String? {
        guard let meters = suggestionDistances[suggestion.distanceKey] else { return nil }
        if meters < 1_000 {
            return "\(Int((meters / 10).rounded() * 10)) m"
        }
        return String(format: "%.1f km", meters / 1_000)
    }

    private func refreshSuggestionDistances() {
        distanceTask?.cancel()
        suggestionDistances = [:]
        guard let referenceCoordinate else { return }
        let results = Array(suggestions.prefix(6))
        guard !results.isEmpty else { return }

        distanceTask = Task { @MainActor [weak self] in
            let origin = CLLocation(
                latitude: referenceCoordinate.latitude,
                longitude: referenceCoordinate.longitude
            )
            for suggestion in results {
                guard !Task.isCancelled, let self else { return }
                // These are straight-line distances to geocoded MapKit places,
                // not walking-route lengths or estimates from a text label.
                guard let place = await self.resolve(suggestion),
                      !Task.isCancelled else { continue }
                let point = place.placemark.coordinate
                let meters = origin.distance(
                    from: CLLocation(latitude: point.latitude, longitude: point.longitude)
                )
                self.suggestionDistances[suggestion.distanceKey] = meters
            }
        }
    }

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [
            .address,
            .pointOfInterest
        ]
    }

    nonisolated func completerDidUpdateResults(
        _ completer: MKLocalSearchCompleter
    ) {
        let mapped = completer.results
            .prefix(12)
            .map {
                RunRouteLocationSuggestion(
                    title: $0.title,
                    subtitle: $0.subtitle
                )
            }

        Task { @MainActor [weak self] in
            self?.suggestions = mapped
            self?.refreshSuggestionDistances()
        }
    }

    nonisolated func completer(
        _ completer: MKLocalSearchCompleter,
        didFailWithError error: Error
    ) {
        Task { @MainActor [weak self] in
            self?.distanceTask?.cancel()
            self?.suggestions = []
            self?.suggestionDistances = [:]
        }
    }

    func clear() {
        distanceTask?.cancel()
        query = ""
        suggestions = []
        suggestionDistances = [:]
    }

    func resolve(
        _ suggestion: RunRouteLocationSuggestion
    ) async -> MKMapItem? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = [
            suggestion.title,
            suggestion.subtitle
        ]
        .filter { !$0.isEmpty }
        .joined(separator: ", ")
        if let referenceCoordinate {
            request.region = MKCoordinateRegion(
                center: referenceCoordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.8, longitudeDelta: 0.8)
            )
        }

        let fallbackName =
            suggestion.title.isEmpty
                ? suggestion.subtitle
                : suggestion.title

        let resolved:
            RunRouteResolvedLocation? =
                await withCheckedContinuation {
                    (
                        continuation:
                            CheckedContinuation<
                                RunRouteResolvedLocation?,
                                Never
                            >
                    ) in

                    MKLocalSearch(request: request)
                        .start { response, _ in
                            guard let item =
                                    response?
                                        .mapItems
                                        .first
                            else {
                                continuation.resume(
                                    returning: nil
                                )
                                return
                            }

                            let coordinate =
                                item.placemark
                                    .coordinate
                            let name =
                                item.name?
                                    .trimmingCharacters(
                                        in:
                                            .whitespacesAndNewlines
                                    )

                            continuation.resume(
                                returning:
                                    RunRouteResolvedLocation(
                                        latitude:
                                            coordinate.latitude,
                                        longitude:
                                            coordinate.longitude,
                                        name:
                                            name?.isEmpty == false
                                                ? name!
                                                : fallbackName
                                    )
                            )
                        }
                }

        guard let resolved else {
            return nil
        }

        let placemark = MKPlacemark(
            coordinate:
                CLLocationCoordinate2D(
                    latitude:
                        resolved.latitude,
                    longitude:
                        resolved.longitude
                )
        )
        let item = MKMapItem(
            placemark: placemark
        )
        item.name = resolved.name
        return item
    }

    static func displayName(
        for item: MKMapItem?
    ) -> String {
        guard let item else {
            return "—"
        }

        if let name = item.name,
           !name.isEmpty {
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

struct RunRouteLocationSuggestion:
    Identifiable,
    Sendable
{
    let id = UUID()
    let title: String
    let subtitle: String

    var distanceKey: String { title + "|" + subtitle }
}

enum RunRouteMapPointMode: String, CaseIterable {
    case automatic, start, finish, via

    static func resolve(
        mode: RunRouteMapPointMode, hasStart: Bool, hasFinish: Bool
    ) -> RunRouteMapPointMode {
        guard mode == .automatic else { return mode }
        if !hasStart { return .start }
        if !hasFinish { return .finish }
        return .via
    }
}

private struct RunRouteMapSnapshot {
    let start: MKMapItem?
    let finish: MKMapItem?
    let via: [RunRouteViaPoint]
}

private struct RunRouteViaPoint: Identifiable {
    let id = UUID()
    let item: MKMapItem
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
            .background {
                RoundedRectangle(
                    cornerRadius:
                        ATHLTHTheme
                            .cornerRadius,
                    style: .continuous
                )
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white,
                            ATHLTHPlanDesign.canvas.opacity(0.70)
                        ],
                        startPoint:
                            .topLeading,
                        endPoint:
                            .bottomTrailing
                    )
                )
            }
            .overlay {
                RoundedRectangle(
                    cornerRadius:
                        ATHLTHTheme
                            .cornerRadius,
                    style: .continuous
                )
                .stroke(
                    ATHLTHPlanDesign.warmDivider,
                    lineWidth: 0.8
                )
            }
            .shadow(
                color:
                    ATHLTHTheme
                        .accentDeep
                        .opacity(0.045),
                radius: 9,
                x: 0,
                y: 4
            )
    }
}
