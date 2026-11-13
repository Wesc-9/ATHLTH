import Foundation

/// Opt-in, reusable, user-curated song collections. No automatic Spotify
/// discovery, playlist changes or playback unless the athlete chooses one.
/// A profile travels inside the workout's optional interval-song field.
enum ATHLTHSpotifyMusicIntensity: String, Codable, CaseIterable, Identifiable {
    case easy
    case steady
    case hard

    var id: String { rawValue }
}

struct ATHLTHSpotifyMusicFavorite: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var artist: String
    var durationMilliseconds: Int
    var intensity: ATHLTHSpotifyMusicIntensity

    init(track: ATHLTHSpotifyIntervalTrack, intensity: ATHLTHSpotifyMusicIntensity) {
        self.id = track.id
        self.title = track.title
        self.artist = track.artist
        self.durationMilliseconds = track.durationMilliseconds
        self.intensity = intensity
    }

    var track: ATHLTHSpotifyIntervalTrack {
        ATHLTHSpotifyIntervalTrack(
            id: id, title: title, artist: artist,
            durationMilliseconds: durationMilliseconds
        )
    }
}

struct ATHLTHSpotifyMusicProfile: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var favorites: [ATHLTHSpotifyMusicFavorite]
    var preferFullLength: Bool = true
}

/// Scoring is entirely local and deterministic. A music hint never starts a
/// workout, changes workout time, or guesses a song the athlete did not save.
enum ATHLTHSpotifySmartMusicPolicy {
    static func intensity(for text: String?) -> ATHLTHSpotifyMusicIntensity {
        let input = (text ?? "").lowercased()
        if ["sone 1", "sone 2", "zone 1", "zone 2",
            "rolig", "easy", "recovery", "lett"].contains(where: input.contains) {
            return .easy
        }
        if ["sone 5", "sone 4", "zone 5", "zone 4",
            "maks", "hard", "sprint", "anaerob", "high", "rask"]
            .contains(where: input.contains) {
            return .hard
        }
        if ["sone 3", "zone 3", "tempo", "moderat", "steady", "threshold",
            "terskel"].contains(where: input.contains) {
            return .steady
        }
        // Work intervals with no explicit target are normally the hard portion.
        return .hard
    }

    static func select(
        from profile: ATHLTHSpotifyMusicProfile?,
        effortIndex: Int,
        targetDurationSeconds: TimeInterval?,
        intensityText: String?
    ) -> ATHLTHSpotifyIntervalTrack? {
        guard let profile, effortIndex >= 0 else { return nil }
        let wanted = intensity(for: intensityText)
        // Do not silently play a calming or unrelated song when no hard
        // favorite is supplied; the existing explicitly chosen track wins.
        let eligible = profile.favorites.filter {
            $0.intensity == wanted &&
            ATHLTHSpotifyIntervalCuePolicy.validSpotifyTrackID($0.track.uri) != nil
        }
        guard !eligible.isEmpty else { return nil }

        let target: Int? = targetDurationSeconds.flatMap { duration in
            guard duration.isFinite, duration > 0, duration < 86_400 else { return nil }
            return Int(duration * 1_000)
        }
        let ordered = eligible.sorted { lhs, rhs in
            let a = durationScore(lhs.durationMilliseconds, target, profile.preferFullLength)
            let b = durationScore(rhs.durationMilliseconds, target, profile.preferFullLength)
            if a != b { return a < b }
            return lhs.id < rhs.id
        }
        // Rotate among the three closest matches when there is a meaningful
        // duration target. With a single favorite every effort repeats it.
        let candidates = target == nil ? ordered : Array(ordered.prefix(3))
        return candidates[effortIndex % candidates.count].track
    }

    private static func durationScore(
        _ milliseconds: Int, _ target: Int?, _ preferFullLength: Bool
    ) -> Int {
        guard let target else { return 0 }
        guard milliseconds > 0 else { return Int.max / 2 }
        let delta = abs(milliseconds - target)
        // A song ending early is considerably worse than one slightly long.
        let shortfall = max(target - milliseconds, 0)
        let penalty = preferFullLength ? 4 : 1
        return delta + min(shortfall, 3_600_000) * penalty
    }
}
