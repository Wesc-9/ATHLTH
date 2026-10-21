import XCTest
@testable import ATHLTH

final class RunRouteMapPointModeTests: XCTestCase {
    func testAutomaticTapUsesStartThenFinishThenVia() {
        XCTAssertEqual(
            RunRouteMapPointMode.resolve(mode: .automatic, hasStart: false, hasFinish: false),
            .start
        )
        XCTAssertEqual(
            RunRouteMapPointMode.resolve(mode: .automatic, hasStart: true, hasFinish: false),
            .finish
        )
        XCTAssertEqual(
            RunRouteMapPointMode.resolve(mode: .automatic, hasStart: true, hasFinish: true),
            .via
        )
    }

    func testResolvedMapAddressUsesStreetAndLocality() {
        XCTAssertEqual(
            RunRouteAddressPresentation.name(
                street: "Storgata 12", fallbackName: "Storgata",
                locality: "Fauske"),
            "Storgata 12, Fauske"
        )
    }

    func testResolvedMapPlaceAvoidsRepeatingLocality() {
        XCTAssertEqual(
            RunRouteAddressPresentation.name(
                street: "", fallbackName: "Fauske", locality: "Fauske"),
            "Fauske"
        )
        XCTAssertEqual(
            RunRouteAddressPresentation.name(
                street: "", fallbackName: "Hauan idrettspark",
                locality: "Fauske"),
            "Hauan idrettspark, Fauske"
        )
    }

    func testFailedGeocodeNeverInventsAddress() {
        XCTAssertNil(RunRouteAddressPresentation.name(
            street: "", fallbackName: nil, locality: nil))
        XCTAssertEqual(RunRouteAddressPresentation.name(
            street: "", fallbackName: nil, locality: "Fauske"), "Fauske")
    }

    func testSearchRetainsDistancesWhenKeyboardDismissalSendsEmptyResults() {
        XCTAssertFalse(RunRouteSearchSuggestionPolicy.shouldReplaceResults(
            query: "Esso",
            currentKeys: ["Esso|Storgaten 57, Fauske"],
            incomingKeys: []
        ))
    }

    func testSearchAvoidsResettingDistancesForIdenticalResults() {
        let keys = ["Esso|Storgaten 57, Fauske", "Esso|Melilli, Italia"]
        XCTAssertFalse(RunRouteSearchSuggestionPolicy.shouldReplaceResults(
            query: "Esso", currentKeys: keys, incomingKeys: keys
        ))
    }

    func testSearchReplacesResultsForNewAddressesButNotEmptyQuery() {
        XCTAssertTrue(RunRouteSearchSuggestionPolicy.shouldReplaceResults(
            query: "Esso",
            currentKeys: ["Esso|Storgaten 57, Fauske"],
            incomingKeys: ["Esso|Storgaten 57, Fauske", "Esso|Melilli, Italia"]
        ))
        XCTAssertFalse(RunRouteSearchSuggestionPolicy.shouldReplaceResults(
            query: " ", currentKeys: [], incomingKeys: ["Esso|Melilli, Italia"]
        ))
    }

    func testSelectedPointModeOverridesAutomaticOrder() {
        XCTAssertEqual(
            RunRouteMapPointMode.resolve(mode: .start, hasStart: true, hasFinish: true),
            .start
        )
        XCTAssertEqual(
            RunRouteMapPointMode.resolve(mode: .finish, hasStart: false, hasFinish: false),
            .finish
        )
        XCTAssertEqual(
            RunRouteMapPointMode.resolve(mode: .via, hasStart: true, hasFinish: true),
            .via
        )
    }
}
