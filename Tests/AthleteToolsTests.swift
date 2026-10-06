import XCTest
@testable import ATHLTH

final class AthleteToolsTests: XCTestCase {
    func testRacePhasesUseCalendarDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let raceDate = Date(timeIntervalSince1970: 1_800_000_000)
        let race = AthleteRace(name: "10K", date: raceDate, distanceKM: 10, goal: "Finish")
        XCTAssertEqual(race.phase(at: raceDate.addingTimeInterval(-15 * 86_400), calendar: calendar), "Preparation")
        XCTAssertEqual(race.phase(at: raceDate.addingTimeInterval(-5 * 86_400), calendar: calendar), "Taper")
        XCTAssertEqual(race.phase(at: raceDate, calendar: calendar), "Race day")
        XCTAssertEqual(race.phase(at: raceDate.addingTimeInterval(3 * 86_400), calendar: calendar), "Recovery")
    }
    func testLoadRequiresThreeWeeksAndExcludesFutureSessions() {
        let now = Date()
        var samples = [8,15,22].map { AthleteLoadSample(date: now.addingTimeInterval(-Double($0) * 86_400), minutes: 100, effort: 4) }
        samples.append(AthleteLoadSample(date: now.addingTimeInterval(-86_400), minutes: 150, effort: 4))
        samples.append(AthleteLoadSample(date: now.addingTimeInterval(86_400), minutes: 1000, effort: 10))
        let assessment = AthleteLoadEngine.assess(samples, recoveryScore: 70, now: now)
        XCTAssertEqual(assessment.current, 600)
        XCTAssertEqual(assessment.baseline, 400)
        XCTAssertEqual(assessment.ratio, 1.5)
        XCTAssertTrue(assessment.shouldWarn)
        XCTAssertFalse(AthleteLoadEngine.assess(Array(samples.dropFirst()), recoveryScore: 70, now: now).hasBaseline)
    }
    func testNoHistoryDoesNotGenerateWarning() {
        let assessment = AthleteLoadEngine.assess([], recoveryScore: 20)
        XCTAssertNil(assessment.ratio)
        XCTAssertFalse(assessment.shouldWarn)
    }
    func testProgressionUsesAllWorkingSetsAndEffort() throws {
        let ready = try XCTUnwrap(AthleteStrengthProgression.suggestion(sets: [set(reps: 10, rpe: 7),set(reps: 10, rpe: 8)], targetReps: 10))
        XCTAssertEqual(ready.suggestedWeightKilograms, 52.5)
        let fatigued = try XCTUnwrap(AthleteStrengthProgression.suggestion(sets: [set(reps: 10, rpe: 7),set(reps: 7, rpe: 10)], targetReps: 10))
        XCTAssertLessThan(fatigued.suggestedWeightKilograms, 50)
        let missing = try XCTUnwrap(AthleteStrengthProgression.suggestion(sets: [set(reps: 10)], targetReps: 10))
        XCTAssertEqual(missing.suggestedWeightKilograms, 50)
    }
    func testWarmUpsDoNotPreventProgressionAndRIRCanGuideIt() throws {
        let suggestion = try XCTUnwrap(AthleteStrengthProgression.suggestion(sets: [set(reps: 3, rpe: 10, warmUp: true),set(reps: 10, rir: 3)], targetReps: 10))
        XCTAssertEqual(suggestion.suggestedWeightKilograms, 52.5)
    }
    func testRecentStrengthTrendRequiresLatestSessionToSupportIncrease() throws {
        let readyLatest =
            try XCTUnwrap(
                AthleteStrengthProgression
                    .suggestion(
                        sets: [
                            set(
                                reps: 10,
                                rpe: 7
                            )
                        ],
                        targetReps: 10
                    )
            )
        var readyOlder =
            readyLatest
        readyOlder =
            StrengthProgressionSuggestion(
                previousWeightKilograms:
                    47.5,
                previousReps: 10,
                suggestedWeightKilograms:
                    50,
                suggestedReps: 10
            )

        XCTAssertEqual(
            AthleteStrengthProgression
                .recentTrend(
                    suggestions: [
                        readyLatest,
                        readyOlder
                    ]
                ),
            .readyRepeated(
                readySessions: 2,
                totalSessions: 2
            )
        )

        let holdLatest =
            StrengthProgressionSuggestion(
                previousWeightKilograms:
                    50,
                previousReps: 10,
                suggestedWeightKilograms:
                    50,
                suggestedReps: 10
            )

        XCTAssertEqual(
            AthleteStrengthProgression
                .recentTrend(
                    suggestions: [
                        holdLatest,
                        readyOlder
                    ]
                ),
            .improving(
                totalSessions: 2
            )
        )
    }

    func testFuelScheduleIsBoundedAndEndsBeforeWorkoutEnd() {
        let plan = AthleteFuelPlan(durationMinutes: 480, intervalMinutes: 10, carbohydrateGramsPerHour: 60, fluidMLPerHour: 600)
        XCTAssertEqual(plan.reminderOffsets.count, 47)
        XCTAssertEqual(plan.reminderOffsets.last, 470)
        XCTAssertEqual(plan.gramsPerReminder, 10)
        XCTAssertEqual(plan.fluidPerReminder, 100)
        var invalid = plan; invalid.intervalMinutes = 0
        XCTAssertTrue(invalid.reminderOffsets.isEmpty)
    }
    func testMaintenanceRestartPreservesOdometer() {
        var rule = AthleteGearRule(intervalKM: 500)
        XCTAssertEqual(rule.remaining(at: 600), -100)
        rule.baselineKM = 600
        XCTAssertEqual(rule.remaining(at: 650), 450)
    }
    func testDropSetDoesNotCountLighterRepsAtHeavierLoad() throws {
        var completed = set(reps: 10, rpe: 8)
        completed.effortSegments = [StrengthSetEffortSegment(reps: 8, weightKilograms: 50), StrengthSetEffortSegment(reps: 2, weightKilograms: 40)]
        let suggestion = try XCTUnwrap(AthleteStrengthProgression.suggestion(sets: [completed], targetReps: 10))
        XCTAssertEqual(suggestion.previousReps, 8)
        XCTAssertEqual(suggestion.previousWeightKilograms, 50)
        XCTAssertEqual(suggestion.suggestedWeightKilograms, 50)
    }
    func testTimedAndResistanceLevelSetsDoNotSuggestKilograms() {
        var completed = set(reps: 10, rpe: 7)
        completed.targetKind = .time
        XCTAssertNil(AthleteStrengthProgression.suggestion(sets: [completed], targetReps: 10))
        completed.targetKind = nil
        completed.loadKind = .resistanceLevel
        XCTAssertNil(AthleteStrengthProgression.suggestion(sets: [completed], targetReps: 10))
    }
    private func set(reps: Int, rpe: Double? = nil, rir: Double? = nil, warmUp: Bool = false) -> StrengthSetLog {
        StrengthSetLog(id: UUID(), setNumber: 1, plannedReps: 10, plannedWeightKilograms: 50, completedReps: reps, completedWeightKilograms: 50,
                       rpe: rpe, completedAt: Date(), restSeconds: nil, rir: rir, isWarmUp: warmUp)
    }
}
