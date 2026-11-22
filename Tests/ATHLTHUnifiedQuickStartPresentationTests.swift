import XCTest
@testable import ATHLTH

final class ATHLTHUnifiedQuickStartPresentationTests: XCTestCase {
    func testActivityTypeChoicesAreSharedAcrossBasicAndAdvanced() {
        XCTAssertEqual(ATHLTHQuickStartActivity.running.types,
                       [.free, .route, .workout])
        XCTAssertEqual(ATHLTHQuickStartActivity.walking.types,
                       [.free, .route])
        XCTAssertEqual(ATHLTHQuickStartActivity.strength.types,
                       [.free, .workout, .exercises])
    }

    func testStrengthNeverOffersWalkingCompanion() {
        for iPad in [false, true] {
            let tools = ATHLTHQuickStartActivity.strength.availableTools(
                registeredIPad: iPad
            )
            XCTAssertFalse(tools.contains(.companion))
            XCTAssertTrue(tools.contains(.partner))
            XCTAssertTrue(tools.contains(.guidance))
            XCTAssertTrue(tools.contains(.equipment))
            XCTAssertTrue(tools.contains(.spotify))
        }
        XCTAssertTrue(
            ATHLTHQuickStartActivity.running.availableTools(
                registeredIPad: false
            ).contains(.companion)
        )
        XCTAssertTrue(
            ATHLTHQuickStartActivity.walking.availableTools(
                registeredIPad: false
            ).contains(.companion)
        )
    }

    func testIPadControlIsHiddenWithoutConfirmedRegistration() {
        for activity in [
            ATHLTHQuickStartActivity.running, .walking, .strength
        ] {
            XCTAssertFalse(activity.availableTools(
                registeredIPad: false
            ).contains(.iPad))
            XCTAssertTrue(activity.availableTools(
                registeredIPad: true
            ).contains(.iPad))
        }
    }

    func testCoachGuidanceIsNotRunSpecific() {
        XCTAssertEqual(
            ATHLTHQuickStartTool.guidance.title,
            ATHLTHLocalization.choose(
                english: "Coach & guidance",
                norwegian: "Coach og veiledning"
            )
        )
    }

    func testAllWorkoutTypesHaveAnAccessibleTitleAndSymbol() {
        for activity in [
            ATHLTHQuickStartActivity.running, .walking, .strength
        ] {
            for type in activity.types {
                XCTAssertFalse(type.title(for: activity).isEmpty)
                XCTAssertFalse(type.subtitle(for: activity).isEmpty)
                XCTAssertFalse(type.symbol.isEmpty)
            }
        }
    }
}
