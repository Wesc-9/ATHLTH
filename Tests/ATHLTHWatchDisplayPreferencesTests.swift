import XCTest
@testable import ATHLTH

final class ATHLTHWatchDisplayPreferencesTests: XCTestCase {
    func testDefaultWorkoutHierarchyIsPreserved() {
        let config = ATHLTHLiveWorkoutSurfaceConfiguration.standard
        XCTAssertFalse(ATHLTHWatchDisplayPreferences.prefersDistance(
            kind: .running, configuration: config
        ))
        XCTAssertTrue(ATHLTHWatchDisplayPreferences.prefersDistance(
            kind: .walking, configuration: config
        ))
        XCTAssertEqual(ATHLTHWatchDisplayPreferences.startingRunPage(
            configuration: config, audioCoachAvailable: false
        ), 0)
        XCTAssertFalse(ATHLTHWatchDisplayPreferences.hidesAlwaysOnDetails(config))
    }

    func testUserCanChoosePrimaryMetricAcrossRunAndWalk() {
        var config = ATHLTHLiveWorkoutSurfaceConfiguration.standard
        config.preferredRunMetricRaw = "distance"
        XCTAssertTrue(ATHLTHWatchDisplayPreferences.prefersDistance(
            kind: .running, configuration: config
        ))
        config.preferredRunMetricRaw = "pace"
        XCTAssertFalse(ATHLTHWatchDisplayPreferences.prefersDistance(
            kind: .walking, configuration: config
        ))
        config.preferredRunMetricRaw = "invalid"
        XCTAssertTrue(ATHLTHWatchDisplayPreferences.prefersDistance(
            kind: .walking, configuration: config
        ))
    }

    func testUnavailableCoachFallsBackToLiveMetrics() {
        var config = ATHLTHLiveWorkoutSurfaceConfiguration.standard
        config.preferredRunPageRaw = "coach"
        XCTAssertEqual(ATHLTHWatchDisplayPreferences.startingRunPage(
            configuration: config, audioCoachAvailable: false
        ), 0)
        XCTAssertEqual(ATHLTHWatchDisplayPreferences.startingRunPage(
            configuration: config, audioCoachAvailable: true
        ), 8)
        config.preferredRunPageRaw = "pulse"
        XCTAssertEqual(ATHLTHWatchDisplayPreferences.startingRunPage(
            configuration: config, audioCoachAvailable: false
        ), 7)
    }

    func testPrivacyAndContrastAreOptIn() {
        var config = ATHLTHLiveWorkoutSurfaceConfiguration.standard
        config.privateAlwaysOn = true
        config.strongWatchContrast = true
        XCTAssertTrue(ATHLTHWatchDisplayPreferences.hidesAlwaysOnDetails(config))
        XCTAssertTrue(ATHLTHWatchDisplayPreferences.prefersStrongContrast(config))
    }

    func testOptionalFieldsRoundTripAndDecodeOldConfiguration() throws {
        let old = ATHLTHLiveWorkoutSurfaceConfiguration.standard
        let legacy = try JSONEncoder().encode(old)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: legacy) as? [String: Any])
        object.removeValue(forKey: "preferredRunMetricRaw")
        object.removeValue(forKey: "preferredRunPageRaw")
        object.removeValue(forKey: "strongWatchContrast")
        object.removeValue(forKey: "privateAlwaysOn")
        let bytes = try JSONSerialization.data(withJSONObject: object)
        let restored = try JSONDecoder().decode(
            ATHLTHLiveWorkoutSurfaceConfiguration.self, from: bytes
        )
        XCTAssertNil(restored.privateAlwaysOn)
        XCTAssertEqual(restored.dynamicIslandEnabled, old.dynamicIslandEnabled)
    }
}
