import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHTournamentLocalCoachPolicyTests: XCTestCase {
    func testOnlyCatalogIDsAndAllowedActivitiesAreSelected() throws {
        let row = ATHLTHTournamentExerciseSearchResult(id: UUID(), name: "Dumbbell Row", isActivityTemplate: false)
        let press = ATHLTHTournamentExerciseSearchResult(id: UUID(), name: "Bench Press", isActivityTemplate: false)
        let run = ATHLTHTournamentExerciseSearchResult(id: UUID(), name: "5 km", isActivityTemplate: true, activity: .running)
        let draft = try XCTUnwrap(ATHLTHTournamentLocalCoachPolicy.suggest(prompt: "Rygg, kun treningssenter",
            activities: [.strength], exerciseCount: 1, catalog: [row, press, run]))
        XCTAssertEqual(draft.exerciseIDs, [row.id])
        XCTAssertEqual(draft.environment, "gym")
        XCTAssertNil(ATHLTHTournamentLocalCoachPolicy.suggest(prompt: "Rygg", activities: [.strength],
            exerciseCount: 2, catalog: [row, row, press]))
    }

    func testTogetherIntentDoesNotNeedPartnerHealthData() {
        let intake = ATHLTHCoachChatWorkoutIntake.prefilled(from: "Lag en fellesøkt for rygg i morgen")
        XCTAssertTrue(ATHLTHCoachChatWorkoutIntake.isRequest("Lag en fellesøkt for rygg i morgen"))
        XCTAssertEqual(intake.forTogether, true)
        XCTAssertEqual(intake.focus, .back)
    }
}
