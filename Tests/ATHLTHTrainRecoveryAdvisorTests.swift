import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHTrainRecoveryAdvisorTests: XCTestCase {
    private var start: Date {
        Calendar.current.startOfDay(
            for: Date(timeIntervalSince1970: 1_920_000_000)
        )
    }

    private func makeExercise() -> PlannedExercise {
        PlannedExercise(
            id: UUID(),
            exerciseID: nil,
            embeddedExercise: ExerciseSnapshot(
                name: "Squat", instructions: [],
                primaryMuscles: ["quads"], secondaryMuscles: [],
                equipment: ["Barbell"], imageURL: nil
            ),
            sets: 4, reps: 8,
            targetWeightKilograms: 80,
            targetRPE: nil, restSeconds: 120,
            notes: nil
        )
    }

    private func makeSession(kind: WorkoutKind = .strength) -> PlannedSession {
        PlannedSession(
            id: UUID(), title: "Legs", kind: kind,
            scheduledStart: nil, durationMinutes: 60,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil,
            exercises: kind == .strength ? [makeExercise()] : [],
            notes: nil
        )
    }

    private func plan(day: Int = 1, kind: WorkoutKind = .strength) -> TrainingPlan {
        TrainingPlan(
            id: UUID(), ownerID: UUID(), title: "Build",
            summary: "", visibility: .privateOnly,
            version: 1, weeks: [
                TrainingPlanWeek(
                    id: UUID(), weekNumber: 1, title: "Week",
                    days: [
                        TrainingPlanDay(
                            id: UUID(), dayIndex: day,
                            title: "Today", sessions: [makeSession(kind: kind)]
                        )
                    ]
                )
            ],
            tags: [], createdAt: start,
            updatedAt: start, startDate: start
        )
    }

    private var lowReadiness: RecoveryReadinessSummary {
        RecoveryReadinessSummary(
            score: 42, state: .recover, detail: "Low",
            baselineDays: 7, averageSleepDuration: 25_000,
            baselineHRVMilliseconds: 50,
            baselineRestingHeartRate: 60
        )
    }

    func testNoOptInOrRecentSignalsNeverSuggestsWorkout() {
        let source = plan()
        let proposals = ATHLTHTrainRecoveryAdvisor.proposals(
            plan: source, completedIDs: [], skippedIDs: [],
            strengthHistory: [], selfReportedEnergy: nil,
            readiness: nil, now: start
        )
        XCTAssertTrue(proposals.isEmpty)
    }

    func testManualLowEnergySuggestsFutureStrengthWorkout() throws {
        let source = plan()
        let result = ATHLTHTrainRecoveryAdvisor.proposals(
            plan: source, completedIDs: [], skippedIDs: [],
            strengthHistory: [], selfReportedEnergy: 2,
            readiness: nil, now: start
        )
        let suggestion = try XCTUnwrap(result.first)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(suggestion.beforeWorkingSets, 4)
        XCTAssertEqual(suggestion.afterWorkingSets, 3)
        XCTAssertEqual(suggestion.beforeWeight, 80)
        XCTAssertEqual(suggestion.afterWeight, 72)
        XCTAssertTrue(suggestion.hasChanges)
        XCTAssertEqual(source.weeks[0].days[0].sessions[0].exercises[0].sets, 4)
    }

    func testReadinessWithoutBaselineDoesNotFabricateSuggestion() {
        let empty = RecoveryReadinessSummary.buildingBaseline
        let result = ATHLTHTrainRecoveryAdvisor.proposals(
            plan: plan(), completedIDs: [], skippedIDs: [],
            strengthHistory: [], selfReportedEnergy: nil,
            readiness: empty, now: start
        )
        XCTAssertTrue(result.isEmpty)
    }

    func testFreshLowReadinessCanSuggestWithoutManualEnergy() {
        let result = ATHLTHTrainRecoveryAdvisor.proposals(
            plan: plan(), completedIDs: [], skippedIDs: [],
            strengthHistory: [], selfReportedEnergy: nil,
            readiness: lowReadiness, now: start
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result[0].signals.contains(.lowRecentReadiness))
    }

    func testCompletedSkippedAndPastDaysAreProtected() {
        let source = plan()
        let id = source.weeks[0].days[0].sessions[0].id
        let completed = ATHLTHTrainRecoveryAdvisor.proposals(
            plan: source, completedIDs: [id], skippedIDs: [],
            strengthHistory: [], selfReportedEnergy: 1,
            readiness: nil, now: start
        )
        let skipped = ATHLTHTrainRecoveryAdvisor.proposals(
            plan: source, completedIDs: [], skippedIDs: [id],
            strengthHistory: [], selfReportedEnergy: 1,
            readiness: nil, now: start
        )
        let past = ATHLTHTrainRecoveryAdvisor.proposals(
            plan: source, completedIDs: [], skippedIDs: [],
            strengthHistory: [], selfReportedEnergy: 1,
            readiness: nil, now: start.addingTimeInterval(3 * 86_400)
        )
        XCTAssertTrue(completed.isEmpty)
        XCTAssertTrue(skipped.isEmpty)
        XCTAssertTrue(past.isEmpty)
    }

    func testRunningIsNotChangedByStrengthRule() {
        let result = ATHLTHTrainRecoveryAdvisor.proposals(
            plan: plan(kind: .running),
            completedIDs: [], skippedIDs: [],
            strengthHistory: [], selfReportedEnergy: 1,
            readiness: lowReadiness, now: start
        )
        XCTAssertTrue(result.isEmpty)
    }

    func testIndividualWarmupTargetsAndIDsArePreserved() throws {
        var workout = makeSession()
        let warmup = PlannedExerciseSetTarget(
            reps: 10, weightKilograms: 20,
            isWarmUp: true, setType: .warmUp
        )
        let first = PlannedExerciseSetTarget(reps: 8, weightKilograms: 80)
        let second = PlannedExerciseSetTarget(reps: 8, weightKilograms: 85)
        let third = PlannedExerciseSetTarget(reps: 8, weightKilograms: 90)
        let fourth = PlannedExerciseSetTarget(reps: 8, weightKilograms: 95)
        workout.exercises[0].sets = 5
        workout.exercises[0].setTargets = [warmup, first, second, third, fourth]

        let lighter = try XCTUnwrap(
            ATHLTHTrainRecoveryAdvisor.lighterStrengthSession(workout)
        )
        XCTAssertEqual(lighter.exercises[0].sets, 4)
        XCTAssertEqual(lighter.exercises[0].setTargets?.first?.id, warmup.id)
        XCTAssertEqual(lighter.exercises[0].setTargets?.first?.weightKilograms, 20)
        XCTAssertEqual(lighter.exercises[0].setTargets?[1].id, first.id)
        XCTAssertEqual(lighter.exercises[0].setTargets?[1].weightKilograms, 72)
        XCTAssertNotNil(lighter.recoveryOriginalExercises)
        XCTAssertEqual(lighter.recoveryAdjustedExercises, lighter.exercises)
        XCTAssertEqual(workout.exercises[0].setTargets?.count, 5)
        XCTAssertNil(ATHLTHTrainRecoveryAdvisor.lighterStrengthSession(lighter))
    }

    func testMissingWeightNeverGetsInvented() throws {
        var workout = makeSession()
        workout.exercises[0].targetWeightKilograms = nil
        let adjusted = try XCTUnwrap(
            ATHLTHTrainRecoveryAdvisor.lighterStrengthSession(workout)
        )
        XCTAssertNil(adjusted.exercises[0].targetWeightKilograms)
        XCTAssertEqual(adjusted.exercises[0].sets, 3)
        XCTAssertEqual(workout.exercises[0].sets, 4)
    }

    func testPastSessionCannotBeSuggestedWithFutureReadiness() {
        let source = plan(day: 1)
        let result = ATHLTHTrainRecoveryAdvisor.proposals(
            plan: source, completedIDs: [], skippedIDs: [],
            strengthHistory: [], selfReportedEnergy: 1,
            readiness: lowReadiness,
            now: start.addingTimeInterval(86_400)
        )
        XCTAssertTrue(result.isEmpty)
    }
}
