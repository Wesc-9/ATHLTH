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
        // The public barbell Bench Press should resolve to its licensed RepDB
        // entry, but other distinct native bench-press variants can legitimately
        // appear in a broad Norwegian search such as "benkpress".
        XCTAssertFalse(benchPress.contains {
            $0.sourceIdentifier == "athlth-native-bench-press"
        })
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
    func testOriginalArtworkRequiresCompleteExactIDPair() {
        let start = URL(fileURLWithPath: "/fixture/bench-press-start.webp")
        let peak = URL(fileURLWithPath: "/fixture/bench-press-peak.webp")
        let complete = ["bench-press-start.webp": start, "bench-press-peak.webp": peak]
        let pair = ExerciseLibraryStore.originalArtworkPair(for: "bench-press", in: complete)
        XCTAssertEqual(pair?.start, start)
        XCTAssertEqual(pair?.peak, peak)
        XCTAssertNil(ExerciseLibraryStore.originalArtworkPair(for: "bench-press", in: ["bench-press-start.webp": start]))
        XCTAssertNil(ExerciseLibraryStore.originalArtworkPair(for: "incline-bench-press", in: complete))
        XCTAssertNil(ExerciseLibraryStore.originalArtworkPair(for: "../bench-press", in: complete))
    }

    @MainActor
    func testWeightedPlankIsDistinctLocalizedAndHasBundledArtwork() throws {
        let library = ExerciseLibraryStore()
        let slug = "athlth-native-weighted-plank"
        let entry = try XCTUnwrap(library.selectableExercises.first { $0.sourceIdentifier == slug })
        XCTAssertEqual(entry.name, "Weighted Plank")
        XCTAssertEqual(ATHLTHExerciseNameLocalization.norwegianName(for: entry.name), "Planke med vekt")
        XCTAssertEqual(entry.exercise.primaryMuscles, ["Core"])
        XCTAssertEqual(entry.exercise.equipment, ["Weight Plate"])
        XCTAssertEqual(entry.exercise.instructions.count, 4)
        XCTAssertTrue(library.search(query: "Weighted Plank").contains { $0.id == entry.id })
        XCTAssertTrue(library.search(query: "Planke med vekt").contains { $0.id == entry.id })
        let front = try XCTUnwrap(entry.imageStartURL)
        let side = try XCTUnwrap(entry.imagePeakURL)
        XCTAssertTrue(front.isFileURL && side.isFileURL)
        XCTAssertNotEqual(front, side)
        XCTAssertTrue(FileManager.default.fileExists(atPath: front.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: side.path))
        XCTAssertEqual(ExerciseLibraryStore().selectableExercises.first { $0.sourceIdentifier == slug }?.id, entry.id)
        XCTAssertNotEqual(library.selectableExercises.first { $0.sourceIdentifier == "plank" }?.id, entry.id)
    }

    @MainActor
    func testHistoricalOriginalCoreUUIDResolvesButCannotBeSelectedAgain() throws {
        let library = ExerciseLibraryStore()
        let source = try XCTUnwrap(library.athlthCatalogExercises.first {
            ExerciseLibraryStore.isRetiredOriginalCoreSlug($0.sourceIdentifier)
        })
        XCTAssertTrue(library.allExercises.contains { $0.id == source.id })
        XCTAssertFalse(library.selectableExercises.contains { $0.id == source.id })

        var historical = WorkoutTemplateBlock(
            sequence: 1, kind: .exercise, title: source.name,
            exerciseSlug: source.sourceIdentifier,
            distanceMeters: nil, repetitions: 8, durationSeconds: nil,
            targetWeightKilograms: nil, loadNote: nil, notes: nil, phase: .main
        )
        historical.exerciseID = source.id
        XCTAssertEqual(
            ATHLTHExerciseReferenceResolver.resolve(
                historical, in: library.allExercises
            )?.id,
            source.id,
            "An old workout must retain its exact exercise identity"
        )
        XCTAssertFalse(library.search(query: source.name).contains {
            $0.id == source.id
        })
    }

    @MainActor
    func testCuratedExercisesRemainSelectableButDuplicateNativeMovementsAreHidden() throws {
        let library = ExerciseLibraryStore()
        let featured = ExerciseLibraryStore.featuredNativeExerciseSlugs
        // The initial three curated IDs remain available; 2.2.2 also
        // intentionally exposes additional non-duplicate native movements
        // referenced by bundled training plans.
        let originalFeatured: Set<String> = [
            "athlth-native-tabletop-sit-up",
            "athlth-native-free-strength-training",
            "athlth-native-test-bodyweight-squat"
        ]
        XCTAssertTrue(featured.isSuperset(of: originalFeatured))
        XCTAssertTrue(featured.contains("athlth-native-cable-curl"))
        XCTAssertTrue(featured.contains("athlth-native-power-clean"))
        XCTAssertTrue(featured.isDisjoint(
            with: ExerciseLibraryStore.retiredNativeDuplicateSlugs
        ))
        XCTAssertEqual(ExerciseLibraryStore.retiredNativeDuplicateSlugs, Set([
            "athlth-native-weighted-russian-twist",
            "athlth-native-six-inch-hold",
            "athlth-native-incline-dumbbell-bench-press",
            "athlth-native-hollow-body-hold"
        ]))
        let catalog = library.allExercises
        let selectableIDs = Set(library.selectableExercises.map(\.id))
        for slug in featured.sorted() {
            let native = try XCTUnwrap(catalog.first { entry in
                entry.source == .athlthCatalog && entry.sourceIdentifier == slug
            }, "Missing native exercise: \(slug)")
            let replacement = ATHLTHExerciseReferenceResolver.reviewedReplacement(for: native, in: catalog)
            let preferred = replacement ?? native
            XCTAssertTrue(selectableIDs.contains(preferred.id), "Missing selectable exercise: \(slug)")
        }
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
    func testBundledDeadliftIsDiscoverableWithoutDuplicatingLibraryRecords() throws {
        let library = ExerciseLibraryStore()
        let original = try XCTUnwrap(library.allExercises.first {
            $0.sourceIdentifier == "athlth-native-deadlift"
        })
        let preferred = ATHLTHExerciseReferenceResolver.visibleEquivalent(
            of: original, in: library.allExercises
        )
        let visible = library.selectableExercises
        XCTAssertTrue(visible.contains { $0.id == preferred.id })
        if preferred.id != original.id {
            XCTAssertEqual(preferred.source, .repDB)
            XCTAssertFalse(visible.contains { $0.id == original.id })
        }
        XCTAssertTrue(library.search(query: "Markløft").contains {
            $0.id == preferred.id
        })
        XCTAssertTrue(library.search(query: "Rumensk markløft")
            .allSatisfy { $0.sourceIdentifier != "athlth-native-deadlift" })
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
            // Allow intentionally featured ATHLTH exercises such as Cable
            // Curl, while keeping retired duplicates out of search results.
            let isSelectableSource = entry.source != .athlthCatalog ||
                (entry.sourceIdentifier.map {
                    ExerciseLibraryStore.featuredNativeExerciseSlugs.contains($0) ||
                    ExerciseLibraryStore.referencedNativeExerciseSlugs.contains($0) ||
                    ExerciseLibraryStore.referencedFallbackExerciseSlugs.contains($0)
                } == true &&
                !ExerciseLibraryStore.isRetiredNativeDuplicate(entry))
            let isBiceps = (entry.bodyPart.map {
                ExerciseLibraryStore.canonicalMuscleFilter($0) == "Biceps"
            } ?? false) ||
            entry.exercise.primaryMuscles.contains {
                ExerciseLibraryStore.canonicalMuscleFilter($0) == "Biceps"
            }
            return isSelectableSource && isBiceps
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
