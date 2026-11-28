import Foundation
import XCTest
@testable import ATHLTH

@MainActor
final class ATHLTHPlanLifecycleStateTests: XCTestCase {
    private func plan(_ title: String) -> TrainingPlan {
        let start = Calendar.current.startOfDay(for: Date())
        return TrainingPlan(
            id: UUID(), ownerID: UUID(), title: title, summary: "",
            visibility: .privateOnly, version: 1,
            weeks: [TrainingPlanWeek(
                id: UUID(), weekNumber: 1, title: "Week 1",
                days: (1...7).map {
                    TrainingPlanDay(id: UUID(), dayIndex: $0, title: "", sessions: [])
                }
            )], tags: [], createdAt: start, updatedAt: start,
            startDate: start
        )
    }

    func testPausedPlanCannotAutoReactivateOnRefreshOrReload() throws {
        let suite = "PlanLifecycle.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let startPlan = plan("Paused")
        let store = AppSessionStore(activePlan: startPlan, defaults: defaults)
        // This also covers in-memory state for accounts not yet signed in.
        XCTAssertTrue(store.pauseTrainingPlan(startPlan.id))
        store.refreshActivePlanForToday()
        XCTAssertNil(store.activePlan)
        XCTAssertTrue(store.isTrainingPlanPaused(startPlan.id))
        XCTAssertTrue(store.resumeTrainingPlan(startPlan.id))
        store.refreshActivePlanForToday()
        XCTAssertEqual(store.activePlan?.id, startPlan.id)
    }

    func testDeactivatedPlanStaysSavedAndIsNotAutomaticallySelected() throws {
        let suite = "PlanLifecycle.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let startPlan = plan("Deactivated")
        let store = AppSessionStore(activePlan: startPlan, defaults: defaults)
        XCTAssertTrue(store.deactivateTrainingPlan(startPlan.id))
        XCTAssertTrue(store.isTrainingPlanDeactivated(startPlan.id))
        XCTAssertNil(store.activePlan)
        XCTAssertEqual(store.trainingPlan(withID: startPlan.id)?.title, "Deactivated")
        store.refreshActivePlanForToday()
        XCTAssertNil(store.activePlan)
        XCTAssertTrue(store.resumeTrainingPlan(startPlan.id))
        XCTAssertEqual(store.activePlan?.id, startPlan.id)
    }

    func testPausedProgramCanBeReplacedButNotResumedOverAnActiveProgram() throws {
        let suite = "PlanLifecycle.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = plan("First")
        let replacement = plan("Replacement")
        let store = AppSessionStore(activePlan: first, defaults: defaults)
        XCTAssertTrue(store.pauseTrainingPlan(first.id))
        XCTAssertTrue(store.addTrainingPlan(replacement))
        XCTAssertEqual(store.activePlan?.id, replacement.id)
        XCTAssertFalse(store.resumeTrainingPlan(first.id))
        XCTAssertTrue(store.isTrainingPlanPaused(first.id))
        XCTAssertEqual(store.activePlan?.id, replacement.id)
    }

    func testUpcomingPlanIsVisibleAndDisabledPlansAreNotPreviewed() throws {
        let suite = "PlanLifecycle.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        var future = plan("First 5K")
        future.startDate = Calendar.current.date(byAdding: .day, value: 5, to: Date())
        let store = AppSessionStore(defaults: defaults)
        XCTAssertTrue(store.addTrainingPlan(future))
        XCTAssertNil(store.activePlan)
        XCTAssertEqual(store.nextTrainingPlan?.id, future.id)

        XCTAssertTrue(store.deactivateTrainingPlan(future.id))
        XCTAssertNil(store.nextTrainingPlan)
        XCTAssertNotNil(store.trainingPlan(withID: future.id))
        XCTAssertTrue(store.resumeTrainingPlan(future.id))
        XCTAssertEqual(store.nextTrainingPlan?.id, future.id)

        XCTAssertTrue(store.pauseTrainingPlan(future.id))
        XCTAssertNil(store.nextTrainingPlan)
    }

    func testNewPlanMayStartTodayAfterExplicitDeactivationOfOverlappingPlan() throws {
        let suite = "PlanLifecycle.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        var future = plan("First 5K")
        future.startDate = Calendar.current.date(byAdding: .day, value: 5, to: Date())
        var today = plan("New program")
        today.weeks.append(TrainingPlanWeek(
            id: UUID(), weekNumber: 2, title: "Week 2",
            days: (1...7).map {
                TrainingPlanDay(id: UUID(), dayIndex: $0, title: "", sessions: [])
            }
        ))

        let store = AppSessionStore(defaults: defaults)
        XCTAssertTrue(store.addTrainingPlan(future))
        XCTAssertEqual(store.trainingPlanConflict(
            startDate: Calendar.current.startOfDay(for: Date()),
            weekCount: 2
        )?.id, future.id)
        XCTAssertFalse(store.addTrainingPlan(today))

        // The old plan is retained, not deleted or silently rescheduled.
        XCTAssertTrue(store.deactivateTrainingPlan(future.id))
        XCTAssertTrue(store.addTrainingPlan(today))
        XCTAssertEqual(store.activePlan?.id, today.id)
        XCTAssertNil(store.nextTrainingPlan)
        XCTAssertTrue(store.isTrainingPlanDeactivated(future.id))
        XCTAssertNotNil(store.trainingPlan(withID: future.id))
    }

    func testEditingExistingPlanRetainsIdentityAndLinkedCopy() throws {
        let suite = "PlanEdit.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppSessionStore(defaults: defaults)
        var source = plan("Original")
        source.ownerID = store.profile.userID
        let workout = PlannedSession(id: UUID(), title: "Run", kind: .running,
            scheduledStart: nil, durationMinutes: 45, targetDistanceKilometers: 5,
            targetPaceSecondsPerKilometer: nil, routeID: nil, exercises: [], notes: "Keep")
        source.weeks[0].days[0].sessions = [workout]
        XCTAssertTrue(store.addTrainingPlan(source))
        let original = try XCTUnwrap(store.trainingPlan(withID: source.id))
        let anchor = try XCTUnwrap(original.startDate)
        let weekday = (Calendar.current.component(.weekday, from: anchor) + 5) % 7 + 1
        var day = ATHLTHPlanWeekDayEdit()
        day.detailedWorkout = .editingSnapshot(workout)
        day.additionalDetailedWorkouts = []
        let edits = [weekday: day]
        let savedCopyID = try XCTUnwrap(store.planTemplates.first?.id)
        XCTAssertTrue(store.saveEditedTrainingPlan(original: original, reusable: false,
            originalAnchor: anchor, title: "Updated", summary: "", visibility: .privateOnly,
            startDate: anchor, weekCount: 1, builderProfile: nil, initialEdits: edits, edits: edits))
        let saved = try XCTUnwrap(store.trainingPlan(withID: source.id))
        XCTAssertEqual(saved.title, "Updated")
        XCTAssertEqual(saved.version, original.version + 1)
        XCTAssertEqual(saved.weeks[0].days[0].sessions, [workout])
        XCTAssertEqual(store.trainingPlans.count, 1)
        XCTAssertEqual(store.planTemplates.count, 1)
        XCTAssertEqual(store.planTemplates.first?.id, savedCopyID)
        XCTAssertEqual(store.planTemplates.first?.title, "Updated")
        XCTAssertFalse(store.saveEditedTrainingPlan(original: original, reusable: false,
            originalAnchor: anchor, title: "Stale", summary: "", visibility: .privateOnly,
            startDate: anchor, weekCount: 1, builderProfile: nil, initialEdits: edits, edits: edits))
    }

    func testEditingInactivePlanDoesNotReactivateIt() throws {
        let suite = "InactivePlanEdit.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppSessionStore(defaults: defaults)
        var source = plan("Original")
        source.ownerID = store.profile.userID
        XCTAssertTrue(store.addTrainingPlan(source))
        XCTAssertTrue(store.deactivateTrainingPlan(source.id))
        let original = try XCTUnwrap(store.trainingPlan(withID: source.id))
        let anchor = try XCTUnwrap(original.startDate)
        XCTAssertTrue(store.saveEditedTrainingPlan(original: original, reusable: false,
            originalAnchor: anchor, title: "Updated", summary: "", visibility: .privateOnly,
            startDate: anchor, weekCount: 1, builderProfile: nil, initialEdits: [:], edits: [:]))
        XCTAssertTrue(store.isTrainingPlanDeactivated(source.id))
        XCTAssertNil(store.activePlan)
        XCTAssertEqual(store.trainingPlan(withID: source.id)?.title, "Updated")
    }

    func testEditingReusablePlanDoesNotScheduleIt() throws {
        let suite = "TemplatePlanEdit.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppSessionStore(defaults: defaults)
        var source = plan("Original")
        source.ownerID = store.profile.userID
        store.savePlanToLibrary(source)
        let original = try XCTUnwrap(store.planTemplates.first)
        let anchor = try XCTUnwrap(source.startDate)
        XCTAssertTrue(store.saveEditedTrainingPlan(original: original, reusable: true,
            originalAnchor: anchor, title: "Updated", summary: "", visibility: .privateOnly,
            startDate: anchor, weekCount: 1, builderProfile: nil, initialEdits: [:], edits: [:]))
        XCTAssertEqual(store.planTemplates.count, 1)
        XCTAssertEqual(store.planTemplates.first?.id, original.id)
        XCTAssertEqual(store.planTemplates.first?.title, "Updated")
        XCTAssertNil(store.planTemplates.first?.startDate)
        XCTAssertTrue(store.trainingPlans.isEmpty)
    }

        func testOldAccountTrainingContentDecodesWithoutLifecycleFields() throws {
        let old = """
        {"activePlan":null,"scheduledPlans":[],"planTemplates":[],
         "savedWorkoutTemplates":[],"manuallyCompletedPlanSessions":[],
         "savedRoutes":[],"onboardingProfile":null}
        """
        let parsed = try JSONDecoder().decode(
            AccountTrainingContent.self, from: Data(old.utf8)
        )
        XCTAssertNil(parsed.pausedTrainingPlanIDs)
        XCTAssertNil(parsed.deactivatedTrainingPlanIDs)
    }
}
