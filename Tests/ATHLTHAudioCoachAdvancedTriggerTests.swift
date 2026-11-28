import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHAudioCoachAdvancedTriggerTests: XCTestCase {
    func testCommandSelectionIsUniqueAndSpeakingOrderCanChange() {
        let initial: [ATHLTHAudioCoachRule.Metric] = [.heartRate, .speed]
        XCTAssertEqual(ATHLTHCoachCommandSelection.adding(.heartRate, to: initial, multiple: true), initial)
        XCTAssertEqual(ATHLTHCoachCommandSelection.adding(.distance, to: initial, multiple: false), [.distance])
        XCTAssertEqual(ATHLTHCoachCommandSelection.moving(.speed, earlierIn: initial), [.speed, .heartRate])
    }

    func testCommandCatalogueRespectsActivityAndContext() {
        let strength = ATHLTHCoachCommandSelection.available(activity: .strength, structured: true, routes: false, distance: false)
        XCTAssertTrue(strength.contains(.nextExercise))
        XCTAssertTrue(strength.contains(.heartRate))
        XCTAssertFalse(strength.contains(.pace))
        XCTAssertFalse(strength.contains(.speed))
        let running = ATHLTHCoachCommandSelection.available(activity: .running, structured: false, routes: false, distance: true)
        XCTAssertTrue(running.contains(.speed))
        XCTAssertFalse(running.contains(.nextExercise))
        XCTAssertFalse(running.contains(.routeRemainingDistance))
    }

    func testCommandPreviewUsesRuleFormatterAndSelectedOrder() {
        var rule = ATHLTHAudioCoachRule(trigger: .time, metric: .heartRate, interval: 60,
                                       additionalMetrics: [.motivation, .speed])
        rule.customPhrase = "Hold flyten"
        let preview = ATHLTHCoachCommandSelection.example(for: rule, activity: .running, norwegian: true)
        XCTAssertTrue(preview?.hasPrefix("Puls 154. Hold flyten. Hastighet") == true)
    }

    func testSeparateMotivationCommandsAndOwnMessagesRoundTrip() throws {
        var rule = ATHLTHAudioCoachRule(trigger: .distance, metric: .pushMessage,
            interval: 1000, additionalMetrics: [.motivation, .praise, .ownMessage])
        rule.ownMessages = ["Hold flyten", "Du klarer dette"]
        let restored = try JSONDecoder().decode(ATHLTHAudioCoachRule.self, from: JSONEncoder().encode(rule))
        XCTAssertEqual(restored.selectedMetrics, [.pushMessage, .motivation, .praise, .ownMessage])
        XCTAssertEqual(restored.ownMessages, rule.ownMessages)
        let phrase = restored.phrase(distanceMeters: 1000, elapsedSeconds: 300,
            paceSecondsPerKilometer: nil, heartRateBPM: nil, norwegian: true)
        XCTAssertTrue(phrase?.contains("Du klarer dette") == true)
        XCTAssertEqual(restored.phrase(distanceMeters: 2000, elapsedSeconds: 600,
            paceSecondsPerKilometer: nil, heartRateBPM: nil, norwegian: true,
            excluding: [.pushMessage, .motivation, .praise]), "Hold flyten")
    }

    func testNewReadoutsNeverInventMissingMeasurements() {
        let rule = ATHLTHAudioCoachRule(trigger: .time, metric: .averageHeartRate, interval: 60,
            additionalMetrics: [.ghostTimeDifference, .currentSet, .targetPaceDifference])
        XCTAssertNil(rule.phrase(distanceMeters: 0, elapsedSeconds: 60,
            paceSecondsPerKilometer: nil, heartRateBPM: 155, norwegian: true))
        var context = ATHLTHCoachReadoutContext()
        context.averageHeartRateBPM = 140
        context.ghostTimeDifferenceSeconds = -12
        let phrase = rule.phrase(distanceMeters: 0, elapsedSeconds: 60,
            paceSecondsPerKilometer: nil, heartRateBPM: 155, norwegian: true, context: context)
        XCTAssertEqual(phrase, "Snittpuls 140. 12 sekunder bak Ghost")
    }

    private func due(
        _ rule: ATHLTHAudioCoachRule,
        time: Double = 300,
        distance: Double = 1_000,
        heartRate: Double? = nil,
        maxHR: Double? = nil,
        context: ATHLTHCoachReadoutContext = .init(),
        slots: inout [UUID: Int]
    ) -> [String] {
        ATHLTHAudioCoachRuleDelivery.dueMessages(
            rules: [rule],
            distanceMeters: distance,
            elapsedSeconds: time,
            paceSecondsPerKilometer: 300,
            heartRateBPM: heartRate,
            norwegian: true,
            maximumHeartRateBPM: maxHR,
            context: context,
            lastSlots: &slots
        )
    }

    func testApproachingTimeGoalFiresOnceOnlyWhenRemainingKnown() {
        let rule = ATHLTHAudioCoachRule(
            trigger: .nearFinishTime, metric: .motivation, interval: 90
        )
        var slots: [UUID: Int] = [:]
        XCTAssertTrue(due(rule, context: .init(), slots: &slots).isEmpty)
        var ctx = ATHLTHCoachReadoutContext()
        ctx.workoutRemainingSeconds = 91
        XCTAssertTrue(due(rule, context: ctx, slots: &slots).isEmpty)
        ctx.workoutRemainingSeconds = 88
        XCTAssertEqual(due(rule, context: ctx, slots: &slots).count, 1)
        XCTAssertTrue(due(rule, context: ctx, slots: &slots).isEmpty)
    }

    func testApproachingDistanceGoalNeverGuessesFromElapsedDistance() {
        let rule = ATHLTHAudioCoachRule(
            trigger: .nearFinishDistance, metric: .motivation, interval: 250
        )
        var slots: [UUID: Int] = [:]
        XCTAssertTrue(due(rule, distance: 5_000, slots: &slots).isEmpty)
        var ctx = ATHLTHCoachReadoutContext()
        ctx.workoutRemainingMeters = 251
        XCTAssertTrue(due(rule, context: ctx, slots: &slots).isEmpty)
        ctx.workoutRemainingMeters = 240
        XCTAssertEqual(due(rule, context: ctx, slots: &slots).count, 1)
        XCTAssertTrue(due(rule, context: ctx, slots: &slots).isEmpty)
    }

    func testElevationGainUsesVerifiedSensorNotDistance() {
        let rule = ATHLTHAudioCoachRule(
            trigger: .elevationGain, metric: .motivation, interval: 50
        )
        var slots = ATHLTHAudioCoachRuleDelivery.initialSlots(
            rules: [rule], distanceMeters: 9_000, elapsedSeconds: 1_800
        )
        XCTAssertEqual(slots[rule.id], 0)
        XCTAssertTrue(due(rule, slots: &slots).isEmpty)
        var ctx = ATHLTHCoachReadoutContext()
        ctx.elevationGainMeters = 49.9
        XCTAssertTrue(due(rule, context: ctx, slots: &slots).isEmpty)
        ctx.elevationGainMeters = 51
        XCTAssertEqual(due(rule, context: ctx, slots: &slots).count, 1)
        XCTAssertTrue(due(rule, context: ctx, slots: &slots).isEmpty)
        ctx.elevationGainMeters = 101
        XCTAssertEqual(due(rule, context: ctx, slots: &slots).count, 1)
    }

    func testUphillOnlyFiresOnVerifiedEntry() {
        let rule = ATHLTHAudioCoachRule(
            trigger: .uphillDetected, metric: .motivation, interval: 1
        )
        var slots: [UUID: Int] = [:]
        var ctx = ATHLTHCoachReadoutContext()
        XCTAssertTrue(due(rule, context: ctx, slots: &slots).isEmpty)
        ctx.isUphill = true
        XCTAssertEqual(due(rule, context: ctx, slots: &slots).count, 1)
        XCTAssertTrue(due(rule, context: ctx, slots: &slots).isEmpty)
        ctx.isUphill = nil
        XCTAssertTrue(due(rule, context: ctx, slots: &slots).isEmpty)
        ctx.isUphill = false
        XCTAssertTrue(due(rule, context: ctx, slots: &slots).isEmpty)
        ctx.isUphill = true
        XCTAssertEqual(due(rule, context: ctx, slots: &slots).count, 1)
    }

    func testZoneBelowAndPlannedZoneNeedValidatedHRmax() {
        let zoneRule = ATHLTHAudioCoachRule(
            trigger: .zoneBelow, metric: .heartRateZone, interval: 4
        )
        let planRule = ATHLTHAudioCoachRule(
            trigger: .plannedZoneBelow, metric: .heartRateZone, interval: 1
        )
        var slots: [UUID: Int] = [:]
        XCTAssertTrue(due(zoneRule, heartRate: 110, slots: &slots).isEmpty)
        XCTAssertEqual(due(zoneRule, heartRate: 110, maxHR: 180,
                           slots: &slots).count, 1)
        slots = [:]
        XCTAssertTrue(due(planRule, heartRate: 110, maxHR: 180,
                          slots: &slots).isEmpty)
        var ctx = ATHLTHCoachReadoutContext()
        ctx.plannedHeartRateZone = 4
        XCTAssertEqual(due(planRule, heartRate: 110, maxHR: 180,
                           context: ctx, slots: &slots).count, 1)
    }

    func testWorkoutTargetOutsideRuleNeedsARealPrescribedZone() {
        let rule = ATHLTHAudioCoachRule(
            trigger: .plannedZoneOutside, metric: .motivation, interval: 1
        )
        var slots: [UUID: Int] = [:]
        XCTAssertTrue(due(rule, heartRate: 110, maxHR: 180,
                          slots: &slots).isEmpty)
        var ctx = ATHLTHCoachReadoutContext()
        ctx.plannedHeartRateZone = 4
        let spoken = due(rule, heartRate: 110, maxHR: 180,
                         context: ctx, slots: &slots)
        XCTAssertEqual(spoken.count, 1)
        XCTAssertTrue(spoken[0].contains("utenfor"))
        XCTAssertTrue(due(rule, heartRate: 110, maxHR: 180,
                          context: ctx, slots: &slots).isEmpty)
    }

    func testPaceTargetIsNotInferredWhenWorkoutHasNoTarget() {
        let rule = ATHLTHAudioCoachRule(
            trigger: .paceSlowerThanTarget,
            metric: .motivation,
            interval: 1
        )
        var slots: [UUID: Int] = [:]
        XCTAssertTrue(due(rule, slots: &slots).isEmpty)
        var ctx = ATHLTHCoachReadoutContext()
        ctx.targetSlowestPaceSecondsPerKilometer = 250
        XCTAssertEqual(due(rule, context: ctx, slots: &slots).count, 1)
    }

    func testRandomMotivationHasJitterAndDoesNotRepeatWithinWindow() {
        let rule = ATHLTHAudioCoachRule(
            trigger: .randomMotivation, metric: .motivation, interval: 180
        )
        var slots: [UUID: Int] = [:]
        XCTAssertTrue(due(rule, time: 179, slots: &slots).isEmpty)
        var spoken = 0
        for time in stride(from: 180.0, through: 350.0, by: 5) {
            spoken += due(rule, time: time, slots: &slots).count
        }
        XCTAssertEqual(spoken, 1)
        XCTAssertEqual(due(rule, time: 350, slots: &slots).count, 0)
    }

    func testNewRuleAndCoachGroupRoundTripToWatch() throws {
        let rule = ATHLTHAudioCoachRule(
            trigger: .nearFinishDistance, metric: .motivation, interval: 200
        )
        var group = ATHLTHAudioCoachGroup(name: "Finish", ruleIDs: [rule.id])
        group.trigger = .nearFinishDistance
        group.interval = 200
        var config = WatchAudioCoachConfiguration.disabled
        config.customRules = [rule]
        config.coachGroups = [group]
        let restored = try JSONDecoder().decode(
            WatchAudioCoachConfiguration.self,
            from: JSONEncoder().encode(config)
        )
        XCTAssertEqual(restored.customRules?.first?.trigger, .nearFinishDistance)
        XCTAssertEqual(restored.coachGroups?.first?.trigger, .nearFinishDistance)
    }
}
