import CoreLocation
import XCTest
@testable import ATHLTH

/// Deterministic regression runs: these scenarios must behave the same in
/// CI without network, motion sensors or a real Apple Watch attached.
final class ATHLTHGhostRaceScenarioTests: XCTestCase {
    private func reference() -> GhostRaceReference {
        let points = (0...20).map { step in
            let fraction = Double(step) / 20
            return GhostRacePoint(
                id: step,
                latitude: 63.43 + 0.01 * fraction,
                longitude: 10.40 + 0.01 * fraction,
                altitude: nil,
                elapsedTime: 600 * fraction,
                cumulativeMeters: 2_000 * fraction
            )
        }
        return GhostRaceReference(
            id: UUID(),
            sourceWorkoutID: UUID(),
            title: "Synthetic 2K",
            startedAt: Date(timeIntervalSince1970: 1_800_000_000),
            durationSeconds: 600,
            distanceMeters: 2_000,
            points: points
        )
    }

    @MainActor
    func testNetworkGapCannotTurnIncompleteRouteIntoVictory() throws {
        let route = reference()
        let store = GhostRaceStore()
        try store.prepare(reference: route)
        store.updatePhoneWorkout(
            location: route.points[16].location,
            elapsedTime: 480, state: .running,
            routeProgressPercent: 80
        )
        store.updatePhoneWorkout(
            location: nil,
            elapsedTime: 570, state: .completed
        )
        let result = try XCTUnwrap(store.result)
        XCTAssertFalse(result.completedRoute)
        XCTAssertNil(result.beatGhost)
    }

    @MainActor
    func testReconnectionAfterPauseKeepsRaceClockAndCorrectFinalResult() throws {
        let route = reference()
        let store = GhostRaceStore()
        try store.prepare(reference: route)
        store.updatePhoneWorkout(
            location: route.points[15].location,
            elapsedTime: 450, state: .running,
            routeProgressPercent: 75
        )
        store.updatePhoneWorkout(
            location: route.points[15].location,
            elapsedTime: 450, state: .paused,
            routeProgressPercent: 75
        )
        XCTAssertNil(store.comparison)

        store.updatePhoneWorkout(
            location: route.points[19].location,
            elapsedTime: 540, state: .running,
            routeProgressPercent: 95
        )
        store.updatePhoneWorkout(
            location: route.points[20].location,
            elapsedTime: 570, state: .completed,
            routeProgressPercent: 100
        )
        let result = try XCTUnwrap(store.result)
        XCTAssertTrue(result.completedRoute)
        XCTAssertEqual(result.beatGhost, true)
    }

    @MainActor
    func testLastSecondGPSTeleportNeverWins() throws {
        let route = reference()
        let store = GhostRaceStore()
        try store.prepare(reference: route)
        store.updatePhoneWorkout(
            location: route.points[19].location,
            elapsedTime: 540, state: .running,
            routeProgressPercent: 95
        )
        store.updatePhoneWorkout(
            location: route.points.last!.location,
            elapsedTime: 541, state: .completed,
            routeProgressPercent: 100
        )
        let result = try XCTUnwrap(store.result)
        XCTAssertFalse(result.completedRoute)
    }

    func testReplayAndWatchInterpolationAgreeAtIrregularTimestamps() throws {
        let times: [Double] = [0, 17, 43, 91, 140, 202]
        let metres: [Double] = [0, 60, 180, 310, 545, 800]
        for second in stride(from: 0.0, through: 200.0, by: 2) {
            let distance = try XCTUnwrap(ATHLTHGhostTimeline.interpolate(
                at: second,
                count: times.count,
                position: { times[$0] },
                value: { metres[$0] }
            ))
            XCTAssertGreaterThanOrEqual(distance, 0)
            XCTAssertLessThanOrEqual(distance, 800)
            let backToTime = try XCTUnwrap(ATHLTHGhostTimeline.interpolate(
                at: distance,
                count: metres.count,
                position: { metres[$0] },
                value: { times[$0] }
            ))
            XCTAssertEqual(backToTime, second, accuracy: 0.0001)
        }
    }

    func testSingleNoisySampleCannotCreateOvertakeAfterDropout() {
        var tracker = ATHLTHGhostLeadTracker()
        XCTAssertFalse(tracker.observe(signedGapMeters: 15, elapsedSeconds: 10))
        XCTAssertFalse(tracker.observe(signedGapMeters: -30, elapsedSeconds: 11))
        tracker.invalidatePending()
        XCTAssertFalse(tracker.observe(signedGapMeters: -30, elapsedSeconds: 12))
        XCTAssertFalse(tracker.observe(signedGapMeters: -30, elapsedSeconds: 13))
        XCTAssertTrue(tracker.observe(signedGapMeters: -30, elapsedSeconds: 15))
    }

    func testRaceCannotBeDeclaredFromStaleSharedTimestamps() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertFalse(ATHLTHLiveGhostResultEvidence.bothFinishesPlausible(
            synchronizedStart: start,
            firstFinish: start.addingTimeInterval(600),
            firstElapsed: 600,
            secondFinish: start.addingTimeInterval(900),
            secondElapsed: 610
        ))
    }
}
