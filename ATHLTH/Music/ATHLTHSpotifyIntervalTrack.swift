import Foundation

/// An optional, athlete-chosen Spotify track for timed running efforts.
/// A workout with no selection behaves exactly as it did before.
struct ATHLTHSpotifyIntervalTrack: Identifiable, Codable, Hashable {
    let id: String
    var title: String
    var artist: String
    var durationMilliseconds: Int

    var uri: String { "spotify:track:\(id)" }
    var durationLabel: String {
        guard durationMilliseconds > 0 else { return "—" }
        let seconds = max(0, durationMilliseconds / 1_000)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// Presentation and routing only. Audio Coach / the running engine own all
/// clocks, cue timing, and recording. The music choice can never block them.
enum ATHLTHSpotifyIntervalCuePolicy {
    static func isEffort(_ phase: String?) -> Bool {
        phase == "work" || phase == "interval"
    }

    static func validSpotifyTrackID(_ input: String) -> String? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let identifier: String
        if value.hasPrefix("spotify:track:") {
            identifier = String(value.dropFirst("spotify:track:".count))
        } else if let components = URLComponents(string: value),
                  components.scheme == "https",
                  components.host == "open.spotify.com",
                  let path = components.path.split(separator: "/").last,
                  components.path.split(separator: "/").contains("track") {
            identifier = String(path)
        } else {
            return nil
        }
        let characters = CharacterSet(charactersIn:
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        guard identifier.count == 22,
              identifier.unicodeScalars.allSatisfy({ characters.contains($0) })
        else { return nil }
        return identifier
    }

    static func shouldPlay(
        phase: String?,
        stepIndex: Int,
        previouslyPlayed: Set<Int>,
        manuallyPaused: Bool
    ) -> Bool {
        !manuallyPaused && stepIndex >= 0 && isEffort(phase)
            && !previouslyPlayed.contains(stepIndex)
    }
}
