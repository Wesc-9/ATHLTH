import SwiftUI

/// Spotify for this workout, using the existing authenticated playlist picker.
/// A selection remains in the workout draft until explicitly saved.
struct ATHLTHWorkoutSpotifyOptionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var playlist: SpotifyPlaylistReference?
    @Binding var autoplay: Bool?
    @Binding var intervalTrack: ATHLTHSpotifyIntervalTrack?
    let supportsIntervals: Bool
    @State private var showingPlaylistPicker = false
    @State private var showingIntervalTrackPicker = false
    @State private var intervalOptionsExpanded = false

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        showingPlaylistPicker = true
                    } label: {
                        HStack {
                            Label(tr("Playlist", "Spilleliste"), systemImage: "music.note.list")
                            Spacer()
                            Text(playlist?.name ?? tr("Choose", "Velg"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Toggle(
                        tr("Start music with workout", "Start musikk med økten"),
                        isOn: Binding(
                            get: { autoplay == true },
                            set: { autoplay = $0 }
                        )
                    )
                    .disabled(playlist == nil)
                    .tint(ATHLTHTrainDesign.bronze)
                }

                // Hidden for non-running workouts and collapsed otherwise.
                // Spotify is never a mandatory step in training setup.
                if supportsIntervals {
                Section {
                    DisclosureGroup(
                        isExpanded: $intervalOptionsExpanded
                    ) {
                        Button {
                            showingIntervalTrackPicker = true
                        } label: {
                            HStack(spacing: 9) {
                                Image(systemName: "music.note")
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(intervalTrack?.title ?? tr(
                                        "Choose a song", "Velg en sang"
                                    ))
                                        .foregroundStyle(.primary)
                                    if let intervalTrack {
                                        Text("\(intervalTrack.artist) · \(intervalTrack.durationLabel)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if intervalTrack != nil {
                            Button(tr("Remove interval song", "Fjern intervallsang")) {
                                intervalTrack = nil
                            }
                            .font(.subheadline)
                        }
                        Text(tr(
                            "Optional: start your favorite song from 0:00 for each work interval on iPhone. Spotify may start slightly late. Watch playback is unchanged.",
                            "Valgfritt: start favorittsangen fra 0:00 på hvert arbeidsdrag på iPhone. Spotify kan starte litt forsinket. Avspilling på Apple Watch endres ikke."
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    } label: {
                        HStack {
                            Label(
                                tr("Song for intervals", "Sang på drag"),
                                systemImage: "waveform"
                            )
                            Spacer()
                            if !intervalOptionsExpanded {
                                Text(intervalTrack == nil
                                     ? tr("Off", "Av")
                                     : tr("Selected", "Valgt"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text(tr("Optional", "Valgfritt"))
                }
                }

                Section {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(tr(
                            "Your playlist is saved with this workout. On iPhone it can play when the workout starts.",
                            "Spillelisten lagres sammen med økten. På iPhone kan den starte når økten starter."
                        ))
                        Label(tr(
                            "Apple Watch: Start Spotify directly on your Watch, using headphones paired with the Watch. ATHLTH won't autoplay on a previously used Spotify Connect speaker.",
                            "Apple Watch: Start Spotify direkte på klokken, med hodetelefoner koblet til klokken. ATHLTH starter ikke musikk på en tidligere brukt Spotify Connect-høyttaler."
                        ), systemImage: "applewatch")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Spotify")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Done", "Ferdig")) { dismiss() }
                }
            }
            .sheet(isPresented: $showingPlaylistPicker) {
                SpotifyPlaylistPickerView(
                    title: tr("Workout playlist", "Spilleliste for økten"),
                    selection: $playlist
                )
            }
            .sheet(isPresented: $showingIntervalTrackPicker) {
                ATHLTHSpotifyIntervalTrackPicker(selection: $intervalTrack)
            }
            .onChange(of: playlist?.id) { oldID, newID in
                if newID == nil && oldID != nil { autoplay = false }
                if newID != nil && autoplay == nil { autoplay = true }
            }
        }
    }
}
