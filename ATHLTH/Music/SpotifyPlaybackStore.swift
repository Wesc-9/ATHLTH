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
        // Spotify playback stays disabled until the real authorization and
        // App Remote flow is implemented. Never simulate a successful start.
        activePlaylist = nil
        lastStartedAt = nil
    }

    func stopPreviewPlaybackState() {
        activePlaylist = nil
        lastStartedAt = nil
    }
}
