import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHPlanCreationDraftTests: XCTestCase {
    func testSimplePlanRestoresChosenDatesAndLengthWithoutAnEightWeekReset() throws {
        let start = Date(timeIntervalSince1970: 1_900_000_000)
        let original = ATHLTHPlanCreationDraft(
            title: "My walking plan", weekCount: 3, startDate: start,
            advanced: false, source: "scratch", stage: "basics",
            preferredDayIndexes: [2, 5], simpleMinutes: 15,
            simpleActivityKinds: ["walking"])
        let restored = try JSONDecoder().decode(ATHLTHPlanCreationDraft.self,
                                               from: JSONEncoder().encode(original))
        XCTAssertEqual(restored.weekCount, 3)
        XCTAssertEqual(restored.startDate, start)
        XCTAssertEqual(restored.simpleMinutes, 15)
        XCTAssertEqual(restored.preferredDayIndexes, [2, 5])
        XCTAssertEqual(restored.simpleActivityKinds, ["walking"])
    }

    func testSelectedGoalSurvivesCheckpointWithoutSavingPersonalNotes() throws {
        let draft = ATHLTHPlanCreationDraft(
            title: "My running plan",
            weekCount: 6,
            startDate: Date(),
            advanced: false,
            source: "scratch",
            stage: "goal",
            entryGoalArea: "running",
            entryGoalChoice: "speed",
            entryPlanFocus: TrainingPlanFocus.running.rawValue,
            entryPlanGoal: TrainingPlanGoalType.runFaster.rawValue
        )
        let data = try JSONEncoder().encode(draft)
        let restored = try JSONDecoder().decode(ATHLTHPlanCreationDraft.self, from: data)
        XCTAssertEqual(restored.entryGoalArea, "running")
        XCTAssertEqual(restored.entryGoalChoice, "speed")
        XCTAssertEqual(restored.entryPlanFocus, "running")
        XCTAssertEqual(restored.entryPlanGoal, "runFaster")
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("goalDetail"))

        let invalid = ATHLTHPlanCreationDraft(
            title: "Invalid goal", weekCount: 4, startDate: Date(),
            advanced: true, source: "scratch", stage: "goal",
            entryGoalArea: "running", entryGoalChoice: "invented_choice",
            entryPlanFocus: "unknown_focus", entryPlanGoal: "unknown_goal"
        )
        XCTAssertNil(invalid.entryGoalChoice)
        XCTAssertNil(invalid.entryPlanFocus)
        XCTAssertNil(invalid.entryPlanGoal)
    }

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

    func testActiveEditorMarkerIsPerAccountAndClearResetsIt() {
        let (settings, suite) = defaults()
        defer { settings.removePersistentDomain(forName: suite) }
        let location = FileManager.default.temporaryDirectory
            .appendingPathComponent("ATHLTHEditingFlag.\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: location) }
        let store = ATHLTHPlanCreationDraftStore(defaults: settings, directoryURL: location)
        let user = UUID()
        let another = UUID()
        XCTAssertFalse(store.wasEditing(userID: user))
        store.setEditing(true, userID: user)
        XCTAssertTrue(store.wasEditing(userID: user))
        XCTAssertFalse(store.wasEditing(userID: another))
        store.clear(userID: user)
        XCTAssertFalse(store.wasEditing(userID: user))
    }

    func testDeleteDraftRemovesCheckpointAndResumeFlagWithoutTouchingOtherAccount() throws {
        let (settings, suite) = defaults()
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ATHLTHPlanDraftDelete.\(UUID().uuidString)",
                                    isDirectory: true)
        defer {
            settings.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: folder)
        }

        let owner = UUID()
        let another = UUID()
        let store = ATHLTHPlanCreationDraftStore(
            defaults: settings, directoryURL: folder
        )
        store.save(draft(name: "Delete this one"), userID: owner)
        store.save(draft(name: "Keep this one"), userID: another)
        store.setEditing(true, userID: owner)
        XCTAssertNotNil(store.load(userID: owner))

        XCTAssertTrue(store.deleteDraft(userID: owner))
        XCTAssertNil(store.load(userID: owner))
        XCTAssertFalse(store.wasEditing(userID: owner))
        XCTAssertEqual(store.load(userID: another)?.title, "Keep this one")

        let freshInstance = ATHLTHPlanCreationDraftStore(
            defaults: settings, directoryURL: folder
        )
        XCTAssertNil(freshInstance.load(userID: owner),
                     "Deleted draft must not reappear when Plan is opened again")
        XCTAssertTrue(freshInstance.deleteDraft(userID: owner),
                      "Deleting an already missing draft is safe")
    }

    func testDeleteDraftClearsLegacyCheckpointWithoutTouchingStoredPlans() throws {
        let (settings, suite) = defaults()
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ATHLTHLegacyDraftDelete.\(UUID().uuidString)",
                                    isDirectory: true)
        defer {
            settings.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: folder)
        }
        let user = UUID()
        let legacyKey = "athlth.planWizardDraft.v1.\(user.uuidString)"
        settings.set(try JSONEncoder().encode(draft(name: "Old checkpoint")),
                     forKey: legacyKey)
        let store = ATHLTHPlanCreationDraftStore(
            defaults: settings, directoryURL: folder
        )

        XCTAssertTrue(store.deleteDraft(userID: user))
        XCTAssertNil(settings.data(forKey: legacyKey))
        XCTAssertNil(store.load(userID: user))
    }

    func testAtomicDraftSurvivesFreshStoreInstance() throws {
        let (settings, suite) = defaults()
        let location = FileManager.default.temporaryDirectory
            .appendingPathComponent("ATHLTHDraftStore.\(UUID().uuidString)", isDirectory: true)
        defer {
            settings.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: location)
        }
        let user = UUID()
        let first = ATHLTHPlanCreationDraftStore(defaults: settings, directoryURL: location)
        first.save(draft(), userID: user)

        let fresh = ATHLTHPlanCreationDraftStore(defaults: settings, directoryURL: location)
        let restored = try XCTUnwrap(fresh.load(userID: user))
        XCTAssertEqual(restored.title, "Eight week running")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: location.path).count, 1)

        fresh.clear(userID: user)
        XCTAssertNil(first.load(userID: user))
    }

    func testExistingUserDefaultsDraftMigratesToFile() throws {
        let (settings, suite) = defaults()
        let location = FileManager.default.temporaryDirectory
            .appendingPathComponent("ATHLTHLegacyDraft.\(UUID().uuidString)", isDirectory: true)
        defer {
            settings.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: location)
        }
        let user = UUID()
        let original = draft(name: "Migrated plan")
        let key = "athlth.planWizardDraft.v1.\(user.uuidString)"
        settings.set(try JSONEncoder().encode(original), forKey: key)

        let store = ATHLTHPlanCreationDraftStore(defaults: settings, directoryURL: location)
        XCTAssertEqual(store.load(userID: user)?.title, "Migrated plan")
        XCTAssertNil(settings.data(forKey: key), "Legacy UserDefaults entry is cleared after migration")
        XCTAssertEqual(store.load(userID: user)?.stage, "profile")
    }

    func testDraftRemembersWeekEditorAndSimpleChoices() throws {
        let advanced = ATHLTHPlanCreationDraft(
            title: "4-week plan", weekCount: 4, startDate: Date(),
            advanced: true, source: "scratch", stage: "week",
            selectedPlanWeekIndex: 2, editorDay: 4, editorKind: "studio"
        )
        let resumed = try JSONDecoder().decode(
            ATHLTHPlanCreationDraft.self, from: JSONEncoder().encode(advanced)
        )
        XCTAssertEqual(resumed.selectedPlanWeekIndex, 2)
        XCTAssertEqual(resumed.editorDay, 4)
        XCTAssertEqual(resumed.editorKind, "studio")

        let basic = ATHLTHPlanCreationDraft(
            title: "Walk and run", weekCount: 8, startDate: Date(),
            advanced: false, source: "scratch", stage: "basics",
            simpleMinutes: 25, simpleActivityKinds: ["running", "walking"]
        )
        XCTAssertEqual(basic.simpleMinutes, 25)
        XCTAssertEqual(basic.simpleActivityKinds, ["running", "walking"])
        XCTAssertNil(basic.editorDay)
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

    func testSwitchingToSimpleRetainsSanitizedAdvancedWorkoutsForSwitchingBack() throws {
        // A mode change is not a fresh draft. Structured advanced training
        // must survive even when the last visible page is the Simple wizard.
        let exercise = WorkoutTemplateBlock(
            sequence: 1, kind: .exercise, title: "Squat",
            exerciseSlug: "repdb-squat", distanceMeters: nil,
            repetitions: 10, durationSeconds: nil,
            targetWeightKilograms: nil,
            loadNote: "Private note", notes: "Private workout note"
        )
        let blueprint = ATHLTHPlanStructuredWorkoutBlueprint(
            title: "Legs", kind: .strength,
            durationMinutes: 30, routeID: UUID(), blocks: [exercise]
        )
        let draft = ATHLTHPlanCreationDraft(
            title: "Hybrid training", weekCount: 8,
            startDate: Date(), advanced: false,
            source: "scratch", stage: "mode",
            preferredDayIndexes: [1, 3, 5],
            varyWeekdays: true,
            equipmentContext: "both",
            weeklyTimeBudgetMinutes: 360,
            workoutKindsByDay: [1: "strength", 3: "running"],
            workoutPresetsByDay: [3: "Bakkeintervaller"],
            workoutMinutesByDay: [3: 45],
            structuredWorkoutsByDay: [1: blueprint],
            planningApproach: "quick",
            selectedPlanWeekIndex: 2,
            simpleMinutes: 25,
            simpleActivityKinds: ["walking", "running"]
        )
        let bytes = try JSONEncoder().encode(draft)
        let resumed = try JSONDecoder().decode(
            ATHLTHPlanCreationDraft.self, from: bytes
        )
        XCTAssertFalse(resumed.advanced)
        XCTAssertEqual(resumed.preferredDayIndexes, [1, 3, 5])
        XCTAssertEqual(resumed.weekCount, 8)
        XCTAssertEqual(resumed.varyWeekdays, true)
        XCTAssertEqual(resumed.equipmentContext, "both")
        XCTAssertEqual(resumed.weeklyTimeBudgetMinutes, 360)
        XCTAssertEqual(resumed.workoutKindsByDay?[3], "running")
        XCTAssertEqual(resumed.workoutPresetsByDay?[3], "Bakkeintervaller")
        XCTAssertEqual(resumed.workoutMinutesByDay?[3], 45)
        XCTAssertEqual(resumed.planningApproach, "quick")
        XCTAssertEqual(resumed.selectedPlanWeekIndex, 2)
        XCTAssertEqual(resumed.simpleMinutes, 25)
        XCTAssertEqual(resumed.simpleActivityKinds, ["walking", "running"])
        let detail = try XCTUnwrap(resumed.structuredWorkoutsByDay?[1])
        XCTAssertEqual(detail.title, "Legs")
        XCTAssertNil(detail.routeID)
        XCTAssertNil(detail.blocks.first?.notes)
        XCTAssertNil(detail.blocks.first?.loadNote)
        let stored = String(decoding: bytes, as: UTF8.self)
        XCTAssertFalse(stored.contains("Private workout note"))
        XCTAssertFalse(stored.contains("Private note"))
    }

    func testFreshDefaultInputsAreIndependentOfPreviousDraft() {
        let previous = ATHLTHPlanCreationDraft(
            title: "Previous", weekCount: 12, startDate: Date(),
            advanced: true, source: "scratch", stage: "week",
            preferredDayIndexes: [2, 4, 6],
            workoutKindsByDay: [2: "running"]
        )
        let fresh = ATHLTHPlanCreationDraft(
            title: "New plan", weekCount: 4, startDate: Date(),
            advanced: false, source: "scratch", stage: "mode",
            preferredDayIndexes: [1, 3, 5]
        )
        XCTAssertEqual(previous.preferredDayIndexes, [2, 4, 6])
        XCTAssertEqual(fresh.preferredDayIndexes, [1, 3, 5])
        XCTAssertNil(fresh.workoutKindsByDay)
        XCTAssertEqual(fresh.weekCount, 4)
    }

    func testNewPlanDraftDoesNotOverwriteExistingDraft() throws {
        let (settings, suite) = defaults()
        let location = FileManager.default.temporaryDirectory
            .appendingPathComponent("ATHLTHParallelDrafts.\(UUID().uuidString)", isDirectory: true)
        defer {
            settings.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: location)
        }
        let store = ATHLTHPlanCreationDraftStore(
            defaults: settings, directoryURL: location
        )
        let user = UUID()
        let first = draft(name: "Existing running program")
        let secondID = UUID()
        let thirdID = UUID()
        store.save(first, userID: user)
        store.save(draft(name: "New strength program"), userID: user, draftID: secondID)
        store.save(draft(name: "Another plan"), userID: user, draftID: thirdID)

        let reopened = ATHLTHPlanCreationDraftStore(
            defaults: settings, directoryURL: location
        )
        XCTAssertEqual(reopened.load(userID: user)?.title, first.title)
        XCTAssertEqual(reopened.load(userID: user, draftID: secondID)?.title,
                       "New strength program")
        XCTAssertEqual(reopened.load(userID: user, draftID: thirdID)?.title,
                       "Another plan")
        XCTAssertEqual(reopened.records(userID: user).count, 3)

        reopened.clear(userID: user, draftID: secondID)
        XCTAssertEqual(reopened.load(userID: user)?.title, first.title)
        XCTAssertNil(reopened.load(userID: user, draftID: secondID))
        XCTAssertNotNil(reopened.load(userID: user, draftID: thirdID))
    }

    func testNewPlanInvalidCheckpointNeverDeletesOlderDraft() {
        let (settings, suite) = defaults()
        let location = FileManager.default.temporaryDirectory
            .appendingPathComponent("ATHLTHInvalidNewDraft.\(UUID().uuidString)", isDirectory: true)
        defer {
            settings.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: location)
        }
        let store = ATHLTHPlanCreationDraftStore(
            defaults: settings, directoryURL: location
        )
        let user = UUID()
        let newID = UUID()
        store.save(draft(name: "Keep this"), userID: user)
        store.save(draft(name: "New plan"), userID: user, draftID: newID)
        store.save(draft(name: "   "), userID: user, draftID: newID)

        XCTAssertNil(store.load(userID: user, draftID: newID))
        XCTAssertEqual(store.load(userID: user)?.title, "Keep this")
    }

    func testScopedEditingFlagsDoNotTriggerOtherDrafts() {
        let (settings, suite) = defaults()
        defer { settings.removePersistentDomain(forName: suite) }
        let store = ATHLTHPlanCreationDraftStore(defaults: settings)
        let user = UUID()
        let newID = UUID()
        store.setEditing(true, userID: user, draftID: newID)
        XCTAssertTrue(store.wasEditing(userID: user, draftID: newID))
        XCTAssertFalse(store.wasEditing(userID: user))
        store.setEditing(false, userID: user, draftID: newID)
        XCTAssertFalse(store.wasEditing(userID: user, draftID: newID))
    }

}
