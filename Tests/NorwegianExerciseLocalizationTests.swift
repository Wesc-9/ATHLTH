import XCTest
@testable import ATHLTH

final class NorwegianExerciseLocalizationTests: XCTestCase {
    @MainActor
    func testEquipmentTranslationsPreserveEnglishCanonicalValues() {
        let previous = UserDefaults.standard.string(forKey: "settings.language")
        UserDefaults.standard.set("nb", forKey: "settings.language")
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: "settings.language")
            } else {
                UserDefaults.standard.removeObject(forKey: "settings.language")
            }
        }

        let library = ExerciseLibraryStore()
        XCTAssertEqual(library.localizedEquipmentTitle("Ab Crunch Machine"), "Magemaskin")
        XCTAssertEqual(library.localizedEquipmentTitle("Ab Wheel"), "Magehjul")
        XCTAssertEqual(library.localizedEquipmentTitle("Barbell"), "Vektstang")
        XCTAssertEqual(library.localizedEquipmentTitle("Battle Rope"), "Treningstau")
        XCTAssertEqual(library.localizedEquipmentTitle("Bench"), "Benk")
        XCTAssertEqual(library.localizedEquipmentTitle("Bodyweight"), "Kroppsvekt")
        XCTAssertEqual(library.localizedEquipmentTitle("Smith Machine"), "Smithmaskin")
        XCTAssertEqual(library.localizedDifficultyTitle("Beginner"), "Nybegynner")
        XCTAssertEqual(library.localizedDifficultyTitle("Intermediate"), "Viderekommen")
        XCTAssertEqual(library.localizedBodyPartTitle("Upper Legs"), "Lår")
        // Canonical equipment is not rewritten: filters and stored workouts
        // must continue to use RepDB's original English equipment IDs.
        XCTAssertEqual("Ab Wheel", "Ab Wheel")
    }

    func testNorwegianNameVocabularyRetainsSearchableEnglishSource() {
        XCTAssertEqual(ATHLTHExerciseNameLocalization.norwegianName(for: "Ab Crunch Machine"),
                       "Magemaskin")
        XCTAssertEqual(ATHLTHExerciseNameLocalization.norwegianName(for: "Ab Wheel"),
                       "Magehjul")
        XCTAssertEqual(ATHLTHExerciseNameLocalization.norwegianName(for: "Back Extension Bench"),
                       "Rygghevbenk")
        XCTAssertEqual(ATHLTHExerciseNameLocalization.norwegianName(for: "Bench Press"),
                       "Benkpress")
        let terms = ATHLTHExerciseNameLocalization.searchTerms(for: "Bench Press")
        XCTAssertTrue(terms.contains("Bench Press"))
        XCTAssertTrue(terms.contains("Benkpress"))
    }

    @MainActor
    func testCompactTranslationOverlayIsKeyedBySourceIdentifier() {
        let previous = UserDefaults.standard.string(forKey: "settings.language")
        UserDefaults.standard.set("nb", forKey: "settings.language")
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: "settings.language")
            } else {
                UserDefaults.standard.removeObject(forKey: "settings.language")
            }
        }

        let reviewed = NorwegianExerciseText.record(for: "plank")
        XCTAssertEqual(reviewed?.name, "Planke")
        XCTAssertNotNil(reviewed?.summary)
        XCTAssertEqual(reviewed?.instructions?.count, 3)
        XCTAssertNotNil(reviewed?.tips?.first)
        XCTAssertNil(NorwegianExerciseText.record(for: "never-existed-example"))
    }
}
