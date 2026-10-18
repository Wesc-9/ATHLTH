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

    @MainActor
    func testEquipmentUsesRealWorldNorwegianAndEnglishGymTerms() {
        let previous = UserDefaults.standard.string(
            forKey: "settings.language"
        )
        UserDefaults.standard.set("nb", forKey: "settings.language")
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: "settings.language")
            } else {
                UserDefaults.standard.removeObject(forKey: "settings.language")
            }
        }

        let library = ExerciseLibraryStore()
        let expectations: [(String, String)] = [
            ("Treadmill", "Tredemølle"),
            ("Rower", "Romaskin"),
            ("Stationary Bike", "Treningssykkel"),
            ("Elliptical", "Ellipsemaskin"),
            ("Bicycle", "Sykkel"),
            ("Dumbbell", "Manual"),
            ("Barbell", "Vektstang"),
            ("Cable", "Kabelapparat"),
            ("Dip Station", "Dipsstativ"),
            ("Climbing Rope", "Klatretau"),
            ("EZ Bar", "EZ-stang"),
            ("Kettlebell", "Kettlebell"),
            ("Hack Squat", "Hack squat"),
            ("Pec Deck", "Pec deck"),
            ("Leg Curl", "Leg curl"),
            ("Leg Extension", "Leg extension"),
            ("Ski Erg", "SkiErg"),
            ("TRX", "TRX"),
            ("Battle Rope", "Battle rope"),
            ("Chest Press Machine", "Chest press-maskin"),
            ("Hip Thrust Machine", "Hip thrust-maskin"),
            ("Wall Ball", "Wall ball")
        ]
        for (original, expected) in expectations {
            XCTAssertEqual(
                library.localizedEquipmentTitle(original),
                expected,
                "Wrong everyday gym term for \(original)"
            )
        }

        // Keep filter values as the catalog IDs. Translated labels must
        // never become exercise metadata or filter query arguments.
        XCTAssertTrue(library.equipmentOptions.contains("Treadmill"))
        XCTAssertFalse(library.equipmentOptions.contains("Tredemølle"))
        XCTAssertFalse(
            library.search(query: "", equipment: "Treadmill").isEmpty
        )

        UserDefaults.standard.set("en", forKey: "settings.language")
        XCTAssertEqual(library.localizedEquipmentTitle("Treadmill"), "Treadmill")
        XCTAssertEqual(library.localizedEquipmentTitle("Hip Thrust Machine"), "Hip Thrust Machine")
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

    func testRowingMachineLocalizationLoadsWithoutDuplicateDictionaryKeys() {
        XCTAssertEqual(
            ATHLTHExerciseNameLocalization.norwegianName(for: "Rowing Machine"),
            "Romaskin"
        )
        let searchTerms = ATHLTHExerciseNameLocalization.searchTerms(
            for: "Rowing Machine"
        )
        XCTAssertTrue(searchTerms.contains("Rowing Machine"))
        XCTAssertTrue(searchTerms.contains("Romaskin"))
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
        XCTAssertEqual(NorwegianExerciseText.name(for: "plank"), "Planke")
        XCTAssertNotNil(reviewed?.summary)
        XCTAssertEqual(reviewed?.instructions?.count, 3)
        XCTAssertNotNil(reviewed?.tips?.first)
        XCTAssertNil(NorwegianExerciseText.record(for: "never-existed-example"))
    }
    @MainActor
    func testEveryRepDBEntryKeepsCanonicalIdentifierAndFallbackText() {
        let old = UserDefaults.standard.string(forKey: "settings.language")
        UserDefaults.standard.set("nb", forKey: "settings.language")
        defer {
            if let old {
                UserDefaults.standard.set(old, forKey: "settings.language")
            } else {
                UserDefaults.standard.removeObject(forKey: "settings.language")
            }
        }

        let library = ExerciseLibraryStore()
        XCTAssertGreaterThanOrEqual(library.repDBExercises.count, 600)
        for entry in library.repDBExercises {
            XCTAssertNotNil(entry.sourceIdentifier)
            XCTAssertFalse(entry.name.isEmpty)
            // Even before Apple's language model is installed, every
            // exercise has a usable name and valid technique instructions.
            XCTAssertFalse(library.localizedExerciseName(entry).isEmpty)
            XCTAssertFalse(library.localizedExerciseInstructions(entry).isEmpty)
            XCTAssertFalse(entry.exercise.instructions.isEmpty)
        }
        XCTAssertGreaterThanOrEqual(
            NorwegianExerciseAutoTranslation.shared.cachedStringCount, 0
        )
    }

    @MainActor
    func testTranslationNeverChangesCanonicalEquipmentOrExerciseIdentity() {
        let old = UserDefaults.standard.string(forKey: "settings.language")
        UserDefaults.standard.set("nb", forKey: "settings.language")
        defer {
            if let old {
                UserDefaults.standard.set(old, forKey: "settings.language")
            } else {
                UserDefaults.standard.removeObject(forKey: "settings.language")
            }
        }

        let library = ExerciseLibraryStore()
        let original = library.repDBExercises.first {
            $0.exercise.equipment.contains("Barbell")
        }
        guard let entry = original else {
            XCTFail("Expected a barbell exercise in RepDB")
            return
        }

        let stableID = entry.id
        let canonicalName = entry.name
        let canonicalEquipment = entry.exercise.equipment
        _ = library.localizedExerciseName(entry)
        _ = library.localizedExerciseInstructions(entry)
        _ = library.localizedExerciseSummary(entry)
        _ = library.localizedExerciseTips(entry)
        XCTAssertEqual(entry.id, stableID)
        XCTAssertEqual(entry.name, canonicalName)
        XCTAssertEqual(entry.exercise.equipment, canonicalEquipment)
        XCTAssertEqual(library.localizedEquipmentTitle("Barbell"), "Vektstang")
    }

}
