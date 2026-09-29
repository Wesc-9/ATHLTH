import CoreLocation
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

extension LiveWorkoutSurfaceTests {
    func testSharedRouteGuidanceReportsProgressAndDeviation() {
        let route = [
            CLLocation(
                latitude: 63.4305,
                longitude: 10.3951
            ),
            CLLocation(
                latitude: 63.4310,
                longitude: 10.4051
            ),
            CLLocation(
                latitude: 63.4315,
                longitude: 10.4151
            )
        ]
        let geometry =
            ATHLTHRouteGuidanceEngine
                .cumulativeGeometry(
                    locations: route
                )
        let location =
            CLLocation(
                latitude: 63.4310,
                longitude: 10.4051
            )

        let state =
            ATHLTHRouteGuidanceEngine.state(
                location: location,
                routeLocations: route,
                cumulativeMeters:
                    geometry.cumulativeMeters,
                geometryTotalMeters:
                    geometry.totalMeters,
                advertisedDistanceMeters:
                    geometry.totalMeters
            )

        XCTAssertNotNil(state)
        XCTAssertEqual(
            state?.progressPercent ?? 0,
            50,
            accuracy: 8
        )
        XCTAssertLessThan(
            state?.deviationMeters ??
                .greatestFiniteMagnitude,
            5
        )
    }

    func testSharedStructuredStepEngineHandlesTimeAndDistance() {
        let timeStep =
            WatchRunningWorkoutStep(
                id: UUID(),
                title: "Tempo",
                measure: .time,
                distanceMeters: nil,
                durationSeconds: 60,
                intensityText: nil
            )
        let distanceStep =
            WatchRunningWorkoutStep(
                id: UUID(),
                title: "1 km",
                measure: .distance,
                distanceMeters: 1_000,
                durationSeconds: nil,
                intensityText: nil
            )

        XCTAssertTrue(
            ATHLTHRunningStepEngine
                .isCompleted(
                    step: timeStep,
                    elapsedTime: 160,
                    distanceMeters: 0,
                    stepStartElapsedTime: 100,
                    stepStartDistanceMeters: 0
                )
        )
        XCTAssertTrue(
            ATHLTHRunningStepEngine
                .isCompleted(
                    step: distanceStep,
                    elapsedTime: 0,
                    distanceMeters: 2_500,
                    stepStartElapsedTime: 0,
                    stepStartDistanceMeters: 1_500
                )
        )
    }
}

