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
