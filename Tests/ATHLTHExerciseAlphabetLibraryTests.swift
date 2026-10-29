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
            equipment: ["Bodyweight"], imageURL: nil
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
}
