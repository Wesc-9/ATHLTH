import Foundation
import XCTest
@testable import ATHLTH

@MainActor
final class ATHLTHAccountPlanDocumentsTests: XCTestCase {
    private func plan(owner: UUID) -> TrainingPlan {
        let today = Calendar.current.startOfDay(for: Date())
        return TrainingPlan(id: UUID(), ownerID: owner, title: "My plan", summary: "",
            visibility: .privateOnly, version: 1,
            weeks: [TrainingPlanWeek(id: UUID(), weekNumber: 1, title: "Week 1",
                days: (1...7).map { TrainingPlanDay(id: UUID(), dayIndex: $0, title: "", sessions: []) })],
            tags: [], createdAt: today, updatedAt: today, startDate: today)
    }

    func testNewPlanSavesReusableCopyUnlessOptedOut() throws {
        let suite = "AccountPlanDocuments.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = AppSessionStore(defaults: defaults)
        let source = plan(owner: session.profile.userID)
        XCTAssertTrue(session.addTrainingPlan(source))
        XCTAssertEqual(session.planTemplates.count, 1)
        session.savePlanToLibrary(source)
        XCTAssertEqual(session.planTemplates.count, 1)
        XCTAssertNil(session.planTemplates.first?.startDate)
        XCTAssertTrue(session.deactivateTrainingPlan(source.id))
        XCTAssertTrue(session.addTrainingPlan(plan(owner: session.profile.userID), saveToLibrary: false))
        XCTAssertEqual(session.planTemplates.count, 1)
    }

    func testLibraryDocumentImportsWithoutBecomingActiveOrDuplicating() throws {
        let suite = "AccountPlanDocuments.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = AppSessionStore(defaults: defaults)
        var document = plan(owner: session.profile.userID)
        document.tags = ["sync:template"]
        document.startDate = nil
        XCTAssertTrue(session.importAccountPlanDocument(document))
        XCTAssertTrue(session.importAccountPlanDocument(document))
        XCTAssertNil(session.activePlan)
        XCTAssertTrue(session.trainingPlans.isEmpty)
        XCTAssertEqual(session.planTemplates.count, 1)
        XCTAssertFalse(session.planTemplates[0].tags.contains("sync:template"))
        XCTAssertEqual(session.accountPlanDocument(withID: document.id), document)
    }

    func testDisabledRemotePlanCannotReplaceAnActivePlan() throws {
        let suite = "AccountPlanDocuments.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = AppSessionStore(defaults: defaults)
        let active = plan(owner: session.profile.userID)
        XCTAssertTrue(session.addTrainingPlan(active, saveToLibrary: false))
        var remote = plan(owner: session.profile.userID)
        remote.tags = ["sync:inactive"]
        XCTAssertTrue(session.importAccountPlanDocument(remote))
        XCTAssertEqual(session.activePlan?.id, active.id)
        XCTAssertTrue(session.isTrainingPlanDeactivated(remote.id))
        XCTAssertEqual(session.trainingPlans.count, 2)
        XCTAssertTrue(session.planTemplates.isEmpty)
    }

    func testStandaloneWorkoutRoundTripAndDeletionNeverCreatesTrainingPlan() throws {
        let suite = "AccountPlanDocuments.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let owner = UUID()
        defaults.set(true, forKey: "session.signedIn")
        let session = AppSessionStore(defaults: defaults)
        XCTAssertTrue(session.restoreOfflineAccount(persistedAuthUserID: owner))
        let otherSuite = suite + ".second"
        let otherDefaults = try XCTUnwrap(UserDefaults(suiteName: otherSuite))
        defer { otherDefaults.removePersistentDomain(forName: otherSuite) }
        otherDefaults.set(true, forKey: "session.signedIn")
        let other = AppSessionStore(defaults: otherDefaults)
        XCTAssertTrue(other.restoreOfflineAccount(persistedAuthUserID: owner))
        let id = UUID()
        let workout = PlannedSession(id: id, title: "Strength", kind: .strength,
            scheduledStart: Date().addingTimeInterval(3600), durationMinutes: 15,
            targetDistanceKilometers: nil, targetPaceSecondsPerKilometer: nil,
            routeID: nil, exercises: [], notes: "Private note")
        session.addStandalonePlannedSession(workout)
        let document = try XCTUnwrap(session.accountSyncDocument(withID: id))
        XCTAssertEqual(document, session.accountSyncDocument(withID: id))
        XCTAssertTrue(document.tags.contains("sync:standalone"))
        XCTAssertNil(session.accountPlanDocument(withID: id))
        let clean = ATHLTHStudioPlanSyncStore.accountCopy(of: document)
        XCTAssertNil(clean.weeks.first?.days.first?.sessions.first?.notes)
        XCTAssertTrue(other.importAccountSyncDocument(clean))
        XCTAssertTrue(other.importAccountSyncDocument(clean))
        XCTAssertEqual(other.standalonePlannedSessions.filter { $0.id == id }.count, 1)
        let day = try XCTUnwrap(workout.scheduledStart)
        XCTAssertEqual(HomeTodayCalendarSchedule.workouts(
            plan: nil, standalone: other.standalonePlannedSessions, on: day,
            calendar: Calendar.current
        ).map(\.id), [id])
        XCTAssertTrue(other.trainingPlans.isEmpty)
        XCTAssertTrue(other.planTemplates.isEmpty)
        var updated = workout
        updated.scheduledStart = day.addingTimeInterval(3600)
        updated.cancelledAt = Date()
        session.updateStandalonePlannedSession(updated)
        let cancelled = try XCTUnwrap(session.accountSyncDocument(withID: id))
        XCTAssertTrue(other.importAccountSyncDocument(ATHLTHStudioPlanSyncStore.accountCopy(of: cancelled)))
        XCTAssertEqual(other.standalonePlannedSessions.first?.scheduledStart, updated.scheduledStart)
        XCTAssertEqual(other.standalonePlannedSessions.first?.cancelledAt, updated.cancelledAt)
        session.removeStandalonePlannedSession(id)
        let deleted = try XCTUnwrap(session.accountSyncDocument(withID: id))
        XCTAssertTrue(deleted.weeks.isEmpty)
        XCTAssertTrue(other.importAccountSyncDocument(deleted))
        XCTAssertFalse(other.standalonePlannedSessions.contains { $0.id == id })
        XCTAssertTrue(other.trainingPlans.isEmpty)
        other.reloadTrainingContent()
        XCTAssertEqual(other.accountSyncDocument(withID: id), deleted)
    }

    func testDifferentAccountDocumentIsRejected() throws {
        let suite = "AccountPlanDocuments.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = AppSessionStore(defaults: defaults)
        XCTAssertFalse(session.importAccountPlanDocument(plan(owner: UUID())))
        XCTAssertTrue(session.trainingPlans.isEmpty)
        XCTAssertTrue(session.planTemplates.isEmpty)
    }

    func testEditingPlanUpdatesSavedCopyWithoutDuplicatingOrRecreatingIt() throws {
        let suite = "AccountPlanDocuments.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = AppSessionStore(defaults: defaults)
        let source = plan(owner: session.profile.userID)
        XCTAssertTrue(session.addTrainingPlan(source))
        let savedID = try XCTUnwrap(session.planTemplates.first?.id)
        XCTAssertTrue(session.updateTrainingPlan(
            planID: source.id, title: "Edited plan", summary: "Updated",
            visibility: .privateOnly, tags: [],
            startDate: try XCTUnwrap(source.startDate), weekCount: 2))
        XCTAssertEqual(session.planTemplates.count, 1)
        XCTAssertEqual(session.planTemplates.first?.id, savedID)
        XCTAssertEqual(session.planTemplates.first?.title, "Edited plan")
        XCTAssertEqual(session.planTemplates.first?.weeks.count, 2)
        XCTAssertNil(session.planTemplates.first?.startDate)
        session.deletePlanTemplate(savedID)
        XCTAssertTrue(session.updateTrainingPlan(
            planID: source.id, title: "Edit after removing saved copy", summary: "",
            visibility: .privateOnly, tags: [],
            startDate: try XCTUnwrap(source.startDate), weekCount: 2))
        XCTAssertTrue(session.planTemplates.isEmpty)
    }
}


@MainActor
final class ATHLTHCoachPlanMuscleFocusTests: XCTestCase {
    func testGeneralIsDefaultAndOldIntakesDecode() throws {
        let initial = ATHLTHCoachChatPlanIntake()
        XCTAssertTrue(initial.activeMuscleFocus.isEmpty)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(initial)) as? [String: Any])
        object.removeValue(forKey: "muscleFocus")
        let old = try JSONDecoder().decode(ATHLTHCoachChatPlanIntake.self,
            from: JSONSerialization.data(withJSONObject: object))
        XCTAssertTrue(old.activeMuscleFocus.isEmpty)
    }

    func testMultipleMuscleGroupsAndRememberedChoices() throws {
        var intake = ATHLTHCoachChatPlanIntake.prefilled(from: "Lag en treningsplan for bryst og rygg")
        XCTAssertEqual(Set(intake.activeMuscleFocus), [.chest, .back])
        var preferences = ATHLTHCoachPreferences()
        preferences.remember(intake)
        let decoded = try JSONDecoder().decode(ATHLTHCoachPreferences.self,
            from: JSONEncoder().encode(preferences))
        XCTAssertEqual(decoded.planMuscleFocus, Set([.chest, .back]))
        XCTAssertEqual(Set(ATHLTHCoachChatPlanIntake.prefilled(from: "Lag en treningsplan",
            preferences: decoded).activeMuscleFocus), [.chest, .back])
        intake.goal = .running
        XCTAssertTrue(intake.activeMuscleFocus.isEmpty)
        intake.goal = .hybrid
        XCTAssertEqual(Set(intake.activeMuscleFocus), [.chest, .back])
    }

    func testFocusedPlanDoesNotInventMissingLibraryExercises() {
        var intake = ATHLTHCoachChatPlanIntake()
        intake.muscleFocus = [.back, .chest]
        XCTAssertNil(ATHLTHCoachChatPlanFactory.makeDraft(intake, library: []))
    }
}
