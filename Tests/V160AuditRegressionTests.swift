import XCTest
@testable import ATHLTH

final class V160AuditRegressionTests: XCTestCase {
    @MainActor
    func testSignOutClearsSharedWidgetSnapshot() {
        let previous = ATHLTHSurfaceSharedStore.load()
        defer { ATHLTHSurfaceSharedStore.save(previous) }
        var snapshot = ATHLTHSurfaceSnapshot.empty
        snapshot.recoveryScore = 81
        snapshot.nextWorkoutTitle = "Previous account workout"
        ATHLTHSurfaceSharedStore.save(snapshot)
        let suite = "V160AuditTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        AppSessionStore(defaults: defaults).clearAfterSignOut()
        XCTAssertEqual(ATHLTHSurfaceSharedStore.load(), .empty)
    }

    func testEditsDuringUploadRequireAnotherBackup() {
        var changes = TrainingBackupChangeTracker()
        changes.markDirty()
        let uploadingRevision = changes.revision
        changes.markDirty() // An edit arrives after snapshot capture.
        changes.didUpload(revision: uploadingRevision)
        XCTAssertTrue(changes.isDirty)
        changes.didUpload(revision: changes.revision)
        XCTAssertFalse(changes.isDirty)
    }

    func testNewProfileDoesNotShareHealthInformation() {
        let settings = SocialPrivacySettings.fallback(userID: UUID())
        XCTAssertFalse(settings.sharePerformanceStats)
        XCTAssertFalse(settings.shareWorkoutTotals)
        XCTAssertFalse(settings.shareRecentActivity)
        XCTAssertFalse(settings.shareRunningPRs)
        XCTAssertFalse(settings.shareStrengthPRs)
        XCTAssertEqual(settings.performanceStatsVisibility, "private")
        XCTAssertEqual(settings.recentActivityVisibility, "private")
        XCTAssertEqual(settings.trainingFocusVisibility, "private")
    }

    func testPrivateStorageLocatorsRequireTheCorrectProjectAndBucket() {
        let project = SupabaseEnvironment.projectURL.absoluteString
        let locator = URL(string: project + "/storage/v1/object/public/workout-media/owner/photo.jpg?v=1")!
        XCTAssertEqual(ATHLTHStorageImageURL.privateWorkoutPath(locator), "owner/photo.jpg")
        XCTAssertNil(ATHLTHStorageImageURL.privateWorkoutPath(URL(string: "https://example.com/storage/v1/object/public/workout-media/photo.jpg")!))
        XCTAssertNil(ATHLTHStorageImageURL.privateWorkoutPath(URL(string: project + "/storage/v1/object/public/profile-avatars/owner/avatar.jpg")!))
    }

    func testUsernamesMatchDatabaseCharacterAndLengthRules() {
        XCTAssertTrue(UsernameGenerator.isValid("abc_123"))
        for invalid in ["ab", "bad.name", "åbc", String(repeating: "a", count: 21)] {
            XCTAssertFalse(UsernameGenerator.isValid(invalid))
        }
    }
}
