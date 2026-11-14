import Foundation
import XCTest
@testable import ATHLTH

@MainActor
final class ATHLTHRouteDetailsPolicyTests: XCTestCase {
    private func route(
        coordinates: [RouteCoordinate],
        routeSource: String? = nil
    ) -> TrainingRoute {
        TrainingRoute(
            id: UUID(), ownerID: UUID(), title: "Testløype",
            visibility: .privateOnly,
            coordinates: coordinates,
            distanceKilometers: 5,
            elevationGainMeters: nil,
            importedFilename: nil,
            createdAt: Date(),
            routeSource: routeSource
        )
    }

    private func point(_ latitude: Double, _ longitude: Double,
                       _ elevation: Double?, _ sequence: Int) -> RouteCoordinate {
        RouteCoordinate(latitude: latitude, longitude: longitude,
                        altitude: elevation, sequence: sequence)
    }

    func testLegacyRouteJSONWithoutNewPropertiesDecodes() throws {
        let older = route(coordinates: [
            point(63.4, 10.4, nil, 0),
            point(63.5, 10.5, nil, 1)
        ])
        let data = try JSONEncoder().encode(older)
        var dict = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        dict.removeValue(forKey: "tags")
        dict.removeValue(forKey: "surfacePercentages")
        let legacyData = try JSONSerialization.data(withJSONObject: dict)
        let decoded = try JSONDecoder().decode(TrainingRoute.self, from: legacyData)
        XCTAssertNil(decoded.tags)
        XCTAssertNil(decoded.surfacePercentages)
        XCTAssertEqual(decoded.coordinates.count, 2)
    }

    func testUnspecifiedSurfaceStaysUnknown() {
        XCTAssertEqual(ATHLTHRouteDetailsPolicy.cleanedSurfaces([:]), [:])
        XCTAssertEqual(ATHLTHRouteDetailsPolicy.unclassifiedPercent([:]), 100)
        XCTAssertEqual(ATHLTHRouteDetailsPolicy.cleanedSurfaces(
            ["asphalt": 70, "trail": 20]
        ), ["asphalt": 70, "trail": 20])
        XCTAssertEqual(ATHLTHRouteDetailsPolicy.unclassifiedPercent(
            ["asphalt": 70, "trail": 20]
        ), 10)
    }

    func testSurfaceTotalsNeverExceed100AndUnknownKeysAreDropped() {
        let result = ATHLTHRouteDetailsPolicy.cleanedSurfaces([
            "asphalt": 80, "gravel": 80,
            "invented": 40, "trail": -5
        ])
        XCTAssertEqual(result.values.reduce(0, +), 100)
        XCTAssertNil(result["invented"])
        XCTAssertEqual(ATHLTHRouteDetailsPolicy.unclassifiedPercent(result), 0)
    }

    func testTagCleaningDeduplicatesAndBounds() {
        XCTAssertEqual(
            ATHLTHRouteDetailsPolicy.cleanedTags(
                [" Intervall ", "intervall", "Utsikt", "", "  "]
            ),
            ["Intervall", "Utsikt"]
        )
        XCTAssertEqual(
            ATHLTHRouteDetailsPolicy.cleanedTags((0..<15).map { "Tag\($0)" }).count,
            8
        )
    }

    func testElevationNotInventedForRoutesWithoutAltitude() {
        let route = route(coordinates: [
            point(63.4, 10.4, nil, 0),
            point(63.41, 10.41, nil, 1)
        ])
        XCTAssertTrue(ATHLTHRouteDetailsPolicy.elevationSamples(route).isEmpty)
    }

    func testAvailableElevationOrderedByGPSSequence() {
        let route = route(coordinates: [
            point(63.41, 10.41, 160, 1),
            point(63.4, 10.4, 130, 0),
            point(63.42, 10.42, 145, 2)
        ])
        XCTAssertEqual(ATHLTHRouteDetailsPolicy.elevationSamples(route),
                       [130, 160, 145])
        let change = try? XCTUnwrap(
            ATHLTHRouteDetailsPolicy.ascentDescent([130, 160, 145])
        )
        XCTAssertEqual(change?.ascent, 30)
        XCTAssertEqual(change?.descent, 15)
    }

    func testRouteTypeUsesGeometryAndExplicitOutAndBackSource() {
        let first = point(63.40, 10.40, nil, 0)
        let second = point(63.41, 10.41, nil, 1)
        let last = point(63.40, 10.40, nil, 2)
        XCTAssertEqual(
            ATHLTHRouteDetailsPolicy.shape(route(coordinates: [first, second, last],
                                                  routeSource: "apple_maps_walking_out_and_back")),
            .outAndBack
        )
        XCTAssertEqual(
            ATHLTHRouteDetailsPolicy.shape(route(coordinates: [first, second])),
            .pointToPoint
        )
    }

    func testEstimatesAreApproximateAndNeverMadeUpForZeroDistance() {
        XCTAssertNil(ATHLTHRouteDetailsPolicy.estimateSeconds(
            distanceKilometers: 0, running: true
        ))
        XCTAssertEqual(ATHLTHRouteDetailsPolicy.estimateSeconds(
            distanceKilometers: 5, running: false
        ), 3_600)
        XCTAssertEqual(ATHLTHRouteDetailsPolicy.estimateSeconds(
            distanceKilometers: 5, running: true
        ), 1_800)
    }
}
