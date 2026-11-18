import UIKit
import XCTest
@testable import ATHLTH

final class ATHLTHHomeFeedArtworkTests: XCTestCase {
    func testRunningWithoutGPSUsesExistingOfflineArtwork() {
        let name = ATHLTHHomeFeedFallbackPolicy.imageName(for: .running)
        XCTAssertEqual(name, ATHLTHPlanWorkoutArtwork.asset(for: .easyRun))
        XCTAssertNotNil(name)
        XCTAssertNotNil(UIImage(named: try! XCTUnwrap(name)),
                        "The running fallback must ship in Assets.xcassets")
    }

    func testNonRunningActivitiesDoNotReplaceTheirExistingArtwork() {
        XCTAssertNil(ATHLTHHomeFeedFallbackPolicy.imageName(for: .strength))
        XCTAssertNil(ATHLTHHomeFeedFallbackPolicy.imageName(for: .walking))
        XCTAssertNil(ATHLTHHomeFeedFallbackPolicy.imageName(for: .cycling))
    }
}
