import SwiftUI
import XCTest
@testable import ATHLTH

final class ATHLTHStudioFullscreenEditingTests: XCTestCase {
    func testExistingIPhoneFlowKeepsSheetByDefault() {
        XCTAssertFalse(EnvironmentValues().athlthStudioFullscreenEditing)
    }

    func testIPadStudioCanOptIntoSharedFullScreenEditor() {
        var values = EnvironmentValues()
        values.athlthStudioFullscreenEditing = true
        XCTAssertTrue(values.athlthStudioFullscreenEditing)

        values.athlthStudioFullscreenEditing = false
        XCTAssertFalse(values.athlthStudioFullscreenEditing)
    }
}
