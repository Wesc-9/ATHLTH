import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHAudioCoachPaceAndPRTests: XCTestCase {
    private func due(
        rule: ATHLTHAudioCoachRule,
        context: ATHLTHCoachReadoutContext,
        elapsed: Double,
        currentPace: Double? = nil,
        journal: inout [UUID: Int]
    ) -> [String] {
        ATHLTHAudioCoachRuleDelivery.dueMessages(
            rules: [rule], distanceMeters: 2_000,
            elapsedSeconds: elapsed, paceSecondsPerKilometer: currentPace,
            heartRateBPM: nil, norwegian: true,
            context: context, lastSlots: &journal
        )
    }

    func testCompleteRollingKilometreRequiresOneThousandMeasuredMeters() {
        var window = ATHLTHAudioCoachRollingKilometer()
        window.record(distanceMeters: 0, activeSeconds: 0)
        window.record(distanceMeters: 500, activeSeconds: 145)
        window.record(distanceMeters: 999, activeSeconds: 289.71)
        XCTAssertNil(window.paceSecondsPerKilometer)
        window.record(distanceMeters: 1_000, activeSeconds: 290)
        XCTAssertEqual(window.paceSecondsPerKilometer ?? -1, 290, accuracy: 0.2)
        window.record(distanceMeters: 1_100, activeSeconds: 320)
        XCTAssertEqual(window.paceSecondsPerKilometer ?? -1, 291, accuracy: 0.5)
    }

    func testBelowFiveMinuteOverallPaceTriggersOnceUntilRearmed() {
        let rule = ATHLTHAudioCoachRule(
            trigger: .paceFasterOverall, metric: .averagePace, interval: 300
        )
        var context = ATHLTHCoachReadoutContext()
        var journal: [UUID: Int] = [:]
        context.overallPaceSecondsPerKilometer = 299
        XCTAssertEqual(due(rule: rule, context: context, elapsed: 600, journal: &journal).count, 1)
        XCTAssertTrue(due(rule: rule, context: context, elapsed: 605, journal: &journal).isEmpty)
        context.overallPaceSecondsPerKilometer = 305
        XCTAssertTrue(due(rule: rule, context: context, elapsed: 610, journal: &journal).isEmpty)
        context.overallPaceSecondsPerKilometer = 311
        XCTAssertTrue(due(rule: rule, context: context, elapsed: 615, journal: &journal).isEmpty)
        context.overallPaceSecondsPerKilometer = 298
        XCTAssertEqual(due(rule: rule, context: context, elapsed: 620, journal: &journal).count, 1)
    }

    func testRollingKilometrePaceConditionNeedsVerifiedRollingPace() {
        let rule = ATHLTHAudioCoachRule(
            trigger: .paceFasterLastKilometer, metric: .lastKilometerPace,
            interval: 300
        )
        var context = ATHLTHCoachReadoutContext()
        var journal: [UUID: Int] = [:]
        XCTAssertTrue(due(rule: rule, context: context, elapsed: 20, journal: &journal).isEmpty)
        context.lastKilometerPaceSecondsPerKilometer = 299
        let announcement = due(rule: rule, context: context, elapsed: 300, journal: &journal)
        XCTAssertEqual(announcement.count, 1)
        XCTAssertTrue(announcement[0].contains("siste kilometer"))
        XCTAssertEqual(rule.trigger.summary(interval: 300).contains("5:00"), true)
    }

    func testExerciseTargetPaceNeedsBothTargetAndFreshPace() {
        let rule = ATHLTHAudioCoachRule(
            trigger: .paceFasterThanTarget, metric: .pace, interval: 1
        )
        var context = ATHLTHCoachReadoutContext()
        var journal: [UUID: Int] = [:]
        XCTAssertTrue(due(rule: rule, context: context, elapsed: 60,
                          currentPace: 290, journal: &journal).isEmpty)
        context.targetPaceSecondsPerKilometer = 300
        XCTAssertTrue(due(rule: rule, context: context, elapsed: 65,
                          currentPace: nil, journal: &journal).isEmpty)
        XCTAssertEqual(due(rule: rule, context: context, elapsed: 70,
                           currentPace: 290, journal: &journal).count, 1)
    }

    func testPRCueMustHaveConfirmedHistoricalEvidence() {
        let rule = ATHLTHAudioCoachRule(
            trigger: .personalRecordConfirmed,
            metric: .personalRecord,
            interval: 1
        )
        var context = ATHLTHCoachReadoutContext()
        var journal: [UUID: Int] = [:]
        XCTAssertTrue(due(rule: rule, context: context, elapsed: 1500,
                          journal: &journal).isEmpty)
        context.verifiedPersonalRecordEnglish = "New verified personal record"
        context.verifiedPersonalRecordNorwegian = "Ny bekreftet personlig rekord"
        let words = due(rule: rule, context: context, elapsed: 1500,
                        journal: &journal)
        XCTAssertEqual(words.count, 1)
        XCTAssertTrue(words[0].contains("personlig rekord"))
        XCTAssertTrue(due(rule: rule, context: context, elapsed: 1501,
                          journal: &journal).isEmpty)
        XCTAssertFalse(ATHLTHAudioCoachRule.Metric.personalRecord.requiresInternet)
    }

    func testStrengthProgressNeedsActualComparableEvidence() {
        let rule = ATHLTHAudioCoachRule(trigger: .strengthProgressConfirmed, metric: .motivation, interval: 1)
        var ctx = ATHLTHCoachReadoutContext()
        var journal: [UUID: Int] = [:]
        XCTAssertTrue(due(rule: rule, context: ctx, elapsed: 20, journal: &journal).isEmpty)
        ctx.verifiedStrengthProgress = .init(exerciseName: "Knebøy", currentWeightKg: 80,
            previousWeightKg: 80, repetitions: 8, completedSetCount: 3, confirmedAt: Date())
        XCTAssertTrue(due(rule: rule, context: ctx, elapsed: 21, journal: &journal).isEmpty)
        ctx.verifiedStrengthProgress = .init(exerciseName: "Knebøy", currentWeightKg: 85,
            previousWeightKg: 80, repetitions: 8, completedSetCount: 3, confirmedAt: Date())
        XCTAssertEqual(due(rule: rule, context: ctx, elapsed: 22, journal: &journal).count, 1)
        XCTAssertTrue(due(rule: rule, context: ctx, elapsed: 23, journal: &journal).isEmpty)
    }

    func testCadenceRequiresFreshMeasuredSensorData() {
        let rule = ATHLTHAudioCoachRule(trigger: .cadenceBelow, metric: .motivation, interval: 160)
        var ctx = ATHLTHCoachReadoutContext()
        var journal: [UUID: Int] = [:]
        XCTAssertTrue(due(rule: rule, context: ctx, elapsed: 20, journal: &journal).isEmpty)
        ctx.measuredCadenceStepsPerMinute = 150
        ctx.cadenceSampleAt = Date().addingTimeInterval(-30)
        XCTAssertTrue(due(rule: rule, context: ctx, elapsed: 30, journal: &journal).isEmpty)
        ctx.cadenceSampleAt = Date()
        XCTAssertEqual(due(rule: rule, context: ctx, elapsed: 31, journal: &journal).count, 1)
        XCTAssertTrue(due(rule: rule, context: ctx, elapsed: 32, journal: &journal).isEmpty)
    }

    func testStrengthCompletedSetsAreCountedOnlyOnce() {
        let rule = ATHLTHAudioCoachRule(trigger: .strengthSetCompleted, metric: .remainingSets, interval: 2)
        var ctx = ATHLTHCoachReadoutContext()
        ctx.remainingSetCount = 8
        var journal: [UUID: Int] = [:]
        XCTAssertTrue(due(rule: rule, context: ctx, elapsed: 10, journal: &journal).isEmpty)
        ctx.completedStrengthSetCount = 1
        XCTAssertTrue(due(rule: rule, context: ctx, elapsed: 20, journal: &journal).isEmpty)
        ctx.completedStrengthSetCount = 2
        XCTAssertEqual(due(rule: rule, context: ctx, elapsed: 30, journal: &journal).count, 1)
        XCTAssertTrue(due(rule: rule, context: ctx, elapsed: 31, journal: &journal).isEmpty)
        ctx.completedStrengthSetCount = 4
        XCTAssertEqual(due(rule: rule, context: ctx, elapsed: 40, journal: &journal).count, 1)
    }

    func testLastExerciseSetAndRestRequireExplicitState() {
        let final = ATHLTHAudioCoachRule(trigger: .lastExerciseSet, metric: .remainingSets, interval: 1)
        let rest = ATHLTHAudioCoachRule(trigger: .strengthRestEnding, metric: .remainingSets, interval: 15)
        var ctx = ATHLTHCoachReadoutContext()
        ctx.stepIndex = 0
        ctx.remainingSetCount = 4
        var journal: [UUID: Int] = [:]
        XCTAssertTrue(due(rule: final, context: ctx, elapsed: 20, journal: &journal).isEmpty)
        ctx.isFinalExerciseSet = true
        XCTAssertEqual(due(rule: final, context: ctx, elapsed: 21, journal: &journal).count, 1)
        ctx.stepPhase = "recovery"
        ctx.completedStrengthSetCount = 3
        ctx.strengthRestRemainingSeconds = 16
        XCTAssertTrue(due(rule: rest, context: ctx, elapsed: 22, journal: &journal).isEmpty)
        ctx.strengthRestRemainingSeconds = 15
        XCTAssertEqual(due(rule: rest, context: ctx, elapsed: 23, journal: &journal).count, 1)
        XCTAssertTrue(due(rule: rest, context: ctx, elapsed: 24, journal: &journal).isEmpty)
    }

    func testProgressNeedsKnownGoalAndFiresOnce() {
        let rule = ATHLTHAudioCoachRule(trigger: .workoutTimeProgress, metric: .elapsedTime, interval: 50)
        var ctx = ATHLTHCoachReadoutContext()
        var journal: [UUID: Int] = [:]
        XCTAssertTrue(due(rule: rule, context: ctx, elapsed: 100, journal: &journal).isEmpty)
        ctx.workoutRemainingSeconds = 101
        XCTAssertTrue(due(rule: rule, context: ctx, elapsed: 100, journal: &journal).isEmpty)
        ctx.workoutRemainingSeconds = 100
        XCTAssertEqual(due(rule: rule, context: ctx, elapsed: 100, journal: &journal).count, 1)
        XCTAssertTrue(due(rule: rule, context: ctx, elapsed: 105, journal: &journal).isEmpty)
    }

    func testBackAtPaceRequiresPriorDeviation() {
        let rule = ATHLTHAudioCoachRule(trigger: .paceBackInTarget, metric: .pace, interval: 1)
        var ctx = ATHLTHCoachReadoutContext()
        ctx.targetPaceSecondsPerKilometer = 300
        var journal: [UUID: Int] = [:]
        XCTAssertTrue(due(rule: rule, context: ctx, elapsed: 60, currentPace: 300, journal: &journal).isEmpty)
        XCTAssertTrue(due(rule: rule, context: ctx, elapsed: 70, currentPace: 330, journal: &journal).isEmpty)
        XCTAssertEqual(due(rule: rule, context: ctx, elapsed: 80, currentPace: 300, journal: &journal).count, 1)
    }

    func testGhostRequiresMeasuredDifference() {
        let rule = ATHLTHAudioCoachRule(trigger: .ghostAhead, metric: .ghostDistanceDifference, interval: 1)
        var ctx = ATHLTHCoachReadoutContext()
        var journal: [UUID: Int] = [:]
        XCTAssertTrue(due(rule: rule, context: ctx, elapsed: 60, journal: &journal).isEmpty)
        ctx.ghostDistanceDifferenceMeters = 12
        XCTAssertEqual(due(rule: rule, context: ctx, elapsed: 65, journal: &journal).count, 1)
        XCTAssertTrue(due(rule: rule, context: ctx, elapsed: 70, journal: &journal).isEmpty)
    }

    func testSustainedPaceAndRepeatDelay() {
        var rule = ATHLTHAudioCoachRule(trigger: .paceFasterOverall, metric: .averagePace, interval: 300)
        rule.triggerConditions = .init(sustainedSeconds: 20, repeatDelaySeconds: 120)
        var ctx = ATHLTHCoachReadoutContext()
        ctx.overallPaceSecondsPerKilometer = 290
        var journal: [UUID: Int] = [:]
        for t in [0.0, 10.0] {
            XCTAssertTrue(due(rule: rule, context: ctx, elapsed: t, journal: &journal).isEmpty)
        }
        XCTAssertEqual(due(rule: rule, context: ctx, elapsed: 20, journal: &journal).count, 1)
        ctx.overallPaceSecondsPerKilometer = 320
        XCTAssertTrue(due(rule: rule, context: ctx, elapsed: 30, journal: &journal).isEmpty)
        ctx.overallPaceSecondsPerKilometer = 290
        for t in [40.0, 50.0, 60.0] {
            XCTAssertTrue(due(rule: rule, context: ctx, elapsed: t, journal: &journal).isEmpty)
        }
    }

    func testMissingSampleResetsSustainedCondition() {
        var rule = ATHLTHAudioCoachRule(trigger: .paceFasterOverall, metric: .averagePace, interval: 300)
        rule.triggerConditions = .init(sustainedSeconds: 20)
        var ctx = ATHLTHCoachReadoutContext()
        var journal: [UUID: Int] = [:]
        ctx.overallPaceSecondsPerKilometer = 290
        XCTAssertTrue(due(rule: rule, context: ctx, elapsed: 0, journal: &journal).isEmpty)
        ctx.overallPaceSecondsPerKilometer = nil
        XCTAssertTrue(due(rule: rule, context: ctx, elapsed: 10, journal: &journal).isEmpty)
        ctx.overallPaceSecondsPerKilometer = 290
        XCTAssertTrue(due(rule: rule, context: ctx, elapsed: 20, journal: &journal).isEmpty)
        XCTAssertTrue(due(rule: rule, context: ctx, elapsed: 30, journal: &journal).isEmpty)
        XCTAssertEqual(due(rule: rule, context: ctx, elapsed: 40, journal: &journal).count, 1)
    }

    func testAdditionalZoneConditionRequiresMeasuredHeartRate() throws {
        var rule = ATHLTHAudioCoachRule(trigger: .paceSlowerThanTarget, metric: .pace, interval: 1)
        rule.triggerConditions = .init(maximumZone: 3)
        var ctx = ATHLTHCoachReadoutContext()
        ctx.targetPaceSecondsPerKilometer = 300
        var journal: [UUID: Int] = [:]
        XCTAssertTrue(due(rule: rule, context: ctx, elapsed: 60, currentPace: 320, journal: &journal).isEmpty)
        var config = WatchAudioCoachConfiguration.disabled
        config.customRules = [rule]
        let restored = try JSONDecoder().decode(WatchAudioCoachConfiguration.self, from: JSONEncoder().encode(config))
        XCTAssertEqual(restored.activeCustomRules.first?.triggerConditions, rule.triggerConditions)
    }

    func testDataModelPaceRuleRoundTripsIntoWatchTransfer() throws {
        let rule = ATHLTHAudioCoachRule(
            trigger: .paceFasterLastKilometer, metric: .lastKilometerPace,
            interval: 300
        )
        var config = WatchAudioCoachConfiguration.disabled
        config.enabled = true
        config.customRules = [rule]
        let restored = try JSONDecoder().decode(
            WatchAudioCoachConfiguration.self, from: JSONEncoder().encode(config)
        )
        XCTAssertEqual(restored.activeCustomRules.first?.trigger, .paceFasterLastKilometer)
        XCTAssertEqual(restored.activeCustomRules.first?.validatedInterval, 300)
    }
}
