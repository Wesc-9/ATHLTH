import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHSideMenuDestinationTests: XCTestCase {
    func testPhoneUtilityRowsAreStaticAndOrdered() {
        XCTAssertEqual(ATHLTHSideMenuDestination.phoneUtilityRows.map(\.rawValue),
                       ["search", "notifications", "inbox"])
    }

    func testPhonePrimaryRowsAreStaticAndOrdered() {
        XCTAssertEqual(ATHLTHSideMenuDestination.phonePrimaryRows.map(\.rawValue),
                       ["trainNow", "trainingLibrary", "clubs", "arena"])
        let visible = ATHLTHSideMenuDestination.phoneUtilityRows + ATHLTHSideMenuDestination.phonePrimaryRows
        XCTAssertEqual(Set(visible.map(\.id)).count, 7)
        XCTAssertFalse(visible.contains(.home))
        XCTAssertFalse(visible.contains(.myExercises))
        XCTAssertFalse(visible.contains(.trainTogether))
        XCTAssertFalse(visible.contains(.challenges))
    }

    func testExerciseProgressIsNotASideMenuDestination() {
        XCTAssertNil(ATHLTHSideMenuDestination(rawValue: "exerciseProgress"))
    }

    func testProfileAndSettingsStayAvailable() {
        XCTAssertEqual(ATHLTHSideMenuDestination.profile.rawValue, "profile")
        XCTAssertEqual(ATHLTHSideMenuDestination.settings.rawValue, "settings")
    }
}
