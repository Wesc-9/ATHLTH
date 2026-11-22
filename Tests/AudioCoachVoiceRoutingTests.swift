import AVFoundation
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

    func testModernStrengthCoachUsesPhoneForRoutineAndSetSpeech() {
        var config = mirroredConfiguration()
        config.outputPreference = .automatic
        for priority in [
            ATHLTHGuidancePriority.routineCoach, .structuredStep
        ] {
            XCTAssertFalse(ATHLTHAudioCoachVoiceRouting.shouldSpeakOnWatch(
                configuration: config, workoutKind: .strength,
                priority: priority, iPhoneVoiceLeaseActive: true
            ))
            XCTAssertTrue(ATHLTHAudioCoachVoiceRouting.shouldSpeakOnWatch(
                configuration: config, workoutKind: .strength,
                priority: priority, iPhoneVoiceLeaseActive: false
            ))
        }
    }

    func testStrengthCriticalCountdownAndSafetyStayOnWatch() {
        var config = mirroredConfiguration()
        config.outputPreference = .automatic
        for priority in [
            ATHLTHGuidancePriority.targetCritical, .routeCritical,
            .ghostImportant, .ghostPeriodic
        ] {
            XCTAssertTrue(ATHLTHAudioCoachVoiceRouting.shouldSpeakOnWatch(
                configuration: config, workoutKind: .strength,
                priority: priority, iPhoneVoiceLeaseActive: true
            ))
        }
    }

    func testStrengthCueIsFreshSessionBoundAndNeverCarriesOldSpeech() throws {
        let now = Date(timeIntervalSince1970: 18_000)
        let start = now.addingTimeInterval(-50)
        let cue = ATHLTHStrengthMirroredCoachCue(
            id: UUID(), workoutStartedAt: start, sentAt: now,
            text: "Pausen starter. 60 sekunder.",
            priority: .structuredStep
        )
        let decoded = try JSONDecoder().decode(
            ATHLTHStrengthMirroredCoachCue.self,
            from: JSONEncoder().encode(cue)
        )
        XCTAssertEqual(decoded.id, cue.id)
        XCTAssertTrue(decoded.isValid(for: start, now: now))
        XCTAssertFalse(decoded.isValid(
            for: start.addingTimeInterval(3), now: now
        ))
        XCTAssertFalse(decoded.isValid(
            for: start, now: now.addingTimeInterval(8)
        ))
        var expired = cue
        expired.sentAt = now.addingTimeInterval(-20)
        XCTAssertFalse(expired.isValid(for: start, now: now))
        var unsafe = cue
        unsafe.priority = .targetCritical
        XCTAssertFalse(unsafe.isValid(for: start, now: now))
        unsafe.priority = .routineCoach
        unsafe.text = String(repeating: "x", count: 381)
        XCTAssertFalse(unsafe.isValid(for: start, now: now))
    }

    func testStrengthMirrorInvitationUsesSameSessionAsPhoneAudio() {
        var config = mirroredConfiguration()
        config.outputPreference = .automatic
        let now = Date(timeIntervalSince1970: 25_000)
        let start = now.addingTimeInterval(-80)
        let invitation = ATHLTHAudioCoachMirrorInvitation(
            workoutStartedAt: start, sentAt: now,
            configuration: config
        )
        XCTAssertTrue(invitation.isValid(for: start, now: now))
        XCTAssertFalse(invitation.isValid(
            for: start.addingTimeInterval(3), now: now
        ))
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

    func testAutomaticOutputPrefersExternalIPhoneAudioOnly() {
        XCTAssertTrue(ATHLTHCoachPhoneOutputPolicy.permitsPhone(
            preference: .automatic, externalOutputAvailable: true
        ))
        XCTAssertFalse(ATHLTHCoachPhoneOutputPolicy.permitsPhone(
            preference: .automatic, externalOutputAvailable: false
        ))
        XCTAssertTrue(ATHLTHCoachPhoneOutputPolicy.permitsPhone(
            preference: .iPhone, externalOutputAvailable: false
        ))
        XCTAssertFalse(ATHLTHCoachPhoneOutputPolicy.permitsPhone(
            preference: .appleWatch, externalOutputAvailable: true
        ))
    }

    func testAutomaticWatchStartCanUseAcknowledgedIPhoneHandoff() throws {
        var config = WatchAudioCoachConfiguration.disabled
        config.enabled = true
        config.outputPreference = .automatic

        XCTAssertTrue(config.shouldPreferIPhoneAudioWhenReachable)
        XCTAssertTrue(config.shouldUseAcknowledgedVoiceLease)
        XCTAssertTrue(ATHLTHAudioCoachVoiceRouting.shouldSpeakOnWatch(
            configuration: config, workoutKind: .running,
            priority: .routineCoach, iPhoneVoiceLeaseActive: false
        ))
        XCTAssertFalse(ATHLTHAudioCoachVoiceRouting.shouldSpeakOnWatch(
            configuration: config, workoutKind: .running,
            priority: .routineCoach, iPhoneVoiceLeaseActive: true
        ))

        let restored = try JSONDecoder().decode(
            WatchAudioCoachConfiguration.self,
            from: JSONEncoder().encode(config)
        )
        XCTAssertEqual(restored.outputPreference, .automatic)
    }

    func testAppleWatchOnlyPreferenceNeverOffersPhoneSpeech() {
        var config = mirroredConfiguration()
        config.outputPreference = .appleWatch
        XCTAssertFalse(config.shouldPreferIPhoneAudioWhenReachable)
        XCTAssertTrue(ATHLTHAudioCoachVoiceRouting.shouldSpeakOnWatch(
            configuration: config, workoutKind: .walking,
            priority: .routineCoach, iPhoneVoiceLeaseActive: true
        ))
    }

    func testWatchLaunchedMirrorInvitationRequiresSameFreshWorkout() throws {
        var config = WatchAudioCoachConfiguration.disabled
        config.enabled = true
        config.outputPreference = .automatic
        let now = Date(timeIntervalSince1970: 20_000)
        let startedAt = now.addingTimeInterval(-90)
        let invitation = ATHLTHAudioCoachMirrorInvitation(
            workoutStartedAt: startedAt, sentAt: now,
            configuration: config
        )
        let decoded = try JSONDecoder().decode(
            ATHLTHAudioCoachMirrorInvitation.self,
            from: JSONEncoder().encode(invitation)
        )
        XCTAssertTrue(decoded.isValid(for: startedAt, now: now))
        XCTAssertFalse(decoded.isValid(
            for: startedAt.addingTimeInterval(2), now: now
        ))
        XCTAssertFalse(decoded.isValid(
            for: startedAt, now: now.addingTimeInterval(16)
        ))
        var disabled = invitation
        disabled.configuration.enabled = false
        XCTAssertFalse(disabled.isValid(for: startedAt, now: now))
        var watchOnly = invitation
        watchOnly.configuration.outputPreference = .appleWatch
        XCTAssertFalse(watchOnly.isValid(for: startedAt, now: now))
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

    func testLeaseFeatureFlagIsBackwardCompatibleForOldWatchSnapshots() throws {
        var snapshot = WatchWorkoutLiveSnapshot(
            kind: .running,
            state: .running,
            startedAt: Date(timeIntervalSince1970: 1_000),
            capturedAt: Date(timeIntervalSince1970: 1_010),
            elapsedTime: 10,
            heartRate: 125,
            activeCalories: 12,
            distanceMeters: 35,
            averageHeartRate: nil,
            maxHeartRate: nil,
            routePointCount: 1
        )
        let legacy = try JSONDecoder().decode(
            WatchWorkoutLiveSnapshot.self,
            from: JSONEncoder().encode(snapshot)
        )
        XCTAssertNil(legacy.supportsAudioCoachVoiceLease)
        snapshot.supportsAudioCoachVoiceLease = true
        let newSnapshot = try JSONDecoder().decode(
            WatchWorkoutLiveSnapshot.self,
            from: JSONEncoder().encode(snapshot)
        )
        XCTAssertEqual(newSnapshot.supportsAudioCoachVoiceLease, true)
        snapshot.runningStepTargetSlowestPaceSecondsPerKilometer = 420
        snapshot.coachResolvedMaximumHeartRateBPM = 192
        let withTargets = try JSONDecoder().decode(
            WatchWorkoutLiveSnapshot.self,
            from: JSONEncoder().encode(snapshot)
        )
        XCTAssertEqual(withTargets.runningStepTargetSlowestPaceSecondsPerKilometer, 420)
        XCTAssertEqual(withTargets.coachResolvedMaximumHeartRateBPM, 192)
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
    func testCoachMusicRestoreIgnoresItsOwnCategoryRouteChange() {
        // A category change is often produced by our own deactivate/restore
        // path. Retrying on that event risks an infinite notify loop.
        XCTAssertFalse(
            ATHLTHCoachMusicRouteRestorePolicy
                .shouldRetryAfterRouteChange(.categoryChange)
        )
        XCTAssertFalse(
            ATHLTHCoachMusicRouteRestorePolicy
                .shouldRetryAfterRouteChange(nil)
        )
        XCTAssertTrue(
            ATHLTHCoachMusicRouteRestorePolicy
                .shouldRetryAfterRouteChange(.oldDeviceUnavailable)
        )
        XCTAssertTrue(
            ATHLTHCoachMusicRouteRestorePolicy
                .shouldRetryAfterRouteChange(.newDeviceAvailable)
        )
        XCTAssertTrue(
            ATHLTHCoachMusicRouteRestorePolicy
                .shouldRetryAfterRouteChange(.routeConfigurationChange)
        )
    }

}
