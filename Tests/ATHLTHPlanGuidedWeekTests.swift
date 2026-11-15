import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHPlanGuidedWeekTests: XCTestCase {
    private func workout(_ title: String) -> ATHLTHPlanStructuredWorkoutBlueprint {
        let block = WorkoutTemplateBlock(
            sequence: 1, kind: .exercise, title: "Squat",
            exerciseSlug: nil, distanceMeters: nil, repetitions: 8,
            durationSeconds: nil, targetWeightKilograms: 40,
            loadNote: nil, notes: nil
        )
        return ATHLTHPlanStructuredWorkoutBlueprint(
            title: title, kind: .strength, durationMinutes: 45,
            routeID: nil, blocks: [block]
        )
    }

    private func makeWeeks() -> [TrainingPlanWeek] {
        (1...3).map { number in
            TrainingPlanWeek(
                id: UUID(), weekNumber: number, title: "Week \(number)",
                days: (1...7).map { day in
                    TrainingPlanDay(id: UUID(), dayIndex: day,
                                    title: "Day \(day)", sessions: [])
                }
            )
        }
    }

    func testStretchingPickerUsesOnlyFirstPartyStretchingAndSharedBlocks() {
        let guides = ATHLTHWellnessBlockFactory.stretching
        XCTAssertFalse(guides.isEmpty)
        XCTAssertTrue(guides.allSatisfy { $0.category == .stretching })
        XCTAssertFalse(guides.contains { $0.category == .zen })
        for guide in guides {
            let block = ATHLTHWellnessBlockFactory.block(for: guide, phase: .cooldown)
            XCTAssertEqual(block.kind, .note)
            XCTAssertEqual(block.wellnessKind, .stretching)
            XCTAssertEqual(block.phase, .cooldown)
            XCTAssertGreaterThan(block.durationSeconds ?? 0, 0)
            XCTAssertNil(block.repetitions)
        }
    }

    func testGuidedDayRequiresExplicitRestOrValidWorkout() {
        XCTAssertFalse(ATHLTHGuidedPlanDayPolicy.isPlanned(nil))

        var placeOnly = ATHLTHPlanWeekDayEdit()
        XCTAssertFalse(ATHLTHGuidedPlanDayPolicy.isPlanned(placeOnly))
        placeOnly.kind = .running
        placeOnly.title = "Suggested run"
        XCTAssertFalse(ATHLTHGuidedPlanDayPolicy.isPlanned(placeOnly),
                       "Metadata without a complete workout must not unlock Next.")

        var invalid = workout("Incomplete")
        invalid.blocks = []
        placeOnly.detailedWorkout = invalid
        XCTAssertFalse(ATHLTHGuidedPlanDayPolicy.isPlanned(placeOnly))

        placeOnly.detailedWorkout = workout("Full workout")
        XCTAssertTrue(ATHLTHGuidedPlanDayPolicy.isPlanned(placeOnly))
        placeOnly.detailedWorkout = nil

        placeOnly.isRestDay = true
        XCTAssertTrue(ATHLTHGuidedPlanDayPolicy.isPlanned(placeOnly))
    }

    func testGuidedDayAcceptsAdditionalValidWorkout() {
        var day = ATHLTHPlanWeekDayEdit()
        day.additionalDetailedWorkouts = [workout("Second session")]
        XCTAssertTrue(ATHLTHGuidedPlanDayPolicy.isPlanned(day))
    }

    func testCopyRetainsTwoWorkoutsRestDaysAndIndependentIDs() throws {
        let start = try XCTUnwrap(Calendar.current.date(
            from: DateComponents(year: 2026, month: 10, day: 17)
        ))
        let first = workout("Overkropp")
        var day = ATHLTHPlanWeekDayEdit(
            kind: .strength, title: "Overkropp", durationMinutes: 45,
            detailedWorkout: first
        )
        day.additionalDetailedWorkouts = [workout("Løping")]
        var rest = ATHLTHPlanWeekDayEdit()
        rest.isRestDay = true

        // 17 October is Saturday. Date-based weekday 6 maps to week dayIndex 1.
        var weeks = makeWeeks()
        ATHLTHPlanWeekDayEdit.apply(
            [6: day, 7: rest, 13: day],
            to: &weeks, startDate: start
        )
        XCTAssertEqual(weeks[0].days[0].sessions.map(\.title),
                       ["Overkropp", "Løping"])
        XCTAssertTrue(weeks[0].days[1].sessions.isEmpty)
        XCTAssertEqual(weeks[1].days[0].sessions.map(\.title),
                       ["Overkropp", "Løping"])
        XCTAssertNotEqual(weeks[0].days[0].sessions[0].id,
                          weeks[1].days[0].sessions[0].id)
        XCTAssertTrue(weeks[2].days[0].sessions.isEmpty)
    }

    func testTwoSessionsRetainIndependentClockTimes() throws {
        let start = try XCTUnwrap(Calendar.current.date(
            from: DateComponents(year: 2026, month: 10, day: 17)
        ))
        var morning = workout("Intervaller")
        morning.startMinuteOfDay = 8 * 60
        var evening = workout("Rolig jogg")
        evening.startMinuteOfDay = 19 * 60
        var edit = ATHLTHPlanWeekDayEdit(
            kind: .strength, title: morning.title,
            durationMinutes: 45, detailedWorkout: morning
        )
        edit.additionalDetailedWorkouts = [evening]
        var weeks = makeWeeks()
        ATHLTHPlanWeekDayEdit.apply([6: edit], to: &weeks, startDate: start)
        let sessions = weeks[0].days[0].sessions
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions.map(\.title), ["Intervaller", "Rolig jogg"])
        XCTAssertEqual(sessions.compactMap { $0.scheduledStart.map {
            Calendar.current.component(.hour, from: $0)
        } }, [8, 19])
    }

    func testWorkoutStartTimeSurvivesPlanDraftSerialization() throws {
        var original = workout("Morgenøkt")
        original.startMinuteOfDay = 7 * 60 + 30
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(
            ATHLTHPlanStructuredWorkoutBlueprint.self, from: data)
        XCTAssertEqual(restored.startMinuteOfDay, 450)
    }

    func testLegacyWorkoutWithoutStartTimeStillDecodes() throws {
        let legacy = workout("Uten klokkeslett")
        let data = try JSONEncoder().encode(legacy)
        let restored = try JSONDecoder().decode(
            ATHLTHPlanStructuredWorkoutBlueprint.self, from: data)
        XCTAssertNil(restored.startMinuteOfDay)
    }

    func testPreviouslyPersistedEditCanDecodeWithOptionalNewFields() throws {
        let legacy = ATHLTHPlanWeekDayEdit(
            kind: .strength, title: "Legacy", durationMinutes: 40,
            detailedWorkout: workout("Legacy")
        )
        let data = try JSONEncoder().encode(legacy)
        let result = try JSONDecoder().decode(ATHLTHPlanWeekDayEdit.self, from: data)
        XCTAssertNil(result.isRestDay)
        XCTAssertNil(result.additionalDetailedWorkouts)
        XCTAssertEqual(result.detailedWorkout?.title, "Legacy")
    }
    func testDeletingLastWorkoutKeepsDayEmptyWithoutBecomingRestDay() throws {
        // A chosen training weekday may already have a generated default.
        // Deleting its final visible workout must remove that default too.
        let start = try XCTUnwrap(Calendar.current.date(
            from: DateComponents(year: 2026, month: 10, day: 17)
        ))
        var weeks = makeWeeks()
        weeks[0].days[0].sessions = [workout("Old session").applying(to: nil)]

        var edit = ATHLTHPlanWeekDayEdit()
        edit.isRestDay = false
        edit.removeTemplateDetail = true
        edit.removeAllWorkouts = true

        XCTAssertFalse(ATHLTHGuidedPlanDayPolicy.isPlanned(edit))
        ATHLTHPlanWeekDayEdit.apply([6: edit], to: &weeks, startDate: start)
        XCTAssertTrue(weeks[0].days[0].sessions.isEmpty)
        XCTAssertNil(edit.detailedWorkout)

        // Persisted checkpoints must never resurrect deleted sessions.
        let data = try JSONEncoder().encode(edit)
        let resumed = try JSONDecoder().decode(
            ATHLTHPlanWeekDayEdit.self, from: data
        )
        XCTAssertEqual(resumed.removeAllWorkouts, true)
        XCTAssertEqual(resumed.isRestDay, false)
    }

    func testQuickRestStepCanBeSavedAsSeparateShortWorkout() {
        let pause = WorkoutTemplateBlock(
            sequence: 1, kind: .rest, title: "Pause",
            exerciseSlug: nil, distanceMeters: nil, repetitions: nil,
            durationSeconds: 90, targetWeightKilograms: nil,
            loadNote: nil, notes: nil, phase: .main
        )
        let session = ATHLTHPlanStructuredWorkoutBlueprint(
            title: "Pause", kind: .recovery, durationMinutes: 5,
            routeID: nil, blocks: [pause]
        )
        XCTAssertTrue(session.isValid)
    }


    func testSecondWorkoutAndExactGuidedEditingPositionSurviveRelaunch() throws {
        var day = ATHLTHPlanWeekDayEdit(
            kind: .strength, title: "Morgen", durationMinutes: 45,
            detailedWorkout: workout("Morgen")
        )
        day.additionalDetailedWorkouts = [workout("Kveld")]
        let initial = ATHLTHPlanCreationDraft(
            title: "Ukeprogram", weekCount: 3,
            startDate: Date(timeIntervalSince1970: 1_800_000_000),
            advanced: true, source: "scratch", stage: "week",
            weekDayEdits: [8: day], planningApproach: "guided",
            guidedDayCursor: 7, selectedPlanWeekIndex: 1,
            editorDay: 1, editorKind: "studio", editorWorkoutIndex: 1
        )
        let restored = try JSONDecoder().decode(
            ATHLTHPlanCreationDraft.self,
            from: JSONEncoder().encode(initial)
        )
        XCTAssertEqual(restored.stage, "week")
        XCTAssertEqual(restored.guidedDayCursor, 7)
        XCTAssertEqual(restored.selectedPlanWeekIndex, 1)
        XCTAssertEqual(restored.editorDay, 1)
        XCTAssertEqual(restored.editorKind, "studio")
        XCTAssertEqual(restored.editorWorkoutIndex, 1)
        XCTAssertEqual(restored.weekDayEdits?[8]?.detailedWorkout?.title, "Morgen")
        XCTAssertEqual(restored.weekDayEdits?[8]?.additionalDetailedWorkouts?.map(\.title), ["Kveld"])
    }


}
