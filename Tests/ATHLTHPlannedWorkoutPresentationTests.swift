import XCTest
@testable import ATHLTH

final class ATHLTHPlannedWorkoutPresentationTests: XCTestCase {
    func testRunningRecipeOverridesStaleDurationAndIncludesIndividualRecoveries() {
        var planned = workout()
        let now = Date()
        planned.runningWorkout = RunningWorkoutTemplate(
            id: UUID(), title: "Short intervals", type: .intervals, summary: "",
            blocks: [RunningWorkoutBlock(kind: .work, title: "Effort", repetitions: 4,
                work: .time(45), recovery: .time(20),
                repetitionOverrides: [RunningRepetitionOverride(
                    repetition: 3, work: .time(47), recovery: .time(35))])],
            routeID: nil, isBuiltIn: false, createdAt: now, updatedAt: now)
        XCTAssertEqual(ATHLTHPlannedWorkoutPresentation.structuredMinutes(for: planned), 5)
        XCTAssertEqual(ATHLTHPlannedWorkoutPresentation.duration(for: planned),
                       ATHLTHLocalization.choose(english: "Estimated 5 min", norwegian: "Estimert 5 min"))
        XCTAssertEqual(planned.durationMinutes, 45)
    }

    func testUnboundedRunningRecoveryDoesNotFallBackToLegacyDuration() {
        var planned = workout()
        let now = Date()
        planned.runningWorkout = RunningWorkoutTemplate(
            id: UUID(), title: "Open recovery", type: .intervals, summary: "",
            blocks: [RunningWorkoutBlock(kind: .work, title: "Effort", repetitions: 2,
                                         work: .time(45), recovery: .open)],
            routeID: nil, isBuiltIn: false, createdAt: now, updatedAt: now)
        XCTAssertNil(ATHLTHPlannedWorkoutPresentation.structuredMinutes(for: planned))
        XCTAssertEqual(ATHLTHPlannedWorkoutPresentation.duration(for: planned),
                       ATHLTHLocalization.choose(english: "Open duration", norwegian: "Åpen varighet"))
    }

    private func workout() -> PlannedSession {
        PlannedSession(
            id: UUID(), title: "Intervals", kind: .running,
            scheduledStart: nil, durationMinutes: 45,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil, exercises: [], notes: nil)
    }

    private func block(_ kind: WorkoutTemplateBlockKind,
                       seconds: Double?) -> WorkoutTemplateBlock {
        WorkoutTemplateBlock(
            sequence: 1, kind: kind, title: "Step",
            exerciseSlug: nil, distanceMeters: nil, repetitions: nil,
            durationSeconds: seconds, targetWeightKilograms: nil,
            loadNote: nil, notes: nil)
    }

    func testLegacyWorkoutKeepsItsPlannedDuration() {
        XCTAssertEqual(ATHLTHPlannedWorkoutPresentation.duration(for: workout()),
                       ATHLTHLocalization.choose(
                        english: "Planned 45 min", norwegian: "Planlagt 45 min"))
    }

    func testDistanceOnlyTimelineDoesNotReuseStaleDuration() {
        var planned = workout()
        var run = block(.run, seconds: nil)
        run.distanceMeters = 5_000
        planned.workoutBlocks = [run]
        XCTAssertEqual(ATHLTHPlannedWorkoutPresentation.duration(for: planned),
                       ATHLTHLocalization.choose(
                        english: "Open duration", norwegian: "Åpen varighet"))
        XCTAssertEqual(planned.durationMinutes, 45)
    }

    func testGroupedIntervalsUseExpandedEstimateWithoutMutatingPrescription() {
        var planned = workout()
        let groupID = UUID()
        var effort = block(.run, seconds: 240)
        var rest = block(.rest, seconds: 120)
        effort.groupID = groupID
        effort.groupKind = .intervals
        effort.groupRounds = 4
        rest.groupID = groupID
        rest.groupKind = .intervals
        rest.groupRounds = 4
        planned.workoutBlocks = [effort, rest]
        let original = planned
        XCTAssertEqual(ATHLTHPlannedWorkoutPresentation.duration(for: planned),
                       ATHLTHLocalization.choose(
                        english: "Estimated 25 min", norwegian: "Estimert 25 min"))
        XCTAssertEqual(planned, original)
    }
}
