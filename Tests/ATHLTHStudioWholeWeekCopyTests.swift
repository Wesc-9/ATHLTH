import Foundation
import XCTest
@testable import ATHLTH

/// Exercises the real AppSessionStore mutation/persistence boundary, rather
/// than mocking a copied week inside the iPad view.
final class ATHLTHStudioWholeWeekCopyTests: XCTestCase {
    @MainActor
    private func makeStore() -> (AppSessionStore, UserDefaults, String) {
        let name = "ATHLTHStudioWholeWeekCopyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        return (AppSessionStore(defaults: defaults), defaults, name)
    }

    private func workout(_ name: String, restDay: Bool = false) -> PlannedSession {
        var result = PlannedSession(
            id: UUID(),
            title: name,
            kind: restDay ? .recovery : .running,
            scheduledStart: nil,
            durationMinutes: restDay ? nil : 40,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil,
            exercises: [],
            notes: nil
        )
        if restDay { result.workoutCategory = "rest_day" }
        return result
    }

    @MainActor
    func testWholeWeekCopyIsAtomicAndCanBeUndone() throws {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        let start = Calendar.current.startOfDay(for: Date())
        let plan = try XCTUnwrap(store.createTrainingPlan(
            title: "Four-week program", summary: "",
            weekCount: 4, startDate: start
        ))
        let monday = workout("Hill repeats")
        let wednesday = workout("Long run")
        let friday = workout("Rest", restDay: true)
        store.addSession(monday, toDay: plan.weeks[0].days[0].id, inPlan: plan.id)
        store.addSession(wednesday, toDay: plan.weeks[0].days[2].id, inPlan: plan.id)
        store.addSession(friday, toDay: plan.weeks[0].days[4].id, inPlan: plan.id)
        let original = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        let receipt = try XCTUnwrap(store.copyPlanStudioWeek(
            planID: plan.id,
            sourceWeekID: original.weeks[0].id,
            targetWeekID: original.weeks[1].id,
            expectedVersion: original.version
        ))
        let copied = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        XCTAssertEqual(copied.version, original.version + 1)
        XCTAssertEqual(copied.weeks[0].days.flatMap(\.sessions).count, 3)
        XCTAssertEqual(copied.weeks[1].days.flatMap(\.sessions).count, 3)
        XCTAssertEqual(
            Set(copied.weeks[1].days.flatMap(\.sessions).map(\.id)),
            receipt.newSessionIDs
        )
        XCTAssertTrue(
            Set(copied.weeks[0].days.flatMap(\.sessions).map(\.id))
                .isDisjoint(with: receipt.newSessionIDs)
        )
        XCTAssertTrue(copied.weeks[1].days[4].sessions[0].isExplicitRestDay)
        XCTAssertEqual(copied.weeks[1].days[0].sessions[0].title, monday.title)

        XCTAssertTrue(store.undoPlanStudioWeekCopy(
            receipt, healthWorkouts: [], strengthHistory: []
        ))
        let undone = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        XCTAssertEqual(undone.version, copied.version + 1)
        XCTAssertTrue(undone.weeks[1].days.allSatisfy(\.sessions.isEmpty))
        XCTAssertEqual(
            undone.weeks[0].days.flatMap(\.sessions).map(\.id),
            original.weeks[0].days.flatMap(\.sessions).map(\.id)
        )
        XCTAssertFalse(store.undoPlanStudioWeekCopy(
            receipt, healthWorkouts: [], strengthHistory: []
        ))
    }

    @MainActor
    func testWeekCopyCannotOverwritePopulatedWeekOrUseStaleVersion() throws {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let plan = try XCTUnwrap(store.createTrainingPlan(
            title: "Protect existing days", summary: "",
            weekCount: 3,
            startDate: Calendar.current.startOfDay(for: Date())
        ))
        store.addSession(
            workout("Original"),
            toDay: plan.weeks[0].days[0].id, inPlan: plan.id
        )
        let before = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        store.addSession(
            workout("Target already used"),
            toDay: plan.weeks[1].days[3].id, inPlan: plan.id
        )
        let latest = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        XCTAssertNil(store.copyPlanStudioWeek(
            planID: plan.id, sourceWeekID: before.weeks[0].id,
            targetWeekID: before.weeks[2].id,
            expectedVersion: before.version
        ))
        XCTAssertNil(store.copyPlanStudioWeek(
            planID: plan.id, sourceWeekID: before.weeks[0].id,
            targetWeekID: before.weeks[1].id,
            expectedVersion: latest.version
        ))
        XCTAssertEqual(
            store.trainingPlan(withID: plan.id)?.version,
            latest.version
        )
    }

    @MainActor
    func testUndoCannotClobberNewerEdits() throws {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let plan = try XCTUnwrap(store.createTrainingPlan(
            title: "Version guard", summary: "", weekCount: 3,
            startDate: Calendar.current.startOfDay(for: Date())
        ))
        store.addSession(workout("Workout"),
                         toDay: plan.weeks[0].days[0].id, inPlan: plan.id)
        let before = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        let receipt = try XCTUnwrap(store.copyPlanStudioWeek(
            planID: plan.id,
            sourceWeekID: before.weeks[0].id,
            targetWeekID: before.weeks[1].id,
            expectedVersion: before.version
        ))
        store.addSession(workout("Newer edit"),
                         toDay: before.weeks[2].days[0].id, inPlan: plan.id)
        XCTAssertFalse(store.undoPlanStudioWeekCopy(
            receipt, healthWorkouts: [], strengthHistory: []
        ))
        let latest = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        XCTAssertEqual(latest.weeks[1].days[0].sessions.count, 1)
        XCTAssertEqual(latest.weeks[2].days[0].sessions.count, 1)
    }
}
