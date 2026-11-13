import SwiftUI

/// Advanced music is deliberately hidden behind the existing Spotify disclosure
/// and entirely opt-in. No Spotify request is made just by opening this screen.
struct ATHLTHSpotifySmartMusicSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore
    @Binding var selection: ATHLTHSpotifyIntervalTrack?

    @State private var saved: [ATHLTHSpotifyMusicProfile] = []
    @State private var draft = ATHLTHSpotifyMusicProfile(
        name: "Mine intervaller", favorites: []
    )
    @State private var nextIntensity: ATHLTHSpotifyMusicIntensity = .hard
    @State private var pickedTrack: ATHLTHSpotifyIntervalTrack?
    @State private var showTrackPicker = false
    @State private var message: String?

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    private func label(_ intensity: ATHLTHSpotifyMusicIntensity) -> String {
        switch intensity {
        case .easy: return tr("Easy", "Rolig")
        case .steady: return tr("Steady", "Moderat")
        case .hard: return tr("Hard", "Hardt")
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if saved.isEmpty {
                        Text(tr(
                            "No saved music setups yet.",
                            "Ingen lagrede musikkoppsett ennå."
                        ))
                        .foregroundStyle(.secondary)
                    }
                    ForEach(saved) { profile in
                        Button {
                            apply(profile)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "music.note.list")
                                    .foregroundStyle(ATHLTHTrainDesign.bronze)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(profile.name).foregroundStyle(.primary)
                                    Text(tr(
                                        "\(profile.favorites.count) favorite songs",
                                        "\(profile.favorites.count) favorittsanger"
                                    ))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete(perform: removeSaved)
                } header: {
                    Text(tr("Saved music setups", "Lagrede musikkoppsett"))
                } footer: {
                    Text(tr(
                        "Choose a saved setup to use it for this workout. Existing workouts keep their own settings.",
                        "Velg et lagret oppsett for denne økten. Andre økter beholder sine egne musikkvalg."
                    ))
                }

                Section {
                    TextField(tr("Name", "Navn"), text: $draft.name)
                        .textInputAutocapitalization(.sentences)

                    Toggle(
                        tr("Prefer songs that last the full interval",
                           "Foretrekk sanger som varer hele draget"),
                        isOn: $draft.preferFullLength
                    )
                    .tint(ATHLTHTrainDesign.bronze)

                    Picker(
                        tr("Intensity for next song", "Intensitet for neste sang"),
                        selection: $nextIntensity
                    ) {
                        ForEach(ATHLTHSpotifyMusicIntensity.allCases) { value in
                            Text(label(value)).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)

                    Button {
                        showTrackPicker = true
                    } label: {
                        Label(tr("Add favorite song", "Legg til favorittsang"),
                              systemImage: "plus")
                    }
                    .disabled(draft.favorites.count >= 20)

                    ForEach(draft.favorites) { favorite in
                        HStack(spacing: 10) {
                            Image(systemName: "music.note")
                                .foregroundStyle(ATHLTHTrainDesign.bronze)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(favorite.title).lineLimit(1)
                                Text(favorite.artist)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 4)
                            Text(label(favorite.intensity))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { offsets in
                        draft.favorites.remove(atOffsets: offsets)
                    }

                    Button {
                        saveAndApply()
                    } label: {
                        Label(tr("Save and use", "Lagre og bruk"),
                              systemImage: "checkmark")
                            .fontWeight(.semibold)
                    }
                    .disabled(draft.favorites.isEmpty ||
                        draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } header: {
                    Text(tr("My interval music", "Min intervallmusikk"))
                } footer: {
                    Text(tr(
                        "ATHLTH only chooses among songs you add. It uses the interval's planned duration and intensity and never interrupts the workout if Spotify is unavailable.",
                        "ATHLTH velger kun blant sangene du legger til. Valget baseres på dragets planlagte varighet og intensitet. Treningsøkten fortsetter alltid selv om Spotify er utilgjengelig."
                    ))
                }

                if let message {
                    Section {
                        Label(message, systemImage: "info.circle")
                            .font(.caption)
                    }
                }
            }
            .navigationTitle(tr("Music setups", "Musikkoppsett"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Close", "Lukk")) { dismiss() }
                }
            }
            .sheet(isPresented: $showTrackPicker) {
                ATHLTHSpotifyIntervalTrackPicker(selection: $pickedTrack)
            }
            .onChange(of: pickedTrack?.id) { _, _ in
                guard let pickedTrack,
                      !draft.favorites.contains(where: { $0.id == pickedTrack.id }),
                      draft.favorites.count < 20 else {
                    self.pickedTrack = nil
                    return
                }
                draft.favorites.append(ATHLTHSpotifyMusicFavorite(
                    track: pickedTrack, intensity: nextIntensity
                ))
                self.pickedTrack = nil
            }
            .onAppear {
                if session.signedIn {
                    saved = AccountLocalStorage.read(
                        [ATHLTHSpotifyMusicProfile].self,
                        name: "spotifyMusicPresets",
                        userID: session.profile.userID
                    ) ?? []
                }
                if let active = selection?.smartProfile { draft = active }
            }
        }
    }

    private func apply(_ profile: ATHLTHSpotifyMusicProfile) {
        guard !profile.favorites.isEmpty else { return }
        var track = selection ?? (
            profile.favorites.first(where: { $0.intensity == .hard }) ??
            profile.favorites[0]
        ).track
        track.smartProfile = profile
        selection = track
        dismiss()
    }

    private func saveAndApply() {
        guard session.signedIn else {
            message = tr(
                "Sign in to save this music setup.",
                "Logg inn for å lagre dette musikkoppsettet."
            )
            return
        }
        guard !draft.favorites.isEmpty else { return }
        draft.name = String(
            draft.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(64)
        )
        guard !draft.name.isEmpty else { return }
        if let index = saved.firstIndex(where: { $0.id == draft.id }) {
            saved[index] = draft
        } else {
            saved.append(draft)
        }
        persistSaved()
        apply(draft)
    }

    private func removeSaved(at offsets: IndexSet) {
        saved.remove(atOffsets: offsets)
        persistSaved()
    }

    private func persistSaved() {
        guard session.signedIn else {
            message = tr(
                "Sign in to save music setups for future workouts.",
                "Logg inn for å lagre musikkoppsett til senere økter."
            )
            return
        }
        AccountLocalStorage.write(
            saved, name: "spotifyMusicPresets",
            userID: session.profile.userID
        )
    }
}
