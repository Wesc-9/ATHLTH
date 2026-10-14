import XCTest
@testable import ATHLTH

final class TrainingPlanCatalogSchedulingTests: XCTestCase {
    @MainActor
    func testSimplePlansAlternateEverySelectedActivityEvenWithOneDayPerWeek() throws {
        for days in [[3], [1, 2, 3, 4, 5, 6, 7]] {
            for minutes in [5, 60, 180] {
                let suite = "SimpleMixedPlanTests.\(UUID().uuidString)"
                let defaults = UserDefaults(suiteName: suite)!
                defer { defaults.removePersistentDomain(forName: suite) }
                let store = AppSessionStore(defaults: defaults)
                let kinds: [WorkoutKind] = [.walking, .running, .strength]
                let profile = TrainingPlanBuilderProfile(
                    mode: .basic, primaryFocus: .hybrid, goal: .improveFitness,
                    sessionsPerWeek: days.count, preferredDayIndexes: days,
                    weeklyTimeBudgetMinutes: minutes * days.count,
                    simpleWorkoutKinds: kinds,
                    preferredWorkoutKindsByDay: Dictionary(uniqueKeysWithValues: days.map { ($0, WorkoutKind.walking) })
                )
                let start = Calendar.current.date(from: DateComponents(year: 2030, month: 1, day: 8))!
                let plan = try XCTUnwrap(store.createConfiguredTrainingPlan(
                    title: "Simple mixed plan", summary: "", weekCount: 8,
                    startDate: start, builderProfile: profile, seedSuggestedWeek: true
                ))
                let workouts = plan.weeks.flatMap(\.days).flatMap(\.sessions)
                XCTAssertEqual(workouts.count, days.count * 8)
                XCTAssertEqual(Set(workouts.map(\.kind)), Set(kinds))
                for (index, workout) in workouts.enumerated() {
                    XCTAssertEqual(workout.kind, kinds[index % kinds.count])
                    XCTAssertEqual(workout.durationMinutes, minutes)
                }
                let restored = try JSONDecoder().decode(
                    TrainingPlanBuilderProfile.self,
                    from: JSONEncoder().encode(profile)
                )
                XCTAssertEqual(restored.simpleWorkoutKinds, kinds)
            }
        }
    }

    @MainActor
    func testExistingSimplePlanKeepsItsPerDayActivityWithoutNewSelectionField() throws {
        let suite = "SimpleLegacyPlanTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppSessionStore(defaults: defaults)
        let profile = TrainingPlanBuilderProfile(
            mode: .basic, primaryFocus: .generalFitness, goal: .improveFitness,
            sessionsPerWeek: 1, preferredDayIndexes: [3], weeklyTimeBudgetMinutes: 60,
            preferredWorkoutKindsByDay: [3: .walking]
        )
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(profile)) as? [String: Any])
        json.removeValue(forKey: "simpleWorkoutKinds")
        let restored = try JSONDecoder().decode(TrainingPlanBuilderProfile.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(restored.simpleWorkoutKinds)
        let start = Calendar.current.date(from: DateComponents(year: 2030, month: 1, day: 8))!
        let plan = try XCTUnwrap(store.createConfiguredTrainingPlan(
            title: "Existing simple plan", summary: "", weekCount: 8,
            startDate: start, builderProfile: restored, seedSuggestedWeek: true
        ))
        XCTAssertTrue(plan.weeks.flatMap(\.days).flatMap(\.sessions).allSatisfy { $0.kind == .walking && $0.durationMinutes == 60 })
    }

    @MainActor
    func testShortOneAndTwoWeekProgramsUseActualSelectedDuration() {
        for weeks in [1, 2] {
            let suite = "TrainingPlanShortDurationTests.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }

            let store = AppSessionStore(defaults: defaults)
            let profile = TrainingPlanBuilderProfile(
                mode: .basic,
                primaryFocus: .generalFitness,
                secondaryFocus: nil,
                primaryFocusWeightPercent: nil,
                goal: .improveFitness,
                goalDetail: nil,
                competitionDate: nil,
                sessionsPerWeek: 3,
                preferredDayIndexes: [1, 3, 5],
                injuriesOrLimitations: nil,
                priorityMuscles: [],
                equipmentContext: "gym",
                weeklyTimeBudgetMinutes: 180,
                preferredWorkoutKindsByDay: [:]
            )

            let start = Calendar.current.date(
                from: DateComponents(year: 2030, month: 1, day: 8)
            )!
            let result = store.createConfiguredTrainingPlan(
                title: "Short program",
                summary: "",
                weekCount: weeks,
                startDate: start,
                builderProfile: profile,
                seedSuggestedWeek: false
            )

            XCTAssertEqual(result?.weeks.count, weeks)
            XCTAssertEqual(
                result?.endDate,
                Calendar.current.date(
                    byAdding: .day,
                    value: weeks * 7 - 1,
                    to: start
                )
            )
        }
    }

    @MainActor
    func testSchedulingSameCatalogPlanTwiceReturnsExistingPlan() {
        let suiteName =
            "TrainingPlanCatalogSchedulingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(
            suiteName: suiteName
        )!
        defer {
            defaults.removePersistentDomain(
                forName: suiteName
            )
        }

        let owner = UUID()
        let store = AppSessionStore(
            profile: UserProfile(
                id: UUID(),
                userID: owner,
                username: "runner",
                displayName: "Runner",
                bio: "",
                avatarURL: nil,
                presence: TrainingPresence(
                    state: .available,
                    workoutTitle: nil,
                    startedAt: nil,
                    visibility: .friends
                )
            ),
            defaults: defaults
        )

        let entry = TrainingPlanCatalogEntry(
            id: UUID(),
            slug: "test-hybrid-plan",
            title: "Test Hybrid Plan",
            summary: "Test plan",
            category: "hybrid",
            goal: "General fitness",
            level: "All levels",
            durationWeeks: 8,
            sessionsPerWeek: 4,
            workoutPattern: [
                "easy_run",
                "full_body_a",
                "tempo_run",
                "full_body_b"
            ],
            tags: ["hybrid"],
            sortOrder: 1,
            catalogVersion: 2
        )

        let requestedStart = Date(
            timeIntervalSince1970:
                1_800_000_000
        )

        let first =
            store.scheduleCatalogPlan(
                entry,
                startDate: requestedStart,
                preferredDayIndexes:
                    [1, 3, 5, 7]
            )
        let second =
            store.scheduleCatalogPlan(
                entry,
                startDate: requestedStart,
                preferredDayIndexes:
                    [1, 3, 5, 7]
            )

        XCTAssertNotNil(first)
        XCTAssertEqual(
            first?.id,
            second?.id
        )
        XCTAssertEqual(
            store.trainingPlans.count,
            1
        )
        XCTAssertEqual(
            store.existingScheduledCatalogPlan(
                entry,
                startDate: requestedStart
            )?.id,
            first?.id
        )
    }

    @MainActor
    func testDifferentPlanStillCannotOverlapScheduledPlan() {
        let suiteName =
            "TrainingPlanCatalogConflictTests.\(UUID().uuidString)"
        let defaults = UserDefaults(
            suiteName: suiteName
        )!
        defer {
            defaults.removePersistentDomain(
                forName: suiteName
            )
        }

        let owner = UUID()
        let store = AppSessionStore(
            profile: UserProfile(
                id: UUID(),
                userID: owner,
                username: "runner",
                displayName: "Runner",
                bio: "",
                avatarURL: nil,
                presence: TrainingPresence(
                    state: .available,
                    workoutTitle: nil,
                    startedAt: nil,
                    visibility: .friends
                )
            ),
            defaults: defaults
        )

        let firstEntry =
            makeEntry(
                slug: "first-plan",
                title: "First Plan"
            )
        let secondEntry =
            makeEntry(
                slug: "second-plan",
                title: "Second Plan"
            )
        let requestedStart = Date(
            timeIntervalSince1970:
                1_800_000_000
        )

        XCTAssertNotNil(
            store.scheduleCatalogPlan(
                firstEntry,
                startDate: requestedStart,
                preferredDayIndexes:
                    [1, 3, 5, 7]
            )
        )

        XCTAssertNil(
            store.scheduleCatalogPlan(
                secondEntry,
                startDate: requestedStart,
                preferredDayIndexes:
                    [1, 3, 5, 7]
            )
        )
        XCTAssertEqual(
            store.trainingPlans.count,
            1
        )
    }

    @MainActor
    func testMovingWorkoutUsesPlanRelativeDayWhenPlanStartsMidweek() {
        let suiteName = "TrainingPlanMoveDayTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = AppSessionStore(defaults: defaults)
        let calendar = Calendar.current
        let start = calendar.date(from: DateComponents(
            year: 2030, month: 1, day: 8
        ))! // Tuesday: plan day 1 is not calendar Monday.

        guard let plan = store.createTrainingPlan(
            title: "Midweek plan",
            summary: "",
            weekCount: 2,
            startDate: start
        ) else {
            return XCTFail("Expected plan")
        }

        let originalTime = calendar.date(
            bySettingHour: 18,
            minute: 45,
            second: 0,
            of: start
        )!
        let workout = PlannedSession(
            id: UUID(),
            title: "Strength",
            kind: .strength,
            scheduledStart: originalTime,
            durationMinutes: 50,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil,
            exercises: [],
            notes: nil,
            runningWorkout: nil
        )
        store.addSession(
            workout,
            toDay: plan.weeks[0].days[0].id,
            inPlan: plan.id
        )
        let targetDate = calendar.date(
            byAdding: .day, value: 2, to: start
        )!

        XCTAssertTrue(store.movePlanSession(
            planID: plan.id,
            sessionID: workout.id,
            to: targetDate
        ))

        guard let movedPlan = store.trainingPlan(withID: plan.id) else {
            return XCTFail("Missing updated plan")
        }
        XCTAssertTrue(movedPlan.weeks[0].days[0].sessions.isEmpty)
        XCTAssertTrue(movedPlan.weeks[0].days[1].sessions.isEmpty)
        let targetDay = movedPlan.weeks[0].days[2]
        XCTAssertEqual(targetDay.dayIndex, 3)
        let moved = targetDay.sessions.first
        XCTAssertEqual(moved?.id, workout.id)
        XCTAssertTrue(calendar.isDate(
            moved?.scheduledStart ?? .distantPast,
            inSameDayAs: targetDate
        ))
        let clock = calendar.dateComponents(
            [.hour, .minute],
            from: moved?.scheduledStart ?? .distantPast
        )
        XCTAssertEqual(clock.hour, 18)
        XCTAssertEqual(clock.minute, 45)
    }

    @MainActor
    func testMovingUnscheduledWorkoutDefaultsToSixPM() {
        let suiteName = "TrainingPlanMoveTimeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = AppSessionStore(defaults: defaults)
        let calendar = Calendar.current
        let start = calendar.date(from: DateComponents(
            year: 2030, month: 1, day: 8
        ))!
        guard let plan = store.createTrainingPlan(
            title: "Reschedule",
            summary: "",
            weekCount: 1,
            startDate: start
        ) else {
            return XCTFail("Expected plan")
        }
        let workout = PlannedSession(
            id: UUID(),
            title: "Easy run",
            kind: .running,
            scheduledStart: nil,
            durationMinutes: 40,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil,
            exercises: [],
            notes: nil,
            runningWorkout: nil
        )
        store.addSession(
            workout,
            toDay: plan.weeks[0].days[0].id,
            inPlan: plan.id
        )
        let target = calendar.date(byAdding: .day, value: 1, to: start)!
        XCTAssertTrue(store.movePlanSession(
            planID: plan.id,
            sessionID: workout.id,
            to: target
        ))
        guard let updated = store.trainingPlan(withID: plan.id),
              let moved = updated.weeks[0].days[1].sessions.first,
              let when = moved.scheduledStart else {
            return XCTFail("Expected moved session")
        }
        XCTAssertEqual(calendar.component(.hour, from: when), 18)
        XCTAssertEqual(calendar.component(.minute, from: when), 0)
    }

    @MainActor
    func testShorteningPlanCannotSilentlyDeleteScheduledWorkouts() {
        let suiteName = "TrainingPlanTruncationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = AppSessionStore(defaults: defaults)
        let start = Calendar.current.date(from: DateComponents(
            year: 2030, month: 1, day: 8
        ))!
        guard let plan = store.createTrainingPlan(
            title: "Protected history",
            summary: "",
            weekCount: 3,
            startDate: start
        ) else {
            return XCTFail("Expected plan")
        }
        let session = PlannedSession(
            id: UUID(),
            title: "Planned long run",
            kind: .running,
            scheduledStart: nil,
            durationMinutes: 60,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil,
            exercises: [],
            notes: nil,
            runningWorkout: nil
        )
        let lastDayID = plan.weeks[2].days[0].id
        store.addSession(session, toDay: lastDayID, inPlan: plan.id)

        XCTAssertFalse(store.setTrainingPlanWeekCount(
            planID: plan.id, weekCount: 2
        ))
        XCTAssertEqual(store.trainingPlan(withID: plan.id)?.weeks.count, 3)
        XCTAssertEqual(
            store.trainingPlan(withID: plan.id)?
                .weeks[2].days[0].sessions.first?.id,
            session.id
        )

        // After explicitly removing the workout, reducing the duration is
        // safe and must not affect earlier weeks.
        store.removeSession(
            session.id, fromDay: lastDayID, inPlan: plan.id
        )
        XCTAssertTrue(store.setTrainingPlanWeekCount(
            planID: plan.id, weekCount: 2
        ))
        XCTAssertEqual(store.trainingPlan(withID: plan.id)?.weeks.count, 2)
    }

    @MainActor
    func testBuildingFromCatalogMakesSeparateEditableCopy() {
        let suite = "TrainingCatalogCopyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer {
            defaults.removePersistentDomain(forName: suite)
        }

        let store = AppSessionStore(defaults: defaults)
        let entry = makeEntry(
            slug: "independent-copy",
            title: "Original training plan"
        )
        let days = [1, 3, 5, 7]
        let date = Date(timeIntervalSince1970: 1_800_000_000)

        guard let template = store.saveCatalogPlanTemplate(
            entry,
            preferredDayIndexes: days
        ) else {
            return XCTFail("Expected a private template copy")
        }

        XCTAssertNil(template.startDate)
        XCTAssertEqual(template.weeks.count, entry.durationWeeks)
        XCTAssertTrue(template.title.contains("Custom"))

        guard let ownPlan = store.usePlanTemplate(
            template.id,
            startDate: date
        ) else {
            return XCTFail("Expected editable scheduled copy")
        }

        XCTAssertNotEqual(template.id, ownPlan.id)
        XCTAssertEqual(ownPlan.weeks.count, entry.durationWeeks)
        XCTAssertTrue(store.planTemplates.contains {
            $0.id == template.id && $0.startDate == nil
        })
        XCTAssertEqual(
            store.trainingPlan(withID: ownPlan.id)?.id,
            ownPlan.id
        )

        // The same start period cannot be silently scheduled twice.
        XCTAssertNil(
            store.usePlanTemplate(template.id, startDate: date)
        )
        XCTAssertEqual(store.trainingPlans.count, 1)
    }

    private func makeEntry(
        slug: String,
        title: String
    ) -> TrainingPlanCatalogEntry {
        TrainingPlanCatalogEntry(
            id: UUID(),
            slug: slug,
            title: title,
            summary: "Test plan",
            category: "hybrid",
            goal: "General fitness",
            level: "All levels",
            durationWeeks: 8,
            sessionsPerWeek: 4,
            workoutPattern: [
                "easy_run",
                "full_body_a",
                "tempo_run",
                "full_body_b"
            ],
            tags: ["hybrid"],
            sortOrder: 1,
            catalogVersion: 2
        )
    }
}
