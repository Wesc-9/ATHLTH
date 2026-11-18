import UIKit
import XCTest
@testable import ATHLTH

final class HomeTreadmillRecentArtworkTests: XCTestCase {
    func testTreadmillFeedUsesAlreadyBundledFullSizeRunningPhoto() {
        let imageName = HomeTreadmillRecentArtwork.backgroundAssetName
        XCTAssertEqual(imageName, ATHLTHPlanWorkoutArtwork.asset(for: .easyRun))
        XCTAssertNotEqual(imageName, "TreadmillRecentCardHero")
        XCTAssertNotNil(UIImage(named: imageName),
                        "Treadmill feed must reuse a bundled running photo")
    }

    func testLegacyTreadmillPhotoIsNotUsedInReplayOrFeed() {
        XCTAssertEqual(HomeTreadmillRecentArtwork.backgroundAssetName,
                       ATHLTHPlanWorkoutArtwork.asset(for: .easyRun))
    }
}
