import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHPlanCreationDraftTests: XCTestCase {
    private func defaults() -> (UserDefaults, String) {
        let suite = "ATHLTHPlanCreationDraftTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    private func draft(
        name: String = "Eight week running",
        savedAt: Date = Date()
    ) -> ATHLTHPlanCreationDraft {
        ATHLTHPlanCreationDraft(
            title: name,
            weekCount: 8,
            startDate: Date().addingTimeInterval(7 * 86400),
            advanced: true,
            source: "scratch",
            stage: "profile",
            savedAt: savedAt
        )
    }

    func testSavedPlanBasicsResumeOnSameAccount() throws {
        let (settings, suite) = defaults()
        defer { settings.removePersistentDomain(forName: suite) }
        let store = ATHLTHPlanCreationDraftStore(defaults: settings)
        let user = UUID()
        store.save(draft(), userID: user)
        let restored = try XCTUnwrap(store.load(userID: user))
        XCTAssertEqual(restored.title, "Eight week running")
        XCTAssertEqual(restored.weekCount, 8)
        XCTAssertTrue(restored.advanced)
        XCTAssertEqual(restored.stage, "profile")
    }

    func testDifferentAccountsDoNotSeeEachOthersDraft() {
        let (settings, suite) = defaults()
        defer { settings.removePersistentDomain(forName: suite) }
        let store = ATHLTHPlanCreationDraftStore(defaults: settings)
        store.save(draft(), userID: UUID())
        XCTAssertNil(store.load(userID: UUID()))
    }

    func testClearingDraftDoesNotModifyOtherAccount() {
        let (settings, suite) = defaults()
        defer { settings.removePersistentDomain(forName: suite) }
        let store = ATHLTHPlanCreationDraftStore(defaults: settings)
        let first = UUID()
        let second = UUID()
        store.save(draft(name: "A"), userID: first)
        store.save(draft(name: "B"), userID: second)
        store.clear(userID: first)
        XCTAssertNil(store.load(userID: first))
        XCTAssertEqual(store.load(userID: second)?.title, "B")
    }

    func testExpiredCheckpointCannotResume() {
        let (settings, suite) = defaults()
        defer { settings.removePersistentDomain(forName: suite) }
        let store = ATHLTHPlanCreationDraftStore(defaults: settings)
        let user = UUID()
        store.save(draft(), userID: user)
        let afterExpiry = Date().addingTimeInterval(
            ATHLTHPlanCreationDraft.lifetime + 5
        )
        XCTAssertNil(store.load(userID: user, at: afterExpiry))
    }

    func testEmptyNamesAreNotPersistedAndDurationIsClamped() {
        let (settings, suite) = defaults()
        defer { settings.removePersistentDomain(forName: suite) }
        let store = ATHLTHPlanCreationDraftStore(defaults: settings)
        let user = UUID()
        store.save(draft(name: "   "), userID: user)
        XCTAssertNil(store.load(userID: user))
        let oversized = ATHLTHPlanCreationDraft(
            title: String(repeating: "x", count: 65),
            weekCount: 900,
            startDate: Date(),
            advanced: false,
            source: "saved",
            stage: "source"
        )
        store.save(oversized, userID: user)
        XCTAssertEqual(store.load(userID: user)?.weekCount, 52)
        XCTAssertEqual(store.load(userID: user)?.title.count, 40)
    }
    func testAdvancedScheduleCheckpointPreservesOnlyStructuralPreferences() throws {
        let prefs = ATHLTHPlanCreationDraft(
            title: "Hybrid plan",
            weekCount: 12,
            startDate: Date().addingTimeInterval(86400),
            advanced: true,
            source: "scratch",
            stage: "week",
            preferredDayIndexes: [5, 1, 3, 3, 12],
            equipmentContext: "both",
            weeklyTimeBudgetMinutes: 600
        )
        XCTAssertEqual(prefs.preferredDayIndexes, [1, 3, 5])
        XCTAssertEqual(prefs.equipmentContext, "both")
        XCTAssertEqual(prefs.weeklyTimeBudgetMinutes, 600)
        let encoded = try JSONEncoder().encode(prefs)
        let restored = try JSONDecoder().decode(
            ATHLTHPlanCreationDraft.self, from: encoded
        )
        XCTAssertEqual(restored, prefs)
        let persistedText = String(decoding: encoded, as: UTF8.self)
        XCTAssertFalse(persistedText.contains("injuriesOrLimitations"))
        XCTAssertFalse(persistedText.contains("goalDetail"))
        XCTAssertFalse(persistedText.contains("healthData"))
    }

    func testLegacyDraftWithoutAdvancedFieldsStillDecodes() throws {
        let oldDraft = ATHLTHPlanCreationDraft(
            title: "Previous checkpoint",
            weekCount: 6,
            startDate: Date(),
            advanced: true,
            source: "scratch",
            stage: "profile"
        )
        let json = try JSONEncoder().encode(oldDraft)
        let restored = try JSONDecoder().decode(
            ATHLTHPlanCreationDraft.self, from: json
        )
        XCTAssertNil(restored.preferredDayIndexes)
        XCTAssertNil(restored.equipmentContext)
        XCTAssertNil(restored.weeklyTimeBudgetMinutes)
    }

}
