import SwiftUI
import MapKit
import CoreLocation
import Combine
import UIKit

/// A single on-demand location fix. Never starts continuous tracking, never
/// requests background authorization, and never writes the athlete's position
/// into the competition unless a meeting pin is explicitly selected.
@MainActor
private final class ATHLTHMeetingLocationRequest: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var coordinate: CLLocationCoordinate2D?
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    private let manager = CLLocationManager()
    private var waiting = false
    private var requestedFix = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func locate() {
        guard !waiting else { return }
        error = nil
        waiting = true
        requestedFix = false
        loading = true
        advance()
    }

    private func advance() {
        guard waiting else { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            guard !requestedFix else { return }
            requestedFix = true
            manager.requestLocation()
        case .denied, .restricted:
            finish(error: "Posisjon er ikke tilgjengelig. Du kan endre stedstilgang i Innstillinger eller søke etter en adresse.")
        @unknown default:
            finish(error: "Kunne ikke hente posisjon. Søk etter et sted i stedet.")
        }
    }

    func cancel() {
        waiting = false
        requestedFix = false
        loading = false
        manager.stopUpdatingLocation()
    }

    private func finish(error: String? = nil) {
        cancel()
        self.error = error
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in self?.advance() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let fix = locations.last else { return }
        let latitude = fix.coordinate.latitude
        let longitude = fix.coordinate.longitude
        let accuracy = fix.horizontalAccuracy
        let age = abs(fix.timestamp.timeIntervalSinceNow)
        Task { @MainActor [weak self] in
            guard let self, self.waiting else { return }
            guard accuracy >= 0, age <= 120 else {
                self.finish(error: "Posisjonen var ikke oppdatert. Prøv igjen.")
                return
            }
            self.coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            self.finish()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self, self.waiting else { return }
            self.finish(error: "Kunne ikke hente posisjonen. Prøv igjen eller søk etter en adresse.")
        }
    }
}

/// Shared map picker. Address and meeting instructions are edited locally
/// until Done. GPS lap selection uses separate coordinates and cannot replace
/// a competition meeting point.
struct ATHLTHCompetitionMeetingPointPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var settings: ATHLTHTournamentCompetitionSettings
    var lapPointOnly = false
    @StateObject private var location = ATHLTHMeetingLocationRequest()
    @FocusState private var addressFocused: Bool
    @State private var address = ""
    @State private var instructions = ""
    @State private var pin: CLLocationCoordinate2D?
    @State private var userCoordinate: CLLocationCoordinate2D?
    @State private var position: MapCameraPosition = .automatic
    @State private var initialized = false
    @State private var suggestions: [MKMapItem] = []
    @State private var nearby: [MKMapItem] = []
    @State private var searchAnchor: CLLocationCoordinate2D?
    @State private var nearbyRefresh = UUID()
    @State private var reverseLookupID: UUID?
    @State private var searching = false
    @State private var loadingNearby = false
    @State private var searchMessage: String?
    @State private var nearbyMessage: String?

    private var query: String { address.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var combined: String {
        ATHLTHTournamentCompetitionSettings.combinedMeetingPlace(address: address, description: instructions)
    }
    private var canFinish: Bool {
        if lapPointOnly { return pin != nil }
        return combined.count <= 240 && (instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !query.isEmpty || pin != nil)
    }
    private var addressBinding: Binding<String> {
        Binding(get: { address }, set: { value in
            address = value
            // A manually changed address must not retain a different old pin.
            pin = nil
            reverseLookupID = nil
            suggestions = []
            searchMessage = nil
        })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    addressSearch
                    mapCard
                    nearbyCard
                    if !lapPointOnly { instructionCard }
                    if let error = location.error {
                        Text(error).font(.caption).foregroundStyle(.orange)
                    }
                    Button(lapPointOnly ? "Fjern valgt pinne" : "Fjern møtepunkt", role: .destructive) {
                        address = ""
                        instructions = ""
                        pin = nil
                        reverseLookupID = nil
                        suggestions = []
                        searchMessage = nil
                        if lapPointOnly {
                            settings.race.lapCourseLatitude = nil
                            settings.race.lapCourseLongitude = nil
                            dismiss()
                        }
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .padding(16)
                .frame(maxWidth: 700)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(ATHLTHArenaV3Style.cream.ignoresSafeArea())
            .foregroundStyle(ATHLTHArenaV3Style.ink)
            .tint(ATHLTHArenaV3Style.gold)
            .navigationTitle(lapPointOnly ? "Velg rundepassasje" : "Velg møtepunkt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Avbryt") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ferdig") { commit(); dismiss() }
                        .fontWeight(.semibold)
                        .disabled(!canFinish)
                }
            }
            .onAppear { restore() }
            .onDisappear { location.cancel() }
            .onReceive(location.$coordinate) { fix in
                guard let fix else { return }
                userCoordinate = fix
                focus(fix)
                refreshNearby(around: fix)
            }
            .task(id: query + "|" + String(addressFocused)) {
                await autocomplete()
            }
            .task(id: nearbyRefresh) {
                await loadNearby()
            }
            .task(id: reverseLookupID) {
                await resolveTappedAddress()
            }
        }
    }

    private var addressSearch: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Adresse eller sted").font(.subheadline.weight(.semibold))
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(ATHLTHArenaV3Style.secondary)
                TextField("Søk etter adresse eller sted", text: addressBinding)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.search)
                    .focused($addressFocused)
                    .onSubmit { addressFocused = false }
                if searching {
                    ProgressView().controlSize(.small)
                } else if !address.isEmpty {
                    Button {
                        addressBinding.wrappedValue = ""
                        addressFocused = true
                    } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Tøm adresse")
                }
            }
            .padding(12)
            .background(.white, in: RoundedRectangle(cornerRadius: 13))
            if addressFocused && !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(suggestions.enumerated()), id: \.offset) { index, item in
                        placeRow(item, showDistance: false) { choose(item) }
                        if index < suggestions.count - 1 { Divider() }
                    }
                }
                .padding(.horizontal, 12)
                .background(ATHLTHArenaV3Style.panel())
            }
            if let searchMessage, addressFocused {
                Text(searchMessage).font(.caption).foregroundStyle(ATHLTHArenaV3Style.secondary)
            }
        }
    }

    private var mapCard: some View {
        MapReader { proxy in
            Map(position: $position) {
                if let pin {
                    Marker(lapPointOnly ? "Rundepassasje" : "Møtepunkt", coordinate: pin)
                        .tint(ATHLTHArenaV3Style.gold)
                }
                if let userCoordinate {
                    Annotation("Min posisjon", coordinate: userCoordinate) {
                        Circle().fill(.blue)
                            .frame(width: 16, height: 16)
                            .overlay { Circle().strokeBorder(.white, lineWidth: 3) }
                            .shadow(radius: 2)
                    }
                }
            }
            .mapStyle(.standard)
            .onTapGesture { point in
                guard let coordinate = proxy.convert(point, from: .local) else { return }
                addressFocused = false
                pin = coordinate
                address = "Valgt punkt på kart"
                reverseLookupID = UUID()
                refreshNearby(around: coordinate)
                focus(coordinate)
            }
            .overlay(alignment: .topTrailing) {
                Button {
                    addressFocused = false
                    location.locate()
                } label: {
                    Group {
                        if location.loading { ProgressView() }
                        else { Image(systemName: "location.fill").font(.system(size: 19, weight: .semibold)) }
                    }
                    .foregroundStyle(ATHLTHArenaV3Style.gold)
                    .frame(width: 46, height: 46)
                    .background(.white, in: RoundedRectangle(cornerRadius: 14))
                    .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
                }
                .buttonStyle(.plain)
                .disabled(location.loading)
                .accessibilityLabel("Vis min posisjon")
                .padding(12)
            }
            .clipShape(RoundedRectangle(cornerRadius: 17))
        }
        .frame(height: lapPointOnly ? 320 : 290)
    }

    private var nearbyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Treningssteder i nærheten", systemImage: "mappin.and.ellipse")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ATHLTHArenaV3Style.gold)
            if loadingNearby {
                ProgressView("Henter steder i nærheten…").font(.caption)
            } else if nearby.isEmpty {
                Text(nearbyMessage ?? "Trykk på posisjonsknappen eller velg en adresse for å se treningssentre, idrettshaller og baner i nærheten.")
                    .font(.caption)
                    .foregroundStyle(ATHLTHArenaV3Style.secondary)
            } else {
                ForEach(Array(nearby.enumerated()), id: \.offset) { index, item in
                    placeRow(item, showDistance: true) { choose(item) }
                    if index < nearby.count - 1 { Divider() }
                }
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ATHLTHArenaV3Style.panel())
    }

    private var instructionCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Nærmere møtebeskrivelse").font(.subheadline.weight(.semibold))
            TextField("F.eks. hovedinngangen, ved resepsjonen",
                      text: $instructions, axis: .vertical)
                .lineLimit(2...4)
                .padding(13)
                .background(.white, in: RoundedRectangle(cornerRadius: 13))
            Text("Valgfritt. Beskriv hvor på den valgte adressen dere skal møtes. Din posisjon deles ikke automatisk.")
                .font(.caption)
                .foregroundStyle(ATHLTHArenaV3Style.secondary)
            if combined.count > 240 {
                Text("Adresse og beskrivelse kan til sammen være maks 240 tegn.")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private func placeRow(_ item: MKMapItem, showDistance: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: showDistance ? "figure.run.circle" : "mappin.circle")
                    .font(.title2)
                    .foregroundStyle(ATHLTHArenaV3Style.gold)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name ?? item.placemark.title ?? "Valgt sted")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHArenaV3Style.ink)
                    if let subtitle = item.placemark.title, subtitle != item.name {
                        Text(subtitle).font(.caption)
                            .foregroundStyle(ATHLTHArenaV3Style.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 6)
                if showDistance, let anchor = searchAnchor {
                    Text(distanceLabel(from: anchor, to: item.placemark.coordinate))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(ATHLTHArenaV3Style.secondary)
                }
                Image(systemName: "chevron.right").font(.caption)
                    .foregroundStyle(ATHLTHArenaV3Style.gold)
            }
            .padding(.vertical, 9)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func restore() {
        guard !initialized else { return }
        initialized = true
        if !lapPointOnly {
            address = settings.meetingAddress ?? settings.meetingPlace
            instructions = settings.meetingDescription ?? ""
        }
        let latitude = lapPointOnly ? settings.race.lapCourseLatitude : settings.meetingLat
        let longitude = lapPointOnly ? settings.race.lapCourseLongitude : settings.meetingLon
        if let latitude, let longitude {
            let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            pin = coordinate
            focus(coordinate)
            refreshNearby(around: coordinate)
        }
    }

    private func commit() {
        if lapPointOnly {
            settings.race.lapCourseLatitude = pin?.latitude
            settings.race.lapCourseLongitude = pin?.longitude
        } else {
            settings.setMeetingPoint(address: address, description: instructions,
                                     latitude: pin?.latitude, longitude: pin?.longitude)
        }
    }

    private func focus(_ coordinate: CLLocationCoordinate2D) {
        withAnimation(.easeInOut(duration: 0.35)) {
            position = .region(MKCoordinateRegion(center: coordinate,
                latitudinalMeters: 1_500, longitudinalMeters: 1_500))
        }
    }

    private func choose(_ item: MKMapItem) {
        addressFocused = false
        reverseLookupID = nil
        let coordinate = item.placemark.coordinate
        pin = coordinate
        address = addressLabel(item)
        suggestions = []
        searchMessage = nil
        focus(coordinate)
        refreshNearby(around: coordinate)
    }

    private func addressLabel(_ item: MKMapItem) -> String {
        let street = item.placemark.title ?? ""
        let name = item.name ?? ""
        if street.isEmpty { return name.isEmpty ? "Valgt punkt på kart" : name }
        if name.isEmpty || street.localizedCaseInsensitiveContains(name) { return street }
        return name + ", " + street
    }

    private func refreshNearby(around coordinate: CLLocationCoordinate2D) {
        searchAnchor = coordinate
        nearby = []
        nearbyMessage = nil
        nearbyRefresh = UUID()
    }

    private func region(around coordinate: CLLocationCoordinate2D) -> MKCoordinateRegion {
        MKCoordinateRegion(center: coordinate, latitudinalMeters: 16_000, longitudinalMeters: 16_000)
    }

    private func autocomplete() async {
        guard addressFocused, query.count >= 2 else {
            suggestions = []
            searching = false
            return
        }
        let requested = query
        searching = true
        defer { if !Task.isCancelled { searching = false } }
        do {
            try await Task.sleep(for: .milliseconds(320))
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = requested
            request.resultTypes = [.address, .pointOfInterest]
            if let anchor = searchAnchor { request.region = region(around: anchor) }
            let response = try await MKLocalSearch(request: request).start()
            guard !Task.isCancelled, requested == query, addressFocused else { return }
            suggestions = Array(response.mapItems.prefix(5))
            searchMessage = suggestions.isEmpty ? "Ingen treff. Du kan skrive adressen manuelt." : nil
        } catch {
            guard !Task.isCancelled, requested == query, addressFocused else { return }
            suggestions = []
            searchMessage = "Ingen adresseforslag tilgjengelig. Du kan skrive adressen manuelt."
        }
    }

    private func loadNearby() async {
        guard let anchor = searchAnchor else { return }
        let generation = nearbyRefresh
        loadingNearby = true
        defer { if generation == nearbyRefresh { loadingNearby = false } }
        let categories = ["treningssenter", "idrettshall", "idrettsbane"]
        var groups: [[MKMapItem]] = []
        for category in categories {
            guard !Task.isCancelled, generation == nearbyRefresh else { return }
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = category
            request.resultTypes = .pointOfInterest
            request.region = region(around: anchor)
            let response = try? await MKLocalSearch(request: request).start()
            let items = (response?.mapItems ?? []).filter {
                distance(from: anchor, to: $0.placemark.coordinate) <= 12_000
            }.sorted {
                distance(from: anchor, to: $0.placemark.coordinate) < distance(from: anchor, to: $1.placemark.coordinate)
            }
            groups.append(items)
        }
        guard !Task.isCancelled, generation == nearbyRefresh else { return }
        var result: [MKMapItem] = []
        var seen: Set<String> = []
        func add(_ item: MKMapItem) {
            let key = (item.name ?? "").lowercased() + "|" + (item.placemark.title ?? "").lowercased()
            guard result.count < 3, seen.insert(key).inserted else { return }
            result.append(item)
        }
        for group in groups {
            if let first = group.first { add(first) }
        }
        for item in groups.flatMap({ $0 }).sorted(by: {
            distance(from: anchor, to: $0.placemark.coordinate) < distance(from: anchor, to: $1.placemark.coordinate)
        }) { add(item) }
        nearby = result
        nearbyMessage = result.isEmpty ? "Fant ingen treningssteder i nærheten. Du kan fortsatt søke eller velge på kartet." : nil
    }

    private func resolveTappedAddress() async {
        guard let id = reverseLookupID, let pin else { return }
        let geocoder = CLGeocoder()
        let result = try? await geocoder.reverseGeocodeLocation(CLLocation(latitude: pin.latitude, longitude: pin.longitude))
        guard !Task.isCancelled, reverseLookupID == id, let placemark = result?.first else { return }
        let street = [placemark.thoroughfare, placemark.subThoroughfare].compactMap { $0 }.joined(separator: " ")
        let city = [placemark.postalCode, placemark.locality].compactMap { $0 }.joined(separator: " ")
        let label = [street, city].filter { !$0.isEmpty }.joined(separator: ", ")
        if !label.isEmpty { address = label }
    }

    private func distance(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: from.latitude, longitude: from.longitude)
            .distance(from: CLLocation(latitude: to.latitude, longitude: to.longitude))
    }

    private func distanceLabel(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> String {
        let meters = distance(from: from, to: to)
        if meters < 1_000 { return "\(Int(meters.rounded())) m" }
        return (meters / 1_000).formatted(.number.precision(.fractionLength(1))) + " km"
    }
}


/// Compact shared rules/review preview. The selected meeting point is the
/// only coordinate used; no location permission or live map tracking.
struct ATHLTHCompetitionMeetingPointPreview: View {
    let settings: ATHLTHTournamentCompetitionSettings
    var editable = false

    private struct Point: Hashable {
        let latitude: Double
        let longitude: Double
    }

    @State private var renderedPoint: Point?
    @State private var snapshot: UIImage?
    @State private var attemptedPoint: Point?

    private var point: Point? {
        guard let latitude = settings.meetingLat, let longitude = settings.meetingLon,
              CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
        else { return nil }
        return Point(latitude: latitude, longitude: longitude)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.title3)
                    .foregroundStyle(ATHLTHArenaV3Style.gold)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Møtested")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHArenaV3Style.secondary)
                    Text(settings.meetingDisplayAddress)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHArenaV3Style.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if let description = settings.meetingDisplayDescription {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(ATHLTHArenaV3Style.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 4)
                if editable {
                    Text("Endre")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHArenaV3Style.gold)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHArenaV3Style.gold)
                }
            }
            if let point {
                mapPreview(point)
            } else {
                Label("Kartutsnitt vises når et punkt er valgt på kartet.", systemImage: "map")
                    .font(.caption)
                    .foregroundStyle(ATHLTHArenaV3Style.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: point) {
            guard let point else {
                snapshot = nil
                renderedPoint = nil
                attemptedPoint = nil
                return
            }
            if renderedPoint == point, snapshot != nil { return }
            snapshot = nil
            renderedPoint = nil
            attemptedPoint = nil
            let image = await RouteMapSnapshotCache.meetingPointImage(
                latitude: point.latitude, longitude: point.longitude)
            guard !Task.isCancelled, self.point == point else { return }
            snapshot = image
            renderedPoint = image == nil ? nil : point
            attemptedPoint = point
        }
    }

    private func mapPreview(_ point: Point) -> some View {
        Color.clear
            .aspectRatio(2.5, contentMode: .fit)
            .overlay {
                if renderedPoint == point, let snapshot {
                    Image(uiImage: snapshot)
                        .resizable()
                        .scaledToFit()
                        .overlay {
                            // The snapshot is centered on the saved coordinate.
                            // Align the bottom of the pin to that center.
                            Image(systemName: "mappin.circle.fill")
                                .font(.system(size: 29, weight: .semibold))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, ATHLTHArenaV3Style.gold)
                                .shadow(color: .black.opacity(0.22), radius: 3, y: 2)
                                .offset(y: -12)
                        }
                } else {
                    VStack(spacing: 6) {
                        if attemptedPoint != point {
                            ProgressView().controlSize(.small)
                            Text("Henter kart…").font(.caption)
                        } else {
                            Image(systemName: "map").font(.title3)
                            Text("Kartutsnitt utilgjengelig").font(.caption)
                        }
                    }
                    .foregroundStyle(ATHLTHArenaV3Style.secondary)
                }
            }
            .background(ATHLTHArenaV3Style.cream)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityLabel("Kartutsnitt av valgt møtested")
            .allowsHitTesting(false)
    }
}
