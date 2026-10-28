import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHTrainingProfileAndExerciseProgressTests: XCTestCase {
    func testPrivateMeasurementsRetainHistoryAndReplaceSameDayOnly() {
        var profile = ATHLTHTrainingProfile()
        let first = Date(timeIntervalSince1970: 1_700_000_000)
        let later = first.addingTimeInterval(10 * 86_400)
        XCTAssertTrue(profile.record(metric: .weight, value: 84.5, at: first))
        XCTAssertTrue(profile.record(metric: .waist, value: 89, at: first))
        XCTAssertTrue(profile.record(metric: .weight, value: 82.3, at: later))
        XCTAssertEqual(profile.readings(for: .weight).count, 2)
        XCTAssertEqual(profile.latest(.weight)?.value, 82.3)
        XCTAssertEqual(profile.latest(.waist)?.value, 89)
        XCTAssertTrue(profile.record(metric: .weight, value: 82.0, at: later))
        XCTAssertEqual(profile.readings(for: .weight).count, 2)
        XCTAssertEqual(profile.latest(.weight)?.value, 82)
    }

    func testInvalidBodyMeasuresNeverEnterHistory() {
        var profile = ATHLTHTrainingProfile()
        XCTAssertFalse(profile.record(metric: .weight, value: -1, at: Date()))
        XCTAssertFalse(profile.record(metric: .thigh, value: .infinity, at: Date()))
        XCTAssertFalse(profile.record(metric: .waist, value: 900, at: Date()))
        XCTAssertTrue(profile.measurements.isEmpty)
    }

    func testPrivateNotesRoundTripWithoutImplicitConsentFields() throws {
        let profile = ATHLTHTrainingProfile(
            trainingNotes: "Gym two days and running outdoors",
            injuryAndLimitations: "Avoid deep squats",
            measurements: []
        )
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(ATHLTHTrainingProfile.self, from: data)
        XCTAssertEqual(decoded.trainingNotes, profile.trainingNotes)
        XCTAssertEqual(decoded.injuryAndLimitations, profile.injuryAndLimitations)
    }

    func testWorkoutCreationIntentNotTriggeredByQuestionsOrPlanCreation() {
        XCTAssertTrue(ATHLTHCoachWorkoutCreationIntent.isRequest(
            "Lag en treningsøkt for bryst på 45 minutter"))
        XCTAssertTrue(ATHLTHCoachWorkoutCreationIntent.isRequest(
            "Help me create a workout for tomorrow"))
        XCTAssertFalse(ATHLTHCoachWorkoutCreationIntent.isRequest(
            "Lag en treningsplan for de neste 8 ukene"))
        XCTAssertFalse(ATHLTHCoachWorkoutCreationIntent.isRequest(
            "Hvorfor er benkpress bra?"))
    }

    private func strengthSession(
        weight: Double, days: Int, completed: Bool = true
    ) -> StrengthWorkoutLog {
        let date = Date(timeIntervalSince1970: 1_700_000_000 +
                        Double(days) * 86_400)
        var sets = (1...3).map { index in
            StrengthSetLog(
                id: UUID(), setNumber: index,
                plannedReps: 8, plannedWeightKilograms: 200,
                completedReps: 8, completedWeightKilograms: weight,
                rpe: nil, completedAt: date, restSeconds: 90
            )
        }
        var warmup = StrengthSetLog(
            id: UUID(), setNumber: 0,
            plannedReps: 12, plannedWeightKilograms: 10,
            completedReps: 12, completedWeightKilograms: 10,
            rpe: nil, completedAt: date, restSeconds: 30
        )
        warmup.isWarmUp = true
        sets.insert(warmup, at: 0)

        return StrengthWorkoutLog(
            id: UUID(), plannedSessionID: nil, watchSessionID: nil,
            captureDevice: .iPhone, trackingMode: .advanced,
            title: "Chest", startedAt: date,
            endedAt: completed ? date.addingTimeInterval(1800) : nil,
            exercises: [StrengthExerciseLog(
                id: UUID(), plannedExerciseID: nil,
                exercise: ExerciseSnapshot(
                    name: "Bench Press", instructions: [],
                    primaryMuscles: ["chest"], secondaryMuscles: [],
                    equipment: ["barbell"], imageURL: nil
                ),
                sets: sets, completedAt: completed ? date : nil
            )],
            healthMetrics: LinkedHealthWorkoutMetrics(
                healthKitWorkoutUUID: nil, duration: nil,
                activeCalories: nil, averageHeartRate: nil, maxHeartRate: nil
            )
        )
    }

    func testExerciseProgressCountsOnlyActualWorkingSetsAndCompletedWorkouts() {
        let summary = ATHLTHExerciseProgress.summary(
            exerciseID: UUID(), name: "Bench Press", isCustom: false,
            workouts: [
                strengthSession(weight: 50, days: 1),
                strengthSession(weight: 60, days: 8),
                strengthSession(weight: 80, days: 9, completed: false)
            ]
        )
        XCTAssertEqual(summary.uses, 2)
        XCTAssertEqual(summary.totalSets, 6)
        XCTAssertEqual(summary.totalRepetitions, 48)
        XCTAssertEqual(summary.bestWeight, 60)
        XCTAssertEqual(summary.totalVolume, 2_640)
        XCTAssertEqual(summary.firstToLastWeightChange, 10)
    }

    func testCustomExerciseDoesNotInheritOtherExercisesHistoryByName() {
        let summary = ATHLTHExerciseProgress.summary(
            exerciseID: UUID(), name: "Bench Press", isCustom: true,
            workouts: [strengthSession(weight: 50, days: 1)]
        )
        XCTAssertEqual(summary.uses, 0)
    }
}
