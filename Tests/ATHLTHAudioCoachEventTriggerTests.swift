import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHAudioCoachEventTriggerTests: XCTestCase {
    private func speak(
        _ rule: ATHLTHAudioCoachRule,
        slots: inout [UUID: Int],
        context: ATHLTHCoachReadoutContext = .init(),
        elapsed: Double = 90,
        bpm: Double? = nil,
        maximum: Double? = nil
    ) -> [ATHLTHAudioCoachDueAnnouncement] {
        ATHLTHAudioCoachRuleDelivery.dueAnnouncements(
            rules: [rule],
            distanceMeters: 500,
            elapsedSeconds: elapsed,
            paceSecondsPerKilometer: 330,
            heartRateBPM: bpm,
            norwegian: true,
            maximumHeartRateBPM: maximum,
            context: context,
            lastSlots: &slots
        )
    }

    func testPulseThresholdSpeaksOnCrossingAndAgainAfterReturn() {
        let rule = ATHLTHAudioCoachRule(
            trigger: .heartRateAbove, metric: .heartRate, interval: 150
        )
        var slots: [UUID: Int] = [:]
        XCTAssertTrue(speak(rule, slots: &slots, bpm: 130).isEmpty)
        XCTAssertEqual(speak(rule, slots: &slots, bpm: 160).count, 1)
        XCTAssertTrue(speak(rule, slots: &slots, bpm: 161).isEmpty)
        XCTAssertTrue(speak(rule, slots: &slots, bpm: nil).isEmpty)
        XCTAssertTrue(speak(rule, slots: &slots, bpm: 135).isEmpty)
        XCTAssertEqual(speak(rule, slots: &slots, bpm: 160).count, 1)
    }

    func testZoneExitRequiresActualMeasuredZoneAndAnEntryFirst() {
        let rule = ATHLTHAudioCoachRule(
            trigger: .zoneExit, metric: .heartRateZone, interval: 3
        )
        var slots: [UUID: Int] = [:]
        XCTAssertTrue(speak(rule, slots: &slots, bpm: 95, maximum: 180).isEmpty)
        XCTAssertTrue(speak(rule, slots: &slots, bpm: 140, maximum: 180).isEmpty)
        XCTAssertTrue(speak(rule, slots: &slots, bpm: nil, maximum: 180).isEmpty)
        XCTAssertEqual(speak(rule, slots: &slots, bpm: 170, maximum: 180).count, 1)
    }

    func testWorkAndActiveRecoveryUseRealStructuredPhase() {
        var context = ATHLTHCoachReadoutContext()
        context.stepIndex = 1
        context.stepCount = 5
        context.stepPhase = "work"
        context.previousStepPhase = "warmup"
        context.stepElapsedSeconds = 0.5
        let start = ATHLTHAudioCoachRule(
            trigger: .effortStart, metric: .elapsedTime, interval: 1
        )
        var slots: [UUID: Int] = [:]
        XCTAssertEqual(speak(start, slots: &slots, context: context).count, 1)
        XCTAssertTrue(speak(start, slots: &slots, context: context).isEmpty)

        context.stepIndex = 2
        context.stepPhase = "recovery"
        context.previousStepPhase = "work"
        context.isActiveRecovery = true
        let active = ATHLTHAudioCoachRule(
            trigger: .activeRecoveryStart, metric: .elapsedTime, interval: 1
        )
        slots.removeAll()
        XCTAssertEqual(speak(active, slots: &slots, context: context).count, 1)
        context.isActiveRecovery = false
        slots.removeAll()
        XCTAssertTrue(speak(active, slots: &slots, context: context).isEmpty)
    }

    func testBeforeMainOnlyFiresNearKnownWarmupBoundary() {
        let rule = ATHLTHAudioCoachRule(
            trigger: .beforeMain, metric: .stepName, interval: 10
        )
        var context = ATHLTHCoachReadoutContext()
        context.stepIndex = 0
        context.stepCount = 3
        context.stepName = "Warm-up"
        context.stepPhase = "warmup"
        context.nextStepPhase = "work"
        context.stepRemainingSeconds = 12
        var slots: [UUID: Int] = [:]
        XCTAssertTrue(speak(rule, slots: &slots, context: context).isEmpty)
        context.stepRemainingSeconds = 8
        XCTAssertEqual(speak(rule, slots: &slots, context: context).count, 1)
        context.stepRemainingSeconds = 6
        XCTAssertTrue(speak(rule, slots: &slots, context: context).isEmpty)
    }

    func testExistingDistanceCadenceStillWorks() {
        let rule = ATHLTHAudioCoachRule(
            trigger: .distance, metric: .distance, interval: 1000
        )
        var slots: [UUID: Int] = [:]
        XCTAssertTrue(speak(rule, slots: &slots).isEmpty)
        let once = ATHLTHAudioCoachRuleDelivery.dueAnnouncements(
            rules: [rule], distanceMeters: 1000, elapsedSeconds: 320,
            paceSecondsPerKilometer: 320, heartRateBPM: nil,
            norwegian: true, lastSlots: &slots
        )
        XCTAssertEqual(once.count, 1)
    }
}
