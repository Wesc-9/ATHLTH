import Foundation
import XCTest
@testable import ATHLTH

@MainActor
final class ATHLTHExerciseAlphabetLibraryTests: XCTestCase {
    private func makeEntry(_ title: String) -> ExerciseLibraryEntry {
        let id = UUID()
        let exercise = Exercise(
            id: id, origin: .custom, ownerID: UUID(),
            name: title, instructions: ["Move with control."],
            primaryMuscles: ["Back"], secondaryMuscles: [],
            equipment: ["Bodyweight"], imageURL: nil,
            isVisibleOutsideOwnerLibrary: false
        )
        return ExerciseLibraryEntry(
            id: id, exercise: exercise, source: .custom,
            sourceIdentifier: nil, summary: nil, tips: [],
            category: "custom", difficulty: nil, bodyPart: "Back",
            imageStartURL: nil, imagePeakURL: nil
        )
    }

    func testNorwegianAlphabetIncludesAllTwentyNineLetters() {
        XCTAssertEqual(ATHLTHExerciseAlphabet.letters.count, 29)
        XCTAssertEqual(Array(ATHLTHExerciseAlphabet.letters.suffix(3)), ["Æ", "Ø", "Å"])
        XCTAssertEqual(ATHLTHExerciseAlphabet.letter(for: " åsen "), "Å")
        XCTAssertEqual(ATHLTHExerciseAlphabet.letter(for: "Ærlig"), "Æ")
        XCTAssertEqual(ATHLTHExerciseAlphabet.letter(for: "øvelse"), "Ø")
        XCTAssertEqual(ATHLTHExerciseAlphabet.letter(for: "planke"), "P")
    }

    func testAlphabetSortingUsesDisplayNamesAndNorwegianCollation() {
        let store = ExerciseLibraryStore()
        let entries = [
            makeEntry("Øvelse"), makeEntry("Zigzag"), makeEntry("Benkpress"),
            makeEntry("Åsen"), makeEntry("Ærlig"), makeEntry("Armheving")
        ]
        let sorted = store.alphabetized(entries)
        XCTAssertEqual(
            sorted.map(\.name),
            ["Armheving", "Benkpress", "Zigzag", "Ærlig", "Øvelse", "Åsen"]
        )
        let targets = store.alphabetIndexTargets(for: sorted)
        XCTAssertEqual(targets["A"], sorted[0].id)
        XCTAssertEqual(targets["Æ"], sorted[3].id)
        XCTAssertEqual(targets["Ø"], sorted[4].id)
        XCTAssertEqual(targets["Å"], sorted[5].id)
        XCTAssertNil(targets["C"])
    }

    func testAlphabetIndexCanJumpOutsideFirstFiftyRows() throws {
        let store = ExerciseLibraryStore()
        // Alphabet targets represent the entire filtered result, but only one
        // page is mounted at a time. Previously the S/Å targets were disabled.
        let entries = (0..<140).map {
            makeEntry(String(format: "A%03d", $0))
        } + [makeEntry("Siste"), makeEntry("Årlig")]
        let sorted = store.alphabetized(entries)
        let targets = store.alphabetIndexTargets(for: sorted)
        let firstPage = ATHLTHExerciseAlphabetPage.visibleEntries(
            from: sorted, startIndex: 0,
            limit: ATHLTHLibraryPagination.pageSize
        )
        XCTAssertEqual(firstPage.count, 50)
        XCTAssertNil(store.alphabetIndexTargets(for: firstPage)["S"])
        let sID = try XCTUnwrap(targets["S"])
        let sOffset = try XCTUnwrap(
            ATHLTHExerciseAlphabetPage.startIndex(for: sID, in: sorted)
        )
        XCTAssertEqual(sOffset, 140)
        let sPage = ATHLTHExerciseAlphabetPage.visibleEntries(
            from: sorted, startIndex: sOffset,
            limit: ATHLTHLibraryPagination.pageSize
        )
        XCTAssertEqual(sPage.map(\.name), ["Siste", "Årlig"])
        XCTAssertEqual(
            ATHLTHExerciseAlphabetPage.remainingCount(
                total: sorted.count, startIndex: sOffset
            ),
            2
        )
        let aID = try XCTUnwrap(targets["A"])
        XCTAssertEqual(
            ATHLTHExerciseAlphabetPage.startIndex(for: aID, in: sorted), 0
        )
        let lastID = try XCTUnwrap(targets["Å"])
        XCTAssertEqual(
            ATHLTHExerciseAlphabetPage.startIndex(
                for: lastID, in: sorted
            ),
            141
        )
    }

    func testAlphabetPaginationOnlyLoadsFiftyRowsAtEachNewLetter() throws {
        let store = ExerciseLibraryStore()
        let entries = (0..<120).map {
            makeEntry(String(format: "A%03d", $0))
        } + (0..<130).map {
            makeEntry(String(format: "S%03d", $0))
        }
        let sorted = store.alphabetized(entries)
        let target = try XCTUnwrap(store.alphabetIndexTargets(for: sorted)["S"])
        let start = try XCTUnwrap(
            ATHLTHExerciseAlphabetPage.startIndex(for: target, in: sorted)
        )
        XCTAssertEqual(start, 120)
        let first = ATHLTHExerciseAlphabetPage.visibleEntries(
            from: sorted, startIndex: start, limit: 50
        )
        XCTAssertEqual(first.count, 50)
        XCTAssertTrue(first.allSatisfy { $0.name.hasPrefix("S") })
        let expanded = ATHLTHExerciseAlphabetPage.visibleEntries(
            from: sorted, startIndex: start, limit: 100
        )
        XCTAssertEqual(expanded.count, 100)
        XCTAssertEqual(
            ATHLTHExerciseAlphabetPage.remainingCount(
                total: sorted.count, startIndex: start
            ),
            130
        )
        XCTAssertEqual(
            ATHLTHExerciseAlphabetPage.visibleEntries(
                from: sorted, startIndex: sorted.count + 1, limit: 50
            ).count,
            0
        )
    }

    func testSearchReturnsAlreadySortedExercisesForReuseAcrossViews() {
        let store = ExerciseLibraryStore()
        let entries = store.search(query: "", bodyPart: "Chest")
        XCTAssertFalse(entries.isEmpty)
        let sorted = store.alphabetized(entries)
        XCTAssertEqual(entries.map(\.id), sorted.map(\.id))
        // Repeated queries reuse the same cached sorted results.
        XCTAssertEqual(
            store.search(query: "", bodyPart: "Chest").map(\.id),
            entries.map(\.id)
        )
    }
    func testSquatPrototypeIsSelectableWithoutReplacingOriginal() throws {
        let store = ExerciseLibraryStore()
        let prototype = try XCTUnwrap(store.athlthCatalogExercises.first {
            $0.sourceIdentifier == "athlth-native-test-bodyweight-squat"
        })
        let original = try XCTUnwrap(store.athlthCatalogExercises.first {
            $0.sourceIdentifier == "athlth-native-back-squat"
        })
        XCTAssertEqual(prototype.name, "test")
        XCTAssertEqual(store.localizedExerciseName(prototype), "test")
        XCTAssertEqual(prototype.exercise.primaryMuscles, ["Quads"])
        XCTAssertEqual(prototype.exercise.secondaryMuscles, ["Glutes", "Core"])
        XCTAssertEqual(prototype.exercise.equipment, ["Bodyweight"])
        XCTAssertNotEqual(prototype.id, original.id)
        XCTAssertTrue(store.selectableExercises.contains { $0.id == prototype.id })
        XCTAssertEqual(original.name, "Barbell Back Squat")
    }

}
