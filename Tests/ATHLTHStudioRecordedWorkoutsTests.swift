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

    func testNearbyHealthWorkoutAcrossBucketBoundaryIsNotDoubleCounted() {
        let start = Date(timeIntervalSince1970: 1_800_000_119)
        let healthLike = WorkoutSummary(localStrengthWorkout: strength(
            started: start
        ))
        let local = strength(started: start.addingTimeInterval(2))
        let result = ATHLTHStudioRecordedWorkouts.merged(
            health: [healthLike], localStrength: [local]
        )
        XCTAssertEqual(result.count, 1)
    }

    func testHealthWorkoutExactly120SecondsAwayIsNotMerged() {
        let start = Date(timeIntervalSince1970: 1_800_000_119)
        let healthLike = WorkoutSummary(localStrengthWorkout: strength(
            started: start.addingTimeInterval(120)
        ))
        let local = strength(started: start)
        let result = ATHLTHStudioRecordedWorkouts.merged(
            health: [healthLike], localStrength: [local]
        )
        XCTAssertEqual(result.count, 2)
    }

    func testHealthWorkout119SecondsAwayIsMerged() {
        let start = Date(timeIntervalSince1970: 1_800_000_119)
        let healthLike = WorkoutSummary(localStrengthWorkout: strength(
            started: start.addingTimeInterval(-119)
        ))
        let local = strength(started: start)
        let result = ATHLTHStudioRecordedWorkouts.merged(
            health: [healthLike], localStrength: [local]
        )
        XCTAssertEqual(result.count, 1)
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

@MainActor
final class ATHLTHStudioAnalyticsTests: XCTestCase {
    private func recordedStrength(started: Date, seconds: TimeInterval = 1_800) -> WorkoutSummary {
        let log = StrengthWorkoutLog(
            id: UUID(),
            plannedSessionID: nil,
            watchSessionID: nil,
            captureDevice: .iPhone,
            trackingMode: .simple,
            title: "Training",
            startedAt: started,
            endedAt: started.addingTimeInterval(seconds),
            exercises: [],
            healthMetrics: LinkedHealthWorkoutMetrics(
                healthKitWorkoutUUID: nil,
                duration: seconds,
                activeCalories: nil,
                averageHeartRate: nil,
                maxHeartRate: nil
            )
        )
        return WorkoutSummary(localStrengthWorkout: log)
    }

    func testSinglePassAnalyticsCountsOnlyWorkoutsWithinSelectedDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Oslo"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 11, day: 10, hour: 16
        )))
        let today = calendar.startOfDay(for: now)
        let yesterday = try XCTUnwrap(calendar.date(
            byAdding: .day, value: -1, to: today
        ))
        let old = try XCTUnwrap(calendar.date(
            byAdding: .day, value: -8, to: today
        ))
        let entries = [
            recordedStrength(started: today.addingTimeInterval(3_600)),
            recordedStrength(started: yesterday.addingTimeInterval(3_600)),
            recordedStrength(started: old.addingTimeInterval(3_600)),
            recordedStrength(started: now.addingTimeInterval(3_600))
        ]
        let report = ATHLTHStudioAnalytics.snapshot(
            from: entries, days: 7, now: now, calendar: calendar
        )
        XCTAssertEqual(report.sessions, 2)
        XCTAssertEqual(report.strengthSessions, 2)
        XCTAssertEqual(report.runningSessions, 0)
        XCTAssertEqual(report.minutes, 60, accuracy: 0.001)
        XCTAssertEqual(report.distanceKilometers, 0, accuracy: 0.001)
        XCTAssertEqual(report.days.count, 7)
        XCTAssertEqual(report.days.reduce(0) { $0 + $1.sessions }, 2)
        XCTAssertEqual(report.days.last?.sessions, 1)
        XCTAssertEqual(report.days[5].sessions, 1)
    }

    func testSinglePassAnalyticsPreservesCalendarDaysAcrossOsloDST() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Oslo"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 26, hour: 16
        )))
        let october24 = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 24, hour: 10
        )))
        let october25 = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 25, hour: 10
        )))
        let report = ATHLTHStudioAnalytics.snapshot(
            from: [recordedStrength(started: october24),
                   recordedStrength(started: october25)],
            days: 3, now: now, calendar: calendar
        )
        XCTAssertEqual(report.days.count, 3)
        XCTAssertEqual(report.days.map(\.sessions), [1, 1, 0])
        XCTAssertEqual(report.sessions, 2)
        XCTAssertEqual(report.minutes, 60, accuracy: 0.001)
    }
}
