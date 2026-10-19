import Foundation
import XCTest
@testable import ATHLTH

final class SocialActivityReactionTests: XCTestCase {
    private func feedItem(_ kind: String) -> SocialFeedItem {
        let ownerID = UUID()
        return SocialFeedItem(
            activity: SocialActivityRecord(
                id: UUID(),
                actorID: ownerID,
                kind: "workout",
                title: kind + " workout",
                subtitle: nil,
                metadata: ["kind": kind],
                visibility: "public",
                eventKey: nil,
                workoutSessionID: nil,
                createdAt: Date()
            ),
            actor: SocialProfileCard(
                userID: ownerID,
                username: nil,
                displayName: "Athlete",
                bio: nil,
                avatarURL: nil,
                profileVisibility: "public",
                createdAt: nil,
                updatedAt: nil
            ),
            reactions: []
        )
    }

    func testLikeUnlikeAndSwitchWorksForEveryWorkoutKind() {
        let kinds = [
            "Running", "Strength", "Walking", "Cycling",
            "Treadmill", "Yoga", "HIIT", "Other"
        ]
        let reactor = UUID()
        for kind in kinds {
            let original = feedItem(kind)
            let liked = original.replacingReaction(
                from: reactor, with: .heart
            )
            XCTAssertEqual(liked.reactions.count, 1, kind)
            XCTAssertEqual(liked.reactions.first?.userID, reactor)
            XCTAssertEqual(liked.reactions.first?.reaction, .heart)
            XCTAssertEqual(liked.id, original.id)

            let switched = liked.replacingReaction(
                from: reactor, with: .fire
            )
            XCTAssertEqual(switched.reactions.count, 1, kind)
            XCTAssertEqual(switched.reactions.first?.reaction, .fire)

            let unliked = switched.replacingReaction(
                from: reactor, with: nil
            )
            XCTAssertTrue(unliked.reactions.isEmpty, kind)
        }
    }

    func testAnotherAthletesLikeRemainsWhenSwitching() {
        let first = UUID()
        let second = UUID()
        let original = feedItem("Strength")
        let both = original
            .replacingReaction(from: first, with: .heart)
            .replacingReaction(from: second, with: .heart)
        XCTAssertEqual(both.reactions.count, 2)

        let updated = both.replacingReaction(from: first, with: nil)
        XCTAssertEqual(updated.reactions.count, 1)
        XCTAssertEqual(updated.reactions.first?.userID, second)
    }
}
