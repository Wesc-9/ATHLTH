import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHIndoorRunDetectionTests: XCTestCase {
    private let started = Date(timeIntervalSince1970: 1_700_000_000)

    private func qualifies(
        seconds: TimeInterval = 901,
        meters: Double = 99,
        firstFixOffset: TimeInterval? = 30,
        lastFixOffset: TimeInterval? = 900,
        fixes: Int = 28,
        outdoor: Bool = true,
        paused: Bool = false,
        route: Bool = false,
        prompted: Bool = false
    ) -> Bool {
        ATHLTHIndoorRunDetection.shouldOffer(
            elapsedWallSeconds: seconds,
            acceptedDistanceMeters: meters,
            firstReliableFix: firstFixOffset.map { started.addingTimeInterval($0) },
            lastReliableFix: lastFixOffset.map { started.addingTimeInterval($0) },
            acceptedFixCount: fixes,
            now: started.addingTimeInterval(seconds),
            isOutdoor: outdoor,
            manualPause: paused,
            hasPlannedRouteOrGhost: route,
            alreadyPrompted: prompted
        )
    }

    func testOffersAtFifteenMinutesWithLessThan100MetresOfActualGPSDistance() {
        XCTAssertTrue(qualifies())
        XCTAssertFalse(qualifies(seconds: 899))
        XCTAssertTrue(qualifies(meters: 100))
        XCTAssertFalse(qualifies(meters: 120))
    }

    func testMissingUnreliableOrShortGPSSampleHistoryNeverOffers() {
        XCTAssertFalse(qualifies(firstFixOffset: nil))
        XCTAssertFalse(qualifies(lastFixOffset: nil))
        XCTAssertFalse(qualifies(fixes: 2))
        XCTAssertFalse(qualifies(firstFixOffset: 220))
        XCTAssertFalse(qualifies(seconds: 1_050, lastFixOffset: 900))
    }

    func testNeverPromptsIndoorsPausedOrTwiceAndSkipsPlannedRoutes() {
        XCTAssertFalse(qualifies(outdoor: false))
        XCTAssertFalse(qualifies(paused: true))
        XCTAssertFalse(qualifies(prompted: true))
        XCTAssertFalse(qualifies(route: true))
    }

    func testExactlyTwoIndoorVenueChoices() {
        XCTAssertEqual(Set(ATHLTHIndoorRunVenue.allCases),
                       Set([.treadmill, .indoorRunning]))
    }
}
