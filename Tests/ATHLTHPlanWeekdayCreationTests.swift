import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHPlanWeekdayCreationTests: XCTestCase {
    @MainActor
    func testThursdayStartRespectsSelectedThursdayAndMonday() throws {
        let suite = "ATHLTHPlanWeekdayCreationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppSessionStore(defaults: defaults)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = try XCTUnwrap(calendar.date(
            byAdding: .day, value: -1, to: today
        ))
        // Foundation Sunday = 1, Thursday = 5.
        let thursday = try XCTUnwrap(calendar.nextDate(
            after: yesterday,
            matching: DateComponents(weekday: 5),
            matchingPolicy: .nextTimePreservingSmallerComponents
        ))
        let start = calendar.startOfDay(for: thursday)
        var profile = TrainingPlanBuilderProfile(
            mode: .advanced,
            primaryFocus: .hybrid,
            goal: .improveFitness,
            sessionsPerWeek: 2,
            preferredDayIndexes: [1, 4]
        )
        profile.preferredWorkoutKindsByDay = [1: .walking, 4: .strength]
        profile.preferredWorkoutTitlesByDay = [
            1: "Monday Walk", 4: "Thursday Strength"
        ]
        profile.preferredWorkoutMinutesByDay = [1: 30, 4: 55]

        let plan = try XCTUnwrap(store.createConfiguredTrainingPlan(
            title: "Calendar weekdays", summary: "",
            weekCount: 2, startDate: start,
            builderProfile: profile, seedSuggestedWeek: true
        ))

        let first = try XCTUnwrap(plan.weeks.first)
        XCTAssertEqual(first.days.first(where: { $0.dayIndex == 1 })?
            .sessions.first?.title, "Thursday Strength")
        XCTAssertEqual(first.days.first(where: { $0.dayIndex == 1 })?
            .sessions.first?.kind, .strength)
        XCTAssertEqual(first.days.first(where: { $0.dayIndex == 5 })?
            .sessions.first?.title, "Monday Walk")
        XCTAssertEqual(first.days.first(where: { $0.dayIndex == 5 })?
            .sessions.first?.durationMinutes, 30)
        XCTAssertTrue(first.days.first(where: { $0.dayIndex == 2 })?
            .sessions.isEmpty ?? false)
        XCTAssertEqual(
            ATHLTHTrainingPlanSchedule.sessions(in: plan, on: start)
                .first?.title, "Thursday Strength"
        )
    }

    @MainActor
    func testDetailedBlocksFollowTheirSelectedCalendarWeekday() throws {
        let suite = "ATHLTHPlanWeekdayCreationTests.blocks.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppSessionStore(defaults: defaults)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = try XCTUnwrap(calendar.date(
            byAdding: .day, value: -1, to: today
        ))
        let thursday = try XCTUnwrap(calendar.nextDate(
            after: yesterday,
            matching: DateComponents(weekday: 5),
            matchingPolicy: .nextTimePreservingSmallerComponents
        ))
        let start = calendar.startOfDay(for: thursday)
        let block = WorkoutTemplateBlock(
            sequence: 1, kind: .exercise,
            title: "Squat", exerciseSlug: nil,
            distanceMeters: nil, repetitions: 10,
            durationSeconds: nil, targetWeightKilograms: 40,
            loadNote: nil, notes: nil
        )
        let detailed = ATHLTHPlanStructuredWorkoutBlueprint(
            title: "Knebøy", kind: .strength, durationMinutes: 20,
            routeID: nil, blocks: [block]
        )
        let profile = TrainingPlanBuilderProfile(
            mode: .advanced, primaryFocus: .strength,
            goal: .improveFitness, sessionsPerWeek: 1,
            preferredDayIndexes: [4]
        )
        let plan = try XCTUnwrap(store.createConfiguredTrainingPlan(
            title: "Structured Thursday", summary: "",
            weekCount: 1, startDate: start,
            builderProfile: profile, seedSuggestedWeek: false,
            structuredWorkoutsByDay: [4: detailed]
        ))
        XCTAssertEqual(
            ATHLTHTrainingPlanSchedule.sessions(in: plan, on: start)
                .first?.resolvedWorkoutBlocks, [block]
        )
        XCTAssertTrue(
            plan.weeks[0].days
                .first(where: { $0.dayIndex == 4 })?.sessions.isEmpty ?? false
        )
    }
}
