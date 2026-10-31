@preconcurrency import MapKit
import SwiftUI

/// Coach-guided route creation. User choices stay on-device: Apple Maps
/// receives only coordinates needed to calculate pedestrian geometry.
/// The runner must approve a proposal before it becomes a saved route.
struct ATHLTHCoachRouteGeneratorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var routeDiscovery: RouteDiscoveryStore
    @StateObject private var locationStore = HomeLocationStore()

    var onRouteSaved: ((TrainingRoute) -> Void)? = nil

    @State private var brief = ATHLTHCoachRouteBrief()
    @State private var suggestions: [ATHLTHCoachRouteSuggestion] = []
    @State private var selectedID: UUID?
    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var isGenerating = false
    @State private var failureMessage: String?
    @State private var customTitle = ""

    private var selected: ATHLTHCoachRouteSuggestion? {
        suggestions.first { $0.id == selectedID }
    }

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(
                        tr("Describe the run. Coach will find walkable routes in Apple Maps.",
                           "Beskriv turen. Coach finner gangbare ruteforslag i Apple Maps."),
                        systemImage: "figure.run"
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHPlanDesign.ink)
                }
                .listRowBackground(ATHLTHPlanDesign.selectedSurface)

                Section(tr("Distance and time", "Distanse og tid")) {
                    Toggle(tr("Distance", "Distanse"), isOn: $brief.useDistance)
                        .tint(ATHLTHTrainDesign.bronze)
                    if brief.useDistance {
                        HStack {
                            Slider(value: $brief.distanceKilometers,
                                   in: 1...30, step: 0.5)
                            Text(String(format: "%.1f km", brief.distanceKilometers))
                                .monospacedDigit().frame(minWidth: 72, alignment: .trailing)
                        }
                    }
                    Toggle(tr("Duration", "Varighet"), isOn: $brief.useDuration)
                        .tint(ATHLTHTrainDesign.bronze)
                    if brief.useDuration {
                        Picker(tr("Target time", "Ønsket tid"),
                               selection: $brief.durationMinutes) {
                            ForEach(Array(stride(from: 15, through: 180, by: 5)),
                                    id: \.self) { time in
                                Text("\(time) min").tag(time)
                            }
                        }
                    }
                    HStack {
                        Text(tr("Expected pace", "Forventet tempo"))
                        Spacer()
                        Picker(tr("Pace", "Tempo"),
                               selection: $brief.paceMinutesPerKilometer) {
                            ForEach(Array(stride(from: 4.0, through: 12.0, by: 0.5)),
                                    id: \.self) { pace in
                                Text(String(format: "%.1f min/km", pace)).tag(pace)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    Text(tr(
                        "Time is estimated from distance and your selected pace, not Apple Maps walking time.",
                        "Tiden anslås fra distanse og valgt løpstempo, ikke gangtiden i Apple Maps."
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section(tr("Starting point", "Startsted")) {
                    Picker(tr("Start", "Start"), selection: $brief.startMode) {
                        ForEach(ATHLTHCoachRouteBrief.StartMode.allCases) {
                            Text($0.title).tag($0)
                        }
                    }
                    if brief.startMode == .nearby {
                        Picker(tr("Maximum distance to start", "Maks avstand til start"),
                               selection: $brief.startRadiusKilometers) {
                            ForEach([0.5, 1.0, 2.0, 5.0, 10.0], id: \.self) {
                                Text(String(format: "%.1f km", $0)).tag($0)
                            }
                        }
                    }
                    Toggle(tr("Return to start", "Rundtur"),
                           isOn: $brief.isLoop)
                        .tint(ATHLTHTrainDesign.bronze)
                    Text(brief.isLoop
                        ? tr("A connected loop returning to its starting point.",
                             "Sammenhengende rundtur tilbake til startstedet.")
                        : tr("Out and back on the same verified route.",
                             "Tur-retur langs samme beregnede strekning."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section(tr("Terrain and surroundings", "Underlag og omgivelser")) {
                    Picker(tr("Preferred surface", "Ønsket underlag"),
                           selection: $brief.surface) {
                        ForEach(ATHLTHCoachRouteBrief.Surface.allCases) {
                            Text($0.title).tag($0)
                        }
                    }
                    Picker(tr("Surroundings", "Omgivelser"),
                           selection: $brief.setting) {
                        ForEach(ATHLTHCoachRouteBrief.Setting.allCases) {
                            Text($0.title).tag($0)
                        }
                    }
                    Toggle(tr("Prefer quiet roads", "Foretrekk lite trafikk"),
                           isOn: $brief.avoidBusyRoads)
                    Toggle(tr("Prefer less climbing", "Foretrekk færre høydemeter"),
                           isOn: $brief.preferLessClimbing)
                    Text(tr(
                        "Important: walking directions do not certify surface, traffic, elevation or mountain-trail safety. These preferences are not enforced until verified map data is available.",
                        "Viktig: Gangruter dokumenterer ikke underlag, trafikk, høydemeter eller sikkerhet på fjellstier. Disse preferansene kan ikke håndheves før kartdataene er verifisert."
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section {
                    Button {
                        generate()
                    } label: {
                        HStack {
                            Spacer()
                            if isGenerating { ProgressView().padding(.trailing, 6) }
                            Label(tr("Find route suggestions", "Finn ruteforslag"),
                                  systemImage: "sparkles")
                                .font(.headline)
                            Spacer()
                        }
                        .frame(minHeight: 38)
                    }
                    .disabled(isGenerating || brief.validationMessage != nil)
                    .foregroundStyle(ATHLTHTrainDesign.bronze)
                    if let message = brief.validationMessage {
                        Text(message).font(.caption).foregroundStyle(.secondary)
                    }
                    if let failureMessage {
                        Label(failureMessage, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                if !suggestions.isEmpty {
                    Section(tr("Coach's route suggestions", "Ruteforslag fra coach")) {
                        ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, item in
                            Button {
                                selectedID = item.id
                                updateMap(for: item)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: selectedID == item.id
                                          ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(ATHLTHTrainDesign.bronze)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(index == 0
                                             ? tr("Best distance match", "Nærmest ønsket distanse")
                                             : tr("Alternative", "Alternativ") + " \(index + 1)")
                                            .font(.subheadline.weight(.semibold))
                                        Text(String(format: "%.1f km · ca. %.0f min",
                                                    item.distanceMeters / 1000,
                                                    item.predictedRunMinutes))
                                            .font(.caption)
                                        if brief.startMode == .nearby {
                                            Text(String(format: "%.1f km til start",
                                                        item.distanceFromUserMeters / 1000))
                                                .font(.caption2)
                                        }
                                    }
                                    Spacer()
                                }
                                .foregroundStyle(ATHLTHPlanDesign.ink)
                            }
                            .buttonStyle(.plain)
                        }

                        if let selected {
                            Map(position: $mapPosition) {
                                MapPolyline(coordinates: selected.coordinates)
                                    .stroke(ATHLTHTrainDesign.bronze, lineWidth: 5)
                                Annotation(tr("Start", "Start"), coordinate: selected.start) {
                                    Image(systemName: "mappin.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(ATHLTHTrainDesign.bronze)
                                }
                            }
                            .frame(height: 235)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .accessibilityLabel(tr("Route preview", "Forhåndsvisning av ruten"))
                            surfaceSummary(for: selected)

                            TextField(tr("Route name (optional)", "Rutenavn (valgfritt)"),
                                      text: $customTitle)
                            Button {
                                save(selected)
                            } label: {
                                Label(tr("Save selected route", "Lagre valgt rute"),
                                      systemImage: "checkmark.circle.fill")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity, minHeight: 42)
                            }
                            .tint(ATHLTHTrainDesign.bronze)
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(tr("Coach Route Builder", "Lag rute med Coach"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Close", "Lukk")) { dismiss() }
                }
            }
            .task { locationStore.start() }
        }
    }

    private func surfaceSummary(
        for item: ATHLTHCoachRouteSuggestion
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(tr("Surface estimate", "Estimert underlag"))
                .font(.subheadline.weight(.semibold))
            Text(tr(
                "Asphalt — · Gravel — · Trail — · Unknown 100%",
                "Asfalt — · Grus — · Sti — · Ukjent 100 %"
            ))
            .font(.caption)
            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            Text(tr(
                "Surface percentages are not yet available from this map provider. Unknown is shown instead of inventing values. Verify terrain and access before running.",
                "Underlagsandeler er foreløpig ikke tilgjengelige fra kartleverandøren. Vi viser ukjent i stedet for å gjette. Kontroller terreng og fremkommelighet før turen."
            ))
            .font(.caption2)
            .foregroundStyle(.secondary)
            if abs(item.distanceMeters - brief.targetMeters) / brief.targetMeters > 0.15 {
                Text(tr(
                    "This suggestion differs by more than 15% from your desired distance.",
                    "Dette forslaget avviker mer enn 15 % fra ønsket distanse."
                ))
                .font(.caption)
                .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 5)
    }

    private func generate() {
        guard !isGenerating,
              brief.validationMessage == nil else { return }
        guard let location = locationStore.location else {
            failureMessage = tr(
                "Your location is unavailable. Allow location access in Settings.",
                "Posisjonen er ikke tilgjengelig. Tillat posisjonstilgang i Innstillinger."
            )
            return
        }
        let selectedBrief = brief
        isGenerating = true
        suggestions = []
        selectedID = nil
        failureMessage = nil
        Task { @MainActor in
            do {
                let results = try await ATHLTHCoachRouteGenerator.generate(
                    brief: selectedBrief, location: location
                )
                suggestions = results
                selectedID = results.first?.id
                if let first = results.first { updateMap(for: first) }
            } catch {
                failureMessage = error.localizedDescription
            }
            isGenerating = false
        }
    }

    private func updateMap(for result: ATHLTHCoachRouteSuggestion) {
        let latitudes = result.coordinates.map(\.latitude)
        let longitudes = result.coordinates.map(\.longitude)
        guard let minLat = latitudes.min(), let maxLat = latitudes.max(),
              let minLon = longitudes.min(), let maxLon = longitudes.max()
        else { return }
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2
        )
        mapPosition = .region(MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(
                latitudeDelta: max((maxLat - minLat) * 1.4, 0.009),
                longitudeDelta: max((maxLon - minLon) * 1.4, 0.009)
            )
        ))
    }

    private func save(_ selected: ATHLTHCoachRouteSuggestion) {
        guard selected.coordinates.count >= 2 else { return }
        let routeTitle = customTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let route = TrainingRoute(
            id: UUID(),
            ownerID: session.profile.userID,
            title: routeTitle.isEmpty
                ? tr("Coach route", "Coach-rute") +
                    String(format: " · %.1f km", selected.distanceMeters / 1000)
                : routeTitle,
            visibility: .privateOnly,
            coordinates: selected.coordinates.enumerated().map {
                RouteCoordinate(
                    latitude: $0.element.latitude,
                    longitude: $0.element.longitude,
                    altitude: nil,
                    sequence: $0.offset
                )
            },
            distanceKilometers: selected.distanceMeters / 1000,
            elevationGainMeters: nil,
            importedFilename: nil,
            createdAt: Date(),
            startName: brief.startMode == .current
                ? tr("My location", "Der jeg er")
                : tr("Nearby start", "Start i nærheten"),
            endName: brief.isLoop
                ? tr("Return to start", "Tilbake til start") : nil,
            expectedTravelTimeSeconds: selected.predictedRunMinutes * 60,
            routeSource: "athlth_coach_apple_walking"
        )
        session.addImportedRoute(route)
        onRouteSaved?(route)
        // Reuse the existing publication path, not a parallel route database.
        Task { await routeDiscovery.publish(route) }
        dismiss()
    }
}
