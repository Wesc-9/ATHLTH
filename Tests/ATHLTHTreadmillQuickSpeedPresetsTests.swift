import XCTest
@testable import ATHLTH

final class ATHLTHTreadmillQuickSpeedPresetsTests: XCTestCase {
    func testAthleteCanChooseTwoToSixQuickSpeeds() {
        XCTAssertEqual(ATHLTHTreadmillQuickSpeedPresets.count(1), 2)
        XCTAssertEqual(ATHLTHTreadmillQuickSpeedPresets.count(4), 4)
        XCTAssertEqual(ATHLTHTreadmillQuickSpeedPresets.count(6), 6)
        XCTAssertEqual(ATHLTHTreadmillQuickSpeedPresets.count(100), 6)
    }

    func testSavedPresetSpeedsKeepAllSixValuesForFutureChanges() {
        XCTAssertEqual(
            ATHLTHTreadmillQuickSpeedPresets.parse("6.0,8.0,10.0,12.0,14.0,16.0"),
            [6, 8, 10, 12, 14, 16]
        )
    }

    func testInvalidPresetSettingsFallBackToSafeDefaults() {
        XCTAssertEqual(
            ATHLTHTreadmillQuickSpeedPresets.parse("NaN,-1,999"),
            [6, 8, 10, 12, 14, 16]
        )
    }
}
