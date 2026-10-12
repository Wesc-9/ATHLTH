import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHLiveGhostWatchSignalTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func context(
        gap: Double? = 62,
        age: TimeInterval = 2,
        connection: String? = "LIVE",
        progress: Double? = 34,
        opponentProgress: Double? = 30
    ) -> ATHLTHLiveGhostContext {
        ATHLTHLiveGhostContext(
            title: "Rival",
            distanceDeltaMeters: gap,
            estimatedTimeDeltaSeconds: 11,
            updatedAt: now.addingTimeInterval(-age),
            opponentName: "Rival",
            ownProgressPercent: progress,
            opponentProgressPercent: opponentProgress,
            connectionText: connection
        )
    }

    private func signal(
        _ context: ATHLTHLiveGhostContext?,
        paused: Bool = false
    ) -> ATHLTHLiveGhostWatchSignal {
        ATHLTHLiveGhostWatchSignal.resolve(
            context: context, isPaused: paused, now: now
        )
    }

    func testFreshLiveOpponentCanDisplayGapAndAnnouncePassing() {
        XCTAssertEqual(signal(context()), .live)
        XCTAssertTrue(signal(context()).mayAnnouncePassing)
    }

    func testWatchPauseKeepsDuelButSuppressesPassing() {
        let result = signal(context(), paused: true)
        XCTAssertEqual(result, .paused)
        XCTAssertFalse(result.mayAnnouncePassing)
    }

    func testStaleLocationHidesFormerLeadAfterConnectionLoss() {
        XCTAssertEqual(signal(context(age: 18.1)), .delayed)
        XCTAssertFalse(signal(context(age: 18.1)).mayAnnouncePassing)
        XCTAssertEqual(signal(context(age: 300)), .delayed)
    }

    func testConnectionStatusOverridesApparentlyFreshDistance() {
        XCTAssertEqual(signal(context(connection: "RECONNECTING")), .delayed)
        XCTAssertEqual(signal(context(connection: "DELAYED")), .delayed)
        XCTAssertEqual(signal(context(connection: "WAITING")), .waiting)
        XCTAssertEqual(signal(context(connection: nil)), .waiting)
    }

    func testMissingGhostDataWaitsInsteadOfInventingOpponent() {
        XCTAssertEqual(signal(nil), .waiting)
        XCTAssertEqual(signal(context(gap: nil)), .waiting)
        XCTAssertFalse(signal(context(gap: nil)).mayAnnouncePassing)
    }

    func testCorruptedGapAndProgressNeverLookLive() {
        XCTAssertEqual(signal(context(gap: .nan)), .waiting)
        XCTAssertEqual(signal(context(gap: .infinity)), .waiting)
        XCTAssertEqual(signal(context(progress: 130)), .waiting)
        XCTAssertEqual(signal(context(opponentProgress: -.infinity)), .waiting)
    }

    func testDistanceOnlyDuelDoesNotRequireMapProgress() {
        XCTAssertEqual(signal(context(progress: nil, opponentProgress: nil)), .live)
    }

    func testClockSkewAndMissingUpdatesNeverShowLivePass() {
        XCTAssertEqual(signal(context(age: -6)), .delayed)
        XCTAssertEqual(signal(context(age: .infinity)), .delayed)
    }
}
