import Foundation
import CoreGraphics
import XCTest
@testable import ATHLTH

final class ATHLTHRecentActivityLayoutTests: XCTestCase {
    func testFullHistoryHasOneMediaHeight() {
        XCTAssertEqual(ATHLTHRecentActivityLayoutPolicy.historyArtworkHeight, 190)
    }

    func testIPhoneCardsUseFullWidthMediaAboveText() {
        for width: CGFloat in [280, 320, 375, 393, 440, 600] {
            XCTAssertFalse(
                ATHLTHRecentActivityLayoutPolicy.isHorizontal(
                    availableWidth: width
                )
            )
            XCTAssertEqual(
                ATHLTHRecentActivityLayoutPolicy.artworkWidth(
                    for: width, horizontal: false
                ),
                width,
                accuracy: 0.01
            )
            XCTAssertEqual(
                ATHLTHRecentActivityLayoutPolicy.artworkHeight(
                    horizontal: false
                ),
                132
            )
        }
    }

    func testWideIPadWindowsUseSideBySideLayout() {
        for width: CGFloat in [650, 768, 820, 1024] {
            XCTAssertTrue(
                ATHLTHRecentActivityLayoutPolicy.isHorizontal(
                    availableWidth: width
                )
            )
            XCTAssertEqual(
                ATHLTHRecentActivityLayoutPolicy.artworkWidth(
                    for: width, horizontal: true
                ),
                width * 0.39,
                accuracy: 0.01
            )
            XCTAssertGreaterThan(
                width - ATHLTHRecentActivityLayoutPolicy.artworkWidth(
                    for: width, horizontal: true
                ),
                width * 0.5
            )
        }
    }

    func testWideIPadArtworkIsCompactWithoutRemovingItsSideBySideLayout() {
        XCTAssertEqual(
            ATHLTHRecentActivityLayoutPolicy.artworkHeight(horizontal: true),
            158
        )
        XCTAssertLessThan(
            ATHLTHRecentActivityLayoutPolicy.artworkHeight(horizontal: false),
            ATHLTHRecentActivityLayoutPolicy.artworkHeight(horizontal: true)
        )
    }

    func testStageManagerNarrowWindowAndAccessibilityKeepVerticalLayout() {
        XCTAssertFalse(
            ATHLTHRecentActivityLayoutPolicy.isHorizontal(
                availableWidth: 580
            )
        )
        XCTAssertFalse(
            ATHLTHRecentActivityLayoutPolicy.isHorizontal(
                availableWidth: 820, accessibilityText: true
            )
        )
    }

    func testFollowingPreviewKeepsNewestPerSharedSessionAndSkipsOwnSessions() {
        let own = UUID()
        let shared = UUID()
        let candidates = [
            HomeRecentFollowingCandidate(index: 0, date: Date(timeIntervalSince1970: 10), sessionID: shared),
            HomeRecentFollowingCandidate(index: 1, date: Date(timeIntervalSince1970: 50), sessionID: own),
            HomeRecentFollowingCandidate(index: 2, date: Date(timeIntervalSince1970: 40), sessionID: shared),
            HomeRecentFollowingCandidate(index: 3, date: Date(timeIntervalSince1970: 30), sessionID: nil),
            HomeRecentFollowingCandidate(index: 4, date: Date(timeIntervalSince1970: 20), sessionID: nil)
        ]
        XCTAssertEqual(HomeRecentFollowingSelection.indices(candidates, excluding: [own], limit: 2), [2, 3])
        XCTAssertEqual(HomeRecentFollowingSelection.indices(candidates, excluding: [own], limit: 6), [2, 3, 4])
        XCTAssertEqual(HomeRecentFollowingSelection.indices(candidates, excluding: [own], limit: 0), [])
    }

    func testFollowingPreviewPreservesFeedOrderForEqualDatesAndBoundsLargeFeeds() {
        let date = Date(timeIntervalSince1970: 100)
        let candidates = (0..<1000).map {
            HomeRecentFollowingCandidate(index: $0, date: date, sessionID: nil)
        }
        XCTAssertEqual(HomeRecentFollowingSelection.indices(candidates, excluding: [], limit: 6), Array(0..<6))
        XCTAssertEqual(HomeRecentFollowingSelection.indices([], excluding: [], limit: 6), [])
    }

    func testFiveFriendsFitAcrossAvailableStripWidth() {
        for width: CGFloat in [260, 292, 320, 375, 440, 820, 1200] {
            let tile = ATHLTHFriendsStripLayout.tileWidth(for: width)
            XCTAssertEqual(tile * 5 + ATHLTHFriendsStripLayout.spacing * 4, width, accuracy: 0.01)
            XCTAssertLessThanOrEqual(ATHLTHFriendsStripLayout.avatarSize(for: tile) + 10, tile)
        }
    }
}
