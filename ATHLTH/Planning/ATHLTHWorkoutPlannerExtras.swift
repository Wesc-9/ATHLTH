import Foundation

/// Optional workout-level integrations. Nil means an existing program default
/// can still apply; an explicit false autoplay overrides that default.
struct ATHLTHWorkoutPlannerExtras: Codable, Hashable {
    var gearIDs: [UUID]? = nil
    var spotifyPlaylist: SpotifyPlaylistReference? = nil
    var spotifyAutoplayOnStart: Bool? = nil
}
