import Foundation
import XCTest
@testable import ATHLTH

final class StrengthPostWorkoutReviewTests: XCTestCase {
    private let timestamp = Date(timeIntervalSince1970: 1_800_000_000)

    private func loggedSet(
        reps: Int?,
        weight: Double?,
        duration: Int? = nil
    ) -> StrengthSetLog {
        var set = StrengthSetLog(
            id: UUID(),
            setNumber: 1,
            plannedReps: reps,
            plannedWeightKilograms: weight,
            completedReps: reps,
            completedWeightKilograms: weight,
            rpe: nil,
            completedAt: timestamp,
            restSeconds: 90
        )
        if let duration {
            set.targetKind = .time
            set.completedDurationSeconds = duration
        }
        return set
    }

    private func exercise(
        _ name: String,
        sets: [StrengthSetLog]
    ) -> StrengthExerciseLog {
        StrengthExerciseLog(
            id: UUID(),
            plannedExerciseID: nil,
            exercise: ExerciseSnapshot(
                name: name,
                instructions: [],
                primaryMuscles: ["Abdominals"],
                secondaryMuscles: [],
                equipment: [],
                imageURL: nil
            ),
            sets: sets,
            completedAt: timestamp
        )
    }

    private func session(
        exercises: [StrengthExerciseLog]
    ) -> StrengthWorkoutLog {
        StrengthWorkoutLog(
            id: UUID(),
            plannedSessionID: nil,
            watchSessionID: nil,
            captureDevice: .iPhone,
            trackingMode: .advanced,
            title: "Strength",
            startedAt: timestamp.addingTimeInterval(-3600),
            endedAt: timestamp,
            exercises: exercises,
            healthMetrics: LinkedHealthWorkoutMetrics(
                healthKitWorkoutUUID: nil,
                duration: 3600,
                activeCalories: nil,
                averageHeartRate: nil,
                maxHeartRate: nil
            )
        )
    }

    func testHistoricalSixInchHoldDoesNotBecomeAWeightRecord() {
        // A legacy hold accidentally recorded a 20 kg draft weight.
        // Preserve the real measured time, never invent weighted effort.
        let hold = exercise(
            "Six Inch Hold",
            sets: [loggedSet(reps: 3, weight: 20, duration: 45)]
        )

        let review = SocialPublishableWorkout(strengthWorkout: session(exercises: [hold]))

        XCTAssertNil(review.strengthTotalVolumeKilograms)
        XCTAssertNil(review.strengthHeaviestWeightKilograms)
        XCTAssertNil(review.strengthTotalReps)

        let display = try XCTUnwrap(
            review.strengthPerformedExerciseSummaries?.first
        )
        XCTAssertTrue(display.contains("0:45"))
        XCTAssertFalse(display.contains("kg"))
    }

    func testTimedHoldDoesNotContaminateActualBenchPressVolume() {
        let hold = exercise(
            "Six Inch Hold",
            sets: [loggedSet(reps: 3, weight: 20, duration: 55)]
        )
        let bench = exercise(
            "Bench Press",
            sets: [loggedSet(reps: 10, weight: 30)]
        )

        let review = SocialPublishableWorkout(
            strengthWorkout: session(exercises: [hold, bench])
        )

        XCTAssertEqual(review.strengthTotalVolumeKilograms, 300)
        XCTAssertEqual(review.strengthHeaviestWeightKilograms, 30)
        XCTAssertEqual(review.strengthTotalReps, 10)
        XCTAssertFalse(
            review.strengthPerformedExerciseSummaries?.first?.contains("kg")
                ?? true
        )
        XCTAssertTrue(
            review.strengthPerformedExerciseSummaries?.last?.contains("30.0 kg")
                ?? false
        )
    }
}
