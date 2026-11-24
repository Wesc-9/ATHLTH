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

    func testStructuredInjuriesAreOptionalAndRespectLegacyProfile() throws {
        let legacy = ATHLTHTrainingProfile(
            trainingNotes: "Strength",
            injuryAndLimitations: "Previous knee note",
            measurements: []
        )
        let encoded = try JSONEncoder().encode(legacy)
        let dictionary = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var previousVersion = dictionary
        previousVersion.removeValue(forKey: "injuryRestrictions")
        let decoded = try JSONDecoder().decode(
            ATHLTHTrainingProfile.self,
            from: JSONSerialization.data(withJSONObject: previousVersion)
        )
        XCTAssertNil(decoded.injuryRestrictions)
        XCTAssertEqual(decoded.coachLimitationsSummary, "Previous knee note")
    }

    func testRestrictionLevelsAndCoachNotesPreserveTheStrongestSafetyRule() throws {
        var profile = ATHLTHTrainingProfile()
        profile.injuryRestrictions = [
            ATHLTHInjuryRestriction(area: .knee, side: .left, level: .avoid),
            ATHLTHInjuryRestriction(area: .neck, side: .unspecified,
                                    level: .moderate, notes: "Avoid overhead work")
        ]
        let summary = profile.coachLimitationsSummary
        XCTAssertTrue(summary.contains("DO NOT prescribe"))
        XCTAssertTrue(summary.contains("left knee"))
        XCTAssertTrue(summary.contains("neck"))
        XCTAssertTrue(summary.contains("Avoid overhead work"))
        let restored = try JSONDecoder().decode(
            ATHLTHTrainingProfile.self, from: JSONEncoder().encode(profile)
        )
        XCTAssertEqual(restored.injuryRestrictions?.count, 2)
        XCTAssertEqual(restored.coachLimitationsSummary, summary)
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

    func testGhostProgressNeverCountsPlannedSetsOrExceedsProgressRange() {
        let progress = ATHLTHExerciseProgress.GhostProgress(sets: [])
        let reference = ATHLTHExerciseProgress.Session(
            id: UUID(), date: Date(), workoutTitle: "Reference", completedSets: 3,
            repetitions: 24, volumeKilograms: 1200, highestWeightKilograms: 50)
        XCTAssertEqual(progress.sets, 0)
        XCTAssertEqual(progress.reps, 0)
        XCTAssertEqual(progress.volume, 0)
        XCTAssertEqual(progress.setProgress(against: reference), 0)
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

    func testBodyweightProgressShowsRepsButNoZeroKilogramVolume() {
        let bodyweight = ATHLTHExerciseProgress.summary(
            exerciseID: UUID(), name: "Bench Press", isCustom: false,
            workouts: [strengthSession(weight: 0, days: 1)]
        )
        XCTAssertEqual(bodyweight.uses, 1)
        XCTAssertEqual(bodyweight.totalSets, 3)
        XCTAssertEqual(bodyweight.totalRepetitions, 24)
        XCTAssertEqual(bodyweight.totalVolume, 0)
        XCTAssertNil(bodyweight.bestWeight)
        XCTAssertFalse(bodyweight.hasMeaningfulLoad)

        let loaded = ATHLTHExerciseProgress.summary(
            exerciseID: UUID(), name: "Bench Press", isCustom: false,
            workouts: [strengthSession(weight: 50, days: 2)]
        )
        XCTAssertTrue(loaded.hasMeaningfulLoad)
    }

    func testProgressChartFollowsCanonicalExerciseAcrossRenames() {
        let libraryID = UUID()
        var reference = ExerciseSnapshot(
            name: "Bench Press", instructions: [],
            primaryMuscles: ["chest"], secondaryMuscles: [],
            equipment: ["barbell"], imageURL: nil
        )
        reference.libraryExerciseID = libraryID
        var logged = strengthSession(weight: 60, days: 2)
        logged.exercises[0].exercise.libraryExerciseID = libraryID
        logged.exercises[0].exercise.name = "Barbell Bench Press"

        let summary = ATHLTHExerciseProgress.summary(
            exerciseID: libraryID, name: "Bench Press", isCustom: true,
            workouts: [logged], reference: reference
        )
        XCTAssertEqual(summary.uses, 1)
        XCTAssertEqual(summary.bestWeight, 60)
    }

    func testProgressChartDoesNotMixLibraryExercisesSharingSameName() {
        let libraryID = UUID()
        var reference = ExerciseSnapshot(
            name: "Bench Press", instructions: [],
            primaryMuscles: ["chest"], secondaryMuscles: [],
            equipment: ["barbell"], imageURL: nil
        )
        reference.libraryExerciseID = libraryID
        var other = strengthSession(weight: 90, days: 4)
        other.exercises[0].exercise.libraryExerciseID = UUID()
        let summary = ATHLTHExerciseProgress.summary(
            exerciseID: libraryID, name: "Bench Press", isCustom: false,
            workouts: [other], reference: reference
        )
        XCTAssertEqual(summary.uses, 0)
        XCTAssertNil(summary.bestWeight)
    }

    func testProgressChartRejectsLegacyApparatusOrLoadBasisMismatch() {
        let libraryID = UUID()
        var reference = ExerciseSnapshot(
            name: "Bench Press", instructions: [],
            primaryMuscles: ["chest"], secondaryMuscles: [],
            equipment: ["barbell"], imageURL: nil
        )
        reference.libraryExerciseID = libraryID
        reference.coachLoadBasis = .totalKilograms
        let legacy = strengthSession(weight: 50, days: 1)
        var wrongEquipment = strengthSession(weight: 95, days: 2)
        wrongEquipment.exercises[0].exercise.equipment = ["dumbbells"]
        var wrongBasis = strengthSession(weight: 110, days: 3)
        wrongBasis.exercises[0].exercise.coachLoadBasis = .kilogramsPerHand

        let summary = ATHLTHExerciseProgress.summary(
            exerciseID: libraryID, name: "Bench Press", isCustom: false,
            workouts: [legacy, wrongEquipment, wrongBasis],
            reference: reference
        )
        XCTAssertEqual(summary.uses, 0)

        var compatible = legacy
        compatible.exercises[0].exercise.coachLoadBasis = .totalKilograms
        let matching = ATHLTHExerciseProgress.summary(
            exerciseID: libraryID, name: "Bench Press", isCustom: false,
            workouts: [compatible], reference: reference
        )
        XCTAssertEqual(matching.uses, 1)
        XCTAssertEqual(matching.bestWeight, 50)
    }

    func testProgressChartKeepsLegacyMatchingWhenBasisUnknownBothSides() {
        let exerciseID = UUID()
        var reference = ExerciseSnapshot(
            name: "Bench Press", instructions: [],
            primaryMuscles: ["chest"], secondaryMuscles: [],
            equipment: ["barbell"], imageURL: nil
        )
        reference.libraryExerciseID = exerciseID
        let summary = ATHLTHExerciseProgress.summary(
            exerciseID: exerciseID, name: "Bench Press", isCustom: false,
            workouts: [strengthSession(weight: 55, days: 1)],
            reference: reference
        )
        XCTAssertEqual(summary.uses, 1)
        XCTAssertEqual(summary.bestWeight, 55)
    }

    func testCustomExerciseDoesNotInheritOtherExercisesHistoryByName() {
        let summary = ATHLTHExerciseProgress.summary(
            exerciseID: UUID(), name: "Bench Press", isCustom: true,
            workouts: [strengthSession(weight: 50, days: 1)]
        )
        XCTAssertEqual(summary.uses, 0)
    }
}
