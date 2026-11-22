import XCTest
@testable import ATHLTH

final class ATHLTHCoachTriggerSelectionTests: XCTestCase {
    private func due(
        _ rule: ATHLTHAudioCoachRule,
        at index: Int,
        phase: String,
        count: Int = 5,
        firstRest: Int? = 1,
        lastRest: Int? = 3,
        lastSlots: inout [UUID: Int]
    ) -> [String] {
        var context = ATHLTHCoachReadoutContext()
        context.stepIndex = index
        context.stepCount = count
        context.stepPhase = phase
        context.stepElapsedSeconds = 1
        context.stepRemainingSeconds = 30
        context.firstRecoveryStepIndex = firstRest
        context.lastRecoveryStepIndex = lastRest
        return ATHLTHAudioCoachRuleDelivery.dueMessages(
            rules: [rule], distanceMeters: 500,
            elapsedSeconds: Double(index * 180 + 1),
            paceSecondsPerKilometer: 320,
            heartRateBPM: 145,
            norwegian: true,
            context: context,
            lastSlots: &lastSlots
        )
    }

    func testFirstStepOnlySpeaksAtFirstOccurrence() {
        var rule = ATHLTHAudioCoachRule(
            trigger: .stepStart, metric: .distance, interval: 1
        )
        rule.eventSelection = .first
        var slots: [UUID: Int] = [:]
        XCTAssertEqual(due(rule, at: 0, phase: "warmup", lastSlots: &slots).count, 1)
        XCTAssertTrue(due(rule, at: 1, phase: "work", lastSlots: &slots).isEmpty)
    }

    func testLastStepOnlySpeaksAtLastOccurrence() {
        var rule = ATHLTHAudioCoachRule(
            trigger: .stepStart, metric: .distance, interval: 1
        )
        rule.eventSelection = .last
        var slots: [UUID: Int] = [:]
        XCTAssertTrue(due(rule, at: 2, phase: "work", lastSlots: &slots).isEmpty)
        XCTAssertEqual(due(rule, at: 4, phase: "cooldown", lastSlots: &slots).count, 1)
    }

    func testPauseFirstAndLastMatchActualPlannedRecoveryIndices() {
        var first = ATHLTHAudioCoachRule(
            trigger: .recoveryStart, metric: .elapsedTime, interval: 1
        )
        first.eventSelection = .first
        var last = first
        last.id = UUID()
        last.eventSelection = .last
        var firstSlots: [UUID: Int] = [:]
        var lastSlots: [UUID: Int] = [:]
        XCTAssertEqual(due(first, at: 1, phase: "recovery",
                           lastSlots: &firstSlots).count, 1)
        XCTAssertTrue(due(first, at: 3, phase: "recovery",
                          lastSlots: &firstSlots).isEmpty)
        XCTAssertTrue(due(last, at: 1, phase: "recovery",
                          lastSlots: &lastSlots).isEmpty)
        XCTAssertEqual(due(last, at: 3, phase: "recovery",
                           lastSlots: &lastSlots).count, 1)
    }

    func testStepSelectionMainAndWithoutRest() {
        let context = ATHLTHCoachReadoutContext(
            stepIndex: 1, stepPhase: "recovery"
        )
        var rule = ATHLTHAudioCoachRule(
            trigger: .stepStart, metric: .elapsedTime, interval: 1
        )
        rule.eventSelection = .mainOnly
        XCTAssertTrue(rule.matchesEventSelection(context))
        rule.eventSelection = .withoutRest
        XCTAssertFalse(rule.matchesEventSelection(context))
    }

    func testPhaseScopeAllowsMainIncludingRecovery() {
        XCTAssertTrue(ATHLTHCoachWorkoutPhase.main.matches(stepPhase: "work"))
        XCTAssertTrue(ATHLTHCoachWorkoutPhase.main.matches(stepPhase: "recovery"))
        XCTAssertFalse(ATHLTHCoachWorkoutPhase.main.matches(stepPhase: "warmup"))
    }

    func testPersistedGroupAndRuleSelectionsSurviveWatchRoundtrip() throws {
        var rule = ATHLTHAudioCoachRule(
            trigger: .recoveryStart, metric: .heartRate, interval: 1,
            additionalMetrics: [.elapsedTime]
        )
        rule.eventSelection = .last
        let group = ATHLTHAudioCoachGroup(
            name: "Siste pause", ruleIDs: [rule.id],
            trigger: .recoveryStart, interval: 1,
            enabled: true, phases: [.main], eventSelection: .last
        )
        var config = WatchAudioCoachConfiguration.disabled
        config.customRules = [rule]
        config.coachGroups = [group]
        let restored = try JSONDecoder().decode(
            WatchAudioCoachConfiguration.self,
            from: JSONEncoder().encode(config)
        )
        XCTAssertEqual(restored.coachGroups?.first?.eventSelection, .last)
        XCTAssertEqual(restored.activeCustomRules.first?.eventSelection, .last)
        XCTAssertEqual(restored.activeCustomRules.first?.allowedPhases, [.main])
    }
}
