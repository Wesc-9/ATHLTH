import UIKit
import XCTest
@testable import ATHLTH

final class ATHLTHHomeFeedArtworkTests: XCTestCase {
    func testSharedArtworkDisplaysRecordedRunMetrics() {
        let metrics = ATHLTHFeedArtworkMetrics(duration: 1500, distanceMeters: 5000)
        XCTAssertEqual(metrics.primary, "5.00 km")
        XCTAssertEqual(metrics.secondary, "25 min · 5:00 /km")
    }

    func testStrengthArtworkUsesActualDurationAndOmitsMissingMetrics() {
        let metrics = ATHLTHFeedArtworkMetrics(duration: 60, strength: true)
        XCTAssertEqual(metrics.primary, "1 min")
        XCTAssertTrue(metrics.secondary.isEmpty)
        let empty = ATHLTHFeedArtworkMetrics(duration: .nan, distanceMeters: 0, strength: true)
        XCTAssertNil(empty.primary)
        XCTAssertTrue(empty.secondary.isEmpty)
    }

    func testCyclingDoesNotShowRunningPace() {
        let metrics = ATHLTHFeedArtworkMetrics(duration: 1800, distanceMeters: 12000, showsPace: false)
        XCTAssertEqual(metrics.primary, "12.00 km")
        XCTAssertEqual(metrics.secondary, "30 min")
    }

    func testRunningWithoutGPSUsesExistingOfflineArtwork() throws {
        let name = try XCTUnwrap(ATHLTHHomeFeedFallbackPolicy.imageName(for: .running))
        XCTAssertEqual(name, ATHLTHPlanWorkoutArtwork.asset(for: .easyRun))
        XCTAssertNotNil(UIImage(named: name),
                        "The running fallback must ship in Assets.xcassets")
    }

    func testNonRunningActivitiesDoNotReplaceTheirExistingArtwork() {
        XCTAssertNil(ATHLTHHomeFeedFallbackPolicy.imageName(for: .strength))
        XCTAssertNil(ATHLTHHomeFeedFallbackPolicy.imageName(for: .walking))
        XCTAssertNil(ATHLTHHomeFeedFallbackPolicy.imageName(for: .cycling))
    }
}
