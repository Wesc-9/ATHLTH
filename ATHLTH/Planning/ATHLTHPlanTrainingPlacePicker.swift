import SwiftUI
@preconcurrency import MapKit
import Combine

/// MapKit result types are not Sendable. Transfer only these immutable strings
/// from the delegate to the SwiftUI main actor.
struct ATHLTHTrainingPlaceSuggestion: Sendable {
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
    @FocusState private var nameFocused: Bool

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
                            english: "Select a type, search Apple Maps or choose a favorite. A street address is optional.",
                            norwegian: "Velg type, søk i Apple Maps eller bruk et favorittsted. Adresse er valgfritt."),
                        icon: "mappin.and.ellipse")

                    VStack(alignment: .leading, spacing: 12) {
                        Text(ATHLTHLocalization.choose(
                            english: "WHAT KIND OF PLACE?", norwegian: "HVOR TRENER DU?"
                        ))
                        .font(.caption.weight(.semibold))
                        .tracking(1)
                        .foregroundStyle(.secondary)

                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 9),
                            GridItem(.flexible(), spacing: 9),
                            GridItem(.flexible(), spacing: 9)
                        ], spacing: 9) {
                            ForEach(
                                ATHLTHTrainingPlaceKind.allCases.filter {
                                    $0 != .address && $0 != .other
                                }
                            ) { option in
                                Button {
                                    kind = option
                                    if name.isEmpty { nameFocused = true }
                                } label: {
                                    VStack(spacing: 7) {
                                        Image(systemName: option.symbol)
                                            .font(.title3)
                                            .frame(height: 24)
                                        Text(option.title)
                                            .font(.caption.weight(.medium))
                                            .lineLimit(2)
                                            .multilineTextAlignment(.center)
                                    }
                                    .foregroundStyle(
                                        kind == option
                                            ? Color.white : ATHLTHPlanDesign.ink
                                    )
                                    .frame(maxWidth: .infinity, minHeight: 76)
                                    .padding(.horizontal, 5)
                                    .background(
                                        kind == option
                                            ? ATHLTHPlanDesign.ink
                                            : Color(red: 0.954, green: 0.952, blue: 0.947),
                                        in: RoundedRectangle(cornerRadius: 14)
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(kind == option ? .isSelected : [])
                            }
                        }
                        Button {
                            kind = .other
                            if name.isEmpty { nameFocused = true }
                        } label: {
                            Label(
                                ATHLTHLocalization.choose(
                                    english: "Another training place",
                                    norwegian: "Annet treningssted"
                                ),
                                systemImage: "mappin.and.ellipse"
                            )
                            .font(.subheadline)
                            .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(ATHLTHPlanDesign.ink)
                    }
                    .padding(15)
                    .background(.white, in: RoundedRectangle(cornerRadius: 19))


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
                            TextField(ATHLTHLocalization.choose(
                                english: "Name of the training place",
                                norwegian: "Navn på treningsstedet"),
                                text: $name)
                                .textInputAutocapitalization(.words)
                                .focused($nameFocused)
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
