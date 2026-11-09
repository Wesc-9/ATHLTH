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

        // Historical native IDs remain resolvable, but the restored RepDB
        // catalog is now the source for new selections. Its display names
        // need not be identical to the retired native exercises.
        XCTAssertTrue(exercises.contains { $0.name == "Bench Press" })
        XCTAssertGreaterThanOrEqual(library.repDBExercises.count, 400)
        let benchPress = library.search(query: "benkpress")
        XCTAssertFalse(benchPress.isEmpty)
        XCTAssertTrue(benchPress.contains { $0.source == .repDB })
        XCTAssertFalse(benchPress.contains { $0.source == .athlthCatalog })
        XCTAssertTrue(library.search(query: "knebøy").contains {
            $0.source == .repDB
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

    @MainActor
    func testCuratedExercisesRemainSelectableButDuplicateNativeMovementsAreHidden() {
        let library = ExerciseLibraryStore()
        let featured = ExerciseLibraryStore.featuredNativeExerciseSlugs
        XCTAssertEqual(featured, Set([
            "athlth-native-tabletop-sit-up",
            "athlth-native-free-strength-training"
        ]))
        XCTAssertEqual(ExerciseLibraryStore.retiredNativeDuplicateSlugs, Set([
            "athlth-native-weighted-russian-twist",
            "athlth-native-six-inch-hold",
            "athlth-native-incline-dumbbell-bench-press",
            "athlth-native-hollow-body-hold"
        ]))
        XCTAssertTrue(featured.allSatisfy { slug in
            library.selectableExercises.contains {
                $0.source == .athlthCatalog && $0.sourceIdentifier == slug
            }
        })
        for phrase in [
            "Skråbenk med manualer",
            "Situps med beina i 90 grader",
            "Fri styrketrening"
        ] {
            XCTAssertFalse(library.search(query: phrase).isEmpty,
                           "Curated exercise missing from selectable search: \(phrase)")
        }
        // The incline dumbbell result must be the licensed RepDB original.
        // Do not reintroduce a duplicate native exercise merely to pass search.
        XCTAssertTrue(library.search(query: "Skråbenk med manualer").contains {
            $0.source == .repDB
        })
        XCTAssertTrue(ExerciseLibraryStore.searchableNorwegianTerms(
            sourceIdentifier: "incline-dumbbell-bench-press",
            englishName: "Incline Dumbbell Bench Press",
            bodyPart: "Chest",
            primaryMuscles: ["Chest"]
        ).contains("Skråbenk med manualer"))
        for slug in ExerciseLibraryStore.retiredNativeDuplicateSlugs {
            // Keep the old stable ID available when viewing saved history.
            XCTAssertTrue(library.athlthCatalogExercises.contains {
                $0.source == .athlthCatalog && $0.sourceIdentifier == slug
            })
            // But never offer a duplicate as a new exercise, even offline.
            XCTAssertFalse(library.selectableExercises.contains {
                $0.source == .athlthCatalog && $0.sourceIdentifier == slug
            })
        }
        // None of the licensed RepDB records may be dropped by retiring
        // duplicate ATHLTH-native entries.
        XCTAssertEqual(
            Set(library.repDBExercises.map(\.id)),
            Set(library.selectableExercises
                .filter { $0.source == .repDB }.map(\.id))
        )
        XCTAssertFalse(library.repDBExercises.isEmpty)
        // Retired policy is strictly scoped to ATHLTH-native source records.
        XCTAssertTrue(library.repDBExercises.allSatisfy {
            !ExerciseLibraryStore.isRetiredNativeDuplicate($0)
        })
        XCTAssertFalse(library.selectableExercises.contains {
            ExerciseLibraryStore.isRetiredOriginalCoreSlug($0.sourceIdentifier)
        })
    }

    @MainActor
    func testMuscleFiltersMatchSelectableRepDBExercises() {
        let library = ExerciseLibraryStore()

        XCTAssertEqual(
            ExerciseLibraryStore.canonicalMuscleFilter("biceps brachii"),
            "Biceps"
        )
        XCTAssertEqual(
            ExerciseLibraryStore.canonicalMuscleFilter("triceps brachii"),
            "Triceps"
        )
        XCTAssertEqual(
            ExerciseLibraryStore.canonicalMuscleFilter("Deltoid"),
            "Shoulders"
        )

        // All menu choices must actually return an exercise in the same
        // selectable dataset; historical hidden entries must not create
        // misleading empty categories.
        for part in library.bodyParts {
            XCTAssertFalse(
                library.search(query: "", bodyPart: part, equipment: "All").isEmpty,
                "Empty muscle filter: \(part)"
            )
        }

        XCTAssertTrue(library.bodyParts.contains("Biceps"))
        let bicepsExercises = library.search(
            query: "", bodyPart: "Biceps", equipment: "All"
        )
        XCTAssertFalse(bicepsExercises.isEmpty)
        XCTAssertTrue(bicepsExercises.allSatisfy { entry in
            entry.source != .athlthCatalog &&
                (
                    (entry.bodyPart.map {
                        ExerciseLibraryStore.canonicalMuscleFilter($0) == "Biceps"
                    } ?? false) ||
                    entry.exercise.primaryMuscles.contains {
                        ExerciseLibraryStore.canonicalMuscleFilter($0) == "Biceps"
                    }
                )
        })
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
