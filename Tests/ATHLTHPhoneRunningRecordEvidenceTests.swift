import XCTest
@testable import ATHLTH

final class ATHLTHPhoneRunningRecordEvidenceTests: XCTestCase {
    private func run(start: Date, seconds: Double, meters: Double) -> PhoneWorkout {
        PhoneWorkout(
            walking: false,
            start: start,
            end: start.addingTimeInterval(seconds),
            lastCheckpoint: start.addingTimeInterval(seconds),
            distanceMeters: meters
        )
    }

    func testFirstRunDoesNotClaimPersonalRecord() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let first = run(start: now, seconds: 1500, meters: 5000)
        XCTAssertNil(ATHLTHPhoneRunningRecordEvidence.announcement(
            current: first, history: []
        ))
    }

    func testVerifiedLongerFasterRunHasQualifyingRecordLanguage() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let previous = run(start: now, seconds: 1900, meters: 4800)
        let current = run(start: now.addingTimeInterval(86_400), seconds: 1620, meters: 5200)
        let spoken = ATHLTHPhoneRunningRecordEvidence.announcement(
            current: current, history: [previous]
        )
        XCTAssertTrue(spoken?.norwegian.contains("lengste registrerte løpetur") == true)
        XCTAssertTrue(spoken?.english.contains("fastest average pace") == true)
        XCTAssertTrue(spoken?.norwegian.contains("iPhone") == true)
    }

    func testSlowerShorterRunHasNoFalseRecord() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let previous = run(start: now, seconds: 1500, meters: 5000)
        let slower = run(start: now.addingTimeInterval(86_400), seconds: 1800, meters: 4800)
        XCTAssertNil(ATHLTHPhoneRunningRecordEvidence.announcement(
            current: slower, history: [previous]
        ))
    }

    func testVerifiedRouteBestRequiresValidCourseEvidence() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let routeID = UUID()
        var previous = run(start: now, seconds: 1900, meters: 5000)
        previous.plannedComparisonRouteID = routeID
        previous.finalLeaderboardEligible = true
        var current = run(start: now.addingTimeInterval(86_400), seconds: 1800, meters: 5000)
        current.plannedComparisonRouteID = routeID
        current.finalLeaderboardEligible = true
        XCTAssertTrue(ATHLTHPhoneRunningRecordEvidence.announcement(
            current: current, history: [previous]
        )?.norwegian.contains("bestetid") == true)
        current.finalLeaderboardEligible = false
        XCTAssertFalse(ATHLTHPhoneRunningRecordEvidence.announcement(
            current: current, history: [previous]
        )?.norwegian.contains("bestetid") == true)
    }
}
