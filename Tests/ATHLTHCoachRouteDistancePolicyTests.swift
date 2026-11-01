import CoreLocation
import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHCoachRouteDistancePolicyTests: XCTestCase {
    @MainActor
    func testSevenKilometreTargetRejectsTwelveKilometreSuggestions() {
        let target = 7_000.0
        XCTAssertTrue(ATHLTHCoachRouteGenerator.matchesRequestedDistance(
            actualMeters: 7_000, targetMeters: target
        ))
        XCTAssertTrue(ATHLTHCoachRouteGenerator.matchesRequestedDistance(
            actualMeters: 6_650, targetMeters: target
        ))
        XCTAssertTrue(ATHLTHCoachRouteGenerator.matchesRequestedDistance(
            actualMeters: 7_350, targetMeters: target
        ))
        for meters in [7_500.0, 12_200, 15_600, 15_900] {
            XCTAssertFalse(ATHLTHCoachRouteGenerator.matchesRequestedDistance(
                actualMeters: meters, targetMeters: target
            ), "A 7 km preference must never display \\(meters / 1000) km")
        }
        XCTAssertFalse(ATHLTHCoachRouteGenerator.matchesRequestedDistance(
            actualMeters: .nan, targetMeters: target
        ))
    }

    @MainActor
    func testCorrectedWaypointsMoveTowardsRequestedDistance() {
        let tooLong = ATHLTHCoachRouteGenerator.tunedRadius(
            previousRadius: 2_000, actualMeters: 12_200, targetMeters: 7_000
        )
        XCTAssertLessThan(tooLong, 2_000)
        let tooShort = ATHLTHCoachRouteGenerator.tunedRadius(
            previousRadius: 2_000, actualMeters: 4_000, targetMeters: 7_000
        )
        XCTAssertGreaterThan(tooShort, 2_000)
        XCTAssertLessThanOrEqual(tooShort, 3_300)
    }

    @MainActor
    func testAutomaticPrefersABWithOutAndBackFallback() {
        var brief = ATHLTHCoachRouteBrief()
        XCTAssertEqual(brief.routeShape, .automatic)
        XCTAssertEqual(
            ATHLTHCoachRouteGenerator.preferredShapes(for: brief.routeShape),
            [.oneWay, .outAndBack]
        )
        brief.routeShape = .oneWay
        XCTAssertEqual(
            ATHLTHCoachRouteGenerator.preferredShapes(for: brief.routeShape),
            [.oneWay]
        )
        brief.routeShape = .outAndBack
        XCTAssertEqual(
            ATHLTHCoachRouteGenerator.preferredShapes(for: brief.routeShape),
            [.outAndBack]
        )
    }

    @MainActor
    func testTimeOnlyStillProducesDistanceGoal() {
        var brief = ATHLTHCoachRouteBrief()
        brief.useDistance = false
        brief.useDuration = true
        brief.durationMinutes = 35
        brief.paceMinutesPerKilometer = 5.0
        XCTAssertEqual(brief.targetMeters, 7_000)
    }
}
