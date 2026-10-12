import XCTest
@testable import ATHLTH

final class ATHLTHLiveActivitySessionIdentityTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testSameRunWithChangedTitleRetainsLiveActivity() {
        let first = ATHLTHLiveActivitySessionIdentity(
            systemImage: "figure.run", startedAt: now,
            fallbackTitle: "Morning run"
        )
        let renamed = ATHLTHLiveActivitySessionIdentity(
            systemImage: "figure.run", startedAt: now,
            fallbackTitle: "Intervals"
        )
        XCTAssertTrue(first.matches(renamed))
    }

    func testSubsequentRunMustNotReuseOldActivity() {
        let earlier = ATHLTHLiveActivitySessionIdentity(
            systemImage: "figure.run", startedAt: now,
            fallbackTitle: "Run"
        )
        let later = ATHLTHLiveActivitySessionIdentity(
            systemImage: "figure.run",
            startedAt: now.addingTimeInterval(30),
            fallbackTitle: "Run"
        )
        XCTAssertFalse(earlier.matches(later))
    }

    func testDifferentSportCannotReuseActivity() {
        let run = ATHLTHLiveActivitySessionIdentity(
            systemImage: "figure.run", startedAt: now,
            fallbackTitle: "Workout"
        )
        let walk = ATHLTHLiveActivitySessionIdentity(
            systemImage: "figure.walk", startedAt: now,
            fallbackTitle: "Workout"
        )
        XCTAssertFalse(run.matches(walk))
    }

    func testMissingStartDateNeedsSameFallbackTitleAndKind() {
        let one = ATHLTHLiveActivitySessionIdentity(
            systemImage: "dumbbell.fill", startedAt: nil,
            fallbackTitle: "Strength A"
        )
        let matching = ATHLTHLiveActivitySessionIdentity(
            systemImage: "dumbbell.fill", startedAt: nil,
            fallbackTitle: "Strength A"
        )
        let different = ATHLTHLiveActivitySessionIdentity(
            systemImage: "dumbbell.fill", startedAt: nil,
            fallbackTitle: "Strength B"
        )
        XCTAssertTrue(one.matches(matching))
        XCTAssertFalse(one.matches(different))
        XCTAssertFalse(one.matches(.init(
            systemImage: "dumbbell.fill", startedAt: now,
            fallbackTitle: "Strength A"
        )))
    }
}
