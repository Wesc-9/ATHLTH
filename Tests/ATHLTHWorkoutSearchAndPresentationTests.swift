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

    func testFourByFourTimelineFactsPreserveActualEffortsAndRecovery() throws {
        let workout = try XCTUnwrap(
            RunningWorkoutLibraryStore.builtInTemplates.first { $0.title == workoutTitle }
        )
        let steps = workout.recipePreviewBlocks
        XCTAssertEqual(steps.count, 9)
        XCTAssertEqual(steps[1].durationSeconds, 4 * 60)
        XCTAssertEqual(steps[2].durationSeconds, 2 * 60)
        XCTAssertEqual(steps[1].targetEffortRPE, 8)
        XCTAssertNil(steps[2].targetEffortRPE)

        // Both the tapped drag and its next step use canonical execution order.
        XCTAssertEqual(ATHLTHWorkoutStepCopy.title(
            for: steps[2], workoutTitle: workoutTitle, compact: true
        ), ATHLTHLocalization.choose(
            english: "Active recovery · easy jog",
            norwegian: "Aktiv pause · rolig jogg"
        ))
        let facts = ATHLTHPlanWorkoutCardPresentation.facts(
            for: steps[1], workoutTitle: workoutTitle
        )
        XCTAssertTrue(facts.contains("4 min"))
        XCTAssertTrue(facts.contains(ATHLTHLocalization.choose(
            english: "Suggested HR zone Z4",
            norwegian: "Anbefalt pulssone S4"
        )))
        // A suggestion in the preview is never silently written as a target.
        XCTAssertNil(steps[1].targetHeartRateZone)
    }


    func testFractionalRunningRPEIsNotRoundedInStepDetails() throws {
        let workout = try XCTUnwrap(
            RunningWorkoutLibraryStore.builtInTemplates.first {
                $0.title == "5 × 1 km terskel"
            }
        )
        let work = try XCTUnwrap(workout.recipePreviewBlocks.first {
            $0.resolvedPhase == .main
        })
        XCTAssertNil(work.targetEffortRPE)
        XCTAssertEqual(work.targetIntensityType, "RPE 7.5")
    }


    func testWorkoutAlphabetIndexSeesLettersBeyondFirstFiftyResults() throws {
        var index = ATHLTHWorkoutAlphabetPage.Index()
        for number in 0..<120 {
            index.register(
                title: String(format: "A%03d", number),
                id: UUID(), offset: number
            )
        }
        let sID = UUID()
        let aeID = UUID()
        let oID = UUID()
        let aRingID = UUID()
        index.register(title: "Siste drag", id: sID, offset: 120)
        index.register(title: "Ærlig innsats", id: aeID, offset: 121)
        index.register(title: "Økt på mølle", id: oID, offset: 122)
        index.register(title: "Åsen rundt", id: aRingID, offset: 123)

        XCTAssertEqual(index.targets.count, 5)
        XCTAssertEqual(index.targets["S"], sID)
        XCTAssertEqual(index.targets["Æ"], aeID)
        XCTAssertEqual(index.targets["Ø"], oID)
        XCTAssertEqual(index.targets["Å"], aRingID)
        XCTAssertEqual(index.startIndex(for: sID), 120)

        let sRange = ATHLTHWorkoutAlphabetPage.range(
            startIndex: 120, limit: 50, offset: 0, count: 124
        )
        XCTAssertEqual(sRange, 120..<124)
    }

    func testWorkoutAlphabetPageSavesFiftyRowBudgetAcrossAllSections() {
        let counts = [3, 65, 42, 185] // planned, saved, catalog, running
        let offsets = [0, 3, 68, 110]
        func page(_ start: Int, _ limit: Int) -> [Range<Int>] {
            counts.indices.map {
                ATHLTHWorkoutAlphabetPage.range(
                    startIndex: start, limit: limit,
                    offset: offsets[$0], count: counts[$0]
                )
            }
        }

        let first = page(0, 50)
        XCTAssertEqual(first, [0..<3, 0..<47, 0..<0, 0..<0])
        XCTAssertEqual(first.reduce(0) { $0 + $1.count }, 50)

        // A letter in the running templates, beyond 50 results.
        let running = page(170, 50)
        XCTAssertEqual(running, [3..<3, 65..<65, 42..<42, 60..<110])
        XCTAssertEqual(running.reduce(0) { $0 + $1.count }, 50)

        // A letter in Mine, then load 50 more without returning to A.
        let mine = page(60, 50)
        XCTAssertEqual(mine, [3..<3, 57..<65, 0..<42, 0..<0])
        XCTAssertEqual(mine.reduce(0) { $0 + $1.count }, 50)
        let expanded = page(60, 100)
        XCTAssertEqual(expanded.reduce(0) { $0 + $1.count }, 100)
        XCTAssertEqual(
            ATHLTHWorkoutAlphabetPage.remainingCount(
                total: counts.reduce(0, +), startIndex: 60
            ),
            235
        )
    }

}
