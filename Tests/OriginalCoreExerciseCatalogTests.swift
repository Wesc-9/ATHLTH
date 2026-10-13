import XCTest
@testable import ATHLTH

/// Regression checks for the 20 retired ATHLTH-original core movements.
/// Existing RepDB exercises must remain available.
final class OriginalCoreExerciseCatalogTests: XCTestCase {
    @MainActor
    func testOriginalCoreExerciseIdentifiersAreTwentyUniqueATHLTHSlugs() {
        let slugs = ExerciseLibraryStore.originalCoreSlugs
        XCTAssertEqual(slugs.count, 20)
        XCTAssertEqual(Set(slugs).count, slugs.count)
        XCTAssertTrue(slugs.allSatisfy { $0.hasPrefix("athlth-core-") })

        // All 20 additions are now retired from new selections.
        XCTAssertTrue(slugs.allSatisfy {
            ExerciseLibraryStore.isRetiredOriginalCoreSlug($0)
        })
        XCTAssertFalse(
            ExerciseLibraryStore.isRetiredOriginalCoreSlug("plank")
        )
        XCTAssertFalse(
            ExerciseLibraryStore.isRetiredOriginalCoreSlug("athlth-core-unknown")
        )
        XCTAssertFalse(
            ExerciseLibraryStore.isRetiredOriginalCoreSlug(nil)
        )

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

    @MainActor
    func testNativeATHLTHCatalogIsAvailableOfflineWithStableIdentifiers() async {
        let library = ExerciseLibraryStore()
        let exercises = library.athlthCatalogExercises
        XCTAssertGreaterThanOrEqual(exercises.count, 62)
        XCTAssertEqual(Set(exercises.map(\.id)).count, exercises.count)
        XCTAssertTrue(exercises.allSatisfy { $0.source == .athlthCatalog })
        XCTAssertTrue(exercises.allSatisfy { !$0.exercise.primaryMuscles.isEmpty })

        let benchPress = library.search(query: "benkpress")
        XCTAssertTrue(benchPress.contains { $0.name == "Bench Press" })
        XCTAssertTrue(library.search(query: "knebøy").contains {
            $0.name == "Barbell Back Squat"
        })

        let beforeRefresh = exercises.map(\.id)
        await library.refresh(force: true)
        XCTAssertEqual(library.athlthCatalogExercises.map(\.id), beforeRefresh)

        let anotherLibrary = ExerciseLibraryStore()
        XCTAssertEqual(
            anotherLibrary.athlthCatalogExercises.map(\.id),
            beforeRefresh
        )
    }

    func testExerciseStudioCanImportAndDiscardLocalDemoVideo() throws {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        try Data(repeating: 0x31, count: 2_048).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }

        let imported = try ExerciseStudioVideoStorage.importVideo(from: source)
        XCTAssertTrue(ExerciseStudioVideoStorage.isOwnedVideo(imported))
        XCTAssertTrue(FileManager.default.fileExists(atPath: imported.path))
        XCTAssertNotEqual(imported, source)

        ExerciseStudioVideoStorage.discardOwnedVideo(imported)
        XCTAssertFalse(FileManager.default.fileExists(atPath: imported.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testExerciseStudioRejectsUnsupportedVideoAndDoesNotDeleteOtherFiles() throws {
        let unrelated = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("txt")
        try Data("not a movie".utf8).write(to: unrelated)
        defer { try? FileManager.default.removeItem(at: unrelated) }

        XCTAssertThrowsError(
            try ExerciseStudioVideoStorage.importVideo(from: unrelated)
        )
        ExerciseStudioVideoStorage.discardOwnedVideo(unrelated)
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
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
