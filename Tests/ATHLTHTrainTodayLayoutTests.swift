import SwiftUI
import XCTest
@testable import ATHLTH

final class ATHLTHTrainTodayLayoutTests: XCTestCase {
    @MainActor
    func testTodaySurfaceFitsCompactPhoneWidths() {
        let plan = TrainingPlan(
            id: UUID(),
            ownerID: UUID(),
            title: "Weekly plan",
            summary: "",
            visibility: .privateOnly,
            version: 1,
            weeks: [],
            tags: [],
            createdAt: Date(),
            updatedAt: Date()
        )

        // No plan and rest days both use photo heroes. Verify that image
        // aspect ratios cannot force a wider-than-screen SwiftUI layout.
        let scenarios: [TrainingPlan?] = [nil, plan]
        for width in [320.0, 375.0, 430.0] {
            for currentPlan in scenarios {
                for hasActiveWorkout in [false, true] {
                let today = ATHLTHTrainTodayPremiumView(
                    plan: currentPlan,
                    sessions: [],
                    completedIDs: [],
                    healthCompletedIDs: [],
                    nextWorkoutTitle: currentPlan == nil ? nil : "Strength legs",
                    nextWorkoutDate: nil,
                    completionFraction: 0,
                    planPosition: "",
                    hasActiveWorkout: hasActiveWorkout,
                    onChooseSuggestedWorkout: { _ in },
                    onOpenPlan: {},
                    onCreatePlan: {},
                    onOpenLibrary: {},
                    onStartWorkout: { _, _ in },
                    onWorkoutDetails: { _, _ in },
                    onQuickTrain: { _ in },
                    onGhostRace: {}
                )

                let host = UIHostingController(rootView: today)
                host.loadViewIfNeeded()
                let measured = host.sizeThatFits(
                    in: CGSize(width: width, height: 1_600)
                )
                XCTAssertLessThanOrEqual(
                    measured.width,
                    width + 1,
                    "Today content exceeds a \(Int(width))-point viewport"
                )
                }
            }
        }
    }
}
