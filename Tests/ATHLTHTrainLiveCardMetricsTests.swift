import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHTrainLiveCardMetricsTests: XCTestCase {
    func testUnknownDistanceOrNonFiniteReadingIsNotDisplayed() {
        XCTAssertNil(ATHLTHTrainLiveCardMetrics.distanceLabel(
            meters: 0, estimated: false
        ))
        XCTAssertNil(ATHLTHTrainLiveCardMetrics.distanceLabel(
            meters: .infinity, estimated: true
        ))
        XCTAssertNil(ATHLTHTrainLiveCardMetrics.averagePaceLabel(
            activeSeconds: 20, meters: 0
        ))
    }

    func testTreadmillDistanceAlwaysCarriesEstimateLabel() {
        let value = ATHLTHTrainLiveCardMetrics.distanceLabel(
            meters: 3250, estimated: true
        )
        XCTAssertTrue(value?.contains("estimert") == true)
        XCTAssertFalse(value?.contains("GPS") == true)
    }

    func testMeasuredOutdoorDistanceUsesGPSSource() {
        let value = ATHLTHTrainLiveCardMetrics.distanceLabel(
            meters: 5000, estimated: false
        )
        XCTAssertTrue(value?.contains("GPS") == true)
        XCTAssertFalse(value?.contains("estimert") == true)
    }

    func testAveragePaceUsesActiveSecondsAndHasReliableBounds() {
        XCTAssertEqual(
            ATHLTHTrainLiveCardMetrics.averagePaceLabel(
                activeSeconds: 1500, meters: 5000
            ),
            "Snitt 5:00/km"
        )
        XCTAssertNil(ATHLTHTrainLiveCardMetrics.averagePaceLabel(
            activeSeconds: 12, meters: 12
        ))
        XCTAssertNil(ATHLTHTrainLiveCardMetrics.averagePaceLabel(
            activeSeconds: .infinity, meters: 5000
        ))
    }
    func testStrengthShowsCurrentSetTargetWithoutMarkingRepsCompleted() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let completed = StrengthSetLog(
            id: UUID(), setNumber: 1,
            plannedReps: 8, plannedWeightKilograms: 40,
            completedReps: 8, completedWeightKilograms: 40,
            rpe: nil, completedAt: start, restSeconds: 90
        )
        let current = StrengthSetLog(
            id: UUID(), setNumber: 2,
            plannedReps: 10, plannedWeightKilograms: 45,
            completedReps: nil, completedWeightKilograms: nil,
            rpe: nil, completedAt: nil, restSeconds: 90
        )
        let exercise = StrengthExerciseLog(
            id: UUID(), plannedExerciseID: nil,
            exercise: ExerciseSnapshot(
                name: "Squat", instructions: [], primaryMuscles: [],
                secondaryMuscles: [], equipment: [], imageURL: nil
            ),
            sets: [completed, current], completedAt: nil
        )
        let workout = StrengthWorkoutLog(
            id: UUID(), plannedSessionID: nil, watchSessionID: nil,
            captureDevice: .iPhone, trackingMode: .advanced,
            title: "Legs", startedAt: start, endedAt: nil,
            exercises: [exercise],
            healthMetrics: LinkedHealthWorkoutMetrics(
                healthKitWorkoutUUID: nil, duration: nil,
                activeCalories: nil, averageHeartRate: nil,
                maxHeartRate: nil
            )
        )
        let text = ATHLTHTrainLiveCardMetrics.strengthDetail(
            workout, exerciseIndex: 0, setIndex: 1,
            restEndsAt: start.addingTimeInterval(90), at: start
        )
        XCTAssertTrue(text?.contains("1/2 sett fullført") == true)
        XCTAssertTrue(text?.contains("Sett 2 · mål 10 reps") == true)
        XCTAssertTrue(text?.contains("Pause pågår") == true)
    }

    func testStrengthFinishedSetDoesNotDisplayAnotherPendingRepTarget() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let completed = StrengthSetLog(
            id: UUID(), setNumber: 1,
            plannedReps: 8, plannedWeightKilograms: 20,
            completedReps: 8, completedWeightKilograms: 20,
            rpe: nil, completedAt: start, restSeconds: 60
        )
        let exercise = StrengthExerciseLog(
            id: UUID(), plannedExerciseID: nil,
            exercise: ExerciseSnapshot(
                name: "Press", instructions: [], primaryMuscles: [],
                secondaryMuscles: [], equipment: [], imageURL: nil
            ),
            sets: [completed], completedAt: start
        )
        let workout = StrengthWorkoutLog(
            id: UUID(), plannedSessionID: nil, watchSessionID: nil,
            captureDevice: .iPhone, trackingMode: .advanced,
            title: "Upper", startedAt: start, endedAt: nil,
            exercises: [exercise],
            healthMetrics: LinkedHealthWorkoutMetrics(
                healthKitWorkoutUUID: nil, duration: nil,
                activeCalories: nil, averageHeartRate: nil,
                maxHeartRate: nil
            )
        )
        let detail = ATHLTHTrainLiveCardMetrics.strengthDetail(
            workout, exerciseIndex: 0, setIndex: 0,
            restEndsAt: nil, at: start
        )
        XCTAssertTrue(detail?.contains("1/1 sett fullført") == true)
        XCTAssertFalse(detail?.contains("mål 8 reps") == true)
    }

}
