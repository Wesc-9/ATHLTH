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

    func testActivityKitSnapshotWatermarkRejectsDelayedOlderUpdate() {
        let session = ATHLTHLiveActivitySessionIdentity(
            systemImage: "figure.run",
            startedAt: now,
            fallbackTitle: "Run"
        )
        XCTAssertTrue(ATHLTHLiveActivitySessionIdentity.acceptsCapturedAt(
            currentIdentity: session,
            incomingIdentity: session,
            currentCapturedAt: now.addingTimeInterval(25),
            incomingCapturedAt: now.addingTimeInterval(30)
        ))
        XCTAssertFalse(ATHLTHLiveActivitySessionIdentity.acceptsCapturedAt(
            currentIdentity: session,
            incomingIdentity: session,
            currentCapturedAt: now.addingTimeInterval(30),
            incomingCapturedAt: now.addingTimeInterval(25)
        ))
        let nextWorkout = ATHLTHLiveActivitySessionIdentity(
            systemImage: "figure.run",
            startedAt: now.addingTimeInterval(120),
            fallbackTitle: "Run"
        )
        XCTAssertTrue(ATHLTHLiveActivitySessionIdentity.acceptsCapturedAt(
            currentIdentity: session,
            incomingIdentity: nextWorkout,
            currentCapturedAt: now.addingTimeInterval(30),
            incomingCapturedAt: now.addingTimeInterval(121)
        ))
        XCTAssertFalse(ATHLTHLiveActivitySessionIdentity.acceptsCapturedAt(
            currentIdentity: nil,
            incomingIdentity: session,
            currentCapturedAt: nil,
            incomingCapturedAt: Date(timeIntervalSince1970: .infinity)
        ))
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
