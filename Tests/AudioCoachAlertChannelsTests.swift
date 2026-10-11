import XCTest
@testable import ATHLTH

final class AudioCoachAlertChannelsTests: XCTestCase {
    func testCriticalBothChannelsRemainIndependent() {
        let both = ATHLTHCoachAlertChannels.resolve(
            delivery: .both,
            voiceEnabled: false,
            hapticsEnabled: true,
            hapticPermittedByPriority: true
        )
        XCTAssertFalse(both.voice)
        XCTAssertTrue(both.haptic)

        let opposite = ATHLTHCoachAlertChannels.resolve(
            delivery: .both,
            voiceEnabled: true,
            hapticsEnabled: false,
            hapticPermittedByPriority: true
        )
        XCTAssertTrue(opposite.voice)
        XCTAssertFalse(opposite.haptic)
    }

    func testVoiceOnlyAndHapticOnlyRespectUserChoice() {
        let voice = ATHLTHCoachAlertChannels.resolve(
            delivery: .voice,
            voiceEnabled: true,
            hapticsEnabled: true,
            hapticPermittedByPriority: true
        )
        XCTAssertTrue(voice.voice)
        XCTAssertFalse(voice.haptic)

        let haptic = ATHLTHCoachAlertChannels.resolve(
            delivery: .haptic,
            voiceEnabled: true,
            hapticsEnabled: true,
            hapticPermittedByPriority: true
        )
        XCTAssertFalse(haptic.voice)
        XCTAssertTrue(haptic.haptic)
    }

    func testQuietHapticGateNeverDisablesSelectedVoice() {
        let channels = ATHLTHCoachAlertChannels.resolve(
            delivery: .both,
            voiceEnabled: true,
            hapticsEnabled: true,
            hapticPermittedByPriority: false
        )
        XCTAssertTrue(channels.voice)
        XCTAssertFalse(channels.haptic)
    }

    func testBothDisabledNeverProducesAnAlert() {
        let channels = ATHLTHCoachAlertChannels.resolve(
            delivery: .both,
            voiceEnabled: false,
            hapticsEnabled: false,
            hapticPermittedByPriority: true
        )
        XCTAssertFalse(channels.voice)
        XCTAssertFalse(channels.haptic)
    }

    func testBilateralReceiptsSuppressOnlyMatchingWorkoutCue() throws {
        let time = Date(timeIntervalSince1970: 15_000)
        let start = time.addingTimeInterval(-120)
        var watchLedger = ATHLTHCoachEventLedger()
        var phoneLedger = ATHLTHCoachEventLedger()

        let watchStep = ATHLTHCoachEvent(
            kind: .runningStep,
            key: "2",
            priority: .structuredStep,
            createdAt: time,
            validFor: 10
        )
        watchLedger.didDeliver(watchStep, now: time)
        let watchReceipt = ATHLTHCoachDeliveryReceipt(
            workoutStartedAt: start,
            eventKind: .runningStep,
            eventKey: "2",
            sentAt: time
        )
        let decodedOnPhone = try JSONDecoder().decode(
            ATHLTHCoachDeliveryReceipt.self,
            from: JSONEncoder().encode(watchReceipt)
        )
        XCTAssertTrue(decodedOnPhone.isValid(for: start, now: time))
        phoneLedger.noteCompanionDelivery(id: decodedOnPhone.deliveryID)
        XCTAssertFalse(phoneLedger.canDeliver(watchStep, now: time))

        let phoneMilestone = ATHLTHCoachEvent(
            kind: .routineMilestone,
            key: "d1000",
            priority: .routineCoach,
            createdAt: time,
            validFor: 10
        )
        phoneLedger.didDeliver(phoneMilestone, now: time)
        let phoneReceipt = ATHLTHCoachDeliveryReceipt(
            workoutStartedAt: start,
            eventKind: .routineMilestone,
            eventKey: "d1000",
            sentAt: time
        )
        let decodedOnWatch = try JSONDecoder().decode(
            ATHLTHCoachDeliveryReceipt.self,
            from: JSONEncoder().encode(phoneReceipt)
        )
        XCTAssertTrue(decodedOnWatch.isValid(for: start, now: time))
        watchLedger.noteCompanionDelivery(id: decodedOnWatch.deliveryID)
        XCTAssertFalse(watchLedger.canDeliver(phoneMilestone, now: time))

        let another = ATHLTHCoachEvent(
            kind: .runningStep,
            key: "3",
            priority: .structuredStep,
            createdAt: time,
            validFor: 10
        )
        XCTAssertTrue(phoneLedger.canDeliver(another, now: time))
        XCTAssertTrue(watchLedger.canDeliver(another, now: time))
    }
}
