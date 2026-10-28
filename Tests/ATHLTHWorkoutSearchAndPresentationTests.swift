import Foundation
import XCTest
@testable import ATHLTH

@MainActor
final class ATHLTHWorkoutSearchAndPresentationTests: XCTestCase {
    private let workoutTitle = "4 × 4 intervaller"

    func testFourByFourSearchIgnoresMultiplicationGlyphAndWhitespace() {
        let names = ["4 × 4 intervaller", "Rolig jogg", "Løping"]
        for query in [
            "4x4", "4 x 4", "4  x  4", "4×4", "4X4",
            "norwegian 4x4", "4x4 intervals", "Norwegian 4 x 4 intervals"
        ] {
            XCTAssertTrue(ATHLTHWorkoutSearch.matches(query, texts: names),
                          "Expected search to match: \(query)")
        }
        XCTAssertFalse(ATHLTHWorkoutSearch.matches("7x3", texts: names))
        XCTAssertTrue(ATHLTHWorkoutSearch.matches("   ", texts: names))
    }

    func testFourByFourHasConcreteWarmupAndIntervalLabels() throws {
        let workout = try XCTUnwrap(
            RunningWorkoutLibraryStore.builtInTemplates.first { $0.title == workoutTitle }
        )
        let steps = workout.recipePreviewBlocks
        XCTAssertEqual(ATHLTHWorkoutStepCopy.title(
            for: steps[0], workoutTitle: workoutTitle, compact: true
        ), "Jogging")
        XCTAssertEqual(ATHLTHWorkoutStepCopy.title(
            for: steps[1], workoutTitle: workoutTitle, compact: true
        ), "4x4 intervall · drag 1/4")
        XCTAssertEqual(ATHLTHWorkoutStepCopy.title(
            for: steps[2], workoutTitle: workoutTitle, compact: true
        ), "Aktiv pause · rolig jogg")
        XCTAssertEqual(steps.filter { $0.resolvedPhase == .main }.count, 4)
    }

    func testSuggestedZonesAreHintsAndDoNotChangeWorkoutPrescription() throws {
        let workout = try XCTUnwrap(
            RunningWorkoutLibraryStore.builtInTemplates.first { $0.title == workoutTitle }
        )
        let steps = workout.recipePreviewBlocks
        XCTAssertEqual(ATHLTHWorkoutStepCopy.suggestedZone(
            for: steps[0], workoutTitle: workoutTitle
        ), "Anbefalt pulssone S1–2")
        XCTAssertEqual(ATHLTHWorkoutStepCopy.suggestedZone(
            for: steps[1], workoutTitle: workoutTitle
        ), "Anbefalt pulssone S4")
        XCTAssertNil(steps[1].targetHeartRateZone)
        var prescribed = steps[1]
        prescribed.targetHeartRateZone = 3
        XCTAssertNil(ATHLTHWorkoutStepCopy.suggestedZone(
            for: prescribed, workoutTitle: workoutTitle
        ))
        XCTAssertNil(ATHLTHWorkoutStepCopy.suggestedZone(
            for: steps[0], workoutTitle: "Recovery run"
        ))
    }
}
