import Foundation
import XCTest
@testable import ATHLTH

final class ExplorePublicWorkoutMapTests: XCTestCase {
    func testOnlyPublicMarketplaceAreasAppearOnExploreMap() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let upcoming = now.addingTimeInterval(3_600)

        XCTAssertTrue(ExplorePublicWorkoutMapPolicy.canDisplay(
            status: .open, broadArea: "Trondheim",
            scheduledStart: upcoming, asOf: now
        ))
        XCTAssertTrue(ExplorePublicWorkoutMapPolicy.canDisplay(
            status: .full, broadArea: "Bodø",
            scheduledStart: upcoming, asOf: now
        ))

        for status: TrainTogetherPostStatus in [.cancelled, .completed] {
            XCTAssertFalse(ExplorePublicWorkoutMapPolicy.canDisplay(
                status: status, broadArea: "Trondheim",
                scheduledStart: upcoming, asOf: now
            ))
        }

        for area in ["", "   ", "Online", "på avstand", "remote", "Digitalt"] {
            XCTAssertFalse(ExplorePublicWorkoutMapPolicy.canDisplay(
                status: .open, broadArea: area,
                scheduledStart: upcoming, asOf: now
            ))
        }

        XCTAssertFalse(ExplorePublicWorkoutMapPolicy.canDisplay(
            status: .open, broadArea: "Trondheim",
            scheduledStart: now.addingTimeInterval(-3 * 3_600),
            asOf: now
        ))
    }
}
