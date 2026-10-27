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
