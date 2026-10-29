import Foundation
import XCTest
@testable import ATHLTH

@MainActor
final class ATHLTHLibraryDisplayModeTests: XCTestCase {
    func testDefaultIsListUntilUserChoosesGrid() {
        let userID = UUID()
        XCTAssertEqual(ATHLTHLibraryDisplayMode.load(userID: userID), .list)
    }

    func testLastSelectedModeSurvivesViewRecreation() {
        let userID = UUID()
        ATHLTHLibraryDisplayMode.grid.save(userID: userID)
        XCTAssertEqual(ATHLTHLibraryDisplayMode.load(userID: userID), .grid)

        ATHLTHLibraryDisplayMode.list.save(userID: userID)
        XCTAssertEqual(ATHLTHLibraryDisplayMode.load(userID: userID), .list)
    }

    func testDisplayModeIsAccountScoped() {
        let first = UUID()
        let second = UUID()
        ATHLTHLibraryDisplayMode.grid.save(userID: first)
        XCTAssertEqual(ATHLTHLibraryDisplayMode.load(userID: first), .grid)
        XCTAssertEqual(ATHLTHLibraryDisplayMode.load(userID: second), .list)
    }

    func testIconsAndCasesCoverBothLayouts() {
        XCTAssertEqual(ATHLTHLibraryDisplayMode.allCases, [.list, .grid])
        XCTAssertEqual(ATHLTHLibraryDisplayMode.list.symbol, "list.bullet")
        XCTAssertEqual(ATHLTHLibraryDisplayMode.grid.symbol, "square.grid.2x2")
    }
}
