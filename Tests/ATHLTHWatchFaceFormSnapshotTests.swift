import XCTest
@testable import ATHLTH

final class ATHLTHWatchFaceFormSnapshotTests: XCTestCase {
    func testScoreExpiresAtMidnightAndRejectsFutureData() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Oslo"))
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 27, hour: 12)))
        let score = ATHLTHWatchFaceFormSnapshot(score: 83, updatedAt: day)
        let midnight = try XCTUnwrap(ATHLTHWatchFaceFormSnapshot.nextDay(after: day, calendar: calendar))
        XCTAssertEqual(score.currentScore(at: day, calendar: calendar), 83)
        XCTAssertEqual(score.currentScore(at: midnight.addingTimeInterval(-1), calendar: calendar), 83)
        XCTAssertNil(score.currentScore(at: midnight, calendar: calendar))
        XCTAssertNil(score.currentScore(at: day.addingTimeInterval(-1), calendar: calendar))
        XCTAssertNil(ATHLTHWatchFaceFormSnapshot(score: 101, updatedAt: day).currentScore(at: day, calendar: calendar))
    }

    func testCacheChangesAndClearsWithoutRepeatedReloads() throws {
        let suite = "ATHLTHWatchFaceFormSnapshotTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let snapshot = ATHLTHWatchFaceFormSnapshot(score: 71, updatedAt: Date())
        XCTAssertTrue(ATHLTHWatchFaceFormSnapshot.write(snapshot, to: defaults))
        XCTAssertEqual(ATHLTHWatchFaceFormSnapshot.read(from: defaults), snapshot)
        XCTAssertFalse(ATHLTHWatchFaceFormSnapshot.write(snapshot, to: defaults))
        XCTAssertTrue(ATHLTHWatchFaceFormSnapshot.write(nil, to: defaults))
        XCTAssertNil(ATHLTHWatchFaceFormSnapshot.read(from: defaults))
        XCTAssertFalse(ATHLTHWatchFaceFormSnapshot.write(nil, to: defaults))
    }
}
