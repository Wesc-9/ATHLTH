import XCTest
@testable import ATHLTH

final class MuscleRecoveryMinuteWeightingTests: XCTestCase {
    func testEveryCanonicalRepDBMuscleMapsIntoRecovery() {
        // All distinct anatomy keys in the 637-exercise public snapshot.
        let sourceNames = [
            "abductors", "adductors", "anterior_deltoid",
            "biceps_brachii", "brachialis", "brachioradialis",
            "erector_spinae", "forearm_extensors", "forearm_flexors",
            "forearms", "gastrocnemius", "gluteus_maximus",
            "gluteus_medius", "hamstrings", "hip_flexors",
            "lateral_deltoid", "latissimus_dorsi", "obliques",
            "pectoralis_major", "posterior_deltoid",
            "quadratus_lumborum", "quadriceps", "rectus_abdominis",
            "rhomboids", "serratus_anterior", "soleus",
            "supraspinatus", "tibialis_anterior",
            "transverse_abdominis", "trapezius", "triceps_brachii"
        ]
        for name in sourceNames {
            XCTAssertNotNil(
                MuscleRecoveryEngine.normalizedMuscleGroup(name),
                "Unrecognized RepDB anatomy: \(name)"
            )
        }
    }

    func testErectorsAndLateralDeltoidAreNeverAssignedWrongArea() {
        XCTAssertEqual(
            MuscleRecoveryEngine.normalizedMuscleGroup("erector_spinae"),
            "Lower Back"
        )
        XCTAssertEqual(
            MuscleRecoveryEngine.normalizedMuscleGroup("lateral_deltoid"),
            "Shoulders"
        )
        XCTAssertEqual(
            MuscleRecoveryEngine.normalizedMuscleGroup("abductors"),
            "Glutes"
        )
        XCTAssertEqual(
            MuscleRecoveryEngine.normalizedMuscleGroup("adductors"),
            "Adductors"
        )
        XCTAssertEqual(
            MuscleRecoveryEngine.normalizedMuscleGroup("gastrocnemius"),
            "Calves"
        )
        XCTAssertEqual(
            MuscleRecoveryEngine.normalizedMuscleGroup("hip_flexors"),
            "Hip Flexors"
        )
        XCTAssertEqual(
            MuscleRecoveryEngine.normalizedMuscleGroup("tibialis_anterior"),
            "Shins"
        )
    }

    func testLegacyBackExtensionsHaveAnatomicalMuscleFallback() {
        let regions = StrengthMuscleResolver.fallbackRegions(
            forExerciseName: "Machine Back Extension"
        )
        XCTAssertTrue(regions.contains(.lowerBack))
    }

    @MainActor
    func testTwentyCoreEssentialsHaveOriginalNorwegianInstructions() {
        let ids = ExerciseLibraryStore.originalCoreSlugs
        XCTAssertEqual(ids.count, 20)
        XCTAssertEqual(Set(ids).count, 20)
        for id in ids {
            XCTAssertNotNil(
                ExerciseLibraryStore.norwegianExerciseNames[id],
                "Missing Norwegian search alias for \(id)"
            )
            XCTAssertEqual(
                ExerciseLibraryStore.norwegianCoreInstructions[id]?.count,
                2,
                "Missing ATHLTH how-to instructions for \(id)"
            )
        }
        let terms = ExerciseLibraryStore.searchableNorwegianTerms(
            sourceIdentifier: "plank",
            bodyPart: "Core",
            primaryMuscles: ["rectus_abdominis"]
        )
        XCTAssertTrue(terms.contains("mage"))
        XCTAssertTrue(terms.contains("Planke"))
    }

    func testShortRunStaysLowLoadAndMostlyReady() {
        let status =
            MuscleRecoveryStatus(
                muscleGroup: "Calves",
                lastTrainedAt: Date(),
                completedSets: 0,
                runningMinutes: 20,
                walkingMinutes: 0,
                estimatedRecoveryHours: 16,
                soreness: .none
            )

        XCTAssertLessThan(
            status.currentLoadScore,
            0.20
        )
        XCTAssertGreaterThan(
            status.readinessScore,
            0.80
        )
        XCTAssertEqual(
            status.loadTitle,
            ATHLTHLocalization.choose(
                english: "Ready",
                norwegian: "Klar"
            )
        )
    }

    func testVeryShortStrengthSessionDoesNotCreateHighLoad() {
        let status =
            MuscleRecoveryStatus(
                muscleGroup: "Quads",
                lastTrainedAt: Date(),
                completedSets: 1,
                strengthMinutes: 5,
                estimatedRecoveryHours: 8,
                soreness: .none
            )

        XCTAssertLessThan(
            status.currentLoadScore,
            0.20
        )
        XCTAssertGreaterThan(
            status.readinessScore,
            0.80
        )
    }

    func testLongStrengthSessionCanCreateMeaningfulLoad() {
        let status =
            MuscleRecoveryStatus(
                muscleGroup: "Quads",
                lastTrainedAt: Date(),
                completedSets: 10,
                strengthMinutes: 60,
                estimatedRecoveryHours: 42,
                soreness: .none
            )

        XCTAssertGreaterThan(
            status.currentLoadScore,
            0.60
        )
        XCTAssertLessThan(
            status.readinessScore,
            0.40
        )
    }

    func testRedThresholdRequiresVeryHighRecentLoad() {
        let moderate =
            MuscleRecoveryStatus(
                muscleGroup: "Calves",
                lastTrainedAt: Date(),
                completedSets: 0,
                runningMinutes: 90,
                estimatedRecoveryHours: 40,
                soreness: .none
            )

        let veryHigh =
            MuscleRecoveryStatus(
                muscleGroup: "Calves",
                lastTrainedAt: Date(),
                completedSets: 0,
                runningMinutes: 180,
                estimatedRecoveryHours: 52,
                soreness: .none
            )

        XCTAssertLessThan(
            moderate.currentLoadScore,
            0.84
        )
        XCTAssertGreaterThanOrEqual(
            veryHigh.currentLoadScore,
            0.84
        )
    }
}
