import SwiftUI
import XCTest
@testable import ATHLTH

final class ATHLTHTrainTodayLayoutTests: XCTestCase {
    @MainActor
    func testWorkoutSuggestionsPreferRelevantAndDifferentCategories() {
        func make(_ category: String, _ difficulty: String, _ sortOrder: Int,
                  tags: [String] = []) -> WorkoutTemplateCatalogEntry {
            let block = WorkoutTemplateBlock(
                sequence: 1, kind: .rest, title: "Recovery",
                exerciseSlug: nil, distanceMeters: nil,
                repetitions: nil, durationSeconds: 60,
                targetWeightKilograms: nil, loadNote: nil, notes: nil
            )
            return WorkoutTemplateCatalogEntry(
                id: UUID(), slug: "\(category)-\(sortOrder)",
                title: "\(category)-\(sortOrder)", summary: "",
                category: category, difficulty: difficulty,
                estimatedDurationMinutes: 30, tags: tags,
                sourceLabel: nil, sourceURL: nil,
                blocks: [block], sortOrder: sortOrder
            )
        }

        let entries = [
            make("hybrid", "Advanced", 1, tags: ["hyrox"]),
            make("running", "Beginner", 2),
            make("running", "Beginner", 3),
            make("strength", "Beginner", 4)
        ]
        let chosen = TrainWorkoutSuggestionPolicy.pick(
            entries, preferredKind: .strength
        )
        XCTAssertEqual(chosen.count, 2)
        XCTAssertEqual(chosen[0].category, "strength")
        XCTAssertEqual(chosen[1].category, "running")
        XCTAssertFalse(chosen.contains(where: { $0.tags.contains("hyrox") }))
        let withoutPlan = TrainWorkoutSuggestionPolicy.pick(
            entries, preferredKind: nil
        )
        XCTAssertEqual(Set(withoutPlan.map(\.category)).count, 2)
        XCTAssertEqual(TrainWorkoutSuggestionPolicy.pick(
            [entries[0]], preferredKind: nil
        ).count, 0)
    }

    @MainActor
    func testTodaySurfaceFitsCompactPhoneWidths() {
        let plan = TrainingPlan(
            id: UUID(),
            ownerID: UUID(),
            title: "Weekly plan",
            summary: "",
            visibility: .privateOnly,
            version: 1,
            weeks: [],
            tags: [],
            createdAt: Date(),
            updatedAt: Date()
        )

        // No plan and rest days both use photo heroes. Verify that image
        // aspect ratios cannot force a wider-than-screen SwiftUI layout.
        let scenarios: [TrainingPlan?] = [nil, plan]
        for width in [320.0, 375.0, 430.0] {
            for currentPlan in scenarios {
                for hasActiveWorkout in [false, true] {
                let today = ATHLTHTrainTodayPremiumView(
                    workoutCatalog: WorkoutTemplateCatalogStore(),
                    plan: currentPlan,
                    sessions: [],
                    completedIDs: [],
                    healthCompletedIDs: [],
                    nextWorkoutTitle: currentPlan == nil ? nil : "Strength legs",
                    nextWorkoutDate: nil,
                    completionFraction: 0,
                    planPosition: "",
                    hasActiveWorkout: hasActiveWorkout,
                    onChooseSuggestedWorkout: { _ in },
                    onOpenPlan: {},
                    onCreatePlan: {},
                    onOpenLibrary: {},
                    onStartWorkout: { _, _ in },
                    onWorkoutDetails: { _, _ in },
                    onQuickTrain: { _ in },
                    onGhostRace: {}
                )

                let host = UIHostingController(rootView: today)
                host.loadViewIfNeeded()
                let measured = host.sizeThatFits(
                    in: CGSize(width: width, height: 1_600)
                )
                XCTAssertLessThanOrEqual(
                    measured.width,
                    width + 1,
                    "Today content exceeds a \(Int(width))-point viewport"
                )
                }
            }
        }
    }
}
