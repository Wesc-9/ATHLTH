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

    private func routeRecord(
        name: String, source: String,
        coordinates: [RouteCoordinate],
        sourceID: Int64 = 1
    ) -> PublicTrailRecord {
        PublicTrailRecord(
            id: UUID(),
            osmRelationID: sourceID,
            name: name,
            routeKind: "hiking",
            network: nil,
            reference: nil,
            operatorName: nil,
            symbol: nil,
            coordinates: coordinates,
            distanceKilometers: 1.3,
            centerLatitude: 67.28,
            centerLongitude: 14.44,
            leaderboardEnabled: false,
            athlthVerified: false,
            source: source
        )
    }

    func testKartverketAndOSMGeometryAreOneRouteDespiteDifferentNamesAndDirection() {
        let geometry = (0...10).map {
            RouteCoordinate(
                latitude: 67.28, longitude: 14.42 + Double($0) * 0.003,
                altitude: nil, sequence: $0
            )
        }
        let kartverket = routeRecord(
            name: "Kystløypa", source: "kartverket_turrutebasen",
            coordinates: geometry, sourceID: -1
        )
        let osm = routeRecord(
            name: "Running Trail Bodø", source: "openstreetmap",
            coordinates: geometry.reversed().enumerated().map {
                RouteCoordinate(
                    latitude: $0.element.latitude, longitude: $0.element.longitude,
                    altitude: nil, sequence: $0.offset
                )
            }, sourceID: 123
        )
        let found = PublicTrailDeduplicator.unique([osm, kartverket])
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.id, kartverket.id)
    }

    func testCrossingTrailsRemainSeparateEvenWithSameCenterAndLength() {
        let eastWest = (0...10).map {
            RouteCoordinate(latitude: 67.28,
                            longitude: 14.425 + Double($0) * 0.003,
                            altitude: nil, sequence: $0)
        }
        let northSouth = (0...10).map {
            RouteCoordinate(latitude: 67.265 + Double($0) * 0.003,
                            longitude: 14.44,
                            altitude: nil, sequence: $0)
        }
        let first = routeRecord(
            name: "Øst–vest", source: "kartverket_turrutebasen",
            coordinates: eastWest
        )
        let second = routeRecord(
            name: "Nord–sør", source: "openstreetmap",
            coordinates: northSouth
        )
        XCTAssertEqual(PublicTrailDeduplicator.unique([first, second]).count, 2)
    }

    func testSourceIndependentDuplicatesDoNotDiscardTwoOwnRouteObjects() {
        let points = (0...10).map {
            RouteCoordinate(latitude: 67.28,
                            longitude: 14.425 + Double($0) * 0.003,
                            altitude: nil, sequence: $0)
        }
        let first = routeRecord(
            name: "Alternativ A", source: "kartverket_turrutebasen",
            coordinates: points, sourceID: -10
        )
        let second = routeRecord(
            name: "Alternativ B", source: "kartverket_turrutebasen",
            coordinates: points, sourceID: -11
        )
        XCTAssertEqual(PublicTrailDeduplicator.unique([first, second]).count, 2)
    }
}
