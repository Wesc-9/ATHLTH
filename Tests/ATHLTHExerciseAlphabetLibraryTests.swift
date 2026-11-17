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


    func testSharedAlphabetLookupCanJumpToSAfterHundredItems() throws {
        struct Item {
            let id: UUID
            let title: String
        }
        let initial = (0..<130).map { number in
            Item(id: UUID(), title: String(format: "A%03d", number))
        }
        let s = Item(id: UUID(), title: "Siste økt")
        let ae = Item(id: UUID(), title: "Ærlig innsats")
        let oe = Item(id: UUID(), title: "Økt i skogen")
        let aa = Item(id: UUID(), title: "Åsen rundt")
        let all = initial + [s, ae, oe, aa]
        let alphabet = ATHLTHLibraryAlphabetLookup(
            items: all, id: { $0.id }, title: { $0.title }
        )
        XCTAssertEqual(alphabet.targets.count, 5)
        XCTAssertEqual(alphabet.targets["S"], s.id)
        XCTAssertEqual(alphabet.targets["Æ"], ae.id)
        XCTAssertEqual(alphabet.targets["Ø"], oe.id)
        XCTAssertEqual(alphabet.targets["Å"], aa.id)
        XCTAssertEqual(alphabet.index(for: s.id), 130)
        XCTAssertNil(alphabet.targets["G"])

        // The very first page has no S, yet the index jumps directly into
        // the full filtered result without mounting the preceding 130 rows.
        XCTAssertEqual(
            ATHLTHLibraryAlphabetWindow.visible(all, start: 0, limit: 50).count, 50
        )
        let sWindow = ATHLTHLibraryAlphabetWindow.visible(
            all, start: 130, limit: 50
        )
        XCTAssertEqual(sWindow.map(\.id), [s.id, ae.id, oe.id, aa.id])
        XCTAssertEqual(
            ATHLTHLibraryAlphabetWindow.remaining(total: all.count, start: 130), 4
        )
    }

    func testSharedAlphabetPagingKeepsFiftyItemsWithDifferentLibraryTypes() throws {
        struct LibraryCard {
            let id: UUID
            let name: String
            let group: String
        }
        let plans = (0..<65).map {
            LibraryCard(id: UUID(), name: String(format: "A%03d", $0), group: "plan")
        }
        let routes = (0..<120).map {
            LibraryCard(id: UUID(), name: String(format: "S%03d", $0), group: "route")
        }
        let all = plans + routes
        let lookup = ATHLTHLibraryAlphabetLookup(
            items: all, id: { $0.id }, title: { $0.name }
        )
        let sIndex = try XCTUnwrap(lookup.index(for: routes[0].id))
        XCTAssertEqual(sIndex, 65)
        let firstS = ATHLTHLibraryAlphabetWindow.visible(
            all, start: sIndex, limit: ATHLTHLibraryPagination.pageSize
        )
        XCTAssertEqual(firstS.count, 50)
        XCTAssertTrue(firstS.allSatisfy { $0.group == "route" })
        let next = ATHLTHLibraryAlphabetWindow.visible(
            all, start: sIndex, limit: 2 * ATHLTHLibraryPagination.pageSize
        )
        XCTAssertEqual(next.count, 100)
        let nearEnd = ATHLTHLibraryAlphabetWindow.visible(
            all, start: 180, limit: 50
        )
        XCTAssertEqual(nearEnd.count, 5)
        XCTAssertEqual(
            ATHLTHLibraryAlphabetWindow.remaining(total: all.count, start: 180), 5
        )
    }

    func testFilteredAlphabetIndexDoesNotReferenceExcludedCards() throws {
        struct Card {
            let id: UUID
            let title: String
            let favorite: Bool
        }
        let all = [
            Card(id: UUID(), title: "A-økt", favorite: true),
            Card(id: UUID(), title: "Skulderpress", favorite: false),
            Card(id: UUID(), title: "Styrkeøkt", favorite: true)
        ]
        let filtered = all.filter(\.favorite)
        let lookup = ATHLTHLibraryAlphabetLookup(
            items: filtered, id: { $0.id }, title: { $0.title }
        )
        XCTAssertEqual(lookup.targets["S"], all[2].id)
        XCTAssertEqual(lookup.index(for: all[2].id), 1)
        XCTAssertNil(lookup.index(for: all[1].id))
        XCTAssertEqual(lookup.targets["A"], all[0].id)
    }

}
