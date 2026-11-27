import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHCoachReadToolsTests: XCTestCase {
    func testStrictFiltersAndMissingMeasurements() throws {
        let query = try XCTUnwrap(ATHLTHCoachReadQuery.parse("Finn alle løpeøktene mine over 5 km med snittpuls under 150"))
        let now = Date()
        let valid = ATHLTHCoachReadRecord(id: UUID(), activity: .running, date: now, seconds: 1800, meters: 6000, pulse: 145)
        let missing = ATHLTHCoachReadRecord(id: UUID(), activity: .running, date: now, seconds: 1800, meters: 6000, pulse: nil)
        let boundary = ATHLTHCoachReadRecord(id: UUID(), activity: .running, date: now, seconds: 1800, meters: 5000, pulse: 149)
        XCTAssertEqual(ATHLTHCoachReadExecutor.matches(query, records: [valid, valid, missing, boundary], now: now), [valid])
        XCTAssertNil(ATHLTHCoachReadQuery.parse("Finn alle løpeøktene med snittpuls over 170"))
        XCTAssertNil(ATHLTHCoachReadQuery.parse("Finn alle løpeøkter under 45 minutter"))
    }

    func testReportUsesActualPeriod() throws {
        let query = try XCTUnwrap(ATHLTHCoachReadQuery.parse("Månedsrapport"))
        XCTAssertEqual(query.kind, .report)
        XCTAssertEqual(query.days, 30)
        XCTAssertEqual(ATHLTHIntelligenceRoutingPolicy.provider(for: .privateHistorySearch), .rules)
        XCTAssertEqual(ATHLTHIntelligenceRoutingPolicy.provider(for: .privateHistorySearch, localAvailable: true), .appleLocal)
        XCTAssertThrowsError(try ATHLTHIntelligenceRoutingPolicy.groqEndpoint(for: .privateHistorySearch))
    }
}
