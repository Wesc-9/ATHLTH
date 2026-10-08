import XCTest
@testable import ATHLTH

final class StrengthMuscleProfileTests: XCTestCase {
    func testBenchPressMusclesMapToExpectedBodyRegions() {
        XCTAssertEqual(
            StrengthMuscleResolver.regions(
                for: "Pectoralis Major"
            ),
            [.chest]
        )
        XCTAssertEqual(
            StrengthMuscleResolver.regions(
                for: "Anterior Deltoid"
            ),
            [.frontDelts]
        )
        XCTAssertEqual(
            StrengthMuscleResolver.regions(
                for: "Triceps Brachii"
            ),
            [.triceps]
        )
    }

    func testLowerBodyRepDBMusclesMapToExpectedRegions() {
        XCTAssertEqual(
            StrengthMuscleResolver.regions(
                for: "Gluteus Maximus"
            ),
            [.glutes]
        )
        XCTAssertEqual(
            StrengthMuscleResolver.regions(
                for: "Gluteus Medius"
            ),
            [.outerHip]
        )
        XCTAssertEqual(
            StrengthMuscleResolver.regions(
                for: "Quadriceps"
            ),
            [.quads]
        )
        XCTAssertEqual(
            StrengthMuscleResolver.regions(
                for: "Hamstrings"
            ),
            [.hamstrings]
        )
        XCTAssertEqual(
            StrengthMuscleResolver.regions(
                for: "Gastrocnemius"
            ),
            [.calves]
        )
    }

    func testPredefinedCustomExerciseMuscleGroupsMapToVisualRegions() {
        for group in ExerciseMuscleGroup.allCases {
            XCTAssertFalse(
                StrengthMuscleResolver
                    .regions(
                        for: group.rawValue
                    )
                    .isEmpty,
                group.rawValue
            )
        }
    }

    func testExerciseNameFallbackCoversRowingMachine() {
        let regions =
            Set(
                StrengthMuscleResolver
                    .fallbackRegions(
                        forExerciseName:
                            "Rowing Machine"
                    )
            )

        XCTAssertTrue(
            regions.contains(.lats)
        )
        XCTAssertTrue(
            regions.contains(.upperBack)
        )
        XCTAssertTrue(
            regions.contains(.biceps)
        )
        XCTAssertTrue(
            regions.contains(.quads)
        )
        XCTAssertTrue(
            regions.contains(.hamstrings)
        )
    }

    func testExerciseNameFallbackCoversCommonStrengthPatterns() {
        XCTAssertEqual(
            Set(
                StrengthMuscleResolver
                    .fallbackRegions(
                        forExerciseName:
                            "Bench Press"
                    )
            ),
            Set([
                .chest,
                .frontDelts,
                .triceps
            ])
        )

        XCTAssertTrue(
            StrengthMuscleResolver
                .fallbackRegions(
                    forExerciseName:
                        "Back Squat"
                )
                .contains(.glutes)
        )
    }

    func testNorwegianExerciseFallbacksUseActualMuscleRegions() {
        let squat = Set(
            StrengthMuscleResolver.fallbackRegions(
                forExerciseName: "Knebøy"
            )
        )
        XCTAssertTrue(squat.contains(.quads))
        XCTAssertTrue(squat.contains(.glutes))

        let bench = Set(
            StrengthMuscleResolver.fallbackRegions(
                forExerciseName: "Benkpress"
            )
        )
        XCTAssertTrue(bench.contains(.chest))
        XCTAssertTrue(bench.contains(.triceps))

        let deadlift = Set(
            StrengthMuscleResolver.fallbackRegions(
                forExerciseName: "Rumensk markløft"
            )
        )
        XCTAssertTrue(deadlift.contains(.hamstrings))
        XCTAssertTrue(deadlift.contains(.glutes))
    }

    func testRepDBBodyPartFallbackAlwaysProducesVisualRegions() {
        let supported = [
            "Chest",
            "Shoulders",
            "Back",
            "Core",
            "Lower Arms",
            "Lower Legs",
            "Upper Arms",
            "Upper Legs",
            "Full Body"
        ]

        for bodyPart in supported {
            XCTAssertFalse(
                StrengthMuscleResolver
                    .fallbackRegions(
                        forBodyPart:
                            bodyPart
                    )
                    .isEmpty,
                bodyPart
            )
        }
    }

    func testMuscleHighlightKeepsPrimaryAndSecondaryRolesDistinct() {
        let profile = StrengthMuscleProfile(
            activations: [
                StrengthMuscleActivation(region: .chest, score: 4),
                StrengthMuscleActivation(region: .triceps, score: 2),
                StrengthMuscleActivation(region: .frontDelts, score: 1)
            ],
            primaryRegions: [.chest],
            secondaryRegions: [.triceps]
        )

        XCTAssertEqual(profile.highlightRole(for: .chest), .primary)
        XCTAssertEqual(profile.highlightRole(for: .triceps), .secondary)
        XCTAssertEqual(profile.highlightRole(for: .frontDelts), .estimated)
        XCTAssertGreaterThan(
            profile.intensity(for: .chest),
            profile.intensity(for: .triceps)
        )
    }

    func testMuscleCannotBeBothPrimaryAndSecondary() {
        let profile = StrengthMuscleProfile(
            activations: [
                StrengthMuscleActivation(region: .quads, score: 6)
            ],
            primaryRegions: [.quads],
            secondaryRegions: [.quads]
        )

        XCTAssertEqual(profile.highlightRole(for: .quads), .primary)
        XCTAssertFalse(profile.secondaryRegions.contains(.quads))
    }

    func testPremiumVectorAtlasCoversWorkoutMusclesOnBothSides() {
        let front = ATHLTHPremiumMuscleAtlas.coveredRegions(isFront: true)
        let back = ATHLTHPremiumMuscleAtlas.coveredRegions(isFront: false)

        XCTAssertTrue(front.isSuperset(of: [
            .chest, .frontDelts, .sideDelts, .biceps,
            .forearms, .abs, .obliques, .serratus,
            .hipFlexors, .quads, .calves, .shins
        ]))
        XCTAssertTrue(back.isSuperset(of: [
            .traps, .rearDelts, .upperBack, .lats,
            .triceps, .lowerBack, .glutes, .hamstrings, .calves
        ]))
    }

    func testPremiumVectorAtlasDoesNotChangeRecoveryActivationSemantics() {
        let profile = StrengthMuscleProfile(
            activations: [
                StrengthMuscleActivation(region: .quads, score: 5),
                StrengthMuscleActivation(region: .glutes, score: 2)
            ],
            primaryRegions: [.quads],
            secondaryRegions: [.glutes]
        )

        XCTAssertEqual(profile.highlightRole(for: .quads), .primary)
        XCTAssertEqual(profile.highlightRole(for: .glutes), .secondary)
        XCTAssertGreaterThan(
            profile.intensity(for: .quads),
            profile.intensity(for: .glutes)
        )
    }

    func testNorwegianExerciseNameLocalization() {
        XCTAssertEqual(
            ATHLTHExerciseNameLocalization
                .norwegianName(for: "Bench Press"),
            "Benkpress"
        )
        XCTAssertEqual(
            ATHLTHExerciseNameLocalization
                .norwegianName(for: "Romanian Deadlift"),
            "Rumensk markløft"
        )
        XCTAssertEqual(
            ATHLTHExerciseNameLocalization
                .norwegianName(
                    for: "Dumbbell Lateral Raise"
                ),
            "Manual sidehev"
        )
    }

    func testExerciseNameSearchTermsIncludeNorwegianAndEnglish() {
        let terms =
            ATHLTHExerciseNameLocalization
                .searchTerms(for: "Bench Press")
                .map { $0.lowercased() }

        XCTAssertTrue(terms.contains("bench press"))
        XCTAssertTrue(terms.contains("benkpress"))
        XCTAssertTrue(terms.contains("benk"))
    }

}
