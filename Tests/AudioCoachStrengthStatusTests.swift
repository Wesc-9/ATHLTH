import XCTest
@testable import ATHLTH

final class AudioCoachStrengthStatusTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 10_000)

    func testNorwegianSetAndRestSummary() {
        let message = ATHLTHStrengthCoachStatusMessage.make(
            completedSets: 3,
            totalSets: 5,
            exerciseName: "Knebøy",
            restEndsAt: now.addingTimeInterval(42),
            now: now,
            norwegian: true
        )
        XCTAssertEqual(
            message,
            "3 av 5 sett fullført. Nåværende øvelse: Knebøy. 42 sekunder igjen av hvilen."
        )
    }

    func testEnglishSummaryWithoutRest() {
        let message = ATHLTHStrengthCoachStatusMessage.make(
            completedSets: 2,
            totalSets: 8,
            exerciseName: "Bench press",
            restEndsAt: nil,
            now: now,
            norwegian: false
        )
        XCTAssertEqual(
            message,
            "2 of 8 sets complete. Current exercise: Bench press."
        )
    }

    func testPastRestDeadlineIsNotAnnounced() {
        let message = ATHLTHStrengthCoachStatusMessage.make(
            completedSets: 3,
            totalSets: 4,
            exerciseName: "Roing",
            restEndsAt: now.addingTimeInterval(-15),
            now: now,
            norwegian: true
        )
        XCTAssertFalse(message.contains("hvilen"))
        XCTAssertEqual(
            message,
            "3 av 4 sett fullført. Nåværende øvelse: Roing."
        )
    }

    func testNoExerciseAndInvalidCountsRemainSafe() {
        let message = ATHLTHStrengthCoachStatusMessage.make(
            completedSets: -3,
            totalSets: -1,
            exerciseName: "  ",
            restEndsAt: nil,
            now: now,
            norwegian: false
        )
        XCTAssertEqual(message, "0 of 0 sets complete.")
    }

    func testCompletedSetsCannotExceedTotalInSpokenText() {
        let message = ATHLTHStrengthCoachStatusMessage.make(
            completedSets: 9,
            totalSets: 4,
            exerciseName: nil,
            restEndsAt: nil,
            now: now,
            norwegian: true
        )
        XCTAssertEqual(message, "9 av 9 sett fullført.")
    }

    func testVoiceOnlyPauseLeavesBothHapticAndTimersIndependent() {
        let delivery = ATHLTHCoachAlertChannels.resolve(
            delivery: .both,
            voiceEnabled: ATHLTHCoachVoicePausePolicy.allowsSpeech(
                coachEnabled: true,
                speechPaused: true,
                priority: .structuredStep
            ),
            hapticsEnabled: true,
            hapticPermittedByPriority: true
        )
        XCTAssertFalse(delivery.voice)
        XCTAssertTrue(delivery.haptic)
    }

    func testSecondCountdownFollowsRealDeadlineAndSkipsStaleNumbers() {
        XCTAssertNil(ATHLTHCoachSecondCountdown.dueNumber(
            remaining: 10.2, length: 10, previousNumber: nil
        ))
        XCTAssertEqual(ATHLTHCoachSecondCountdown.dueNumber(
            remaining: 9.8, length: 10, previousNumber: nil
        ), 10)
        XCTAssertEqual(ATHLTHCoachSecondCountdown.dueNumber(
            remaining: 8.9, length: 10, previousNumber: 10
        ), 9)
        XCTAssertEqual(ATHLTHCoachSecondCountdown.dueNumber(
            remaining: 5.8, length: 10, previousNumber: 9
        ), 6) // Delayed tick skips 8 and 7; never plays them late.
        XCTAssertNil(ATHLTHCoachSecondCountdown.dueNumber(
            remaining: 7.2, length: 10, previousNumber: 6
        ))
        XCTAssertNil(ATHLTHCoachSecondCountdown.dueNumber(
            remaining: 0, length: 10, previousNumber: 1
        ))
        XCTAssertNil(ATHLTHCoachSecondCountdown.dueNumber(
            remaining: -4, length: 10, previousNumber: 1
        ))
        XCTAssertNil(ATHLTHCoachSecondCountdown.dueNumber(
            remaining: .infinity, length: 10, previousNumber: nil
        ))
    }

    func testStrengthOnlyCountdownOptionsSurviveWatchTransfer() throws {
        var coach = StrengthAudioCoachConfiguration()
        coach.enabled = true
        coach.spokenCountdownToRestSeconds = 5
        coach.spokenCountdownFromRestSeconds = 15
        coach.afterCountdownToRest = .numbersOnly
        coach.afterCountdownFromRest = .nextStep
        coach.motivationEveryCompletedSets = 3
        coach.personalMotivationPhrase = "Du klarer dette."
        let transfer = coach.watchConfiguration
        XCTAssertEqual(transfer.resolvedStrengthCountdownToRest, 5)
        XCTAssertEqual(transfer.resolvedStrengthCountdownFromRest, 15)
        XCTAssertEqual(transfer.strengthAfterCountdownToRest, .numbersOnly)
        XCTAssertEqual(transfer.strengthAfterCountdownFromRest, .nextStep)
        let restored = try JSONDecoder().decode(
            WatchAudioCoachConfiguration.self,
            from: JSONEncoder().encode(transfer)
        )
        XCTAssertEqual(restored, transfer)
        XCTAssertNil(WatchAudioCoachConfiguration.disabled.resolvedStrengthCountdownToRest)
    }

    func testRunRecoveryCountdownAppearsOnlyForStructuredExercise() {
        XCTAssertTrue(ATHLTHAudioCoachOption.intervalRecoveryCountdown.isVisible(
            route: false, structured: true
        ))
        XCTAssertFalse(ATHLTHAudioCoachOption.intervalRecoveryCountdown.isVisible(
            route: false, structured: false
        ))
        var draft = AudioCoachDraft()
        XCTAssertFalse(ATHLTHAudioCoachOption.intervalRecoveryCountdown.isActive(in: draft))
        ATHLTHAudioCoachOption.intervalRecoveryCountdown.setActive(true, in: &draft)
        XCTAssertTrue(ATHLTHAudioCoachOption.intervalRecoveryCountdown.isActive(in: draft))
        let config = draft.configuration()
        XCTAssertEqual(config.resolvedIntervalCountdownToRecovery, 10)
        XCTAssertEqual(config.resolvedIntervalCountdownFromRecovery, 10)
    }

    func testRecoveryEndChoiceCanSilenceOldAutomaticPhaseMessage() {
        var config = WatchAudioCoachConfiguration.disabled
        config.enabled = true
        var smart = ATHLTHAudioCoachSmartSettings()
        smart.intervalCountdownToRecoverySeconds = 10
        smart.intervalCountdownFromRecoverySeconds = 5
        smart.intervalAfterCountdownToRecovery = .numbersOnly
        smart.intervalAfterCountdownFromRecovery = .shortAlert
        config.smartPrompts = smart
        XCTAssertEqual(
            ATHLTHCoachRecoveryBoundary.afterAction(
                finishedPhase: "work", nextPhase: "recovery", configuration: config
            ), .numbersOnly
        )
        XCTAssertEqual(
            ATHLTHCoachRecoveryBoundary.afterAction(
                finishedPhase: "recovery", nextPhase: "work", configuration: config
            ), .shortAlert
        )
        XCTAssertNil(ATHLTHCoachRecoveryBoundary.afterAction(
            finishedPhase: "warmup", nextPhase: "work", configuration: config
        ))
    }

    func testStrengthSetMotivationIsOnlyDueOnRequestedMilestone() {
        XCTAssertNil(ATHLTHStrengthCoachStatusMessage.setMilestoneMotivation(
            completedSets: 2, everySets: 3, personalMessage: "Heia", norwegian: true
        ))
        XCTAssertEqual(ATHLTHStrengthCoachStatusMessage.setMilestoneMotivation(
            completedSets: 3, everySets: 3, personalMessage: "Heia", norwegian: true
        ), "Heia")
        XCTAssertNil(ATHLTHStrengthCoachStatusMessage.setMilestoneMotivation(
            completedSets: 4, everySets: nil, personalMessage: "Heia", norwegian: true
        ))
    }


    func testScopedCountdownForWarmupMainGroupAndWholePlannedWorkout() {
        let group = UUID()
        let nextGroup = UUID()
        var groupEnd = ATHLTHCoachBoundaryCountdownRule()
        groupEnd.scope = .group
        groupEnd.boundary = .ends
        groupEnd.seconds = 10
        groupEnd.after = .shortAlert
        var phaseEnd = ATHLTHCoachBoundaryCountdownRule()
        phaseEnd.scope = .section
        phaseEnd.boundary = .ends
        phaseEnd.seconds = 15
        phaseEnd.sectionFilter = "main"
        var groupStart = ATHLTHCoachBoundaryCountdownRule()
        groupStart.scope = .group
        groupStart.boundary = .starts
        groupStart.seconds = 5
        var finish = ATHLTHCoachBoundaryCountdownRule()
        finish.scope = .plannedWorkout
        finish.boundary = .ends
        finish.seconds = 20
        finish.after = .numbersOnly

        let rules = [groupEnd, phaseEnd, groupStart, finish]
        let noneWithinGroup = ATHLTHCoachBoundaryCountdown.chosenRule(
            rules, currentPhase: "work", nextPhase: "recovery",
            currentGroupID: group, nextGroupID: group,
            stepIndex: 1, stepCount: 5
        )
        XCTAssertNil(noneWithinGroup)

        let betweenGroups = ATHLTHCoachBoundaryCountdown.chosenRule(
            rules, currentPhase: "recovery", nextPhase: "work",
            currentGroupID: group, nextGroupID: nextGroup,
            stepIndex: 2, stepCount: 5
        )
        XCTAssertEqual(betweenGroups?.scope, .group)
        XCTAssertEqual(betweenGroups?.boundary, .ends)
        XCTAssertEqual(betweenGroups?.seconds, 10)

        let fromMainToCooldown = ATHLTHCoachBoundaryCountdown.chosenRule(
            rules, currentPhase: "work", nextPhase: "cooldown",
            currentGroupID: group, nextGroupID: nil,
            stepIndex: 3, stepCount: 5
        )
        XCTAssertEqual(fromMainToCooldown?.scope, .section)
        XCTAssertEqual(fromMainToCooldown?.seconds, 15)
        XCTAssertEqual(fromMainToCooldown?.sectionFilter, "main")

        let finalCountdown = ATHLTHCoachBoundaryCountdown.chosenRule(
            rules, currentPhase: "cooldown", nextPhase: nil,
            currentGroupID: nil, nextGroupID: nil,
            stepIndex: 4, stepCount: 5
        )
        XCTAssertEqual(finalCountdown?.scope, .plannedWorkout)
        XCTAssertEqual(finalCountdown?.seconds, 20)
        XCTAssertEqual(finalCountdown?.after, .numbersOnly)
    }

    func testSectionStartCountdownOnlyWhenASectionActuallyChanges() {
        var beforeMain = ATHLTHCoachBoundaryCountdownRule()
        beforeMain.scope = .section
        beforeMain.boundary = .starts
        beforeMain.sectionFilter = "main"
        beforeMain.seconds = 10

        XCTAssertNil(ATHLTHCoachBoundaryCountdown.chosenRule(
            [beforeMain], currentPhase: "work", nextPhase: "recovery",
            currentGroupID: nil, nextGroupID: nil, stepIndex: 1, stepCount: 4
        ))
        let selection = ATHLTHCoachBoundaryCountdown.chosenRule(
            [beforeMain], currentPhase: "warmup", nextPhase: "work",
            currentGroupID: nil, nextGroupID: UUID(),
            stepIndex: 0, stepCount: 4
        )
        XCTAssertEqual(selection?.scope, .section)
        XCTAssertEqual(selection?.boundary, .starts)

        var startWhole = ATHLTHCoachBoundaryCountdownRule()
        startWhole.scope = .plannedWorkout
        startWhole.boundary = .starts
        XCTAssertNil(ATHLTHCoachBoundaryCountdown.chosenRule(
            [startWhole], currentPhase: "warmup", nextPhase: "work",
            currentGroupID: nil, nextGroupID: nil, stepIndex: 0, stepCount: 4
        ))
    }

    func testLengthWinsWhenMultipleCountdownRulesShareOneBoundary() {
        var dragEnd = ATHLTHCoachBoundaryCountdownRule()
        dragEnd.scope = .step
        dragEnd.seconds = 5
        var groupEnd = ATHLTHCoachBoundaryCountdownRule()
        groupEnd.scope = .group
        groupEnd.seconds = 15
        let selected = ATHLTHCoachBoundaryCountdown.chosenRule(
            [dragEnd, groupEnd],
            currentPhase: "work", nextPhase: "cooldown",
            currentGroupID: UUID(), nextGroupID: nil,
            stepIndex: 2, stepCount: 4
        )
        XCTAssertEqual(selected?.scope, .group)
        XCTAssertEqual(selected?.seconds, 15)
    }

    func testStrengthScopedCountdownOnlyAtKnownEndsAndStarts() {
        var step = ATHLTHCoachBoundaryCountdownRule()
        step.scope = .step
        step.boundary = .ends
        step.seconds = 5
        var section = ATHLTHCoachBoundaryCountdownRule()
        section.scope = .section
        section.boundary = .ends
        section.seconds = 10
        var whole = ATHLTHCoachBoundaryCountdownRule()
        whole.scope = .plannedWorkout
        whole.boundary = .ends
        whole.seconds = 15
        let rules = [step, section, whole]
        XCTAssertEqual(
            ATHLTHCoachBoundaryCountdown.forStrengthTimedSet(
                rules, exerciseIndex: 0, exerciseCount: 3,
                setIndex: 0, setCount: 3
            )?.scope, .step
        )
        XCTAssertEqual(
            ATHLTHCoachBoundaryCountdown.forStrengthTimedSet(
                rules, exerciseIndex: 1, exerciseCount: 3,
                setIndex: 2, setCount: 3
            )?.scope, .section
        )
        XCTAssertEqual(
            ATHLTHCoachBoundaryCountdown.forStrengthTimedSet(
                rules, exerciseIndex: 2, exerciseCount: 3,
                setIndex: 2, setCount: 3
            )?.scope, .plannedWorkout
        )
        var begin = ATHLTHCoachBoundaryCountdownRule()
        begin.scope = .section
        begin.boundary = .starts
        XCTAssertNil(ATHLTHCoachBoundaryCountdown.forStrengthAfterRest(
            [begin], nextExercise: false
        ))
        XCTAssertEqual(ATHLTHCoachBoundaryCountdown.forStrengthAfterRest(
            [begin], nextExercise: true
        )?.scope, .section)
    }

    func testScopedRulesSurviveProfileAndWatchTransfer() throws {
        var rule = ATHLTHCoachBoundaryCountdownRule()
        rule.scope = .section
        rule.sectionFilter = "cooldown"
        rule.boundary = .starts
        rule.seconds = 20
        rule.after = .shortAlert
        var draft = AudioCoachDraft()
        draft.smartPrompts.boundaryCountdownRules = [rule]
        let original = draft.configuration()
        XCTAssertEqual(original.effectiveBoundaryCountdownRules, [rule])
        let restored = try JSONDecoder().decode(
            WatchAudioCoachConfiguration.self,
            from: JSONEncoder().encode(original)
        )
        XCTAssertEqual(restored.effectiveBoundaryCountdownRules, [rule])
        var strength = StrengthAudioCoachConfiguration()
        strength.boundaryCountdownRules = [rule]
        let transfer = strength.watchConfiguration
        XCTAssertEqual(transfer.effectiveBoundaryCountdownRules, [rule])
    }

}
