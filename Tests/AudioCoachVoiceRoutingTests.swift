import XCTest
@testable import ATHLTH

/// Stage 1 guardrail: iPhone mirroring must not silence cues it cannot
/// reproduce, and ordinary run commentary must not play on both devices.
final class AudioCoachVoiceRoutingTests: XCTestCase {
    private func mirroredConfiguration() -> WatchAudioCoachConfiguration {
        var configuration = WatchAudioCoachConfiguration.disabled
        configuration.enabled = true
        configuration.preferIPhoneAudioWhenReachable = true
        return configuration
    }

    func testMirroredRunKeepsRoutineAndStepSpeechOnIPhone() {
        let configuration = mirroredConfiguration()
        for priority in [
            ATHLTHGuidancePriority.routineCoach,
            .structuredStep
        ] {
            XCTAssertFalse(
                ATHLTHAudioCoachVoiceRouting.shouldSpeakOnWatch(
                    configuration: configuration,
                    workoutKind: .running,
                    priority: priority,
                    iPhoneVoiceLeaseActive: true
                ),
                "Routine/step speech must not duplicate on Watch and iPhone"
            )
        }
    }

    func testMirroredRunKeepsUniqueAlertsAudibleOnWatch() {
        let configuration = mirroredConfiguration()
        for priority in [
            ATHLTHGuidancePriority.ghostPeriodic,
            .ghostImportant,
            .targetCritical,
            .routeCritical
        ] {
            XCTAssertTrue(
                ATHLTHAudioCoachVoiceRouting.shouldSpeakOnWatch(
                    configuration: configuration,
                    workoutKind: .running,
                    priority: priority,
                    iPhoneVoiceLeaseActive: true
                ),
                "The mirrored iPhone coach does not reproduce this alert"
            )
        }
    }

    func testStrengthSpeechStaysOnWatchWhenIPhoneIsReachable() {
        let configuration = mirroredConfiguration()
        for priority in [
            ATHLTHGuidancePriority.routineCoach,
            .structuredStep,
            .targetCritical
        ] {
            XCTAssertTrue(
                ATHLTHAudioCoachVoiceRouting.shouldSpeakOnWatch(
                    configuration: configuration,
                    workoutKind: .strength,
                    priority: priority,
                    iPhoneVoiceLeaseActive: true
                )
            )
        }
    }

    func testWalkingUsesSameRoutineOwnershipAsRunning() {
        XCTAssertFalse(
            ATHLTHAudioCoachVoiceRouting.shouldSpeakOnWatch(
                configuration: mirroredConfiguration(),
                workoutKind: .walking,
                priority: .routineCoach,
                iPhoneVoiceLeaseActive: true
            )
        )
    }

    func testWatchTakesAllSpeechWhenPhoneIsNotReachable() {
        let configuration = mirroredConfiguration()
        for priority in [
            ATHLTHGuidancePriority.routineCoach,
            .ghostPeriodic,
            .structuredStep,
            .targetCritical,
            .routeCritical
        ] {
            XCTAssertTrue(
                ATHLTHAudioCoachVoiceRouting.shouldSpeakOnWatch(
                    configuration: configuration,
                    workoutKind: .running,
                    priority: priority,
                    iPhoneVoiceLeaseActive: false
                )
            )
        }
    }

    func testWatchOwnedWorkoutDoesNotDependOnReachability() {
        var configuration = mirroredConfiguration()
        configuration.preferIPhoneAudioWhenReachable = false
        XCTAssertTrue(
            ATHLTHAudioCoachVoiceRouting.shouldSpeakOnWatch(
                configuration: configuration,
                workoutKind: .running,
                priority: .routineCoach,
                iPhoneVoiceLeaseActive: true
            )
        )
    }

    func testExistingConfigWithoutNewPreferenceStaysWatchOwned() throws {
        let decoded = try JSONDecoder().decode(
            WatchAudioCoachConfiguration.self,
            from: JSONEncoder().encode(WatchAudioCoachConfiguration.disabled)
        )
        XCTAssertFalse(decoded.shouldPreferIPhoneAudioWhenReachable)
    }

    func testValidOfferGrantsTemporaryLeaseAndAcknowledgesRequest() {
        var lease = ATHLTHAudioCoachVoiceLease()
        let now = Date(timeIntervalSince1970: 1_000)
        let startedAt = now.addingTimeInterval(-30)
        let offer = ATHLTHAudioCoachLeaseOffer(
            generationID: UUID(),
            requestID: UUID(),
            workoutStartedAt: startedAt,
            issuedAt: now
        )

        let acknowledgement = lease.grant(
            offer: offer,
            workoutStartedAt: startedAt,
            eligible: true,
            now: now
        )
        XCTAssertEqual(acknowledgement?.requestID, offer.requestID)
        XCTAssertEqual(acknowledgement?.generationID, offer.generationID)
        XCTAssertTrue(lease.isActive(at: now.addingTimeInterval(5)))
        XCTAssertFalse(lease.isActive(at: now.addingTimeInterval(7)))
    }

    func testLeaseRejectsStaleOfferOrDifferentWorkout() {
        let now = Date(timeIntervalSince1970: 2_000)
        let startedAt = now.addingTimeInterval(-30)
        var lease = ATHLTHAudioCoachVoiceLease()
        let offer = ATHLTHAudioCoachLeaseOffer(
            generationID: UUID(),
            requestID: UUID(),
            workoutStartedAt: startedAt,
            issuedAt: now.addingTimeInterval(-10)
        )
        XCTAssertNil(lease.grant(
            offer: offer,
            workoutStartedAt: startedAt,
            eligible: true,
            now: now
        ))
        XCTAssertFalse(lease.isActive(at: now))
        let freshOffer = ATHLTHAudioCoachLeaseOffer(
            generationID: offer.generationID,
            requestID: UUID(),
            workoutStartedAt: startedAt,
            issuedAt: now
        )
        XCTAssertNil(lease.grant(
            offer: freshOffer,
            workoutStartedAt: startedAt.addingTimeInterval(60),
            eligible: true,
            now: now
        ))
        XCTAssertFalse(lease.isActive(at: now))
    }

    func testLeaseRejectsIneligibleOrOutOfOrderOffer() {
        let now = Date(timeIntervalSince1970: 3_000)
        let startedAt = now.addingTimeInterval(-20)
        var lease = ATHLTHAudioCoachVoiceLease()
        let first = ATHLTHAudioCoachLeaseOffer(
            generationID: UUID(),
            requestID: UUID(),
            workoutStartedAt: startedAt,
            issuedAt: now
        )
        XCTAssertNil(lease.grant(
            offer: first,
            workoutStartedAt: startedAt,
            eligible: false,
            now: now
        ))
        XCTAssertNotNil(lease.grant(
            offer: first,
            workoutStartedAt: startedAt,
            eligible: true,
            now: now
        ))
        let earlier = ATHLTHAudioCoachLeaseOffer(
            generationID: first.generationID,
            requestID: UUID(),
            workoutStartedAt: startedAt,
            issuedAt: now.addingTimeInterval(-1)
        )
        XCTAssertNil(lease.grant(
            offer: earlier,
            workoutStartedAt: startedAt,
            eligible: true,
            now: now
        ))
        lease.reset()
        XCTAssertFalse(lease.isActive(at: now))
    }

    func testLeaseCanUseJsonAcrossPhoneAndWatch() throws {
        let startedAt = Date(timeIntervalSince1970: 4_000)
        let offer = ATHLTHAudioCoachLeaseOffer(
            generationID: UUID(),
            requestID: UUID(),
            workoutStartedAt: startedAt,
            issuedAt: startedAt
        )
        let decoded = try JSONDecoder().decode(
            ATHLTHAudioCoachLeaseOffer.self,
            from: JSONEncoder().encode(offer)
        )
        XCTAssertEqual(offer, decoded)

        var lease = ATHLTHAudioCoachVoiceLease()
        let acknowledgement = try XCTUnwrap(lease.grant(
            offer: decoded,
            workoutStartedAt: startedAt,
            eligible: true,
            now: startedAt
        ))
        let decodedAck = try JSONDecoder().decode(
            ATHLTHAudioCoachLeaseAcknowledgement.self,
            from: JSONEncoder().encode(acknowledgement)
        )
        XCTAssertEqual(decodedAck.requestID, offer.requestID)
    }

    func testPriorityGateDoesNotOverrideCriticalWithRoutine() {
        var gate = ATHLTHGuidancePriorityGate()
        let now = Date(timeIntervalSince1970: 100)
        XCTAssertEqual(
            gate.voiceDecision(
                for: .targetCritical,
                isSpeaking: false,
                quietPeriodSeconds: 10,
                now: now
            ),
            .deliver
        )
        XCTAssertEqual(
            gate.voiceDecision(
                for: .routineCoach,
                isSpeaking: true,
                quietPeriodSeconds: 10,
                now: now.addingTimeInterval(1)
            ),
            .drop
        )
        XCTAssertTrue(
            gate.allowsHaptic(
                for: .routeCritical,
                now: now.addingTimeInterval(2)
            )
        )
    }
}
