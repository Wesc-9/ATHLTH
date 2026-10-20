import SwiftUI
@preconcurrency import MapKit
import Combine

/// MapKit result types are not Sendable. Transfer only these immutable strings
/// from the delegate to the SwiftUI main actor.
private struct ATHLTHTrainingPlaceSuggestion: Sendable {
    let title: String
    let subtitle: String
}

/// Apple Maps address and point-of-interest suggestions without requiring
/// the athlete's current location.
@MainActor
final class ATHLTHTrainingPlaceSearch: NSObject, ObservableObject,
    MKLocalSearchCompleterDelegate {
    @Published private(set) var results: [ATHLTHTrainingPlaceSuggestion] = []
    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func search(_ text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { results = [] }
        completer.queryFragment = clean
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        guard !completer.queryFragment.trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty else { return }
        let suggestions = completer.results.prefix(8).map {
            ATHLTHTrainingPlaceSuggestion(title: $0.title, subtitle: $0.subtitle)
        }
        Task { @MainActor [weak self] in
            self?.results = suggestions
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter,
                              didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.results = []
        }
    }
}

/// Account-local favorites, not public map pins and never shared with other athletes.
enum ATHLTHTrainingPlaceFavorites {
    private static let storageName = "favoriteTrainingPlaces"

    static func load(userID: UUID) -> [ATHLTHTrainingPlace] {
        AccountLocalStorage.read([ATHLTHTrainingPlace].self,
                                 name: storageName, userID: userID) ?? []
    }

    static func add(_ place: ATHLTHTrainingPlace, userID: UUID) {
        var places = load(userID: userID)
        places.removeAll {
            $0.name.localizedCaseInsensitiveCompare(place.name) == .orderedSame &&
            $0.address.localizedCaseInsensitiveCompare(place.address) == .orderedSame
        }
        places.insert(place, at: 0)
        AccountLocalStorage.write(Array(places.prefix(100)),
                                  name: storageName, userID: userID)
    }

    static func remove(_ id: UUID, userID: UUID) {
        var places = load(userID: userID)
        places.removeAll { $0.id == id }
        AccountLocalStorage.write(places, name: storageName, userID: userID)
    }
}

/// One reusable, ATHLTH-plan-styled picker for a specific date.
struct ATHLTHPlanTrainingPlacePicker: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore

    @State private var kind: ATHLTHTrainingPlaceKind
    @State private var name: String
    @State private var address: String
    @State private var favorites: [ATHLTHTrainingPlace] = []
    @StateObject private var placeSearch = ATHLTHTrainingPlaceSearch()
    @State private var query = ""

    let onSave: (ATHLTHTrainingPlace?) -> Void

    init(initial: ATHLTHTrainingPlace?,
         onSave: @escaping (ATHLTHTrainingPlace?) -> Void) {
        _kind = State(initialValue: initial?.kind ?? .other)
        _name = State(initialValue: initial?.name ?? "")
        _address = State(initialValue: initial?.address ?? "")
        self.onSave = onSave
    }

    private var selectedPlace: ATHLTHTrainingPlace? {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty || !cleanAddress.isEmpty else { return nil }
        return ATHLTHTrainingPlace(kind: kind,
            name: cleanName.isEmpty ? cleanAddress : cleanName,
            address: cleanAddress)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ATHLTHPlanSectionIntro(
                        eyebrow: "ATHLTH",
                        title: ATHLTHLocalization.choose(
                            english: "Where will you train?", norwegian: "Hvor skal du trene?"),
                        subtitle: ATHLTHLocalization.choose(
                            english: "Choose a favorite or add a new location for this day.",
                            norwegian: "Velg et favorittsted eller legg til et nytt sted for denne dagen."),
                        icon: "mappin.and.ellipse")

                    ATHLTHPlanSurface {
                        VStack(alignment: .leading, spacing: 10) {
                            TextField(ATHLTHLocalization.choose(
                                english: "Search Apple Maps for a place or address",
                                norwegian: "Søk etter sted eller adresse i Apple Maps"),
                                text: $query)
                                .textInputAutocapitalization(.words)
                                .autocorrectionDisabled()
                                .onChange(of: query) { _, value in
                                    placeSearch.search(value)
                                }
                            ForEach(Array(placeSearch.results.prefix(6).enumerated()),
                                    id: \.offset) { entry in
                                let result = entry.element
                                Button {
                                    name = result.title
                                    address = result.subtitle
                                    query = ""
                                    placeSearch.search("")
                                } label: {
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: "mappin.and.ellipse")
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(result.title)
                                                .font(.subheadline.weight(.semibold))
                                            Text(result.subtitle)
                                                .font(.caption)
                                                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                                        }
                                        Spacer()
                                    }
                                    .foregroundStyle(ATHLTHPlanDesign.ink)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    ATHLTHPlanSurface {
                        VStack(alignment: .leading, spacing: 14) {
                            Picker(ATHLTHLocalization.choose(
                                english: "Type of place", norwegian: "Type sted"),
                                   selection: $kind) {
                                ForEach(ATHLTHTrainingPlaceKind.allCases) { value in
                                    Label(value.title, systemImage: value.symbol).tag(value)
                                }
                            }
                            TextField(ATHLTHLocalization.choose(
                                english: "Name (gym, hotel, etc.)",
                                norwegian: "Navn (treningssenter, hotell osv.)"),
                                text: $name)
                                .textInputAutocapitalization(.words)
                            TextField(ATHLTHLocalization.choose(
                                english: "Address (optional)", norwegian: "Adresse (valgfritt)"),
                                text: $address)
                                .textInputAutocapitalization(.words)
                            if let place = selectedPlace {
                                Button {
                                    ATHLTHTrainingPlaceFavorites.add(place,
                                        userID: session.profile.userID)
                                    favorites = ATHLTHTrainingPlaceFavorites.load(
                                        userID: session.profile.userID)
                                } label: {
                                    Label(ATHLTHLocalization.choose(
                                        english: "Save as favorite", norwegian: "Lagre som favoritt"),
                                        systemImage: "star")
                                }
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(ATHLTHPlanDesign.accentInk)
                            }
                        }
                    }

                    if !favorites.isEmpty {
                        Text(ATHLTHLocalization.choose(
                            english: "FAVORITES", norwegian: "FAVORITTER"))
                            .font(.caption.weight(.bold))
                            .tracking(1.4)
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        ATHLTHPlanSurface {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(favorites) { place in
                                    HStack(spacing: 10) {
                                        Button {
                                            kind = place.kind
                                            name = place.name
                                            address = place.address
                                        } label: {
                                            HStack(spacing: 10) {
                                                Image(systemName: place.kind.symbol)
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(place.name)
                                                        .font(.subheadline.weight(.semibold))
                                                    if !place.address.isEmpty {
                                                        Text(place.address)
                                                            .font(.caption)
                                                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                                                    }
                                                }
                                                Spacer()
                                            }
                                            .foregroundStyle(ATHLTHPlanDesign.ink)
                                            .frame(minHeight: 48)
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                        Button {
                                            ATHLTHTrainingPlaceFavorites.remove(place.id,
                                                userID: session.profile.userID)
                                            favorites = ATHLTHTrainingPlaceFavorites.load(
                                                userID: session.profile.userID)
                                        } label: {
                                            Image(systemName: "star.slash")
                                                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                                        }
                                        .accessibilityLabel(ATHLTHLocalization.choose(
                                            english: "Remove favorite", norwegian: "Fjern favoritt"))
                                    }
                                    if place.id != favorites.last?.id { Divider() }
                                }
                            }
                        }
                    }
                }
                .padding(18)
            }
            .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
            .navigationTitle(ATHLTHLocalization.choose(
                english: "Training place", norwegian: "Treningssted"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ATHLTHLocalization.choose(
                        english: "Cancel", norwegian: "Avbryt")) { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 10) {
                    Button {
                        onSave(nil)
                        dismiss()
                    } label: {
                        Text(ATHLTHLocalization.choose(
                            english: "No place", norwegian: "Uten sted"))
                            .frame(maxWidth: .infinity, minHeight: 46)
                    }
                    .foregroundStyle(ATHLTHPlanDesign.ink)
                    .background(ATHLTHPlanDesign.selectedSurface,
                                in: RoundedRectangle(cornerRadius: 15))
                    Button {
                        onSave(selectedPlace)
                        dismiss()
                    } label: {
                        Text(ATHLTHLocalization.choose(
                            english: "Use this place", norwegian: "Bruk dette stedet"))
                            .frame(maxWidth: .infinity, minHeight: 46)
                    }
                    .disabled(selectedPlace == nil)
                    .foregroundStyle(.white)
                    .background(ATHLTHPlanDesign.accentInk,
                                in: RoundedRectangle(cornerRadius: 15))
                }
                .font(.subheadline.weight(.semibold))
                .padding(14)
                .background(ATHLTHPlanDesign.canvas)
            }
            .onAppear {
                favorites = ATHLTHTrainingPlaceFavorites.load(userID: session.profile.userID)
            }
        }
    }
}
