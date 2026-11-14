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

    func testIndexedSearchKeepsNorwegianAndFourByFourMatching() {
        let examples: [([String], [String: Bool])] = [
            (["4 × 4 intervaller", "Løping"], [
                "4x4": true, "norwegian 4x4": true,
                "Norwegian 4 x 4 intervals": true, "7x3": false
            ]),
            (["Fullkropp – styrke", "Nybegynner", "bein"], [
                "fullkropp": true, "FULLKROPP": true,
                "styrke": true, "rygg": false
            ]),
            (["Skuldre og armer", "Dumbbell Press"], [
                "skuldre": true, "dumbbellpress": true,
                "mage": false
            ])
        ]
        for (texts, queries) in examples {
            let index = ATHLTHWorkoutSearch.makeIndex(texts: texts)
            for (query, expected) in queries {
                let needle = ATHLTHWorkoutSearch.normalized(query)
                XCTAssertEqual(
                    ATHLTHWorkoutSearch.matches(
                        normalizedNeedle: needle, index: index
                    ),
                    expected,
                    "\(query) should match correctly in cached search"
                )
                XCTAssertEqual(
                    ATHLTHWorkoutSearch.matches(query, texts: texts),
                    expected
                )
            }
        }
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
        ), ATHLTHLocalization.choose(
            english: "4x4 intervals · rep 1/4",
            norwegian: "4x4 intervall · drag 1/4"
        ))
        XCTAssertEqual(ATHLTHWorkoutStepCopy.title(
            for: steps[2], workoutTitle: workoutTitle, compact: true
        ), ATHLTHLocalization.choose(
            english: "Active recovery · easy jog",
            norwegian: "Aktiv pause · rolig jogg"
        ))
        XCTAssertEqual(steps.filter { $0.resolvedPhase == .main }.count, 4)
    }

    func testSuggestedZonesAreHintsAndDoNotChangeWorkoutPrescription() throws {
        let workout = try XCTUnwrap(
            RunningWorkoutLibraryStore.builtInTemplates.first { $0.title == workoutTitle }
        )
        let steps = workout.recipePreviewBlocks
        XCTAssertEqual(ATHLTHWorkoutStepCopy.suggestedZone(
            for: steps[0], workoutTitle: workoutTitle
        ), ATHLTHLocalization.choose(
            english: "Suggested HR zone Z1–Z2",
            norwegian: "Anbefalt pulssone S1–S2"
        ))
        XCTAssertEqual(ATHLTHWorkoutStepCopy.suggestedZone(
            for: steps[1], workoutTitle: workoutTitle
        ), ATHLTHLocalization.choose(
            english: "Suggested HR zone Z4",
            norwegian: "Anbefalt pulssone S4"
        ))
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
