import Foundation
import XCTest
@testable import ATHLTH

@MainActor
final class ATHLTHLibraryWorkoutHistoryIndexTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_800_000_000)

    private func workout(
        exerciseID: UUID, name: String, date: Date, completed: Bool = true
    ) -> StrengthWorkoutLog {
        let set = StrengthSetLog(
            id: UUID(), setNumber: 1,
            plannedReps: 10, plannedWeightKilograms: 25,
            completedReps: completed ? 10 : nil,
            completedWeightKilograms: completed ? 25 : nil,
            rpe: nil, completedAt: completed ? date : nil,
            restSeconds: 60
        )
        let exercise = StrengthExerciseLog(
            id: UUID(), plannedExerciseID: exerciseID,
            exercise: ExerciseSnapshot(
                name: name,
                instructions: [],
                primaryMuscles: ["Biceps"],
                secondaryMuscles: [],
                equipment: [],
                imageURL: nil
            ),
            sets: [set], completedAt: completed ? date : nil
        )
        return StrengthWorkoutLog(
            id: UUID(), plannedSessionID: nil, watchSessionID: nil,
            captureDevice: .iPhone, trackingMode: .advanced,
            title: "Strength", startedAt: date.addingTimeInterval(-900),
            endedAt: completed ? date : nil, exercises: [exercise],
            healthMetrics: LinkedHealthWorkoutMetrics(
                healthKitWorkoutUUID: nil, duration: 900,
                activeCalories: nil, averageHeartRate: nil, maxHeartRate: nil
            )
        )
    }

    func testIndexedResultsEqualHistoricalRowLookup() {
        let id = UUID()
        let earlier = workout(
            exerciseID: id, name: "Barbell Curl",
            date: date.addingTimeInterval(-3_600)
        )
        let newer = workout(exerciseID: id, name: "Barbell Curl", date: date)
        let workouts = [earlier, newer]
        let index = ATHLTHLibraryWorkoutHistory.strengthExerciseIndex(
            workouts: workouts
        )
        let cached = index.summary(id: id, canonicalName: "Barbell Curl",
                                   isCustom: false)
        let original = ATHLTHLibraryWorkoutHistory.strengthExercise(
            id: id, canonicalName: "Barbell Curl",
            isCustom: false, workouts: workouts
        )
        XCTAssertEqual(cached, original)
        XCTAssertEqual(cached?.date, date)
    }

    func testCustomExerciseNeverInheritsResultsByNameOnly() {
        let trainedID = UUID()
        let unrelatedID = UUID()
        let workouts = [workout(exerciseID: trainedID,
                                name: "My Curl", date: date)]
        let index = ATHLTHLibraryWorkoutHistory.strengthExerciseIndex(
            workouts: workouts
        )
        XCTAssertNil(index.summary(id: unrelatedID, canonicalName: "My Curl",
                                   isCustom: true))
        XCTAssertEqual(index.summary(id: trainedID, canonicalName: "My Curl",
                                     isCustom: true)?.date, date)
        XCTAssertEqual(index.summary(id: unrelatedID, canonicalName: "My Curl",
                                     isCustom: false)?.date, date)
    }

    func testUnfinishedWorkoutAddsNoHistoryBadge() {
        let id = UUID()
        let index = ATHLTHLibraryWorkoutHistory.strengthExerciseIndex(
            workouts: [workout(exerciseID: id, name: "Barbell Curl",
                               date: date, completed: false)]
        )
        XCTAssertNil(index.summary(id: id, canonicalName: "Barbell Curl",
                                   isCustom: false))
    }
}
