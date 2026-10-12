import Foundation
import XCTest
@testable import ATHLTH

/// Live Ghost may start a NEW iPhone/Watch workout only after the
/// synchronized server countdown and both READY replies agree.
final class LiveGhostSynchronizedLaunchGateTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    func testBothReadyAtServerCountdownStartAllowsOneLaunch() {
        XCTAssertTrue(LiveGhostSynchronizedLaunchGate.mayLaunch(
            status: .countdown,
            startsAt: start,
            ownReady: true,
            opponentReady: true,
            now: start
        ))
        XCTAssertTrue(LiveGhostSynchronizedLaunchGate.mayLaunch(
            status: .racing,
            startsAt: start,
            ownReady: true,
            opponentReady: true,
            now: start.addingTimeInterval(2)
        ))
    }

    func testOpponentRevokingReadyBlocksNewWorkout() {
        XCTAssertFalse(LiveGhostSynchronizedLaunchGate.mayLaunch(
            status: .countdown,
            startsAt: start,
            ownReady: true,
            opponentReady: false,
            now: start
        ))
        XCTAssertFalse(LiveGhostSynchronizedLaunchGate.mayLaunch(
            status: .racing,
            startsAt: start,
            ownReady: false,
            opponentReady: true,
            now: start
        ))
    }

    func testCancelledFinishedAndLobbyRoomsNeverLaunch() {
        for status: LiveGhostRaceRoomStatus in [.cancelled, .finished, .lobby] {
            XCTAssertFalse(LiveGhostSynchronizedLaunchGate.mayLaunch(
                status: status,
                startsAt: start,
                ownReady: true,
                opponentReady: true,
                now: start
            ))
        }
    }

    func testCannotLaunchBeforeSynchronizedStart() {
        XCTAssertFalse(LiveGhostSynchronizedLaunchGate.mayLaunch(
            status: .countdown,
            startsAt: start,
            ownReady: true,
            opponentReady: true,
            now: start.addingTimeInterval(-0.1)
        ))
    }

    func testExpiredCountdownRequiresReconnectNotNewWorkout() {
        XCTAssertTrue(LiveGhostSynchronizedLaunchGate.mayLaunch(
            status: .racing,
            startsAt: start,
            ownReady: true,
            opponentReady: true,
            now: start.addingTimeInterval(15)
        ))
        XCTAssertFalse(LiveGhostSynchronizedLaunchGate.mayLaunch(
            status: .racing,
            startsAt: start,
            ownReady: true,
            opponentReady: true,
            now: start.addingTimeInterval(15.01)
        ))
    }

    func testMissingRoomOrStartTimeCannotLaunch() {
        XCTAssertFalse(LiveGhostSynchronizedLaunchGate.mayLaunch(
            status: nil,
            startsAt: start,
            ownReady: true,
            opponentReady: true,
            now: start
        ))
        XCTAssertFalse(LiveGhostSynchronizedLaunchGate.mayLaunch(
            status: .racing,
            startsAt: nil,
            ownReady: true,
            opponentReady: true,
            now: start
        ))
    }
}
