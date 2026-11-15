import XCTest
@testable import ATHLTH

final class ATHLTHStudioHomePlanHeroPolicyTests: XCTestCase {
    func testNoPlanDoesNotClaimAnActivePlan() {
        XCTAssertEqual(
            ATHLTHStudioHomePlanHeroPolicy.statusLabel(for: nil, norwegian: true),
            "INGEN AKTIV TRENINGSPLAN"
        )
        XCTAssertEqual(
            ATHLTHStudioHomePlanHeroPolicy.statusLabel(for: nil, norwegian: false),
            "NO ACTIVE TRAINING PLAN"
        )
    }

    func testUpcomingPlanIsNotPresentedAsActive() {
        XCTAssertEqual(
            ATHLTHStudioHomePlanHeroPolicy.statusLabel(
                for: .upcoming, norwegian: true
            ),
            "KOMMENDE TRENINGSPLAN"
        )
        XCTAssertEqual(
            ATHLTHStudioHomePlanHeroPolicy.statusLabel(
                for: .upcoming, norwegian: false
            ),
            "UPCOMING TRAINING PLAN"
        )
    }

    func testOnlyGenuineActivePlanReceivesActiveHeading() {
        XCTAssertEqual(
            ATHLTHStudioHomePlanHeroPolicy.statusLabel(
                for: .active, norwegian: true
            ),
            "AKTIV TRENINGSPLAN"
        )
    }

    func testCompletedAndUnscheduledHaveTheirOwnHeadings() {
        XCTAssertEqual(
            ATHLTHStudioHomePlanHeroPolicy.statusLabel(
                for: .completed, norwegian: true
            ),
            "FULLFØRT TRENINGSPLAN"
        )
        XCTAssertEqual(
            ATHLTHStudioHomePlanHeroPolicy.statusLabel(
                for: .unscheduled, norwegian: false
            ),
            "UNSCHEDULED TRAINING PLAN"
        )
    }
}
