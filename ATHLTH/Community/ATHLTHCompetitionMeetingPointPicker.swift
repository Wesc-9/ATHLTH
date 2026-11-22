import SwiftUI
import MapKit

/// Select an optional competition meeting point without requesting the
/// athlete's current location. A typed address or a tapped map pin is valid.
struct ATHLTHCompetitionMeetingPointPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var settings: ATHLTHTournamentCompetitionSettings
    @State private var query = ""
    @State private var position: MapCameraPosition = .automatic
    @State private var searching = false
    @State private var message: String?

    private var coordinate: CLLocationCoordinate2D? {
        guard let latitude = settings.meetingLat,
              let longitude = settings.meetingLon else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    TextField("Søk etter sted eller adresse", text: $query)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.search)
                        .onSubmit { Task { await lookup() } }
                        .padding(12)
                        .background(.white, in: RoundedRectangle(cornerRadius: 13))
                    Button {
                        Task { await lookup() }
                    } label: {
                        if searching { ProgressView() }
                        else { Image(systemName: "magnifyingglass") }
                    }
                    .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty ||
                              searching)
                    .tint(ATHLTHArenaV3Style.gold)
                }

                MapReader { proxy in
                    Map(position: $position) {
                        if let coordinate {
                            Marker("Møtepunkt", coordinate: coordinate)
                                .tint(ATHLTHArenaV3Style.gold)
                        }
                    }
                    .mapStyle(.standard)
                    .onTapGesture { point in
                        guard let coordinate = proxy.convert(point, from: .local)
                        else { return }
                        select(coordinate)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 17))
                }
                .frame(minHeight: 250)
                .frame(maxHeight: .infinity)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Adresse eller møtebeskrivelse")
                        .font(.subheadline.weight(.semibold))
                    TextField("F.eks. inngangen til treningssenteret",
                              text: $settings.meetingPlace, axis: .vertical)
                        .lineLimit(1...3)
                        .padding(13)
                        .background(.white, in: RoundedRectangle(cornerRadius: 13))
                    Text("Skriv adressen, eller trykk på kartet for å velge en presis pinne. Møtepunktet er kun informasjon; ingen automatisk posisjonssporing.")
                        .font(.caption)
                        .foregroundStyle(ATHLTHArenaV3Style.secondary)
                }

                if let message {
                    Text(message).font(.caption).foregroundStyle(.orange)
                }
                Button("Fjern møtepunkt") {
                    settings.meetingPlace = ""
                    settings.meetingLat = nil
                    settings.meetingLon = nil
                }
                .font(.caption)
                .tint(ATHLTHArenaV3Style.gold)
            }
            .padding(16)
            .background(ATHLTHArenaV3Style.cream.ignoresSafeArea())
            .navigationTitle("Velg møtepunkt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ferdig") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                query = settings.meetingPlace
                if let coordinate {
                    position = .region(MKCoordinateRegion(
                        center: coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.015,
                                             longitudeDelta: 0.015)))
                }
            }
        }
    }

    @MainActor
    private func select(_ location: CLLocationCoordinate2D) {
        settings.meetingLat = location.latitude
        settings.meetingLon = location.longitude
        if settings.meetingPlace.isEmpty {
            settings.meetingPlace = "Valgt møtepunkt på kart"
        }
        position = .region(MKCoordinateRegion(
            center: location,
            span: MKCoordinateSpan(latitudeDelta: 0.012,
                                 longitudeDelta: 0.012)))
        message = nil
    }

    @MainActor
    private func lookup() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !searching else { return }
        searching = true
        defer { searching = false }
        do {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = text
            let result = try await MKLocalSearch(request: request).start()
            guard let place = result.mapItems.first else {
                message = "Fant ingen treff. Skriv en adresse manuelt."
                return
            }
            select(place.placemark.coordinate)
            settings.meetingPlace = String(text.prefix(240))
        } catch {
            message = "Stedssøket var utilgjengelig. Du kan fortsatt skrive adressen."
        }
    }
}
