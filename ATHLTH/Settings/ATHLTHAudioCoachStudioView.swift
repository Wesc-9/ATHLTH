import MapKit
import SwiftUI

private struct ATHLTHAudioCoachPlaceCandidate: Identifiable {
    let id = UUID()
    let name: String
    let detail: String
    let latitude: Double
    let longitude: Double
}

/// An athlete-owned Audio Coach studio. Saved profiles stay local and are
/// transferred as part of the normal workout configuration to Apple Watch.
struct ATHLTHAudioCoachStudioView: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @State private var profileName = ""
    @State private var customPhrase = ""
    @State private var placeSearch = ""
    @State private var placeSide: ATHLTHCoachLandmarkSide = .unspecified
    @State private var foundPlaces: [ATHLTHAudioCoachPlaceCandidate] = []
    @State private var searching = false
    @State private var placeError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                introduction
                profilesCard
                motivationCard
                randomCard
                landmarksCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .background {
            LinearGradient(
                colors: [ATHLTHTheme.canvasTop, .white, ATHLTHTheme.canvasBottom],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        }
        .navigationTitle("Audio Coach")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("ATHLTH COACH STUDIO", systemImage: "waveform")
                .font(.caption.weight(.semibold))
                .tracking(2)
                .foregroundStyle(ATHLTHTheme.accentDeep)
            Text(ATHLTHLocalization.choose(
                english: "A voice that runs with you.",
                norwegian: "En stemme som løper med deg."
            ))
            .font(.largeTitle.weight(.bold))
            .foregroundStyle(ATHLTHTheme.primaryText)
            Text(ATHLTHLocalization.choose(
                english: "Build your own mix of motivation, updates and places. Save the entire experience for your next workout.",
                norwegian: "Sett sammen motivasjon, oppdateringer og steder. Lagre hele opplevelsen til neste økt."
            ))
            .font(.subheadline)
            .foregroundStyle(ATHLTHTheme.mutedText)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(
            LinearGradient(
                colors: [ATHLTHTheme.accentSoft, Color.white],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 28)
        )
    }

    private var profilesCard: some View {
        studioCard(
            title: ATHLTHLocalization.choose(
                english: "My coach profiles", norwegian: "Mine coach-profiler"
            ),
            subtitle: ATHLTHLocalization.choose(
                english: "Switch between intervals, recovery runs or long runs.",
                norwegian: "Bytt mellom intervall, rolig tur og langkjøring."
            ),
            icon: "square.stack.3d.up"
        ) {
            VStack(spacing: 12) {
                ForEach(settings.audioCoachProfiles) { profile in
                    HStack(spacing: 10) {
                        Image(systemName: settings.activeAudioCoachProfileID == profile.id
                              ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                        Button {
                            settings.applyAudioCoachProfile(profile)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(profile.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(ATHLTHTheme.primaryText)
                                Text(settings.activeAudioCoachProfileID == profile.id
                                     ? ATHLTHLocalization.choose(english: "Selected", norwegian: "Valgt")
                                     : ATHLTHLocalization.choose(english: "Use profile", norwegian: "Bruk profil"))
                                    .font(.caption)
                                    .foregroundStyle(ATHLTHTheme.mutedText)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        Button(role: .destructive) {
                            settings.audioCoachProfiles.removeAll { $0.id == profile.id }
                            if settings.activeAudioCoachProfileID == profile.id {
                                settings.activeAudioCoachProfileID = nil
                            }
                        } label: {
                            Image(systemName: "trash")
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel(ATHLTHLocalization.choose(
                            english: "Delete profile", norwegian: "Slett profil"
                        ))
                    }
                    if profile.id != settings.audioCoachProfiles.last?.id {
                        Divider()
                    }
                }
                TextField(ATHLTHLocalization.choose(
                    english: "e.g. For intervals", norwegian: "F.eks. Ved intervall"
                ), text: $profileName)
                .textInputAutocapitalization(.sentences)
                .padding(12)
                .background(ATHLTHTheme.canvasTop,
                            in: RoundedRectangle(cornerRadius: 12))

                Button {
                    settings.saveAudioCoachProfile(named: profileName)
                    profileName = ""
                } label: {
                    Label(ATHLTHLocalization.choose(
                        english: "Save current coach as a profile",
                        norwegian: "Lagre oppsettet som profil"
                    ), systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(ATHLTHTheme.accentDeep)
                .disabled(profileName.trimmingCharacters(
                    in: .whitespacesAndNewlines).isEmpty ||
                    settings.audioCoachProfiles.count >= 30)
            }
        }
    }

    private var motivationCard: some View {
        studioCard(
            title: ATHLTHLocalization.choose(
                english: "Motivation along the way",
                norwegian: "Motivasjon underveis"
            ),
            subtitle: ATHLTHLocalization.choose(
                english: "Contextual, encouraging updates while you run.",
                norwegian: "Korte, motiverende kommentarer mens du løper."
            ),
            icon: "bolt.heart"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(ATHLTHLocalization.choose(
                    english: "Enable motivational updates",
                    norwegian: "Motiverende oppdateringer"
                ), isOn: $settings.audioCoachSmartSettings.motivationEnabled)
                .tint(ATHLTHTheme.accentDeep)

                if settings.audioCoachSmartSettings.motivationEnabled {
                    Stepper(
                        value: $settings.audioCoachSmartSettings.motivationIntervalSeconds,
                        in: 30...600, step: 30
                    ) {
                        Text(ATHLTHLocalization.choose(
                            english: "About every \(settings.audioCoachSmartSettings.motivationIntervalSeconds) sec",
                            norwegian: "Omtrent hvert \(settings.audioCoachSmartSettings.motivationIntervalSeconds). sekund"
                        ))
                        .font(.subheadline)
                    }
                }
                info(ATHLTHLocalization.choose(
                    english: "Pace feedback is based on measured data. Personal bests are never claimed without verified records.",
                    norwegian: "Tempokommentarer bruker målte data. Personlig rekord påstås aldri uten verifiserte resultater."
                ))
            }
        }
    }

    private var randomCard: some View {
        studioCard(
            title: ATHLTHLocalization.choose(
                english: "Surprise me", norwegian: "Overrask meg"
            ),
            subtitle: ATHLTHLocalization.choose(
                english: "A large varied set of uplifting phrases — plus your own words.",
                norwegian: "Mange ulike oppmuntringer, i tillegg til dine egne setninger."
            ),
            icon: "sparkles"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(ATHLTHLocalization.choose(
                    english: "Random encouragements",
                    norwegian: "Tilfeldige oppmuntringer"
                ), isOn: $settings.audioCoachSmartSettings.randomEncouragementEnabled)
                .tint(ATHLTHTheme.accentDeep)

                if settings.audioCoachSmartSettings.randomEncouragementEnabled {
                    Stepper(
                        value: $settings.audioCoachSmartSettings.randomIntervalSeconds,
                        in: 90...900, step: 30
                    ) {
                        Text(ATHLTHLocalization.choose(
                            english: "Average every \(settings.audioCoachSmartSettings.randomIntervalSeconds / 60) min",
                            norwegian: "I snitt hvert \(settings.audioCoachSmartSettings.randomIntervalSeconds / 60). min"
                        ))
                        .font(.subheadline)
                    }
                    info(ATHLTHLocalization.choose(
                        english: "Timing varies, and recent phrases aren't repeated.",
                        norwegian: "Tidspunktene varierer, og nylige setninger gjentas ikke."
                    ))
                }

                ForEach(settings.audioCoachSmartSettings.customEncouragements,
                        id: \.self) { phrase in
                    HStack(alignment: .center, spacing: 10) {
                        Text(phrase).font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button(role: .destructive) {
                            settings.audioCoachSmartSettings.customEncouragements
                                .removeAll { $0 == phrase }
                        } label: {
                            Image(systemName: "trash")
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel(ATHLTHLocalization.choose(
                            english: "Delete encouragement", norwegian: "Slett setning"
                        ))
                    }
                }

                TextField(ATHLTHLocalization.choose(
                    english: "Write your own encouragement",
                    norwegian: "Skriv en motiverende setning"
                ), text: $customPhrase, axis: .vertical)
                .lineLimit(1...3)
                .padding(12)
                .background(ATHLTHTheme.canvasTop,
                            in: RoundedRectangle(cornerRadius: 12))
                Button {
                    let value = String(customPhrase.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).prefix(140))
                    guard !value.isEmpty,
                          !settings.audioCoachSmartSettings.customEncouragements
                            .contains(value)
                    else { return }
                    settings.audioCoachSmartSettings.customEncouragements.append(value)
                    customPhrase = ""
                } label: {
                    Label(ATHLTHLocalization.choose(
                        english: "Add phrase", norwegian: "Legg til setning"
                    ), systemImage: "plus")
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(customPhrase.trimmingCharacters(
                    in: .whitespacesAndNewlines).isEmpty ||
                    settings.audioCoachSmartSettings.customEncouragements.count >= 40)
            }
        }
    }

    private var landmarksCard: some View {
        studioCard(
            title: ATHLTHLocalization.choose(
                english: "Places along the route",
                norwegian: "Steder langs ruten"
            ),
            subtitle: ATHLTHLocalization.choose(
                english: "Choose places to hear about as you pass them.",
                norwegian: "Velg steder coachen kan fortelle om når du passerer."
            ),
            icon: "mappin.and.ellipse"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(settings.audioCoachSmartSettings.landmarks) { landmark in
                    HStack(spacing: 10) {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(landmark.name).font(.subheadline.weight(.semibold))
                            Text(landmark.side.title).font(.caption)
                                .foregroundStyle(ATHLTHTheme.mutedText)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            settings.audioCoachSmartSettings.landmarks
                                .removeAll { $0.id == landmark.id }
                        } label: {
                            Image(systemName: "trash")
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel(ATHLTHLocalization.choose(
                            english: "Delete place", norwegian: "Slett sted"
                        ))
                    }
                }

                TextField(ATHLTHLocalization.choose(
                    english: "Search for a landmark or a street",
                    norwegian: "Søk etter et landemerke eller en gate"
                ), text: $placeSearch)
                .submitLabel(.search)
                .onSubmit(searchForPlace)
                .padding(12)
                .background(ATHLTHTheme.canvasTop,
                            in: RoundedRectangle(cornerRadius: 12))
                Picker(ATHLTHLocalization.choose(
                    english: "Which side?", norwegian: "Hvilken side?"
                ), selection: $placeSide) {
                    ForEach(ATHLTHCoachLandmarkSide.allCases) { side in
                        Text(side.title).tag(side)
                    }
                }
                .pickerStyle(.segmented)

                Button(action: searchForPlace) {
                    Label(searching
                          ? ATHLTHLocalization.choose(english: "Searching", norwegian: "Søker")
                          : ATHLTHLocalization.choose(english: "Find place", norwegian: "Finn sted"),
                          systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(searching || placeSearch.trimmingCharacters(
                    in: .whitespacesAndNewlines).isEmpty)

                if let placeError {
                    Text(placeError).font(.caption).foregroundStyle(.secondary)
                }
                ForEach(foundPlaces) { candidate in
                    Button {
                        settings.audioCoachSmartSettings.landmarks.append(
                            ATHLTHCoachLandmark(
                                name: candidate.name,
                                latitude: candidate.latitude,
                                longitude: candidate.longitude,
                                side: placeSide
                            )
                        )
                        foundPlaces = []
                        placeSearch = ""
                        placeError = nil
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(candidate.name).font(.subheadline.weight(.semibold))
                                Text(candidate.detail).font(.caption)
                                    .foregroundStyle(ATHLTHTheme.mutedText)
                            }
                            Spacer()
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(ATHLTHTheme.accentDeep)
                        }
                        .foregroundStyle(ATHLTHTheme.primaryText)
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .disabled(settings.audioCoachSmartSettings.landmarks.count >= 30)
                }
                info(ATHLTHLocalization.choose(
                    english: "Outdoor GPS only. The selected side is read as you entered it; it is not inferred from your direction of travel.",
                    norwegian: "Kun utendørs med god GPS. Valgt side leses slik du har angitt den, ikke beregnet ut fra løperetningen."
                ))
            }
        }
    }

    private func info(_ value: String) -> some View {
        Text(value)
            .font(.caption)
            .foregroundStyle(ATHLTHTheme.mutedText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func studioCard<Content: View>(
        title: String,
        subtitle: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                    .frame(width: 42, height: 42)
                    .background(ATHLTHTheme.accentSoft,
                                in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                        .foregroundStyle(ATHLTHTheme.primaryText)
                    Text(subtitle).font(.caption)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Divider()
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ATHLTHTheme.card, in: RoundedRectangle(cornerRadius: 25))
    }

    private func searchForPlace() {
        let query = placeSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !searching else { return }
        searching = true
        placeError = nil
        foundPlaces = []
        Task { @MainActor in
            var request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.resultTypes = [.pointOfInterest, .address]
            do {
                let response = try await MKLocalSearch(request: request).start()
                foundPlaces = response.mapItems.prefix(6).compactMap { item in
                    let point = item.placemark.coordinate
                    guard CLLocationCoordinate2DIsValid(point) else { return nil }
                    return ATHLTHAudioCoachPlaceCandidate(
                        name: item.name ?? query,
                        detail: item.placemark.title ?? "",
                        latitude: point.latitude,
                        longitude: point.longitude
                    )
                }
                if foundPlaces.isEmpty {
                    placeError = ATHLTHLocalization.choose(
                        english: "No matching places found. Try a more specific name.",
                        norwegian: "Fant ingen steder. Prøv et mer presist navn."
                    )
                }
            } catch {
                placeError = ATHLTHLocalization.choose(
                    english: "Place search is unavailable right now.",
                    norwegian: "Stedssøk er ikke tilgjengelig akkurat nå."
                )
            }
            searching = false
        }
    }
}
