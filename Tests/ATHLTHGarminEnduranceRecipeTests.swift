import XCTest
@testable import ATHLTH

final class ATHLTHGarminEnduranceRecipeTests: XCTestCase {
    func testPreservesAppleWatchStepsAndIdentities() throws {
        let source = UUID(), plan = UUID(), session = UUID()
        let steps = [
            WatchRunningWorkoutStep(id: UUID(), title: "Warmup", measure: .open,
                distanceMeters: nil, durationSeconds: nil, intensityText: nil, phase: "warmup"),
            WatchRunningWorkoutStep(id: UUID(), title: "Work", measure: .time,
                distanceMeters: nil, durationSeconds: 240, intensityText: nil, phase: "work"),
            WatchRunningWorkoutStep(id: UUID(), title: "Rest", measure: .distance,
                distanceMeters: 200, durationSeconds: nil, intensityText: nil, phase: "recovery")
        ]
        let transfer = WatchRunningWorkoutTransfer(title: "Intervals", steps: steps,
            sourceWorkoutID: source, autoAdvanceTimedSteps: false, autoStartMainAfterWarmup: false)
        let recipe = try ATHLTHGarminEnduranceRecipe(transfer: transfer, plannedPlanID: plan, plannedSessionID: session)
        XCTAssertEqual(recipe.steps.map(\.id), steps.map(\.id))
        XCTAssertEqual(recipe.steps.map(\.target), [nil, 240, 200])
        XCTAssertEqual(recipe.sourceWorkoutID, source)
        XCTAssertEqual(recipe.plannedSessionID, session)
        XCTAssertFalse(recipe.autoAdvance)
        XCTAssertFalse(recipe.autoStartMain)
        let request = ATHLTHGarminLiveRequest(sport: .running, recipe: recipe)
        XCTAssertEqual(request.message["v"] as? Int, 2)
    }

    func testRejectsUnsupportedOrIncompleteRecipe() {
        let step = WatchRunningWorkoutStep(id: UUID(), title: "Work", measure: .time,
            distanceMeters: nil, durationSeconds: nil, intensityText: nil)
        XCTAssertThrowsError(try ATHLTHGarminEnduranceRecipe(transfer: .init(title: "Bad", steps: [step])))
        XCTAssertThrowsError(try ATHLTHGarminEnduranceRecipe(transfer: .init(title: "Empty", steps: [])))
        XCTAssertThrowsError(try ATHLTHGarminEnduranceRecipe(transfer: .init(title: "Linked", steps: [step]), plannedPlanID: UUID()))
    }
}
