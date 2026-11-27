import XCTest
@testable import ATHLTH

final class ATHLTHPhonePulseFreshnessTests: XCTestCase {
    func testOnlyCurrentWorkoutFreshPositiveSamples() {
        let now = Date(timeIntervalSince1970: 1000)
        let start = now.addingTimeInterval(-60)
        XCTAssertEqual(ATHLTHPhonePulseFreshness.value(145, sampledAt: now.addingTimeInterval(-5), startedAt: start, now: now), 145)
        XCTAssertNil(ATHLTHPhonePulseFreshness.value(145, sampledAt: now.addingTimeInterval(-16), startedAt: start, now: now))
        XCTAssertNil(ATHLTHPhonePulseFreshness.value(145, sampledAt: now.addingTimeInterval(3), startedAt: start, now: now))
        XCTAssertNil(ATHLTHPhonePulseFreshness.value(145, sampledAt: now.addingTimeInterval(-5), startedAt: now, now: now))
        XCTAssertNil(ATHLTHPhonePulseFreshness.value(.nan, sampledAt: now, startedAt: start, now: now))
        XCTAssertNil(ATHLTHPhonePulseFreshness.value(0, sampledAt: now, startedAt: start, now: now))
    }
}
