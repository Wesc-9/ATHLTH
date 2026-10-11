import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHArenaRepetitionResultTests: XCTestCase {
    func testAgreedExerciseUsesExplicitRoundRule() {
        let rules = "Øvelse: Knebøy\nKun godkjente løft telles."
        XCTAssertEqual(
            ATHLTHArenaRepetitionResult.agreedExercise(in: rules),
            "Knebøy"
        )
        XCTAssertNil(ATHLTHArenaRepetitionResult.agreedExercise(
            in: "Flest repetisjoner i valgfri øvelse."
        ))
    }

    func testManualRepetitionResultIncludesExerciseAndEachPlace() {
        let result = ATHLTHArenaRepetitionResult.explanation(
            exercise: "Knebøy",
            repetitions: ["45", "38", "21"],
            optionalNote: "Kun godkjente løft"
        )
        XCTAssertTrue(result?.contains("Øvelse: Knebøy") == true)
        XCTAssertTrue(result?.contains("3. plass: 21 repetisjoner") == true)
        XCTAssertTrue(result?.contains("Kun godkjente løft") == true)
    }

    func testMissingExerciseIsNotAnEligibleResult() {
        XCTAssertNil(ATHLTHArenaRepetitionResult.explanation(
            exercise: " ", repetitions: ["50"], optionalNote: ""
        ))
    }

    func testZeroOrMalformedRepetitionsCannotBeSubmitted() {
        for count in ["0", "-2", "45.5", "text", "100001"] {
            XCTAssertNil(ATHLTHArenaRepetitionResult.explanation(
                exercise: "Push-ups", repetitions: [count], optionalNote: ""
            ))
        }
    }

    func testOversizedEvidenceIsRejectedBeforeSubmitting() {
        XCTAssertNil(ATHLTHArenaRepetitionResult.explanation(
            exercise: "Squat", repetitions: ["25"],
            optionalNote: String(repeating: "X", count: 620)
        ))
    }
}
