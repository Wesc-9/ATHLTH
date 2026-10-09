import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHTrainTrendEngineTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_900_000_000)
    private let sessionID = UUID()
    private let exerciseID = UUID()

    private func snapshot(_ name: String = "Bicepscurl") -> ExerciseSnapshot {
        ExerciseSnapshot(
            name: name, instructions: [],
            primaryMuscles: ["biceps"], secondaryMuscles: [],
            equipment: ["Dumbbells"], imageURL: nil
        )
    }

    private func plan() -> TrainingPlan {
        let curl = PlannedExercise(
            id: exerciseID,
            exerciseID: nil,
            embeddedExercise: snapshot(),
            sets: 3, reps: 10,
            targetWeightKilograms: 14,
            targetRPE: nil,
            restSeconds: 90,
            notes: nil
        )
        let planned = PlannedSession(
            id: sessionID, title: "Upper body", kind: .strength,
            scheduledStart: date, durationMinutes: 45,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil, exercises: [curl], notes: nil
        )
        return TrainingPlan(
            id: UUID(), ownerID: UUID(), title: "Strong",
            summary: "", visibility: .privateOnly,
            version: 1,
            weeks: [
                TrainingPlanWeek(
                    id: UUID(), weekNumber: 1, title: "Week 1",
                    days: [
                        TrainingPlanDay(
                            id: UUID(), dayIndex: 1,
                            title: "Monday", sessions: [planned]
                        )
                    ]
                )
            ],
            tags: [], createdAt: date, updatedAt: date,
            startDate: date
        )
    }

    private func completedSet(
        weight: Double? = 14,
        reps: Int = 10,
        warmup: Bool = false
    ) -> StrengthSetLog {
        StrengthSetLog(
            id: UUID(), setNumber: 1,
            plannedReps: 10,
            plannedWeightKilograms: 14,
            completedReps: reps,
            completedWeightKilograms: weight,
            rpe: nil,
            completedAt: date,
            restSeconds: 90,
            isWarmUp: warmup
        )
    }

    private func logged(
        linked: UUID?,
        sets: [StrengthSetLog],
        complete: Bool = true,
        id: UUID = UUID(),
        exerciseName: String = "Bicepscurl"
    ) -> StrengthWorkoutLog {
        StrengthWorkoutLog(
            id: id, plannedSessionID: linked,
            watchSessionID: nil, captureDevice: .iPhone,
            trackingMode: .advanced, title: "Upper body",
            startedAt: date,
            endedAt: complete ? date.addingTimeInterval(1800) : nil,
            exercises: [
                StrengthExerciseLog(
                    id: UUID(), plannedExerciseID: exerciseID,
                    exercise: snapshot(exerciseName),
                    sets: sets, completedAt: date
                )
            ],
            healthMetrics: LinkedHealthWorkoutMetrics(
                healthKitWorkoutUUID: nil, duration: nil,
                activeCalories: nil, averageHeartRate: nil,
                maxHeartRate: nil
            )
        )
    }

    func testEmptyHistoryShowsNoFabricatedPerformancePoints() {
        let snapshot = ATHLTHTrainTrendEngine.make(
            plan: plan(), strengthHistory: []
        )
        XCTAssertEqual(snapshot.linkedWorkoutCount, 0)
        XCTAssertEqual(snapshot.points.count, 0)
        XCTAssertEqual(snapshot.exercises.count, 1)
        XCTAssertEqual(snapshot.exercises.first?.title, "Bicepscurl")
    }

    func testUnrelatedOrUnfinishedLogsNeverCreateResults() {
        let unrelated = logged(linked: UUID(), sets: [completedSet()])
        let unfinished = logged(
            linked: sessionID, sets: [completedSet()], complete: false
        )
        let result = ATHLTHTrainTrendEngine.make(
            plan: plan(), strengthHistory: [unrelated, unfinished]
        )
        XCTAssertTrue(result.points.isEmpty)
        XCTAssertEqual(result.linkedWorkoutCount, 0)
        XCTAssertEqual(result.unlinkedWorkoutCount, 1)
    }

    func testOnlyCompletedWorkingSetsContributeVolumeAndLoad() {
        let warmup = completedSet(weight: 5, warmup: true)
        let valid = completedSet(weight: 14, reps: 10)
        var unfinished = completedSet(weight: 50, reps: 5)
        unfinished.completedAt = nil
        let result = ATHLTHTrainTrendEngine.make(
            plan: plan(),
            strengthHistory: [
                logged(linked: sessionID, sets: [warmup, valid, unfinished])
            ]
        )
        let value = try? XCTUnwrap(result.points.first)
        XCTAssertEqual(value?.completedWorkingSets, 1)
        XCTAssertEqual(value?.peakWeightKilograms, 14)
        XCTAssertEqual(value?.volumeKilograms, 140)
        XCTAssertEqual(value?.completedRepetitions, 10)
    }

    func testSplitSetsUseActualEffortSegmentsAndAvoidAggregateWeight() {
        var drop = completedSet(weight: nil, reps: 10)
        drop.effortSegments = [
            StrengthSetEffortSegment(reps: 8, weightKilograms: 14),
            StrengthSetEffortSegment(reps: 2, weightKilograms: 10)
        ]
        let result = ATHLTHTrainTrendEngine.make(
            plan: plan(), strengthHistory: [
                logged(linked: sessionID, sets: [drop])
            ]
        )
        XCTAssertEqual(result.points.first?.peakWeightKilograms, 14)
        XCTAssertEqual(result.points.first?.volumeKilograms, 132)
    }

    func testDuplicateHistoryEntriesNotCountedTwice() {
        let same = logged(linked: sessionID, sets: [completedSet()])
        let result = ATHLTHTrainTrendEngine.make(
            plan: plan(), strengthHistory: [same, same]
        )
        XCTAssertEqual(result.linkedWorkoutCount, 1)
        XCTAssertEqual(result.points.first?.completedWorkingSets, 1)
        XCTAssertEqual(result.points.first?.volumeKilograms, 140)
    }

    func testLegacyRenamedExerciseResolvesToPlanNameByID() {
        let result = ATHLTHTrainTrendEngine.make(
            plan: plan(), strengthHistory: [
                logged(
                    linked: sessionID,
                    sets: [completedSet()],
                    exerciseName: "Dumbbell Curl"
                )
            ]
        )
        XCTAssertEqual(result.exercises.count, 1)
        XCTAssertEqual(result.points.first?.exerciseID, "bicepscurl")
    }
}
