import XCTest
@testable import ATHLTH

final class ATHLTHGhostCourseProgressPolicyTests: XCTestCase {
    func testOnlyLocationMatchedToPlannedCourseCounts() {
        XCTAssertTrue(ATHLTHGhostCourseProgressPolicy.isReliableOnRoute(
            horizontalAccuracy: 9, deviationMeters: 14,
            alertThresholdMeters: 35
        ))
        XCTAssertFalse(ATHLTHGhostCourseProgressPolicy.isReliableOnRoute(
            horizontalAccuracy: 8, deviationMeters: 150,
            alertThresholdMeters: 35
        ))
        XCTAssertFalse(ATHLTHGhostCourseProgressPolicy.isReliableOnRoute(
            horizontalAccuracy: 65, deviationMeters: 5,
            alertThresholdMeters: 35
        ))
    }

    func testExtraDistanceOffRouteDoesNotChangeCourseGap() {
        // The runner added two kilometres on a detour but returned to
        // the original 2 km position of an 8 km course. The ghost has
        // continued to 3 km on its own reference timeline.
        let gap = ATHLTHGhostCourseProgressPolicy.ghostLeadPercent(
            runnerCourseMeters: 2_000,
            ghostCourseMeters: 3_000,
            routeLengthMeters: 8_000
        )
        XCTAssertEqual(gap ?? 0, 12.5, accuracy: 0.01)
    }

    func testGhostLeadCanBeNegativeWhenRunnerIsAhead() {
        let gap = ATHLTHGhostCourseProgressPolicy.ghostLeadPercent(
            runnerCourseMeters: 4_200,
            ghostCourseMeters: 3_800,
            routeLengthMeters: 10_000
        )
        XCTAssertEqual(gap ?? 0, -4, accuracy: 0.01)
    }

    func testTeleportAtReentryNeverCountsAsRealLead() {
        XCTAssertFalse(ATHLTHGhostCourseProgressPolicy.plausibleCourseAdvance(
            previousMeters: 600, previousElapsed: 30,
            candidateMeters: 2_100, elapsed: 35
        ))
        // Long, genuine detours can bring a runner back farther down
        // the course after sufficient real time has passed.
        XCTAssertTrue(ATHLTHGhostCourseProgressPolicy.plausibleCourseAdvance(
            previousMeters: 600, previousElapsed: 30,
            candidateMeters: 2_100, elapsed: 800
        ))
        XCTAssertFalse(ATHLTHGhostCourseProgressPolicy.plausibleCourseAdvance(
            previousMeters: 600, previousElapsed: 30,
            candidateMeters: 100, elapsed: 800
        ))
    }

    func testFivePercentNoticeIsNotRepeatedOnReentry() {
        XCTAssertFalse(ATHLTHGhostCourseProgressPolicy.shouldAnnouncePercentGap(
            ghostLeadPercent: 4.9, lastAnnouncedPercent: nil,
            secondsSinceLast: nil
        ))
        XCTAssertTrue(ATHLTHGhostCourseProgressPolicy.shouldAnnouncePercentGap(
            ghostLeadPercent: 8, lastAnnouncedPercent: nil,
            secondsSinceLast: nil
        ))
        XCTAssertFalse(ATHLTHGhostCourseProgressPolicy.shouldAnnouncePercentGap(
            ghostLeadPercent: 8.2, lastAnnouncedPercent: 8,
            secondsSinceLast: 1200
        ))
        XCTAssertFalse(ATHLTHGhostCourseProgressPolicy.shouldAnnouncePercentGap(
            ghostLeadPercent: 14, lastAnnouncedPercent: 8,
            secondsSinceLast: 200
        ))
        XCTAssertTrue(ATHLTHGhostCourseProgressPolicy.shouldAnnouncePercentGap(
            ghostLeadPercent: 14, lastAnnouncedPercent: 8,
            secondsSinceLast: 500
        ))
    }

    func testUnknownOrShortCourseDoesNotReportFalsePercent() {
        XCTAssertNil(ATHLTHGhostCourseProgressPolicy.ghostLeadPercent(
            runnerCourseMeters: 100, ghostCourseMeters: 200,
            routeLengthMeters: 0
        ))
        XCTAssertNil(ATHLTHGhostCourseProgressPolicy.ghostLeadPercent(
            runnerCourseMeters: 100, ghostCourseMeters: 200,
            routeLengthMeters: 300
        ))
    }
}
