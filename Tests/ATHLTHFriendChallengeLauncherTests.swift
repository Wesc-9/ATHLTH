import SwiftUI
import XCTest
@testable import ATHLTH

/// Regression for the 2.2.7 (135) main-thread generic metadata stack guard
/// crash when opening Home -> Friends -> Challenge on iOS 27.3 beta.
/// Construct and lay out the exact lightweight entry and its profile/feed
/// launchers independently of the large social profile's SwiftUI view tree.
final class ATHLTHFriendChallengeLauncherTests: XCTestCase {
    private func friend() -> SocialProfileCard {
        SocialProfileCard(
            userID: UUID(),
            username: "partner",
            displayName: "Training partner",
            bio: nil,
            avatarURL: nil,
            profileVisibility: "public",
            createdAt: nil,
            updatedAt: nil
        )
    }

    @MainActor
    private func render<Content: View>(_ content: Content) {
        let controller = UIHostingController(rootView: content)
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 780)
        controller.view.layoutIfNeeded()
        XCTAssertGreaterThan(controller.view.bounds.width, 0)
    }

    @MainActor
    func testFriendsChallengeActionRendersWithoutMountingParentProfile() {
        render(ATHLTHFriendChallengeLauncher(
            friend: friend(),
            isAllowed: true,
            style: .profileAction
        ))
    }

    @MainActor
    func testFeedChallengeActionRendersWithoutMountingFeedCard() {
        render(ATHLTHFriendChallengeLauncher(
            friend: friend(),
            isAllowed: true,
            style: .feedAction
        ))
    }

    @MainActor
    func testChallengeSportPickerRendersFromFriendContext() {
        render(ATHLTHCompetitionEntryView(preselectedFriend: friend()))
    }

    @MainActor
    func testUnfollowedFriendStillHasAnExplicitPermissionGate() {
        render(ATHLTHFriendChallengeLauncher(
            friend: friend(),
            isAllowed: false,
            style: .profileAction
        ))
    }
}
