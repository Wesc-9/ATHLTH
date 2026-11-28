import XCTest
@testable import ATHLTH

final class ATHLTHCoachTriggerCapabilityTests: XCTestCase {
    func testFreeWorkoutDoesNotOfferFinishWithoutPlannedGoal() {
        let capabilities = ATHLTHCoachTriggerAvailability.session(
            hasRoute: false, structured: false
        )
        XCTAssertTrue(capabilities.supports(.distance, for: .running))
        XCTAssertFalse(capabilities.supports(.nearFinishDistance, for: .running))
        XCTAssertFalse(capabilities.supports(.nearFinishTime, for: .running))
        XCTAssertFalse(capabilities.supports(.paceSlowerThanTarget, for: .running))
        XCTAssertFalse(capabilities.supports(.plannedZoneBelow, for: .running))
        XCTAssertFalse(capabilities.supports(.stepStart, for: .running))
    }

    func testActualTargetsEnableOnlyRelevantTriggers() {
        var capabilities = ATHLTHCoachTriggerAvailability.session(
            hasRoute: true, structured: true
        )
        capabilities.workoutActivity = .running
        capabilities.hasTimeGoal = true
        capabilities.hasPaceGoal = true
        capabilities.hasZoneGoal = true
        XCTAssertTrue(capabilities.supports(.nearFinishDistance, for: .running))
        XCTAssertTrue(capabilities.supports(.nearFinishTime, for: .running))
        XCTAssertTrue(capabilities.supports(.paceSlowerThanTarget, for: .running))
        XCTAssertTrue(capabilities.supports(.plannedZoneBelow, for: .running))
        XCTAssertTrue(capabilities.supports(.stepStart, for: .intervals))
        XCTAssertFalse(capabilities.supports(.paceSlowerThanTarget, for: .strength))
        XCTAssertFalse(capabilities.supports(.nearFinishDistance, for: .cycling))
        XCTAssertFalse(capabilities.supports(.slowerThanPreviousWorkout, for: .walking))
    }

    func testSportRestrictionsAlsoProtectGlobalTemplates() {
        let global = ATHLTHCoachTriggerAvailability.global
        XCTAssertTrue(global.supports(.time, for: .strength))
        XCTAssertTrue(global.supports(.heartRateAbove, for: .strength))
        XCTAssertFalse(global.supports(.distance, for: .strength))
        XCTAssertFalse(global.supports(.uphillDetected, for: .swimming))
        XCTAssertFalse(global.supports(.slowerThanPreviousWorkout, for: .walking))
        XCTAssertTrue(global.supports(.slowerThanPreviousWorkout, for: .running))
    }

    func testAllSelectionInConcreteStrengthWorkoutStillUsesStrengthRestrictions() {
        var capabilities = ATHLTHCoachTriggerAvailability.session(hasRoute: false, structured: true)
        capabilities.workoutActivity = .strength
        XCTAssertFalse(capabilities.supports(.distance, for: .all))
        XCTAssertFalse(capabilities.supports(.paceFasterOverall, for: .all))
        XCTAssertFalse(capabilities.supports(.personalRecordConfirmed, for: .all))
        XCTAssertTrue(capabilities.supports(.heartRateAbove, for: .all))
    }

    func testHistoricKilometreMustBeMeasuredAndSpeakOnce() {
        var rule = ATHLTHAudioCoachRule(
            trigger: .slowerThanPreviousWorkout,
            metric: .motivation,
            interval: 1
        )
        rule.activityFilter = .running
        rule.historicalWorkoutID = UUID()
        rule.historicalWorkoutFirstKilometerSeconds = 270
        var slots: [UUID: Int] = [:]
        var context = ATHLTHCoachReadoutContext()
        context.overallPaceSecondsPerKilometer = 287

        func due(_ metres: Double, sport: String) -> [String] {
            ATHLTHAudioCoachRuleDelivery.dueMessages(
                rules: [rule],
                distanceMeters: metres,
                elapsedSeconds: 287,
                paceSecondsPerKilometer: 287,
                heartRateBPM: nil,
                norwegian: true,
                context: context,
                sport: sport,
                lastSlots: &slots
            )
        }
        XCTAssertTrue(due(1_000, sport: "strength").isEmpty)
        XCTAssertTrue(due(999, sport: "running").isEmpty)
        let spoken = due(1_000, sport: "running")
        XCTAssertEqual(spoken.count, 1)
        XCTAssertTrue(spoken[0].contains("saktere"))
        XCTAssertTrue(due(1_010, sport: "running").isEmpty)
    }

    func testMissingHistoryDoesNotCreateAudioCoachClaim() {
        let rule = ATHLTHAudioCoachRule(
            trigger: .slowerThanPreviousWorkout,
            metric: .motivation,
            interval: 1
        )
        var slots: [UUID: Int] = [:]
        var context = ATHLTHCoachReadoutContext()
        context.overallPaceSecondsPerKilometer = 330
        XCTAssertTrue(ATHLTHAudioCoachRuleDelivery.dueMessages(
            rules: [rule], distanceMeters: 1_000,
            elapsedSeconds: 330, paceSecondsPerKilometer: 330,
            heartRateBPM: nil, norwegian: true,
            context: context, sport: "running", lastSlots: &slots
        ).isEmpty)
    }

    func testTypeFilterDoesNotConsumeRunningRuleInWalking() {
        var rule = ATHLTHAudioCoachRule(
            trigger: .time, metric: .elapsedTime, interval: 60
        )
        rule.activityFilter = .running
        var slots: [UUID: Int] = [:]
        func read(_ sport: String) -> [String] {
            ATHLTHAudioCoachRuleDelivery.dueMessages(
                rules: [rule], distanceMeters: 0,
                elapsedSeconds: 61, paceSecondsPerKilometer: nil,
                heartRateBPM: nil, norwegian: true,
                sport: sport, lastSlots: &slots
            )
        }
        XCTAssertTrue(read("walking").isEmpty)
        XCTAssertNil(slots[rule.id])
        XCTAssertEqual(read("running").count, 1)
    }

    func testBackgroundIsNotUserDismissal() {
        XCTAssertFalse(ATHLTHScenePresentationContinuityPolicy.acceptsDismissal(
            sceneIsActive: false
        ))
        XCTAssertTrue(ATHLTHScenePresentationContinuityPolicy.acceptsDismissal(
            sceneIsActive: true
        ))
    }
}
