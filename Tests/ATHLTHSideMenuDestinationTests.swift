import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHSideMenuDestinationTests: XCTestCase {
    func testHomeQuickActionsRemainReachableFromSideMenu() {
        XCTAssertEqual(
            [
                ATHLTHSideMenuDestination.search.rawValue,
                ATHLTHSideMenuDestination.inbox.rawValue,
                ATHLTHSideMenuDestination.notifications.rawValue
            ],
            ["search", "inbox", "notifications"]
        )
    }

    func testSideMenuLinksToDeepToolsRatherThanMainTabs() {
        let destinations: [ATHLTHSideMenuDestination] = [
            .trainingLibrary,
            .trainTogether,
            .ghostRace,
            .challenges,
            .arena,
            .clubs
        ]
        XCTAssertEqual(Set(destinations.map(\.id)).count, destinations.count)

        for duplicatedTab in [
            "calendar", "train", "plans", "insights", "explore", "community"
        ] {
            XCTAssertNil(ATHLTHSideMenuDestination(rawValue: duplicatedTab))
        }
    }

    func testExerciseProgressIsNotASideMenuDestination() {
        XCTAssertNil(ATHLTHSideMenuDestination(rawValue: "exerciseProgress"))
    }

    func testProfileAndSettingsStayAvailable() {
        XCTAssertEqual(ATHLTHSideMenuDestination.profile.rawValue, "profile")
        XCTAssertEqual(ATHLTHSideMenuDestination.settings.rawValue, "settings")
    }
}
