import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHPlanReviewDurationProposalTests: XCTestCase {
    @MainActor
    private func store() -> (AppSessionStore, UserDefaults, String) {
        let suite = "ATHLTHPlanReviewDurationProposalTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (AppSessionStore(defaults: defaults), defaults, suite)
    }

    private func workout(
        duration: Int?, kind: WorkoutKind = .running
    ) -> PlannedSession {
        PlannedSession(
            id: UUID(), title: "Target workout", kind: kind,
            scheduledStart: nil, durationMinutes: duration,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil, exercises: [], notes: nil
        )
    }

    @MainActor
    private func prepared(
        peerMinutes: [Int],
        targetKind: WorkoutKind = .running
    ) throws -> (
        AppSessionStore, UserDefaults, String,
        TrainingPlan, PlannedSession
    ) {
        let (session, defaults, suite) = store()
        let start = Calendar.current.startOfDay(for: Date())
        let original = try XCTUnwrap(session.createTrainingPlan(
            title: "Approval", summary: "", weekCount: 1,
            startDate: start
        ))
        let target = workout(duration: nil, kind: targetKind)
        session.addSession(
            target, toDay: original.weeks[0].days[0].id, inPlan: original.id
        )
        for (index, minutes) in peerMinutes.enumerated() {
            session.addSession(
                workout(duration: minutes),
                toDay: original.weeks[0].days[index + 1].id,
                inPlan: original.id
            )
        }
        return (
            session, defaults, suite,
            try XCTUnwrap(session.trainingPlan(withID: original.id)), target
        )
    }

    @MainActor
    private func proposal(
        for plan: TrainingPlan
    ) throws -> ATHLTHPlanReviewDurationProposal.Proposal {
        let advice = ATHLTHPlanReviewAdvisor.inspect(plan)
        let suggestion = try XCTUnwrap(advice.first(where: {
            $0.kind == .missingDuration
        }))
        return try XCTUnwrap(ATHLTHPlanReviewDurationProposal.suggest(
            for: suggestion, in: plan
        ))
    }

    @MainActor
    func testPreviewDoesNotChangePlanUntilExplicitlyApproved() throws {
        let (session, defaults, suite, saved, target) = try prepared(
            peerMinutes: [30, 50]
        )
        defer { defaults.removePersistentDomain(forName: suite) }
        let preview = try proposal(for: saved)
        XCTAssertEqual(preview.suggestedMinutes, 40)
        XCTAssertEqual(preview.comparableSessionCount, 2)
        XCTAssertNil(saved.weeks[0].days[0].sessions[0].durationMinutes)
        XCTAssertEqual(session.trainingPlan(withID: saved.id)?.version, saved.version)

        XCTAssertTrue(session.applyPlanReviewDurationProposal(
            preview, healthWorkouts: [], strengthHistory: []
        ))
        let updated = try XCTUnwrap(session.trainingPlan(withID: saved.id))
        XCTAssertEqual(updated.version, saved.version + 1)
        XCTAssertEqual(
            updated.weeks[0].days[0].sessions[0].durationMinutes, 40
        )
        XCTAssertEqual(
            updated.weeks[0].days[0].sessions[0].id, target.id
        )
        XCTAssertEqual(
            updated.weeks[0].days[1].sessions[0].durationMinutes, 30
        )
        XCTAssertFalse(session.applyPlanReviewDurationProposal(
            preview, healthWorkouts: [], strengthHistory: []
        ))
    }

    @MainActor
    func testStalePreviewCannotOverwriteNewPlanVersion() throws {
        let (session, defaults, suite, plan, _) = try prepared(
            peerMinutes: [35, 45]
        )
        defer { defaults.removePersistentDomain(forName: suite) }
        let preview = try proposal(for: plan)
        session.addSession(
            workout(duration: 60),
            toDay: plan.weeks[0].days[5].id,
            inPlan: plan.id
        )
        XCTAssertFalse(session.applyPlanReviewDurationProposal(
            preview, healthWorkouts: [], strengthHistory: []
        ))
        XCTAssertNil(
            session.trainingPlan(withID: plan.id)?
                .weeks[0].days[0].sessions[0].durationMinutes
        )
    }

    @MainActor
    func testCompletedOrSkippedSessionCannotBeUpdated() throws {
        let (session, defaults, suite, plan, target) = try prepared(
            peerMinutes: [35, 45]
        )
        defer { defaults.removePersistentDomain(forName: suite) }
        let preview = try proposal(for: plan)
        session.setPlanSessionManuallyCompleted(
            planID: plan.id, sessionID: target.id, completed: true
        )
        XCTAssertFalse(session.applyPlanReviewDurationProposal(
            preview, healthWorkouts: [], strengthHistory: []
        ))
        session.setPlanSessionManuallyCompleted(
            planID: plan.id, sessionID: target.id, completed: false
        )
        session.setPlanSessionSkipped(
            planID: plan.id, sessionID: target.id, skipped: true
        )
        XCTAssertFalse(session.applyPlanReviewDurationProposal(
            preview, healthWorkouts: [], strengthHistory: []
        ))
    }

    @MainActor
    func testTooLittleEvidenceAndDifferentWorkoutKindsNeverSuggest() throws {
        let (session, defaults, suite, plan, _) = try prepared(
            peerMinutes: [45], targetKind: .strength
        )
        defer { defaults.removePersistentDomain(forName: suite) }
        let suggestion = try XCTUnwrap(
            ATHLTHPlanReviewAdvisor.inspect(plan).first(where: {
                $0.kind == .missingDuration
            })
        )
        XCTAssertNil(ATHLTHPlanReviewDurationProposal.suggest(
            for: suggestion, in: plan
        ))
        let noChange = try XCTUnwrap(
            session.trainingPlan(withID: plan.id)
        )
        XCTAssertNil(noChange.weeks[0].days[0].sessions[0].durationMinutes)
    }
}
