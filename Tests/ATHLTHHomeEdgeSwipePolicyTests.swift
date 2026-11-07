import CoreGraphics
import XCTest
@testable import ATHLTH

final class ATHLTHHomeEdgeSwipePolicyTests: XCTestCase {
    func testOpensWhenStartingAtLeftEdgeAndDraggingTowardMiddle() {
        XCTAssertTrue(ATHLTHHomeEdgeSwipePolicy.shouldOpen(
            startLocation: CGPoint(x: 2, y: 350),
            translation: CGSize(width: 120, height: 6)
        ))
        XCTAssertTrue(ATHLTHHomeEdgeSwipePolicy.shouldOpen(
            startLocation: CGPoint(x: 29, y: 180),
            translation: CGSize(width: 73, height: -12)
        ))
    }

    func testDoesNotOpenWhenStartingOutsideEdge() {
        XCTAssertFalse(ATHLTHHomeEdgeSwipePolicy.shouldOpen(
            startLocation: CGPoint(x: 46, y: 220),
            translation: CGSize(width: 250, height: 0)
        ))
        XCTAssertFalse(ATHLTHHomeEdgeSwipePolicy.shouldOpen(
            startLocation: CGPoint(x: -2, y: 220),
            translation: CGSize(width: 250, height: 0)
        ))
    }

    func testDoesNotOpenForBackwardsOrShortSwipes() {
        XCTAssertFalse(ATHLTHHomeEdgeSwipePolicy.shouldOpen(
            startLocation: CGPoint(x: 10, y: 200),
            translation: CGSize(width: -130, height: 0)
        ))
        XCTAssertFalse(ATHLTHHomeEdgeSwipePolicy.shouldOpen(
            startLocation: CGPoint(x: 10, y: 200),
            translation: CGSize(width: 36, height: 0)
        ))
    }

    func testVerticalHomeScrollingDoesNotOpenDrawer() {
        XCTAssertFalse(ATHLTHHomeEdgeSwipePolicy.shouldOpen(
            startLocation: CGPoint(x: 8, y: 240),
            translation: CGSize(width: 18, height: -200)
        ))
        XCTAssertFalse(ATHLTHHomeEdgeSwipePolicy.shouldOpen(
            startLocation: CGPoint(x: 8, y: 240),
            translation: CGSize(width: 80, height: -130)
        ))
    }

    func testBorderlineDiagonalGestureMustBeClearlyHorizontal() {
        XCTAssertTrue(ATHLTHHomeEdgeSwipePolicy.shouldOpen(
            startLocation: CGPoint(x: 18, y: 240),
            translation: CGSize(width: 96, height: 50)
        ))
        XCTAssertFalse(ATHLTHHomeEdgeSwipePolicy.shouldOpen(
            startLocation: CGPoint(x: 18, y: 240),
            translation: CGSize(width: 96, height: 80)
        ))
    }
}
