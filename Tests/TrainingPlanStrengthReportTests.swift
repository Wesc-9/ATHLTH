import Foundation
import XCTest
@testable import ATHLTH

final class TrainingPlanStrengthReportTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_900_000_000)

    private func snapshot(muscle: String = "biceps") -> ExerciseSnapshot {
        ExerciseSnapshot(
            name: "Dumbbell Curl",
            instructions: [],
            primaryMuscles: [muscle],
            secondaryMuscles: [],
            equipment: ["Dumbbells"],
            imageURL: nil
        )
    }

    private func plannedExercise(id: UUID) -> PlannedExercise {
        var exercise = PlannedExercise(
            id: id,
            exerciseID: nil,
            embeddedExercise: snapshot(),
            sets: 3,
            reps: 10,
            targetWeightKilograms: nil,
            targetRPE: nil,
            restSeconds: 90,
            notes: nil,
            targetRIR: nil,
            supersetGroupID: nil,
            progression: .none
        )
        exercise.setTargets = [
            PlannedExerciseSetTarget(
                reps: 10,
                isWarmUp: true,
                setType: .warmUp
            ),
            PlannedExerciseSetTarget(reps: 10),
            PlannedExerciseSetTarget(reps: 8)
        ]
        return exercise
    }

    private func plan(sessionID: UUID, exerciseID: UUID) -> TrainingPlan {
        let workout = PlannedSession(
            id: sessionID,
            title: "Biceps",
            kind: .strength,
            scheduledStart: nil,
            durationMinutes: 40,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil,
            exercises: [plannedExercise(id: exerciseID)],
            notes: nil,
            runningWorkout: nil
        )
        let firstDay = TrainingPlanDay(
            id: UUID(),
            dayIndex: 1,
            title: "Monday",
            sessions: [workout]
        )
        let week = TrainingPlanWeek(
            id: UUID(),
            weekNumber: 1,
            title: "Week 1",
            days: [firstDay]
        )
        return TrainingPlan(
            id: UUID(),
            ownerID: UUID(),
            title: "Arms",
            summary: "",
            visibility: .privateOnly,
            version: 1,
            weeks: [week],
            tags: [],
            createdAt: date,
            updatedAt: date,
            startDate: date,
            endDate: date
        )
    }

    private func loggedWorkout(
        sessionID: UUID?,
        exerciseID: UUID,
        completed: Bool = true
    ) -> StrengthWorkoutLog {
        let warmup = StrengthSetLog(
            id: UUID(),
            setNumber: 1,
            plannedReps: 10,
            plannedWeightKilograms: nil,
            completedReps: 10,
            completedWeightKilograms: 5,
            rpe: nil,
            completedAt: date,
            restSeconds: 60,
            isWarmUp: true
        )
        var work = StrengthSetLog(
            id: UUID(),
            setNumber: 2,
            plannedReps: 10,
            plannedWeightKilograms: nil,
            completedReps: 10,
            completedWeightKilograms: 10,
            rpe: nil,
            completedAt: date,
            restSeconds: 90
        )
        work.effortSegments = [
            StrengthSetEffortSegment(reps: 8, weightKilograms: 10),
            StrengthSetEffortSegment(reps: 2, weightKilograms: 8)
        ]
        let exercise = StrengthExerciseLog(
            id: UUID(),
            plannedExerciseID: exerciseID,
            exercise: snapshot(),
            sets: [warmup, work],
            completedAt: date
        )
        return StrengthWorkoutLog(
            id: UUID(),
            plannedSessionID: sessionID,
            watchSessionID: nil,
            captureDevice: .iPhone,
            trackingMode: .advanced,
            title: "Biceps",
            startedAt: date,
            endedAt: completed ? date.addingTimeInterval(1800) : nil,
            exercises: [exercise],
            healthMetrics: LinkedHealthWorkoutMetrics(
                healthKitWorkoutUUID: nil,
                duration: nil,
                activeCalories: nil,
                averageHeartRate: nil,
                maxHeartRate: nil
            )
        )
    }

    func testPlannedSetsExcludeWarmUpAndDoNotInventLoggedResults() {
        let sessionID = UUID()
        let exerciseID = UUID()
        let report = TrainingPlanStrengthReport.make(
            plan: plan(sessionID: sessionID, exerciseID: exerciseID),
            strengthHistory: []
        )

        XCTAssertEqual(report.totalPlannedStrengthSets, 2)
        XCTAssertEqual(report.totalPerformedStrengthSets, 0)
        XCTAssertEqual(report.totalRecordedVolumeKilograms, 0)
        XCTAssertEqual(report.loggedSessionCount, 0)
        XCTAssertEqual(report.muscles.first?.id, "biceps")
        XCTAssertEqual(report.muscles.first?.plannedWorkingSets, 2)
    }

    func testLinkedCompletedSessionUsesRealWorkingSetsAndSplitVolume() {
        let sessionID = UUID()
        let exerciseID = UUID()
        let log = loggedWorkout(sessionID: sessionID, exerciseID: exerciseID)
        let report = TrainingPlanStrengthReport.make(
            plan: plan(sessionID: sessionID, exerciseID: exerciseID),
            strengthHistory: [log]
        )

        XCTAssertEqual(report.loggedSessionCount, 1)
        XCTAssertEqual(report.totalPlannedStrengthSets, 2)
        XCTAssertEqual(report.totalPerformedStrengthSets, 1)
        XCTAssertEqual(report.totalRecordedVolumeKilograms, 96)
        XCTAssertEqual(report.muscles.first?.performedVolumeKilograms, 96)
        XCTAssertEqual(report.weeks.first?.loggedStrengthSessions, 1)
        XCTAssertEqual(report.exerciseSummaries.count, 1)
        XCTAssertEqual(report.exerciseSummaries.first?.workingSets, 1)
        XCTAssertEqual(report.exerciseSummaries.first?.loggedSessions, 1)
        XCTAssertEqual(report.exerciseSummaries.first?.volumeKilograms, 96)
        XCTAssertEqual(report.exerciseSummaries.first?.peakWeightKilograms, 10)
    }

    func testUnlinkedAndUnfinishedWorkoutsAreNotAttributedToPlan() {
        let sessionID = UUID()
        let exerciseID = UUID()
        let unrelated = loggedWorkout(sessionID: UUID(), exerciseID: exerciseID)
        let unfinished = loggedWorkout(
            sessionID: sessionID,
            exerciseID: exerciseID,
            completed: false
        )
        let report = TrainingPlanStrengthReport.make(
            plan: plan(sessionID: sessionID, exerciseID: exerciseID),
            strengthHistory: [unrelated, unfinished]
        )

        XCTAssertEqual(report.loggedSessionCount, 0)
        XCTAssertEqual(report.totalPerformedStrengthSets, 0)
        XCTAssertEqual(report.totalRecordedVolumeKilograms, 0)
    }
    private func strengthPlanWithPrescribedWeight(
        sessionID: UUID,
        exerciseID: UUID
    ) -> TrainingPlan {
        var training = plan(sessionID: sessionID, exerciseID: exerciseID)
        training.weeks[0].days[0].sessions[0]
            .exercises[0].targetWeightKilograms = 10
        return training
    }

    private func secondRecordedWorkSet(
        reps: Int = 8,
        rir: Double? = 2
    ) -> StrengthSetLog {
        var logged = StrengthSetLog(
            id: UUID(),
            setNumber: 3,
            plannedReps: 8,
            plannedWeightKilograms: 10,
            completedReps: reps,
            completedWeightKilograms: 10,
            rpe: nil,
            completedAt: date,
            restSeconds: 90
        )
        logged.rir = rir
        return logged
    }

    func testAdvisorDoesNotTreatSplitSetAsTargetWeightCompleted() {
        let sessionID = UUID()
        let exerciseID = UUID()
        let training = strengthPlanWithPrescribedWeight(
            sessionID: sessionID,
            exerciseID: exerciseID
        )
        var workout = loggedWorkout(
            sessionID: sessionID,
            exerciseID: exerciseID
        )
        // The first working set was 8x10 kg + 2x8 kg, not 10x10 kg.
        workout.exercises[0].sets[1].rir = 2
        workout.exercises[0].sets.append(secondRecordedWorkSet())

        let advice = TrainingPlanLoadAdvisor.evaluate(
            plan: training,
            strengthHistory: [workout]
        )
        XCTAssertEqual(advice.count, 1)
        XCTAssertEqual(advice.first?.verdict, .reviewTargets)
        XCTAssertNil(advice.first?.suggestedNextWeightKilograms)
        XCTAssertEqual(advice.first?.completedWorkSets, 2)
        XCTAssertEqual(advice.first?.plannedWorkSets, 2)
    }

    func testAdvisorRequiresLoggedRIRForIncreaseSuggestion() {
        let sessionID = UUID()
        let exerciseID = UUID()
        let training = strengthPlanWithPrescribedWeight(
            sessionID: sessionID,
            exerciseID: exerciseID
        )
        var workout = loggedWorkout(
            sessionID: sessionID,
            exerciseID: exerciseID
        )
        workout.exercises[0].sets[1].effortSegments = [
            StrengthSetEffortSegment(reps: 10, weightKilograms: 10)
        ]
        workout.exercises[0].sets[1].rir = 2
        workout.exercises[0].sets.append(secondRecordedWorkSet())

        let ready = TrainingPlanLoadAdvisor.evaluate(
            plan: training,
            strengthHistory: [workout]
        )
        XCTAssertEqual(ready.first?.verdict, .considerIncrease)
        XCTAssertEqual(ready.first?.suggestedNextWeightKilograms, 10.5)

        workout.exercises[0].sets[1].rir = nil
        let withoutRealRIR = TrainingPlanLoadAdvisor.evaluate(
            plan: training,
            strengthHistory: [workout]
        )
        XCTAssertEqual(withoutRealRIR.first?.verdict, .targetMet)
        XCTAssertNil(withoutRealRIR.first?.suggestedNextWeightKilograms)
    }

    func testAdvisorNeverLinksUnrelatedOrUnfinishedWorkouts() {
        let sessionID = UUID()
        let exerciseID = UUID()
        let training = strengthPlanWithPrescribedWeight(
            sessionID: sessionID,
            exerciseID: exerciseID
        )
        let unrelated = loggedWorkout(
            sessionID: UUID(),
            exerciseID: exerciseID
        )
        let unfinished = loggedWorkout(
            sessionID: sessionID,
            exerciseID: exerciseID,
            completed: false
        )

        let advice = TrainingPlanLoadAdvisor.evaluate(
            plan: training,
            strengthHistory: [unrelated, unfinished]
        )
        XCTAssertTrue(advice.isEmpty)
    }

}
