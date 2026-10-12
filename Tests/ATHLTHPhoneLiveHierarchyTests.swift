import XCTest
@testable import ATHLTH

final class ATHLTHPhoneLiveHierarchyTests: XCTestCase {
    func testRunPlacesPaceBeforeElapsed() {
        let order = ATHLTHPhoneLiveHierarchyResolver.resolve(kind: .running)
        XCTAssertEqual(order.primary, .pace)
        XCTAssertEqual(order.secondary, [.distance, .elapsed])
    }

    func testWalkingPlacesDistanceBeforePace() {
        let order = ATHLTHPhoneLiveHierarchyResolver.resolve(kind: .walking)
        XCTAssertEqual(order.primary, .distance)
        XCTAssertEqual(order.secondary, [.pace, .elapsed])
    }

    func testStrengthRestDoesNotShowOldRepsAsLive() {
        let order = ATHLTHPhoneLiveHierarchyResolver.resolve(
            kind: .strength,
            strengthHasSet: true,
            strengthIsResting: true
        )
        XCTAssertEqual(order.primary, .restRemaining)
    }

    func testTimedStrengthNeverPretendsToBeReps() {
        let order = ATHLTHPhoneLiveHierarchyResolver.resolve(
            kind: .strength,
            strengthHasSet: true,
            strengthIsTimed: true
        )
        XCTAssertEqual(order.primary, .timeRemaining)
    }

    func testGenericWorkoutsDoNotClaimPace() {
        for kind: WatchWorkoutKind in [.yoga, .hiit, .functional, .other] {
            let order = ATHLTHPhoneLiveHierarchyResolver.resolve(kind: kind)
            XCTAssertEqual(order.primary, .elapsed)
        }
    }

    func testMissingOrInvalidPaceRemainsMissing() {
        XCTAssertFalse(ATHLTHPhoneLiveHierarchyResolver.paceIsAvailable(nil))
        XCTAssertFalse(ATHLTHPhoneLiveHierarchyResolver.paceIsAvailable(.nan))
        XCTAssertFalse(ATHLTHPhoneLiveHierarchyResolver.paceIsAvailable(.infinity))
        XCTAssertFalse(ATHLTHPhoneLiveHierarchyResolver.paceIsAvailable(0))
        XCTAssertTrue(ATHLTHPhoneLiveHierarchyResolver.paceIsAvailable(300))
    }
}
