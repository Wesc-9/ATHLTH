import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHCoachStrengthComparableHistoryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_050_000_000)

    private func exercise(
        name: String = "Bench Press",
        equipment: [String] = ["barbell"],
        primaryMuscles: [String] = ["chest"],
        sets: [StrengthSetLog]? = nil
    ) -> StrengthExerciseLog {
        StrengthExerciseLog(
            id: UUID(),
            plannedExerciseID: nil,
            exercise: ExerciseSnapshot(
                name: name, instructions: [],
                primaryMuscles: primaryMuscles,
                secondaryMuscles: [],
                equipment: equipment,
                imageURL: nil
            ),
            sets: sets ?? [workingSet()],
            completedAt: now
        )
    }

    private func workingSet() -> StrengthSetLog {
        StrengthSetLog(
            id: UUID(),
            setNumber: 1,
            plannedReps: 8,
            plannedWeightKilograms: 60,
            completedReps: 8,
            completedWeightKilograms: 60,
            rpe: 8,
            completedAt: now,
            restSeconds: 90
        )
    }

    private func workout(
        daysAgo: Int,
        exercises: [StrengthExerciseLog],
        completed: Bool = true
    ) -> StrengthWorkoutLog {
        let date = now.addingTimeInterval(-Double(daysAgo) * 86_400)
        return StrengthWorkoutLog(
            id: UUID(),
            plannedSessionID: nil,
            watchSessionID: nil,
            captureDevice: .iPhone,
            trackingMode: .advanced,
            title: "Strength",
            startedAt: date,
            endedAt: completed ? date.addingTimeInterval(3_600) : nil,
            exercises: exercises,
            healthMetrics: LinkedHealthWorkoutMetrics(
                healthKitWorkoutUUID: nil,
                duration: nil,
                activeCalories: nil,
                averageHeartRate: nil,
                maxHeartRate: nil
            )
        )
    }

    func testSameNameDifferentEquipmentCannotBecomeProgressionEvidence() {
        let target = exercise()
        let history = [
            workout(daysAgo: 1, exercises: [
                exercise(equipment: ["dumbbell"])
            ]),
            workout(daysAgo: 2, exercises: [
                exercise(name: " BENCH PRESS ", equipment: ["BARBELL"])
            ])
        ]
        let result = ATHLTHCoachStrengthComparableHistory.sessions(
            for: target, in: history, now: now
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].exercise.exercise.equipment, ["BARBELL"])
    }

    func testDifferentMovementNeverMatchesEvenWithSameEquipment() {
        let result = ATHLTHCoachStrengthComparableHistory.sessions(
            for: exercise(),
            in: [workout(daysAgo: 1, exercises: [exercise(name: "Incline Bench Press")])],
            now: now
        )
        XCTAssertTrue(result.isEmpty)
    }

    func testWarmupSkippedTimedAndResistanceSetsAreNotWorkingEvidence() {
        var warmup = workingSet()
        warmup.isWarmUp = true
        var skipped = workingSet()
        skipped.completedAt = nil
        skipped.skippedAt = now
        var timed = workingSet()
        timed.targetKind = .time
        var resistance = workingSet()
        resistance.loadKind = .resistanceLevel
        var unloaded = workingSet()
        unloaded.recordsWeight = false
        var drop = workingSet()
        drop.effortSegments = [
            StrengthSetEffortSegment(
                reps: 4,
                weightKilograms: 60
            ),
            StrengthSetEffortSegment(
                reps: 4,
                weightKilograms: 45
            )
        ]

        for invalid in [warmup, skipped, timed, resistance, unloaded, drop] {
            XCTAssertFalse(
                ATHLTHCoachStrengthComparableHistory.isComparableWorkingSet(invalid)
            )
        }
        XCTAssertTrue(
            ATHLTHCoachStrengthComparableHistory.isComparableWorkingSet(workingSet())
        )
    }

    func testUnfinishedFutureAndStaleHistoryExcluded() {
        let target = exercise()
        let history = [
            workout(daysAgo: -1, exercises: [exercise()]),
            workout(daysAgo: 3, exercises: [exercise()], completed: false),
            workout(daysAgo: 60, exercises: [exercise()]),
            workout(daysAgo: 5, exercises: [exercise()])
        ]
        let result = ATHLTHCoachStrengthComparableHistory.sessions(
            for: target, in: history, now: now
        )
        XCTAssertEqual(result.count, 1)
    }

    func testDistinctSessionsAreOrderedAndBounded() {
        let workouts = (1...7).map {
            workout(daysAgo: $0, exercises: [exercise()])
        }
        let result = ATHLTHCoachStrengthComparableHistory.sessions(
            for: exercise(), in: workouts, now: now, limit: 3
        )
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(Set(result.map(\.workoutID)).count, 3)
        XCTAssertGreaterThan(result[0].date, result[1].date)
        XCTAssertGreaterThan(result[1].date, result[2].date)
    }

    func testCanonicalLibraryIdentityPreventsAccidentalMatching() {
        var original = exercise().exercise
        var variant = original
        let id = UUID()
        original.libraryExerciseID = id
        variant.libraryExerciseID = UUID()
        XCTAssertFalse(ATHLTHCoachStrengthComparableHistory.isSameExercise(
            original, variant
        ))
        variant.libraryExerciseID = nil
        XCTAssertFalse(ATHLTHCoachStrengthComparableHistory.isSameExercise(
            original, variant
        ))
        variant.libraryExerciseID = id
        variant.name = "Updated bench press label"
        variant.primaryMuscles = ["upper chest"]
        XCTAssertTrue(ATHLTHCoachStrengthComparableHistory.isSameExercise(
            original, variant
        ))
        XCTAssertEqual(
            ATHLTHCoachStrengthComparableHistory.identityKey(for: original),
            ATHLTHCoachStrengthComparableHistory.identityKey(for: variant)
        )
    }

    func testExplicitLoadBasisMustMatchAcrossSessions() {
        var total = exercise().exercise
        total.libraryExerciseID = UUID()
        total.coachLoadBasis = .totalKilograms
        var perHand = total
        perHand.coachLoadBasis = .kilogramsPerHand

        XCTAssertFalse(ATHLTHCoachStrengthComparableHistory.isSameExercise(
            total, perHand
        ))
        XCTAssertNotEqual(
            ATHLTHCoachStrengthComparableHistory.identityKey(for: total),
            ATHLTHCoachStrengthComparableHistory.identityKey(for: perHand)
        )

        perHand.coachLoadBasis = nil
        XCTAssertFalse(ATHLTHCoachStrengthComparableHistory.isSameExercise(
            total, perHand
        ))
        perHand.coachLoadBasis = .totalKilograms
        XCTAssertTrue(ATHLTHCoachStrengthComparableHistory.isSameExercise(
            total, perHand
        ))
    }

    func testMissingEquipmentCannotJustifyWeightIncrease() {
        let first = exercise(equipment: []).exercise
        let second = exercise(equipment: []).exercise
        XCTAssertFalse(ATHLTHCoachStrengthComparableHistory.isSameExercise(
            first, second
        ))
    }

    func testSkippedWorkingSetBlocksSuccessfulSessionEvidence() {
        var skipped = workingSet()
        skipped.completedAt = nil
        skipped.skippedAt = now
        let entry = exercise(sets: [workingSet(), workingSet(), skipped])
        XCTAssertNil(ATHLTHCoachStrengthComparableHistory.targetEvidence(
            for: entry
        ))
    }

    func testVeryHardEffortCannotSupportLoadIncrease() {
        var nearFailure = workingSet()
        nearFailure.rir = 0
        let entry = exercise(sets: [workingSet(), nearFailure])
        let result = ATHLTHCoachStrengthComparableHistory.targetEvidence(
            for: entry
        )
        XCTAssertEqual(result?.metAllTargets, false)
    }

    func testTwoSuccessfulSetsIncludeBothProvenanceIDs() {
        let first = workingSet()
        let second = workingSet()
        let result = ATHLTHCoachStrengthComparableHistory.targetEvidence(
            for: exercise(sets: [first, second]), minimumLoadKg: 60
        )
        XCTAssertEqual(result?.workingSetIDs.count, 2)
        XCTAssertEqual(result?.minimumRecordedWeightKg, 60)
        XCTAssertEqual(result?.metAllTargets, true)
    }

    func testFullySkippedLatestSessionIsStillVisibleAsVetoEvidence() {
        var skipped = workingSet()
        skipped.completedAt = nil
        skipped.skippedAt = now
        let prior = workout(daysAgo: 10, exercises: [
            exercise(sets: [workingSet(), workingSet()])
        ])
        let latest = workout(daysAgo: 1, exercises: [
            exercise(sets: [skipped, skipped])
        ])
        let sessions = ATHLTHCoachStrengthComparableHistory.sessions(
            for: exercise(), in: [prior, latest], now: now
        )
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions.first?.workoutID, latest.id)
        XCTAssertNil(sessions.first.flatMap {
            ATHLTHCoachStrengthComparableHistory.targetEvidence(
                for: $0.exercise
            )
        })
    }

    func testRepeatedExerciseInOneWorkoutIsAmbiguous() {
        let repeated = workout(daysAgo: 1, exercises: [
            exercise(sets: [workingSet(), workingSet()]),
            exercise(sets: [workingSet(), workingSet()])
        ])
        let result = ATHLTHCoachStrengthComparableHistory.sessions(
            for: exercise(), in: [repeated], now: now
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.isAmbiguous, true)
    }

    func testNoEvidenceWhenCurrentTargetIsTimedOrMachineResistance() {
        var timed = workingSet()
        timed.targetKind = .time
        var resistance = workingSet()
        resistance.loadKind = .resistanceLevel
        let history = [workout(daysAgo: 2, exercises: [exercise()])]
        for invalid in [timed, resistance] {
            XCTAssertTrue(
                ATHLTHCoachStrengthComparableHistory.sessions(
                    for: exercise(sets: [invalid]), in: history, now: now
                ).isEmpty
            )
        }
    }
}
