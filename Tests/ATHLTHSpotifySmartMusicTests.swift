import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHSpotifySmartMusicTests: XCTestCase {
    private let id1 = "2TpxZ7JUBn3uw46aR7qd6V"
    private let id2 = "3n3Ppam7vgaVa1iaRUc9Lp"
    private let id3 = "4uLU6hMCjMI75M1A2tKUQC"

    private func favorite(
        _ id: String, duration: Int, intensity: ATHLTHSpotifyMusicIntensity
    ) -> ATHLTHSpotifyMusicFavorite {
        .init(
            track: .init(id: id, title: id, artist: "Artist",
                         durationMilliseconds: duration),
            intensity: intensity
        )
    }

    func testNoSetupKeepsOneTrackPerIntervalBehaviour() {
        XCTAssertNil(ATHLTHSpotifySmartMusicPolicy.select(
            from: nil, effortIndex: 0,
            targetDurationSeconds: 240, intensityText: "Zone 4"
        ))
    }

    func testPreferredSongCoversFourMinuteEffort() {
        let profile = ATHLTHSpotifyMusicProfile(
            name: "4 x 4",
            favorites: [
                favorite(id1, duration: 205_000, intensity: .hard),
                favorite(id2, duration: 246_000, intensity: .hard)
            ]
        )
        XCTAssertEqual(
            ATHLTHSpotifySmartMusicPolicy.select(
                from: profile, effortIndex: 0,
                targetDurationSeconds: 240, intensityText: "Sone 4"
            )?.id,
            id2
        )
    }

    func testIntensityNeverChoosesWrongMood() {
        let profile = ATHLTHSpotifyMusicProfile(
            name: "Easy and hard",
            favorites: [
                favorite(id1, duration: 230_000, intensity: .easy),
                favorite(id2, duration: 245_000, intensity: .hard)
            ]
        )
        XCTAssertEqual(ATHLTHSpotifySmartMusicPolicy.select(
            from: profile, effortIndex: 0,
            targetDurationSeconds: 240, intensityText: "rolig sone 2"
        )?.id, id1)
        XCTAssertEqual(ATHLTHSpotifySmartMusicPolicy.select(
            from: profile, effortIndex: 0,
            targetDurationSeconds: 240, intensityText: "sprint"
        )?.id, id2)
        XCTAssertNil(ATHLTHSpotifySmartMusicPolicy.select(
            from: profile, effortIndex: 0,
            targetDurationSeconds: 240, intensityText: "terskel"
        ))
    }

    func testRotationIsStableAndNeverUsesUnselectedSongs() {
        let profile = ATHLTHSpotifyMusicProfile(
            name: "Three favorites",
            favorites: [
                favorite(id1, duration: 242_000, intensity: .hard),
                favorite(id2, duration: 243_000, intensity: .hard),
                favorite(id3, duration: 245_000, intensity: .hard)
            ]
        )
        let ids = (0..<4).compactMap { index in
            ATHLTHSpotifySmartMusicPolicy.select(
                from: profile, effortIndex: index,
                targetDurationSeconds: 240, intensityText: "hard"
            )?.id
        }
        XCTAssertEqual(Set(ids.prefix(3)).count, 3)
        XCTAssertEqual(ids[0], ids[3])
    }

    func testOldWorkoutTrackStillDecodesWithoutSmartMusic() throws {
        let json = """
        {"id":"2TpxZ7JUBn3uw46aR7qd6V","title":"Favorite",
        "artist":"Artist","durationMilliseconds":245000}
        """.data(using: .utf8)!
        let restored = try JSONDecoder().decode(
            ATHLTHSpotifyIntervalTrack.self, from: json
        )
        XCTAssertNil(restored.smartProfile)
        XCTAssertEqual(restored.title, "Favorite")
    }

    func testMusicProfileRoundTripRetainsDurationsAndIntensity() throws {
        var track = ATHLTHSpotifyIntervalTrack(
            id: id1, title: "Favorite", artist: "Artist",
            durationMilliseconds: 246_000
        )
        track.smartProfile = ATHLTHSpotifyMusicProfile(
            name: "My intervals",
            favorites: [favorite(id2, duration: 248_000, intensity: .hard)]
        )
        let restored = try JSONDecoder().decode(
            ATHLTHSpotifyIntervalTrack.self,
            from: JSONEncoder().encode(track)
        )
        XCTAssertEqual(restored, track)
    }

    func testNeverPlaysInvalidSongIdentifierOrBadDuration() {
        let profile = ATHLTHSpotifyMusicProfile(
            name: "Invalid",
            favorites: [
                favorite("bad", duration: 240_000, intensity: .hard),
                favorite(id1, duration: -99, intensity: .hard)
            ]
        )
        XCTAssertNil(ATHLTHSpotifySmartMusicPolicy.select(
            from: profile, effortIndex: -1,
            targetDurationSeconds: 240, intensityText: "hard"
        ))
        XCTAssertEqual(ATHLTHSpotifySmartMusicPolicy.select(
            from: profile, effortIndex: 0,
            targetDurationSeconds: 240, intensityText: "hard"
        )?.id, id1)
    }
}
