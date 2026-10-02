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
