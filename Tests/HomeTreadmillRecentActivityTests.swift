import XCTest
@testable import ATHLTH

final class HomeTreadmillRecentActivityTests: XCTestCase {
    func testPhoneTreadmillPreservesEnvironmentAndRecordedMetrics() {
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let end = start.addingTimeInterval(21 * 60)
        var phone = PhoneWorkout(
            walking: false,
            start: start,
            end: end,
            lastCheckpoint: end
        )
        phone.runEnvironment = .treadmill
        phone.accumulatedSeconds = 21 * 60
        phone.distanceMeters = 2_790

        let displayed = SocialPublishableWorkout(phoneWorkout: phone)
        XCTAssertEqual(displayed.activity, .running)
        XCTAssertEqual(displayed.isIndoor, true)
        XCTAssertEqual(displayed.distanceMeters, 2_790)
        XCTAssertEqual(displayed.duration, 21 * 60)
        XCTAssertTrue(displayed.summaryText.contains("2.79 km"))
    }

    func testOutdoorPhoneRunRemainsOutdoor() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        var phone = PhoneWorkout(
            walking: false,
            start: now,
            end: now.addingTimeInterval(600),
            lastCheckpoint: now.addingTimeInterval(600)
        )
        phone.runEnvironment = .outdoor
        let displayed = SocialPublishableWorkout(phoneWorkout: phone)
        XCTAssertEqual(displayed.isIndoor, false)
    }
}
