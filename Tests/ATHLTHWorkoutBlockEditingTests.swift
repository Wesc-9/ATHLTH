import XCTest
@testable import ATHLTH

final class ATHLTHWorkoutBlockEditingTests: XCTestCase {
    private func block(
        _ sequence: Int,
        title: String,
        kind: WorkoutTemplateBlockKind = .exercise
    ) -> WorkoutTemplateBlock {
        WorkoutTemplateBlock(
            sequence: sequence,
            kind: kind,
            title: title,
            exerciseSlug: kind == .exercise ? "barbell-squat" : nil,
            distanceMeters: kind == .run ? 1200 : nil,
            repetitions: kind == .exercise ? 10 : nil,
            durationSeconds: kind == .rest ? 90 : nil,
            targetWeightKilograms: kind == .exercise ? 60 : nil,
            loadNote: kind == .exercise ? "20 kg bar" : nil,
            notes: "Saved note"
        )
    }

    func testReorderingPreservesEveryBlockPrescription() {
        let original = [
            block(4, title: "Warmup", kind: .run),
            block(8, title: "Squat"),
            block(15, title: "Rest", kind: .rest)
        ]

        let moved = ATHLTHWorkoutBlockEditing.moved(original, from: 1, to: 0)
        XCTAssertEqual(moved.map(\.title), ["Squat", "Warmup", "Rest"])
        XCTAssertEqual(moved.map(\.sequence), [1, 2, 3])
        XCTAssertEqual(moved[0].exerciseSlug, "barbell-squat")
        XCTAssertEqual(moved[0].targetWeightKilograms, 60)
        XCTAssertEqual(moved[0].repetitions, 10)
        XCTAssertEqual(moved[0].loadNote, "20 kg bar")
        XCTAssertEqual(moved[1].distanceMeters, 1200)
        XCTAssertEqual(moved[2].durationSeconds, 90)
        XCTAssertEqual(original.map(\.sequence), [4, 8, 15])
    }

    func testReplacingAndRemovingNeverChangeOtherBlockDetails() {
        let original = [block(1, title: "Squat"), block(2, title: "Pause", kind: .rest)]
        var edited = original[0]
        edited.title = "Squat – heavier"
        edited.notes = "New target"
        let replaced = ATHLTHWorkoutBlockEditing.replacing(
            original, at: 0, with: edited
        )
        XCTAssertEqual(replaced[0].title, "Squat – heavier")
        XCTAssertEqual(replaced[0].notes, "New target")
        XCTAssertEqual(replaced[0].targetWeightKilograms, 60)
        XCTAssertEqual(replaced[1], original[1])

        let removed = ATHLTHWorkoutBlockEditing.removing(replaced, at: 0)
        XCTAssertEqual(removed.count, 1)
        XCTAssertEqual(removed[0].sequence, 1)
        XCTAssertEqual(removed[0].durationSeconds, 90)
        XCTAssertEqual(original[0].notes, "Saved note")
    }

    func testAddingPauseLeavesOtherBlocksUnchanged() {
        let original = [block(1, title: "Squat")]
        let updated = ATHLTHWorkoutBlockEditing.appending(original, kind: .rest)
        XCTAssertEqual(updated.count, 2)
        XCTAssertEqual(updated[0], original[0])
        XCTAssertEqual(updated[1].kind, .rest)
        XCTAssertEqual(updated[1].durationSeconds, 60)
        XCTAssertEqual(
            ATHLTHWorkoutBlockEditing.appending(original, kind: .exercise),
            original
        )
    }
}
