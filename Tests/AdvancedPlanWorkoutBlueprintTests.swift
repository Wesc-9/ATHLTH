import XCTest
@testable import ATHLTH

final class AdvancedPlanWorkoutBlueprintTests: XCTestCase {
    private func exercise(_ name: String = "Squat", seq: Int = 1) -> WorkoutTemplateBlock {
        WorkoutTemplateBlock(
            sequence: seq, kind: .exercise, title: name,
            exerciseSlug: "repdb-squat", distanceMeters: nil,
            repetitions: 8, durationSeconds: nil,
            targetWeightKilograms: 60, loadNote: nil,
            notes: nil, phase: .main,
            setCount: 3, restBetweenSetsSeconds: 90
        )
    }

    private func run(_ title: String = "Run", seq: Int = 1) -> WorkoutTemplateBlock {
        WorkoutTemplateBlock(
            sequence: seq, kind: .run, title: title,
            exerciseSlug: nil, distanceMeters: nil,
            repetitions: nil, durationSeconds: 120,
            targetWeightKilograms: nil, loadNote: nil,
            notes: nil, phase: .warmup
        )
    }

    private func makeWeek(_ number: Int) -> TrainingPlanWeek {
        let days = (1...7).map { day -> TrainingPlanDay in
            let sessions: [PlannedSession]
            if day == 1 {
                sessions = [PlannedSession(
                    id: UUID(), title: "AI suggestion", kind: .running,
                    scheduledStart: nil, durationMinutes: 40,
                    targetDistanceKilometers: nil,
                    targetPaceSecondsPerKilometer: nil,
                    routeID: nil, exercises: [], notes: nil
                )]
            } else {
                sessions = []
            }
            return TrainingPlanDay(
                id: UUID(), dayIndex: day, title: "Day \(day)",
                sessions: sessions
            )
        }
        return TrainingPlanWeek(
            id: UUID(), weekNumber: number, title: "Week \(number)", days: days
        )
    }

    func testAdvancedSessionIsPersistedAcrossEveryWeekAndReplacesAIContent() {
        var first = exercise()
        first.setCount = 4
        let blueprint = ATHLTHPlanStructuredWorkoutBlueprint(
            title: "Heavy legs", kind: .strength,
            durationMinutes: 55, routeID: nil, blocks: [first]
        )
        var weeks = [makeWeek(1), makeWeek(2), makeWeek(3)]
        let originalFirstID = weeks[0].days[0].sessions[0].id
        ATHLTHPlanStructuredWorkoutBlueprint.apply([1: blueprint], to: &weeks)

        XCTAssertEqual(weeks.count, 3)
        XCTAssertEqual(weeks[0].days[0].sessions[0].id, originalFirstID)
        for week in weeks {
            let sessions = week.days[0].sessions
            XCTAssertEqual(sessions.count, 1)
            XCTAssertEqual(sessions[0].title, "Heavy legs")
            XCTAssertEqual(sessions[0].kind, .strength)
            XCTAssertEqual(sessions[0].durationMinutes, 55)
            XCTAssertEqual(sessions[0].workoutCategory, "strength")
            XCTAssertEqual(sessions[0].workoutBlocks?.first?.setCount, 4)
            XCTAssertEqual(sessions[0].workoutBlocks?.expandedForExecution().count, 7)
            XCTAssertTrue(sessions[0].exercises.isEmpty)
            // A separate day must never be altered by a built Monday workout.
            XCTAssertTrue(week.days[1].sessions.isEmpty)
        }
    }

    func testHybridGroupsRoundTripWithoutChangingOriginalBlockMetadata() throws {
        let group = UUID()
        var runBlock = run()
        runBlock.groupID = group
        runBlock.groupKind = .intervals
        runBlock.groupRounds = 5

        var recovery = WorkoutTemplateBlock(
            sequence: 2, kind: .rest, title: "Rest",
            exerciseSlug: nil, distanceMeters: nil,
            repetitions: nil, durationSeconds: 60,
            targetWeightKilograms: nil, loadNote: nil, notes: nil,
            phase: .recovery
        )
        recovery.groupID = group
        recovery.groupKind = .intervals
        recovery.groupRounds = 5

        let blueprint = ATHLTHPlanStructuredWorkoutBlueprint(
            title: "Hill intervals", kind: .running,
            durationMinutes: 45, routeID: UUID(),
            blocks: [runBlock, recovery]
        )
        var weeks = [makeWeek(1)]
        ATHLTHPlanStructuredWorkoutBlueprint.apply([4: blueprint], to: &weeks)
        let planned = try XCTUnwrap(weeks[0].days[3].sessions.first)
        let data = try JSONEncoder().encode(planned)
        let restored = try JSONDecoder().decode(PlannedSession.self, from: data)
        XCTAssertEqual(restored.workoutBlocks?.first?.groupID, group)
        XCTAssertEqual(restored.workoutBlocks?.first?.groupRounds, 5)
        XCTAssertEqual(restored.routeID, blueprint.routeID)
        XCTAssertEqual(restored.workoutBlocks?.expandedForExecution().count, 9)
    }

    func testNoDetailsMeansOriginalBasicSessionsRemainUnmodified() {
        var weeks = [makeWeek(1)]
        let before = weeks
        ATHLTHPlanStructuredWorkoutBlueprint.apply([:], to: &weeks)
        XCTAssertEqual(before, weeks)
    }

    func testUnfinishedSupersetCannotOverwriteExistingPlan() {
        let group = UUID()
        var single = exercise()
        single.groupID = group
        single.groupKind = .superset
        single.groupRounds = 3
        let draft = ATHLTHPlanStructuredWorkoutBlueprint(
            title: "Incomplete", kind: .strength,
            durationMinutes: 35, routeID: nil, blocks: [single]
        )
        XCTAssertFalse(draft.isValid)
        var weeks = [makeWeek(1)]
        let before = weeks
        ATHLTHPlanStructuredWorkoutBlueprint.apply([1: draft], to: &weeks)
        XCTAssertEqual(weeks, before)
    }
}
