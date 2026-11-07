import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHCoachMessageLanguageTests: XCTestCase {
    func testNorwegianQuestionUsesNorwegianReplyLanguage() {
        XCTAssertEqual(
            ATHLTHCoachMessageLanguage.responseCode(
                for: "Hva tenker du jeg burde trene i dag?"
            ),
            "nb"
        )
        XCTAssertEqual(
            ATHLTHCoachMessageLanguage.responseCode(
                for: "Hvordan bør jeg legge opp økten?"
            ),
            "nb"
        )
    }

    func testEnglishQuestionUsesEnglishReplyLanguage() {
        XCTAssertEqual(
            ATHLTHCoachMessageLanguage.responseCode(
                for: "What should I train today?"
            ),
            "en"
        )
        XCTAssertEqual(
            ATHLTHCoachMessageLanguage.responseCode(
                for: "Please suggest a strength workout."
            ),
            "en"
        )
    }

    func testLanguageIsEvaluatedIndependentlyForEachQuestion() {
        XCTAssertEqual(
            ATHLTHCoachMessageLanguage.responseCode(
                for: "Can you recommend a workout for tomorrow?"
            ), "en"
        )
        XCTAssertEqual(
            ATHLTHCoachMessageLanguage.responseCode(
                for: "Hva med en rolig løpetur?"
            ), "nb"
        )
    }
}
