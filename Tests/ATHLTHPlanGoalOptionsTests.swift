import Foundation
import XCTest
@testable import ATHLTH

/// The plan goal selector must keep one clear meaning per choice, without
/// adding a second goals model or invalidating old draft option identifiers.
final class ATHLTHPlanGoalOptionsTests: XCTestCase {
    func testAllCategoriesHaveUniqueStableChoices() {
        for area in ATHLTHPlanGoalArea.allCases {
            let options = ATHLTHPlanGoalOption.options(for: area)
            XCTAssertEqual(options.count, 5)
            XCTAssertEqual(Set(options.map(\.id)).count, options.count)
            XCTAssertTrue(options.allSatisfy { !$0.title.isEmpty && !$0.subtitle.isEmpty })
        }
    }

    func testHypertrophyIsNotMistakenForKilogramTarget() throws {
        let strength = ATHLTHPlanGoalOption.options(for: .strength)
        let muscle = try XCTUnwrap(strength.first(where: { $0.id == "muscle" }))
        let weight = try XCTUnwrap(strength.first(where: { $0.id == "power" }))
        XCTAssertEqual(muscle.focus, .hypertrophy)
        XCTAssertEqual(muscle.goal, .buildMuscle)
        XCTAssertEqual(weight.focus, .strength)
        XCTAssertEqual(weight.goal, .getStronger)
        XCTAssertNotEqual(muscle.goal, weight.goal)
    }

    func testRunningChoicesSupportReturnAndConsistencyWithoutStrengthGoals() throws {
        let running = ATHLTHPlanGoalOption.options(for: .running)
        XCTAssertEqual(running.first(where: { $0.id == "power" })?.goal, .maintain)
        XCTAssertEqual(running.first(where: { $0.id == "wellness" })?.goal, .returnAfterBreak)
        XCTAssertFalse(running.contains(where: { $0.goal == .getStronger }))
    }

    func testExistingGoalDraftIdentifiersStillResolve() {
        XCTAssertTrue(ATHLTHPlanGoalOption.options(for: .strength)
            .contains(where: { $0.id == "power" }))
        XCTAssertTrue(ATHLTHPlanGoalOption.options(for: .strength)
            .contains(where: { $0.id == "muscle" }))
    }
}
