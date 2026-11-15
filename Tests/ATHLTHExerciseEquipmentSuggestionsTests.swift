import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHExerciseEquipmentSuggestionsTests: XCTestCase {
    private let catalog = [
        "Dumbbells", "Barbell", "Cable Machine", "Resistance Band",
        "Exercise Bike", "Leg Press Machine", "Rowing Machine", "Kettlebell"
    ]

    func testSuggestionsPrioritizePrefixBeforeSubstring() {
        let result = ATHLTHExerciseEquipmentSuggestions.suggestions(
            for: "leg",
            options: catalog,
            localizedTitle: { $0 }
        )
        XCTAssertEqual(result.first, "Leg Press Machine")
    }

    func testNorwegianLocalizedEquipmentIsSearchable() {
        let result = ATHLTHExerciseEquipmentSuggestions.suggestions(
            for: "manual",
            options: catalog,
            localizedTitle: { $0 == "Dumbbells" ? "Manualer" : $0 }
        )
        XCTAssertEqual(result.first, "Dumbbells")
    }

    func testTypingPartOfEquipmentNameOffersMatchingMachine() {
        let results = ATHLTHExerciseEquipmentSuggestions.suggestions(
            for: "press",
            options: catalog,
            localizedTitle: { $0 }
        )
        XCTAssertTrue(results.contains("Leg Press Machine"))
    }

    func testSmallTypoStillSuggestsExistingEquipment() {
        let results = ATHLTHExerciseEquipmentSuggestions.suggestions(
            for: "kettlbell",
            options: catalog,
            localizedTitle: { $0 }
        )
        XCTAssertEqual(results.first, "Kettlebell")
    }

    func testEmptyQueryDoesNotDumpEntireCatalog() {
        XCTAssertTrue(ATHLTHExerciseEquipmentSuggestions.suggestions(
            for: "",
            options: catalog,
            localizedTitle: { $0 }
        ).isEmpty)
        XCTAssertTrue(ATHLTHExerciseEquipmentSuggestions.suggestions(
            for: "x",
            options: catalog,
            localizedTitle: { $0 }
        ).isEmpty)
    }

    func testSuggestionsNeverExceedDisplayLimit() {
        XCTAssertLessThanOrEqual(
            ATHLTHExerciseEquipmentSuggestions.suggestions(
                for: "machine",
                options: catalog,
                localizedTitle: { $0 },
                limit: 2
            ).count,
            2
        )
    }
}
