import SwiftUI

/// Spotify for this workout, using the existing authenticated playlist picker.
/// A selection remains in the workout draft until explicitly saved.
struct ATHLTHWorkoutSpotifyOptionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var playlist: SpotifyPlaylistReference?
    @Binding var autoplay: Bool?
    @State private var showingPlaylistPicker = false

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
                } footer: {
                    Text(tr(
                        "Spotify requires a connected account. Your music selection is saved with this workout, not played until the workout starts.",
                        "Spotify krever en tilkoblet konto. Spillelisten lagres med økten og spilles først når økten starter."
                    ))
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
            .onChange(of: playlist?.id) { oldID, newID in
                if newID == nil && oldID != nil { autoplay = false }
                if newID != nil && autoplay == nil { autoplay = true }
            }
        }
    }
}
