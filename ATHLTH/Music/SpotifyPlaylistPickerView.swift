import SwiftUI

struct SpotifyPlaylistPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var spotify: SpotifyPlaybackStore

    @Binding var selection: SpotifyPlaylistReference?
    let title: String

    init(
        title: String = "Choose Playlist",
        selection: Binding<SpotifyPlaylistReference?>
    ) {
        self.title = title
        _selection = selection
    }

    var body: some View {
        NavigationStack {
            Group {
                if !spotify.isConfigured {
                    ContentUnavailableView(
                        "Spotify Setup Required",
                        systemImage: "music.note",
                        description: Text(
                            spotify.setupMessage
                                ?? "Spotify is not configured for this build."
                        )
                    )
                } else if !spotify.isConnected {
                    VStack(spacing: 18) {
                        ContentUnavailableView(
                            "Connect Spotify",
                            systemImage: "music.note",
                            description: Text(
                                "Connect Spotify to choose one of your playlists for this workout or program."
                            )
                        )

                        Button("Connect Spotify") {
                            spotify.connect()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                } else if spotify.isRefreshingPlaylists &&
                            spotify.playlists.isEmpty {
                    ProgressView("Loading playlists…")
                } else {
                    List {
                        Section {
                            Button {
                                selection = nil
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "speaker.slash")
                                        .frame(width: 46, height: 46)
                                        .background(
                                            Color.secondary.opacity(0.08),
                                            in: RoundedRectangle(
                                                cornerRadius: 10,
                                                style: .continuous
                                            )
                                        )

                                    VStack(
                                        alignment: .leading,
                                        spacing: 2
                                    ) {
                                        Text(
                                            ATHLTHLocalization.choose(
                                                english: "Don't link a playlist",
                                                norwegian: "Ikke koble spilleliste"
                                            )
                                        )
                                        .foregroundStyle(.primary)

                                        Text(
                                            ATHLTHLocalization.choose(
                                                english: "Spotify stays off for this choice",
                                                norwegian: "Spotify forblir av for dette valget"
                                            )
                                        )
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    if selection == nil {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(ATHLTHTheme.accentDeep)
                                    }
                                }
                            }
                        }

                        Section("Your Spotify Playlists") {
                            ForEach(spotify.playlists) { playlist in
                                Button {
                                    selection = playlist
                                    dismiss()
                                } label: {
                                    HStack(spacing: 12) {
                                        playlistArtwork(playlist)

                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(playlist.name)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(.primary)
                                                .lineLimit(2)

                                            if let owner = playlist.ownerName,
                                               !owner.isEmpty {
                                                Text(owner)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                            }
                                        }

                                        Spacer()

                                        if selection?.id == playlist.id {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(ATHLTHTheme.accentDeep)
                                        }
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .refreshable {
                        await spotify.refreshPlaylists()
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if spotify.isConnected {
                        Button {
                            Task {
                                await spotify.refreshPlaylists()
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(spotify.isRefreshingPlaylists)
                    }
                }
            }
            .task {
                if spotify.isConnected && spotify.playlists.isEmpty {
                    await spotify.refreshPlaylists()
                }
            }
        }
    }

    @ViewBuilder
    private func playlistArtwork(
        _ playlist: SpotifyPlaylistReference
    ) -> some View {
        if let artworkURL = playlist.artworkURL {
            AsyncImage(url: artworkURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    artworkFallback
                }
            }
            .frame(width: 46, height: 46)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 10,
                    style: .continuous
                )
            )
        } else {
            artworkFallback
                .frame(width: 46, height: 46)
        }
    }

    private var artworkFallback: some View {
        RoundedRectangle(
            cornerRadius: 10,
            style: .continuous
        )
        .fill(Color.secondary.opacity(0.08))
        .overlay {
            Image(systemName: "music.note")
                .foregroundStyle(ATHLTHTheme.accentDeep)
        }
    }
}
