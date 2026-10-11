import XCTest
@testable import ATHLTH

final class GhostRacePrivacyTests: XCTestCase {
    func testFriendGhostPrivacyTrimsAndRebasesRoute() throws {
        let reference = makeReference(
            distanceMeters: 2_000,
            durationSeconds: 600,
            pointCount: 21
        )

        let payload =
            try GhostFriendRaceSanitizer.makePayload(
                from: reference,
                hideStartAndEnd: true
            )

        XCTAssertTrue(payload.privacyTrimmed)
        XCTAssertGreaterThanOrEqual(
            payload.distanceMeters,
            1_400
        )
        XCTAssertLessThanOrEqual(
            payload.distanceMeters,
            1_600
        )
        XCTAssertEqual(
            payload.points.first!.cumulativeMeters,
            0,
            accuracy: 0.001
        )
        XCTAssertEqual(
            payload.points.first!.elapsedTime,
            0,
            accuracy: 0.001
        )
        XCTAssertLessThanOrEqual(
            payload.points.count,
            350
        )
    }

    func testFriendGhostCanKeepFullRouteWhenPrivacyTrimIsOff() throws {
        let reference = makeReference(
            distanceMeters: 2_000,
            durationSeconds: 600,
            pointCount: 21
        )

        let payload =
            try GhostFriendRaceSanitizer.makePayload(
                from: reference,
                hideStartAndEnd: false
            )

        XCTAssertFalse(payload.privacyTrimmed)
        XCTAssertEqual(
            payload.distanceMeters,
            2_000,
            accuracy: 0.001
        )
        XCTAssertEqual(
            payload.durationSeconds,
            600,
            accuracy: 0.001
        )
    }

    func testFriendGhostRefusesTooShortPrivateRoute() {
        let reference = makeReference(
            distanceMeters: 600,
            durationSeconds: 180,
            pointCount: 13
        )

        XCTAssertThrowsError(
            try GhostFriendRaceSanitizer.makePayload(
                from: reference,
                hideStartAndEnd: true
            )
        )
    }

    @MainActor
    func testPlannedRouteGhostUsesSyntheticPaceAndExistingPrivacyTrimming() throws {
        let coordinates = (0..<41).map { i in
            RouteCoordinate(
                latitude: 63.42 + Double(i) * 0.0003,
                longitude: 10.39 + Double(i) * 0.0002,
                altitude: nil,
                sequence: i
            )
        }
        let route = TrainingRoute(
            id: UUID(),
            ownerID: UUID(),
            title: "Arena test route",
            visibility: .privateOnly,
            coordinates: coordinates,
            distanceKilometers: 1.5,
            elevationGainMeters: nil,
            importedFilename: nil,
            createdAt: Date(),
            startName: nil,
            endName: nil,
            expectedTravelTimeSeconds: nil,
            routeSource: "arena_competition"
        )
        let builder = GhostRaceStore()
        try builder.prepareTarget(
            route: route,
            targetDurationSeconds: 900
        )
        let reference = try XCTUnwrap(builder.reference)
        XCTAssertEqual(reference.sourceWorkoutID, route.id)
        XCTAssertEqual(reference.durationSeconds, 900, accuracy: 0.001)

        let protected = try GhostFriendRaceSanitizer.makePayload(
            from: reference,
            hideStartAndEnd: true
        )
        XCTAssertTrue(protected.privacyTrimmed)
        XCTAssertLessThan(protected.distanceMeters, reference.distanceMeters)
        XCTAssertEqual(protected.points.first?.elapsedTime ?? -1, 0, accuracy: 0.01)
        XCTAssertEqual(protected.points.first?.cumulativeMeters ?? -1, 0, accuracy: 0.01)
        XCTAssertLessThanOrEqual(protected.points.count, 350)
        XCTAssertNotEqual(protected.points.first?.latitude,
                          reference.points.first?.latitude)
    }

    func testLiveGhostFinishGateRejectsDuplicatesAndInvalidTimes() {
        let challenge = UUID()
        var gate = ATHLTHLiveGhostFinishGate()
        XCTAssertFalse(gate.begin(challengeID: challenge, seconds: .nan))
        XCTAssertFalse(gate.begin(challengeID: challenge, seconds: 0))
        XCTAssertFalse(gate.begin(challengeID: challenge, seconds: 86_401))
        XCTAssertTrue(gate.begin(challengeID: challenge, seconds: 900))
        XCTAssertFalse(gate.begin(challengeID: challenge, seconds: 901))
        gate.end(challengeID: challenge, succeeded: true)
        XCTAssertFalse(gate.begin(challengeID: challenge, seconds: 900))
        XCTAssertTrue(gate.begin(challengeID: UUID(), seconds: 900))
    }

    func testLiveGhostFinishGateAllowsRetryAfterNetworkFailure() {
        let challenge = UUID()
        var gate = ATHLTHLiveGhostFinishGate()
        XCTAssertTrue(gate.begin(challengeID: challenge, seconds: 1_200))
        gate.end(challengeID: challenge, succeeded: false)
        XCTAssertTrue(gate.begin(challengeID: challenge, seconds: 1_200))
        gate.end(challengeID: challenge, succeeded: true)
        XCTAssertFalse(gate.begin(challengeID: challenge, seconds: 1_200))
    }

    @MainActor
    func testPhoneGhostRuntimeProducesRouteAwareComparison() throws {
        let reference = makeReference(
            distanceMeters: 2_000,
            durationSeconds: 600,
            pointCount: 21
        )
        let store = GhostRaceStore()

        try store.prepare(
            reference: reference
        )

        let point = reference.points[10]

        store.updatePhoneWorkout(
            location: point.location,
            elapsedTime: 270,
            state: .running
        )

        let comparison =
            try XCTUnwrap(
                store.comparison
            )

        XCTAssertEqual(
            comparison.userProgress,
            0.5,
            accuracy: 0.02
        )
        XCTAssertLessThan(
            comparison.routeDeviationMeters,
            2
        )
        XCTAssertGreaterThan(
            comparison.signedTimeSeconds,
            0
        )
    }

    @MainActor
    func testPhoneGhostRuntimeCompletesAndScoresRace() throws {
        let reference = makeReference(
            distanceMeters: 2_000,
            durationSeconds: 600,
            pointCount: 21
        )
        let store = GhostRaceStore()

        try store.prepare(
            reference: reference
        )

        store.updatePhoneWorkout(
            location:
                reference
                    .points
                    .last!
                    .location,
            elapsedTime: 570,
            state: .completed
        )

        let result =
            try XCTUnwrap(
                store.result
            )

        XCTAssertTrue(
            result.completedRoute
        )
        let signedTime =
            try XCTUnwrap(
                result.signedTimeSeconds
            )

        XCTAssertEqual(
            signedTime,
            30,
            accuracy: 0.01
        )
        XCTAssertEqual(
            result.beatGhost,
            true
        )
    }

    @MainActor
    func testGhostResultTracksLeadChangesAndExtremes() throws {
        let reference = makeReference(
            distanceMeters: 2_000,
            durationSeconds: 600,
            pointCount: 21
        )
        let store = GhostRaceStore()

        try store.prepare(
            reference: reference
        )

        store.updatePhoneWorkout(
            location:
                reference.points[10].location,
            elapsedTime: 330,
            state: .running
        )

        store.updatePhoneWorkout(
            location:
                reference.points[15].location,
            elapsedTime: 420,
            state: .running
        )

        store.updatePhoneWorkout(
            location:
                reference.points.last!.location,
            elapsedTime: 570,
            state: .completed
        )

        let result =
            try XCTUnwrap(store.result)

        XCTAssertGreaterThan(
            result.maximumLeadMeters,
            50
        )
        XCTAssertGreaterThan(
            result.maximumDeficitMeters,
            50
        )
        XCTAssertGreaterThanOrEqual(
            result.leadChangeCount,
            1
        )
    }

    func testAgreedArenaRouteIsRequiredForLinkedLiveDuel() {
        let round = UUID()
        let course = UUID()
        XCTAssertEqual(
            GhostFriendRaceArenaLinkPolicy.eligibleRoundID(
                roundID: round,
                agreedRouteID: course,
                selectedRouteID: course,
                isPlannedRoute: true
            ),
            round
        )
        XCTAssertNil(
            GhostFriendRaceArenaLinkPolicy.eligibleRoundID(
                roundID: round,
                agreedRouteID: course,
                selectedRouteID: UUID(),
                isPlannedRoute: true
            )
        )
    }

    func testEarlierWorkoutMustNeverBeAttributedToUnverifiedArenaRoute() {
        XCTAssertNil(
            GhostFriendRaceArenaLinkPolicy.eligibleRoundID(
                roundID: UUID(),
                agreedRouteID: UUID(),
                selectedRouteID: UUID(),
                isPlannedRoute: false
            )
        )
        XCTAssertNil(
            GhostFriendRaceArenaLinkPolicy.eligibleRoundID(
                roundID: UUID(),
                agreedRouteID: nil,
                selectedRouteID: nil,
                isPlannedRoute: true
            )
        )
    }

    private func makeReference(
        distanceMeters: Double,
        durationSeconds: TimeInterval,
        pointCount: Int
    ) -> GhostRaceReference {
        let points =
            (0..<pointCount).map {
                index -> GhostRacePoint in

                let progress =
                    Double(index) /
                    Double(
                        max(
                            pointCount - 1,
                            1
                        )
                    )

                return GhostRacePoint(
                    id: index,
                    latitude:
                        63.43 +
                        progress * 0.01,
                    longitude:
                        10.40 +
                        progress * 0.01,
                    altitude: nil,
                    elapsedTime:
                        durationSeconds *
                        progress,
                    cumulativeMeters:
                        distanceMeters *
                        progress
                )
            }

        return GhostRaceReference(
            id: UUID(),
            sourceWorkoutID: UUID(),
            title: "Test Ghost",
            startedAt: Date(),
            durationSeconds: durationSeconds,
            distanceMeters: distanceMeters,
            points: points
        )
    }
}
