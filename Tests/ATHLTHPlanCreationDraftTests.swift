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

    func testWeekPresetsResumeWithoutStoringCustomWorkoutNotes() throws {
        let draft = ATHLTHPlanCreationDraft(
            title: "Løpeplan",
            weekCount: 6,
            startDate: Date().addingTimeInterval(86_400),
            advanced: true,
            source: "scratch",
            stage: "week",
            preferredDayIndexes: [1, 4],
            workoutKindsByDay: [1: "strength", 4: "running", 9: "walking"],
            workoutPresetsByDay: [1: "Overkropp", 4: "Bakkeintervaller"],
            workoutMinutesByDay: [1: 45, 4: 35, 9: 100]
        )
        let restored = try JSONDecoder().decode(
            ATHLTHPlanCreationDraft.self, from: JSONEncoder().encode(draft)
        )
        XCTAssertEqual(restored.workoutKindsByDay?[1], "strength")
        XCTAssertNil(restored.workoutKindsByDay?[9])
        XCTAssertEqual(restored.workoutPresetsByDay?[4], "Bakkeintervaller")
        XCTAssertEqual(restored.workoutMinutesByDay?[4], 35)
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

    func testAdvancedWorkoutCheckpointRoundTripsWithoutHealthNotesOrRoute() throws {
        var squat = WorkoutTemplateBlock(
            sequence: 1, kind: .exercise, title: "Squat",
            exerciseSlug: "repdb-squat", distanceMeters: nil,
            repetitions: 8, durationSeconds: nil,
            targetWeightKilograms: 55, loadNote: "Private load note",
            notes: "Private exercise note", phase: .main,
            setCount: 4, restBetweenSetsSeconds: 90
        )
        squat.groupRounds = nil
        let blueprint = ATHLTHPlanStructuredWorkoutBlueprint(
            title: "Heavy legs", kind: .strength, durationMinutes: 60,
            routeID: UUID(), blocks: [squat]
        )
        let draft = ATHLTHPlanCreationDraft(
            title: "Strength cycle", weekCount: 4, startDate: Date(),
            advanced: true, source: "scratch", stage: "week",
            structuredWorkoutsByDay: [1: blueprint, 8: blueprint]
        )
        let bytes = try JSONEncoder().encode(draft)
        let text = String(decoding: bytes, as: UTF8.self)
        XCTAssertFalse(text.contains("Private load note"))
        XCTAssertFalse(text.contains("Private exercise note"))
        XCTAssertFalse(text.contains(blueprint.routeID!.uuidString))
        let saved = try JSONDecoder().decode(ATHLTHPlanCreationDraft.self, from: bytes)
        XCTAssertNil(saved.structuredWorkoutsByDay?[8])
        let restored = try XCTUnwrap(saved.structuredWorkoutsByDay?[1])
        XCTAssertNil(restored.routeID)
        XCTAssertEqual(restored.blocks.first?.setCount, 4)
        XCTAssertEqual(restored.blocks.first?.restBetweenSetsSeconds, 90)
        XCTAssertNil(restored.blocks.first?.notes)
        XCTAssertNil(restored.blocks.first?.loadNote)
    }

    func testBasicNeverPersistsAdvancedWorkoutBuilder() {
        let exercise = WorkoutTemplateBlock(
            sequence: 1, kind: .exercise, title: "Squat",
            exerciseSlug: "repdb-squat", distanceMeters: nil,
            repetitions: 10, durationSeconds: nil,
            targetWeightKilograms: nil, loadNote: nil, notes: nil
        )
        let blueprint = ATHLTHPlanStructuredWorkoutBlueprint(
            title: "Hidden details", kind: .strength,
            durationMinutes: 30, routeID: nil, blocks: [exercise]
        )
        let draft = ATHLTHPlanCreationDraft(
            title: "Basic walking", weekCount: 8,
            startDate: Date(), advanced: false,
            source: "scratch", stage: "basics",
            structuredWorkoutsByDay: [1: blueprint]
        )
        XCTAssertNil(draft.structuredWorkoutsByDay)
    }

}
