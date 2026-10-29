import Combine
import Foundation
import XCTest
@testable import ATHLTH

/// Train is a persistent tab and can refresh when foregrounded, when the
/// calendar day rolls over, and on account changes. A no-op refresh must
/// not rebroadcast the entire training-plan graph or schedule a disk write.
@MainActor
final class ATHLTHPlanRefreshPerformanceTests: XCTestCase {
    private func samplePlan() -> TrainingPlan {
        let today = Calendar.current.startOfDay(for: Date())
        return TrainingPlan(
            id: UUID(), ownerID: UUID(), title: "Training",
            summary: "", visibility: .privateOnly, version: 1,
            weeks: [TrainingPlanWeek(
                id: UUID(), weekNumber: 1, title: "Week",
                days: (1...7).map { day in
                    TrainingPlanDay(
                        id: UUID(), dayIndex: day, title: "", sessions: []
                    )
                }
            )],
            tags: [], createdAt: today, updatedAt: today,
            startDate: today
        )
    }

    func testRepeatedNoOpPlanRefreshDoesNotInvalidateObservers() throws {
        let suite = "ATHLTHPlanPerformance.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let plan = samplePlan()
        let store = AppSessionStore(activePlan: plan, defaults: defaults)
        store.refreshActivePlanForToday()
        XCTAssertEqual(store.activePlan?.id, plan.id)

        var publications = 0
        let subscription = store.objectWillChange.sink {
            publications += 1
        }
        defer { subscription.cancel() }

        for _ in 0..<6 {
            store.refreshActivePlanForToday()
        }
        XCTAssertEqual(
            publications, 0,
            "An unchanged plan must not repeatedly publish or schedule saves."
        )
        XCTAssertEqual(store.activePlan?.id, plan.id)
    }

    func testEmptyPlansRefreshDoesNotPublish() throws {
        let suite = "ATHLTHNoPlansPerformance.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppSessionStore(defaults: defaults)
        var publications = 0
        let subscription = store.objectWillChange.sink {
            publications += 1
        }
        defer { subscription.cancel() }

        store.refreshActivePlanForToday()
        store.refreshActivePlanForToday()

        XCTAssertNil(store.activePlan)
        XCTAssertEqual(publications, 0)
    }
}
