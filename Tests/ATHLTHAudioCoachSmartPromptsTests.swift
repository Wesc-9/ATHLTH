import XCTest
@testable import ATHLTH

final class ATHLTHAudioCoachSmartPromptsTests: XCTestCase {
    func testMotivationIsOptInAndDoesNotRepeatWithinOneSlot() {
        var state = ATHLTHAudioCoachSmartState()
        var config = ATHLTHAudioCoachSmartSettings()

        XCTAssertNil(state.nextMotivation(
            settings: config, elapsed: 60,
            paceSecondsPerKilometer: nil, norwegian: true
        ))

        config.motivationEnabled = true
        XCTAssertNotNil(state.nextMotivation(
            settings: config, elapsed: 120,
            paceSecondsPerKilometer: nil, norwegian: true
        ))
        XCTAssertNil(state.nextMotivation(
            settings: config, elapsed: 120.9,
            paceSecondsPerKilometer: nil, norwegian: true
        ))
    }

    func testMeasuredPaceFeedbackNeverInventsPersonalBest() {
        var state = ATHLTHAudioCoachSmartState()
        var config = ATHLTHAudioCoachSmartSettings()
        config.motivationEnabled = true

        _ = state.nextMotivation(
            settings: config, elapsed: 60,
            paceSecondsPerKilometer: 315, norwegian: true
        )
        let faster = state.nextMotivation(
            settings: config, elapsed: 120,
            paceSecondsPerKilometer: 280, norwegian: true
        )

        XCTAssertTrue(faster?.contains("økt farten") == true)
        XCTAssertFalse(faster?.localizedCaseInsensitiveContains(
            "personlig rekord"
        ) == true)
    }

    func testRandomEncouragementVariesAndHasBoundedCadence() {
        var state = ATHLTHAudioCoachSmartState()
        var config = ATHLTHAudioCoachSmartSettings()
        config.randomEncouragementEnabled = true
        config.randomIntervalSeconds = 90
        var delivered: [String] = []
        for elapsed in stride(from: 0.0, through: 1400, by: 1.0) {
            if let message = state.nextMotivation(
                settings: config, elapsed: elapsed,
                paceSecondsPerKilometer: nil, norwegian: false
            ) {
                delivered.append(message)
            }
        }
        XCTAssertGreaterThanOrEqual(delivered.count, 8)
        for (index, message) in delivered.enumerated() {
            let previous = delivered[max(0, index - 8)..<index]
            XCTAssertFalse(previous.contains(message))
        }
    }

    func testLandmarkNeedsAccurateFreshGPSAndIsAnnouncedOnce() {
        var state = ATHLTHAudioCoachSmartState()
        var config = ATHLTHAudioCoachSmartSettings()
        config.landmarks = [
            ATHLTHCoachLandmark(
                name: "Eiffel Tower", latitude: 48.8584,
                longitude: 2.2945, side: .left
            )
        ]

        func message(
            accuracy: Double,
            age: TimeInterval
        ) -> String? {
            state.nextLandmark(
                settings: config, latitude: 48.8584,
                longitude: 2.2945, horizontalAccuracy: accuracy,
                locationAge: age, norwegian: true
            )
        }

        XCTAssertNil(message(accuracy: 80, age: 1))
        XCTAssertNil(message(accuracy: 5, age: 100))
        XCTAssertTrue(message(accuracy: 5, age: 1)?
            .contains("venstre side") == true)
        XCTAssertNil(message(accuracy: 5, age: 1))
    }

    func testFullCoachProfileSurvivesEncoding() throws {
        var config = WatchAudioCoachConfiguration.disabled
        config.enabled = true
        var smart = ATHLTHAudioCoachSmartSettings()
        smart.motivationEnabled = true
        smart.randomEncouragementEnabled = true
        smart.customEncouragements = ["Keep it going!"]
        smart.landmarks = [
            ATHLTHCoachLandmark(
                name: "Bridge", latitude: 60.0,
                longitude: 10.0, side: .right
            )
        ]
        config.smartPrompts = smart
        config.customRules = [
            ATHLTHAudioCoachRule(
                trigger: .time, metric: .pace, interval: 30
            )
        ]
        let profile = ATHLTHAudioCoachProfile(
            name: "Ved intervall", configuration: config
        )
        let decoded = try JSONDecoder().decode(
            ATHLTHAudioCoachProfile.self,
            from: JSONEncoder().encode(profile)
        )
        XCTAssertEqual(decoded, profile)
        XCTAssertEqual(decoded.configuration.smartPrompts?.landmarks.count, 1)
        XCTAssertEqual(decoded.configuration.customRules?.first?.interval, 30)
    }

    func testOldWatchConfigurationWithoutSmartFieldsStillDecodes() throws {
        let legacy = WatchAudioCoachConfiguration.disabled
        let data = try JSONEncoder().encode(legacy)
        let restored = try JSONDecoder().decode(
            WatchAudioCoachConfiguration.self, from: data
        )
        XCTAssertNil(restored.smartPrompts)
    }
}
