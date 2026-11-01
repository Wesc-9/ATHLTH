import XCTest
@testable import ATHLTH

final class HomeSocialWorkoutIdentityTests: XCTestCase {
    private func item(
        owner: UUID,
        eventKey: String?,
        metadata: [String: String]?,
        kind: String = "workout"
    ) -> SocialFeedItem {
        let activity = SocialActivityRecord(
            id: UUID(),
            actorID: owner,
            kind: kind,
            title: "Styrke",
            subtitle: nil,
            metadata: metadata,
            visibility: "friends",
            eventKey: eventKey,
            workoutSessionID: nil,
            createdAt: Date()
        )
        let profile = SocialProfileCard(
            userID: owner,
            username: nil,
            displayName: "Athlete",
            bio: nil,
            avatarURL: nil,
            profileVisibility: "public",
            createdAt: nil,
            updatedAt: nil
        )
        return SocialFeedItem(
            activity: activity, actor: profile, reactions: []
        )
    }

    func testPublishedStrengthUsesOriginalLogIdEvenWithHealthKitID() {
        let owner = UUID(), healthID = UUID(), logID = UUID()
        let ids = HomeSocialWorkoutIdentity.allIDs(
            visibleWorkoutID: healthID,
            originalStrengthID: logID,
            originalPhoneID: nil
        )
        let post = item(owner: owner,
                        eventKey: "strength-workout-\(logID.uuidString)",
                        metadata: ["workout_id": logID.uuidString])
        XCTAssertTrue(HomeSocialWorkoutIdentity.matches(
            item: post, ownerID: owner, workoutIDs: ids
        ))
    }

    func testWatchAndPhonePublicationRemainLikable() {
        let owner = UUID(), healthID = UUID(), phoneID = UUID()
        let ids = HomeSocialWorkoutIdentity.allIDs(
            visibleWorkoutID: healthID,
            originalStrengthID: nil,
            originalPhoneID: phoneID
        )
        let post = item(
            owner: owner, eventKey: "workout-\(phoneID.uuidString)",
            metadata: nil
        )
        XCTAssertTrue(HomeSocialWorkoutIdentity.matches(
            item: post, ownerID: owner, workoutIDs: ids
        ))
    }

    func testDifferentUserAndUnrelatedPostsNeverMatch() {
        let owner = UUID(), otherOwner = UUID(), workoutID = UUID()
        let ids = HomeSocialWorkoutIdentity.allIDs(
            visibleWorkoutID: workoutID,
            originalStrengthID: nil,
            originalPhoneID: nil
        )
        let wrongOwner = item(
            owner: otherOwner,
            eventKey: "workout-\(workoutID.uuidString)",
            metadata: ["workout_id": workoutID.uuidString]
        )
        XCTAssertFalse(HomeSocialWorkoutIdentity.matches(
            item: wrongOwner, ownerID: owner, workoutIDs: ids
        ))
        let unrelated = item(
            owner: owner, eventKey: "workout-\(UUID().uuidString)",
            metadata: nil
        )
        XCTAssertFalse(HomeSocialWorkoutIdentity.matches(
            item: unrelated, ownerID: owner, workoutIDs: ids
        ))
        let nonWorkout = item(
            owner: owner, eventKey: "workout-\(workoutID.uuidString)",
            metadata: nil, kind: "challenge"
        )
        XCTAssertFalse(HomeSocialWorkoutIdentity.matches(
            item: nonWorkout, ownerID: owner, workoutIDs: ids
        ))
    }

    func testHomeFriendStripRequiresMutualFollow() {
        let friend = UUID(), followerOnly = UUID(), followingOnly = UUID()
        let result = ATHLTHHomeFriendsEligibility.mutualIDs(
            followers: [friend, followerOnly],
            following: [friend, followingOnly],
            blocked: [],
            muted: []
        )
        XCTAssertEqual(result, [friend])
    }

    func testMutedAndBlockedFriendsNeverEnterHomeStrip() {
        let visible = UUID(), blocked = UUID(), muted = UUID()
        let all = Set([visible, blocked, muted])
        let result = ATHLTHHomeFriendsEligibility.mutualIDs(
            followers: all,
            following: all,
            blocked: [blocked],
            muted: [muted]
        )
        XCTAssertEqual(result, [visible])
    }

    func testOfflineMutualFriendRemainsEligibleForHome() {
        // Online/training status is intentionally not an eligibility input.
        let friend = UUID()
        XCTAssertEqual(
            ATHLTHHomeFriendsEligibility.mutualIDs(
                followers: [friend],
                following: [friend],
                blocked: [],
                muted: []
            ),
            [friend]
        )
    }
}
