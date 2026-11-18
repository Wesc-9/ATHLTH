import UIKit
import XCTest
@testable import ATHLTH

final class HomeTreadmillRecentArtworkTests: XCTestCase {
    func testTreadmillFeedUsesRealHighResolutionTreadmillPhoto() throws {
        let imageName = HomeTreadmillRecentArtwork.backgroundAssetName
        XCTAssertEqual(imageName, "TreadmillRecentCardHero")
        let image = try XCTUnwrap(UIImage(named: imageName))
        let pixelsWide = try XCTUnwrap(image.cgImage).width
        let pixelsHigh = try XCTUnwrap(image.cgImage).height
        XCTAssertGreaterThanOrEqual(pixelsWide, 1400,
                                    "Treadmill image must be full-resolution")
        XCTAssertGreaterThanOrEqual(pixelsHigh, 900)
    }

    func testTreadmillPhotoIsDistinctFromOutdoorRunning() {
        XCTAssertNotEqual(HomeTreadmillRecentArtwork.backgroundAssetName,
                          ATHLTHPlanWorkoutArtwork.asset(for: .easyRun))
    }
}
