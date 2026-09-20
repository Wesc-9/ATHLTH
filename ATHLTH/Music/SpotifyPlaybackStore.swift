import Foundation

struct SpotifyPlaylistReference: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var uri: String
    var artworkURL: URL?
    var ownerName: String?
}

@MainActor
final class SpotifyPlaybackStore: ObservableObject {
    @Published private(set) var activePlaylist: SpotifyPlaylistReference?
    @Published private(set) var lastStartedAt: Date?

    func startLinkedPlaylist(
        _ playlist: SpotifyPlaylistReference,
        settings: AppSettingsStore
    ) async {
        guard
            settings.spotifyConnected,
            settings.spotifyAutoplayLinkedPlaylists
        else {
            return
        }

        // Preview behavior until the Spotify App Remote implementation is connected.
        activePlaylist = playlist
        lastStartedAt = Date()
    }

    func stopPreviewPlaybackState() {
        activePlaylist = nil
        lastStartedAt = nil
    }
}
