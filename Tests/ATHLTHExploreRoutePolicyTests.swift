import CoreLocation
import MapKit
import XCTest
@testable import ATHLTH

final class ATHLTHExploreRoutePolicyTests: XCTestCase {
    func testGeometryBudgetPreservesEndPointsAndSharpTurn() {
        let coordinates = (0..<401).map { index -> CLLocationCoordinate2D in
            if index <= 200 {
                return CLLocationCoordinate2D(
                    latitude: 63.4,
                    longitude: 10.4 + Double(index) * 0.00001
                )
            }
            return CLLocationCoordinate2D(
                latitude: 63.4 + Double(index - 200) * 0.00001,
                longitude: 10.402
            )
        }

        let overview = ATHLTHExploreRoutePolicy.displayPoints(
            coordinates, maximum: 48
        )
        XCTAssertLessThanOrEqual(overview.count, 48)
        XCTAssertEqual(overview.first?.longitude, coordinates.first?.longitude)
        XCTAssertEqual(overview.last?.latitude, coordinates.last?.latitude)
        XCTAssertTrue(overview.contains {
            abs($0.latitude - 63.4) < 0.000001 &&
            abs($0.longitude - 10.402) < 0.000001
        })
    }

    func testLoopVersusPointToPoint() {
        let start = CLLocationCoordinate2D(latitude: 63.4, longitude: 10.4)
        let finish = CLLocationCoordinate2D(latitude: 63.4, longitude: 10.401)
        XCTAssertTrue(ATHLTHExploreRoutePolicy.isLoop([start, start]))
        XCTAssertFalse(ATHLTHExploreRoutePolicy.isLoop([start, finish]))
    }

    func testReversingAWorkoutDoesNotChangeSavedSource() {
        let points = [
            RouteCoordinate(latitude: 63.4, longitude: 10.4, altitude: nil, sequence: 0),
            RouteCoordinate(latitude: 63.5, longitude: 10.5, altitude: nil, sequence: 1)
        ]
        let route = TrainingRoute(
            id: UUID(), ownerID: UUID(), title: "Utendørs runde",
            visibility: .publicProfile, coordinates: points,
            distanceKilometers: 4.0, elevationGainMeters: 120,
            importedFilename: nil, createdAt: Date(),
            startName: "A", endName: "B"
        )

        let reversed = ATHLTHExploreRoutePolicy.reversedForWorkout(route)
        XCTAssertEqual(reversed.id, route.id)
        XCTAssertEqual(reversed.coordinates.first?.longitude, points.last?.longitude)
        XCTAssertEqual(reversed.coordinates.last?.sequence, 1)
        XCTAssertEqual(reversed.startName, "B")
        XCTAssertEqual(reversed.endName, "A")
        XCTAssertEqual(route.coordinates.first?.longitude, points.first?.longitude)
    }

    func testClusteringWith100500And1000Routes() {
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 63.42, longitude: 10.4),
            span: MKCoordinateSpan(latitudeDelta: 0.4, longitudeDelta: 0.4)
        )
        for count in [100, 500, 1_000] {
            let centers = (0..<count).map { index in
                ATHLTHExploreRoutePolicy.Center(
                    id: UUID(),
                    latitude: 63.38 + Double(index % 50) * 0.001,
                    longitude: 10.36 + Double(index / 50) * 0.001
                )
            }
            let clusters = ATHLTHExploreRoutePolicy.clusters(
                centers, region: region
            )
            XCTAssertEqual(clusters.reduce(0) { $0 + $1.count }, count)
            XCTAssertLessThan(clusters.count, count)
            XCTAssertEqual(Set(clusters.flatMap(\.routeIDs)).count, count)
        }
    }

    func testDenseRouteOverviewBudgetAt1000Tracks() {
        let source = (0..<1_000).map { index in
            CLLocationCoordinate2D(
                latitude: 63.4 + Double(index) * 0.000001,
                longitude: 10.4 + sin(Double(index) * 0.04) * 0.001
            )
        }
        measure {
            for _ in 0..<100 {
                let simplified = ATHLTHExploreRoutePolicy.displayPoints(
                    source, maximum: 160
                )
                XCTAssertLessThanOrEqual(simplified.count, 160)
            }
        }
    }
}
