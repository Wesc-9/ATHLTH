import Foundation
import XCTest
@testable import ATHLTH

final class CustomQuickWorkoutJournalTests: XCTestCase {
    private var setup: CustomQuickWorkoutConfiguration {
        CustomQuickWorkoutConfiguration(
            activity: .rowing, method: .intervals,
            durationMinutes: 20, workSeconds: 40, restSeconds: 20,
            rounds: 8
        )
    }

    func testPhoneTimedWorkoutKeepsManualDistanceUnverified() throws {
        let record = try XCTUnwrap(CustomQuickWorkoutRecord.make(
            configuration: setup,
            recordedAt: Date(timeIntervalSince1970: 1_800_000_000),
            durationSeconds: 1_230,
            distanceKilometers: 4.2,
            perceivedEffort: 7,
            notes: "Good session",
            evidence: .phoneTimer
        ))
        XCTAssertTrue(record.manuallyEnteredMetricsAreUnverified)
        XCTAssertEqual(record.evidence, .phoneTimer)
        XCTAssertEqual(record.manualDistanceKilometers, 4.2)
        XCTAssertEqual(record.durationSeconds, 1_230)
        XCTAssertEqual(record.activity, .rowing)
        XCTAssertEqual(record.method, .intervals)

        let decoded = try JSONDecoder().decode(
            CustomQuickWorkoutRecord.self,
            from: JSONEncoder().encode(record)
        )
        XCTAssertEqual(decoded, record)
    }

    func testRetrospectiveWorkoutCanBeSavedWithoutDistance() throws {
        let userID = UUID()
        let logged = try XCTUnwrap(CustomQuickWorkoutRecord.make(
            configuration: setup,
            recordedAt: Date(timeIntervalSince1970: 1_800_000_000),
            durationSeconds: 1_800,
            distanceKilometers: nil,
            perceivedEffort: nil,
            notes: nil,
            evidence: .manual
        ))
        CustomQuickWorkoutJournal.save(logged, userID: userID)
        CustomQuickWorkoutJournal.save(logged, userID: userID)
        let entries = CustomQuickWorkoutJournal.load(userID: userID)
        XCTAssertEqual(entries.filter { $0.id == logged.id }.count, 1)
        XCTAssertEqual(entries.first?.evidence, .manual)
        XCTAssertNil(entries.first?.manualDistanceKilometers)
        XCTAssertTrue(entries.first?.manuallyEnteredMetricsAreUnverified == true)
    }

    func testInvalidManualMetricsNeverSave() {
        for seconds in [0.0, -10.0, 90_000.0] {
            XCTAssertNil(CustomQuickWorkoutRecord.make(
                configuration: setup, recordedAt: .now,
                durationSeconds: seconds, distanceKilometers: nil,
                perceivedEffort: nil, notes: nil, evidence: .manual
            ))
        }
        for distance in [-1.0, 0.0, 1001.0, .infinity, .nan] {
            XCTAssertNil(CustomQuickWorkoutRecord.make(
                configuration: setup, recordedAt: .now,
                durationSeconds: 120, distanceKilometers: distance,
                perceivedEffort: 5, notes: nil, evidence: .manual
            ))
        }
    }
}
