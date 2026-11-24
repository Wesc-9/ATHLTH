import XCTest
@testable import ATHLTH

final class ATHLTHGarminOfflineCoachPlanTests: XCTestCase {
    private var basic: WatchAudioCoachConfiguration {
        var value = WatchAudioCoachConfiguration.disabled
        value.enabled = true
        value.language = .norwegian
        value.duckOtherAudio = false
        value.muteOtherAudio = false
        return value
    }

    func testSharedConfigurationAndExplicitDeveloperVoice() throws {
        let plan = try ATHLTHGarminOfflineCoachPlan(configuration: basic,
            sport: .running, resolvedLanguage: .norwegian, developerVoiceExplicitlyAccepted: true)
        XCTAssertEqual(plan.language, "nb-NO")
        XCTAssertTrue(plan.start)
        XCTAssertEqual(plan.message["pack"] as? String, "developer-v1")
        let request = ATHLTHGarminLiveRequest(sport: .running, offlineCoach: plan)
        XCTAssertEqual(request.message["v"] as? Int, 4)
        XCTAssertEqual(request.message["recipeVersion"] as? Int, 1)
        XCTAssertThrowsError(try ATHLTHGarminOfflineCoachPlan(configuration: basic,
            sport: .running, resolvedLanguage: .norwegian, developerVoiceExplicitlyAccepted: false))
    }

    func testRejectsMissingVoiceAndUnsupportedReadout() {
        var c = basic
        c.voiceIdentifier = "chosen-voice"
        XCTAssertThrowsError(try ATHLTHGarminOfflineCoachPlan(configuration: c,
            sport: .running, resolvedLanguage: .norwegian, developerVoiceExplicitlyAccepted: true))
        c = basic
        c.announceHeartRate = true
        c.timeIntervalSeconds = 60
        XCTAssertThrowsError(try ATHLTHGarminOfflineCoachPlan(configuration: c,
            sport: .running, resolvedLanguage: .norwegian, developerVoiceExplicitlyAccepted: true))
    }

    func testCountdownAndHandshakeRequireCoachVersion() throws {
        var c = basic
        c.intervalCountdownToRecoverySeconds = 10
        c.intervalAfterCountdownToRecovery = .numbersOnly
        let plan = try ATHLTHGarminOfflineCoachPlan(configuration: c,
            sport: .running, resolvedLanguage: .norwegian, developerVoiceExplicitlyAccepted: true)
        XCTAssertEqual(plan.toRecovery, 10)
        let request = ATHLTHGarminLiveRequest(sport: .running, offlineCoach: plan)
        let device = UUID()
        var handshake = ATHLTHGarminLiveHandshake(request: request, deviceID: device)
        func event(_ v: Int, status: String?) throws -> ATHLTHGarminLiveEvent {
            var message: [String: Any] = ["v": v, "kind": "event", "id": request.id.uuidString,
                "seq": 1, "state": "recording"]
            if let status { message["coachStatus"] = status }
            return try XCTUnwrap(ATHLTHGarminLiveEvent(message: message))
        }
        XCTAssertFalse(handshake.receive(try event(1, status: nil), from: device))
        XCTAssertFalse(handshake.receive(try event(4, status: nil), from: device))
        XCTAssertTrue(handshake.receive(try event(4, status: "ready"), from: device))
    }
}
