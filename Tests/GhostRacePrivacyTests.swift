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
