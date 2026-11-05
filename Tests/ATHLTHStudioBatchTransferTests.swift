import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHStudioBatchTransferTests: XCTestCase {
    @MainActor
    private func makeStore() -> (AppSessionStore, UserDefaults, String) {
        let name = "ATHLTHStudioBatchTransferTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        return (AppSessionStore(defaults: defaults), defaults, name)
    }

    private func workout(_ title: String) -> PlannedSession {
        PlannedSession(
            id: UUID(),
            title: title,
            kind: .running,
            scheduledStart: nil,
            durationMinutes: 40,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil,
            exercises: [],
            notes: nil
        )
    }

    @MainActor
    func testAtomicBatchMoveChangesPlanOnceAndPreservesIDs() throws {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let plan = try XCTUnwrap(store.createTrainingPlan(
            title: "Batch Move", summary: "", weekCount: 3,
            startDate: Calendar.current.startOfDay(for: .now)
        ))
        let first = workout("Intervals")
        let second = workout("Recovery run")
        store.addSession(first, toDay: plan.weeks[0].days[1].id, inPlan: plan.id)
        store.addSession(second, toDay: plan.weeks[0].days[3].id, inPlan: plan.id)
        let before = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        XCTAssertTrue(store.batchTransferPlanStudioWorkouts(
            planID: plan.id,
            workoutIDs: [first.id, second.id],
            targetDayID: before.weeks[1].days[4].id,
            copy: false,
            expectedVersion: before.version,
            healthWorkouts: [], strengthHistory: []
        ))
        let after = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        XCTAssertEqual(after.version, before.version + 1)
        XCTAssertTrue(after.weeks[0].days[1].sessions.isEmpty)
        XCTAssertTrue(after.weeks[0].days[3].sessions.isEmpty)
        XCTAssertEqual(
            Set(after.weeks[1].days[4].sessions.map(\.id)),
            Set([first.id, second.id])
        )
    }

    @MainActor
    func testAtomicBatchCopyGivesNewIdentitiesAndKeepsSources() throws {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let plan = try XCTUnwrap(store.createTrainingPlan(
            title: "Batch Copy", summary: "", weekCount: 3,
            startDate: Calendar.current.startOfDay(for: .now)
        ))
        let first = workout("Tempo")
        let second = workout("Easy")
        store.addSession(first, toDay: plan.weeks[0].days[0].id, inPlan: plan.id)
        store.addSession(second, toDay: plan.weeks[0].days[1].id, inPlan: plan.id)
        let before = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        XCTAssertTrue(store.batchTransferPlanStudioWorkouts(
            planID: plan.id,
            workoutIDs: [first.id, second.id],
            targetDayID: before.weeks[2].days[0].id,
            copy: true,
            expectedVersion: before.version,
            healthWorkouts: [], strengthHistory: []
        ))
        let after = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        XCTAssertEqual(after.version, before.version + 1)
        let copied = after.weeks[2].days[0].sessions
        XCTAssertEqual(copied.count, 2)
        XCTAssertTrue(Set(copied.map(\.id)).isDisjoint(
            with: Set([first.id, second.id])
        ))
        XCTAssertEqual(after.weeks[0].days[0].sessions.first?.id, first.id)
        XCTAssertEqual(after.weeks[0].days[1].sessions.first?.id, second.id)
    }

    @MainActor
    func testBatchRejectsStaleVersionWithoutPartialChanges() throws {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let plan = try XCTUnwrap(store.createTrainingPlan(
            title: "Protected", summary: "", weekCount: 3,
            startDate: Calendar.current.startOfDay(for: .now)
        ))
        let first = workout("Planned one")
        let second = workout("Planned two")
        store.addSession(first, toDay: plan.weeks[0].days[0].id, inPlan: plan.id)
        let stale = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        store.addSession(second, toDay: plan.weeks[0].days[1].id, inPlan: plan.id)
        XCTAssertFalse(store.batchTransferPlanStudioWorkouts(
            planID: plan.id,
            workoutIDs: [first.id, second.id],
            targetDayID: stale.weeks[1].days[0].id,
            copy: false,
            expectedVersion: stale.version,
            healthWorkouts: [], strengthHistory: []
        ))
        let after = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        XCTAssertEqual(after.weeks[0].days[0].sessions.first?.id, first.id)
        XCTAssertEqual(after.weeks[0].days[1].sessions.first?.id, second.id)
        XCTAssertTrue(after.weeks[1].days[0].sessions.isEmpty)
    }
}
