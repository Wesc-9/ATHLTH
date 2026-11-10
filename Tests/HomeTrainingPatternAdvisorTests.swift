import XCTest
@testable import ATHLTH

@MainActor
final class HomeTrainingPatternAdvisorTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_793_793_600)

    private func event(
        _ activity: HomeTrainingPatternAdvisor.Activity,
        daysAgo: Int, minutes: Int = 35
    ) -> HomeTrainingPatternAdvisor.Event {
        HomeTrainingPatternAdvisor.Event(
            id: UUID(), activity: activity,
            startedAt: Calendar(identifier: .gregorian).date(
                byAdding: .day, value: -daysAgo, to: now
            )!,
            minutes: minutes
        )
    }

    private func snapshot(
        events: [HomeTrainingPatternAdvisor.Event],
        intervals: [HomeTrainingPatternAdvisor.Activity: Double] = [:],
        routines: [HomeTrainingPatternAdvisor.StrengthRoutine] = [],
        dog: String? = nil
    ) -> HomeTrainingPatternAdvisor.Snapshot {
        var patterns: [
            HomeTrainingPatternAdvisor.Activity:
            HomeTrainingPatternAdvisor.Pattern
        ] = [:]
        for activity in HomeTrainingPatternAdvisor.Activity.allCases {
            let matches = events.filter { $0.activity == activity }
                .sorted { $0.startedAt > $1.startedAt }
            guard let latest = matches.first else { continue }
            patterns[activity] = .init(
                activity: activity, count42Days: matches.count,
                sessionsPerWeek: Double(matches.count) / 6,
                daysSinceLast: Calendar(identifier: .gregorian).dateComponents(
                    [.day], from: Calendar(identifier: .gregorian).startOfDay(
                        for: latest.startedAt
                    ), to: Calendar(identifier: .gregorian).startOfDay(for: now)
                ).day,
                usualGapDays: intervals[activity],
                usualMinutes: 35
            )
        }
        return .init(
            now: now, calendar: Calendar(identifier: .gregorian),
            events: events, patterns: patterns, routines: routines,
            dogName: dog
        )
    }

    private func advice(
        _ history: HomeTrainingPatternAdvisor.Snapshot,
        readiness: HomeDailyRecommendationPolicy.Readiness = .ready,
        load: Double? = 0.9
    ) -> HomeDailyRecommendationPolicy.Advice {
        HomeDailyRecommendationPolicy.recommendation(
            readiness: readiness, hasWorkoutToday: false,
            trainingLoadRatio: load, personalizedHistory: history
        )
    }


    func testExtendedRunningGapHasShortCardCopyAndDetailedExplanation() {
        let history = snapshot(
            events: [5, 7, 9, 11, 13, 15]
                .map { event(.running, daysAgo: $0) },
            intervals: [.running: 2]
        )

        let selected = advice(history, readiness: .balanced)
        XCTAssertEqual(selected.suggestedWorkout, .easyRun(minutes: 20))
        XCTAssertEqual(
            selected.shortDescription,
            ATHLTHLocalization.choose(
                english: "5 days since your last run. Ease back in.",
                norwegian: "5 dager siden siste løpetur. Start rolig igjen."
            )
        )
        XCTAssertTrue(selected.dayDescription.contains("5"))
        XCTAssertGreaterThan(
            selected.dayDescription.count,
            selected.shortDescription.count,
            "The information sheet should keep the full rationale."
        )
        XCTAssertNotNil(
            selected.evidence,
            "Training evidence remains available in the advice model."
        )
    }

    func testRegularRunnerKeepsRunningInsteadOfGettingWalkRecommendations() {
        let history = snapshot(
            events: [1, 2, 3, 5, 7, 9, 11, 14, 17, 19, 22, 25, 28,
                     30, 32, 34, 36, 38, 40]
                .map { event(.running, daysAgo: $0) },
            intervals: [.running: 2]
        )
        let selected = advice(history)
        XCTAssertEqual(selected.suggestedWorkout, .progressiveRun(minutes: 35))
        XCTAssertEqual(selected.suggestedWorkout.kind, .running)
        XCTAssertTrue(selected.dayDescription.localizedCaseInsensitiveContains(
            ATHLTHLocalization.choose(english: "per week", norwegian: "per uke")
        ))
    }

    func testIrregularRunnerIsNotForcedToWalkOrAnAggressiveTempoRun() {
        let history = snapshot(
            events: [4, 18, 32].map { event(.running, daysAgo: $0) },
            intervals: [.running: 14]
        )
        let selected = advice(history)
        XCTAssertEqual(selected.suggestedWorkout, .easyRun(minutes: 35))
        XCTAssertEqual(selected.suggestedWorkout.kind, .running)
        XCTAssertFalse(selected.dayDescription.localizedCaseInsensitiveContains(
            ATHLTHLocalization.choose(english: "tempo workout", norwegian: "tempoøkt")
        ))
    }

    func testWalkingOnlyMaintainsWalkingAndCanOfferRegisteredDog() {
        let history = snapshot(
            events: [2, 4, 6, 9, 11, 14, 17, 21]
                .map { event(.walking, daysAgo: $0) },
            intervals: [.walking: 3],
            dog: "Rambo"
        )
        let selected = advice(history)
        XCTAssertEqual(selected.suggestedWorkout, .easyWalk(minutes: 35))
        XCTAssertTrue(selected.suggestedDetail.contains("Rambo"))
        XCTAssertEqual(selected.suggestedWorkout.kind, .walking)
        let withoutDog = advice(snapshot(
            events: history.events, intervals: [.walking: 3]
        ))
        XCTAssertFalse(withoutDog.suggestedDetail.contains("Rambo"))
    }

    func testOnlyRunningOnPoorRecoveryGetsRestNotUnfamiliarWalking() {
        let history = snapshot(
            events: [1, 3, 5, 7, 11, 15].map { event(.running, daysAgo: $0) },
            intervals: [.running: 2]
        )
        let selected = advice(history, readiness: .recover)
        XCTAssertEqual(selected.suggestedWorkout, .restDay)
        XCTAssertNil(HomeDailyRecommendationSessionFactory.make(advice: selected))
    }

    func testTwoRecentRunsCanRotateToPreviouslyTrainedChestSession() {
        let session = PlannedSession(
            id: UUID(), title: "Bryst og triceps", kind: .strength,
            scheduledStart: nil, durationMinutes: 45,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil, routeID: nil,
            exercises: [], notes: "Completed exercises"
        )
        let historical = HomeTrainingPatternAdvisor.StrengthRoutine(
            focus: "chest",
            lastPerformed: event(.strength, daysAgo: 7).startedAt,
            occurrences42Days: 4, session: session
        )
        let history = snapshot(
            events: [
                event(.running, daysAgo: 1), event(.running, daysAgo: 2),
                event(.running, daysAgo: 4), event(.running, daysAgo: 8),
                event(.strength, daysAgo: 7),
                event(.strength, daysAgo: 14),
                event(.strength, daysAgo: 21),
                event(.strength, daysAgo: 28)
            ], intervals: [.running: 3, .strength: 7],
            routines: [historical]
        )
        let selected = advice(history, readiness: .balanced)
        XCTAssertEqual(selected.suggestedWorkout, .historicalStrength)
        XCTAssertTrue(selected.dayDescription.localizedCaseInsensitiveContains(
            ATHLTHLocalization.choose(english: "chest", norwegian: "bryst")
        ))
        let duplicated = HomeDailyRecommendationSessionFactory.make(advice: selected)
        XCTAssertEqual(duplicated?.kind, .strength)
        XCTAssertEqual(duplicated?.title, "Bryst og triceps")
        XCTAssertNotEqual(duplicated?.id, session.id)
    }

    func testStrengthRecoveryPreventsSameMuscleRecommendationNextDay() {
        let session = PlannedSession(
            id: UUID(), title: "Bryst", kind: .strength,
            scheduledStart: nil, durationMinutes: 40,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil, routeID: nil,
            exercises: [], notes: nil
        )
        let history = snapshot(
            events: [1, 8, 15, 22]
                .map { event(.strength, daysAgo: $0) },
            intervals: [.strength: 7],
            routines: [.init(
                focus: "chest",
                lastPerformed: event(.strength, daysAgo: 1).startedAt,
                occurrences42Days: 4, session: session
            )]
        )
        let selected = advice(history)
        XCTAssertNotEqual(selected.suggestedWorkout, .historicalStrength)
        XCTAssertNotEqual(selected.suggestedWorkout.kind, .walking)
    }

    func testUnknownActivitiesDoNotCauseUnrelatedRunOrWalkSuggestion() {
        let history = snapshot(
            events: [1, 4, 7].map { event(.cycling, daysAgo: $0) },
            intervals: [.cycling: 3]
        )
        XCTAssertEqual(advice(history).suggestedWorkout, .restDay)
        XCTAssertNil(advice(history).suggestedWorkout.kind)
    }

    func testNoHistoryDoesNotInventAnActivityPreference() {
        let empty = snapshot(events: [])
        let selected = advice(empty)
        XCTAssertEqual(selected.suggestedWorkout, .restDay)
        XCTAssertTrue(selected.dayDescription.localizedCaseInsensitiveContains(
            ATHLTHLocalization.choose(
                english: "limited", norwegian: "lite registrert"
            )
        ))
    }

    func testPlannedWorkoutAndHighLoadAreNotOverwritten() {
        let history = snapshot(
            events: [1, 2, 5, 7].map { event(.running, daysAgo: $0) },
            intervals: [.running: 2]
        )
        let normal = HomeDailyRecommendationPolicy.recommendation(
            readiness: .ready, hasWorkoutToday: true,
            trainingLoadRatio: 0.8, plannedWorkoutTitle: "Mine intervaller",
            personalizedHistory: history
        )
        XCTAssertEqual(normal.suggestedWorkout, .planned)

        let overloaded = HomeDailyRecommendationPolicy.recommendation(
            readiness: .ready, hasWorkoutToday: true,
            trainingLoadRatio: 1.8, plannedWorkoutTitle: "Mine intervaller",
            personalizedHistory: history
        )
        XCTAssertEqual(overloaded.suggestedWorkout, .restDay)
    }
    private func completedStrength(
        id: UUID = UUID(),
        startedAt: Date,
        healthID: UUID? = nil
    ) -> StrengthWorkoutLog {
        StrengthWorkoutLog(
            id: id,
            plannedSessionID: nil,
            watchSessionID: nil,
            captureDevice: .iPhone,
            trackingMode: .simple,
            title: "Strength",
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(1_800),
            exercises: [],
            healthMetrics: LinkedHealthWorkoutMetrics(
                healthKitWorkoutUUID: healthID,
                duration: 1_800,
                activeCalories: nil,
                averageHeartRate: nil,
                maxHeartRate: nil
            )
        )
    }

    func testIndexedMergeKeepsOneStrengthWorkoutWhenHealthAlreadyImportedIt() {
        let started = now.addingTimeInterval(-3_600)
        let healthLog = completedStrength(startedAt: started)
        let appleSummary = WorkoutSummary(localStrengthWorkout: healthLog)
        let independentLog = completedStrength(
            startedAt: started.addingTimeInterval(-2_400)
        )
        let merged = HomeTrainingPatternAdvisor.snapshot(
            workouts: [appleSummary],
            strengthHistory: [healthLog, independentLog],
            phoneHistory: [],
            now: now
        )
        XCTAssertEqual(merged.events.filter { $0.activity == .strength }.count, 2)
    }

    func testIndexedMergePreservesTwoStrengthWorkoutsOutsideTimeWindow() {
        let started = now.addingTimeInterval(-3_600)
        let first = completedStrength(startedAt: started)
        let second = completedStrength(
            startedAt: started.addingTimeInterval(121)
        )
        let merged = HomeTrainingPatternAdvisor.snapshot(
            workouts: [],
            strengthHistory: [first, second],
            phoneHistory: [],
            now: now
        )
        XCTAssertEqual(merged.events.count, 2)
    }

    func testIndexedMergeDeduplicatesNearbyUnlinkedStrengthSessions() {
        let started = now.addingTimeInterval(-3_600)
        let first = completedStrength(startedAt: started)
        let second = completedStrength(
            startedAt: started.addingTimeInterval(119)
        )
        let merged = HomeTrainingPatternAdvisor.snapshot(
            workouts: [],
            strengthHistory: [first, second],
            phoneHistory: [],
            now: now
        )
        XCTAssertEqual(merged.events.count, 1)
    }

}
