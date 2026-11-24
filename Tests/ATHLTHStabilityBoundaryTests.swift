import XCTest
@testable import ATHLTH

final class ATHLTHStabilityBoundaryTests: XCTestCase {
    func testExtremeStageIndexIsRejectedWithoutOverflow() {
        let id = UUID()
        XCTAssertNil(ATHLTHWorkoutLifecyclePolicy.nextPhase(
            for: .advance, workoutID: id, expectedWorkoutID: id,
            source: .structuredTimer, recordingOwner: .iPhone,
            phase: .work, stageIndex: Int.max, stageCount: Int.max
        ))
    }

    func testDelayedNavigationIdentityAcceptsNonFiniteInput() {
        let plan = UUID()
        let workout = UUID()
        for seconds in [Double.infinity, -Double.infinity, Double.nan, Double.greatestFiniteMagnitude] {
            let request = ATHLTHTrainNavigationRequest.startPlannedWorkoutAfter(
                planID: plan, workoutID: workout, seconds: seconds
            )
            XCTAssertFalse(request.id.isEmpty)
        }
    }

    func testDelayedNavigationPreservesFractionalIdentity() {
        let plan = UUID()
        let workout = UUID()
        XCTAssertNotEqual(
            ATHLTHTrainNavigationRequest.startPlannedWorkoutAfter(planID: plan, workoutID: workout, seconds: 1.1).id,
            ATHLTHTrainNavigationRequest.startPlannedWorkoutAfter(planID: plan, workoutID: workout, seconds: 1.9).id
        )
    }
}
