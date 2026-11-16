import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHExerciseReferencesTests: XCTestCase {
    private func block(_ title: String) -> WorkoutTemplateBlock {
        WorkoutTemplateBlock(
            sequence: 1, kind: .exercise, title: title,
            exerciseSlug: nil, distanceMeters: nil,
            repetitions: 10, durationSeconds: nil,
            targetWeightKilograms: nil, loadNote: nil,
            notes: nil, phase: .main
        )
    }

    private func entry(
        _ name: String, id: UUID, source: ExerciseLibrarySource,
        sourceIdentifier: String? = nil, shareable: Bool = false,
        visibility: ATHLTHExerciseVisibility? = nil
    ) -> ExerciseLibraryEntry {
        var exercise = Exercise(
            id: id, origin: source == .custom ? .custom : .publicCatalog,
            ownerID: source == .custom ? UUID() : nil,
            name: name,
            instructions: ["Keep a controlled movement."],
            primaryMuscles: ["Back"],
            secondaryMuscles: ["Biceps"], equipment: ["Cable"],
            imageURL: nil,
            isVisibleOutsideOwnerLibrary: shareable
        )
        exercise.visibility = visibility
        return ExerciseLibraryEntry(
            id: id, exercise: exercise, source: source,
            sourceIdentifier: sourceIdentifier, summary: nil, tips: [],
            category: "strength", difficulty: nil, bodyPart: "Back",
            imageStartURL: nil, imagePeakURL: nil
        )
    }

    func testExistingLatPulldownAndSeatedCableRowResolveByReviewedLibraryID() {
        let first = entry(
            "Lat Pulldown", id: UUID(), source: .athlthCatalog,
            sourceIdentifier: "athlth-native-lat-pulldown"
        )
        let second = entry(
            "Seated Cable Row", id: UUID(), source: .athlthCatalog,
            sourceIdentifier: "athlth-native-seated-cable-row"
        )
        let library = [first, second]
        XCTAssertEqual(
            ATHLTHExerciseReferenceResolver.resolve(
                block("Nedtrekk"), in: library
            )?.id, first.id
        )
        XCTAssertEqual(
            ATHLTHExerciseReferenceResolver.resolve(
                block("Sittende kabelroing"), in: library
            )?.id, second.id
        )
        XCTAssertEqual(
            ATHLTHExerciseReferenceResolver.nativeSourceIdentifier(for: "Lat Pulldown"),
            "athlth-native-lat-pulldown"
        )
    }

    func testSeparatorVariantsResolveToSameEnglishExercise() {
        let sidePlank = entry(
            "Side Plank", id: UUID(), source: .athlthCatalog,
            sourceIdentifier: "athlth-native-side-plank"
        )
        XCTAssertEqual(
            ATHLTHExerciseReferenceResolver.nativeSourceIdentifier(for: "Side-Plank"),
            "athlth-native-side-plank"
        )
        XCTAssertEqual(
            ATHLTHExerciseReferenceResolver.nativeSourceIdentifier(for: "side_plank"),
            "athlth-native-side-plank"
        )
        XCTAssertEqual(
            ATHLTHExerciseReferenceResolver.resolve(block("Side-Plank"), in: [sidePlank])?.id,
            sidePlank.id
        )
    }

    func testSimilarExerciseNamesAreNotSilentlySubstituted() {
        let barbell = entry(
            "Incline Bench Press", id: UUID(), source: .athlthCatalog,
            sourceIdentifier: "athlth-native-incline-bench-press"
        )
        XCTAssertNil(ATHLTHExerciseReferenceResolver.resolve(
            block("Incline Dumbbell Press"), in: [barbell]
        ))
        XCTAssertNil(ATHLTHExerciseReferenceResolver.resolve(
            block("Cable Lateral Raise"), in: [
                entry("Dumbbell Lateral Raise", id: UUID(), source: .athlthCatalog,
                      sourceIdentifier: "athlth-native-lateral-raise")
            ]
        ))
    }

    func testSharedCustomExerciseIsPortableOnlyWithCreatorPermission() {
        let creator = UUID()
        var source = entry(
            "My Special Cable Pull", id: UUID(), source: .custom,
            shareable: true
        ).exercise
        source.ownerID = creator
        source.videoURL = URL(fileURLWithPath: "/private/clip.mov")
        source.imageURL = URL(fileURLWithPath: "/private/photo.jpg")

        var linked = block(source.name)
        linked.exerciseID = source.id
        let match = entry(
            source.name, id: source.id, source: .custom,
            shareable: true, visibility: .publicListing
        )
        let withDetails = ATHLTHExerciseReferenceResolver.portableBlock(
            linked, from: [match]
        )
        XCTAssertNotNil(withDetails.exerciseSnapshot)
        XCTAssertEqual(withDetails.exerciseSnapshot?.instructions.first,
                       "Keep a controlled movement.")
        XCTAssertNil(withDetails.exerciseSnapshot?.imageURL)
        XCTAssertNil(withDetails.exerciseSnapshot?.videoURL)
        XCTAssertEqual(withDetails.exerciseID, source.id)

        let friendOnly = entry(
            source.name, id: source.id, source: .custom,
            shareable: true, visibility: .friends
        )
        XCTAssertNil(
            ATHLTHExerciseReferenceResolver.portableBlock(
                linked, from: [friendOnly]
            ).exerciseSnapshot,
            "Friends-only exercise details must never enter a public plan"
        )

        let notShared = entry(
            source.name, id: source.id, source: .custom,
            shareable: false
        )
        XCTAssertNil(
            ATHLTHExerciseReferenceResolver.portableBlock(
                linked, from: [notShared]
            ).exerciseSnapshot
        )
    }

    func testExistingPlansRemainDecodableWithNoExerciseSnapshot() throws {
        let legacy = """
        {
          "sequence": 1,
          "kind": "exercise",
          "title": "Lat Pulldown",
          "exercise_slug": "athlth-native-lat-pulldown",
          "repetitions": 10
        }
        """
        let block = try JSONDecoder().decode(
            WorkoutTemplateBlock.self, from: Data(legacy.utf8)
        )
        XCTAssertNil(block.exerciseSnapshot)
        XCTAssertNil(block.exerciseID)
        XCTAssertEqual(block.repetitions, 10)
        XCTAssertEqual(block.exerciseSlug, "athlth-native-lat-pulldown")
    }

    @MainActor
    func testEveryCuratedStrengthWorkoutHasSafeReferencesWhenAvailable() {
        let entries = ATHLTHCuratedStrengthWorkouts.entries
        // The curated library now includes eight additional complete sessions.
        XCTAssertEqual(entries.count, 23)
        XCTAssertTrue(entries.flatMap(\.blocks).contains {
            $0.title == "Lat Pulldown" &&
            $0.exerciseSlug == "athlth-native-lat-pulldown"
        })
        XCTAssertTrue(entries.flatMap(\.blocks).contains {
            $0.title == "Seated Cable Row" &&
            $0.exerciseSlug == "athlth-native-seated-cable-row"
        })
    }
    @MainActor
    func testSharedExerciseCopiesArePrivateAndLinkedToSourceAcrossWeeks() throws {
        let recipient = UUID()
        let sourceExerciseID = UUID()
        let library = ExerciseLibraryStore()
        library.switchAccount(recipient)
        defer { library.switchAccount(nil) }

        let snapshot = ExerciseSnapshot(
            name: "Personal Row Variation",
            instructions: ["Set up handles", "Row with a stable trunk"],
            primaryMuscles: ["Back"], secondaryMuscles: ["Biceps"],
            equipment: ["Cable"], imageURL: nil
        )
        let imported = try XCTUnwrap(library.importSharedExercise(
            snapshot, ownerID: recipient, sourceExerciseID: sourceExerciseID
        ))
        XCTAssertEqual(imported.exercise.ownerID, recipient)
        XCTAssertFalse(imported.exercise.isVisibleOutsideOwnerLibrary)
        XCTAssertEqual(imported.exercise.sharedSourceExerciseID, sourceExerciseID)
        XCTAssertEqual(imported.exercise.instructions.count, 2)

        var firstWeek = block(snapshot.name)
        firstWeek.exerciseID = sourceExerciseID
        firstWeek.exerciseSnapshot = snapshot
        XCTAssertEqual(
            ATHLTHExerciseReferenceResolver.resolve(
                firstWeek, in: library.allExercises
            )?.id, imported.id
        )

        // Sharing the same original exercise again reuses the existing copy.
        let again = try XCTUnwrap(library.importSharedExercise(
            snapshot, ownerID: recipient, sourceExerciseID: sourceExerciseID
        ))
        XCTAssertEqual(again.id, imported.id)
    }

    @MainActor
    func testEveryGymCoachProgramExerciseOpensARealLibraryExercise() throws {
        let library = ExerciseLibraryStore()
        let bundled = library.allExercises
        let programs = ATHLTHGymCoachStrengthLibrary.programs
        XCTAssertEqual(programs.count, 11)

        var matchedNames = Set<String>()
        for program in programs {
            for workout in program.program.workouts {
                let steps = ATHLTHGymCoachStrengthLibrary.blocks(for: workout)
                    .filter { $0.kind == .exercise }
                XCTAssertEqual(steps.count, workout.exercises.count)
                for (step, original) in zip(steps, workout.exercises) {
                    matchedNames.insert(original.name)
                    let match = ATHLTHExerciseReferenceResolver.resolve(
                        step, in: bundled
                    )
                    XCTAssertNotNil(
                        match,
                        "Missing actual library exercise for \(original.name) in \(program.slug)"
                    )
                    XCTAssertEqual(match?.source, .athlthCatalog)
                    XCTAssertEqual(match?.sourceIdentifier, step.exerciseSlug)
                    XCTAssertEqual(step.setCount, original.targetSets)
                    XCTAssertEqual(step.repetitions, original.targetRepsMin)
                    XCTAssertEqual(step.targetRepsInReserve, original.targetRIR)
                    XCTAssertEqual(
                        step.restBetweenSetsSeconds, Double(original.restSec)
                    )
                }
            }
        }
        XCTAssertEqual(matchedNames.count, 32)
    }

    @MainActor
    func testOldGZCLPNorwegianShoulderPressResolvesUsingEnglishSourceSnapshot() throws {
        let library = ExerciseLibraryStore()
        var legacy = block("Skulderpress")
        legacy.setCount = 5
        legacy.repetitions = 3
        legacy.restBetweenSetsSeconds = 180
        legacy.targetRepsInReserve = 1
        legacy.exerciseSnapshot = ExerciseSnapshot(
            name: "Overhead Press",
            instructions: [],
            primaryMuscles: ["shoulders"],
            equipment: [], imageURL: nil
        )

        let matched = try XCTUnwrap(
            ATHLTHExerciseReferenceResolver.resolve(
                legacy, in: library.allExercises
            )
        )
        XCTAssertEqual(matched.sourceIdentifier, "athlth-native-overhead-press")
        // Linking must not rewrite any prescription from the plan.
        XCTAssertEqual(legacy.setCount, 5)
        XCTAssertEqual(legacy.repetitions, 3)
        XCTAssertEqual(legacy.restBetweenSetsSeconds, 180)
        XCTAssertEqual(legacy.targetRepsInReserve, 1)
    }

    @MainActor
    func testPrivateOrAmbiguousExercisesNeverResolveBySimilarName() {
        let library = ExerciseLibraryStore()
        var personal = block("Skulderpress")
        personal.exerciseID = UUID()
        personal.exerciseSnapshot = ExerciseSnapshot(
            name: "Overhead Press",
            instructions: ["Use my private setup"],
            primaryMuscles: ["shoulders"],
            equipment: [], imageURL: nil
        )
        XCTAssertNil(ATHLTHExerciseReferenceResolver.resolve(
            personal, in: library.allExercises
        ))
        // Without an explicit reference, "Skulderpress" does not prove
        // whether a user meant barbell, dumbbell or machine.
        XCTAssertNil(ATHLTHExerciseReferenceResolver.resolve(
            block("Skulderpress"), in: library.allExercises
        ))
    }

    @MainActor
    func testDifferentCreatorsMayShareDifferentExercisesWithIdenticalNames() throws {
        let recipient = UUID()
        let library = ExerciseLibraryStore()
        library.switchAccount(recipient)
        defer { library.switchAccount(nil) }

        let source = ExerciseSnapshot(
            name: "Cable Row", instructions: ["Personal setup"],
            primaryMuscles: ["Back"], equipment: ["Cable"], imageURL: nil
        )
        let first = try XCTUnwrap(library.importSharedExercise(
            source, ownerID: recipient, sourceExerciseID: UUID()
        ))
        let secondSourceID = UUID()
        let second = try XCTUnwrap(library.importSharedExercise(
            source, ownerID: recipient, sourceExerciseID: secondSourceID
        ))
        XCTAssertNotEqual(first.id, second.id)
        // Different source exercises keep distinct identities even when
        // their user-visible names are intentionally identical.
        XCTAssertEqual(first.canonicalName, second.canonicalName)
        XCTAssertNotEqual(
            first.exercise.sharedSourceExerciseID,
            second.exercise.sharedSourceExerciseID
        )
        var incoming = block("Cable Row")
        incoming.exerciseID = secondSourceID
        incoming.exerciseSnapshot = source
        XCTAssertEqual(
            ATHLTHExerciseReferenceResolver.resolve(
                incoming, in: library.allExercises
            )?.id, second.id
        )
    }


    func testReviewedPlanAliasesUseExistingExerciseSourceIdentifiers() {
        let expected: [(String, String)] = [
            ("Bird Dog", "bird-dog"),
            ("Fuglehund", "bird-dog"),
            ("Bodyweight Squat", "bodyweight-squat"),
            ("Reverse Lunge", "kettlebell-reverse-lunge"),
            ("Bodyweight Reverse Lunge", "bodyweight-reverse-lunge"),
            ("Incline Dumbbell Curl", "incline-db-curl"),
            ("Hip Thrust", "athlth-native-hip-thrust")
        ]
        for (name, identifier) in expected {
            XCTAssertEqual(
                ATHLTHExerciseReferenceResolver.exerciseSourceIdentifier(for: name),
                identifier, name
            )
        }
        XCTAssertNotEqual(
            ATHLTHExerciseReferenceResolver.exerciseSourceIdentifier(for: "Incline Dumbbell Curl"),
            ATHLTHExerciseReferenceResolver.exerciseSourceIdentifier(for: "Hammer Curl")
        )
        XCTAssertNotEqual(
            ATHLTHExerciseReferenceResolver.exerciseSourceIdentifier(for: "Reverse Lunge"),
            ATHLTHExerciseReferenceResolver.exerciseSourceIdentifier(for: "Bodyweight Reverse Lunge")
        )
    }

    func testReviewedRepDBPlanNamesResolveWithoutDuplicatingExercises() {
        let bird = entry("Bird-Dog", id: UUID(), source: .repDB,
                         sourceIdentifier: "bird-dog")
        let squat = entry("Bodyweight Squat", id: UUID(), source: .repDB,
                          sourceIdentifier: "bodyweight-squat")
        let kettlebellLunge = entry("Kettlebell Reverse Lunge", id: UUID(), source: .repDB,
                                   sourceIdentifier: "kettlebell-reverse-lunge")
        let bodyweightLunge = entry("Bodyweight Reverse Lunge", id: UUID(), source: .repDB,
                                   sourceIdentifier: "bodyweight-reverse-lunge")
        let inclineCurl = entry("Incline Dumbbell Curl", id: UUID(), source: .repDB,
                                sourceIdentifier: "incline-db-curl")
        let hammerCurl = entry("Hammer Curl", id: UUID(), source: .repDB,
                               sourceIdentifier: "hammer-curl")
        let nativeHipThrust = entry("Barbell Hip Thrust", id: UUID(),
                                    source: .athlthCatalog,
                                    sourceIdentifier: "athlth-native-hip-thrust")
        let library = [bird, squat, kettlebellLunge, bodyweightLunge,
                       inclineCurl, hammerCurl, nativeHipThrust]
        let expected: [(String, UUID)] = [
            ("Bird Dog", bird.id),
            ("Bodyweight Squat", squat.id),
            ("Reverse Lunge", kettlebellLunge.id),
            ("Bodyweight Reverse Lunge", bodyweightLunge.id),
            ("Incline Dumbbell Curl", inclineCurl.id),
            ("Hip Thrust", nativeHipThrust.id)
        ]
        for (name, expectedID) in expected {
            XCTAssertEqual(
                ATHLTHExerciseReferenceResolver.resolve(block(name), in: library)?.id,
                expectedID, name
            )
        }
        XCTAssertNotEqual(inclineCurl.id, hammerCurl.id)
        var explicitBodyweight = block("Reverse Lunge")
        explicitBodyweight.exerciseSlug = "bodyweight-reverse-lunge"
        XCTAssertEqual(
            ATHLTHExerciseReferenceResolver.resolve(explicitBodyweight, in: library)?.id,
            bodyweightLunge.id,
            "Explicit canonical identity must take precedence over a plan title"
        )
    }

    @MainActor
    func testEveryBundledStrengthRecipeHasCanonicalExerciseSourceIDs() {
        let workouts = ATHLTHCuratedStrengthWorkouts.entries +
            ATHLTHPremiumStrengthSessions.entries
        XCTAssertEqual(ATHLTHCuratedStrengthWorkouts.entries.count, 23)
        XCTAssertEqual(ATHLTHPremiumStrengthSessions.entries.count, 36)
        for workout in workouts {
            for move in workout.blocks where move.kind == .exercise {
                XCTAssertNotNil(move.exerciseSlug,
                                "\(workout.slug): \(move.title) needs a library identity")
            }
        }
    }

    @MainActor
    func testEquipmentFreeHomePlanOnlyUsesExistingBodyweightExercises() throws {
        let plan = try XCTUnwrap(ATHLTHCuratedTrainingPlans.entries.first {
            $0.slug == "home-bodyweight-8w"
        })
        XCTAssertTrue(plan.tags.contains("no equipment"))
        let bodyweightIDs: Set<String> = [
            "bird-dog", "bodyweight-squat", "bodyweight-reverse-lunge",
            "athlth-native-push-up", "athlth-native-glute-bridge",
            "athlth-native-dead-bug", "athlth-native-hollow-body-hold",
            "athlth-native-plank", "athlth-native-side-plank"
        ]
        for blueprint in plan.sessionBlueprints {
            let workout = ATHLTHCatalogPlanSessionFactory.session(
                entry: plan, blueprint: blueprint, week: 1
            )
            let exercises = workout.resolvedWorkoutBlocks.filter {
                $0.kind == .exercise
            }
            XCTAssertFalse(exercises.isEmpty, blueprint.rawValue)
            for exercise in exercises {
                XCTAssertTrue(
                    exercise.exerciseSlug.map(bodyweightIDs.contains) == true,
                    "\(plan.slug) / \(blueprint.rawValue): \(exercise.title) requires equipment or has no reviewed ID"
                )
            }
            XCTAssertTrue(
                workout.notes?.contains("Equipment: None required") == true ||
                workout.notes?.contains("Utstyr: Ingen") == true
            )
        }
    }


    func testPublishedHYROXStationsBindToExistingFallbackLibraryEntries() {
        let aliases: [(String, String)] = [
            ("burpee-broad-jump", "athlth:burpee-broad-jump"),
            ("farmers-carry", "athlth:farmers-carry"),
            ("hand-release-push-up", "athlth:hand-release-push-up"),
            ("rowing-erg", "athlth:rowing"),
            ("sandbag-walking-lunge", "athlth:sandbag-walking-lunge"),
            ("ski-erg", "athlth:skierg"),
            ("sled-pull", "athlth:sled-pull"),
            ("sled-push", "athlth:sled-push"),
            ("stationary-lunge", "athlth:stationary-lunge"),
            ("wall-ball", "athlth:wall-ball")
        ]
        let library = aliases.map {
            entry("Existing station", id: UUID(),
                  source: .athlthCatalog, sourceIdentifier: $0.1)
        }
        for (publishedID, canonicalID) in aliases {
            var station = block("Unrelated visible station title")
            station.exerciseSlug = publishedID
            let result = ATHLTHExerciseReferenceResolver.resolve(
                station, in: library
            )
            XCTAssertEqual(result?.sourceIdentifier, canonicalID, publishedID)
        }

        // Unknown authored slugs cannot silently become a different movement
        // merely because their names happen to match something in the library.
        var unknown = block("Existing station")
        unknown.exerciseSlug = "private-unknown-station"
        XCTAssertNil(ATHLTHExerciseReferenceResolver.resolve(unknown, in: library))
    }

}
