import Foundation
import XCTest
@testable import ATHLTH

final class WorkoutFeedSafetyTests: XCTestCase {
    func testWorkoutFeedKeepsOnlyExplicitlyAllowedSummaryFields() {
        let unsafe: [String: String] = [
            "workout_id": UUID().uuidString,
            "kind": "running",
            "duration_seconds": "1800",
            "distance_meters": "5000",
            "caption": "Morning workout",
            "share_health_data": "true",
            "average_heart_rate_bpm": "153",
            "heart_rate_curve": "private_samples",
            "heart_rate_zone_seconds": "private_zones",
            "active_kcal": "350",
            "sleep_score": "72",
            "resting_heart_rate": "47",
            "medical_condition": "private",
            "unknown_extra_key": "private"
        ]

        let result = WorkoutFeedSafety.sanitizedMetadata(unsafe)

        XCTAssertEqual(result["kind"], "running")
        XCTAssertEqual(result["distance_meters"], "5000")
        XCTAssertEqual(result["caption"], "Morning workout")
        XCTAssertEqual(result["share_health_data"], "false")
        XCTAssertNil(result["average_heart_rate_bpm"])
        XCTAssertNil(result["heart_rate_curve"])
        XCTAssertNil(result["heart_rate_zone_seconds"])
        XCTAssertNil(result["active_kcal"])
        XCTAssertNil(result["sleep_score"])
        XCTAssertNil(result["resting_heart_rate"])
        XCTAssertNil(result["medical_condition"])
        XCTAssertNil(result["unknown_extra_key"])
    }

    func testEnablingPrivateProfileSectionDefaultsToFriendsNotPublic() {
        XCTAssertEqual(
            PrivacyVisibilityRules.scope(
                enabled: true, current: "private", profile: "public"
            ), "friends"
        )
        XCTAssertEqual(
            PrivacyVisibilityRules.scope(
                enabled: false, current: "public", profile: "public"
            ), "private"
        )
        XCTAssertEqual(
            PrivacyVisibilityRules.scope(
                enabled: true, current: "public", profile: "friends"
            ), "friends"
        )
    }

    func testAutomaticSharingConsentIsAccountScoped() {
        let suiteName = "WorkoutFeedSafetyTests.\\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let firstUser = UUID()
        let secondUser = UUID()

        XCTAssertFalse(
            FriendFeedSharingPreference.isEnabled(userID: firstUser, defaults: defaults)
        )
        XCTAssertFalse(
            FriendFeedSharingPreference.isEnabled(userID: secondUser, defaults: defaults)
        )

        FriendFeedSharingPreference.setEnabled(
            true, userID: firstUser, defaults: defaults
        )
        XCTAssertTrue(
            FriendFeedSharingPreference.isEnabled(userID: firstUser, defaults: defaults)
        )
        XCTAssertFalse(
            FriendFeedSharingPreference.isEnabled(userID: secondUser, defaults: defaults)
        )
        FriendFeedSharingPreference.setEnabled(
            false, userID: firstUser, defaults: defaults
        )
        XCTAssertFalse(
            FriendFeedSharingPreference.isEnabled(userID: firstUser, defaults: defaults)
        )
    }


}


final class ATHLTHProfilePublishedFeedPolicyTests: XCTestCase {
    func testOnlyOwnSharedWorkoutRecordsAreIncluded() {
        let owner = UUID()
        func row(_ actor: UUID, _ kind: String, _ visibility: String) -> SocialActivityRecord {
            .init(id: UUID(), actorID: actor, kind: kind, title: "Workout", subtitle: nil,
                metadata: nil, visibility: visibility, eventKey: nil, workoutSessionID: nil, createdAt: Date())
        }
        XCTAssertTrue(ATHLTHProfilePublishedFeedPolicy.includes(row(owner, "workout", "friends"), owner: owner))
        XCTAssertTrue(ATHLTHProfilePublishedFeedPolicy.includes(row(owner, "workout", "public"), owner: owner))
        XCTAssertFalse(ATHLTHProfilePublishedFeedPolicy.includes(row(owner, "workout", "private"), owner: owner))
        XCTAssertFalse(ATHLTHProfilePublishedFeedPolicy.includes(row(UUID(), "workout", "public"), owner: owner))
        XCTAssertFalse(ATHLTHProfilePublishedFeedPolicy.includes(row(owner, "trophy", "public"), owner: owner))
        XCTAssertFalse(ATHLTHProfilePublishedFeedPolicy.includes(row(owner, "workout", "public"), owner: nil))
    }

    func testSportsAndCustomWorkoutNameSurviveSafeSummaryFiltering() {
        let safe = WorkoutFeedSafety.sanitizedMetadata(["activity_subtype": "sports",
            "custom_workout_title": "Cageball", "average_heart_rate_bpm": "155"])
        XCTAssertEqual(safe["activity_subtype"], "sports")
        XCTAssertEqual(safe["custom_workout_title"], "Cageball")
        XCTAssertNil(safe["average_heart_rate_bpm"])
    }
}
