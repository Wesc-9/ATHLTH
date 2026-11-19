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
}
