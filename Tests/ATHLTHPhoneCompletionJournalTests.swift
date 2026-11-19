import Foundation
import XCTest
@testable import ATHLTH

/// Phase 7: a late finish callback must never replace the newest durable
/// history receipt. Tests use isolated account IDs and remove their files.
final class ATHLTHPhoneCompletionJournalTests: XCTestCase {
    private func workout(start: Date, end: Date) -> PhoneWorkout {
        var result = PhoneWorkout(
            walking: false, start: start,
            resumedAt: start, lastCheckpoint: start
        )
        result.end = end
        return result
    }

    func testOlderCompletionCannotOverwriteNewerReceipt() throws {
        let account = UUID()
        defer { PhoneWorkoutCompletionJournal.remove(userID: account) }
        let base = Date(timeIntervalSince1970: 1_900_000_000)
        let recent = workout(start: base.addingTimeInterval(200),
                             end: base.addingTimeInterval(400))
        let older = workout(start: base,
                            end: base.addingTimeInterval(100))
        try PhoneWorkoutCompletionJournal.save(recent, userID: account)
        try PhoneWorkoutCompletionJournal.save(older, userID: account)
        XCTAssertEqual(PhoneWorkoutCompletionJournal.read(userID: account)?.id,
                       recent.id)
    }

    func testInvalidCompletionCannotReplaceHistory() throws {
        let account = UUID()
        defer { PhoneWorkoutCompletionJournal.remove(userID: account) }
        let base = Date(timeIntervalSince1970: 1_900_000_000)
        let valid = workout(start: base, end: base.addingTimeInterval(90))
        try PhoneWorkoutCompletionJournal.save(valid, userID: account)
        let invalid = workout(start: base.addingTimeInterval(200),
                              end: base.addingTimeInterval(100))
        XCTAssertThrowsError(
            try PhoneWorkoutCompletionJournal.save(invalid, userID: account)
        )
        XCTAssertEqual(PhoneWorkoutCompletionJournal.read(userID: account)?.id,
                       valid.id)
    }

    func testCompletionIsAccountScoped() throws {
        let first = UUID(), second = UUID()
        defer {
            PhoneWorkoutCompletionJournal.remove(userID: first)
            PhoneWorkoutCompletionJournal.remove(userID: second)
        }
        let start = Date(timeIntervalSince1970: 1_900_000_000)
        let record = workout(start: start, end: start.addingTimeInterval(60))
        try PhoneWorkoutCompletionJournal.save(record, userID: first)
        XCTAssertNil(PhoneWorkoutCompletionJournal.read(userID: second))
        XCTAssertEqual(PhoneWorkoutCompletionJournal.read(userID: first)?.id,
                       record.id)
    }

    func testSameEndTimeCannotReplaceAnotherWorkoutReceipt() throws {
        let account = UUID()
        defer { PhoneWorkoutCompletionJournal.remove(userID: account) }
        let start = Date(timeIntervalSince1970: 1_900_000_000)
        let completedAt = start.addingTimeInterval(180)
        let first = workout(start: start, end: completedAt)
        let second = workout(start: start.addingTimeInterval(60), end: completedAt)
        XCTAssertNotEqual(first.id, second.id)
        try PhoneWorkoutCompletionJournal.save(first, userID: account)
        try PhoneWorkoutCompletionJournal.save(second, userID: account)
        XCTAssertEqual(PhoneWorkoutCompletionJournal.read(userID: account)?.id, first.id)
        // Updates for the SAME completed workout are still permitted.
        try PhoneWorkoutCompletionJournal.save(first, userID: account)
        XCTAssertEqual(PhoneWorkoutCompletionJournal.read(userID: account)?.id, first.id)
    }

    func testPhoneResultBreakdownKeepsWallTimeAndActiveTimeSeparate() {
        let start = Date(timeIntervalSince1970: 1_900_000_000)
        var workout = PhoneWorkout(
            walking: false, start: start,
            resumedAt: nil, lastCheckpoint: start.addingTimeInterval(300)
        )
        workout.accumulatedSeconds = 180
        workout.end = start.addingTimeInterval(300)
        workout.distanceMeters = 1_000
        let result = ATHLTHPhoneWorkoutResultBreakdown(workout: workout)
        XCTAssertEqual(result.workoutID, workout.id)
        XCTAssertEqual(result.activeSeconds, 180)
        XCTAssertEqual(result.wallClockSeconds, 300)
        XCTAssertEqual(result.pausedSeconds, 120)
        XCTAssertEqual(result.distanceMeters, 1_000)
        XCTAssertFalse(result.isEstimatedTreadmillDistance)
        XCTAssertTrue(result.segments.isEmpty)
    }

    func testPhoneResultDeduplicatesPartialStepsAndKeepsEstimateProvenance() {
        let start = Date(timeIntervalSince1970: 1_900_000_000)
        var workout = PhoneWorkout(
            walking: false, start: start,
            resumedAt: nil, lastCheckpoint: start.addingTimeInterval(180)
        )
        workout.end = start.addingTimeInterval(180)
        workout.accumulatedSeconds = 180
        workout.runEnvironment = .treadmill
        workout.distanceMeters = 550
        workout.recordedRunningSteps = [
            ATHLTHRecordedRunningStep(
                index: 0, title: "Warmup", phase: "warmup",
                activeSeconds: 50, distanceMeters: 100,
                isUserReported: false, targetPaceSecondsPerKilometer: nil
            ),
            ATHLTHRecordedRunningStep(
                index: 0, title: "Warmup", phase: "warmup",
                activeSeconds: 80, distanceMeters: 220,
                isUserReported: false, targetPaceSecondsPerKilometer: nil
            ),
            ATHLTHRecordedRunningStep(
                index: 1, title: "Run", phase: "main",
                activeSeconds: 100, distanceMeters: 330,
                isUserReported: true, targetPaceSecondsPerKilometer: nil
            ),
            ATHLTHRecordedRunningStep(
                index: 2, title: "Invalid", phase: "main",
                activeSeconds: -.infinity, distanceMeters: 100,
                isUserReported: true, targetPaceSecondsPerKilometer: nil
            )
        ]
        let result = ATHLTHPhoneWorkoutResultBreakdown(workout: workout)
        XCTAssertTrue(result.isEstimatedTreadmillDistance)
        XCTAssertEqual(result.segments.map(\.index), [0, 1])
        XCTAssertEqual(result.segments[0].activeSeconds, 80)
        XCTAssertEqual(result.segments[0].distanceMeters, 220)
        XCTAssertTrue(result.segments.allSatisfy(\.isUserReported))
        XCTAssertEqual(result.distanceMeters, 550)
        // The total is independent of the phase list: the result must
        // not add interval distances to the workout's overall distance.
    }

    func testHealthKitRetryUsesOnlyDurableCompletedWorkoutOfLoadedAccount() {
        let owner = UUID()
        let other = UUID()
        let start = Date(timeIntervalSince1970: 1_900_000_000)
        let finished = workout(
            start: start, end: start.addingTimeInterval(180)
        )
        func allowed(
            _ candidate: PhoneWorkout,
            history: [PhoneWorkout],
            loaded: UUID? = nil,
            deleted: Bool = false
        ) -> Bool {
            ATHLTHPhoneHealthExportPolicy.canExport(
                candidate, ownerID: owner,
                loadedAccountID: loaded ?? owner,
                accountDeleted: deleted, history: history
            )
        }
        XCTAssertTrue(allowed(finished, history: [finished]))
        XCTAssertFalse(allowed(finished, history: []))
        XCTAssertFalse(allowed(finished, history: [finished], loaded: other))
        XCTAssertFalse(allowed(finished, history: [finished], deleted: true))

        var unfinished = finished
        unfinished.end = nil
        XCTAssertFalse(allowed(unfinished, history: [finished]))
        var wrongFinish = finished
        wrongFinish.end = start.addingTimeInterval(181)
        XCTAssertFalse(allowed(wrongFinish, history: [finished]))
        var corrupt = finished
        corrupt.end = start.addingTimeInterval(-1)
        XCTAssertFalse(allowed(corrupt, history: [corrupt]))

        var wrongStart = finished
        wrongStart.start = start.addingTimeInterval(-60)
        XCTAssertFalse(allowed(wrongStart, history: [finished]))
        var uncommitted = finished
        uncommitted.id = UUID()
        XCTAssertFalse(allowed(uncommitted, history: [finished]))
    }
}
