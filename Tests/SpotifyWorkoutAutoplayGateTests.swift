import XCTest
@testable import ATHLTH

final class SpotifyWorkoutAutoplayGateTests: XCTestCase {
    @MainActor
    func testEnteringAppDoesNotReconnectAfterWorkoutEnds() {
        var gate = SpotifyWorkoutAutoplayGate()
        XCTAssertFalse(gate.shouldReconnectForControls)

        let started = gate.begin()
        XCTAssertTrue(gate.isCurrent(started))
        XCTAssertTrue(gate.shouldReconnectForControls)

        gate.end()
        XCTAssertFalse(gate.shouldReconnectForControls)
        XCTAssertFalse(gate.isCurrent(started))
    }

    @MainActor
    func testManualPauseCancelsPendingAutoplayAfterAppSwitch() {
        var gate = SpotifyWorkoutAutoplayGate()
        let request = gate.begin()
        gate.pause()

        XCTAssertFalse(gate.isCurrent(request))
        XCTAssertFalse(gate.shouldReconnectForControls)
        XCTAssertTrue(gate.wasManuallyPaused)

        // Pressing play later is a new user command, not permission for the
        // canceled request to play the original playlist again.
        gate.resumeControls()
        XCTAssertTrue(gate.shouldReconnectForControls)
        XCTAssertFalse(gate.isCurrent(request))
    }

    @MainActor
    func testLateAuthFromOldWorkoutCannotPlayInNewWorkout() {
        var gate = SpotifyWorkoutAutoplayGate()
        let first = gate.begin()
        gate.end()

        let second = gate.begin()
        XCTAssertNotEqual(first, second)
        XCTAssertFalse(gate.isCurrent(first))
        XCTAssertTrue(gate.isCurrent(second))
    }

    @MainActor
    func testNewPlaylistRequestInvalidatesOlderPendingRequest() {
        var gate = SpotifyWorkoutAutoplayGate()
        let first = gate.begin()
        let second = gate.begin()
        XCTAssertFalse(gate.isCurrent(first))
        XCTAssertTrue(gate.isCurrent(second))
    }

    @MainActor
    func testEndingWorkoutDoesNotRequirePausingSpotify() {
        var gate = SpotifyWorkoutAutoplayGate()
        _ = gate.begin()
        gate.end()

        // Linked playback can continue in Spotify after the workout.
        // The gate revokes ATHLTH's ability to issue a fresh autoplay.
        XCTAssertNil(gate.currentRequestID)
        XCTAssertFalse(gate.isWorkoutActive)
        XCTAssertFalse(gate.wasManuallyPaused)
    }
}
