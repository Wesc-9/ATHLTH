import XCTest
@testable import ATHLTH

final class ATHLTHRunningAchievementsTests: XCTestCase {
    func testMeasuredKilometerMustImprovePreviousVerifiedTime() {
        let record = ATHLTHRunningAchievementPolicy.fasterTime(
            kind: .fastestKilometer,
            current: 4 * 60 + 55,
            previousBest: 5 * 60 + 3,
            allowedRange: 150...1_200
        )
        XCTAssertEqual(record?.kind, .fastestKilometer)
        XCTAssertEqual(record?.value, 295)
        XCTAssertEqual(record?.previousValue, 303)

        XCTAssertNil(ATHLTHRunningAchievementPolicy.fasterTime(
            kind: .fastestKilometer,
            current: 295,
            previousBest: nil,
            allowedRange: 150...1_200
        ))
        XCTAssertNil(ATHLTHRunningAchievementPolicy.fasterTime(
            kind: .fastestKilometer,
            current: 300,
            previousBest: 300,
            allowedRange: 150...1_200
        ))
        XCTAssertNil(ATHLTHRunningAchievementPolicy.fasterTime(
            kind: .fastestKilometer,
            current: 299.5,
            previousBest: 300,
            allowedRange: 150...1_200
        ))
        XCTAssertNil(ATHLTHRunningAchievementPolicy.fasterTime(
            kind: .fastestKilometer,
            current: 20,
            previousBest: 295,
            allowedRange: 150...1_200
        ))
    }

    func testFiveKilometreRecordRequiresRealHistoricalComparison() {
        XCTAssertNotNil(ATHLTHRunningAchievementPolicy.fasterTime(
            kind: .fastestFiveKilometers,
            current: 1_490,
            previousBest: 1_550,
            allowedRange: 750...9_000
        ))
        XCTAssertNil(ATHLTHRunningAchievementPolicy.fasterTime(
            kind: .fastestFiveKilometers,
            current: 1_490,
            previousBest: nil,
            allowedRange: 750...9_000
        ))
    }

    func testDistanceAndPeakHRRequireImprovement() {
        XCTAssertEqual(ATHLTHRunningAchievementPolicy.longestRun(
            currentMeters: 10_200, previousBestMeters: 9_800
        )?.kind, .longestRun)
        XCTAssertNil(ATHLTHRunningAchievementPolicy.longestRun(
            currentMeters: 10_001, previousBestMeters: 10_000
        ))
        XCTAssertNil(ATHLTHRunningAchievementPolicy.longestRun(
            currentMeters: 10_200, previousBestMeters: nil
        ))
        XCTAssertNil(ATHLTHRunningAchievementPolicy.maximumHeartRate(
            currentBPM: 190, previousMaximumBPM: 189
        ))
        XCTAssertNil(ATHLTHRunningAchievementPolicy.maximumHeartRate(
            currentBPM: 249, previousMaximumBPM: 188
        ))
        XCTAssertEqual(ATHLTHRunningAchievementPolicy.maximumHeartRate(
            currentBPM: 190, previousMaximumBPM: 185
        )?.kind, .maximumRecordedHeartRate)
    }

    func testRouteRecordNeedsSameAthleteRouteEligibleMatchAndOlderAttempt() {
        let athlete = UUID()
        let route = UUID()
        let currentWorkout = UUID()
        let priorWorkout = UUID()
        let current = attempt(
            route: route, athlete: athlete, workout: currentWorkout,
            seconds: 1_750, started: 500, match: 92
        )
        let prior = attempt(
            route: route, athlete: athlete, workout: priorWorkout,
            seconds: 1_780, started: 400, match: 90
        )
        let result = ATHLTHRunningAchievementPolicy.routePersonalBest(
            current: current, attempts: [prior, current],
            userID: athlete, workoutID: currentWorkout,
            routeName: "Testløypa"
        )
        XCTAssertEqual(result?.kind, .routePersonalBest)
        XCTAssertEqual(result?.routeTitle, "Testløypa")
        XCTAssertEqual(result?.previousValue, 1_780)

        XCTAssertNil(ATHLTHRunningAchievementPolicy.routePersonalBest(
            current: current, attempts: [current],
            userID: athlete, workoutID: currentWorkout, routeName: nil
        ))
        XCTAssertNil(ATHLTHRunningAchievementPolicy.routePersonalBest(
            current: current, attempts: [
                attempt(route: route, athlete: UUID(), workout: priorWorkout,
                        seconds: 1_780, started: 400, match: 91)
            ],
            userID: athlete, workoutID: currentWorkout, routeName: nil
        ))
        XCTAssertNil(ATHLTHRunningAchievementPolicy.routePersonalBest(
            current: current, attempts: [
                attempt(route: route, athlete: athlete, workout: priorWorkout,
                        seconds: 1_780, started: 400, match: 76)
            ],
            userID: athlete, workoutID: currentWorkout, routeName: nil
        ))
        XCTAssertNil(ATHLTHRunningAchievementPolicy.routePersonalBest(
            current: attempt(route: route, athlete: athlete, workout: currentWorkout,
                             seconds: 1_750, started: 500, match: 80),
            attempts: [prior],
            userID: athlete, workoutID: currentWorkout, routeName: nil
        ))
    }

    func testRouteResultMustBeatPreviousBestNotOnlyLastAttempt() {
        let athlete = UUID(), route = UUID(), workout = UUID()
        let current = attempt(route: route, athlete: athlete, workout: workout,
                              seconds: 1_790, started: 600, match: 90)
        let attempts = [
            attempt(route: route, athlete: athlete, workout: UUID(),
                    seconds: 1_800, started: 400, match: 90),
            attempt(route: route, athlete: athlete, workout: UUID(),
                    seconds: 1_770, started: 300, match: 95),
            current
        ]
        XCTAssertNil(ATHLTHRunningAchievementPolicy.routePersonalBest(
            current: current, attempts: attempts,
            userID: athlete, workoutID: workout, routeName: nil
        ))
    }

    func testOnlyTopThreeAreShownInStablePriorityOrder() {
        let sample: [ATHLTHRunningAchievement] = [
            .init(kind: .maximumRecordedHeartRate, value: 190, previousValue: 185),
            .init(kind: .fastestFiveKilometers, value: 1_400, previousValue: 1_500),
            .init(kind: .fastestKilometer, value: 270, previousValue: 275),
            .init(kind: .routePersonalBest, value: 1_500, previousValue: 1_600)
        ]
        XCTAssertEqual(ATHLTHRunningAchievementPolicy.top(sample).map(\.kind),
                       [.routePersonalBest, .fastestKilometer, .fastestFiveKilometers])
        XCTAssertTrue(ATHLTHRunningAchievementPolicy.top([]).isEmpty)
    }

    private func attempt(
        route: UUID,
        athlete: UUID,
        workout: UUID,
        seconds: Double,
        started: TimeInterval,
        match: Double
    ) -> RouteAttemptRecord {
        RouteAttemptRecord(
            id: UUID(), routeID: route, userID: athlete,
            workoutID: workout, activityType: "running",
            startedAt: Date(timeIntervalSince1970: started),
            durationSeconds: seconds, distanceMeters: 5_000,
            routeMatchPercent: match, averageDeviationMeters: 8,
            maxDeviationMeters: 30, source: "apple_health",
            username: nil, displayName: nil, avatarURL: nil
        )
    }
}
