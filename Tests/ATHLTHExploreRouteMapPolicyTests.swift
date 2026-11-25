import CoreLocation
import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHExploreRouteMapPolicyTests: XCTestCase {
    func testStudioExploreUsesActualDetailWidth() {
        XCTAssertFalse(ATHLTHExploreStudioLayoutPolicy.usesWideMap(width: 600))
        XCTAssertNil(ATHLTHExploreStudioLayoutPolicy.previewWidth(width: 600))
        XCTAssertNil(ATHLTHExploreStudioLayoutPolicy.controlsWidth(width: 600))
        XCTAssertTrue(ATHLTHExploreStudioLayoutPolicy.usesWideMap(width: 800))
        XCTAssertEqual(ATHLTHExploreStudioLayoutPolicy.previewWidth(width: 800), 384)
        XCTAssertEqual(ATHLTHExploreStudioLayoutPolicy.previewWidth(width: 1200), 480)
        XCTAssertEqual(ATHLTHExploreStudioLayoutPolicy.controlsWidth(width: 800), 680)
        XCTAssertFalse(ATHLTHExploreStudioLayoutPolicy.usesWideMap(width: .infinity))
    }

    private func point(_ lat: Double, _ lon: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    func testLineTapSelectsTheActualRouteRatherThanADifferentRouteWithin240m() {
        let selectedID = UUID()
        let parallelID = UUID()
        let candidates: [ATHLTHExploreRouteMapPolicy.Candidate] = [
            .init(id: parallelID, points: [
                point(63.4408, 10.4100), point(63.4408, 10.4200)
            ]),
            .init(id: selectedID, points: [
                point(63.4400, 10.4100), point(63.4400, 10.4200)
            ])
        ]
        XCTAssertEqual(
            ATHLTHExploreRouteMapPolicy.nearestRouteID(
                to: point(63.4400, 10.4160),
                candidates: candidates, toleranceMeters: 16
            ),
            selectedID
        )
        XCTAssertNil(
            ATHLTHExploreRouteMapPolicy.nearestRouteID(
                to: point(63.4420, 10.4160),
                candidates: candidates, toleranceMeters: 16
            ),
            "A map tap 130+ m away must not select another route"
        )
    }

    func testPickingUsesSegmentsNotDownsampledWaypoints() {
        let id = UUID()
        let route = ATHLTHExploreRouteMapPolicy.Candidate(
            id: id,
            points: [point(63.4400, 10.4100), point(63.4400, 10.4200)]
        )
        XCTAssertEqual(
            ATHLTHExploreRouteMapPolicy.nearestRouteID(
                to: point(63.4400, 10.4150),
                candidates: [route], toleranceMeters: 12
            ),
            id,
            "Midpoint is near the line even when it is far from both samples"
        )
    }

    func testPreviouslySelectedOverlappingLineKeepsItsIdentity() {
        let original = UUID()
        let other = UUID()
        let geometry = [point(63.4400, 10.4100), point(63.4400, 10.4200)]
        let candidates: [ATHLTHExploreRouteMapPolicy.Candidate] = [
            .init(id: other, points: geometry),
            .init(id: original, points: geometry)
        ]
        XCTAssertEqual(
            ATHLTHExploreRouteMapPolicy.nearestRouteID(
                to: point(63.4400, 10.4150),
                candidates: candidates, toleranceMeters: 18,
                preferredID: original
            ),
            original
        )
    }

    func testDirectionCuesAreAtTurnsNotAnArbitraryThirdOfTheRoute() {
        let route = [
            point(63.4400, 10.4100),
            point(63.4415, 10.4100),
            point(63.4430, 10.4100),
            point(63.4430, 10.4130),
            point(63.4430, 10.4160)
        ]
        let turns = ATHLTHExploreRouteMapPolicy.directionCues(for: route)
        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turns[0].id, 2)
        XCTAssertEqual(turns[0].bearingDegrees, 90, accuracy: 7)
        XCTAssertTrue(turns[0].coordinate.longitude > route[2].longitude)
        XCTAssertEqual(
            ATHLTHExploreRouteMapPolicy.directionCues(
                for: [point(63.4400, 10.4100),
                      point(63.4420, 10.4100),
                      point(63.4440, 10.4100)]
            ).count,
            0,
            "Do not clutter straight segments with false turn arrows"
        )
    }

    func testWalkAndRunEstimatesAreDifferentWithoutInventingARecordedTime() {
        let estimates = ATHLTHExploreRouteMapPolicy.estimatedTimes(
            distanceKilometers: 4
        )
        XCTAssertEqual(estimates?.walk, 48 * 60)
        XCTAssertEqual(estimates?.run, 24 * 60)
        let published = ATHLTHExploreRouteMapPolicy.estimatedTimes(
            distanceKilometers: 4,
            publicWalkSeconds: 3250,
            publicRunSeconds: 1150
        )
        XCTAssertEqual(published?.walk, 3250)
        XCTAssertEqual(published?.run, 1150)
        XCTAssertNil(ATHLTHExploreRouteMapPolicy.estimatedTimes(
            distanceKilometers: 0
        ))
    }

    func testSurfaceIsSourceBoundAndUnknownIsNeverInvented() {
        let result = ATHLTHExploreRouteMapPolicy.surfaceLabel(
            percentages: ["asphalt": 70, "gravel": 30]
        )
        XCTAssertTrue(result.contains("70"))
        XCTAssertTrue(result.contains("30"))
        let unknown = ATHLTHExploreRouteMapPolicy.surfaceLabel(percentages: nil)
        XCTAssertFalse(unknown.contains("Asfalt"))
        XCTAssertFalse(unknown.contains("100"))
        XCTAssertEqual(
            ATHLTHExploreRouteMapPolicy.surfaceLabel(
                percentages: [:], publishedSummary: "Gravel and forest path"
            ),
            "Gravel and forest path"
        )
    }
}
