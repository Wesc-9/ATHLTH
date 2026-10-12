import XCTest
@testable import ATHLTH

final class ATHLTHPlanJourneyTests: XCTestCase {
    func testSimpleStartsWithModeAndSkipsAdvancedQuestions() {
        let stages = ATHLTHPlanJourney.sequence(advanced: false)
        XCTAssertEqual(stages, [.mode, .basics, .source, .review])
        XCTAssertFalse(stages.contains(.profile))
        XCTAssertFalse(stages.contains(.week))
        XCTAssertEqual(ATHLTHPlanJourney.position(of: .review, advanced: false), 4)
    }

    func testAdvancedKeepsAllSixPlanningStages() {
        XCTAssertEqual(
            ATHLTHPlanJourney.sequence(advanced: true),
            [.mode, .basics, .source, .profile, .week, .review]
        )
        XCTAssertEqual(ATHLTHPlanJourney.position(of: .review, advanced: true), 6)
    }

    func testEveryNextAndPreviousStepIsReversible() {
        for isAdvanced in [false, true] {
            let stages = ATHLTHPlanJourney.sequence(advanced: isAdvanced)
            XCTAssertNil(ATHLTHPlanJourney.previous(before: .mode, advanced: isAdvanced))
            XCTAssertNil(ATHLTHPlanJourney.next(after: .review, advanced: isAdvanced))
            for index in 0..<(stages.count - 1) {
                let current = stages[index]
                let following = stages[index + 1]
                XCTAssertEqual(
                    ATHLTHPlanJourney.next(after: current, advanced: isAdvanced),
                    following
                )
                XCTAssertEqual(
                    ATHLTHPlanJourney.previous(before: following, advanced: isAdvanced),
                    current
                )
            }
        }
    }

    func testPlanDesignHasConsistentLayoutPriorities() {
        XCTAssertGreaterThan(
            ATHLTHPlanDesign.Density.comfortable.cardPadding,
            ATHLTHPlanDesign.Density.compact.cardPadding
        )
        XCTAssertGreaterThanOrEqual(ATHLTHPlanDesign.minTapHeight, 44)
        XCTAssertGreaterThan(ATHLTHPlanDesign.maxContentWidth, 600)
    }
}
