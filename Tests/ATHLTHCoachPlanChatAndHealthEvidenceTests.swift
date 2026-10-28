import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHCoachPlanChatAndHealthEvidenceTests: XCTestCase {
    func testExistingPlanChangeIntentInNorwegianAndEnglish() {
        XCTAssertTrue(ATHLTHCoachPlanChatIntent.isAdjustmentRequest(
            "Flytt morgendagens intervaller til fredag", hasActivePlan: true))
        XCTAssertTrue(ATHLTHCoachPlanChatIntent.isAdjustmentRequest(
            "Skip tomorrow's planned session", hasActivePlan: true))
        XCTAssertTrue(ATHLTHCoachPlanChatIntent.isAdjustmentRequest(
            "Juster treningsplanen etter siste økt", hasActivePlan: true))
        XCTAssertFalse(ATHLTHCoachPlanChatIntent.isAdjustmentRequest(
            "Lag en treningsplan for 10 km", hasActivePlan: true))
        XCTAssertFalse(ATHLTHCoachPlanChatIntent.isAdjustmentRequest(
            "Move tomorrow's workout", hasActivePlan: false))
        XCTAssertFalse(ATHLTHCoachPlanChatIntent.isAdjustmentRequest(
            "Hvorfor er pulsen høy under intervaller?", hasActivePlan: true))
    }

    func testSourceFreshnessAllowsCurrentMeasurementsAndRejectsStaleOrFuture() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(ATHLTHCoachHealthEvidence.valid(
            now.addingTimeInterval(-3600), now: now, maxAgeHours: 48))
        XCTAssertTrue(ATHLTHCoachHealthEvidence.valid(
            now.addingTimeInterval(-48 * 3600), now: now, maxAgeHours: 48))
        XCTAssertFalse(ATHLTHCoachHealthEvidence.valid(
            now.addingTimeInterval(-49 * 3600), now: now, maxAgeHours: 48))
        XCTAssertFalse(ATHLTHCoachHealthEvidence.valid(
            now.addingTimeInterval(3600), now: now, maxAgeHours: 48))
        XCTAssertFalse(ATHLTHCoachHealthEvidence.valid(
            nil, now: now, maxAgeHours: 48))
    }

    func testHealthEvidenceRoundTripsWithDateStrings() throws {
        let iso = "2026-10-28T08:00:00Z"
        let evidence = ATHLTHCoachHealthEvidence(
            capturedAt: iso,
            sleepEndedAt: iso,
            hrvSampledAt: iso,
            restingPulseSampledAt: nil
        )
        let restored = try JSONDecoder().decode(
            ATHLTHCoachHealthEvidence.self, from: JSONEncoder().encode(evidence)
        )
        XCTAssertEqual(restored, evidence)
    }

    func testCoachPlanMessagePersistsAndOlderChatsStillDecode() throws {
        let planID = UUID()
        let original = RecoveryCoachMessage(
            role: .assistant,
            text: "Review the proposed plan changes",
            planReviewPlanID: planID,
            planReviewPlanVersion: 9
        )
        let read = try JSONDecoder().decode(
            RecoveryCoachMessage.self, from: JSONEncoder().encode(original)
        )
        XCTAssertEqual(read.planReviewPlanID, planID)
        XCTAssertEqual(read.planReviewPlanVersion, 9)

        var old = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(original))
                as? [String: Any]
        )
        old.removeValue(forKey: "planReviewPlanID")
        old.removeValue(forKey: "planReviewPlanVersion")
        let oldData = try JSONSerialization.data(withJSONObject: old)
        let oldRestored = try JSONDecoder().decode(
            RecoveryCoachMessage.self, from: oldData
        )
        XCTAssertNil(oldRestored.planReviewPlanID)
        XCTAssertNil(oldRestored.planReviewPlanVersion)
    }
}
