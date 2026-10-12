import Foundation
import XCTest
@testable import ATHLTH

final class LiveGhostWatchReconnectTests: XCTestCase {
    func testMatchingActiveWatchDuelsCanReconnectWithoutRestart() {
        let duel = UUID()
        XCTAssertTrue(LiveGhostRaceReentry.canReconnectWatchWorkout(
            comparisonRouteID: duel,
            challengeID: duel,
            roomStatus: .racing,
            mirroredWorkoutActive: true,
            isRunningOrPaused: true,
            snapshotAgeSeconds: 2
        ))
    }

    func testWatchReconnectBlocksDifferentWorkout() {
        XCTAssertFalse(LiveGhostRaceReentry.canReconnectWatchWorkout(
            comparisonRouteID: UUID(),
            challengeID: UUID(),
            roomStatus: .racing,
            mirroredWorkoutActive: true,
            isRunningOrPaused: true,
            snapshotAgeSeconds: 2
        ))
    }

    func testWatchReconnectBlocksStaleOrAbsentMirroring() {
        let duel = UUID()
        for age: TimeInterval in [121, 3_600, .infinity] {
            XCTAssertFalse(LiveGhostRaceReentry.canReconnectWatchWorkout(
                comparisonRouteID: duel,
                challengeID: duel,
                roomStatus: .racing,
                mirroredWorkoutActive: true,
                isRunningOrPaused: true,
                snapshotAgeSeconds: age
            ))
        }
        XCTAssertFalse(LiveGhostRaceReentry.canReconnectWatchWorkout(
            comparisonRouteID: duel,
            challengeID: duel,
            roomStatus: .racing,
            mirroredWorkoutActive: false,
            isRunningOrPaused: true,
            snapshotAgeSeconds: 2
        ))
    }

    func testWatchReconnectRequiresActiveRunningOrPausedState() {
        let duel = UUID()
        XCTAssertFalse(LiveGhostRaceReentry.canReconnectWatchWorkout(
            comparisonRouteID: duel,
            challengeID: duel,
            roomStatus: .racing,
            mirroredWorkoutActive: true,
            isRunningOrPaused: false,
            snapshotAgeSeconds: 2
        ))
    }

    func testFinishedCancelledAndCountdownRoomsCannotReconnectWatch() {
        let duel = UUID()
        for status: LiveGhostRaceRoomStatus in [.finished, .cancelled, .countdown, .lobby] {
            XCTAssertFalse(LiveGhostRaceReentry.canReconnectWatchWorkout(
                comparisonRouteID: duel,
                challengeID: duel,
                roomStatus: status,
                mirroredWorkoutActive: true,
                isRunningOrPaused: true,
                snapshotAgeSeconds: 2
            ))
        }
    }

    func testOnlyThisDuelsGPSCanBePublished() {
        let duel = UUID()
        XCTAssertTrue(ATHLTHLiveGhostWorkoutBinding.accepts(
            ghostChallengeID: duel,
            comparisonRouteID: duel
        ))
        XCTAssertFalse(ATHLTHLiveGhostWorkoutBinding.accepts(
            ghostChallengeID: duel,
            comparisonRouteID: UUID()
        ))
        XCTAssertFalse(ATHLTHLiveGhostWorkoutBinding.accepts(
            ghostChallengeID: duel,
            comparisonRouteID: nil
        ))
    }

    func testRegularWorkoutSharingIsNotAffectedByGhostBinding() {
        XCTAssertTrue(ATHLTHLiveGhostWorkoutBinding.accepts(
            ghostChallengeID: nil,
            comparisonRouteID: nil
        ))
        XCTAssertTrue(ATHLTHLiveGhostWorkoutBinding.accepts(
            ghostChallengeID: nil,
            comparisonRouteID: UUID()
        ))
    }

    func testLiveMapRejectsStaleWatchGPSAfterConnectivityLoss() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(ATHLTHWatchLiveTelemetryFreshness.isFresh(
            capturedAt: now.addingTimeInterval(-2), now: now
        ))
        XCTAssertTrue(ATHLTHWatchLiveTelemetryFreshness.isFresh(
            capturedAt: now.addingTimeInterval(-30), now: now
        ))
        XCTAssertFalse(ATHLTHWatchLiveTelemetryFreshness.isFresh(
            capturedAt: now.addingTimeInterval(-31), now: now
        ))
        XCTAssertFalse(ATHLTHWatchLiveTelemetryFreshness.isFresh(
            capturedAt: now.addingTimeInterval(-300), now: now
        ))
    }

    func testClockSkewOrNonFiniteWatchTimestampCannotFakeLiveGPS() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertFalse(ATHLTHWatchLiveTelemetryFreshness.isFresh(
            capturedAt: now.addingTimeInterval(11), now: now
        ))
        XCTAssertFalse(ATHLTHWatchLiveTelemetryFreshness.isFresh(
            capturedAt: Date(timeIntervalSince1970: .infinity), now: now
        ))
    }

    func testPausedWatchRaceCanReconnect() {
        let duel = UUID()
        XCTAssertTrue(LiveGhostRaceReentry.canReconnectWatchWorkout(
            comparisonRouteID: duel,
            challengeID: duel,
            roomStatus: .racing,
            mirroredWorkoutActive: true,
            isRunningOrPaused: true,
            snapshotAgeSeconds: 30
        ))
    }
}
