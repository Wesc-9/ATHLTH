import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHCoachStrengthIntelligenceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_050_000_000)

    private func workout(
        daysAgo: Int,
        reps: Int = 8,
        plannedReps: Int = 8,
        weight: Double = 40,
        includeWarmup: Bool = false
    ) -> StrengthWorkoutLog {
        let when = now.addingTimeInterval(Double(-daysAgo) * 86_400)
        var sets = (1...3).map { index in
            StrengthSetLog(
                id: UUID(), setNumber: index,
                plannedReps: plannedReps,
                plannedWeightKilograms: weight,
                completedReps: reps,
                completedWeightKilograms: weight,
                rpe: nil, completedAt: when,
                restSeconds: 90
            )
        }
        if includeWarmup {
            var warmup = StrengthSetLog(
                id: UUID(), setNumber: 0,
                plannedReps: 8, plannedWeightKilograms: 20,
                completedReps: 8, completedWeightKilograms: 20,
                rpe: nil, completedAt: when, restSeconds: 30
            )
            warmup.isWarmUp = true
            sets.insert(warmup, at: 0)
        }
        return StrengthWorkoutLog(
            id: UUID(), plannedSessionID: nil, watchSessionID: nil,
            captureDevice: .iPhone, trackingMode: .advanced,
            title: "Strength", startedAt: when,
            endedAt: when.addingTimeInterval(1800),
            exercises: [StrengthExerciseLog(
                id: UUID(), plannedExerciseID: nil,
                exercise: ExerciseSnapshot(
                    name: "Bench Press", instructions: [],
                    primaryMuscles: ["chest"], secondaryMuscles: [],
                    equipment: ["barbell"], imageURL: nil
                ),
                sets: sets, completedAt: when
            )],
            healthMetrics: LinkedHealthWorkoutMetrics(
                healthKitWorkoutUUID: nil,
                duration: nil, activeCalories: nil,
                averageHeartRate: nil, maxHeartRate: nil
            )
        )
    }

    func testNoHistoryDoesNotInventStrengthOrRecommendations() {
        let snapshot = ATHLTHCoachStrengthIntelligence.snapshot(from: [], now: now)
        XCTAssertFalse(snapshot.hasEvidence)
        XCTAssertEqual(snapshot.completedStrengthSessions, 0)
        XCTAssertTrue(snapshot.exerciseSignals.isEmpty)
        XCTAssertEqual(snapshot.recordedVolumeKg, 0)
    }

    func testOneRepMaxIsBoundedToActualRecordedExternalLoad() {
        XCTAssertEqual(
            ATHLTHCoachStrengthIntelligence.estimatedOneRepMax(weightKg: 60, reps: 10),
            80
        )
        XCTAssertNil(ATHLTHCoachStrengthIntelligence.estimatedOneRepMax(weightKg: 0, reps: 5))
        XCTAssertNil(ATHLTHCoachStrengthIntelligence.estimatedOneRepMax(weightKg: 60, reps: 20))
        XCTAssertNil(ATHLTHCoachStrengthIntelligence.estimatedOneRepMax(weightKg: .infinity, reps: 5))
    }

    func testTwoVerifiedSessionsPermitOnlyReviewNotAutomaticIncrease() {
        let history = [workout(daysAgo: 4), workout(daysAgo: 11)]
        let snapshot = ATHLTHCoachStrengthIntelligence.snapshot(from: history, now: now)
        XCTAssertEqual(snapshot.completedStrengthSessions, 2)
        XCTAssertEqual(snapshot.strengthSessionsLastSevenDays, 1)
        XCTAssertEqual(snapshot.completedWorkingSets, 6)
        XCTAssertEqual(snapshot.exerciseSignals.count, 1)
        XCTAssertEqual(snapshot.exerciseSignals[0].recommendation, "review_small_increase")
        XCTAssertEqual(snapshot.exerciseSignals[0].completedSessions, 2)
    }

    func testWarmupIgnoredAndLatestMissedTargetsBlockLoadIncrease() {
        let history = [
            workout(daysAgo: 3, reps: 5, includeWarmup: true),
            workout(daysAgo: 9, includeWarmup: true)
        ]
        let snapshot = ATHLTHCoachStrengthIntelligence.snapshot(from: history, now: now)
        XCTAssertEqual(snapshot.completedWorkingSets, 6)
        XCTAssertEqual(snapshot.exerciseSignals[0].recommendation, "hold_and_collect_evidence")
    }

    func testOldAndUnfinishedSessionsDoNotBecomeEvidence() {
        var unfinished = workout(daysAgo: 3)
        unfinished.endedAt = nil
        let snapshot = ATHLTHCoachStrengthIntelligence.snapshot(
            from: [workout(daysAgo: 65), unfinished],
            now: now
        )
        XCTAssertEqual(snapshot.completedStrengthSessions, 0)
        XCTAssertTrue(snapshot.exerciseSignals.isEmpty)
    }

    func testThreeFlatSessionsAcrossTwoWeeksFlagPlateauForReview() {
        let history = [
            workout(daysAgo: 1),
            workout(daysAgo: 9),
            workout(daysAgo: 19)
        ].map { log -> StrengthWorkoutLog in
            var copy = log
            for i in copy.exercises.indices {
                for j in copy.exercises[i].sets.indices {
                    copy.exercises[i].sets[j].plannedReps = nil
                }
            }
            return copy
        }
        let snapshot = ATHLTHCoachStrengthIntelligence.snapshot(from: history, now: now)
        XCTAssertEqual(snapshot.exerciseSignals.first?.trend, "plateau")
        XCTAssertEqual(snapshot.exerciseSignals.first?.recommendation, "review_plateau")
    }
}
