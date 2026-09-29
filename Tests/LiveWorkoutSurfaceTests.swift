import XCTest
@testable import ATHLTH

final class LiveWorkoutSurfaceTests: XCTestCase {
    func testUrgentRouteOverridesGhostWithSmartPriority() {
        let focus = ATHLTHLiveWorkoutPriorityResolver.resolve(
            configuration: .standard,
            state: ATHLTHLiveWorkoutPriorityState(
                hasRoute: true,
                routeDeviationMeters: 120,
                routeDeviationThresholdMeters: 80,
                hasZoneTarget: true,
                zoneStatus: "On target",
                hasGhost: true,
                hasChallenge: true,
                hasLiveShare: true
            )
        )

        XCTAssertEqual(focus, .routeGuardian)
    }

    func testZoneViolationOverridesGhostWithSmartPriority() {
        let focus = ATHLTHLiveWorkoutPriorityResolver.resolve(
            configuration: .standard,
            state: ATHLTHLiveWorkoutPriorityState(
                hasRoute: true,
                routeDeviationMeters: 10,
                routeDeviationThresholdMeters: 80,
                hasZoneTarget: true,
                zoneStatus: "Above target",
                hasGhost: true,
                hasChallenge: true,
                hasLiveShare: true
            )
        )

        XCTAssertEqual(focus, .zoneLock)
    }

    func testGhostIsSteadyFocusWhenEverythingIsHealthy() {
        let focus = ATHLTHLiveWorkoutPriorityResolver.resolve(
            configuration: .standard,
            state: ATHLTHLiveWorkoutPriorityState(
                hasRoute: true,
                routeDeviationMeters: 10,
                routeDeviationThresholdMeters: 80,
                hasZoneTarget: true,
                zoneStatus: "On target",
                hasGhost: true,
                hasChallenge: true,
                hasLiveShare: true
            )
        )

        XCTAssertEqual(focus, .ghostGap)
    }

    func testDisabledFeatureIsSkipped() {
        var configuration =
            ATHLTHLiveWorkoutSurfaceConfiguration.standard
        configuration.ghostGapEnabled = false

        let focus = ATHLTHLiveWorkoutPriorityResolver.resolve(
            configuration: configuration,
            state: ATHLTHLiveWorkoutPriorityState(
                hasRoute: false,
                routeDeviationMeters: nil,
                routeDeviationThresholdMeters: nil,
                hasZoneTarget: false,
                zoneStatus: nil,
                hasGhost: true,
                hasChallenge: true,
                hasLiveShare: true
            )
        )

        XCTAssertEqual(focus, .liveChallenge)
    }

    func testManualPriorityKeepsGhostAheadOfNonUrgentSurfaces() {
        var configuration =
            ATHLTHLiveWorkoutSurfaceConfiguration.standard
        configuration.smartPriorityEnabled = false

        let focus = ATHLTHLiveWorkoutPriorityResolver.resolve(
            configuration: configuration,
            state: ATHLTHLiveWorkoutPriorityState(
                hasRoute: true,
                routeDeviationMeters: 140,
                routeDeviationThresholdMeters: 80,
                hasZoneTarget: true,
                zoneStatus: "Above target",
                hasGhost: true,
                hasChallenge: true,
                hasLiveShare: true
            )
        )

        XCTAssertEqual(focus, .ghostGap)
    }
}
