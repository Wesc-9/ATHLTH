import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHAudioCoachEventTriggerTests: XCTestCase {
    func testAdvancedRequestValidatesCombinedThresholdAndMultipleMetrics() {
        var availability = ATHLTHCoachTriggerAvailability.basicCoach(activity: .running, hasRoute: false, structured: true)
        availability.hasPaceGoal = true
        let input = "Når jeg er saktere enn målfart i 20 sekunder under drag, og pulsen er maks sone 3, gi meg motivasjon og tempo. Minst 2 minutter mellom beskjeder."
        let json = """
            [{"trigger":"paceSlowerThanTarget","metrics":["motivation","pace"],"scope":"effort","sustainedSeconds":20,"repeatDelaySeconds":120,"maximumZone":3}]
            """
        let rules = ATHLTHCoachAdvancedRequest.decode(json, input: input, availability: availability)
        XCTAssertEqual(rules?.first?.triggerConditions?.sustainedSeconds, 20)
        XCTAssertEqual(rules?.first?.triggerConditions?.repeatDelaySeconds, 120)
        XCTAssertEqual(rules?.first?.triggerConditions?.maximumZone, 3)
        XCTAssertEqual(rules?.first?.scope, .effort)
        XCTAssertEqual(rules?.first?.selectedMetrics, [.motivation, .pace])
        XCTAssertNil(ATHLTHCoachAdvancedRequest.decode(json.replacingOccurrences(of: ":120", with: ":180"), input: input, availability: availability))
        XCTAssertNil(ATHLTHCoachAdvancedRequest.decode(json.replacingOccurrences(of: "\"maximumZone\"", with: "\"minimumZone\""), input: input, availability: availability))
    }

    func testAdvancedRequestRequiresWholeBatchToBeSupported() {
        let availability = ATHLTHCoachTriggerAvailability.basicCoach(activity: .running, hasRoute: false, structured: true)
        let input = "Puls og distanse hvert 5. minutt; si fra 10 sekunder før hvert drag"
        let json = """
            [{"trigger":"time","interval":300,"metrics":["heartRate","distance"]},
             {"trigger":"beforeEffort","interval":10,"metrics":["motivation"]}]
            """
        XCTAssertEqual(ATHLTHCoachAdvancedRequest.decode(json, input: input, availability: availability)?.count, 2)
        XCTAssertNil(ATHLTHCoachAdvancedRequest.decode(json, input: input,
            availability: .basicCoach(activity: .running, hasRoute: false, structured: false)))
        let offline = ATHLTHCoachAdvancedRequest.offline(input, availability: availability)
        XCTAssertEqual(offline?.count, 2)
        XCTAssertEqual(offline?.first?.selectedMetrics, [.heartRate, .distance])
        XCTAssertNil(ATHLTHCoachAdvancedRequest.offline("Puls hvert 5. minutt, men bare i sone 3", availability: availability))
    }

    func testPlainLanguageRequestCreatesExactIntervalWarning() {
        let request = "Jeg ønsker å få beskjed 10 sekunder før hver intervall-drag"
        let availability = ATHLTHCoachTriggerAvailability.basicCoach(activity: .running, hasRoute: false, structured: true)
        XCTAssertEqual(ATHLTHCoachRequestParser.intent(request), .beforeEffort)
        let rule = ATHLTHCoachRequestParser.rule(request, intent: .beforeEffort, availability: availability)
        XCTAssertEqual(rule?.trigger, .beforeEffort)
        XCTAssertEqual(rule?.interval, 10)
        XCTAssertNil(ATHLTHCoachRequestParser.rule(request, intent: .beforeEffort,
            availability: .basicCoach(activity: .running, hasRoute: false, structured: false)))
        XCTAssertNil(ATHLTHCoachRequestParser.rule("Ikke si fra 10 sekunder før hvert drag", intent: .beforeEffort, availability: availability))
        XCTAssertNil(ATHLTHCoachRequestParser.rule("10 sekunder før drag og 20 før pause", intent: .beforeEffort, availability: availability))
    }

    func testPlainLanguageRequestPreservesUnitsAndRejectsWrongSport() {
        let running = ATHLTHCoachTriggerAvailability.basicCoach(activity: .running, hasRoute: false, structured: true)
        let strength = ATHLTHCoachTriggerAvailability.basicCoach(activity: .strength, hasRoute: false, structured: true)
        XCTAssertEqual(ATHLTHCoachRequestParser.rule("Puls hvert 5. minutt", intent: .everyTime, availability: running)?.interval, 300)
        XCTAssertEqual(ATHLTHCoachRequestParser.rule("Si min puls hvert 30. sekund", intent: .everyTime, availability: running)?.metric, .heartRate)
        XCTAssertNil(ATHLTHCoachRequestParser.rule("Varsle 10 sekunder før pausen starter", intent: .beforeRestEnd, availability: strength))
        XCTAssertEqual(ATHLTHCoachRequestParser.rule("Varsle 10 sekunder før pausen er ferdig", intent: .beforeRestEnd, availability: strength)?.trigger, .strengthRestEnding)
        XCTAssertNil(ATHLTHCoachRequestParser.rule("Varsle hver 2 km", intent: .everyDistance, availability: strength))
    }

    func testBeforeEffortNeverSpeaksForRecoveryOrLateBoundary() {
        let rule = ATHLTHAudioCoachRule(trigger: .beforeEffort, metric: .motivation, interval: 10)
        var context = ATHLTHCoachReadoutContext()
        context.stepIndex = 0
        context.stepCount = 5
        context.hasNextStep = true
        context.stepPhase = "warmup"
        context.nextStepPhase = "work"
        var slots: [UUID: Int] = [:]
        context.stepRemainingSeconds = 11
        XCTAssertTrue(speak(rule, slots: &slots, context: context).isEmpty)
        context.stepRemainingSeconds = 10
        XCTAssertEqual(speak(rule, slots: &slots, context: context).count, 1)
        XCTAssertTrue(speak(rule, slots: &slots, context: context).isEmpty)
        slots.removeAll()
        context.nextStepPhase = "recovery"
        XCTAssertTrue(speak(rule, slots: &slots, context: context).isEmpty)
        context.nextStepPhase = "cooldown"
        XCTAssertTrue(speak(rule, slots: &slots, context: context).isEmpty)
        context.nextStepPhase = "work"
        context.stepRemainingSeconds = 2
        XCTAssertTrue(speak(rule, slots: &slots, context: context).isEmpty)
    }

    func testPreparationTargetsUpcomingEffortAndDoesNotInterruptCountdown() {
        var rule = ATHLTHAudioCoachRule(trigger: .beforeNextStep, metric: .motivation,
                                       interval: 15, eventSelection: .withoutRest)
        rule.linkedCountdownSeconds = 10
        var context = ATHLTHCoachReadoutContext()
        context.stepIndex = 1
        context.stepCount = 5
        context.hasNextStep = true
        context.stepPhase = "recovery"
        context.nextStepPhase = "work"
        context.stepRemainingSeconds = 15
        var slots: [UUID: Int] = [:]
        XCTAssertEqual(speak(rule, slots: &slots, context: context).count, 1)
        XCTAssertTrue(speak(rule, slots: &slots, context: context).isEmpty)
        slots.removeAll()
        context.stepRemainingSeconds = 10
        XCTAssertTrue(speak(rule, slots: &slots, context: context).isEmpty)
        context.stepRemainingSeconds = 15
        context.nextStepPhase = "recovery"
        XCTAssertTrue(speak(rule, slots: &slots, context: context).isEmpty)
    }

    func testPushBeforeFinishHonorsSelectedStyle() {
        var rule = ATHLTHAudioCoachRule(trigger: .nearFinishDistance, metric: .motivation, interval: 100)
        rule.encouragementStyle = .push
        let phrase = rule.phrase(distanceMeters: 4900, elapsedSeconds: 1500,
                                 paceSecondsPerKilometer: 300, heartRateBPM: nil, norwegian: true)
        XCTAssertTrue(phrase?.contains("presse kontrollert") == true)
    }

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
