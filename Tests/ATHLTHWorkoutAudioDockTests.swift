import XCTest
@testable import ATHLTH

final class ATHLTHWorkoutAudioDockTests: XCTestCase {
    func testCoachRemainsVisibleWhenSpotifyIsDisconnected() {
        XCTAssertTrue(ATHLTHWorkoutAudioDockPolicy.isVisible(
            coachVisible: true,
            spotifyConnected: false
        ))
        XCTAssertEqual(ATHLTHWorkoutAudioDockPolicy.resolvedMode(
            preferred: .spotify,
            coachVisible: true,
            spotifyConnected: false
        ), .coach)
    }

    func testSpotifyWorksWithoutCoach() {
        XCTAssertTrue(ATHLTHWorkoutAudioDockPolicy.isVisible(
            coachVisible: false,
            spotifyConnected: true
        ))
        XCTAssertEqual(ATHLTHWorkoutAudioDockPolicy.resolvedMode(
            preferred: .coach,
            coachVisible: false,
            spotifyConnected: true
        ), .spotify)
    }

    func testBothSourcesHaveIndependentSelectableControls() {
        XCTAssertEqual(ATHLTHWorkoutAudioDockPolicy.resolvedMode(
            preferred: .coach,
            coachVisible: true,
            spotifyConnected: true
        ), .coach)
        XCTAssertEqual(ATHLTHWorkoutAudioDockPolicy.resolvedMode(
            preferred: .spotify,
            coachVisible: true,
            spotifyConnected: true
        ), .spotify)
    }

    func testAudioDockDisappearsWithoutEitherSource() {
        XCTAssertFalse(ATHLTHWorkoutAudioDockPolicy.isVisible(
            coachVisible: false,
            spotifyConnected: false
        ))
    }
}
