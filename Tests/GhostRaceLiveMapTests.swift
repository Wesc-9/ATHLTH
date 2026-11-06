import CoreLocation
import XCTest
@testable import ATHLTH

final class GhostRaceLiveMapTests: XCTestCase {
    private let clock = Date(timeIntervalSince1970: 1_700_000_000)

    private func comparison(at date: Date) -> GhostRaceComparison {
        GhostRaceComparison(
            userLatitude: 63.43,
            userLongitude: 10.40,
            ghostLatitude: 63.429,
            ghostLongitude: 10.398,
            userProgress: 0.45,
            ghostProgress: 0.43,
            signedDistanceMeters: 100,
            signedTimeSeconds: 28,
            routeDeviationMeters: 8,
            updatedAt: date
        )
    }

    func testFreshValidatedGPSAllowsTwoRunnerMarkers() {
        let value = comparison(at: clock.addingTimeInterval(-3))
        let visible = ATHLTHGhostRaceLiveMapPolicy.acceptedComparison(
            value, paused: false, at: clock
        )
        XCTAssertEqual(visible, value)
    }

    func testPausedOrStaleGPSHidesMarkersAndLead() {
        let value = comparison(at: clock)
        XCTAssertNil(ATHLTHGhostRaceLiveMapPolicy.acceptedComparison(
            value, paused: true, at: clock
        ))
        XCTAssertNil(ATHLTHGhostRaceLiveMapPolicy.acceptedComparison(
            comparison(at: clock.addingTimeInterval(-22)),
            paused: false, at: clock
        ))
        XCTAssertNil(ATHLTHGhostRaceLiveMapPolicy.acceptedComparison(
            comparison(at: clock.addingTimeInterval(8)),
            paused: false, at: clock
        ))
        XCTAssertNil(ATHLTHGhostRaceLiveMapPolicy.acceptedComparison(
            nil, paused: false, at: clock
        ))
    }

    func testInvalidGPSOrProgressNeverAppearsLive() {
        let broken = GhostRaceComparison(
            userLatitude: .nan,
            userLongitude: 10.4,
            ghostLatitude: 63.4,
            ghostLongitude: 10.3,
            userProgress: 1.5,
            ghostProgress: 0.4,
            signedDistanceMeters: 100,
            signedTimeSeconds: 15,
            routeDeviationMeters: 0,
            updatedAt: clock
        )
        XCTAssertNil(ATHLTHGhostRaceLiveMapPolicy.acceptedComparison(
            broken, paused: false, at: clock
        ))
    }

    @MainActor
    func testMapBoundsIncludeStartAndFinish() {
        let points = [
            GhostRacePoint(
                id: 0, latitude: 63.42, longitude: 10.37,
                altitude: nil, elapsedTime: 0, cumulativeMeters: 0
            ),
            GhostRacePoint(
                id: 1, latitude: 63.45, longitude: 10.43,
                altitude: nil, elapsedTime: 1_800, cumulativeMeters: 5_000
            )
        ]
        let reference = GhostRaceReference(
            id: UUID(),
            sourceWorkoutID: UUID(),
            title: "Earlier run",
            startedAt: clock,
            durationSeconds: 1_800,
            distanceMeters: 5_000,
            points: points
        )

        let region = ATHLTHGhostRaceLiveCourseMap.courseRegion(reference)
        XCTAssertGreaterThan(
            region.center.latitude + region.span.latitudeDelta / 2,
            63.45
        )
        XCTAssertLessThan(
            region.center.latitude - region.span.latitudeDelta / 2,
            63.42
        )
        XCTAssertGreaterThan(
            region.center.longitude + region.span.longitudeDelta / 2,
            10.43
        )
    }
}
