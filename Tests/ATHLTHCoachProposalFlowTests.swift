import Foundation
import XCTest
@testable import ATHLTH

@MainActor
final class ATHLTHCoachProposalFlowTests: XCTestCase {
    private func workoutProposal() -> RecoveryCoachProposal {
        RecoveryCoachProposal(
            kind: "workout",
            title: "Chest strength",
            summary: "Chest and triceps with warm-up",
            activity: "strength",
            durationMinutes: 50,
            weekCount: 1,
            sessionsPerWeek: 1,
            steps: [
                RecoveryCoachProposalStep(
                    title: "Bench press", phase: "main",
                    minutes: 0, sets: 4, repetitions: 8, restSeconds: 120
                ),
                RecoveryCoachProposalStep(
                    title: "Incline dumbbell press", phase: "main",
                    minutes: 0, sets: 3, repetitions: 10, restSeconds: 90
                ),
            ]
        )
    }

    func testCoachWorkoutIsEditableAndNotPreloadedWithPersonalWeights() throws {
        let proposal = workoutProposal()
        let result = try XCTUnwrap(ATHLTHCoachProposalBridge.workout(proposal))
        XCTAssertEqual(result.title, proposal.title)
        XCTAssertEqual(result.kind, .strength)
        XCTAssertNil(result.scheduledStart)
        let blocks = result.resolvedWorkoutBlocks
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0].title, "Bench press")
        XCTAssertEqual(blocks[0].setCount, 4)
        XCTAssertEqual(blocks[0].repetitions, 8)
        XCTAssertEqual(blocks[0].restBetweenSetsSeconds, 120)
        XCTAssertNil(blocks[0].targetWeightKilograms)
        XCTAssertNil(blocks[0].targetPaceSecondsPerKilometer)
    }

    func testMixedRunProposalDoesNotFabricatePaceOrHeartRateTargets() throws {
        let proposal = RecoveryCoachProposal(
            kind: "workout",
            title: "4x4 intervals",
            summary: "Four repeats",
            activity: "running",
            durationMinutes: 42,
            weekCount: 1,
            sessionsPerWeek: 1,
            steps: [
                RecoveryCoachProposalStep(
                    title: "Warm-up", phase: "warmup",
                    minutes: 10, sets: 0, repetitions: 0, restSeconds: 0
                ),
                RecoveryCoachProposalStep(
                    title: "Interval 1", phase: "main",
                    minutes: 4, sets: 0, repetitions: 0, restSeconds: 120
                ),
                RecoveryCoachProposalStep(
                    title: "Cool-down", phase: "cooldown",
                    minutes: 10, sets: 0, repetitions: 0, restSeconds: 0
                ),
            ]
        )
        let workout = try XCTUnwrap(ATHLTHCoachProposalBridge.workout(proposal))
        XCTAssertEqual(workout.kind, .running)
        XCTAssertNil(workout.targetPaceSecondsPerKilometer)
        XCTAssertEqual(workout.resolvedWorkoutBlocks.first?.resolvedPhase, .warmup)
        XCTAssertEqual(workout.resolvedWorkoutBlocks.last?.resolvedPhase, .cooldown)
        XCTAssertTrue(workout.resolvedWorkoutBlocks.allSatisfy {
            $0.targetPaceSecondsPerKilometer == nil &&
                $0.targetHeartRateZone == nil
        })
    }

    func testPlanSeedPreservesCoachRequestedScopeForApproval() throws {
        let proposal = RecoveryCoachProposal(
            kind: "plan", title: "10 km plan",
            summary: "Build towards 10 km", activity: "running",
            durationMinutes: 55, weekCount: 8, sessionsPerWeek: 3, steps: []
        )
        let seed = try XCTUnwrap(ATHLTHCoachProposalBridge.planSeed(proposal))
        XCTAssertEqual(seed.preferredTitle, proposal.title)
        XCTAssertEqual(seed.weekCount, 8)
        XCTAssertEqual(seed.sessionsPerWeek, 3)
        XCTAssertEqual(seed.sessionDurationMinutes, 55)
        XCTAssertNil(ATHLTHCoachProposalBridge.workout(proposal))
    }

    func testInvalidProposalDoesNotBecomeATrainingSession() {
        let invalid = RecoveryCoachProposal(
            kind: "workout", title: "Unsafe",
            summary: "", activity: "strength",
            durationMinutes: 50, weekCount: 1, sessionsPerWeek: 1,
            steps: [
                RecoveryCoachProposalStep(
                    title: "", phase: "main",
                    minutes: 5, sets: 2, repetitions: 10, restSeconds: 30
                ),
            ]
        )
        XCTAssertNil(ATHLTHCoachProposalBridge.workout(invalid))
    }

    func testOldConversationMessageDecodesWithoutProposal() throws {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let old = """
        {"id":"\(id.uuidString)","role":"assistant","text":"Hello","createdAt":\(date.timeIntervalSinceReferenceDate)}
        """
        // JSONEncoder defaults to Foundation's deferred Date strategy; use
        // a freshly encoded message and remove the new optional field.
        let current = RecoveryCoachMessage(
            id: id, role: .assistant, text: "Hello", createdAt: date
        )
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(current))
                as? [String: Any]
        )
        object.removeValue(forKey: "proposal")
        let compatible = try JSONSerialization.data(withJSONObject: object)
        let restored = try JSONDecoder().decode(
            RecoveryCoachMessage.self, from: compatible
        )
        XCTAssertEqual(restored.id, id)
        XCTAssertNil(restored.proposal)
        _ = old
    }

    func testProposalPersistsWithCoachConversation() throws {
        let message = RecoveryCoachMessage(
            role: .assistant, text: "Here is your workout",
            proposal: workoutProposal()
        )
        let serialized = try JSONEncoder().encode(message)
        let restored = try JSONDecoder().decode(
            RecoveryCoachMessage.self, from: serialized
        )
        XCTAssertEqual(restored.proposal, message.proposal)
    }
}
