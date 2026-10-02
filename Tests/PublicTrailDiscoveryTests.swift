import CoreLocation
import XCTest
@testable import ATHLTH

final class PublicTrailDiscoveryTests:
    XCTestCase {
    func testValidPublicTrailBuildsTrainingRoute() {
        let trail =
            PublicTrailRecord(
                id: UUID(),
                osmRelationID: 123,
                name: "Test Trail",
                routeKind: "hiking",
                network: "lwn",
                reference: "T1",
                operatorName: nil,
                symbol: nil,
                coordinates: [
                    RouteCoordinate(
                        latitude: 63.42,
                        longitude: 10.36,
                        altitude: nil,
                        sequence: 0
                    ),
                    RouteCoordinate(
                        latitude: 63.43,
                        longitude: 10.37,
                        altitude: nil,
                        sequence: 1
                    )
                ],
                distanceKilometers: 2.4,
                centerLatitude: 63.425,
                centerLongitude: 10.365,
                leaderboardEnabled: true,
                athlthVerified: false,
                source: "openstreetmap"
            )

        XCTAssertTrue(trail.isUsable)

        let route = trail.trainingRoute

        XCTAssertEqual(
            route.id,
            trail.id
        )
        XCTAssertEqual(
            route.title,
            "Test Trail"
        )
        XCTAssertEqual(
            route.routeSource,
            "openstreetmap"
        )
        XCTAssertEqual(
            route.ownerID,
            PublicTrailRecord
                .publicSourceOwnerID
        )
        XCTAssertEqual(
            route.visibility,
            .publicProfile
        )
    }

    func testInvalidPublicTrailIsRejected() {
        let trail =
            PublicTrailRecord(
                id: UUID(),
                osmRelationID: 456,
                name: "Invalid Trail",
                routeKind: "foot",
                network: "lwn",
                reference: nil,
                operatorName: nil,
                symbol: nil,
                coordinates: [
                    RouteCoordinate(
                        latitude: 95,
                        longitude: 10.36,
                        altitude: nil,
                        sequence: 0
                    ),
                    RouteCoordinate(
                        latitude: 63.43,
                        longitude: 10.37,
                        altitude: nil,
                        sequence: 1
                    )
                ],
                distanceKilometers: 2.4,
                centerLatitude: 63.425,
                centerLongitude: 10.365,
                leaderboardEnabled: true,
                athlthVerified: false,
                source: "openstreetmap"
            )

        XCTAssertFalse(trail.isUsable)
    }
}
