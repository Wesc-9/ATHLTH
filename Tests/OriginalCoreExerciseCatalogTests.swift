import XCTest
@testable import ATHLTH

/// Regression checks for ATHLTH's 20 ORIGINAL movements, not the
/// separate third-party RepDB exercise records.
final class OriginalCoreExerciseCatalogTests: XCTestCase {
    @MainActor
    func testOriginalCoreExerciseIdentifiersAreTwentyUniqueATHLTHSlugs() {
        let slugs = ExerciseLibraryStore.originalCoreSlugs
        XCTAssertEqual(slugs.count, 20)
        XCTAssertEqual(Set(slugs).count, slugs.count)
        XCTAssertTrue(slugs.allSatisfy { $0.hasPrefix("athlth-core-") })

        let translated = slugs.compactMap {
            ExerciseLibraryStore.norwegianExerciseNames[$0]
        }
        XCTAssertEqual(translated.count, 20)
        XCTAssertTrue(translated.allSatisfy { !$0.isEmpty })

        let instructions = slugs.compactMap {
            ExerciseLibraryStore.norwegianCoreInstructions[$0]
        }
        XCTAssertEqual(instructions.count, 20)
        XCTAssertTrue(instructions.allSatisfy { $0.count >= 2 })
    }

    func testRecoveryEngineClassifiesPreviouslyUnrecognizedRepDBAnatomy() {
        let cases: [(String, String)] = [
            ("erector_spinae", "Lower Back"),
            ("lateral_deltoid", "Shoulders"),
            ("anterior_deltoid", "Shoulders"),
            ("posterior_deltoid", "Shoulders"),
            ("adductors", "Adductors"),
            ("abductors", "Glutes"),
            ("hip_flexors", "Hip Flexors"),
            ("soleus", "Calves"),
            ("gastrocnemius", "Calves"),
            ("tibialis_anterior", "Shins"),
            ("brachialis", "Arms"),
            ("brachioradialis", "Arms"),
            ("rectus_abdominis", "Core"),
            ("transverse_abdominis", "Core"),
            ("latissimus_dorsi", "Back"),
            ("quadratus_lumborum", "Lower Back"),
            ("gluteus_medius", "Glutes")
        ]
        for (raw, expected) in cases {
            XCTAssertEqual(
                MuscleRecoveryEngine.normalizedMuscleGroup(raw),
                expected,
                "Incorrect recovery group for \(raw)"
            )
        }
    }
}
