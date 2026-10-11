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
                    iPhoneReachable: true
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
                    iPhoneReachable: true
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
                    iPhoneReachable: true
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
                iPhoneReachable: true
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
                    iPhoneReachable: false
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
                iPhoneReachable: true
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
