import XCTest
@testable import ATHLTH

@MainActor
final class ATHLTHOfflineLaunchTests: XCTestCase {
    private func isolatedDefaults() -> UserDefaults {
        let suite = "athlth.tests.offline.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func cachedProfile(userID: UUID) -> UserProfile {
        UserProfile(
            id: UUID(),
            userID: userID,
            username: "offline-athlete",
            displayName: "Saved Athlete",
            bio: "",
            avatarURL: nil,
            headerArtworkName: nil,
            headerImageURL: nil,
            headerDimStrength: nil,
            presence: TrainingPresence(
                state: .available,
                workoutTitle: nil,
                startedAt: nil,
                visibility: .friends
            )
        )
    }

    func testPreviouslyVerifiedSessionRestoresLocallyWithoutAnyNetwork() throws {
        let defaults = isolatedDefaults()
        let id = UUID()
        defaults.set(true, forKey: "session.signedIn")
        defaults.set(true, forKey: "session.onboardingCompleted")
        defaults.set(
            try JSONEncoder().encode(cachedProfile(userID: id)),
            forKey: "session.verifiedOfflineProfile.v1"
        )

        let session = AppSessionStore(defaults: defaults)
        XCTAssertTrue(session.signedIn)
        XCTAssertTrue(session.onboardingCompleted)
        XCTAssertEqual(session.profile.userID, id)
        XCTAssertEqual(session.profile.displayName, "Saved Athlete")
        XCTAssertTrue(session.restoreOfflineAccount(persistedAuthUserID: id))
    }

    func testKeychainUserMismatchDoesNotOpenOtherAccountsData() throws {
        let defaults = isolatedDefaults()
        let id = UUID()
        defaults.set(true, forKey: "session.signedIn")
        defaults.set(
            try JSONEncoder().encode(cachedProfile(userID: id)),
            forKey: "session.verifiedOfflineProfile.v1"
        )
        let session = AppSessionStore(defaults: defaults)
        XCTAssertFalse(session.restoreOfflineAccount(persistedAuthUserID: UUID()))
        XCTAssertFalse(session.signedIn)
        XCTAssertNil(defaults.data(forKey: "session.verifiedOfflineProfile.v1"))
    }

    func testOldInstallationUsesPersistedKeychainAccountIdentity() {
        let defaults = isolatedDefaults()
        let id = UUID()
        defaults.set(true, forKey: "session.signedIn")
        defaults.set(true, forKey: "session.onboardingCompleted")
        defaults.set("Previous Athlete", forKey: "session.usernameSeed")
        let session = AppSessionStore(defaults: defaults)
        XCTAssertTrue(session.restoreOfflineAccount(persistedAuthUserID: id))
        XCTAssertEqual(session.profile.userID, id)
        XCTAssertEqual(session.profile.displayName, "Previous Athlete")
    }

    func testFreshInstallCannotUseAnOrphanedKeychainSession() {
        let defaults = isolatedDefaults()
        let session = AppSessionStore(defaults: defaults)
        XCTAssertFalse(session.restoreOfflineAccount(persistedAuthUserID: UUID()))
        XCTAssertFalse(session.signedIn)
    }

    func testMissingIdentityNeverGrantsRandomLocalAccountAccess() {
        let defaults = isolatedDefaults()
        defaults.set(true, forKey: "session.signedIn")
        let session = AppSessionStore(defaults: defaults)
        XCTAssertFalse(session.restoreOfflineAccount(persistedAuthUserID: nil))
    }
}
