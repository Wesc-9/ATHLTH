import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHGhostPaceTimeConversionTests: XCTestCase {
    func testTimePopulatesPaceForSelectedRoute() {
        // Screenshot example: 1:43:20 over approximately 7.45 km.
        let pace = ATHLTHGhostPaceTimeConversion.paceText(
            duration: 6_200, distanceKilometers: 6_200 / 832
        )
        XCTAssertEqual(pace, "13:52")
    }

    func testPacePopulatesTime() {
        var draft = GhostQuickStartDraft()
        draft.enabled = true
        draft.setTargetPaceText("5:30", distanceKilometers: 10)

        XCTAssertEqual(draft.targetTimeText,
                       GhostTargetTimeFormatter.string(3_300))
        XCTAssertEqual(draft.targetDuration, 3_300)
        XCTAssertEqual(draft.targetPaceText, "5:30")
    }

    func testChangingTimeUpdatesPaceImmediately() {
        var draft = GhostQuickStartDraft()
        draft.enabled = true
        draft.setTargetTimeText(
            GhostTargetTimeFormatter.string(3_600),
            distanceKilometers: 12
        )

        XCTAssertEqual(draft.targetPaceText, "5:00")
        XCTAssertEqual(draft.targetDuration, 3_600)
    }

    func testEditedPaceRoundsDurationToNearestSecond() {
        let duration = ATHLTHGhostPaceTimeConversion.targetDuration(
            paceText: "13:52 /km", distanceKilometers: 7.45
        )
        XCTAssertEqual(duration, 6_198)
    }

    func testInvalidPaceNeverLaunchesWithPreviousStaleTime() {
        var draft = GhostQuickStartDraft()
        draft.enabled = true
        draft.setTargetPaceText("5:30", distanceKilometers: 10)
        XCTAssertNotNil(draft.targetDuration)

        draft.setTargetPaceText("5:99", distanceKilometers: 10)
        XCTAssertEqual(draft.targetPaceText, "5:99")
        XCTAssertNil(draft.targetDuration)
        XCTAssertEqual(draft.targetTimeText, "")

        draft.setTargetPaceText("6:00", distanceKilometers: 10)
        XCTAssertEqual(draft.targetDuration, 3_600)
    }

    func testInvalidTimeDoesNotLeaveMisleadingPace() {
        var draft = GhostQuickStartDraft()
        draft.enabled = true
        draft.setTargetTimeText("45:00", distanceKilometers: 9)
        XCTAssertEqual(draft.targetPaceText, "5:00")
        draft.setTargetTimeText("", distanceKilometers: 9)
        XCTAssertEqual(draft.targetPaceText, "")
        XCTAssertNil(draft.targetDuration)
    }

    func testNoValidRouteDistanceCannotProducePaceOrTarget() {
        XCTAssertNil(ATHLTHGhostPaceTimeConversion.paceText(
            duration: 1_800, distanceKilometers: 0
        ))
        XCTAssertNil(ATHLTHGhostPaceTimeConversion.targetDuration(
            paceText: "5:00", distanceKilometers: 0
        ))
        XCTAssertNil(ATHLTHGhostPaceTimeConversion.targetDuration(
            paceText: "5:00", distanceKilometers: .nan
        ))
        XCTAssertNil(ATHLTHGhostPaceTimeConversion.paceSeconds(
            from: "100000000000000000000000000:00"
        ))
    }
}
