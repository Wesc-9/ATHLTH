import XCTest
import Foundation
@testable import ATHLTH

final class WearableDisplaySourcePolicyTests: XCTestCase {
    func testAutomaticPrefersAppleWhenPresentAndNeverAddsSources() {
        XCTAssertNil(WearableDisplaySourcePolicy.garminReading(metric: .steps, apple: 4000, garmin: 5000, preference: .automatic))
        XCTAssertEqual(WearableDisplaySourcePolicy.garminReading(metric: .steps, apple: nil, garmin: 5000, preference: .automatic)?.value, 5000)
        XCTAssertNil(WearableDisplaySourcePolicy.garminReading(metric: .steps, apple: 0, garmin: 5000, preference: .automatic))
    }
    func testIndependentMetricPreferencesDoNotAddOrAverageSources() {
        XCTAssertEqual(WearableDisplaySourcePolicy.garminReading(metric: .sleep, apple: 24000, garmin: 28000, preference: .garmin)?.value, 28000)
        XCTAssertNil(WearableDisplaySourcePolicy.garminReading(metric: .restingHeartRate, apple: 48, garmin: 52, preference: .appleHealth))
        XCTAssertEqual(WearableDisplaySourcePolicy.garminReading(metric: .hrv, apple: 42, garmin: 60, preference: .garmin)?.sourceLabel, "Garmin natt")
    }

    func testWatchDiagnosticDeviceInfoRoundTrip() throws {
        let source = ATHLTHWatchDeviceDiagnostics(model: "Apple Watch", systemVersion: "27.2", appVersion: "3.0.2")
        XCTAssertEqual(try JSONDecoder().decode(ATHLTHWatchDeviceDiagnostics.self, from: JSONEncoder().encode(source)), source)
        XCTAssertNotEqual(ATHLTHWatchDiagnosticTransport.kind, WatchPreparedWorkoutTransport.kind)
    }

    func testGarminPreferenceAndInvalidData() {
        XCTAssertEqual(WearableDisplaySourcePolicy.garminReading(metric: .sleep, apple: 25000, garmin: 27000, preference: .garmin)?.value, 27000)
        XCTAssertNil(WearableDisplaySourcePolicy.garminReading(metric: .hrv, apple: 40, garmin: .nan, preference: .garmin))
        XCTAssertNil(WearableDisplaySourcePolicy.garminReading(metric: .sleep, apple: nil, garmin: 0, preference: .garmin))
        XCTAssertEqual(WearableDisplaySourcePolicy.garminReading(metric: .hrv, apple: nil, garmin: 50, preference: .automatic)?.sourceLabel, "Garmin natt")
    }
}
