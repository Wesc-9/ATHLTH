import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHStudioRecordedWorkoutsTests: XCTestCase {
    private func strength(
        id: UUID = UUID(),
        healthID: UUID? = nil,
        started: Date = .now,
        finished: Bool = true,
        duration: TimeInterval = 2_400
    ) -> StrengthWorkoutLog {
        StrengthWorkoutLog(
            id: id,
            plannedSessionID: nil,
            watchSessionID: nil,
            captureDevice: .iPhone,
            trackingMode: .simple,
            title: "Strength",
            startedAt: started,
            endedAt: finished ? started.addingTimeInterval(duration) : nil,
            exercises: [],
            healthMetrics: LinkedHealthWorkoutMetrics(
                healthKitWorkoutUUID: healthID,
                duration: finished ? duration : nil,
                activeCalories: nil,
                averageHeartRate: nil,
                maxHeartRate: nil
            )
        )
    }

    func testLocallyCompletedStrengthWorkoutAppearsWithoutAppleHealth() {
        let local = strength()
        let result = ATHLTHStudioRecordedWorkouts.merged(
            health: [], localStrength: [local]
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, local.id)
        XCTAssertEqual(result.first?.activity, .strength)
        XCTAssertEqual(result.first?.duration, 2_400)
    }

    func testLinkedWorkoutIsNotDoubleCounted() {
        let healthID = UUID()
        let local = strength(healthID: healthID)
        let healthSummary = WorkoutSummary(localStrengthWorkout: local)
        let result = ATHLTHStudioRecordedWorkouts.merged(
            health: [healthSummary], localStrength: [local]
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, healthID)
    }

    func testMatchingHealthTimesAreNotDoubleCountedWhenLinkMissing() {
        let moment = Date.now
        let local = strength(started: moment)
        let healthLike = WorkoutSummary(
            localStrengthWorkout: strength(started: moment)
        )
        let result = ATHLTHStudioRecordedWorkouts.merged(
            health: [healthLike], localStrength: [local]
        )
        XCTAssertEqual(result.count, 1)
    }

    func testRepeatedLocalLogDoesNotDuplicateHomeRecording() {
        let local = strength()
        let result = ATHLTHStudioRecordedWorkouts.merged(
            health: [], localStrength: [local, local]
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, local.id)
    }

    func testMatchingHealthIsFoundAmongUnrelatedHealthRecords() {
        let moment = Date(timeIntervalSince1970: 1_800_000_000)
        let local = strength(started: moment)
        let unrelated = (0..<80).map { offset in
            WorkoutSummary(localStrengthWorkout: strength(
                started: moment.addingTimeInterval(Double(offset + 2) * 3_600)
            ))
        }
        let match = WorkoutSummary(localStrengthWorkout: strength(
            started: moment.addingTimeInterval(45)
        ))
        let result = ATHLTHStudioRecordedWorkouts.merged(
            health: unrelated + [match], localStrength: [local]
        )
        XCTAssertEqual(result.count, unrelated.count + 1)
    }

    func testDifferentDurationAtNearbyStartRemainsSeparate() {
        let moment = Date(timeIntervalSince1970: 1_800_000_000)
        let local = strength(started: moment)
        let other = WorkoutSummary(localStrengthWorkout: strength(
            started: moment, duration: 900
        ))
        let result = ATHLTHStudioRecordedWorkouts.merged(
            health: [other], localStrength: [local]
        )
        XCTAssertEqual(result.count, 2)
    }

    func testHomeRecommendationPrefersScheduledWorkout() {
        let result = ATHLTHStudioHomeRecommendation.make(
            nextWorkoutTitle: "Intervals",
            workouts: []
        )
        XCTAssertEqual(result.titleEnglish, "Intervals")
        XCTAssertTrue(result.reasonNorwegian.contains("planlagt"))
    }

    func testHomeRecommendationWithoutHistoryIsTransparent() {
        let result = ATHLTHStudioHomeRecommendation.make(
            nextWorkoutTitle: nil,
            workouts: []
        )
        XCTAssertTrue(result.reasonNorwegian.contains("Ingen nylig"))
    }

    func testHomeRecommendationSuggestsBalanceOnlyFromRecordedActivities() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let recentStrength = WorkoutSummary(localStrengthWorkout: strength(
            started: now.addingTimeInterval(-86_400)
        ))
        let result = ATHLTHStudioHomeRecommendation.make(
            nextWorkoutTitle: nil,
            workouts: [recentStrength],
            now: now
        )
        XCTAssertTrue(result.titleNorwegian.contains("rolig tur"))
    }

    func testUnfinishedLocalStrengthIsNotCountedAsRecorded() {
        let active = strength(finished: false)
        let result = ATHLTHStudioRecordedWorkouts.merged(
            health: [], localStrength: [active]
        )
        XCTAssertTrue(result.isEmpty)
    }
}
