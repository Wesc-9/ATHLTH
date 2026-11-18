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
