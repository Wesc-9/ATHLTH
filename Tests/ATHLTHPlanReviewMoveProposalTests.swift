import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHPlanReviewMoveProposalTests: XCTestCase {
    @MainActor
    private func makeStore() -> (AppSessionStore, UserDefaults, String) {
        let suite = "ATHLTHPlanReviewMoveProposalTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (AppSessionStore(defaults: defaults), defaults, suite)
    }

    private func workout(_ kind: WorkoutKind, minutes: Int = 40) -> PlannedSession {
        PlannedSession(
            id: UUID(), title: "Session", kind: kind,
            scheduledStart: nil, durationMinutes: minutes,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil, exercises: [], notes: nil
        )
    }

    @MainActor
    private func plan(
        dayWorkouts: [(Int, [PlannedSession])]
    ) throws -> (AppSessionStore, UserDefaults, String, TrainingPlan) {
        let (store, defaults, suite) = makeStore()
        let start = Calendar.current.startOfDay(for: Date())
        let created = try XCTUnwrap(store.createTrainingPlan(
            title: "Scheduling", summary: "",
            weekCount: 1, startDate: start
        ))
        for (dayIndex, workouts) in dayWorkouts {
            for workout in workouts {
                store.addSession(
                    workout,
                    toDay: created.weeks[0].days[dayIndex - 1].id,
                    inPlan: created.id
                )
            }
        }
        return (store, defaults, suite,
            try XCTUnwrap(store.trainingPlan(withID: created.id)))
    }

    @MainActor
    private func suggestion(
        in plan: TrainingPlan,
        kind: ATHLTHPlanReviewAdvisor.Kind
    ) throws -> ATHLTHPlanReviewAdvisor.Suggestion {
        try XCTUnwrap(
            ATHLTHPlanReviewAdvisor.inspect(plan).first(where: {
                $0.kind == kind
            })
        )
    }

    @MainActor
    func testMixedDayMoveRequiresApprovalAndPreservesSessionID() throws {
        let run = workout(.running)
        let lift = workout(.strength)
        let (store, defaults, suite, initial) = try plan(dayWorkouts: [
            (1, [run, lift])
        ])
        defer { defaults.removePersistentDomain(forName: suite) }
        let finding = try suggestion(in: initial, kind: .mixedDay)
        let proposal = try XCTUnwrap(ATHLTHPlanReviewMoveProposal.suggest(
            for: finding, in: initial
        ))
        XCTAssertEqual(proposal.workoutID, lift.id)
        XCTAssertNotEqual(proposal.sourceDayID, proposal.targetDayID)
        XCTAssertTrue(initial.weeks[0].days[0].sessions.contains(where: {
            $0.id == lift.id
        }))
        XCTAssertTrue(store.applyPlanReviewMoveProposal(
            proposal, healthWorkouts: [], strengthHistory: []
        ))
        let updated = try XCTUnwrap(store.trainingPlan(withID: initial.id))
        XCTAssertEqual(updated.version, initial.version + 1)
        XCTAssertFalse(updated.weeks[0].days[0].sessions.contains(where: {
            $0.id == lift.id
        }))
        let moved = try XCTUnwrap(updated.weeks[0].days
            .flatMap(\.sessions).first(where: { $0.id == lift.id }))
        XCTAssertEqual(moved.kind, .strength)
        XCTAssertEqual(moved.durationMinutes, 40)
        XCTAssertFalse(store.applyPlanReviewMoveProposal(
            proposal, healthWorkouts: [], strengthHistory: []
        ))
    }

    @MainActor
    func testConsecutiveRunProposalReducesStreak() throws {
        let r1 = workout(.running), r2 = workout(.running), r3 = workout(.running)
        let (store, defaults, suite, initial) = try plan(dayWorkouts: [
            (1, [r1]), (2, [r2]), (3, [r3])
        ])
        defer { defaults.removePersistentDomain(forName: suite) }
        let finding = try suggestion(in: initial, kind: .consecutiveRuns)
        let proposal = try XCTUnwrap(ATHLTHPlanReviewMoveProposal.suggest(
            for: finding, in: initial
        ))
        XCTAssertEqual(proposal.workoutID, r3.id)
        XCTAssertTrue(store.applyPlanReviewMoveProposal(
            proposal, healthWorkouts: [], strengthHistory: []
        ))
        let updated = try XCTUnwrap(store.trainingPlan(withID: initial.id))
        let runDays = updated.weeks[0].days.filter {
            $0.sessions.contains(where: { $0.kind == .running })
        }.map(\.dayIndex)
        XCTAssertEqual(runDays.count, 3)
        XCTAssertFalse(
            (1...5).contains(where: { x in
                runDays.contains(x) && runDays.contains(x+1) && runDays.contains(x+2)
            })
        )
    }

    @MainActor
    func testStaleOrCompletedOrSkippedMoveIsRejected() throws {
        let lift = workout(.strength), run = workout(.running)
        let (store, defaults, suite, initial) = try plan(dayWorkouts: [
            (1, [run, lift])
        ])
        defer { defaults.removePersistentDomain(forName: suite) }
        let finding = try suggestion(in: initial, kind: .mixedDay)
        let proposal = try XCTUnwrap(ATHLTHPlanReviewMoveProposal.suggest(
            for: finding, in: initial
        ))
        store.setPlanSessionManuallyCompleted(
            planID: initial.id, sessionID: lift.id, completed: true
        )
        XCTAssertFalse(store.applyPlanReviewMoveProposal(
            proposal, healthWorkouts: [], strengthHistory: []
        ))
        store.setPlanSessionManuallyCompleted(
            planID: initial.id, sessionID: lift.id, completed: false
        )
        store.setPlanSessionSkipped(
            planID: initial.id, sessionID: lift.id, skipped: true
        )
        XCTAssertFalse(store.applyPlanReviewMoveProposal(
            proposal, healthWorkouts: [], strengthHistory: []
        ))
        store.setPlanSessionSkipped(
            planID: initial.id, sessionID: lift.id, skipped: false
        )
        store.addSession(
            workout(.walking),
            toDay: initial.weeks[0].days[5].id,
            inPlan: initial.id
        )
        XCTAssertFalse(store.applyPlanReviewMoveProposal(
            proposal, healthWorkouts: [], strengthHistory: []
        ))
    }

    @MainActor
    func testNoEmptyDayMeansNoSuggestion() throws {
        let lift = workout(.strength), run = workout(.running)
        var scheduled: [(Int, [PlannedSession])] = [(1, [run, lift])]
        for i in 2...7 {
            scheduled.append((i, [workout(.walking)]))
        }
        let (_, defaults, suite, initial) = try plan(dayWorkouts: scheduled)
        defer { defaults.removePersistentDomain(forName: suite) }
        let finding = try suggestion(in: initial, kind: .mixedDay)
        XCTAssertNil(ATHLTHPlanReviewMoveProposal.suggest(
            for: finding, in: initial
        ))
    }
}
