import XCTest
@testable import ATHLTH

final class ATHLTHRouteWarmupConfigurationTests: XCTestCase {
    private let routeAlerts = WatchRouteAlertConfiguration.standard

    func testWarmupOffPreservesOrdinaryRouteRun() {
        let setup = ATHLTHRouteWarmupConfiguration.disabled
        XCTAssertNil(setup.runningTransfer(
            title: "Park loop",
            routeAlerts: routeAlerts,
            autoPauseEnabled: true
        ))
    }

    func testTimedWarmupCanAdvanceAutomatically() {
        let setup = ATHLTHRouteWarmupConfiguration(
            enabled: true, durationMinutes: 10, autoStartMain: true
        )
        let transfer = setup.runningTransfer(
            title: "Park loop",
            routeAlerts: routeAlerts,
            autoPauseEnabled: true
        )
        XCTAssertEqual(transfer?.steps.count, 2)
        XCTAssertEqual(transfer?.steps.first?.phase, "warmup")
        XCTAssertEqual(transfer?.steps.first?.measure, .time)
        XCTAssertEqual(transfer?.steps.first?.durationSeconds, 600)
        XCTAssertEqual(transfer?.steps.last?.measure, .open)
        XCTAssertEqual(transfer?.steps.last?.phase, "work")
        XCTAssertEqual(transfer?.autoStartMainAfterWarmup, true)
        XCTAssertEqual(transfer?.autoAdvanceTimedSteps, true)
    }

    func testTimedWarmupCanRequireManualStart() {
        let setup = ATHLTHRouteWarmupConfiguration(
            enabled: true, durationMinutes: 15, autoStartMain: false
        )
        let transfer = setup.runningTransfer(
            title: "Park loop",
            routeAlerts: routeAlerts,
            autoPauseEnabled: false
        )
        XCTAssertEqual(transfer?.steps.first?.durationSeconds, 900)
        XCTAssertEqual(transfer?.autoStartMainAfterWarmup, false)
    }

    func testOpenWarmupAlwaysRequiresManualStart() {
        let setup = ATHLTHRouteWarmupConfiguration(
            enabled: true, durationMinutes: 0, autoStartMain: true
        )
        let transfer = setup.runningTransfer(
            title: "Park loop",
            routeAlerts: routeAlerts,
            autoPauseEnabled: true
        )
        XCTAssertEqual(transfer?.steps.first?.measure, .open)
        XCTAssertNil(transfer?.steps.first?.durationSeconds)
        XCTAssertEqual(transfer?.autoStartMainAfterWarmup, false)
    }
}
