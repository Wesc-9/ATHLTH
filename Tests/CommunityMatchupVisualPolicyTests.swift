import XCTest
@testable import ATHLTH

final class CommunityMatchupVisualPolicyTests: XCTestCase {
    func testWinnerRequiresBothFiniteVisibleScores() {
        XCTAssertEqual(
            CommunityMatchupVisualPolicy.standing(mine: 79, theirs: 0),
            .leading
        )
        XCTAssertEqual(
            CommunityMatchupVisualPolicy.standing(mine: 0, theirs: 12),
            .trailing
        )
        XCTAssertEqual(
            CommunityMatchupVisualPolicy.standing(mine: 0, theirs: 0),
            .tied
        )
        XCTAssertEqual(
            CommunityMatchupVisualPolicy.standing(mine: 80, theirs: nil),
            .unavailable
        )
        XCTAssertEqual(
            CommunityMatchupVisualPolicy.standing(mine: .nan, theirs: 0),
            .unavailable
        )
    }

    func testShareIsBoundedAndDoesNotDivideByZero() {
        XCTAssertEqual(
            CommunityMatchupVisualPolicy.share(mine: 20, theirs: 80),
            0.2,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            CommunityMatchupVisualPolicy.share(mine: 0, theirs: 0),
            0.5
        )
        XCTAssertEqual(
            CommunityMatchupVisualPolicy.share(mine: 20, theirs: nil),
            0.5
        )
    }

    func testActivityPointBreakdownMatchesExistingFormula() {
        let result = CommunityMatchupVisualPolicy.pointsBreakdown(
            workouts: 3, activeMinutes: 96
        )
        XCTAssertEqual(result?.workoutPoints, 60)
        XCTAssertEqual(result?.timePoints, 19.2)
        XCTAssertEqual(
            CommunityMatchupVisualPolicy.pointsBreakdown(
                workouts: 1, activeMinutes: 250
            )?.timePoints, 24
        )
        XCTAssertNil(
            CommunityMatchupVisualPolicy.pointsBreakdown(
                workouts: nil, activeMinutes: 90
            )
        )
    }

    func testComparisonBarsDoNotFabricateMissingData() {
        XCTAssertNil(CommunityMatchupVisualPolicy.fraction(nil, 12))
        XCTAssertNil(CommunityMatchupVisualPolicy.fraction(0, 0))
        XCTAssertNil(CommunityMatchupVisualPolicy.fraction(.nan, 8))
        XCTAssertEqual(
            CommunityMatchupVisualPolicy.fraction(30, 10) ?? 0,
            0.75,
            accuracy: 0.0001
        )
    }
}
