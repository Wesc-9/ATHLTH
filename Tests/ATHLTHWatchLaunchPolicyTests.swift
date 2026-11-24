import XCTest
@testable import ATHLTH

final class ATHLTHWatchLaunchPolicyTests: XCTestCase {
    func testAutomaticUsesOnlyLiveCapableWatch() {
        XCTAssertEqual(ATHLTHWatchLaunchPolicy.resolve(preference: .automatic, apple: true, garmin: false), .appleWatch)
        XCTAssertEqual(ATHLTHWatchLaunchPolicy.resolve(preference: .automatic, apple: false, garmin: true), .garmin)
        XCTAssertNil(ATHLTHWatchLaunchPolicy.resolve(preference: .automatic, apple: true, garmin: true))
        XCTAssertNil(ATHLTHWatchLaunchPolicy.resolve(preference: .automatic, apple: false, garmin: false))
    }
    func testExplicitDefaultNeverSilentlySwitches() {
        XCTAssertEqual(ATHLTHWatchLaunchPolicy.resolve(preference: .appleWatch, apple: true, garmin: true), .appleWatch)
        XCTAssertEqual(ATHLTHWatchLaunchPolicy.resolve(preference: .garmin, apple: true, garmin: true), .garmin)
        XCTAssertNil(ATHLTHWatchLaunchPolicy.resolve(preference: .garmin, apple: true, garmin: false))
        XCTAssertNil(ATHLTHWatchLaunchPolicy.resolve(preference: .appleWatch, apple: false, garmin: true))
    }
}
