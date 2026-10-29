import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHPlannedWorkoutTypePickerTests: XCTestCase {
    private func suite() throws -> UserDefaults {
        try XCTUnwrap(UserDefaults(
            suiteName: "ATHLTH.planned.categories.\(UUID().uuidString)"
        ))
    }

    func testFirstOpenUsesPhotoReferenceOrder() throws {
        let defaults = try suite()
        let user = UUID()
        XCTAssertEqual(
            ATHLTHPlannedWorkoutTypeUsageStore.ordered(
                userID: user, defaults: defaults
            ),
            [.strength, .running, .walking, .cycling, .mobility, .custom]
        )
    }

    func testUsageChangesOrderOnlyAfterAWorkoutWasChosen() throws {
        let defaults = try suite()
        let user = UUID()
        XCTAssertEqual(
            ATHLTHPlannedWorkoutTypeUsageStore.load(
                userID: user, defaults: defaults
            ), [:]
        )
        ATHLTHPlannedWorkoutTypeUsageStore.record(
            .running, userID: user,
            at: Date(timeIntervalSince1970: 100),
            defaults: defaults
        )
        XCTAssertEqual(
            ATHLTHPlannedWorkoutTypeUsageStore.ordered(
                userID: user, defaults: defaults
            ).first, .running
        )
        ATHLTHPlannedWorkoutTypeUsageStore.record(
            .strength, userID: user,
            at: Date(timeIntervalSince1970: 200),
            defaults: defaults
        )
        XCTAssertEqual(
            Array(ATHLTHPlannedWorkoutTypeUsageStore.ordered(
                userID: user, defaults: defaults
            ).prefix(2)),
            [.strength, .running]
        )
        ATHLTHPlannedWorkoutTypeUsageStore.record(
            .running, userID: user,
            at: Date(timeIntervalSince1970: 300),
            defaults: defaults
        )
        XCTAssertEqual(
            ATHLTHPlannedWorkoutTypeUsageStore.ordered(
                userID: user, defaults: defaults
            ).first, .running
        )
        XCTAssertEqual(
            ATHLTHPlannedWorkoutTypeUsageStore.load(
                userID: user, defaults: defaults
            )["running"]?.count, 2
        )
    }

    func testPreferencesAreIsolatedPerAccount() throws {
        let defaults = try suite()
        let firstAccount = UUID()
        let secondAccount = UUID()
        ATHLTHPlannedWorkoutTypeUsageStore.record(
            .walking, userID: firstAccount, defaults: defaults
        )
        XCTAssertEqual(
            ATHLTHPlannedWorkoutTypeUsageStore.ordered(
                userID: secondAccount, defaults: defaults
            ), ATHLTHPlannedWorkoutType.defaultOrder
        )
    }

    func testCyclingAndCustomActivitiesUseDistinctCatalogCategories() {
        let cycling = WorkoutTemplateCatalogEntry(
            id: UUID(), slug: "cycling", title: "Bike",
            summary: "", category: "cycling", difficulty: "Beginner",
            estimatedDurationMinutes: 30, tags: [],
            sourceLabel: nil, sourceURL: nil, blocks: [], sortOrder: 1
        )
        let hybrid = WorkoutTemplateCatalogEntry(
            id: UUID(), slug: "hybrid", title: "Mix",
            summary: "", category: "hybrid", difficulty: "Beginner",
            estimatedDurationMinutes: 30, tags: [],
            sourceLabel: nil, sourceURL: nil, blocks: [], sortOrder: 2
        )
        XCTAssertTrue(ATHLTHPlannedWorkoutType.cycling.matches(cycling))
        XCTAssertFalse(ATHLTHPlannedWorkoutType.custom.matches(cycling))
        XCTAssertTrue(ATHLTHPlannedWorkoutType.custom.matches(hybrid))
        XCTAssertFalse(ATHLTHPlannedWorkoutType.running.matches(hybrid))
    }

    func testSavedCustomCategoryNeverStealsCycling() {
        var cycling = PlannedSession(
            id: UUID(), title: "Road ride", kind: .custom,
            scheduledStart: nil, durationMinutes: 45,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil, exercises: [], notes: nil
        )
        cycling.workoutCategory = "cycling"

        XCTAssertTrue(ATHLTHPlannedWorkoutType.cycling.matches(cycling))
        XCTAssertFalse(ATHLTHPlannedWorkoutType.custom.matches(cycling))
        XCTAssertEqual(ATHLTHPlannedWorkoutType.from(cycling), .cycling)
    }
}
