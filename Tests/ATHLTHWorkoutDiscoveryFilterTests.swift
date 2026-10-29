import Foundation
import XCTest
@testable import ATHLTH

@MainActor
final class ATHLTHWorkoutDiscoveryFilterTests: XCTestCase {
    func testStrengthMusclesUseRealRecipeTags() {
        let entries = ATHLTHCuratedStrengthWorkouts.entries
        let chest = entries.first { $0.tags.contains("chest") }
        let legs = entries.first { $0.tags.contains("legs") }
        XCTAssertNotNil(chest)
        XCTAssertNotNil(legs)
        let filter = ATHLTHWorkoutDiscoveryFilter(
            muscleGroups: ["chest"], runningType: nil, duration: .any
        )
        XCTAssertTrue(chest.map(filter.matches) ?? false)
        XCTAssertFalse(legs.map(filter.matches) ?? true)
    }

    func testMuscleChoicesCombineWithOrSemantics() {
        let selected: Set<String> = ["chest", "back"]
        XCTAssertTrue(ATHLTHWorkoutDiscoveryFilter.matchesMuscles(
            tags: ["back"], blocks: [], chosen: selected
        ))
        XCTAssertTrue(ATHLTHWorkoutDiscoveryFilter.matchesMuscles(
            tags: ["chest"], blocks: [], chosen: selected
        ))
        XCTAssertFalse(ATHLTHWorkoutDiscoveryFilter.matchesMuscles(
            tags: ["quads"], blocks: [], chosen: selected
        ))
    }

    func testSavedWorkoutStillMatchesItsPublishedMuscleTags() {
        let source = try! XCTUnwrap(
            ATHLTHCuratedStrengthWorkouts.entries.first {
                $0.tags.contains("chest")
            }
        )
        let saved = source.plannedSession()
        let filter = ATHLTHWorkoutDiscoveryFilter(
            muscleGroups: ["chest"], runningType: nil, duration: .any
        )
        XCTAssertTrue(filter.matches(saved, catalogEntry: source))
        XCTAssertFalse(filter.matches(saved))
    }

    func testRunningTypeFiltersBuiltInRunningWorkouts() {
        let interval = try! XCTUnwrap(
            RunningWorkoutLibraryStore.builtInTemplates.first {
                $0.type == .intervals
            }
        )
        let easy = try! XCTUnwrap(
            RunningWorkoutLibraryStore.builtInTemplates.first {
                $0.type == .easy
            }
        )
        let filter = ATHLTHWorkoutDiscoveryFilter(
            muscleGroups: [], runningType: .intervals, duration: .any
        )
        XCTAssertTrue(filter.matches(interval))
        XCTAssertFalse(filter.matches(easy))
    }

    func testRunningDurationBandsUseActualDurationNotWorkoutName() {
        XCTAssertTrue(ATHLTHWorkoutDiscoveryFilter.Duration.short.matches(minutes: 20))
        XCTAssertFalse(ATHLTHWorkoutDiscoveryFilter.Duration.short.matches(minutes: 45))
        XCTAssertTrue(ATHLTHWorkoutDiscoveryFilter.Duration.medium.matches(minutes: 30))
        XCTAssertTrue(ATHLTHWorkoutDiscoveryFilter.Duration.medium.matches(minutes: 60))
        XCTAssertTrue(ATHLTHWorkoutDiscoveryFilter.Duration.long.matches(minutes: 61))
        XCTAssertFalse(ATHLTHWorkoutDiscoveryFilter.Duration.long.matches(minutes: nil))
        XCTAssertTrue(ATHLTHWorkoutDiscoveryFilter.Duration.any.matches(minutes: nil))
    }

    func testStrengthMetadataDoesNotGuessFromWorkoutTitle() {
        XCTAssertFalse(ATHLTHWorkoutDiscoveryFilter.matchesMuscles(
            tags: ["strength"], blocks: [], chosen: ["chest"]
        ))
    }

    func testRunningCatalogRecipeUsesTypedIntervalBlock() {
        let blocks = [
            WorkoutTemplateBlock(
                sequence: 1, kind: .run, title: "Four intervals",
                exerciseSlug: nil, distanceMeters: nil, repetitions: nil,
                durationSeconds: 240, targetWeightKilograms: nil,
                loadNote: nil, notes: nil, phase: .main,
                groupKind: .intervals
            )
        ]
        let entry = WorkoutTemplateCatalogEntry(
            id: UUID(), slug: "interval-test", title: "Intervals",
            summary: "", category: "running", difficulty: "Intermediate",
            estimatedDurationMinutes: 45, tags: [],
            sourceLabel: nil, sourceURL: nil, blocks: blocks, sortOrder: 1
        )
        let filter = ATHLTHWorkoutDiscoveryFilter(
            muscleGroups: [], runningType: .intervals, duration: .medium
        )
        XCTAssertTrue(filter.matches(entry))
        let tooShort = ATHLTHWorkoutDiscoveryFilter(
            muscleGroups: [], runningType: .intervals, duration: .short
        )
        XCTAssertFalse(tooShort.matches(entry))
    }
}
