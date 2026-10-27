import XCTest
import SwiftUI
@testable import ATHLTH

final class ATHLTHPlanJourneyTests: XCTestCase {
    func testFreshAndResumeLaunchesAreDistinct() {
        let firstNewPlan = TrainProgramCreationLaunch.fresh
        let anotherNewPlan = TrainProgramCreationLaunch.fresh
        let resumedPlan = TrainProgramCreationLaunch.continueDraft

        // Fresh + must not inherit a prior draft's step 2 (or later).
        XCTAssertFalse(firstNewPlan.resumesDraft)
        XCTAssertFalse(anotherNewPlan.resumesDraft)
        XCTAssertTrue(resumedPlan.resumesDraft)

        // Separate sheet identities force SwiftUI to recreate the builder
        // at the canonical first mode-selection step.
        XCTAssertNotEqual(firstNewPlan.id, anotherNewPlan.id)
        XCTAssertNotEqual(firstNewPlan.id, resumedPlan.id)
        XCTAssertEqual(ATHLTHPlanJourney.sequence(advanced: true).first, .mode)
        XCTAssertEqual(ATHLTHPlanJourney.sequence(advanced: false).first, .mode)
    }

    func testSimpleStartsWithModeAndSkipsAdvancedQuestions() {
        let stages = ATHLTHPlanJourney.sequence(advanced: false)
        XCTAssertEqual(stages, [.mode, .goal, .basics])
        XCTAssertFalse(stages.contains(.profile))
        XCTAssertFalse(stages.contains(.week))
        XCTAssertNil(ATHLTHPlanJourney.position(of: .review, advanced: false))
        XCTAssertNil(ATHLTHPlanJourney.next(after: .basics, advanced: false))
    }

    func testAdvancedUsesMethodChoiceInsteadOfMandatoryHealthIntake() {
        XCTAssertEqual(
            ATHLTHPlanJourney.sequence(advanced: true),
            [.mode, .goal, .basics, .approach, .week, .review]
        )
        XCTAssertFalse(ATHLTHPlanJourney.sequence(advanced: true).contains(.profile))
        XCTAssertEqual(ATHLTHPlanJourney.displayedCount(advanced: true), 5)
        XCTAssertEqual(ATHLTHPlanJourney.position(of: .approach, advanced: true), 4)
        XCTAssertEqual(ATHLTHPlanJourney.position(of: .week, advanced: true), 5)
        XCTAssertEqual(ATHLTHPlanJourney.position(of: .review, advanced: true), 5)
        XCTAssertEqual(ATHLTHPlanJourney.next(after: .basics, advanced: true), .approach)
        XCTAssertEqual(ATHLTHPlanJourney.next(after: .approach, advanced: true), .week)
    }

    func testResumeReturnsToLastAllowedWizardStage() {
        XCTAssertEqual(ATHLTHPlanJourney.restoredStep("goal", advanced: true), .goal)
        XCTAssertEqual(ATHLTHPlanJourney.restoredStep("goal", advanced: false), .goal)
        XCTAssertEqual(ATHLTHPlanJourney.restoredStep("week", advanced: true), .week)
        XCTAssertEqual(ATHLTHPlanJourney.restoredStep("profile", advanced: true), .approach)
        XCTAssertEqual(ATHLTHPlanJourney.restoredStep("approach", advanced: true), .approach)
        XCTAssertEqual(ATHLTHPlanJourney.restoredStep("review", advanced: true), .review)
        XCTAssertEqual(ATHLTHPlanJourney.restoredStep("basics", advanced: false), .basics)
        XCTAssertEqual(ATHLTHPlanJourney.restoredStep("week", advanced: false), .basics)
        XCTAssertEqual(ATHLTHPlanJourney.restoredStep("futureStage", advanced: true), .mode)
    }

    func testEveryNextAndPreviousStepIsReversible() {
        for isAdvanced in [false, true] {
            let stages = ATHLTHPlanJourney.sequence(advanced: isAdvanced)
            XCTAssertNil(ATHLTHPlanJourney.previous(before: .mode, advanced: isAdvanced))
            XCTAssertNil(ATHLTHPlanJourney.next(after: .review, advanced: isAdvanced))
            for index in 0..<(stages.count - 1) {
                let current = stages[index]
                let following = stages[index + 1]
                XCTAssertEqual(
                    ATHLTHPlanJourney.next(after: current, advanced: isAdvanced),
                    following
                )
                XCTAssertEqual(
                    ATHLTHPlanJourney.previous(before: following, advanced: isAdvanced),
                    current
                )
            }
        }
    }

    func testGoalCategoriesHaveValidSelectionsAndStoredPlanMappings() {
        for category in ATHLTHPlanGoalArea.allCases {
            let goals = ATHLTHPlanGoalOption.options(for: category)
            XCTAssertEqual(goals.count, 5)
            XCTAssertEqual(Set(goals.map(\.id)).count, goals.count)
            XCTAssertTrue(goals.allSatisfy { !$0.title.isEmpty && !$0.subtitle.isEmpty })
        }
        let running = ATHLTHPlanGoalOption.options(for: .running)
        XCTAssertEqual(running[0].goal, .improveFitness)
        XCTAssertEqual(running[1].goal, .runFaster)
        XCTAssertEqual(running[2].focus, .endurance)
        XCTAssertEqual(ATHLTHPlanGoalOption.options(for: .strength)[1].goal, .buildMuscle)
        XCTAssertEqual(ATHLTHPlanGoalOption.options(for: .specific)[0].goal, .raceReady)
    }

    @MainActor
    func testPlanEntryCardsFitCompactPhoneWidths() {
        let features: [ATHLTHPlanEntryModeCard.Feature] = [
            .init(symbol: "bolt.fill", title: "Rask oppstart"),
            .init(symbol: "list.bullet", title: "Faste maler"),
            .init(symbol: "pencil", title: "Enkel å redigere")
        ]

        for width in [320.0, 375.0, 430.0] {
            let card = ATHLTHPlanEntryModeCard(
                title: "Enkel",
                subtitle: "Kom raskt i gang med kun det viktigste.",
                symbol: "sparkles",
                selected: true,
                features: features,
                onSelect: {}
            )
            let controller = UIHostingController(rootView: card)
            controller.loadViewIfNeeded()
            let allowedWidth = width - 36
            let measured = controller.sizeThatFits(
                in: CGSize(width: allowedWidth, height: 700)
            )
            XCTAssertLessThanOrEqual(
                measured.width, allowedWidth + 1,
                "Mode card overflows a \(Int(width))-pt display"
            )
        }
    }

    @MainActor
    func testPlanExistingChoicesAndIllustrationAreBounded() {
        let artwork = UIHostingController(
            rootView: ATHLTHPlanModeIllustration()
        )
        artwork.loadViewIfNeeded()
        let imageSize = artwork.sizeThatFits(
            in: CGSize(width: 190, height: 177)
        )
        XCTAssertLessThanOrEqual(imageSize.width, 191)

        let shortcut = UIHostingController(
            rootView: ATHLTHPlanExistingChoice(
                title: "Planbibliotek",
                subtitle: "Utforsk ferdige planer",
                symbol: "square.stack.3d.up",
                action: {}
            )
        )
        shortcut.loadViewIfNeeded()
        let shortcutSize = shortcut.sizeThatFits(
            in: CGSize(width: 165, height: 300)
        )
        XCTAssertLessThanOrEqual(shortcutSize.width, 166)
    }


    @MainActor
    func testBuildMethodCardFitsCompactPhones() {
        for width in [320.0, 375.0, 430.0] {
            let selector = ATHLTHPlanBuildMethodEntryView(
                selected: .dayByDay,
                onSelect: { _ in },
                onOpenLibrary: {},
                onOpenMyPlans: {}
            )
            let host = UIHostingController(rootView: selector)
            host.loadViewIfNeeded()
            let available = width - 36
            let size = host.sizeThatFits(in: CGSize(width: available, height: 940))
            XCTAssertLessThanOrEqual(size.width, available + 1)
        }
    }

    func testPlanDesignHasConsistentLayoutPriorities() {
        XCTAssertGreaterThan(
            ATHLTHPlanDesign.Density.comfortable.cardPadding,
            ATHLTHPlanDesign.Density.compact.cardPadding
        )
        XCTAssertGreaterThanOrEqual(ATHLTHPlanDesign.minTapHeight, 44)
        XCTAssertGreaterThan(ATHLTHPlanDesign.maxContentWidth, 600)
    }
}