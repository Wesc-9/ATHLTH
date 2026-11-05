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

    private func trusted(_ point: GhostRacePoint) -> CLLocation {
        CLLocation(
            coordinate: point.coordinate,
            altitude: point.altitude ?? 0,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            timestamp: Date()
        )
    }

    private func trustedOffRoute() -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 63.45, longitude: 10.45),
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            timestamp: Date()
        )
    }

    @MainActor
    func testNetworkGapCannotTurnIncompleteRouteIntoVictory() throws {
        let route = reference()
        let store = GhostRaceStore()
        try store.prepare(reference: route)
        store.updatePhoneWorkout(
            location: trusted(route.points[16]),
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
            location: trusted(route.points[15]),
            elapsedTime: 450, state: .running,
            routeProgressPercent: 75
        )
        store.updatePhoneWorkout(
            location: trusted(route.points[15]),
            elapsedTime: 450, state: .paused,
            routeProgressPercent: 75
        )
        XCTAssertNil(store.comparison)

        store.updatePhoneWorkout(
            location: trusted(route.points[19]),
            elapsedTime: 540, state: .running,
            routeProgressPercent: 95
        )
        store.updatePhoneWorkout(
            location: trusted(route.points[20]),
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
            location: trusted(route.points[19]),
            elapsedTime: 540, state: .running,
            routeProgressPercent: 95
        )
        store.updatePhoneWorkout(
            location: trusted(route.points.last!),
            elapsedTime: 541, state: .completed,
            routeProgressPercent: 100
        )
        let result = try XCTUnwrap(store.result)
        XCTAssertFalse(result.completedRoute)
    }

    @MainActor
    func testFirstValidPositionAfterLongDetourIsNotPlacedBesideGhost() throws {
        let route = reference()
        let store = GhostRaceStore()
        try store.prepare(reference: route)
        // The Watch ran far from the reference route for ten minutes.
        // Ghost has reached the finish; the runner has rejoined at the start.
        store.updatePhoneWorkout(
            location: trustedOffRoute(),
            elapsedTime: 550, state: .running
        )
        XCTAssertNil(store.comparison)
        store.updatePhoneWorkout(
            location: trusted(route.points[0]),
            elapsedTime: 605, state: .running
        )
        let match = try XCTUnwrap(store.comparison)
        XCTAssertEqual(match.userProgress, 0, accuracy: 0.001)
        XCTAssertEqual(match.ghostProgress, 1, accuracy: 0.001)
        XCTAssertLessThan(match.signedDistanceMeters, -1_900)
    }

    @MainActor
    func testGhostDoesNotGetDraggedBackWhenRunnerRejoinsAfterDetour() throws {
        let route = reference()
        let store = GhostRaceStore()
        try store.prepare(reference: route)
        store.updatePhoneWorkout(
            location: trusted(route.points[4]),
            elapsedTime: 120, state: .running
        )
        XCTAssertNotNil(store.comparison)
        store.updatePhoneWorkout(
            location: trustedOffRoute(),
            elapsedTime: 170, state: .running
        )
        XCTAssertNil(store.comparison)
        store.updatePhoneWorkout(
            location: trusted(route.points[5]),
            elapsedTime: 610, state: .running
        )
        let match = try XCTUnwrap(store.comparison)
        XCTAssertEqual(match.userProgress, 0.25, accuracy: 0.01)
        XCTAssertEqual(match.ghostProgress, 1, accuracy: 0.001)
        XCTAssertLessThan(match.signedDistanceMeters, -1_400)
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

    @MainActor
    func testPhoneWarmupUsesTheSameGhostStartBoundaryAsWatch() throws {
        let route = reference()
        let store = GhostRaceStore()
        try store.prepare(reference: route)

        store.updatePhoneWorkout(
            location: trusted(route.points[0]),
            elapsedTime: 300,
            state: .running,
            routeProgressPercent: 0,
            routeWarmup: true
        )
        XCTAssertNil(store.comparison)

        store.updatePhoneWorkout(
            location: trusted(route.points[0]),
            elapsedTime: 301,
            state: .running,
            routeProgressPercent: 0,
            routeWarmup: false,
            mainStepElapsedSeconds: 1
        )
        let comparison = try XCTUnwrap(store.comparison)
        XCTAssertLessThan(comparison.ghostProgress, 0.02)
    }

    @MainActor
    func testWarmupDoesNotAdvanceGhostClockOrShowComparison() throws {
        let route = reference()
        let store = GhostRaceStore()
        try store.prepare(reference: route)

        var snapshot = WatchWorkoutLiveSnapshot(
            kind: .running,
            state: .running,
            startedAt: nil,
            capturedAt: Date(),
            elapsedTime: 600,
            heartRate: 140,
            activeCalories: 60,
            distanceMeters: 1_000,
            averageHeartRate: nil,
            maxHeartRate: nil,
            routePointCount: 1,
            currentLatitude: route.points[0].latitude,
            currentLongitude: route.points[0].longitude
        )
        snapshot.currentHorizontalAccuracy = 5
        snapshot.currentLocationSampledAt = snapshot.capturedAt
        snapshot.runningStepPhase = "warmup"
        snapshot.runningRouteWarmup = true
        store.update(with: snapshot)
        XCTAssertNil(store.comparison, "Ghost cannot move during warm-up.")

        snapshot.runningStepPhase = "work"
        snapshot.runningRouteWarmup = false
        snapshot.runningStepElapsedSeconds = 1
        snapshot.elapsedTime = 601
        snapshot.distanceMeters = 1_005
        snapshot.routeProgressPercent = 0
        snapshot.routeDistanceMeters = 2_000
        store.update(with: snapshot)

        let comparison = try XCTUnwrap(store.comparison)
        XCTAssertLessThan(comparison.ghostProgress, 0.02,
                          "Main phase should start a new Ghost clock, not reuse warm-up time.")
    }

    func testTerrainGhostPreservesFinishTimeAndSlowsOnUphill() {
        let altitudes: [Double] = [0, 0, 5, 17, 25, 24, 10, 0, 0]
        let coordinates = altitudes.enumerated().map { i, altitude in
            RouteCoordinate(
                latitude: 63.43 + Double(i) * 0.0002,
                longitude: 10.40,
                altitude: altitude,
                sequence: i
            )
        }
        let distances = coordinates.indices.map { Double($0) * 22.2 }
        let fractions = GhostTargetPacingStrategy.terrainElapsedFractions(
            coordinates: coordinates, cumulativeMeters: distances
        )
        XCTAssertEqual(fractions.count, coordinates.count)
        XCTAssertEqual(fractions.first, 0)
        XCTAssertEqual(fractions.last, 1)
        for i in 1..<fractions.count {
            XCTAssertGreaterThanOrEqual(fractions[i], fractions[i - 1])
        }
        XCTAssertGreaterThan(fractions[4], 0.5,
                             "Uphill half should use more than half the target time.")
    }

    func testTerrainGhostHasEvenFallbackWithoutElevation() {
        let coordinates = (0...8).map { i in
            RouteCoordinate(
                latitude: 63.43 + Double(i) * 0.0002,
                longitude: 10.4,
                altitude: nil,
                sequence: i
            )
        }
        let distances = coordinates.indices.map { Double($0) * 25 }
        let fractions = GhostTargetPacingStrategy.terrainElapsedFractions(
            coordinates: coordinates, cumulativeMeters: distances
        )
        XCTAssertEqual(fractions[4], 0.5, accuracy: 0.001)
        XCTAssertEqual(fractions.last, 1)
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
