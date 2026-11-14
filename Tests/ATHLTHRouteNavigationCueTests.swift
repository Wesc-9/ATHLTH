import CoreLocation
import XCTest
@testable import ATHLTH

final class ATHLTHRouteNavigationCueTests: XCTestCase {

    func testLegacyRouteAlertsPreserveTurnCoachingAndSafeDefaults() throws {
        let legacy = """
        {
          "enabled": true,
          "deviationMeters": 80,
          "graceSeconds": 20,
          "repeatSeconds": 120,
          "delivery": "both",
          "announceBackOnRoute": true
        }
        """
        let restored = try JSONDecoder().decode(
            WatchRouteAlertConfiguration.self, from: Data(legacy.utf8)
        )
        XCTAssertTrue(restored.shouldAnnounceUpcomingTurns)
        XCTAssertEqual(restored.resolvedTurnCueLeadMeters, 85)
        XCTAssertTrue(restored.shouldAnnounceTurn(distanceMeters: 75))
        XCTAssertFalse(restored.shouldAnnounceTurn(distanceMeters: 130))
    }

    func testRouteCoachTurnLeadDistanceAndDisableStateSurviveRoundTrip() throws {
        var settings = WatchRouteAlertConfiguration.standard
        settings.announceUpcomingTurns = true
        settings.turnCueLeadMeters = 140
        let saved = try JSONDecoder().decode(
            WatchRouteAlertConfiguration.self,
            from: JSONEncoder().encode(settings)
        )
        var workout = RouteGuardianDraft()
        workout.load(configuration: saved)
        XCTAssertTrue(workout.announceUpcomingTurns)
        XCTAssertEqual(workout.turnCueLeadMeters, 140)
        XCTAssertTrue(workout.configuration.shouldAnnounceTurn(distanceMeters: 118))
        XCTAssertFalse(workout.configuration.shouldAnnounceTurn(distanceMeters: 65))

        workout.announceUpcomingTurns = false
        XCTAssertFalse(workout.configuration.shouldAnnounceTurn(distanceMeters: 118))
        workout.enabled = false
        workout.announceUpcomingTurns = true
        XCTAssertFalse(workout.configuration.shouldAnnounceTurn(distanceMeters: 118))
    }

    func testInvalidTurnLeadAndGPSDistanceNeverCreateTurnPrompts() {
        var config = WatchRouteAlertConfiguration.standard
        config.turnCueLeadMeters = .infinity
        XCTAssertEqual(config.resolvedTurnCueLeadMeters, 85)
        XCTAssertFalse(config.shouldAnnounceTurn(distanceMeters: .nan))
        XCTAssertFalse(config.shouldAnnounceTurn(distanceMeters: -.infinity))
    }

    private func coordinate(_ lat: Double, _ lon: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    func testUpcomingRightTurnUsesRouteGeometry() {
        // Northbound for 100 metres, then eastbound.
        let route = [
            coordinate(60.0000, 10.0000),
            coordinate(60.00045, 10.0000),
            coordinate(60.00090, 10.0000),
            coordinate(60.00090, 10.0010),
            coordinate(60.00090, 10.0018)
        ]
        let instruction = ATHLTHRouteNavigationCue.nextTurn(
            route: route, nearestIndex: 0
        )
        XCTAssertEqual(instruction?.direction, .right)
        XCTAssertEqual(instruction?.offRoute, false)
        XCTAssertGreaterThan(instruction?.distanceMeters ?? 0, 90)
    }

    func testUpcomingTurnMeasuresFromProjectedProgressInsteadOfNearestVertex() {
        let route = [
            coordinate(60.0000, 10.0000),
            coordinate(60.00045, 10.0000),
            coordinate(60.00090, 10.0000),
            coordinate(60.00090, 10.0010),
            coordinate(60.00090, 10.0018)
        ]
        let instruction = ATHLTHRouteNavigationCue.nextTurn(
            route: route, nearestIndex: 2,
            cumulativeMeters: [0, 50, 100, 150, 200],
            progressMeters: 67
        )
        XCTAssertEqual(instruction?.direction, .right)
        XCTAssertEqual(instruction?.distanceMeters, 33)
    }

    func testStraightRouteDoesNotInventIntersection() {
        let route = (0...6).map {
            coordinate(60.0 + Double($0) * 0.00035, 10.0)
        }
        XCTAssertNil(ATHLTHRouteNavigationCue.nextTurn(
            route: route, nearestIndex: 1
        ))
    }

    func testRecoveryRespectsRunnerHeading() {
        let route = [
            coordinate(60.0000, 10.0000),
            coordinate(60.0005, 10.0000)
        ]
        let instruction = ATHLTHRouteNavigationCue.recovery(
            user: coordinate(60.0, 9.999),
            courseDegrees: 0,
            route: route,
            nearestIndex: 0,
            deviationMeters: 56
        )
        XCTAssertEqual(instruction?.direction, .right)
        XCTAssertTrue(instruction?.text(norwegian: true).contains("høyre") == true)
    }

    func testUnknownCourseNeverGuessesLeftOrRight() {
        let instruction = ATHLTHRouteNavigationCue.recovery(
            user: coordinate(60.0, 9.999),
            courseDegrees: -1,
            route: [coordinate(60, 10), coordinate(60.001, 10)],
            nearestIndex: 0,
            deviationMeters: 55
        )
        XCTAssertEqual(instruction?.direction, .ahead)
    }

    func testGhostDisableCommandRequiresMatchingFreshWorkout() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let request = ATHLTHGhostDisableDuringWorkout(
            workoutStartedAt: start,
            requestedAt: start.addingTimeInterval(140)
        )
        XCTAssertTrue(request.isValid(
            workoutStart: start,
            now: start.addingTimeInterval(142)
        ))
        XCTAssertFalse(request.isValid(
            workoutStart: start.addingTimeInterval(60),
            now: start.addingTimeInterval(142)
        ))
        XCTAssertFalse(request.isValid(
            workoutStart: start,
            now: start.addingTimeInterval(175)
        ))
    }
}
