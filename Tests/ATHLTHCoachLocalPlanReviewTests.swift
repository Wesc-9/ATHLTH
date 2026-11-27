import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHCoachLocalPlanReviewTests: XCTestCase {
    func testReviewAndMoveIntentsDoNotConfusePlanCreation() {
        XCTAssertTrue(ATHLTHCoachLocalPlanReview.isReviewRequest("Gjennomgå treningsplanen min"))
        XCTAssertFalse(ATHLTHCoachLocalPlanReview.isReviewRequest("Lag en treningsplan"))
        XCTAssertTrue(ATHLTHCoachLocalPlanReview.isMoveRequest("Flytt økten min til i morgen"))
        XCTAssertFalse(ATHLTHCoachLocalPlanReview.isMoveRequest("Lag en økt i morgen"))
        XCTAssertTrue(ATHLTHCoachLocalGoalReview.isRequest("Hvordan ligger jeg an med målene mine?"))
        XCTAssertFalse(ATHLTHCoachLocalGoalReview.isRequest("Lag en treningsplan med mål om styrke"))
    }

    func testNoActiveGoalsDoesNotClaimProgress() {
        let result = ATHLTHCoachLocalGoalReview.render(goals: [], profile: .init(), norwegian: true)
        XCTAssertTrue(result.contains("Ingen") || result.contains("ingen"))
    }

    @MainActor func testReviewAttachmentRejectsUpdatedPlanAndPersistsInChat() throws {
        let suite = "ATHLTHCoachLocalPlanReviewTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppSessionStore(defaults: defaults)
        var plan = try XCTUnwrap(store.createTrainingPlan(title: "Review", summary: "", weekCount: 1, startDate: Date()))
        let review = ATHLTHCoachLocalPlanReview(plan: plan)
        XCTAssertTrue(review.matches(plan))
        plan.version += 1
        XCTAssertFalse(review.matches(plan))
        let message = RecoveryCoachMessage(role: .assistant, text: "Review", localPlanReview: review)
        let restored = try JSONDecoder().decode(RecoveryCoachMessage.self, from: JSONEncoder().encode(message))
        XCTAssertEqual(restored.localPlanReview, review)
    }
}
