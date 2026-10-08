import XCTest
@testable import ATHLTH

final class TrainingPlanCatalogSchedulingTests: XCTestCase {
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
