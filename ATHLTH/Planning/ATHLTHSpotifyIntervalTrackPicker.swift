import SwiftUI

/// Opened only when the athlete explicitly asks for interval music.
/// Spotify remains an optional accessory, never part of the workout flow.
struct ATHLTHSpotifyIntervalTrackPicker: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var spotify: SpotifyPlaybackStore
    @Binding var selection: ATHLTHSpotifyIntervalTrack?

    @State private var searchText = ""
    @State private var pastedLink = ""
    @State private var results: [ATHLTHSpotifyIntervalTrack] = []
    @State private var busy = false
    @State private var message: String?

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 9) {
                        TextField(
                            tr("Song or artist", "Sang eller artist"),
                            text: $searchText
                        )
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                        Button {
                            Task { await search() }
                        } label: {
                            if busy {
                                ProgressView()
                            } else {
                                Image(systemName: "magnifyingglass")
                            }
                        }
                        .disabled(busy || searchText.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).count < 2)
                        .accessibilityLabel(tr("Find songs", "Finn sanger"))
                    }

                    ForEach(results) { track in
                        Button {
                            selection = track
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "music.note")
                                    .foregroundStyle(ATHLTHTrainDesign.bronze)
                                    .frame(width: 25)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(track.title)
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                    Text(track.artist)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 6)
                                Text(track.durationLabel)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text(tr("Choose a favorite song", "Velg favorittsang"))
                } footer: {
                    Text(tr(
                        "A selected song is requested from the beginning for every work interval. The workout never waits for Spotify.",
                        "Den valgte sangen forsøkes startet fra begynnelsen ved hvert arbeidsdrag. Treningsøkten venter aldri på Spotify."
                    ))
                }

                Section {
                    TextField(
                        tr("Spotify track link", "Spotify-lenke til sangen"),
                        text: $pastedLink
                    )
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                    Button(tr("Use this song", "Bruk denne sangen")) {
                        Task { await importLink() }
                    }
                    .disabled(
                        busy || ATHLTHSpotifyIntervalCuePolicy
                            .validSpotifyTrackID(pastedLink) == nil
                    )
                } header: {
                    Text(tr("Or paste a link", "Eller lim inn lenke"))
                }

                if let message {
                    Section {
                        Label(message, systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(tr("Interval song", "Intervallsang"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Close", "Lukk")) { dismiss() }
                }
            }
        }
    }

    @MainActor
    private func search() async {
        guard !busy else { return }
        busy = true
        message = nil
        defer { busy = false }
        do {
            results = try await spotify.searchIntervalTracks(searchText)
            if results.isEmpty {
                message = tr("No songs found.", "Fant ingen sanger.")
            }
        } catch {
            results = []
            message = tr(
                "Spotify search is unavailable. You can also paste a song link.",
                "Spotify-søk er utilgjengelig. Du kan også lime inn en sanglenke."
            )
        }
    }

    @MainActor
    private func importLink() async {
        guard !busy else { return }
        busy = true
        message = nil
        defer { busy = false }
        do {
            selection = try await spotify.resolveIntervalTrackLink(pastedLink)
            dismiss()
        } catch {
            message = tr(
                "Could not read this Spotify track. Check your Spotify connection.",
                "Kunne ikke hente sangen. Kontroller Spotify-tilkoblingen."
            )
        }
    }
}
