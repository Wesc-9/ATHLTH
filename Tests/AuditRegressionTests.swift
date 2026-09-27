import XCTest
@testable import ATHLTH

final class AuditRegressionTests: XCTestCase {
    func testPrivacySwitchAndProfileAudienceLimitVisibility() {
        XCTAssertEqual(PrivacyVisibilityRules.scope(enabled: false, current: "public", profile: "public"), "private")
        XCTAssertEqual(PrivacyVisibilityRules.scope(enabled: true, current: "public", profile: "friends"), "friends")
        XCTAssertEqual(PrivacyVisibilityRules.scope(enabled: true, current: "public", profile: "private"), "private")
        XCTAssertEqual(PrivacyVisibilityRules.scope(enabled: true, current: "friends", profile: "public"), "friends")
        var settings = SocialPrivacySettings.fallback(userID: UUID())
        settings.profileVisibility = "public"
        settings.sharePerformanceStats = false
        settings.shareWorkoutTotals = true
        settings.shareGoals = false
        settings.goalsVisibility = "public"
        settings.normalizeSectionVisibility()
        XCTAssertEqual(settings.goalsVisibility, "private")
        XCTAssertNotEqual(settings.performanceStatsVisibility, "private")
        XCTAssertFalse(settings.sharePerformanceStats)
    }

    @MainActor
    func testCompletePreservesDatesWeeksAndExistingSessions() {
        withDefaults { defaults in
            let owner = UUID()
            let existing = session("Keep me")
            var original = plan(owner)
            original.weeks[0].days[0].sessions = [existing]
            let store = AppSessionStore(activePlan: original, defaults: defaults)
            var generated = plan(owner)
            generated.weeks = [generated.weeks[0]]
            generated.weeks[0].days[0].sessions = [session("Must not replace")]
            generated.weeks[0].days[1].sessions = [session("Fill empty day")]
            XCTAssertTrue(store.fillEmptyDaysFromGeneratedProgram(generated, expectedPlanID: original.id, expectedVersion: original.version))
            XCTAssertEqual(store.activePlan?.weeks.count, 2)
            XCTAssertEqual(store.activePlan?.weeks[0].days[0].sessions, [existing])
            XCTAssertEqual(store.activePlan?.weeks[0].days[1].sessions.first?.title, "Fill empty day")
            XCTAssertEqual(store.activePlan?.weeks[1], original.weeks[1])
            XCTAssertEqual(store.activePlan?.startDate, original.startDate)
            XCTAssertEqual(store.activePlan?.endDate, original.endDate)
            let result = store.activePlan
            XCTAssertFalse(store.fillEmptyDaysFromGeneratedProgram(generated, expectedPlanID: original.id, expectedVersion: original.version))
            XCTAssertEqual(store.activePlan, result)
        }
    }

    @MainActor
    func testSignOutAndRelaunchKeepContentSeparatedByAccount() {
        withDefaults { defaults in
            let first = UUID(), second = UUID()
            let saved = plan(first)
            let store = AppSessionStore(defaults: defaults)
            store.applyBackendBootstrap(bootstrap(first))
            store.activePlan = saved
            store.clearAfterSignOut()
            XCTAssertNil(store.activePlan)
            store.applyBackendBootstrap(bootstrap(second))
            XCTAssertNil(store.activePlan)
            XCTAssertTrue(store.savedRoutes.isEmpty)
            store.clearAfterSignOut()
            let relaunched = AppSessionStore(defaults: defaults)
            relaunched.applyBackendBootstrap(bootstrap(first))
            XCTAssertEqual(relaunched.activePlan?.id, saved.id)
            relaunched.clearAfterAccountDeletion()
            relaunched.applyBackendBootstrap(bootstrap(first))
            XCTAssertNil(relaunched.activePlan)
        }
    }

    @MainActor
    func testLegacyPlanIsRestoredOnlyForItsOwner() throws {
        try withDefaults { defaults in
            let owner = UUID()
            let saved = plan(owner)
            defaults.set(try JSONEncoder().encode(saved), forKey: "session.activePlan")
            let store = AppSessionStore(defaults: defaults)
            store.applyBackendBootstrap(bootstrap(UUID()))
            XCTAssertNil(store.activePlan)
            store.clearAfterSignOut()
            store.applyBackendBootstrap(bootstrap(owner))
            XCTAssertEqual(store.activePlan?.id, saved.id)
            store.clearAfterAccountDeletion()
            store.applyBackendBootstrap(bootstrap(owner))
            XCTAssertNil(store.activePlan)
        }
    }

    func testCoachStorageCannotBeReadByAnotherAccount() {
        withDefaults { defaults in
            let first = UUID(), second = UUID()
            AccountLocalStorage.write(["experience": "beginner"], name: "coach", userID: first, defaults: defaults)
            XCTAssertNil(AccountLocalStorage.read([String: String].self, name: "coach", userID: second, defaults: defaults))
            XCTAssertEqual(AccountLocalStorage.read([String: String].self, name: "coach", userID: first, defaults: defaults)?["experience"], "beginner")
        }
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let name = "ATHLTHTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }

    private func session(_ title: String) -> PlannedSession {
        PlannedSession(id: UUID(), title: title, kind: .running, exercises: [])
    }

    private func plan(_ owner: UUID) -> TrainingPlan {
        let start = Calendar.current.startOfDay(for: Date())
        return TrainingPlan(id: UUID(), ownerID: owner, title: "Original", summary: "", visibility: .privateOnly, version: 1,
            weeks: (1...2).map { week in
                TrainingPlanWeek(id: UUID(), weekNumber: week, title: "Week \(week)", days: (0..<7).map {
                    TrainingPlanDay(id: UUID(), dayIndex: $0, title: "Day \($0)", sessions: [])
                })
            }, tags: [], createdAt: start, updatedAt: start, startDate: start,
            endDate: Calendar.current.date(byAdding: .day, value: 13, to: start))
    }

    private func bootstrap(_ id: UUID) -> BackendUserBootstrap {
        BackendUserBootstrap(
            profile: BackendProfile(id: id, onboardingCompleted: true, createdAt: Date(), updatedAt: Date()),
            role: BackendAccountRole(userID: id, role: "user"),
            entitlement: BackendSubscriptionEntitlement(userID: id, tier: "free", status: "inactive", source: "none", trialStartedAt: nil, trialEndsAt: nil, appStoreProductID: nil, currentPeriodEndsAt: nil))
    }
}
