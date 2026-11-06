import CoreLocation
import XCTest
@testable import ATHLTH

final class ATHLTHPrivateGhostSpectatorTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func reference(pointCount: Int = 360) -> GhostRaceReference {
        let points = (0..<pointCount).map { index in
            GhostRacePoint(
                id: index,
                latitude: 63.4 + Double(index) * 0.0001,
                longitude: 10.3 + Double(index) * 0.0001,
                altitude: nil,
                elapsedTime: Double(index) * 5,
                cumulativeMeters: Double(index) * 15
            )
        }
        return GhostRaceReference(
            id: UUID(), sourceWorkoutID: UUID(),
            title: "Earlier running session", startedAt: now,
            durationSeconds: 1_800,
            distanceMeters: Double(pointCount - 1) * 15,
            points: points
        )
    }

    private func comparison(at date: Date) -> GhostRaceComparison {
        GhostRaceComparison(
            userLatitude: 63.418, userLongitude: 10.318,
            ghostLatitude: 63.416, ghostLongitude: 10.316,
            userProgress: 0.45, ghostProgress: 0.42,
            signedDistanceMeters: 110, signedTimeSeconds: 30,
            routeDeviationMeters: 3, updatedAt: date
        )
    }

    @MainActor
    func testRouteIsSampledAndKeepsEndpoints() throws {
        let source = reference()
        let value = try XCTUnwrap(ATHLTHPrivateGhostSpectatorSnapshot.make(
            reference: source,
            comparison: comparison(at: now),
            sourceDevice: "Apple Watch", paused: false, now: now
        ))
        XCTAssertLessThanOrEqual(value.course.count, 180)
        XCTAssertEqual(value.course.first?.latitude,
                       source.points.first?.latitude)
        XCTAssertEqual(value.course.last?.longitude,
                       source.points.last?.longitude)
        XCTAssertEqual(value.sourceDevice, "Apple Watch")
        XCTAssertTrue(value.hasFreshPositions(at: now))
        XCTAssertEqual(value.signedDistanceMeters, 110)
    }

    @MainActor
    func testPausedRaceDoesNotShareOrShowAnyRunnerMarkers() throws {
        let value = try XCTUnwrap(ATHLTHPrivateGhostSpectatorSnapshot.make(
            reference: reference(),
            comparison: comparison(at: now),
            sourceDevice: "iPhone", paused: true, now: now
        ))
        XCTAssertTrue(value.isFresh(at: now))
        XCTAssertNil(value.runner)
        XCTAssertNil(value.ghost)
        XCTAssertFalse(value.hasFreshPositions(at: now))
    }

    @MainActor
    func testStaleComparisonDoesNotUploadAnOldPosition() throws {
        let value = try XCTUnwrap(ATHLTHPrivateGhostSpectatorSnapshot.make(
            reference: reference(),
            comparison: comparison(at: now.addingTimeInterval(-40)),
            sourceDevice: "iPhone", paused: false, now: now
        ))
        XCTAssertNil(value.runner)
        XCTAssertNil(value.ghost)
    }

    @MainActor
    func testExpiredRaceAndPositionsAreHidden() throws {
        let value = try XCTUnwrap(ATHLTHPrivateGhostSpectatorSnapshot.make(
            reference: reference(),
            comparison: comparison(at: now),
            sourceDevice: "iPhone", paused: false, now: now
        ))
        XCTAssertTrue(value.isFresh(at: now.addingTimeInterval(50)))
        XCTAssertFalse(value.hasFreshPositions(at: now.addingTimeInterval(20)))
        XCTAssertFalse(value.isFresh(at: now.addingTimeInterval(70)))
    }

    func testInvalidCoordinatesCannotBeShown() {
        XCTAssertFalse(ATHLTHPrivateGhostSpectatorSnapshot.validCoordinate(
            .init(latitude: 100, longitude: 10)
        ))
        XCTAssertFalse(ATHLTHPrivateGhostSpectatorSnapshot.validCoordinate(
            .init(latitude: 63, longitude: 181)
        ))
    }
}
