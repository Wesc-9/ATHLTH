import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHSpotifyIntervalCuePolicyTests: XCTestCase {
    private let exampleID = "2TpxZ7JUBn3uw46aR7qd6V"

    func testSpotifyTrackLinkParsesWithoutQueryString() {
        XCTAssertEqual(
            ATHLTHSpotifyIntervalCuePolicy.validSpotifyTrackID(
                "https://open.spotify.com/track/\(exampleID)?si=abc123"
            ),
            exampleID
        )
        XCTAssertEqual(
            ATHLTHSpotifyIntervalCuePolicy.validSpotifyTrackID(
                "spotify:track:\(exampleID)"
            ),
            exampleID
        )
    }

    func testOnlyRealSpotifyTrackLinksAccepted() {
        XCTAssertNil(ATHLTHSpotifyIntervalCuePolicy.validSpotifyTrackID(
            "https://open.spotify.com/playlist/\(exampleID)"
        ))
        XCTAssertNil(ATHLTHSpotifyIntervalCuePolicy.validSpotifyTrackID(
            "https://notspotify.example.com/track/\(exampleID)"
        ))
        XCTAssertNil(ATHLTHSpotifyIntervalCuePolicy.validSpotifyTrackID(
            "spotify:track:../../music"
        ))
    }

    func testSongOnlyStartsForActualRunningWorkSteps() {
        for phase in ["work", "interval"] {
            XCTAssertTrue(ATHLTHSpotifyIntervalCuePolicy.shouldPlay(
                phase: phase, stepIndex: 3, previouslyPlayed: [], manuallyPaused: false
            ))
        }
        for phase in ["warmup", "recovery", "cooldown", "free", nil] {
            XCTAssertFalse(ATHLTHSpotifyIntervalCuePolicy.shouldPlay(
                phase: phase, stepIndex: 3, previouslyPlayed: [], manuallyPaused: false
            ))
        }
    }

    func testDuplicateTransitionsNeverRestartTrack() {
        XCTAssertFalse(ATHLTHSpotifyIntervalCuePolicy.shouldPlay(
            phase: "work", stepIndex: 2, previouslyPlayed: [2], manuallyPaused: false
        ))
    }

    func testManualPauseSuppressesAutomaticTrackChange() {
        XCTAssertFalse(ATHLTHSpotifyIntervalCuePolicy.shouldPlay(
            phase: "work", stepIndex: 4, previouslyPlayed: [], manuallyPaused: true
        ))
    }

    func testSongSelectionRoundTripsAndDurationIsReadable() throws {
        let track = ATHLTHSpotifyIntervalTrack(
            id: exampleID, title: "My favorite", artist: "Artist",
            durationMilliseconds: 240_000
        )
        XCTAssertEqual(track.durationLabel, "4:00")
        XCTAssertEqual(track.uri, "spotify:track:\(exampleID)")
        let restored = try JSONDecoder().decode(
            ATHLTHSpotifyIntervalTrack.self,
            from: JSONEncoder().encode(track)
        )
        XCTAssertEqual(restored, track)
    }
}
