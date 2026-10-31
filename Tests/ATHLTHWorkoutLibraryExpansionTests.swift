import XCTest
@testable import ATHLTH

final class ATHLTHWorkoutLibraryExpansionTests: XCTestCase {
    func testOpeningAndClosingSameCard() {
        let opened = ATHLTHWorkoutLibraryExpansion.toggled(
            current: nil, selecting: "saved-one"
        )
        XCTAssertEqual(opened, "saved-one")
        XCTAssertNil(ATHLTHWorkoutLibraryExpansion.toggled(
            current: opened, selecting: "saved-one"
        ))
    }

    func testOpeningAnotherCardClosesPrevious() {
        let next = ATHLTHWorkoutLibraryExpansion.toggled(
            current: "catalog-one", selecting: "running-two"
        )
        XCTAssertEqual(next, "running-two")
    }
}
