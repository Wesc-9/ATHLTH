import CoreLocation
import XCTest
@testable import ATHLTH

final class ATHLTHAudioCoachSmartPromptsTests: XCTestCase {
    func testZoneWarningTimingSupportsOneMinuteIntervalsAndOldProfiles() throws {
        var settings = ATHLTHAudioCoachSmartSettings()
        XCTAssertEqual(settings.resolvedTargetZoneGrace, 10)
        XCTAssertEqual(settings.resolvedTargetZoneRepeat, 120)

        settings.targetZoneGraceSeconds = 5
        settings.targetZoneRepeatSeconds = 30
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(
            ATHLTHAudioCoachSmartSettings.self, from: data
        )
        XCTAssertEqual(decoded.resolvedTargetZoneGrace, 5)
        XCTAssertEqual(decoded.resolvedTargetZoneRepeat, 30)

        settings.targetZoneGraceSeconds = -5
        settings.targetZoneRepeatSeconds = 10_000
        XCTAssertEqual(settings.resolvedTargetZoneGrace, 5)
        XCTAssertEqual(settings.resolvedTargetZoneRepeat, 600)
    }

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

    func testPraisePushAndEncouragementHaveDistinctVariedBanks() {
        for style in ATHLTHCoachEncouragementStyle.allCases {
            var state = ATHLTHAudioCoachSmartState()
            var config = ATHLTHAudioCoachSmartSettings()
            config.motivationEnabled = true
            config.motivationIntervalSeconds = 60
            config.encouragementStyle = style
            config.contextualFeedbackEnabled = false
            var spoken: [String] = []
            for minute in 1...12 {
                let result = state.nextMotivation(
                    settings: config,
                    elapsed: Double(minute * 60),
                    paceSecondsPerKilometer: nil,
                    norwegian: true
                )
                if let result { spoken.append(result) }
            }
            XCTAssertEqual(spoken.count, 12)
            for index in spoken.indices {
                XCTAssertFalse(
                    spoken[max(0, index - 8)..<index].contains(spoken[index]),
                    "Style \(style) repeated a phrase too early"
                )
            }
        }
    }

    func testMeasuredFasterPaceHasDifferentFeedbackEachMinute() {
        var state = ATHLTHAudioCoachSmartState()
        var config = ATHLTHAudioCoachSmartSettings()
        config.motivationEnabled = true
        let paceValues: [Double] = [360, 330, 300, 275, 250]
        let spoken = paceValues.enumerated().compactMap { index, pace in
            state.nextMotivation(
                settings: config,
                elapsed: Double((index + 1) * 60),
                paceSecondsPerKilometer: pace,
                norwegian: true
            )
        }
        XCTAssertEqual(spoken.count, 5)
        XCTAssertTrue(spoken.dropFirst().allSatisfy {
            $0.contains("økt farten")
        })
        XCTAssertEqual(Set(spoken.dropFirst()).count, 4)
    }

    func testDisablingEnvironmentalContextRetainsMeasuredPaceFeedback() {
        var state = ATHLTHAudioCoachSmartState()
        var config = ATHLTHAudioCoachSmartSettings()
        config.motivationEnabled = true
        config.contextualFeedbackEnabled = false
        _ = state.nextMotivation(
            settings: config, elapsed: 60,
            paceSecondsPerKilometer: 330, norwegian: true
        )
        let faster = state.nextMotivation(
            settings: config, elapsed: 120,
            paceSecondsPerKilometer: 300, norwegian: true,
            environment: .init(
                routeRemainingMeters: 60,
                routeProgressPercent: 98,
                terrain: .uphill
            )
        )
        XCTAssertTrue(faster?.contains("økt farten") == true)
    }

    func testLastStretchUsesVerifiedRouteProgressNotJustDistance() {
        var state = ATHLTHAudioCoachSmartState()
        var config = ATHLTHAudioCoachSmartSettings()
        config.motivationEnabled = true

        let early = state.nextMotivation(
            settings: config, elapsed: 60,
            paceSecondsPerKilometer: nil, norwegian: true,
            environment: .init(
                routeRemainingMeters: 80, routeProgressPercent: 4
            )
        )
        XCTAssertFalse(early?.contains("siste del av ruten") == true)

        let finish = state.nextMotivation(
            settings: config, elapsed: 120,
            paceSecondsPerKilometer: nil, norwegian: true,
            environment: .init(
                routeRemainingMeters: 80, routeProgressPercent: 97
            )
        )
        XCTAssertTrue(
            ["mål", "siste", "fremme"].contains {
                finish?.localizedCaseInsensitiveContains($0) == true
            }
        )
        let second = state.nextMotivation(
            settings: config, elapsed: 180,
            paceSecondsPerKilometer: nil, norwegian: true,
            environment: .init(
                routeRemainingMeters: 50, routeProgressPercent: 98
            )
        )
        XCTAssertNotEqual(finish, second)
    }

    func testRealUphillRequiresFreshAccurateElevationAndDistance() {
        var state = ATHLTHAudioCoachSmartState()
        let base = Date(timeIntervalSince1970: 1_790_000_000)
        func sample(
            latitude: Double, altitude: Double,
            verticalAccuracy: Double, time: TimeInterval
        ) -> CLLocation {
            CLLocation(
                coordinate: CLLocationCoordinate2D(
                    latitude: latitude, longitude: 10.4
                ),
                altitude: altitude,
                horizontalAccuracy: 6,
                verticalAccuracy: verticalAccuracy,
                timestamp: base.addingTimeInterval(time)
            )
        }
        state.observeTerrain(
            location: sample(latitude: 63.43, altitude: 12,
                             verticalAccuracy: 3, time: 0),
            now: base.addingTimeInterval(1)
        )
        state.observeTerrain(
            location: sample(latitude: 63.431, altitude: 35,
                             verticalAccuracy: 3, time: 10),
            now: base.addingTimeInterval(11)
        )
        XCTAssertEqual(state.inferredTerrain, .uphill)

        state.observeTerrain(
            location: sample(latitude: 63.432, altitude: 8,
                             verticalAccuracy: 50, time: 20),
            now: base.addingTimeInterval(21)
        )
        XCTAssertNil(state.inferredTerrain)
    }

    func testHomeAndSeaAreOnlySpokenForExplicitPinnedLocations() {
        var state = ATHLTHAudioCoachSmartState()
        var config = ATHLTHAudioCoachSmartSettings()
        config.landmarks = [
            ATHLTHCoachLandmark(
                name: "Bryggen", latitude: 63.43,
                longitude: 10.4, side: .unspecified,
                kind: .waterfront
            )
        ]
        let nearWater = state.nextLandmark(
            settings: config, latitude: 63.43, longitude: 10.4,
            horizontalAccuracy: 5, locationAge: 1, norwegian: true
        )
        XCTAssertTrue(nearWater?.contains("Sjøen") == true)
        XCTAssertNil(state.nextLandmark(
            settings: config, latitude: 63.43, longitude: 10.4,
            horizontalAccuracy: 5, locationAge: 1, norwegian: true
        ))
        config.landmarks = [
            ATHLTHCoachLandmark(
                name: "Hjem", latitude: 63.44, longitude: 10.4,
                side: .unspecified, kind: .home
            )
        ]
        XCTAssertNil(state.nextLandmark(
            settings: config, latitude: 63.43, longitude: 10.4,
            horizontalAccuracy: 5, locationAge: 1, norwegian: true
        ))
        XCTAssertNil(state.nextLandmark(
            settings: config, latitude: 63.44, longitude: 10.4,
            horizontalAccuracy: 5, locationAge: 1, norwegian: true,
            elapsedSeconds: 60, routeProgressPercent: 3
        ))
        XCTAssertNil(state.nextLandmark(
            settings: config, latitude: 63.44, longitude: 10.4,
            horizontalAccuracy: 5, locationAge: 1, norwegian: true,
            elapsedSeconds: 1_200, routeProgressPercent: 40
        ))
        XCTAssertTrue(state.nextLandmark(
            settings: config, latitude: 63.44, longitude: 10.4,
            horizontalAccuracy: 5, locationAge: 1, norwegian: true,
            elapsedSeconds: 1_200, routeProgressPercent: 97
        )?.contains("hjemme") == true)
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

    func testReactiveCueSuppressesSameSlotAutomaticMotivation() {
        var state = ATHLTHAudioCoachSmartState()
        var settings = ATHLTHAudioCoachSmartSettings()
        settings.motivationEnabled = true
        settings.motivationIntervalSeconds = 60
        settings.randomEncouragementEnabled = true
        settings.randomIntervalSeconds = 120

        state.noteExternalPrompt(elapsed: 60, settings: settings)
        XCTAssertNil(state.nextMotivation(
            settings: settings, elapsed: 60.5,
            paceSecondsPerKilometer: 350, norwegian: true
        ))
        XCTAssertNil(state.nextMotivation(
            settings: settings, elapsed: 90,
            paceSecondsPerKilometer: 350, norwegian: true
        ))
        XCTAssertNotNil(state.nextMotivation(
            settings: settings, elapsed: 120,
            paceSecondsPerKilometer: 350, norwegian: true
        ))
    }

    func testReactiveCueResetClearsAntiOverlapState() {
        var state = ATHLTHAudioCoachSmartState()
        var settings = ATHLTHAudioCoachSmartSettings()
        settings.motivationEnabled = true
        state.noteExternalPrompt(elapsed: 60, settings: settings)
        state.reset()
        XCTAssertNotNil(state.nextMotivation(
            settings: settings, elapsed: 60,
            paceSecondsPerKilometer: nil, norwegian: true
        ))
    }
}
