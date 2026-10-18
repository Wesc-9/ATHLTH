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
        sourceIdentifier: String? = nil, shareable: Bool = false
    ) -> ExerciseLibraryEntry {
        let exercise = Exercise(
            id: id, origin: source == .custom ? .custom : .publicCatalog,
            ownerID: source == .custom ? UUID() : nil,
            name: name,
            instructions: ["Keep a controlled movement."],
            primaryMuscles: ["Back"],
            secondaryMuscles: ["Biceps"], equipment: ["Cable"],
            imageURL: nil,
            isVisibleOutsideOwnerLibrary: shareable
        )
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
            shareable: true
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
        XCTAssertEqual(entries.count, 15)
        XCTAssertTrue(entries.flatMap(\.blocks).contains {
            $0.title == "Lat Pulldown" &&
            $0.exerciseSlug == "athlth-native-lat-pulldown"
        })
        XCTAssertTrue(entries.flatMap(\.blocks).contains {
            $0.title == "Seated Cable Row" &&
            $0.exerciseSlug == "athlth-native-seated-cable-row"
        })
    }
}
