import UIKit
import XCTest
@testable import ATHLTH

final class HomeTreadmillRecentArtworkTests: XCTestCase {
    func testTreadmillFeedUsesRealHighResolutionTreadmillPhoto() throws {
        let imageName = HomeTreadmillRecentArtwork.backgroundAssetName
        XCTAssertEqual(imageName, "TreadmillRecentCardHero")
        // UIImage(named:) can return a downsized asset-catalog rendition.
        // Verify the original photo that the actual card loads instead.
        let path = try XCTUnwrap(Bundle.main.url(
            forResource: "TreadmillRecentCardHeroFull",
            withExtension: "jpg"
        ), "The original source must be bundled, not just the small asset.")
        let photo = try XCTUnwrap(UIImage(contentsOfFile: path.path))
        let width = try XCTUnwrap(photo.cgImage).width
        let height = try XCTUnwrap(photo.cgImage).height
        XCTAssertGreaterThanOrEqual(width, 1400,
                                    "Treadmill source must be full-resolution")
        XCTAssertGreaterThanOrEqual(height, 900)
    }

    func testTreadmillPhotoIsDistinctFromOutdoorRunning() {
        XCTAssertNotEqual(HomeTreadmillRecentArtwork.backgroundAssetName,
                          ATHLTHPlanWorkoutArtwork.asset(for: .easyRun))
    }
}
