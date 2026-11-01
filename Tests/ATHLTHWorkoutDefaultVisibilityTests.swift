import Foundation
import XCTest
@testable import ATHLTH

@MainActor
final class ATHLTHWorkoutDefaultVisibilityTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        let name = "athlth.workoutVisibilityTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func testNewWorkoutVisibilityDefaultsToPublicWithoutEnablingAutoPublish() {
        let defaults = freshDefaults()
        let settings = AppSettingsStore(defaults: defaults)

        XCTAssertEqual(settings.defaultActivityVisibility, .publicProfile)
        XCTAssertFalse(settings.autoPublishCompletedWorkouts)
        XCTAssertEqual(
            defaults.string(forKey: "settings.defaultActivityVisibility"),
            ProfileVisibility.publicProfile.rawValue
        )
    }

    func testOneTimeMigrationMovesLegacyFriendsDefaultToPublic() {
        let defaults = freshDefaults()
        defaults.set(
            ProfileVisibility.friends.rawValue,
            forKey: "settings.defaultActivityVisibility"
        )

        let migrated = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(migrated.defaultActivityVisibility, .publicProfile)
        XCTAssertTrue(defaults.bool(
            forKey: "settings.workoutsPublicByDefault.v207"
        ))

        // New preferences are respected after migration, not reset on launch.
        migrated.defaultActivityVisibility = .friends
        let reloaded = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.defaultActivityVisibility, .friends)
    }

    func testExplicitPrivateChoiceIsNotMadePublic() {
        let defaults = freshDefaults()
        defaults.set(
            ProfileVisibility.privateOnly.rawValue,
            forKey: "settings.defaultActivityVisibility"
        )
        let settings = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(settings.defaultActivityVisibility, .privateOnly)
        XCTAssertFalse(settings.autoPublishCompletedWorkouts)
    }

    func testMigrationDoesNotChangeExistingProfilePrivacy() {
        let defaults = freshDefaults()
        defaults.set(
            ProfileVisibility.privateOnly.rawValue,
            forKey: "settings.profileVisibility"
        )
        let settings = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(settings.profileVisibility, .privateOnly)
        XCTAssertEqual(settings.defaultActivityVisibility, .publicProfile)
        XCTAssertFalse(settings.autoPublishCompletedWorkouts)
    }
}
