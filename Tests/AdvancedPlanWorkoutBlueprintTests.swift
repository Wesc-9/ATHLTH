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

    private func makeRunBlock(_ title: String = "Run", seq: Int = 1) -> WorkoutTemplateBlock {
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
        var runBlock = makeRunBlock()
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

    func testDatedOverridesOnlyChangeSelectedWeek() throws {
        let monday = try XCTUnwrap(Calendar.current.date(
            from: DateComponents(year: 2026, month: 10, day: 19)
        ))
        let repeated = ATHLTHPlanStructuredWorkoutBlueprint(
            title: "Upper body", kind: .strength,
            durationMinutes: 45, routeID: nil,
            blocks: [exercise()]
        )
        var weeks = [makeWeek(1), makeWeek(2), makeWeek(3)]
        ATHLTHPlanStructuredWorkoutBlueprint.apply([1: repeated], to: &weeks)

        let firstWorkoutID = try XCTUnwrap(weeks[0].days[0].sessions.first?.id)
        let edited = ATHLTHPlanWeekDayEdit(
            kind: .walking,
            title: "Walk outside",
            durationMinutes: 40,
            detailedWorkout: nil
        )
        // Key 8 = Monday in the second week, leaving weeks 1 and 3 intact.
        ATHLTHPlanWeekDayEdit.apply([8: edited], to: &weeks, startDate: monday)

        XCTAssertEqual(weeks[0].days[0].sessions.first?.title, "Upper body")
        XCTAssertEqual(weeks[0].days[0].sessions.first?.id, firstWorkoutID)
        XCTAssertEqual(weeks[1].days[0].sessions.first?.title, "Walk outside")
        XCTAssertEqual(weeks[1].days[0].sessions.first?.kind, .walking)
        XCTAssertEqual(weeks[1].days[0].sessions.first?.durationMinutes, 40)
        XCTAssertEqual(weeks[2].days[0].sessions.first?.title, "Upper body")
    }

    func testWeekOverrideCanReplaceDetailedTemplateWithoutAParallelWorkout() {
        let monday = Calendar.current.date(
            from: DateComponents(year: 2026, month: 10, day: 19)
        )!
        let original = ATHLTHPlanStructuredWorkoutBlueprint(
            title: "Upper body", kind: .strength,
            durationMinutes: 45, routeID: nil, blocks: [exercise()]
        )
        var weeks = [makeWeek(1), makeWeek(2)]
        ATHLTHPlanStructuredWorkoutBlueprint.apply([1: original], to: &weeks)
        var choice = ATHLTHPlanWeekDayEdit(
            kind: .running,
            title: "Intervals",
            durationMinutes: 30,
            detailedWorkout: nil
        )
        choice.removeTemplateDetail = true
        ATHLTHPlanWeekDayEdit.apply([8: choice], to: &weeks, startDate: monday)

        XCTAssertEqual(weeks[1].days[0].sessions.count, 1)
        XCTAssertEqual(weeks[1].days[0].sessions.first?.kind, .running)
        XCTAssertTrue(weeks[1].days[0].sessions.first?.resolvedWorkoutBlocks.isEmpty ?? false)
        XCTAssertEqual(weeks[0].days[0].sessions.first?.workoutBlocks?.count, 1)
    }

    func testCopyingPlannedWorkoutPreservesOriginalOnBusyDay() throws {
        var edit = ATHLTHPlanWeekDayEdit()
        let second = ATHLTHPlanStructuredWorkoutBlueprint(
            title: "Evening intervals", kind: .running,
            durationMinutes: 35, routeID: nil,
            blocks: [makeRunBlock()]
        )
        edit.additionalDetailedWorkouts = [second]

        let existing = try XCTUnwrap(makeWeek(1).days[0].sessions.first)
        let result = edit.scheduledSessions(from: [existing])
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].id, existing.id)
        XCTAssertEqual(result[0].title, existing.title)
        XCTAssertEqual(result[1].title, "Evening intervals")
        XCTAssertNotEqual(result[0].id, result[1].id)
    }

    func testCopyingWorkoutOntoRestDayCreatesOnlyOneSession() {
        let source = ATHLTHPlanStructuredWorkoutBlueprint(
            title: "Evening intervals", kind: .running,
            durationMinutes: 35, routeID: nil, blocks: [makeRunBlock()]
        )
        let edit = ATHLTHPlanWeekDayEdit(
            kind: .running, title: source.title,
            durationMinutes: source.durationMinutes,
            detailedWorkout: source
        )
        let result = edit.scheduledSessions(from: [])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.title, source.title)
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
    func testAIProjectionPreventsDuplicateOnProtectedWeekdayBeforeValidation() {
        let first = exercise("Squat")
        let locked = ATHLTHPlanStructuredWorkoutBlueprint(
            title: "Manual leg day", kind: .strength,
            durationMinutes: 55, routeID: nil, blocks: [first]
        )
        let generated = AIProgramDraft(
            title: "Program", summary: "AI suggested",
            weeks: (1...2).map { week in
                AIProgramDraftWeek(
                    weekNumber: week,
                    title: "Week \(week)",
                    days: (1...7).map { day in
                        AIProgramDraftDay(
                            dayIndex: day, title: "Day \(day)",
                            sessions: day == 1 ? (1...2).map { _ in
                                AIProgramDraftSession(
                                    title: "Conflicting AI session", kind: "running",
                                    durationMinutes: 40,
                                    targetDistanceKilometers: nil,
                                    targetPaceSecondsPerKilometer: nil,
                                    notes: nil, exercises: []
                                )
                            } : []
                        )
                    }
                )
            }
        )
        let effective = generated.displayingLockedWorkouts([1: locked])
        XCTAssertEqual(effective.sessionCount, 2)
        XCTAssertEqual(effective.weeks[0].days[0].sessions.count, 1)
        XCTAssertEqual(effective.weeks[0].days[0].sessions.first?.title, "Manual leg day")

        let issues = ATHLTHPlanDraftValidator.issues(
            in: effective, expectedWeeks: 2,
            allowedDayIndexes: [1], maximumSessionsPerWeek: 1,
            requireFullWeeks: true
        )
        XCTAssertTrue(issues.isEmpty, "Projection must validate: \(issues)")

        var final = effective.makeTrainingPlan(
            ownerID: UUID(), startDate: Calendar.current.startOfDay(for: Date())
        )
        ATHLTHPlanStructuredWorkoutBlueprint.apply([1: locked], to: &final.weeks)
        XCTAssertEqual(final.weeks[1].days[0].sessions.count, 1)
        XCTAssertEqual(final.weeks[1].days[0].sessions[0].workoutBlocks?.first?.setCount, 3)
    }


    func testAISuggestionsRespectChosenDayTypeAndKeepMatchingExercises() {
        let squat = AIProgramDraftExercise(
            name: "Squat", sets: 3, reps: 8,
            targetRPE: nil, restSeconds: 90, notes: nil
        )
        let generated = AIProgramDraft(
            title: "AI week", summary: "",
            weeks: [AIProgramDraftWeek(
                weekNumber: 1, title: "Week 1",
                days: (1...7).map { day in
                    AIProgramDraftDay(
                        dayIndex: day, title: "Day \(day)",
                        sessions: day <= 2
                            ? [AIProgramDraftSession(
                                title: "AI suggestion",
                                kind: "strength",
                                durationMinutes: 25,
                                targetDistanceKilometers: nil,
                                targetPaceSecondsPerKilometer: nil,
                                notes: nil, exercises: [squat]
                            )]
                            : []
                    )
                }
            )]
        )
        let choices: [Int: ATHLTHPlanDayPreference] = [
            1: ATHLTHPlanDayPreference(
                title: "Easy run", kind: .running, durationMinutes: 40
            ),
            2: ATHLTHPlanDayPreference(
                title: "Upper body", kind: .strength, durationMinutes: 55
            )
        ]
        let effective = generated.honoringWeekdayChoices(choices)
        let run = effective.weeks[0].days[0].sessions[0]
        XCTAssertEqual(run.title, "Easy run")
        XCTAssertEqual(run.kind, WorkoutKind.running.rawValue)
        XCTAssertEqual(run.durationMinutes, 40)
        XCTAssertTrue(run.exercises.isEmpty, "Strength work must not be mixed into a running session")
        let strength = effective.weeks[0].days[1].sessions[0]
        XCTAssertEqual(strength.title, "Upper body")
        XCTAssertEqual(strength.durationMinutes, 55)
        XCTAssertEqual(strength.exercises.first?.name, "Squat")
    }

    func testWeekdayPreferenceNeverOverwritesAlreadyProtectedStudioWorkout() {
        let original = AIProgramDraft(
            title: "Week", summary: "",
            weeks: [AIProgramDraftWeek(
                weekNumber: 1, title: "First",
                days: [AIProgramDraftDay(
                    dayIndex: 1, title: "Monday",
                    sessions: [AIProgramDraftSession(
                        title: "My detailed interval", kind: "running",
                        durationMinutes: 45,
                        targetDistanceKilometers: nil,
                        targetPaceSecondsPerKilometer: nil,
                        notes: nil, exercises: []
                    )]
                )]
            )]
        )
        let after = original.honoringWeekdayChoices(
            [1: ATHLTHPlanDayPreference(
                title: "Old generic name", kind: .strength, durationMinutes: 60
            )],
            protectedDays: [1]
        )
        XCTAssertEqual(after, original)
    }

    func testAIPlanKeepsAdvancedModeAndSelectedSubcategoriesAfterSave() throws {
        let selected = TrainingPlanBuilderProfile(
            mode: .advanced,
            primaryFocus: .hybrid,
            goal: .improveFitness,
            sessionsPerWeek: 2,
            preferredDayIndexes: [1, 4],
            preferredWorkoutKindsByDay: [1: .running, 4: .strength],
            preferredWorkoutTitlesByDay: [1: "Bakkeintervaller", 4: "Overkropp"],
            preferredWorkoutMinutesByDay: [1: 40, 4: 65]
        )
        let draft = AIProgramDraft(
            title: "AI generated",
            summary: "Generic summary",
            weeks: [AIProgramDraftWeek(
                weekNumber: 1,
                title: "Week 1",
                days: (1...7).map {
                    AIProgramDraftDay(dayIndex: $0, title: "Day \($0)", sessions: [])
                }
            )]
        )
        let seed = AIProgramBuilderSeed(
            preferredTitle: "Hybrid",
            startDate: Date(),
            weekCount: 1,
            sessionsPerWeek: 2,
            sessionDurationMinutes: 50,
            availableDays: [1, 4],
            trainingFocus: .hybrid,
            gymAccess: "Yes",
            limitations: "",
            coachFocusNotes: "",
            selectedGoalIDs: [],
            builderProfile: selected,
            planVisibility: .privateOnly,
            planSummary: "User-approved plan"
        )
        var generated = draft.makeTrainingPlan(ownerID: UUID(), startDate: seed.startDate)
        XCTAssertNil(generated.builderProfile)
        seed.applyWizardMetadata(to: &generated)
        let restored = try JSONDecoder().decode(
            TrainingPlan.self,
            from: JSONEncoder().encode(generated)
        )
        XCTAssertEqual(restored.builderProfile?.mode, .advanced)
        XCTAssertEqual(restored.builderProfile?.preferredDayIndexes, [1, 4])
        XCTAssertEqual(restored.builderProfile?.preferredWorkoutKindsByDay?[1], .running)
        XCTAssertEqual(restored.builderProfile?.preferredWorkoutTitlesByDay?[1], "Bakkeintervaller")
        XCTAssertEqual(restored.builderProfile?.preferredWorkoutMinutesByDay?[4], 65)
        // Keep Coach's useful explanation, not just the generic wizard summary.
        XCTAssertEqual(restored.summary, "Generic summary")
        XCTAssertEqual(restored.visibility, .privateOnly)

        var noCoachSummary = draft.makeTrainingPlan(
            ownerID: UUID(), startDate: seed.startDate
        )
        noCoachSummary.summary = ""
        seed.applyWizardMetadata(to: &noCoachSummary)
        XCTAssertEqual(noCoachSummary.summary, "User-approved plan")
    }

    func testStandaloneCoachStillWorksWithoutWizardMetadata() {
        let draft = AIProgramDraft(
            title: "Standalone",
            summary: "Coach summary",
            weeks: [AIProgramDraftWeek(
                weekNumber: 1, title: "First",
                days: [AIProgramDraftDay(dayIndex: 1, title: "Mon", sessions: [])]
            )]
        )
        var plan = draft.makeTrainingPlan(ownerID: UUID(), startDate: Date())
        let seed = AIProgramBuilderSeed(
            preferredTitle: "Standalone",
            startDate: Date(), weekCount: 1,
            sessionsPerWeek: 1, sessionDurationMinutes: 30,
            availableDays: [1], trainingFocus: .generalFitness,
            gymAccess: nil, limitations: "", coachFocusNotes: "",
            selectedGoalIDs: []
        )
        let before = plan
        seed.applyWizardMetadata(to: &plan)
        XCTAssertEqual(plan, before)
    }

}
