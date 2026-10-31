import XCTest
@testable import ATHLTH

final class ATHLTHCoachRouteIntentTests: XCTestCase {
    func testUnderstandsNorwegianRequestWithoutPretendingToHaveRoute() {
        let prompt = "Kan du lage en løperute på 7,5 km grus nær sentrum?"
        XCTAssertTrue(ATHLTHCoachRouteIntent.isRequest(prompt))
        let brief = ATHLTHCoachRouteIntent.initialBrief(from: prompt)
        XCTAssertEqual(brief.distanceKilometers, 7.5)
        XCTAssertEqual(brief.surface, .gravel)
        XCTAssertEqual(brief.setting, .central)
    }

    func testTimeOnlyAndNearbyStart() {
        let prompt = "Finn en rute i nærheten, 45 minutter på sti"
        XCTAssertTrue(ATHLTHCoachRouteIntent.isRequest(prompt))
        let brief = ATHLTHCoachRouteIntent.initialBrief(from: prompt)
        XCTAssertFalse(brief.useDistance)
        XCTAssertTrue(brief.useDuration)
        XCTAssertEqual(brief.durationMinutes, 45)
        XCTAssertEqual(brief.startMode, .nearby)
        XCTAssertEqual(brief.surface, .path)
    }

    func testNotTriggeredForUnrelatedOrCyclingRequest() {
        XCTAssertFalse(ATHLTHCoachRouteIntent.isRequest("Hva er ruten min i dag?"))
        XCTAssertFalse(ATHLTHCoachRouteIntent.isRequest("Lag en sykkelrute"))
    }

    func testRejectsMissingLengthAndTime() {
        var brief = ATHLTHCoachRouteBrief()
        brief.useDistance = false
        brief.useDuration = false
        XCTAssertNotNil(brief.validationMessage)
    }

    func testDurationToDistanceUsesChosenPace() {
        var brief = ATHLTHCoachRouteBrief()
        brief.useDistance = false
        brief.useDuration = true
        brief.durationMinutes = 30
        brief.paceMinutesPerKilometer = 6
        XCTAssertEqual(brief.targetMeters, 5000)
    }
}
