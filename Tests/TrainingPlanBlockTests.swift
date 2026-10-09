import Foundation
import XCTest
@testable import ATHLTH

final class TrainingPlanBlockTests: XCTestCase {
    private func makePlan() -> TrainingPlan {
        let weeks = (1...12).map { number in
            TrainingPlanWeek(
                id: UUID(),
                weekNumber: number,
                title: "Week \(number)",
                days: (1...7).map { day in
                    TrainingPlanDay(
                        id: UUID(),
                        dayIndex: day,
                        title: "Day \(day)",
                        sessions: []
                    )
                }
            )
        }
        return TrainingPlan(
            id: UUID(),
            ownerID: UUID(),
            title: "Twelve-week training plan",
            summary: "",
            visibility: .privateOnly,
            version: 1,
            weeks: weeks,
            tags: [],
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    func testLegacyPlanWithoutBlocksDecodes() throws {
        let plan = makePlan()
        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(plan))
            as? [String: Any]
        )
        json.removeValue(forKey: "trainingBlocks")
        let original = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(TrainingPlan.self, from: original)
        XCTAssertNil(decoded.trainingBlocks)
        XCTAssertEqual(decoded.weeks.count, 12)
    }

    func testRoundTripPreservesMultipleBlocksAndGoals() throws {
        var plan = makePlan()
        let first = TrainingPlanBlock(
            id: UUID(), title: "Grunnlag", purpose: .foundation,
            startWeek: 1, endWeek: 4, goal: "Teknikk og arbeidskapasitet"
        )
        let second = TrainingPlanBlock(
            id: UUID(), title: "Progresjon", purpose: .progression,
            startWeek: 5, endWeek: 8, goal: "Gradvis økning"
        )
        let third = TrainingPlanBlock(
            id: UUID(), title: "Evaluering", purpose: .evaluation,
            startWeek: 9, endWeek: 12, goal: "Test fremgang"
        )
        plan.trainingBlocks = [first, second, third]

        let restored = try JSONDecoder().decode(
            TrainingPlan.self, from: JSONEncoder().encode(plan)
        )
        XCTAssertEqual(restored.trainingBlocks, [first, second, third])
        XCTAssertEqual(restored.weeks, plan.weeks)
        XCTAssertEqual(restored.version, plan.version)
        XCTAssertEqual(restored.trainingBlocks?.first?.weekCount, 4)
    }

    func testContainsOnlyDesignatedWeeks() {
        let block = TrainingPlanBlock(
            id: UUID(), title: "Målrettet trening",
            purpose: .specialization,
            startWeek: 5, endWeek: 8, goal: "10 km"
        )
        XCTAssertFalse(block.contains(week: 4))
        XCTAssertTrue(block.contains(week: 5))
        XCTAssertTrue(block.contains(week: 7))
        XCTAssertTrue(block.contains(week: 8))
        XCTAssertFalse(block.contains(week: 9))
    }

    func testBlocksDoNotBecomeWorkouts() {
        var plan = makePlan()
        let sessionsBefore = plan.weeks.flatMap(\.days).flatMap(\.sessions)
        plan.trainingBlocks = [
            TrainingPlanBlock(
                id: UUID(), title: "Restitusjon", purpose: .recovery,
                startWeek: 9, endWeek: 12, goal: ""
            )
        ]
        XCTAssertEqual(
            plan.weeks.flatMap(\.days).flatMap(\.sessions), sessionsBefore
        )
    }
}
