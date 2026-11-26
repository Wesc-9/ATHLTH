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

    @MainActor
    func testSparseGhostPolylineMatchesRunnerBetweenTwoWaypoints() throws {
        let points = [
            GhostRacePoint(
                id: 0, latitude: 63.4305, longitude: 10.3900,
                altitude: nil, elapsedTime: 0, cumulativeMeters: 0
            ),
            GhostRacePoint(
                id: 1, latitude: 63.4305, longitude: 10.3970,
                altitude: nil, elapsedTime: 420, cumulativeMeters: 350
            )
        ]
        let reference = GhostRaceReference(
            id: UUID(), sourceWorkoutID: UUID(), title: "Sparse course",
            startedAt: Date(), durationSeconds: 420,
            distanceMeters: 350, points: points
        )
        let location = CLLocation(
            coordinate: CLLocationCoordinate2D(
                latitude: 63.4305, longitude: 10.3935
            ),
            altitude: 0, horizontalAccuracy: 5,
            verticalAccuracy: 5, timestamp: Date()
        )
        let store = GhostRaceStore()
        try store.prepare(reference: reference)
        store.updatePhoneWorkout(
            location: location, elapsedTime: 210, state: .running
        )
        let match = try XCTUnwrap(store.comparison)
        XCTAssertLessThan(match.routeDeviationMeters, 8)
        XCTAssertEqual(match.userProgress, 0.5, accuracy: 0.05)
        XCTAssertEqual(match.ghostProgress, 0.5, accuracy: 0.05)
    }

    @MainActor
    func testBadAccuracyOrOldGPSCannotCreateGhostLead() throws {
        let route = reference()
        let store = GhostRaceStore()
        try store.prepare(reference: route)
        let point = route.points[6]
        let unreliable = CLLocation(
            coordinate: point.coordinate,
            altitude: 0,
            horizontalAccuracy: 180,
            verticalAccuracy: 5,
            timestamp: Date()
        )
        store.updatePhoneWorkout(
            location: unreliable, elapsedTime: 190, state: .running
        )
        XCTAssertNil(store.comparison)
        let stale = CLLocation(
            coordinate: point.coordinate,
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            timestamp: Date().addingTimeInterval(-45)
        )
        store.updatePhoneWorkout(
            location: stale, elapsedTime: 192, state: .running
        )
        XCTAssertNil(store.comparison)
        store.updatePhoneWorkout(
            location: trusted(point), elapsedTime: 195, state: .running
        )
        XCTAssertNotNil(store.comparison)
    }

    @MainActor
    func testTargetPaceUsesTrueGeometryEvenWhenStoredMetadataIsWrong() throws {
        let coordinates = (0...10).map { index in
            RouteCoordinate(
                latitude: 63.4305,
                longitude: 10.3900 + Double(index) * 0.0007,
                altitude: nil,
                sequence: index
            )
        }
        let route = TrainingRoute(
            id: UUID(),
            ownerID: UUID(),
            title: "Sparse example",
            visibility: .privateOnly,
            coordinates: coordinates,
            distanceKilometers: 10, // wrong legacy metadata
            elevationGainMeters: nil,
            importedFilename: nil,
            createdAt: Date(),
            startName: "A",
            endName: "B",
            expectedTravelTimeSeconds: nil,
            routeSource: "test",
            sharedSourceOwnerID: nil,
            sharedSourceRouteID: nil
        )
        let courseKilometers = try XCTUnwrap(
            GhostTargetRouteEligibility.geometryDistanceKilometers(route)
        )
        let duration = try XCTUnwrap(GhostTargetPaceFormatter.duration(
            paceSeconds: 300, routeKilometers: courseKilometers
        ))
        let store = GhostRaceStore()
        try store.prepareTarget(
            route: route, targetDurationSeconds: duration
        )
        let reference = try XCTUnwrap(store.reference)
        XCTAssertEqual(
            reference.durationSeconds, courseKilometers * 300, accuracy: 0.6
        )
        XCTAssertEqual(
            reference.routeDistanceMeters / 1_000, courseKilometers,
            accuracy: 0.01
        )
        XCTAssertNotEqual(reference.durationSeconds, 3_000)
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


final class ATHLTHIntervalGhostPacerPolicyTests: XCTestCase {
    func testWorkIntervalsExcludePassiveRecovery() throws {
        let start = ATHLTHIntervalGhostPacer.VirtualProgress()
        let first = try XCTUnwrap(ATHLTHIntervalGhostPacer.advance(
            start, kind: .work, scope: .mainOnly,
            elapsedSeconds: 300, actualMeters: 1_050,
            workPaceSecondsPerKilometer: 300, recovery: .freeze
        ))
        let paused = try XCTUnwrap(ATHLTHIntervalGhostPacer.advance(
            first, kind: .passiveRecovery, scope: .mainOnly,
            elapsedSeconds: 120, actualMeters: 0,
            workPaceSecondsPerKilometer: 300, recovery: .freeze
        ))
        XCTAssertEqual(paused.ghostMeters, 1_000, accuracy: 0.01)
        XCTAssertEqual(paused.leadMeters, 50, accuracy: 0.01)
        let second = try XCTUnwrap(ATHLTHIntervalGhostPacer.advance(
            paused, kind: .work, scope: .mainOnly,
            elapsedSeconds: 300, actualMeters: 950,
            workPaceSecondsPerKilometer: 300, recovery: .freeze
        ))
        XCTAssertEqual(second.leadMeters, 0, accuracy: 0.01)
    }

    func testActiveRecoveryCanFollowActualDistance() throws {
        let start = ATHLTHIntervalGhostPacer.VirtualProgress()
        let next = try XCTUnwrap(ATHLTHIntervalGhostPacer.advance(
            start, kind: .activeRecovery, scope: .mainOnly,
            elapsedSeconds: 90, actualMeters: 180,
            workPaceSecondsPerKilometer: 300,
            recovery: .followActualDistance
        ))
        XCTAssertEqual(next.ghostMeters, 180, accuracy: 0.01)
        XCTAssertEqual(next.leadMeters, 0, accuracy: 0.01)
    }

    func testWorkoutConfigurationRoundTripsAndSelectsOnlyChosenDrag() throws {
        let selected = UUID()
        let skipped = UUID()
        var configuration = ATHLTHIntervalGhostPacer.WorkoutConfiguration()
        configuration.isEnabled = true
        configuration.coverage = .selectedSegments
        configuration.segments = [
            .init(id: selected, enabled: true, paceSecondsPerKilometer: 240),
            .init(id: skipped, enabled: false, paceSecondsPerKilometer: nil)
        ]
        let decoded = try JSONDecoder().decode(
            ATHLTHIntervalGhostPacer.WorkoutConfiguration.self,
            from: JSONEncoder().encode(configuration)
        )
        XCTAssertEqual(decoded, configuration)
        XCTAssertTrue(decoded.isValid)
        let start = ATHLTHIntervalGhostPacer.VirtualProgress()
        let skippedProgress = try XCTUnwrap(decoded.progress(
            from: start, segmentID: skipped, kind: .work,
            elapsedSeconds: 240, actualMeters: 950
        ))
        XCTAssertEqual(skippedProgress.ghostMeters, 0)
        let selectedProgress = try XCTUnwrap(decoded.progress(
            from: skippedProgress, segmentID: selected, kind: .work,
            elapsedSeconds: 240, actualMeters: 950
        ))
        XCTAssertEqual(selectedProgress.ghostMeters, 1_000, accuracy: 0.01)
        XCTAssertEqual(selectedProgress.leadMeters, -50, accuracy: 0.01)
    }

    func testRepeatedWatchSampleDoesNotAdvanceGhostTwice() throws {
        var configuration = ATHLTHIntervalGhostPacer.WorkoutConfiguration()
        configuration.isEnabled = true
        let id = UUID()
        let initial = ATHLTHIntervalGhostPacer.LiveSample(
            elapsedSeconds: 0, distanceMeters: 0
        )
        let current = ATHLTHIntervalGhostPacer.LiveSample(
            elapsedSeconds: 300, distanceMeters: 1_050
        )
        let first = try XCTUnwrap(ATHLTHIntervalGhostPacer.advanceLiveSample(
            configuration: configuration,
            progress: .init(),
            previous: initial, current: current,
            segmentID: id, kind: .work
        ))
        let duplicate = try XCTUnwrap(ATHLTHIntervalGhostPacer.advanceLiveSample(
            configuration: configuration,
            progress: first,
            previous: current, current: current,
            segmentID: id, kind: .work
        ))
        XCTAssertEqual(duplicate.ghostMeters, 1_000, accuracy: 0.01)
        XCTAssertEqual(duplicate.leadMeters, 50, accuracy: 0.01)
    }

    func testWatchSampleRejectsBackwardClockOrDistance() {
        var configuration = ATHLTHIntervalGhostPacer.WorkoutConfiguration()
        configuration.isEnabled = true
        XCTAssertNil(ATHLTHIntervalGhostPacer.advanceLiveSample(
            configuration: configuration,
            progress: .init(),
            previous: .init(elapsedSeconds: 300, distanceMeters: 1_000),
            current: .init(elapsedSeconds: 299, distanceMeters: 1_050),
            segmentID: UUID(), kind: .work
        ))
    }

    func testWorkoutConfigurationRejectsInvalidRecoveryPace() {
        var configuration = ATHLTHIntervalGhostPacer.WorkoutConfiguration()
        configuration.isEnabled = true
        configuration.pauseBehavior = .customPace
        configuration.recoveryPaceSecondsPerKilometer = .nan
        XCTAssertFalse(configuration.isValid)
    }

    func testIndividualIntervalsCanBeExcludedOrHaveOwnPace() throws {
        let ignoredID = UUID()
        let fastID = UUID()
        let overrides: [ATHLTHIntervalGhostPacer.SegmentOverride] = [
            .init(segmentID: ignoredID, enabled: false, paceSecondsPerKilometer: nil),
            .init(segmentID: fastID, enabled: true, paceSecondsPerKilometer: 240)
        ]
        let start = ATHLTHIntervalGhostPacer.VirtualProgress()
        let excluded = try XCTUnwrap(ATHLTHIntervalGhostPacer.advanceSegment(
            start, segmentID: ignoredID, kind: .work, scope: .mainOnly,
            elapsedSeconds: 300, actualMeters: 1_000,
            defaultPaceSecondsPerKilometer: 300,
            recovery: .freeze, overrides: overrides
        ))
        XCTAssertEqual(excluded.ghostMeters, 0)
        XCTAssertEqual(excluded.runnerMeters, 0)
        let fast = try XCTUnwrap(ATHLTHIntervalGhostPacer.advanceSegment(
            excluded, segmentID: fastID, kind: .work, scope: .mainOnly,
            elapsedSeconds: 240, actualMeters: 950,
            defaultPaceSecondsPerKilometer: 300,
            recovery: .freeze, overrides: overrides
        ))
        XCTAssertEqual(fast.ghostMeters, 1_000, accuracy: 0.01)
        XCTAssertEqual(fast.leadMeters, -50, accuracy: 0.01)
    }

    func testMainOnlyIgnoresWarmupAndInvalidPace() throws {
        let start = ATHLTHIntervalGhostPacer.VirtualProgress()
        let next = try XCTUnwrap(ATHLTHIntervalGhostPacer.advance(
            start, kind: .warmup, scope: .mainOnly,
            elapsedSeconds: 600, actualMeters: 1_000,
            workPaceSecondsPerKilometer: 300, recovery: .freeze
        ))
        XCTAssertEqual(next.ghostMeters, 0)
        XCTAssertNil(ATHLTHIntervalGhostPacer.advance(
            start, kind: .work, scope: .mainOnly,
            elapsedSeconds: 300, actualMeters: 1_000,
            workPaceSecondsPerKilometer: .nan, recovery: .freeze
        ))
    }
}

final class ATHLTHSoloGhostFinishPolicyTests: XCTestCase {
    func testDistanceFinishUsesTargetTimeRatherThanOvershoot() throws {
        let result = try XCTUnwrap(ATHLTHSoloGhostComparison.result(
            elapsed: 301, meters: 1_020, pace: 300,
            targetMeters: 1_000, targetSeconds: nil))
        XCTAssertEqual(result.outcome, .behind)
        XCTAssertEqual(result.timeGapSeconds, -1, accuracy: 0.001)
    }

    func testStoppedBeforeDistanceIsNotAWin() throws {
        let result = try XCTUnwrap(ATHLTHSoloGhostComparison.result(
            elapsed: 120, meters: 500, pace: 300,
            targetMeters: 1_000, targetSeconds: nil))
        XCTAssertEqual(result.outcome, .incomplete)
        XCTAssertGreaterThan(result.leadMeters, 0)
    }

    func testOpenAndTimedResults() throws {
        let open = try XCTUnwrap(ATHLTHSoloGhostComparison.result(
            elapsed: 300, meters: 1_100, pace: 300, targetMeters: nil, targetSeconds: nil))
        XCTAssertEqual(open.outcome, .ahead)
        XCTAssertEqual(open.timeGapSeconds, 30, accuracy: 0.001)
        XCTAssertEqual(ATHLTHSoloGhostComparison.result(
            elapsed: 300, meters: 1_100, pace: 300, targetMeters: nil, targetSeconds: 600)?.outcome, .incomplete)
        XCTAssertEqual(ATHLTHSoloGhostComparison.result(
            elapsed: 600, meters: 2_000, pace: 300, targetMeters: nil, targetSeconds: 600)?.outcome, .tied)
    }

    func testDistancePresetsAndOpenTransfer() throws {
        XCTAssertEqual(ATHLTHSoloGhostPacePolicy.presets.map(\.meters),
                       [1_000, 2_000, 5_000, 10_000, 21_097.5, 42_195])
        let transfer = try XCTUnwrap(ATHLTHSoloGhostPacePolicy.transfer(
            paceSeconds: 330, distanceMeters: nil, durationSeconds: nil))
        XCTAssertEqual(transfer.soloGhostRace, true)
        XCTAssertEqual(transfer.steps.first?.measure, .open)
        XCTAssertNil(ATHLTHSoloGhostPacePolicy.transfer(
            paceSeconds: 330, distanceMeters: 5_000, durationSeconds: 600))
    }
}

final class ATHLTHSoloGhostTemplateTests: XCTestCase {
    func testTemplateValidationRejectsConflictingGoals() {
        XCTAssertTrue(ATHLTHSoloGhostTemplate(id: UUID(), name: "5 km", paceSeconds: 300,
            distanceMeters: 5000, durationSeconds: nil).isValid)
        XCTAssertFalse(ATHLTHSoloGhostTemplate(id: UUID(), name: "Invalid", paceSeconds: 300,
            distanceMeters: 5000, durationSeconds: 600).isValid)
        XCTAssertFalse(ATHLTHSoloGhostTemplate(id: UUID(), name: " ", paceSeconds: 300,
            distanceMeters: nil, durationSeconds: nil).isValid)
    }
}

final class ATHLTHSoloGhostCoachTests: XCTestCase {
    func testCoachReportsSignedEquivalentTimeAndTie() {
        XCTAssertEqual(ATHLTHSoloGhostComparison.coachPhrase(leadMeters: 100, pace: 300, norwegian: true),
                       "Du ligger 30 sekunder foran ghosten.")
        XCTAssertEqual(ATHLTHSoloGhostComparison.coachPhrase(leadMeters: -100, pace: 300, norwegian: false),
                       "You are 30 seconds behind the ghost.")
        XCTAssertEqual(ATHLTHSoloGhostComparison.coachPhrase(leadMeters: 0, pace: 300, norwegian: true),
                       "Du holder samme fart som ghosten.")
        XCTAssertNil(ATHLTHSoloGhostComparison.coachPhrase(leadMeters: .nan, pace: 300, norwegian: true))
    }
}

final class ATHLTHSoloGhostSampledStatsTests: XCTestCase {
    func testNoSamplesDoesNotInventRaceStatistics() {
        XCTAssertNil(ATHLTHSoloGhostComparison.sampledStats(samples: [], pace: 300, finishElapsed: 600))
        XCTAssertNil(ATHLTHSoloGhostComparison.result(elapsed: 300, meters: 1000, pace: 300,
            targetMeters: nil, targetSeconds: nil)?.sampledStats)
    }
}
