import XCTest
@testable import ATHLTH

final class ATHLTHCoachChatPlanTests: XCTestCase {
    func testRecognizesPlanAndPrefillsExample() {
        let prompt = "Kan du lage en treningsplan for meg? Jeg trener 3-4 ganger i uken og vil bli sterkere i lår. Ute om sommeren og på senter om vinteren."
        XCTAssertTrue(ATHLTHCoachChatPlanIntake.isCreationRequest(prompt))
        let intake = ATHLTHCoachChatPlanIntake.prefilled(from: prompt)
        XCTAssertEqual(intake.goal, .legs)
        XCTAssertEqual(intake.place, .seasonal)
        XCTAssertEqual(intake.sessionsPerWeek, 3)
        XCTAssertFalse(ATHLTHCoachChatPlanIntake.isCreationRequest("Endre treningsplanen min"))
    }
    func testDraftRoundTripsThroughChat() throws {
        var intake = ATHLTHCoachChatPlanIntake()
        intake.goal = .legs
        intake.weeks = 4
        let draft = try XCTUnwrap(ATHLTHCoachChatPlanFactory.makeDraft(intake))
        XCTAssertEqual(draft.program.sessionCount, 12)
        let message = RecoveryCoachMessage(role: .assistant, text: "Draft", chatPlanDraft: draft)
        let restored = try JSONDecoder().decode(RecoveryCoachMessage.self, from: JSONEncoder().encode(message))
        XCTAssertEqual(restored.chatPlanDraft, draft)
    }
}
