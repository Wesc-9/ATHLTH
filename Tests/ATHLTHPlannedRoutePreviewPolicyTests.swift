import XCTest
@testable import ATHLTH

final class ATHLTHPlannedRoutePreviewPolicyTests: XCTestCase {
    private func run(_ name: String, meters: Double? = nil) -> WorkoutTemplateBlock {
        WorkoutTemplateBlock(
            sequence: 1, kind: .run, title: name,
            exerciseSlug: nil, distanceMeters: meters,
            repetitions: nil, durationSeconds: nil,
            targetWeightKilograms: nil, loadNote: nil, notes: nil,
            phase: .main
        )
    }

    func testRemovingRouteClearsSelectionAndLeavesWarmupUntouched() {
        let id = UUID()
        var route = run("Bø til pizzafjoset og tilbake", meters: 7_500)
        route.routeID = id
        var warmup = run("Oppvarming")
        warmup.durationSeconds = 600

        XCTAssertEqual(
            ATHLTHPlannedRoutePreviewPolicy.activeRouteID(
                selectedRouteID: id, routeTitle: route.title,
                blocks: [warmup, route]
            ), id
        )
        XCTAssertNil(
            ATHLTHPlannedRoutePreviewPolicy.selectedRouteIDAfterDeleting(
                route, selectedRouteID: id, routeTitle: route.title
            )
        )
        XCTAssertNil(
            ATHLTHPlannedRoutePreviewPolicy.activeRouteID(
                selectedRouteID: id, routeTitle: route.title,
                blocks: [warmup]
            )
        )
        XCTAssertNil(
            ATHLTHPlannedRoutePreviewPolicy.distanceKilometers(for: [warmup])
        )
    }

    func testLegacyRouteNameCanBeRemovedWithoutTouchingIndependentDistance() {
        let id = UUID()
        let oldRoute = run("Gammel rute", meters: 7_500)
        let other = run("Fritt løp", meters: 1_000)
        XCTAssertEqual(
            ATHLTHPlannedRoutePreviewPolicy.selectedRouteIDAfterDeleting(
                other, selectedRouteID: id, routeTitle: oldRoute.title
            ), id
        )
        XCTAssertNil(
            ATHLTHPlannedRoutePreviewPolicy.selectedRouteIDAfterDeleting(
                oldRoute, selectedRouteID: id, routeTitle: oldRoute.title
            )
        )
        XCTAssertEqual(
            ATHLTHPlannedRoutePreviewPolicy.distanceKilometers(for: [other]),
            1
        )
    }

    func testDistanceSummaryCountsOnlyVisibleValidSteps() {
        let a = run("Route", meters: 7_500)
        let b = run("Extra", meters: 1_200)
        XCTAssertEqual(
            ATHLTHPlannedRoutePreviewPolicy.distanceKilometers(for: [a, b]) ?? 0,
            8.7, accuracy: 0.000001
        )
        XCTAssertNil(
            ATHLTHPlannedRoutePreviewPolicy.distanceKilometers(for: [])
        )
    }
}
