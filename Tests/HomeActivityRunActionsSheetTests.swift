import XCTest
@testable import ATHLTH

final class HomeActivityRunActionsSheetTests: XCTestCase {
    func testRunShowsSingleSetOfActionsIncludingRemoval() {
        XCTAssertEqual(
            HomeActivityRunAction.available(
                isIndoor: false, hasRecordedGPS: true,
                hasSavedRoute: false, canRemoveFromATHLTH: true
            ),
            [.share, .openMap, .savePrivateRoute, .removeFromATHLTH]
        )
    }

    func testExistingRouteCanBeOpenedButNotSavedAgain() {
        XCTAssertEqual(
            HomeActivityRunAction.available(
                isIndoor: false, hasRecordedGPS: true,
                hasSavedRoute: true, canRemoveFromATHLTH: true
            ),
            [.share, .openMap, .openSavedRoute, .removeFromATHLTH]
        )
    }

    func testIndoorRunDoesNotDisplayOutdoorActions() {
        XCTAssertEqual(
            HomeActivityRunAction.available(
                isIndoor: true, hasRecordedGPS: false,
                hasSavedRoute: false, canRemoveFromATHLTH: false
            ),
            [.share]
        )
    }

    func testOtherDestinationsCannotRemoveWorkout() {
        XCTAssertFalse(
            HomeActivityRunAction.available(
                isIndoor: false, hasRecordedGPS: true,
                hasSavedRoute: false, canRemoveFromATHLTH: false
            ).contains(.removeFromATHLTH)
        )
    }
}
